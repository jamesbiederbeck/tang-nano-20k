`timescale 1ns/1ps
// Counts the signals over three frames and checks the 1280x720p60 numbers.
module video_timing_tb;
    reg clk = 0;
    wire [10:0] x;
    wire [9:0] y;
    wire de, hsync, vsync, frame_start;
    video_timing dut (.clk(clk), .x(x), .y(y), .de(de), .hsync(hsync), .vsync(vsync), .frame_start(frame_start));
    always #5 clk = ~clk;

    integer clocks = 0, frames = 0, de_clks = 0, hs_clks = 0, vs_clks = 0, errors = 0;
    integer fr_de, fr_hs, fr_vs, fr_clk;

    reg armed = 0;   // the first frame is only partly seen, so start checking at the second frame start
    initial begin fr_de = 0; fr_hs = 0; fr_vs = 0; fr_clk = 0; end

    always @(posedge clk) begin
        #1;
        if (frame_start) begin
          if (armed) begin
            // end of a frame: check the totals
            if (fr_clk !== 1650 * 750)        begin $display("FAIL: %0d clocks per frame", fr_clk); errors = errors + 1; end
            if (fr_de  !== 1280 * 720)        begin $display("FAIL: %0d active pixels", fr_de);    errors = errors + 1; end
            if (fr_hs  !== 40 * 750)          begin $display("FAIL: hsync high %0d clocks", fr_hs); errors = errors + 1; end
            if (fr_vs  !== 5 * 1650)          begin $display("FAIL: vsync high %0d clocks", fr_vs); errors = errors + 1; end
            frames = frames + 1;
          end
          armed = 1;
          fr_de = 0; fr_hs = 0; fr_vs = 0; fr_clk = 0;
        end
        fr_clk = fr_clk + 1;
        fr_de  = fr_de + de;
        fr_hs  = fr_hs + hsync;
        fr_vs  = fr_vs + vsync;
        if (de && (hsync || vsync)) begin $display("FAIL: sync during active video"); errors = errors + 1; end
    end

    initial begin
        #(10 * 1650 * 750 * 4 + 100);
        if (frames < 3) begin $display("FAIL: only %0d full frames seen", frames); errors = errors + 1; end
        if (errors == 0) $display("PASS: %0d frames of 1650x750, 1280x720 active", frames);
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
