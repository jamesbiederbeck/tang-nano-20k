`timescale 1ns/1ps
// Runs life_row_core on a 16x8 torus through several reseeds and compares every displayed
// generation against a plain-loop reference kept in this testbench, then reads rows back
// through the display port.
module life_row_core_tb;
    localparam W = 16, H = 8, YB = 3, MAX_GEN = 40, GENS = 130;

    reg clk = 0;
    always #5 clk = ~clk;

    reg go = 0, disp_req = 0;
    reg [YB-1:0] disp_row = 0;
    wire [W-1:0] disp_data;
    wire disp_valid, swapped, seed_swap;
    wire [15:0] gen, last_cycles;
    life_row_core #(.W(W), .H(H), .YB(YB), .MAX_GEN(MAX_GEN)) dut (
        .clk(clk), .go(go), .disp_req(disp_req), .disp_row(disp_row),
        .disp_data(disp_data), .disp_valid(disp_valid),
        .gen(gen), .swapped(swapped), .seed_swap(seed_swap), .last_cycles(last_cycles));

    reg golden [0:H*W-1];
    reg nextg  [0:H*W-1];
    integer x, y, dx, dy, n, errors, swaps, seeds, i, r, cyc_min, cyc_max;

    function front_cell(input integer a);   // a = row * W + column
        reg [W-1:0] row;
        begin
            row = dut.ram.mem[(dut.front << YB) | (a / W)];
            front_cell = row[a % W];
        end
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

    // the display port: request a row, then compare the data in the cycle valid is high
    reg [W-1:0] got;
    task read_row(input integer row);
        integer c;
        begin
            @(negedge clk); disp_row = row; disp_req = 1;
            @(negedge clk); disp_req = 0;
            @(negedge clk);                     // two clocks after the request edge
            if (!disp_valid) errors = errors + 1;
            got = disp_data;
            for (c = 0; c < W; c = c + 1)
                if (got[c] !== golden[row*W + c]) errors = errors + 1;
        end
    endtask

    always @(posedge clk) if (swapped) begin
        swaps = swaps + 1;
        if (seed_swap) begin
            seeds = seeds + 1;
            for (i = 0; i < H*W; i = i + 1) golden[i] = front_cell(i);
        end else begin
            step_golden;
            if (last_cycles < cyc_min) cyc_min = last_cycles;
            if (last_cycles > cyc_max) cyc_max = last_cycles;
        end
        for (i = 0; i < H*W; i = i + 1)
            if (front_cell(i) !== golden[i]) errors = errors + 1;
    end

    initial begin
        errors = 0; swaps = 0; seeds = 0; cyc_min = 1000; cyc_max = 0;
        repeat (4) @(posedge clk);
        while (swaps < GENS) begin
            wait (dut.state == 1);          // S_READY
            repeat (3) @(posedge clk); #1;
            go = 1; @(posedge clk); #1; go = 0;
            wait (dut.state == 1);
            repeat (3) @(posedge clk); #1;
            if (swaps % 10 == 0) for (r = 0; r < H; r = r + 1) read_row(r);
        end
        if (seeds < 2) errors = errors + 1000;   // the reseed path must have run
        if (cyc_max != H + 6 || cyc_min != H + 6) errors = errors + 100000;
        if (errors == 0) $display("PASS: %0d swaps, %0d seeds, front buffer matched the reference every generation; %0d clocks per generation for H=%0d", swaps, seeds, cyc_max, H);
        else             $display("FAIL: %0d mismatches (%0d swaps, %0d seeds, clocks per generation %0d..%0d)", errors, swaps, seeds, cyc_min, cyc_max);
        $finish;
    end

    initial begin #200000000; $display("FAIL: timeout (swaps=%0d)", swaps); $finish; end
endmodule
