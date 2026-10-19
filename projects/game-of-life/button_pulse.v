// Turns a raw push-button pin into one clean clock pulse per press, whichever level means "pressed".
//
// The pin is synchronised, then the level it has after SETTLE clocks (buttons not touched) is taken
// as "not pressed". After that, a different level that holds for DEBOUNCE clocks is a press, and
// the pulse comes once when it is recognised. Nothing happens until the button is released again.
module button_pulse #(
    parameter SETTLE = 1 << 22,         // about 56 ms at 74.25 MHz
    parameter DEBOUNCE = 1 << 20        // about 14 ms
) (
    input  wire clk,
    input  wire raw,
    output reg  pulse = 1'b0
);
    reg  a = 0, b = 0;
    always @(posedge clk) begin a <= raw; b <= a; end

    reg [23:0] settle = 0;
    reg        armed = 1'b0;
    reg        idle = 1'b0;
    always @(posedge clk) begin
        if (!armed) begin
            if (settle == SETTLE) begin armed <= 1'b1; idle <= b; end
            else settle <= settle + 24'd1;
        end
    end

    wire       down = armed && (b != idle);
    reg [23:0] hold = 0;
    reg        held = 1'b0;             // already reported this press
    always @(posedge clk) begin
        pulse <= 1'b0;
        if (!down) begin hold <= 0; held <= 1'b0; end
        else if (!held) begin
            if (hold == DEBOUNCE) begin pulse <= 1'b1; held <= 1'b1; end
            else hold <= hold + 24'd1;
        end
    end
endmodule
