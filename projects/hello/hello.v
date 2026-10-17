// Sends a greeting over the BL616's UART bridge (appears as /dev/ttyUSB1) once a second.
module hello #(
    parameter CLK_HZ = 27_000_000,
    parameter BAUD   = 115200
) (
    input  wire clk,
    output reg  tx = 1'b1,
    output wire [5:0] leds
);
    localparam integer DIV = CLK_HZ / BAUD;   // 234 clocks per bit
    localparam [8*27-1:0] MSG = "Hello from Tang Nano 20K!\r\n";
    localparam integer LEN = 27;

    reg [15:0] div = 0;
    reg [3:0]  bit_i = 0;
    reg [9:0]  shifter = 10'h3ff;
    reg        busy = 0;
    reg [5:0]  idx = 0;
    reg [24:0] wait_ctr = 0;
    reg [2:0]  state = 0;                      // 0: gap, 1: load byte, 2: send, 3: advance
    reg [7:0]  ch;

    always @(posedge clk) begin
        case (state)
            0: begin                           // one-second gap between greetings
                wait_ctr <= wait_ctr + 1;
                if (wait_ctr == CLK_HZ - 1) begin
                    wait_ctr <= 0;
                    idx <= 0;
                    state <= 1;
                end
            end
            1: begin                           // MSG[0] is the leftmost character
                ch <= MSG[8*(27-1-idx) +: 8];
                state <= 2;
                shifter <= {1'b1, MSG[8*(27-1-idx) +: 8], 1'b0};  // stop, data, start
                bit_i <= 0;
                div <= 0;
                busy <= 1;
            end
            2: begin
                tx <= shifter[0];
                if (div == DIV - 1) begin
                    div <= 0;
                    shifter <= {1'b1, shifter[9:1]};
                    if (bit_i == 9) state <= 3;
                    bit_i <= bit_i + 1;
                end else div <= div + 1;
            end
            3: begin
                busy <= 0;
                if (idx == LEN - 1) state <= 0;
                else begin idx <= idx + 1; state <= 1; end
            end
        endcase
    end

    reg [26:0] count = 0;
    always @(posedge clk) count <= count + 1;
    assign leds = ~count[26:21];               // LEDs are active low
endmodule
