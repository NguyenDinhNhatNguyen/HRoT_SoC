// SHA-256 compression, one round per clock: 64 rounds + 1 cycle to fold into H = 65 cycles per block
// - start (1-cycle pulse) hashes block_in. init=1 starts from the standard H0-H7 (first block),
//   init=0 chains from the previous block's hash (multi-block messages)
// - Message padding is done by firmware
// - block_in[511:480] = W0 (big-endian, as in FIPS 180-4)
module SHA256_Core (
    input              clk, reset, start, init,
    input      [511:0] block_in,
    output reg         busy,
    output reg         done,      // high while hash_out is valid, cleared by the next start
    output     [255:0] hash_out
);
    localparam [255:0] IV = {32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
                             32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19};

    // The 64 SHA-256 round constants, K[0] in the top bits
    localparam [2047:0] K_ALL = {
        32'h428a2f98, 32'h71374491, 32'hb5c0fbcf, 32'he9b5dba5, 32'h3956c25b, 32'h59f111f1, 32'h923f82a4, 32'hab1c5ed5,
        32'hd807aa98, 32'h12835b01, 32'h243185be, 32'h550c7dc3, 32'h72be5d74, 32'h80deb1fe, 32'h9bdc06a7, 32'hc19bf174,
        32'he49b69c1, 32'hefbe4786, 32'h0fc19dc6, 32'h240ca1cc, 32'h2de92c6f, 32'h4a7484aa, 32'h5cb0a9dc, 32'h76f988da,
        32'h983e5152, 32'ha831c66d, 32'hb00327c8, 32'hbf597fc7, 32'hc6e00bf3, 32'hd5a79147, 32'h06ca6351, 32'h14292967,
        32'h27b70a85, 32'h2e1b2138, 32'h4d2c6dfc, 32'h53380d13, 32'h650a7354, 32'h766a0abb, 32'h81c2c92e, 32'h92722c85,
        32'ha2bfe8a1, 32'ha81a664b, 32'hc24b8b70, 32'hc76c51a3, 32'hd192e819, 32'hd6990624, 32'hf40e3585, 32'h106aa070,
        32'h19a4c116, 32'h1e376c08, 32'h2748774c, 32'h34b0bcb5, 32'h391c0cb3, 32'h4ed8aa4a, 32'h5b9cca4f, 32'h682e6ff3,
        32'h748f82ee, 32'h78a5636f, 32'h84c87814, 32'h8cc70208, 32'h90befffa, 32'ha4506ceb, 32'hbef9a3f7, 32'hc67178f2};

    function [31:0] rotr(input [31:0] x, input [4:0] n);
        rotr = (x >> n) | (x << (32 - n));
    endfunction

    reg [255:0] H;                      // hash state H0..H7 (H0 in the top bits)
    reg [31:0]  a, b, c, d, e, f, g, h;
    reg [31:0]  W [0:15];               // 16-word sliding window of the message schedule: W[0] = W_t
    reg [6:0]   round;                  // 0..63: rounds, 64: fold into H

    assign hash_out = H;

    wire [31:0] K_t  = K_ALL[2047 - 32*round[5:0] -: 32];
    wire [31:0] S1   = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
    wire [31:0] ch   = (e & f) ^ (~e & g);
    wire [31:0] T1   = h + S1 + ch + K_t + W[0];
    wire [31:0] S0   = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
    wire [31:0] maj  = (a & b) ^ (a & c) ^ (b & c);
    wire [31:0] T2   = S0 + maj;
    wire [31:0] s0   = rotr(W[1], 7)  ^ rotr(W[1], 18)  ^ (W[1] >> 3);
    wire [31:0] s1   = rotr(W[14], 17) ^ rotr(W[14], 19) ^ (W[14] >> 10);
    wire [31:0] W_new = s1 + W[9] + s0 + W[0];   // = W_{t+16}

    wire [255:0] H_start = init ? IV : H;

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            busy  <= 1'b0;
            done  <= 1'b0;
            round <= 7'd0;
            H     <= IV;
        end else if (start && !busy) begin
            busy  <= 1'b1;
            done  <= 1'b0;
            round <= 7'd0;
            if (init) H <= IV;
            {a, b, c, d, e, f, g, h} <= H_start;
            for (i = 0; i < 16; i = i + 1)
                W[i] <= block_in[511 - 32*i -: 32];
        end else if (busy) begin
            if (round < 7'd64) begin
                h <= g; g <= f; f <= e; e <= d + T1;
                d <= c; c <= b; b <= a; a <= T1 + T2;
                for (i = 0; i < 15; i = i + 1)
                    W[i] <= W[i+1];
                W[15] <= W_new;
                round <= round + 7'd1;
            end else begin
                // H_i = H_i + a..h
                H <= {H[255:224] + a, H[223:192] + b, H[191:160] + c, H[159:128] + d,
                      H[127:96]  + e, H[95:64]    + f, H[63:32]    + g, H[31:0]    + h};
                busy <= 1'b0;
                done <= 1'b1;
            end
        end
    end
endmodule
