// CEA-861 1280x720 @ 60 Hz timing, 74.25 MHz pixel clock, positive sync polarity.
//   horizontal: 1280 active, 110 front porch, 40 sync, 220 back porch = 1650 total
//   vertical:    720 active,   5 front porch,  5 sync,  20 back porch =  750 total
module video_timing (
    input  wire        clk,
    output reg  [10:0] x = 0,          // pixel column, counts the whole line
    output reg  [9:0]  y = 0,          // line number, counts the whole frame
    output wire        de,
    output wire        hsync,
    output wire        vsync,
    output wire        frame_start     // one clock at the first pixel of each frame
);
    localparam H_ACTIVE = 1280, H_FP = 110, H_SYNC = 40, H_TOTAL = 1650;
    localparam V_ACTIVE = 720,  V_FP = 5,   V_SYNC = 5,  V_TOTAL = 750;

    always @(posedge clk) begin
        if (x == H_TOTAL - 1) begin
            x <= 0;
            y <= (y == V_TOTAL - 1) ? 10'd0 : y + 10'd1;
        end else
            x <= x + 11'd1;
    end

    assign de          = (x < H_ACTIVE) && (y < V_ACTIVE);
    assign hsync       = (x >= H_ACTIVE + H_FP) && (x < H_ACTIVE + H_FP + H_SYNC);
    assign vsync       = (y >= V_ACTIVE + V_FP) && (y < V_ACTIVE + V_FP + V_SYNC);
    assign frame_start = (x == 0) && (y == 0);
endmodule
