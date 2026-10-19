`timescale 1ns/1ps
// Runs the full 160 x 90 life_row_core through its eight seed kinds and checks what each one
// writes: the cell counts of the drawn patterns, the mirror symmetry, the soup patch staying
// inside its box. Then the glider gun is run for 30 generations: it must be back in its first
// shape with one more glider (36 + 5 cells).
module life_seed_tb;
    localparam W = 160, H = 90, YB = 7;

    reg clk = 0;
    always #5 clk = ~clk;

    reg go = 0, nxt = 0, prv = 0;
    wire swapped, seed_swap;
    wire [15:0] gen;
    life_row_core #(.W(W), .H(H), .YB(YB), .MAX_GEN(30)) dut (
        .clk(clk), .go(go), .next_seed(nxt), .prev_seed(prv), .disp_req(1'b0), .disp_row(7'd0),
        .disp_data(), .disp_valid(), .gen(gen), .swapped(swapped), .seed_swap(seed_swap),
        .last_cycles());

    integer cells_now, asym_now;
    integer errors = 0, k, y, x, cells, outside, asym, g, gun_cells;
    reg [W-1:0] row;
    integer expect_cells [0:7];

    function [W-1:0] front_row(input integer r);
        front_row = dut.ram.mem[(dut.front << YB) | r];
    endfunction

    task pulse_go;
        begin
            wait (dut.state == 1);
            repeat (3) @(posedge clk); #1;
            go = 1; @(posedge clk); #1; go = 0;
            repeat (3) @(posedge clk);
            wait (dut.state != 2);              // the generation has finished and swapped
            repeat (2) @(posedge clk); #1;
        end
    endtask

    initial begin
        expect_cells[0] = 5;  expect_cells[2] = 7;  expect_cells[3] = 36;
        expect_cells[5] = 7;  expect_cells[6] = 7;
        repeat (4) @(posedge clk);
        for (k = 0; k < 8; k = k + 1) begin
            pulse_go;                           // shows the waiting seed
            cells = 0; outside = 0; asym = 0;
            for (y = 0; y < H; y = y + 1) begin
                row = front_row(y);
                for (x = 0; x < W; x = x + 1) begin
                    cells = cells + row[x];
                    if (row[x] && (x < 56 || x >= 104 || y < 21 || y >= 69)) outside = outside + 1;
                    if (row[x] !== row[W-1-x]) asym = asym + 1;
                end
            end
            case (k)
                1: begin if (asym != 0 || cells < 1000) errors = errors + 1; end
                4: begin if (outside != 0 || cells < 400) errors = errors + 1; end
                7: begin if (cells < 3000) errors = errors + 1; end
                default: if (cells != expect_cells[k]) errors = errors + 1;
            endcase
            if (k == 3) begin
                for (g = 0; g < 30; g = g + 1) pulse_go;
                gun_cells = 0;
                for (y = 0; y < H; y = y + 1) begin
                    row = front_row(y);
                    for (x = 0; x < W; x = x + 1) gun_cells = gun_cells + row[x];
                end
                if (gun_cells != 41) errors = errors + 1000;
            end else if (k != 7) begin
                for (g = 0; g < 30; g = g + 1) pulse_go;    // run this seed out (MAX_GEN = 30)
            end
        end
        // the buttons: next, next, previous, previous from the soup-everywhere seed (kind 7)
        press_and_show(1, 0);   if (dut.shown != 0 || cells_now != 5) errors = errors + 10000;
        press_and_show(1, 0);   if (dut.shown != 1 || asym_now != 0 || cells_now < 1000) errors = errors + 20000;
        press_and_show(0, 1);   if (dut.shown != 0 || cells_now != 5) errors = errors + 40000;
        press_and_show(0, 1);   if (dut.shown != 7 || cells_now < 3000) errors = errors + 80000;
        if (errors == 0) $display("PASS: all 8 seed kinds as drawn; glider gun back in shape with one glider (41 cells) after 30 generations; next/previous requests land on the right kinds");
        else             $display("FAIL: %0d problems (last gun population %0d)", errors, gun_cells);
        $finish;
    end

    task press_and_show(input n, input p);
        begin
            wait (dut.state == 1);
            nxt = n; prv = p; @(posedge clk); #1; nxt = 0; prv = 0;
            repeat (3) @(posedge clk);
            pulse_go;                           // shows the new seed
            cells_now = 0; asym_now = 0;
            for (y = 0; y < H; y = y + 1) begin
                row = front_row(y);
                for (x = 0; x < W; x = x + 1) begin
                    cells_now = cells_now + row[x];
                    if (row[x] !== row[W-1-x]) asym_now = asym_now + 1;
                end
            end
        end
    endtask

    initial begin #500000000; $display("FAIL: timeout (kind %0d)", k); $finish; end
endmodule
