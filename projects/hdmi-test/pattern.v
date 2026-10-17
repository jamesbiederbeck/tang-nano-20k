// Test pattern for the 1280x720 active area:
//   top 40 lines:     a white 32-pixel marker that moves 8 pixels per frame
//   lines 40 to 599:  eight 160-pixel colour bars (white, yellow, cyan, green, magenta, red, blue, black)
//   lines 600 to 719: a horizontal grey ramp, black on the left to white on the right
module pattern (
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire [10:0] marker_x,
    output reg  [23:0] rgb               // {red, green, blue}
);
    // bar number 0..7: the 160-pixel-wide column x falls in
    reg [2:0] bar;
    always @* begin
        if      (x < 160)  bar = 0;
        else if (x < 320)  bar = 1;
        else if (x < 480)  bar = 2;
        else if (x < 640)  bar = 3;
        else if (x < 800)  bar = 4;
        else if (x < 960)  bar = 5;
        else if (x < 1120) bar = 6;
        else               bar = 7;
    end

    wire [18:0] ramp_wide = x * 8'd204;      // x * 204 / 1024 is about x * 255 / 1280
    wire [7:0]  ramp      = ramp_wide[17:10];

    always @* begin
        if (y < 40) begin
            if (x >= marker_x && x < marker_x + 11'd32) rgb = 24'hFFFFFF;
            else                                         rgb = 24'h101010;
        end else if (y < 600) begin
            case (bar)
                0: rgb = 24'hFFFFFF;
                1: rgb = 24'hFFFF00;
                2: rgb = 24'h00FFFF;
                3: rgb = 24'h00FF00;
                4: rgb = 24'hFF00FF;
                5: rgb = 24'hFF0000;
                6: rgb = 24'h0000FF;
                default: rgb = 24'h000000;
            endcase
        end else
            rgb = {ramp, ramp, ramp};
    end
endmodule
