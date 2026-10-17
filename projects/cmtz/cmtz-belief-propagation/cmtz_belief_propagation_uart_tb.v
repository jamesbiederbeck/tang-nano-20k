`timescale 1ns/1ps
// Whole-design test for cmtz_belief_propagation_uart: bit-bangs the UART protocol, sends every
// vector, and compares each reply byte with the compiler's Python reference
// (49 vectors). Also checks the out-of-range reply and the
// resync timeout. Uses 8 clocks per bit so it runs fast. Prints PASS or FAIL.
module cmtz_belief_propagation_uart_tb;
    localparam CPB = 8, TO = 2000;
    localparam NI = 2, NO = 1, NV = 49;
    reg clk = 1'b0;
    reg rx  = 1'b1;
    wire tx;
    wire [5:0] leds;
    cmtz_belief_propagation_uart #(.CLKS_PER_BIT(CPB), .TIMEOUT_CLKS(TO)) dut (.clk(clk), .rx(rx), .tx(tx), .leds(leds));
    always #5 clk = ~clk;

    reg [7:0] vin  [0:NV*NI-1];
    reg [7:0] vout [0:NV*NO-1];
    integer errors = 0;
    integer checked = 0;

    task send_byte;
        input [7:0] v;
        integer i;
        begin
            rx = 1'b0; repeat (CPB) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = v[i]; repeat (CPB) @(posedge clk);
            end
            rx = 1'b1; repeat (CPB) @(posedge clk);
        end
    endtask

    task recv_byte;
        output [7:0] v;
        integer i;
        begin
            @(negedge tx);                          // start bit
            repeat (CPB / 2) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                repeat (CPB) @(posedge clk); v[i] = tx;
            end
            repeat (CPB) @(posedge clk);            // stop bit
        end
    endtask

    task check_vec;
        input integer idx;
        integer j;
        reg [7:0] got;
        begin
            for (j = 0; j < NI; j = j + 1) send_byte(vin[idx * NI + j]);
            for (j = 0; j < NO; j = j + 1) begin
                recv_byte(got);
                if (got !== vout[idx * NO + j]) begin
                    $display("FAIL: vector %0d reply byte %0d = %0d, expected %0d",
                             idx, j, got, vout[idx * NO + j]);
                    errors = errors + 1;
                end
            end
            checked = checked + 1;
        end
    endtask

    task check_error;
        integer j;
        reg [7:0] got;
        begin
            send_byte(7);                          // out of range
            for (j = 1; j < NI; j = j + 1) send_byte(0);
            for (j = 0; j < NO; j = j + 1) begin
                recv_byte(got);
                if (got !== 8'hFF) begin
                    $display("FAIL: error reply byte %0d = %0d, expected 255", j, got);
                    errors = errors + 1;
                end
            end
            checked = checked + 1;
        end
    endtask

    integer v;
    initial begin
        vin[0] = 8'd0;
        vin[1] = 8'd0;
        vout[0] = 8'd0;
        vin[2] = 8'd0;
        vin[3] = 8'd1;
        vout[1] = 8'd0;
        vin[4] = 8'd0;
        vin[5] = 8'd2;
        vout[2] = 8'd0;
        vin[6] = 8'd0;
        vin[7] = 8'd3;
        vout[3] = 8'd0;
        vin[8] = 8'd0;
        vin[9] = 8'd4;
        vout[4] = 8'd0;
        vin[10] = 8'd0;
        vin[11] = 8'd5;
        vout[5] = 8'd0;
        vin[12] = 8'd0;
        vin[13] = 8'd6;
        vout[6] = 8'd0;
        vin[14] = 8'd1;
        vin[15] = 8'd0;
        vout[7] = 8'd0;
        vin[16] = 8'd1;
        vin[17] = 8'd1;
        vout[8] = 8'd6;
        vin[18] = 8'd1;
        vin[19] = 8'd2;
        vout[9] = 8'd5;
        vin[20] = 8'd1;
        vin[21] = 8'd3;
        vout[10] = 8'd4;
        vin[22] = 8'd1;
        vin[23] = 8'd4;
        vout[11] = 8'd3;
        vin[24] = 8'd1;
        vin[25] = 8'd5;
        vout[12] = 8'd2;
        vin[26] = 8'd1;
        vin[27] = 8'd6;
        vout[13] = 8'd1;
        vin[28] = 8'd2;
        vin[29] = 8'd0;
        vout[14] = 8'd0;
        vin[30] = 8'd2;
        vin[31] = 8'd1;
        vout[15] = 8'd5;
        vin[32] = 8'd2;
        vin[33] = 8'd2;
        vout[16] = 8'd3;
        vin[34] = 8'd2;
        vin[35] = 8'd3;
        vout[17] = 8'd1;
        vin[36] = 8'd2;
        vin[37] = 8'd4;
        vout[18] = 8'd6;
        vin[38] = 8'd2;
        vin[39] = 8'd5;
        vout[19] = 8'd4;
        vin[40] = 8'd2;
        vin[41] = 8'd6;
        vout[20] = 8'd2;
        vin[42] = 8'd3;
        vin[43] = 8'd0;
        vout[21] = 8'd0;
        vin[44] = 8'd3;
        vin[45] = 8'd1;
        vout[22] = 8'd4;
        vin[46] = 8'd3;
        vin[47] = 8'd2;
        vout[23] = 8'd1;
        vin[48] = 8'd3;
        vin[49] = 8'd3;
        vout[24] = 8'd5;
        vin[50] = 8'd3;
        vin[51] = 8'd4;
        vout[25] = 8'd2;
        vin[52] = 8'd3;
        vin[53] = 8'd5;
        vout[26] = 8'd6;
        vin[54] = 8'd3;
        vin[55] = 8'd6;
        vout[27] = 8'd3;
        vin[56] = 8'd4;
        vin[57] = 8'd0;
        vout[28] = 8'd0;
        vin[58] = 8'd4;
        vin[59] = 8'd1;
        vout[29] = 8'd3;
        vin[60] = 8'd4;
        vin[61] = 8'd2;
        vout[30] = 8'd6;
        vin[62] = 8'd4;
        vin[63] = 8'd3;
        vout[31] = 8'd2;
        vin[64] = 8'd4;
        vin[65] = 8'd4;
        vout[32] = 8'd5;
        vin[66] = 8'd4;
        vin[67] = 8'd5;
        vout[33] = 8'd1;
        vin[68] = 8'd4;
        vin[69] = 8'd6;
        vout[34] = 8'd4;
        vin[70] = 8'd5;
        vin[71] = 8'd0;
        vout[35] = 8'd0;
        vin[72] = 8'd5;
        vin[73] = 8'd1;
        vout[36] = 8'd2;
        vin[74] = 8'd5;
        vin[75] = 8'd2;
        vout[37] = 8'd4;
        vin[76] = 8'd5;
        vin[77] = 8'd3;
        vout[38] = 8'd6;
        vin[78] = 8'd5;
        vin[79] = 8'd4;
        vout[39] = 8'd1;
        vin[80] = 8'd5;
        vin[81] = 8'd5;
        vout[40] = 8'd3;
        vin[82] = 8'd5;
        vin[83] = 8'd6;
        vout[41] = 8'd5;
        vin[84] = 8'd6;
        vin[85] = 8'd0;
        vout[42] = 8'd0;
        vin[86] = 8'd6;
        vin[87] = 8'd1;
        vout[43] = 8'd1;
        vin[88] = 8'd6;
        vin[89] = 8'd2;
        vout[44] = 8'd2;
        vin[90] = 8'd6;
        vin[91] = 8'd3;
        vout[45] = 8'd3;
        vin[92] = 8'd6;
        vin[93] = 8'd4;
        vout[46] = 8'd4;
        vin[94] = 8'd6;
        vin[95] = 8'd5;
        vout[47] = 8'd5;
        vin[96] = 8'd6;
        vin[97] = 8'd6;
        vout[48] = 8'd6;
        repeat (20) @(posedge clk);
        for (v = 0; v < NV; v = v + 1) check_vec(v);
        check_error;
        check_vec(0);                               // still works after an error
        // resync: a lone first byte, then silence longer than the timeout
        send_byte(vin[0]);
        repeat (TO + 100) @(posedge clk);
        check_vec(0);
        check_vec(NV - 1);
        if (errors == 0) $display("PASS");
        else $display("FAIL: %0d errors in %0d checks", errors, checked);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("FAIL: timeout after %0d checks", checked);
        $finish;
    end
endmodule
