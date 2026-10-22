// Conway's Game of Life on HDMI, Tang Nano 20K: 160x90 cells, 8x8 pixels each, 1280x720 @ 60 Hz.
// 27 MHz crystal -> rPLL -> 371.25 MHz bit clock -> CLKDIV /5 -> 74.25 MHz pixel clock.
// Each TMDS channel is serialized 10:1 by an OSER10 and driven out as a differential pair.
//   buttons: S1 shows the next seed kind, S2 the previous one
//   leds (active low): leds[0] lit when the PLL is locked, leds[5:1] are the generation count (low bits)
`ifdef SYNTHESIZE   // uses Gowin primitives (rPLL, CLKDIV, OSER10, TLVDS_OBUF) the simulator does not have
module top (
    input  wire       clk27,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n,
    output wire [5:0] leds,
    input  wire [1:0] btn               // S1 (next seed) and S2 (previous seed)
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

    // ---- life: one generation every FRAMES_PER_GEN frames (15 per second at 4) ----
    // The engine runs in the vertical blanking interval (line 720), when the display is not
    // reading, and takes 96 clocks. During each line's horizontal blanking the display reads
    // the row for the next active line into a shift register that steps one cell per 8 pixels.
    localparam FRAMES_PER_GEN = 2;
    reg [2:0] fcnt = 0;
    always @(posedge pclk) if (frame_start) fcnt <= (fcnt == FRAMES_PER_GEN - 1) ? 3'd0 : fcnt + 3'd1;
    wire go = (x == 11'd0) && (y == 10'd720) && (fcnt == FRAMES_PER_GEN - 1);

    wire [9:0] ny = (y == 10'd749) ? 10'd0 : y + 10'd1;     // the next line to be drawn
    wire       req = (x == 11'd1300) && (ny < 10'd720);

    wire [159:0] row;
    wire         row_valid;
    wire [15:0]  gen;
    wire next_seed, prev_seed;
    button_pulse bn (.clk(pclk), .raw(btn[0]), .pulse(next_seed));
    button_pulse bp (.clk(pclk), .raw(btn[1]), .pulse(prev_seed));

    life_row_core #(.W(160), .H(90), .YB(7)) life (
        .clk(pclk), .go(go), .next_seed(next_seed), .prev_seed(prev_seed), .disp_req(req), .disp_row(ny[9:3]),
        .disp_data(row), .disp_valid(row_valid),
        .gen(gen), .swapped(), .seed_swap(), .last_cycles());

    reg [159:0] sr = 0;
    always @(posedge pclk) begin
        if (row_valid) sr <= row;
        else if (x < 11'd1280 && x[2:0] == 3'd7) sr <= {1'b0, sr[159:1]};
    end
    wire cell = sr[0];
    wire [2:0] xd = x[2:0], yd = y[2:0];

    // live cells change colour every 64 generations; a dark line separates the cells
    reg [23:0] live;
    always @* begin
        case (gen[8:6])
            0: live = 24'h39ff14;  1: live = 24'h00e5ff;  2: live = 24'hffd400;  3: live = 24'hff4fa3;
            4: live = 24'hff7a1a;  5: live = 24'hb06bff;  6: live = 24'hffffff;  default: live = 24'h5cff9d;
        endcase
    end
    wire [23:0] rgb = (xd == 3'd7 || yd == 3'd7) ? 24'h06060c :
                      cell ? live : 24'h12122a;

    // ---- TMDS: channel 0 = blue (carries hsync/vsync), 1 = green, 2 = red ----
    wire [9:0] sym_b, sym_g, sym_r;
    tmds_encoder enc_b (.clk(pclk), .d(rgb[7:0]),   .c0(hsync), .c1(vsync), .de(de), .q(sym_b));
    tmds_encoder enc_g (.clk(pclk), .d(rgb[15:8]),  .c0(1'b0), .c1(1'b0), .de(de), .q(sym_g));
    tmds_encoder enc_r (.clk(pclk), .d(rgb[23:16]), .c0(1'b0), .c1(1'b0), .de(de), .q(sym_r));

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

    assign leds = ~{gen[4:0], lock};
endmodule
`endif
