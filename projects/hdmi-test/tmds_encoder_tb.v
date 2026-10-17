`timescale 1ns/1ps
// Pushes every byte value (plus a long random run) through the encoder, decodes each
// symbol back with the DVI decoding rules, and checks the byte matches, the running
// disparity stays bounded, and the four control symbols come out as specified.
module tmds_encoder_tb;
    reg clk = 0;
    reg [7:0] d = 0;
    reg c0 = 0, c1 = 0, de = 1;
    wire [9:0] q;
    tmds_encoder dut (.clk(clk), .d(d), .c0(c0), .c1(c1), .de(de), .q(q));
    always #5 clk = ~clk;

    function [7:0] decode(input [9:0] s);
        reg [7:0] x;
        integer i;
        begin
            x = s[9] ? ~s[7:0] : s[7:0];
            decode[0] = x[0];
            for (i = 1; i < 8; i = i + 1)
                decode[i] = s[8] ? (x[i] ^ x[i-1]) : ~(x[i] ^ x[i-1]);
        end
    endfunction

    function integer ones(input [9:0] s);
        integer i;
        begin ones = 0; for (i = 0; i < 10; i = i + 1) ones = ones + s[i]; end
    endfunction

    integer errors = 0, n, disp = 0, maxdisp = 0, k;
    reg [7:0] sent [0:2047];

    initial begin
        // 256 values in order, then 1500 pseudo-random ones
        for (n = 0; n < 256; n = n + 1) sent[n] = n;
        for (n = 256; n < 1756; n = n + 1) sent[n] = $random;

        // feed byte n at edge n; its symbol appears after edge n+1
        for (n = 0; n < 1756; n = n + 1) begin
            d = sent[n];
            @(posedge clk); #1;
            if (n > 0) begin
                // q now holds the symbol for sent[n-1] (registered one clock after its input edge)
            end
            // symbol for the byte presented at the previous edge is available now
        end
    end

    // Check at each clock: q reflects the byte that was on d one edge earlier.
    reg [7:0] prev_d = 0;
    integer seen = 0;
    always @(posedge clk) begin
        #2;
        if (seen > 1 && seen <= 1757) begin
            if (decode(q) !== prev_d) begin
                $display("FAIL: sent %02x, symbol %b decodes to %02x", prev_d, q, decode(q));
                errors = errors + 1;
            end
            disp = disp + ones(q) - (10 - ones(q));
            if (disp > maxdisp) maxdisp = disp;
            if (-disp > maxdisp) maxdisp = -disp;
        end
        prev_d <= d;
        seen = seen + 1;
    end

    initial begin
        #(10 * 1900);
        if (maxdisp > 10) begin
            $display("FAIL: running disparity reached %0d", maxdisp);
            errors = errors + 1;
        end
        // control symbols during blanking
        de = 0;
        c1 = 0; c0 = 0; @(posedge clk); @(posedge clk); #1;
        if (q !== 10'b1101010100) begin $display("FAIL: ctrl 00 gave %b", q); errors = errors + 1; end
        c1 = 0; c0 = 1; @(posedge clk); #1;
        if (q !== 10'b0010101011) begin $display("FAIL: ctrl 01 gave %b", q); errors = errors + 1; end
        c1 = 1; c0 = 0; @(posedge clk); #1;
        if (q !== 10'b0101010100) begin $display("FAIL: ctrl 10 gave %b", q); errors = errors + 1; end
        c1 = 1; c0 = 1; @(posedge clk); #1;
        if (q !== 10'b1010101011) begin $display("FAIL: ctrl 11 gave %b", q); errors = errors + 1; end
        if (errors == 0) $display("PASS: 1756 bytes decoded, max disparity %0d, control symbols ok", maxdisp);
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
