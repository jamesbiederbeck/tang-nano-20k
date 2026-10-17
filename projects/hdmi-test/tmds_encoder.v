// TMDS 8b/10b encoder as defined by the DVI 1.0 specification.
// One pipeline stage: inputs sampled on clk, 10-bit symbol out the next clock.
// During blanking (de = 0) it sends one of the four control symbols selected by {c1, c0}.
module tmds_encoder (
    input  wire       clk,
    input  wire [7:0] d,
    input  wire       c0,
    input  wire       c1,
    input  wire       de,
    output reg  [9:0] q = 10'b1101010100
);
    // stage 1: transition-minimized 9-bit word
    wire [3:0] n1d = d[0] + d[1] + d[2] + d[3] + d[4] + d[5] + d[6] + d[7];
    wire use_xnor  = (n1d > 4'd4) || (n1d == 4'd4 && !d[0]);

    function [8:0] minimize(input [7:0] x, input xnor_mode);
        integer i;
        reg [7:0] t;
        begin
            t[0] = x[0];
            for (i = 1; i < 8; i = i + 1)
                t[i] = xnor_mode ? ~(t[i-1] ^ x[i]) : (t[i-1] ^ x[i]);
            minimize = {~xnor_mode, t};
        end
    endfunction

    wire [8:0] qm = minimize(d, use_xnor);

    // stage 2: DC balancing against the running disparity cnt
    wire [3:0] n1q = qm[0] + qm[1] + qm[2] + qm[3] + qm[4] + qm[5] + qm[6] + qm[7];
    wire signed [4:0] n1s  = {1'b0, n1q};
    wire signed [4:0] diff = n1s - (5'sd8 - n1s);        // ones minus zeros in qm[7:0]

    reg signed [4:0] cnt = 0;

    always @(posedge clk) begin
        if (de) begin
            if (cnt == 0 || n1q == 4'd4) begin
                if (!qm[8]) begin q <= {2'b10, ~qm[7:0]}; cnt <= cnt - diff; end
                else        begin q <= {2'b01,  qm[7:0]}; cnt <= cnt + diff; end
            end else if ((cnt > 0 && n1q > 4'd4) || (cnt < 0 && n1q < 4'd4)) begin
                q   <= {1'b1, qm[8], ~qm[7:0]};
                cnt <= cnt + (qm[8] ? 5'sd2 : 5'sd0) - diff;
            end else begin
                q   <= {1'b0, qm[8], qm[7:0]};
                cnt <= cnt - (qm[8] ? 5'sd0 : 5'sd2) + diff;
            end
        end else begin
            cnt <= 0;
            case ({c1, c0})
                2'b00: q <= 10'b1101010100;
                2'b01: q <= 10'b0010101011;
                2'b10: q <= 10'b0101010100;
                2'b11: q <= 10'b1010101011;
            endcase
        end
    end
endmodule
