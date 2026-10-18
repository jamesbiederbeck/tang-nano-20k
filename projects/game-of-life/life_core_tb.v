`timescale 1ns/1ps
// Runs life_core on a 16x8 torus through several reseeds and compares every displayed
// generation against a plain-loop reference kept in this testbench.
module life_core_tb;
    localparam W = 16, H = 8, XB = 4, YB = 3, MAX_GEN = 40, GENS = 130;

    reg clk = 0;
    always #5 clk = ~clk;

    reg  tick = 0;
    reg  [XB+YB-1:0] raddr = 0;
    wire q, swapped, seed_swap;
    wire [15:0] gen;
    life_core #(.W(W), .H(H), .XB(XB), .YB(YB), .MAX_GEN(MAX_GEN)) dut (
        .clk(clk), .tick(tick), .raddr(raddr), .q(q), .gen(gen),
        .swapped(swapped), .seed_swap(seed_swap));

    reg golden [0:H*W-1];
    reg nextg  [0:H*W-1];
    integer x, y, dx, dy, n, errors, swaps, seeds, i, still;

    // the displayed (front) buffer, read straight out of the RAM copy the display uses
    function front_cell(input integer a);
        front_cell = dut.front ? dut.ramB1.mem[a] : dut.ramA1.mem[a];
    endfunction

    task step_golden;
        begin
            for (y = 0; y < H; y = y + 1)
                for (x = 0; x < W; x = x + 1) begin
                    n = 0;
                    for (dy = -1; dy <= 1; dy = dy + 1)
                        for (dx = -1; dx <= 1; dx = dx + 1)
                            if (dx != 0 || dy != 0)
                                n = n + golden[((y + dy + H) % H) * W + ((x + dx + W) % W)];
                    nextg[y*W + x] = (n == 3) || (golden[y*W + x] && n == 2);
                end
            for (i = 0; i < H*W; i = i + 1) golden[i] = nextg[i];
        end
    endtask

    // the display port: read every cell and compare with the memory contents
    task check_display;
        begin
            for (i = 0; i < H*W; i = i + 1) begin
                // cells are at {cy, cx}, which is cy*16 + cx here
                raddr = {i[XB+YB-1:XB], i[XB-1:0]};
                @(posedge clk); #1;
                @(posedge clk); #1;
                if (q !== golden[i]) errors = errors + 1;
            end
        end
    endtask

    // wait for the engine to finish the generation (S_WAIT), then tick
    always @(posedge clk) if (swapped) begin
        swaps = swaps + 1;
        if (seed_swap) begin
            seeds = seeds + 1;
            for (i = 0; i < H*W; i = i + 1) golden[i] = front_cell(i);
        end else
            step_golden;
        for (i = 0; i < H*W; i = i + 1)
            if (front_cell(i) !== golden[i]) errors = errors + 1;
    end

    initial begin
        errors = 0; swaps = 0; seeds = 0; still = 0;
        repeat (4) @(posedge clk);
        while (swaps < GENS) begin
            wait (dut.state == 2);          // S_WAIT: next generation is ready
            @(posedge clk); #1;
            tick = 1; @(posedge clk); #1; tick = 0;
            repeat (2) @(posedge clk);
            if (swaps % 20 == 0) check_display;
        end
        if (seeds < 2) errors = errors + 1000;   // the reseed path must have run
        if (errors == 0) $display("PASS: %0d swaps, %0d seeds, front buffer matched the reference every generation", swaps, seeds);
        else             $display("FAIL: %0d mismatches (%0d swaps, %0d seeds)", errors, swaps, seeds);
        $finish;
    end

    initial begin #200000000; $display("FAIL: timeout (swaps=%0d)", swaps); $finish; end
endmodule
