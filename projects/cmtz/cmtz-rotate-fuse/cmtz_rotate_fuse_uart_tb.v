`timescale 1ns/1ps
// Whole-design test for cmtz_rotate_fuse_uart: bit-bangs the UART protocol, sends every
// vector, and compares each reply byte with the compiler's Python reference
// (17 vectors). Also checks the out-of-range reply and the
// resync timeout. Uses 8 clocks per bit so it runs fast. Prints PASS or FAIL.
module cmtz_rotate_fuse_uart_tb;
    localparam CPB = 8, TO = 2000;
    localparam NI = 1, NO = 1, NV = 17;
    reg clk = 1'b0;
    reg rx  = 1'b1;
    wire tx;
    wire [5:0] leds;
    cmtz_rotate_fuse_uart #(.CLKS_PER_BIT(CPB), .TIMEOUT_CLKS(TO)) dut (.clk(clk), .rx(rx), .tx(tx), .leds(leds));
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
        vout[0] = 8'd0;
        vin[1] = 8'd1;
        vout[1] = 8'd16;
        vin[2] = 8'd2;
        vout[2] = 8'd15;
        vin[3] = 8'd3;
        vout[3] = 8'd14;
        vin[4] = 8'd4;
        vout[4] = 8'd13;
        vin[5] = 8'd5;
        vout[5] = 8'd12;
        vin[6] = 8'd6;
        vout[6] = 8'd11;
        vin[7] = 8'd7;
        vout[7] = 8'd10;
        vin[8] = 8'd8;
        vout[8] = 8'd9;
        vin[9] = 8'd9;
        vout[9] = 8'd8;
        vin[10] = 8'd10;
        vout[10] = 8'd7;
        vin[11] = 8'd11;
        vout[11] = 8'd6;
        vin[12] = 8'd12;
        vout[12] = 8'd5;
        vin[13] = 8'd13;
        vout[13] = 8'd4;
        vin[14] = 8'd14;
        vout[14] = 8'd3;
        vin[15] = 8'd15;
        vout[15] = 8'd2;
        vin[16] = 8'd16;
        vout[16] = 8'd1;
        repeat (20) @(posedge clk);
        for (v = 0; v < NV; v = v + 1) check_vec(v);
        check_error;
        check_vec(0);                               // still works after an error
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
