`timescale 1ns/1ps
// Both polarities: one pulse per press, bounces and short glitches ignored, a held button
// reports once, and a second press after release reports again.
module button_pulse_tb;
    reg clk = 0;
    always #5 clk = ~clk;

    reg raw_lo = 0, raw_hi = 1;         // active-high and active-low buttons (idle level 0 / 1)
    wire p_lo, p_hi;
    button_pulse #(.SETTLE(50), .DEBOUNCE(20)) b_lo (.clk(clk), .raw(raw_lo), .pulse(p_lo));
    button_pulse #(.SETTLE(50), .DEBOUNCE(20)) b_hi (.clk(clk), .raw(raw_hi), .pulse(p_hi));

    integer n_lo = 0, n_hi = 0, errors = 0;
    always @(posedge clk) begin n_lo = n_lo + p_lo; n_hi = n_hi + p_hi; end

    task press(input integer clocks);   // press for `clocks` with a few bounces at each edge
        begin
            raw_lo = 1; raw_hi = 0; repeat (2) @(posedge clk);
            raw_lo = 0; raw_hi = 1; repeat (2) @(posedge clk);
            raw_lo = 1; raw_hi = 0; repeat (clocks) @(posedge clk);
            raw_lo = 0; raw_hi = 1; repeat (2) @(posedge clk);
            raw_lo = 1; raw_hi = 0; repeat (2) @(posedge clk);
            raw_lo = 0; raw_hi = 1; repeat (100) @(posedge clk);
        end
    endtask

    initial begin
        repeat (200) @(posedge clk);
        if (n_lo != 0 || n_hi != 0) errors = errors + 1;
        press(5);                       // too short: the bounces and this are all under DEBOUNCE
        if (n_lo != 0 || n_hi != 0) errors = errors + 1;
        press(300);                     // a real press, held a long time: one pulse
        if (n_lo != 1 || n_hi != 1) errors = errors + 1;
        press(60);                      // another press after release
        if (n_lo != 2 || n_hi != 2) errors = errors + 1;
        if (errors == 0) $display("PASS: one pulse per press for both polarities, bounces ignored");
        else             $display("FAIL: %0d problems (pulses %0d / %0d)", errors, n_lo, n_hi);
        $finish;
    end
endmodule
