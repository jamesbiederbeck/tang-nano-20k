`timescale 1ns/1ps
// Whole-design test for cmtz_interrupt_handler_uart: bit-bangs the UART protocol, sends every
// vector, and compares each reply byte with the compiler's Python reference
// (66 vectors). Also checks the out-of-range reply and the
// resync timeout. Uses 8 clocks per bit so it runs fast. Prints PASS or FAIL.
module cmtz_interrupt_handler_uart_tb;
    localparam CPB = 8, TO = 2000;
    localparam NI = 3, NO = 2, NV = 66;
    reg clk = 1'b0;
    reg rx  = 1'b1;
    wire tx;
    wire [5:0] leds;
    cmtz_interrupt_handler_uart #(.CLKS_PER_BIT(CPB), .TIMEOUT_CLKS(TO)) dut (.clk(clk), .rx(rx), .tx(tx), .leds(leds));
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
            send_byte(17);                          // out of range
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
        vin[2] = 8'd0;
        vout[0] = 8'd0;
        vout[1] = 8'd0;
        vin[3] = 8'd16;
        vin[4] = 8'd16;
        vin[5] = 8'd16;
        vout[2] = 8'd15;
        vout[3] = 8'd7;
        vin[6] = 8'd12;
        vin[7] = 8'd13;
        vin[8] = 8'd1;
        vout[4] = 8'd14;
        vout[5] = 8'd1;
        vin[9] = 8'd8;
        vin[10] = 8'd16;
        vin[11] = 8'd15;
        vout[6] = 8'd14;
        vout[7] = 8'd12;
        vin[12] = 8'd12;
        vin[13] = 8'd9;
        vin[14] = 8'd15;
        vout[8] = 8'd7;
        vout[9] = 8'd1;
        vin[15] = 8'd11;
        vin[16] = 8'd6;
        vin[17] = 8'd16;
        vout[10] = 8'd5;
        vout[11] = 8'd8;
        vin[18] = 8'd4;
        vin[19] = 8'd9;
        vin[20] = 8'd4;
        vout[12] = 8'd13;
        vout[13] = 8'd6;
        vin[21] = 8'd3;
        vin[22] = 8'd8;
        vin[23] = 8'd4;
        vout[14] = 8'd12;
        vout[15] = 8'd13;
        vin[24] = 8'd9;
        vin[25] = 8'd3;
        vin[26] = 8'd2;
        vout[16] = 8'd5;
        vout[17] = 8'd5;
        vin[27] = 8'd10;
        vin[28] = 8'd15;
        vin[29] = 8'd3;
        vout[18] = 8'd1;
        vout[19] = 8'd15;
        vin[30] = 8'd11;
        vin[31] = 8'd13;
        vin[32] = 8'd10;
        vout[20] = 8'd6;
        vout[21] = 8'd8;
        vin[33] = 8'd6;
        vin[34] = 8'd15;
        vin[35] = 8'd14;
        vout[22] = 8'd12;
        vout[23] = 8'd9;
        vin[36] = 8'd16;
        vin[37] = 8'd8;
        vin[38] = 8'd1;
        vout[24] = 8'd9;
        vout[25] = 8'd7;
        vin[39] = 8'd0;
        vin[40] = 8'd2;
        vin[41] = 8'd12;
        vout[26] = 8'd14;
        vout[27] = 8'd0;
        vin[42] = 8'd0;
        vin[43] = 8'd15;
        vin[44] = 8'd10;
        vout[28] = 8'd8;
        vout[29] = 8'd0;
        vin[45] = 8'd7;
        vin[46] = 8'd10;
        vin[47] = 8'd2;
        vout[30] = 8'd12;
        vout[31] = 8'd2;
        vin[48] = 8'd6;
        vin[49] = 8'd7;
        vin[50] = 8'd7;
        vout[32] = 8'd14;
        vout[33] = 8'd9;
        vin[51] = 8'd4;
        vin[52] = 8'd14;
        vin[53] = 8'd2;
        vout[34] = 8'd16;
        vout[35] = 8'd6;
        vin[54] = 8'd2;
        vin[55] = 8'd10;
        vin[56] = 8'd16;
        vout[36] = 8'd9;
        vout[37] = 8'd3;
        vin[57] = 8'd15;
        vin[58] = 8'd3;
        vin[59] = 8'd9;
        vout[38] = 8'd12;
        vout[39] = 8'd14;
        vin[60] = 8'd9;
        vin[61] = 8'd3;
        vin[62] = 8'd10;
        vout[40] = 8'd13;
        vout[41] = 8'd5;
        vin[63] = 8'd6;
        vin[64] = 8'd9;
        vin[65] = 8'd14;
        vout[42] = 8'd6;
        vout[43] = 8'd9;
        vin[66] = 8'd2;
        vin[67] = 8'd12;
        vin[68] = 8'd10;
        vout[44] = 8'd5;
        vout[45] = 8'd3;
        vin[69] = 8'd7;
        vin[70] = 8'd9;
        vin[71] = 8'd5;
        vout[46] = 8'd14;
        vout[47] = 8'd2;
        vin[72] = 8'd6;
        vin[73] = 8'd5;
        vin[74] = 8'd1;
        vout[48] = 8'd6;
        vout[49] = 8'd9;
        vin[75] = 8'd8;
        vin[76] = 8'd15;
        vin[77] = 8'd2;
        vout[50] = 8'd0;
        vout[51] = 8'd12;
        vin[78] = 8'd2;
        vin[79] = 8'd4;
        vin[80] = 8'd4;
        vout[52] = 8'd8;
        vout[53] = 8'd3;
        vin[81] = 8'd1;
        vin[82] = 8'd2;
        vin[83] = 8'd12;
        vout[54] = 8'd14;
        vout[55] = 8'd10;
        vin[84] = 8'd16;
        vin[85] = 8'd8;
        vin[86] = 8'd16;
        vout[56] = 8'd7;
        vout[57] = 8'd7;
        vin[87] = 8'd7;
        vin[88] = 8'd6;
        vin[89] = 8'd13;
        vout[58] = 8'd2;
        vout[59] = 8'd2;
        vin[90] = 8'd8;
        vin[91] = 8'd14;
        vin[92] = 8'd15;
        vout[60] = 8'd12;
        vout[61] = 8'd12;
        vin[93] = 8'd11;
        vin[94] = 8'd2;
        vin[95] = 8'd10;
        vout[62] = 8'd12;
        vout[63] = 8'd8;
        vin[96] = 8'd3;
        vin[97] = 8'd15;
        vin[98] = 8'd10;
        vout[64] = 8'd8;
        vout[65] = 8'd13;
        vin[99] = 8'd6;
        vin[100] = 8'd7;
        vin[101] = 8'd0;
        vout[66] = 8'd7;
        vout[67] = 8'd9;
        vin[102] = 8'd8;
        vin[103] = 8'd3;
        vin[104] = 8'd7;
        vout[68] = 8'd10;
        vout[69] = 8'd12;
        vin[105] = 8'd11;
        vin[106] = 8'd5;
        vin[107] = 8'd10;
        vout[70] = 8'd15;
        vout[71] = 8'd8;
        vin[108] = 8'd13;
        vin[109] = 8'd1;
        vin[110] = 8'd3;
        vout[72] = 8'd4;
        vout[73] = 8'd11;
        vin[111] = 8'd4;
        vin[112] = 8'd7;
        vin[113] = 8'd1;
        vout[74] = 8'd8;
        vout[75] = 8'd6;
        vin[114] = 8'd2;
        vin[115] = 8'd0;
        vin[116] = 8'd3;
        vout[76] = 8'd3;
        vout[77] = 8'd3;
        vin[117] = 8'd6;
        vin[118] = 8'd3;
        vin[119] = 8'd12;
        vout[78] = 8'd15;
        vout[79] = 8'd9;
        vin[120] = 8'd2;
        vin[121] = 8'd11;
        vin[122] = 8'd3;
        vout[80] = 8'd14;
        vout[81] = 8'd3;
        vin[123] = 8'd1;
        vin[124] = 8'd0;
        vin[125] = 8'd6;
        vout[82] = 8'd6;
        vout[83] = 8'd10;
        vin[126] = 8'd5;
        vin[127] = 8'd3;
        vin[128] = 8'd15;
        vout[84] = 8'd1;
        vout[85] = 8'd16;
        vin[129] = 8'd6;
        vin[130] = 8'd1;
        vin[131] = 8'd0;
        vout[86] = 8'd1;
        vout[87] = 8'd9;
        vin[132] = 8'd13;
        vin[133] = 8'd3;
        vin[134] = 8'd8;
        vout[88] = 8'd11;
        vout[89] = 8'd11;
        vin[135] = 8'd2;
        vin[136] = 8'd7;
        vin[137] = 8'd2;
        vout[90] = 8'd9;
        vout[91] = 8'd3;
        vin[138] = 8'd9;
        vin[139] = 8'd11;
        vin[140] = 8'd13;
        vout[92] = 8'd7;
        vout[93] = 8'd5;
        vin[141] = 8'd5;
        vin[142] = 8'd1;
        vin[143] = 8'd16;
        vout[94] = 8'd0;
        vout[95] = 8'd16;
        vin[144] = 8'd14;
        vin[145] = 8'd1;
        vin[146] = 8'd3;
        vout[96] = 8'd4;
        vout[97] = 8'd4;
        vin[147] = 8'd12;
        vin[148] = 8'd6;
        vin[149] = 8'd8;
        vout[98] = 8'd14;
        vout[99] = 8'd1;
        vin[150] = 8'd11;
        vin[151] = 8'd15;
        vin[152] = 8'd5;
        vout[100] = 8'd3;
        vout[101] = 8'd8;
        vin[153] = 8'd6;
        vin[154] = 8'd1;
        vin[155] = 8'd5;
        vout[102] = 8'd6;
        vout[103] = 8'd9;
        vin[156] = 8'd5;
        vin[157] = 8'd10;
        vin[158] = 8'd16;
        vout[104] = 8'd9;
        vout[105] = 8'd16;
        vin[159] = 8'd8;
        vin[160] = 8'd3;
        vin[161] = 8'd14;
        vout[106] = 8'd0;
        vout[107] = 8'd12;
        vin[162] = 8'd5;
        vin[163] = 8'd0;
        vin[164] = 8'd15;
        vout[108] = 8'd15;
        vout[109] = 8'd16;
        vin[165] = 8'd13;
        vin[166] = 8'd16;
        vin[167] = 8'd9;
        vout[110] = 8'd8;
        vout[111] = 8'd11;
        vin[168] = 8'd11;
        vin[169] = 8'd12;
        vin[170] = 8'd8;
        vout[112] = 8'd3;
        vout[113] = 8'd8;
        vin[171] = 8'd4;
        vin[172] = 8'd0;
        vin[173] = 8'd14;
        vout[114] = 8'd14;
        vout[115] = 8'd6;
        vin[174] = 8'd2;
        vin[175] = 8'd10;
        vin[176] = 8'd1;
        vout[116] = 8'd11;
        vout[117] = 8'd3;
        vin[177] = 8'd8;
        vin[178] = 8'd4;
        vin[179] = 8'd7;
        vout[118] = 8'd11;
        vout[119] = 8'd12;
        vin[180] = 8'd15;
        vin[181] = 8'd11;
        vin[182] = 8'd9;
        vout[120] = 8'd3;
        vout[121] = 8'd14;
        vin[183] = 8'd11;
        vin[184] = 8'd4;
        vin[185] = 8'd9;
        vout[122] = 8'd13;
        vout[123] = 8'd8;
        vin[186] = 8'd12;
        vin[187] = 8'd13;
        vin[188] = 8'd2;
        vout[124] = 8'd15;
        vout[125] = 8'd1;
        vin[189] = 8'd0;
        vin[190] = 8'd6;
        vin[191] = 8'd10;
        vout[126] = 8'd16;
        vout[127] = 8'd0;
        vin[192] = 8'd5;
        vin[193] = 8'd7;
        vin[194] = 8'd7;
        vout[128] = 8'd14;
        vout[129] = 8'd16;
        vin[195] = 8'd14;
        vin[196] = 8'd12;
        vin[197] = 8'd13;
        vout[130] = 8'd8;
        vout[131] = 8'd4;
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
