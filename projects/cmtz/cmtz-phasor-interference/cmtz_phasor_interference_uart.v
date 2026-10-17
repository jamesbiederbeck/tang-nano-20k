// UART receiver and transmitter used by verilog_uart.py (8N1, mid-bit sampling).
module uart_rx #(
    parameter CLKS_PER_BIT = 234            // 27 MHz / 115200
) (
    input  wire       clk,
    input  wire       rx,
    output reg  [7:0] data   = 0,
    output reg        strobe = 0            // one clock, byte received with good stop bit
);
    reg rx_m = 1'b1, rx_s = 1'b1;           // 2-flop synchronizer
    always @(posedge clk) begin rx_m <= rx; rx_s <= rx_m; end

    localparam IDLE = 0, START = 1, DATA = 2, STOP = 3;
    reg [1:0]  st  = IDLE;
    reg [15:0] cnt = 0;
    reg [2:0]  bi  = 0;

    always @(posedge clk) begin
        strobe <= 1'b0;
        case (st)
            IDLE: if (!rx_s) begin cnt <= 0; st <= START; end
            START: if (cnt == CLKS_PER_BIT / 2 - 1) begin   // middle of start bit
                if (!rx_s) begin cnt <= 0; bi <= 0; st <= DATA; end
                else st <= IDLE;
            end else cnt <= cnt + 1;
            DATA: if (cnt == CLKS_PER_BIT - 1) begin        // middle of each data bit
                cnt  <= 0;
                data <= {rx_s, data[7:1]};                  // LSB first
                bi   <= bi + 1;
                if (bi == 7) st <= STOP;
            end else cnt <= cnt + 1;
            STOP: if (cnt == CLKS_PER_BIT - 1) begin
                strobe <= rx_s;
                st <= IDLE;
            end else cnt <= cnt + 1;
        endcase
    end
endmodule

module uart_tx #(
    parameter CLKS_PER_BIT = 234
) (
    input  wire       clk,
    input  wire [7:0] data,
    input  wire       start,                // one clock, ignored while busy
    output reg        tx   = 1'b1,
    output wire       busy
);
    reg [9:0]  sh     = 10'h3ff;            // {stop 1, byte, start 0}
    reg [15:0] cnt    = 0;
    reg [3:0]  bi     = 0;
    reg        active = 1'b0;
    assign busy = active;

    always @(posedge clk) begin
        if (!active) begin
            tx <= 1'b1;
            if (start) begin sh <= {1'b1, data, 1'b0}; cnt <= 0; bi <= 0; active <= 1'b1; end
        end else begin
            tx <= sh[0];
            if (cnt == CLKS_PER_BIT - 1) begin
                cnt <= 0;
                sh  <= {1'b1, sh[9:1]};
                bi  <= bi + 1;
                if (bi == 9) active <= 1'b0;
            end else cnt <= cnt + 1;
        end
    end
endmodule


// UART front end for the generated `cmtz_phasor_interference` datapath, F_7.
//
// Request (4 bytes, 8N1, each 0..6): in_cembed_1 (re, im); in_cembed_2 (re, im)
// Reply   (3 bytes): out_combined; out_solo_A; out_solo_B
// Any request byte >= 7 makes every reply byte 0xFF. A request that stalls
// partway is dropped after TIMEOUT_CLKS; bytes sent during a reply are
// ignored. LEDs (active low): leds[4:0] low bits of the first reply byte,
// leds[5] lights after an error reply.
module cmtz_phasor_interference_uart #(
    parameter CLKS_PER_BIT = 234,           // 27 MHz / 115200
    parameter TIMEOUT_CLKS = 6_750_000      // 250 ms at 27 MHz
) (
    input  wire       clk,
    input  wire       rx,
    output wire       tx,
    output wire [5:0] leds
);
    localparam NI = 4, NO = 3;

    wire [7:0] rx_data;
    wire       rx_strobe;
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rx(rx), .data(rx_data), .strobe(rx_strobe));

    reg  [7:0] req [0:NI-1];
    reg  [7:0] rep [0:NO-1];
    reg  [7:0] cnt      = 0;
    reg        bad      = 1'b0;
    reg        err      = 1'b0;
    reg        tx_start = 1'b0;
    wire       tx_busy;
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .data(rep[cnt]), .start(tx_start), .tx(tx), .busy(tx_busy));

    reg        in_valid = 1'b0;
    wire       out_valid;
    wire [5:0] in_cembed_1_w = {req[1][2:0], req[0][2:0]};
    wire [5:0] in_cembed_2_w = {req[3][2:0], req[2][2:0]};
    wire [2:0] out_combined_w;
    wire [2:0] out_solo_A_w;
    wire [2:0] out_solo_B_w;
    cmtz_phasor_interference dut (.in_cembed_1(in_cembed_1_w), .in_cembed_2(in_cembed_2_w), .out_combined(out_combined_w), .out_solo_A(out_solo_A_w), .out_solo_B(out_solo_B_w), .clk(clk), .in_valid(in_valid), .out_valid(out_valid));

    localparam S_RECV = 0, S_CHK = 1, S_RUN = 2, S_SEND = 3, S_WAIT = 4, S_DONE = 5;
    reg [2:0]  state = S_RECV;
    reg [31:0] idle  = 0;

    always @(posedge clk) begin
        in_valid <= 1'b0;
        tx_start <= 1'b0;
        case (state)
            S_RECV: if (rx_strobe) begin
                req[cnt] <= rx_data;
                if (rx_data >= 8'd7) bad <= 1'b1;
                if (cnt == NI - 1) begin cnt <= 0; state <= S_CHK; end
                else cnt <= cnt + 1;
            end
            S_CHK: if (bad) begin
                rep[0] <= 8'hFF; rep[1] <= 8'hFF; rep[2] <= 8'hFF;
                err <= 1'b1; state <= S_SEND;
            end else begin
                in_valid <= 1'b1; err <= 1'b0; state <= S_RUN;
            end
            S_RUN: if (out_valid) begin
                rep[0] <= out_combined_w; rep[1] <= out_solo_A_w; rep[2] <= out_solo_B_w;
                state <= S_SEND;
            end
            S_SEND: if (!tx_busy) begin tx_start <= 1'b1; state <= S_WAIT; end
            S_WAIT: state <= S_DONE;                   // let tx_busy rise
            S_DONE: if (!tx_busy) begin
                if (cnt == NO - 1) begin cnt <= 0; bad <= 1'b0; state <= S_RECV; end
                else begin cnt <= cnt + 1; state <= S_SEND; end
            end
            default: state <= S_RECV;
        endcase

        // resync: drop a half-received request after TIMEOUT_CLKS of silence
        if (state == S_RECV && cnt != 0 && !rx_strobe) begin
            if (idle == TIMEOUT_CLKS - 1) begin idle <= 0; cnt <= 0; bad <= 1'b0; end
            else idle <= idle + 1;
        end else idle <= 0;
    end

    assign leds = ~{err, rep[0][4:0]};                // LEDs are active low
endmodule
