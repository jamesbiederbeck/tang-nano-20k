// Game of Life on a W x H torus, one whole row of cells per clock.
//
// Each buffer holds H rows of W bits in block RAM, one row per word. A generation streams
// rows H-1, 0, 1, ..., H-1, 0 out of the front buffer through a 3-row window; once the
// window is full, every clock the 3 x W neighbourhood produces a complete new row, which is
// written to the back buffer. A generation takes H + 6 clocks. The buffers are swapped as soon
// as the last row is written, so `go` should only arrive while the display is not reading
// (the vertical blanking interval). The display and the engine share the one read port.
//
// A seed is written first, and again after the grid goes still or after MAX_GEN generations;
// the swap that shows a fresh seed is the next `go` after it is written. Seeds go round eight
// kinds: four small methuselahs and a glider gun (life_pat_rom.v), a soup patch in the middle,
// a left-right mirrored soup, and a soup over the whole grid.
module life_rowram #(
    parameter W = 160,
    parameter AW = 8
) (
    input  wire          clk,
    input  wire          we,
    input  wire [AW-1:0] waddr,
    input  wire [W-1:0]  wdata,
    input  wire [AW-1:0] raddr,
    output reg  [W-1:0]  q
);
    reg [W-1:0] mem [0:(1 << AW) - 1];
    always @(posedge clk) if (we) mem[waddr] <= wdata;
    always @(posedge clk) q <= mem[raddr];          // synchronous read, so it maps to block RAM
endmodule

module life_row_core #(
    parameter W = 160,                  // at most 160
    parameter H = 90,
    parameter YB = 7,                   // bits for a row number
    parameter MAX_GEN = 2400
) (
    input  wire            clk,
    input  wire            go,          // one clock: start a generation (or show a waiting seed)
    input  wire            next_seed,   // one clock: replace the grid with the next seed kind
    input  wire            prev_seed,   // one clock: ... with the previous seed kind
    input  wire            disp_req,    // one clock: read row disp_row of the displayed buffer
    input  wire [YB-1:0]   disp_row,
    output wire [W-1:0]    disp_data,   // valid when disp_valid, 2 clocks after disp_req
    output wire            disp_valid,
    output reg  [15:0]     gen = 0,     // generations since the last seed
    output reg             swapped = 0, // one clock after each buffer swap
    output reg             seed_swap = 0, // that swap exposed a fresh seed
    output reg  [15:0]     last_cycles = 0 // clocks from go to swap for the last generation
);
    localparam S_SEED = 0, S_READY = 1, S_RUN = 2;
    localparam AW = YB + 1;

    reg [1:0]    state = S_SEED;
    reg          front = 1'b0;          // which buffer is displayed
    reg          seeded = 1'b0;         // the back buffer holds a seed that has not been shown yet

    // ---- RAM and its address/write registers ----
    reg [AW-1:0] ra = 0;
    reg          we_r = 1'b0;
    reg [AW-1:0] wa_r = 0;
    reg [W-1:0]  wd_r = 0;
    wire [W-1:0] rq;
    life_rowram #(W, AW) ram (.clk(clk), .we(we_r), .waddr(wa_r), .wdata(wd_r), .raddr(ra), .q(rq));
    assign disp_data = rq;

    // ---- the 3-row window and the next-row logic ----
    reg [W-1:0] w0 = 0, w1 = 0, w2 = 0;
    wire [W-1:0] nxt;
    genvar gx;
    generate
        for (gx = 0; gx < W; gx = gx + 1) begin : lcell
            localparam L = (gx + W - 1) % W;
            localparam R = (gx + 1) % W;
            wire [3:0] n = w0[L] + w0[gx] + w0[R] + w1[L] + w1[R] + w2[L] + w2[gx] + w2[R];
            assign nxt[gx] = (n == 4'd3) | (w1[gx] & (n == 4'd2));
        end
    endgenerate

    // ---- seed: five xorshift32 generators side by side, thinned to about 37% alive ----
    reg [31:0] s0 = 32'h1badf00d, s1 = 32'hdeadbeef, s2 = 32'hc0ffee11, s3 = 32'h0badcafe, s4 = 32'h5eed1234;
    function [31:0] xs(input [31:0] x);
        reg [31:0] a, b;
        begin a = x ^ (x << 13); b = a ^ (a >> 17); xs = b ^ (b << 5); end
    endfunction
    wire [159:0] sr   = {s4, s3, s2, s1, s0};
    wire [159:0] r37  = {sr[122:0], sr[159:123]};
    wire [159:0] r91  = {sr[68:0],  sr[159:69]};
    wire [159:0] soup = sr & (r37 | r91);

    // The seed kinds: 0 R-pentomino, 1 mirrored soup, 2 acorn, 3 glider gun, 4 soup patch,
    // 5 diehard, 6 pi-heptomino, 7 soup over everything. Patterns come from life_pat_rom.
    reg  [2:0]   kind = 0;              // kind of the next seed to be written
    reg  [2:0]   shown = 0;             // kind of the seed on screen
    reg          req_next = 0, req_prev = 0;
    reg  [7:0]   scnt = 0;              // seed rows written
    wire [39:0]  pbits;
    wire [7:0]   px0;
    wire [6:0]   py0;
    wire [3:0]   ph;
    wire [7:0]   prel = scnt - py0;     // row within the pattern
    life_pat_rom prom (.kind(kind), .prow(prel[3:0]), .bits(pbits), .x0(px0), .y0(py0), .h(ph));
    wire         in_pat = (scnt >= py0) && (prel < ph);
    wire [159:0] placed = {120'b0, pbits} << px0;

    // left half of the soup, reflected into the right half: Life keeps the symmetry for ever
    wire [159:0] mirrored;
    genvar gm;
    generate
        for (gm = 0; gm < 80; gm = gm + 1) begin : mir
            assign mirrored[gm]       = soup[gm];
            assign mirrored[159 - gm] = soup[gm];
        end
    endgenerate

    localparam [159:0] PATCH = ((160'b1 << 48) - 1) << 56;     // columns 56..103, rows 21..68
    reg [159:0] seed_row;
    always @* begin
        case (kind)
            3'd1:    seed_row = mirrored;
            3'd4:    seed_row = (scnt >= 21 && scnt < 69) ? (soup & PATCH) : 160'b0;
            3'd7:    seed_row = soup;
            default: seed_row = in_pat ? placed : 160'b0;
        endcase
    end

    // ---- control ----
    reg [7:0]  ic = 0;                  // reads issued this generation
    reg [7:0]  acnt = 0;                // rows that have reached the window
    reg [7:0]  orow = 0;                // output rows produced
    reg        iss1 = 0, iss2 = 0;      // a read is in flight
    reg        vout = 0;                // the window holds a full neighbourhood this clock
    reg        chg = 0;                 // some row changed this generation
    reg        dv1 = 0, dv2 = 0;
    reg [15:0] cyc = 0;
    assign disp_valid = dv2;

    wire [YB-1:0] rowsel = (ic == 0) ? H - 1 : (ic == H + 1) ? 0 : ic - 1;
    wire          issuing = (state == S_RUN) && (ic <= H + 1);
    wire          last_written = we_r && (wa_r[YB-1:0] == H - 1) && (state == S_RUN);

    always @(posedge clk) begin
        swapped <= 1'b0;
        we_r    <= vout;
        iss1 <= 1'b0; dv1 <= 1'b0;
        iss2 <= iss1; dv2 <= dv1;

        // read port: the engine while it is issuing, otherwise the display
        if (issuing) begin
            ra <= {front, rowsel}; iss1 <= 1'b1; ic <= ic + 1;
        end else if (disp_req) begin
            ra <= {front, disp_row}; dv1 <= 1'b1;
        end

        // window: a row arrives from the RAM
        vout <= 1'b0;
        if (iss2) begin
            w0 <= w1; w1 <= w2; w2 <= rq;
            acnt <= acnt + 1;
            vout <= (acnt >= 2);
        end
        if (vout) begin
            wd_r <= nxt; wa_r <= {~front, orow[YB-1:0]};
            orow <= orow + 1;
            if (nxt != w1) chg <= 1'b1;
        end

        case (state)
            S_SEED: begin
                we_r <= 1'b1; wd_r <= seed_row[W-1:0]; wa_r <= {~front, scnt[YB-1:0]};
                s0 <= xs(s0); s1 <= xs(s1); s2 <= xs(s2); s3 <= xs(s3); s4 <= xs(s4);
                scnt <= scnt + 1;
                if (scnt == H - 1) begin scnt <= 0; seeded <= 1'b1; kind <= kind + 3'd1; state <= S_READY; end
            end
            S_READY: if (req_next || req_prev) begin
                // a button: write the neighbouring kind of the one on screen, dropping any waiting seed
                kind <= req_next ? shown + 3'd1 : shown - 3'd1;
                req_next <= 1'b0; req_prev <= 1'b0; seeded <= 1'b0; state <= S_SEED;
            end else if (go) begin
                if (seeded) begin
                    front <= ~front; swapped <= 1'b1; seed_swap <= 1'b1;
                    seeded <= 1'b0; gen <= 0; shown <= kind - 3'd1;
                end else begin
                    ic <= 0; acnt <= 0; orow <= 0; chg <= 1'b0; cyc <= 0; state <= S_RUN;
                end
            end
            S_RUN: begin
                cyc <= cyc + 1;
                if (last_written) begin
                    front <= ~front; swapped <= 1'b1; seed_swap <= 1'b0;
                    gen <= gen + 1; last_cycles <= cyc + 1;
                    state <= (!chg || gen == MAX_GEN - 1) ? S_SEED : S_READY;
                end
            end
        endcase

        // after the case, so a press during the clock that clears a request is not lost
        if (next_seed) req_next <= 1'b1;
        if (prev_seed) req_prev <= 1'b1;
    end
endmodule
