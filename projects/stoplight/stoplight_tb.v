`timescale 1ns/1ps
// 10 Hz "clock" so one second is 10 clocks. Checks that the lamps step through
// the expected patterns for the expected time, and that the two directions are
// never green or yellow together.
module stoplight_tb;
    reg clk = 0;
    wire [5:0] leds;
    stoplight #(.CLK_HZ(10)) dut (.clk(clk), .leds(leds));
    always #5 clk = ~clk;

    wire [5:0] lit = ~leds;     // 1 = lit: {EW g, EW y, EW r, NS g, NS y, NS r}

    reg [5:0] exp_pat [0:5];
    integer   exp_len [0:5];
    integer   pos, cnt, errors, changes;
    reg [5:0] last;
    reg       synced;

    initial begin
        exp_pat[0] = 6'b001_100; exp_len[0] = 50;  // NS green  5 s
        exp_pat[1] = 6'b001_010; exp_len[1] = 20;  // NS yellow 2 s
        exp_pat[2] = 6'b001_001; exp_len[2] = 10;  // all red   1 s
        exp_pat[3] = 6'b100_001; exp_len[3] = 50;  // EW green  5 s
        exp_pat[4] = 6'b010_001; exp_len[4] = 20;  // EW yellow 2 s
        exp_pat[5] = 6'b001_001; exp_len[5] = 10;  // all red   1 s
        errors = 0; changes = 0; synced = 0; pos = 0; cnt = 0; last = 6'b001_001;
    end

    always @(posedge clk) begin
        #1;
        // safety: never both directions non-red
        if ((lit[2] | lit[1]) & (lit[5] | lit[4])) begin
            $display("FAIL: conflicting lamps at %0t, leds=%b", $time, leds);
            errors = errors + 1;
        end

        if (!synced) begin
            // power-up is all red; start checking when NS first goes green
            if (lit === exp_pat[0]) begin synced = 1; pos = 0; cnt = 1; last = lit; end
        end else if (lit === last) begin
            cnt = cnt + 1;
        end else begin
            if (cnt != exp_len[pos]) begin
                $display("FAIL: pattern %b lasted %0d clocks, expected %0d", last, cnt, exp_len[pos]);
                errors = errors + 1;
            end
            pos = (pos + 1) % 6;
            if (lit !== exp_pat[pos]) begin
                $display("FAIL: got %b, expected %b", lit, exp_pat[pos]);
                errors = errors + 1;
            end
            cnt = 1; last = lit; changes = changes + 1;
        end
    end

    initial begin
        #(4 * 160 * 10);        // four full cycles: 16 s = 160 clocks, 10 ns per clock
        if (changes < 12) begin
            $display("FAIL: only %0d pattern changes seen", changes);
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS: %0d pattern changes checked", changes);
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
