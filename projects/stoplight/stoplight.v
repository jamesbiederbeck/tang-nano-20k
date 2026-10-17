// Two-way intersection on the six on-board LEDs (active low).
//   leds[0] NS red   leds[1] NS yellow   leds[2] NS green
//   leds[3] EW red   leds[4] EW yellow   leds[5] EW green
// Both directions are red between phases, so green never overlaps.
module stoplight #(
    parameter CLK_HZ   = 27_000_000,
    parameter GREEN_S  = 5,
    parameter YELLOW_S = 2,
    parameter ALLRED_S = 1
) (
    input  wire clk,
    output wire [5:0] leds
);
    localparam [2:0] NS_GREEN = 0, NS_YELLOW = 1, RED_TO_EW = 2,
                     EW_GREEN = 3, EW_YELLOW = 4, RED_TO_NS = 5;

    reg [2:0]  state = RED_TO_NS;     // power up all red, then NS goes first
    reg [31:0] ticks = 0;             // clocks within the current second
    reg [7:0]  secs  = 0;             // whole seconds spent in this state

    function [7:0] duration(input [2:0] s);
        case (s)
            NS_GREEN, EW_GREEN:   duration = GREEN_S;
            NS_YELLOW, EW_YELLOW: duration = YELLOW_S;
            default:              duration = ALLRED_S;
        endcase
    endfunction

    function [2:0] next(input [2:0] s);
        next = (s == RED_TO_NS) ? NS_GREEN : s + 1;
    endfunction

    // One always block per register, so no register's update hangs off another's if chain.
    wire sec_tick   = (ticks == CLK_HZ - 1);                    // end of a second
    wire phase_done = sec_tick && (secs == duration(state) - 1); // end of this phase

    always @(posedge clk) ticks <= sec_tick ? 32'd0 : ticks + 1;

    always @(posedge clk)
        if (phase_done)    secs <= 0;
        else if (sec_tick) secs <= secs + 1;

    always @(posedge clk)
        if (phase_done) state <= next(state);

    // {EW green, EW yellow, EW red, NS green, NS yellow, NS red}, 1 = lit
    reg [5:0] lamps;
    always @* begin
        case (state)
            NS_GREEN:  lamps = 6'b001_100;
            NS_YELLOW: lamps = 6'b001_010;
            EW_GREEN:  lamps = 6'b100_001;
            EW_YELLOW: lamps = 6'b010_001;
            default:   lamps = 6'b001_001;   // both red
        endcase
    end
    assign leds = ~lamps;
endmodule
