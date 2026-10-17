// HDMI (DVI) test pattern for the Tang Nano 20K: 1280x720 @ 60 Hz.
// 27 MHz crystal -> rPLL -> 371.25 MHz bit clock -> CLKDIV /5 -> 74.25 MHz pixel clock.
// Each TMDS channel is serialized 10:1 by an OSER10 and driven out as a differential pair.
//   leds (active low): leds[0] lit when the PLL is locked, leds[5:1] count frames
`ifdef SYNTHESIZE   // uses Gowin primitives (rPLL, CLKDIV, OSER10, TLVDS_OBUF) the simulator does not have
module top (
    input  wire       clk27,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n,
    output wire [5:0] leds
);
    // ---- clocks ----
    wire fclk, lock, pclk;

    rPLL #(
        .FCLKIN("27"),
        .IDIV_SEL(3),        // 27 MHz / 4
        .FBDIV_SEL(54),      // x 55 -> 371.25 MHz
        .ODIV_SEL(2),        // VCO = 742.5 MHz
        .DEVICE("GW2A-18C")
    ) pll (
        .CLKIN(clk27), .CLKFB(1'b0), .RESET(1'b0), .RESET_P(1'b0),
        .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0),
        .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0),
        .CLKOUT(fclk), .LOCK(lock), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3()
    );

    CLKDIV #(.DIV_MODE("5")) pixel_div (
        .HCLKIN(fclk), .RESETN(lock), .CALIB(1'b0), .CLKOUT(pclk)
    );

    // ---- video ----
    wire [10:0] x;
    wire [9:0]  y;
    wire        de, hsync, vsync, frame_start;
    video_timing timing (.clk(pclk), .x(x), .y(y), .de(de),
                         .hsync(hsync), .vsync(vsync), .frame_start(frame_start));

    reg [10:0] marker_x = 0;
    reg [7:0]  frames   = 0;
    always @(posedge pclk) if (frame_start) begin
        marker_x <= (marker_x >= 11'd1248) ? 11'd0 : marker_x + 11'd8;
        frames   <= frames + 8'd1;
    end

    wire [23:0] rgb;
    pattern pat (.x(x), .y(y), .marker_x(marker_x), .rgb(rgb));

    // ---- TMDS: channel 0 = blue (carries hsync/vsync), 1 = green, 2 = red ----
    wire [9:0] sym_b, sym_g, sym_r;
    tmds_encoder enc_b (.clk(pclk), .d(rgb[7:0]),   .c0(hsync), .c1(vsync), .de(de), .q(sym_b));
    tmds_encoder enc_g (.clk(pclk), .d(rgb[15:8]),  .c0(1'b0),  .c1(1'b0),  .de(de), .q(sym_g));
    tmds_encoder enc_r (.clk(pclk), .d(rgb[23:16]), .c0(1'b0),  .c1(1'b0),  .de(de), .q(sym_r));

    wire [9:0] sym [0:3];
    assign sym[0] = sym_b;
    assign sym[1] = sym_g;
    assign sym[2] = sym_r;
    assign sym[3] = 10'b0000011111;           // clock channel: pixel clock, 5 low then 5 high

    wire [3:0] ser;
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : lane
            OSER10 #(.GSREN("false"), .LSREN("true")) oser (
                .Q(ser[i]), .FCLK(fclk), .PCLK(pclk), .RESET(~lock),
                .D0(sym[i][0]), .D1(sym[i][1]), .D2(sym[i][2]), .D3(sym[i][3]), .D4(sym[i][4]),
                .D5(sym[i][5]), .D6(sym[i][6]), .D7(sym[i][7]), .D8(sym[i][8]), .D9(sym[i][9])
            );
        end
    endgenerate

    TLVDS_OBUF ob_clk (.I(ser[3]), .O(tmds_clk_p),  .OB(tmds_clk_n));
    TLVDS_OBUF ob_d0  (.I(ser[0]), .O(tmds_d_p[0]), .OB(tmds_d_n[0]));
    TLVDS_OBUF ob_d1  (.I(ser[1]), .O(tmds_d_p[1]), .OB(tmds_d_n[1]));
    TLVDS_OBUF ob_d2  (.I(ser[2]), .O(tmds_d_p[2]), .OB(tmds_d_n[2]));

    assign leds = ~{frames[4:0], lock};
endmodule
`endif
