// Conway's Game of Life on a W x H torus, double-buffered in block RAM.
//
// Four 1-bit RAMs hold two copies of each of two buffers: the display reads one copy of
// the front buffer, the engine reads the other, and writes go to both copies of the back
// buffer. The engine visits each cell, fetches its 3x3 neighbourhood one bit at a time
// (12 clocks per cell), and writes the next state to the back buffer. When a generation is
// done it waits for `tick`, then swaps front and back. A random soup is written first, and
// again after the grid goes still or after MAX_GEN generations.
//
// Cell (cx, cy) lives at address {cy, cx}, XB and YB bits wide, so rows are 2**XB apart.
module life_ram #(
    parameter AW = 15
) (
    input  wire          clk,
    input  wire          we,
    input  wire [AW-1:0] waddr,
    input  wire          wdata,
    input  wire [AW-1:0] raddr,
    output reg           q
);
    reg mem [0:(1 << AW) - 1];
    always @(posedge clk) if (we) mem[waddr] <= wdata;
    always @(posedge clk) q <= mem[raddr];          // synchronous read, so it maps to block RAM
endmodule

module life_core #(
    parameter W = 160,
    parameter H = 90,
    parameter XB = 8,
    parameter YB = 7,
    parameter MAX_GEN = 1024
) (
    input  wire               clk,
    input  wire               tick,        // one clock: swap buffers now if the next generation is ready
    input  wire [XB+YB-1:0]   raddr,       // display read address, front buffer
    output wire               q,           // cell value, one clock after raddr
    output reg  [15:0]        gen = 0,     // generations since the last seed
    output reg                swapped = 0, // one clock after each swap
    output reg                seed_swap = 0 // that swap exposed a fresh seed
);
    localparam AW = XB + YB;
    localparam S_SEED = 0, S_RUN = 1, S_WAIT = 2;

    reg [1:0]  state = S_SEED;
    reg        front = 1'b0;               // 0: buffer A is displayed, 1: buffer B
    reg        seeding_back = 1'b1;        // the back buffer holds a seed, not a computed generation
    reg [XB-1:0] cx = 0;
    reg [YB-1:0] cy = 0;
    reg [3:0]  k = 0;
    reg [3:0]  cnt = 0;
    reg        center = 0;
    reg [15:0] chg = 0;                    // cells that changed in this generation
    reg [31:0] rng = 32'h1badf00d;

    reg          we = 0;
    reg [AW-1:0] waddr = 0;
    reg          wdata = 0;
    reg [AW-1:0] ra = 0;

    wire weA = we & front;                 // the back buffer is A when B is displayed
    wire weB = we & ~front;
    wire qA1, qB1, qA2, qB2;
    life_ram #(AW) ramA1 (.clk(clk), .we(weA), .waddr(waddr), .wdata(wdata), .raddr(raddr), .q(qA1));
    life_ram #(AW) ramB1 (.clk(clk), .we(weB), .waddr(waddr), .wdata(wdata), .raddr(raddr), .q(qB1));
    life_ram #(AW) ramA2 (.clk(clk), .we(weA), .waddr(waddr), .wdata(wdata), .raddr(ra),    .q(qA2));
    life_ram #(AW) ramB2 (.clk(clk), .we(weB), .waddr(waddr), .wdata(wdata), .raddr(ra),    .q(qB2));
    assign q = front ? qB1 : qA1;
    wire eq  = front ? qB2 : qA2;

    // neighbours with wraparound
    wire [XB-1:0] xm = (cx == 0)     ? W - 1 : cx - 1;
    wire [XB-1:0] xp = (cx == W - 1) ? 0     : cx + 1;
    wire [YB-1:0] ym = (cy == 0)     ? H - 1 : cy - 1;
    wire [YB-1:0] yp = (cy == H - 1) ? 0     : cy + 1;

    // k = 0..8 walks the 3x3 neighbourhood row by row; k = 4 is the cell itself
    reg [AW-1:0] nb;
    always @* begin
        case (k)
            0: nb = {ym, xm};  1: nb = {ym, cx};  2: nb = {ym, xp};
            3: nb = {cy, xm};  4: nb = {cy, cx};  5: nb = {cy, xp};
            6: nb = {yp, xm};  7: nb = {yp, cx};  default: nb = {yp, xp};
        endcase
    end

    wire [3:0] n_all  = cnt;
    wire       alive_next = (n_all == 4'd3) || (center && n_all == 4'd2);

    // xorshift32; ~37% of cells start alive
    wire [31:0] r1 = rng ^ (rng << 13);
    wire [31:0] r2 = r1 ^ (r1 >> 17);
    wire [31:0] r3 = r2 ^ (r2 << 5);
    wire        seed_bit = rng[0] & (rng[7] | rng[19]);

    wire last_x    = (cx == W - 1);
    wire last_y    = (cy == H - 1);
    wire last_cell = last_x && last_y;

    always @(posedge clk) begin
        swapped   <= 1'b0;
        we        <= 1'b0;
        case (state)
            S_SEED: begin
                we <= 1'b1; waddr <= {cy, cx}; wdata <= seed_bit; rng <= r3;
                cx <= last_x ? 0 : cx + 1;
                cy <= last_x ? (last_y ? 0 : cy + 1) : cy;
                if (last_cell) begin state <= S_WAIT; seeding_back <= 1'b1; end
            end
            S_RUN: begin
                k <= k + 1;
                if (k <= 8) ra <= nb;                              // issue read for neighbour k
                if (k >= 2 && k <= 10) begin                       // data for neighbour k-2 arrives
                    if (k == 6) center <= eq;
                    else        cnt <= cnt + eq;
                end
                if (k == 11) begin
                    we <= 1'b1; waddr <= {cy, cx}; wdata <= alive_next;
                    if (alive_next != center) chg <= chg + 1;
                    k <= 0; cnt <= 0;
                    cx <= last_x ? 0 : cx + 1;
                    cy <= last_x ? (last_y ? 0 : cy + 1) : cy;
                    if (last_cell) state <= S_WAIT;
                end
            end
            S_WAIT: if (tick) begin
                front   <= ~front;
                swapped <= 1'b1;
                seed_swap <= seeding_back;
                if (seeding_back) begin
                    gen <= 0; chg <= 0; seeding_back <= 1'b0; state <= S_RUN;
                end else if (chg == 0 || gen == MAX_GEN - 1) begin
                    gen <= gen + 1; chg <= 0; seeding_back <= 1'b1; state <= S_SEED;
                end else begin
                    gen <= gen + 1; chg <= 0; state <= S_RUN;
                end
            end
        endcase
    end
endmodule
