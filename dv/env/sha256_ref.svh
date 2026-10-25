// SHA-256 reference model in SystemVerilog (same algorithm as fw/hal/test/sha256_ref.c).
// Used by the self-checking sequences of P-08. The DPI scoreboard on sha256_ref.c is task P-17.
// Same convention as the RTL: H0 in the top bits of the 256-bit hash, W0 in the top bits of the 512-bit block.

localparam bit [255:0] SHA256_IV = {32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
                                                                        32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19};

localparam bit [2047:0] SHA256_K_ALL = {
    32'h428a2f98, 32'h71374491, 32'hb5c0fbcf, 32'he9b5dba5, 32'h3956c25b, 32'h59f111f1, 32'h923f82a4, 32'hab1c5ed5,
    32'hd807aa98, 32'h12835b01, 32'h243185be, 32'h550c7dc3, 32'h72be5d74, 32'h80deb1fe, 32'h9bdc06a7, 32'hc19bf174,
    32'he49b69c1, 32'hefbe4786, 32'h0fc19dc6, 32'h240ca1cc, 32'h2de92c6f, 32'h4a7484aa, 32'h5cb0a9dc, 32'h76f988da,
    32'h983e5152, 32'ha831c66d, 32'hb00327c8, 32'hbf597fc7, 32'hc6e00bf3, 32'hd5a79147, 32'h06ca6351, 32'h14292967,
    32'h27b70a85, 32'h2e1b2138, 32'h4d2c6dfc, 32'h53380d13, 32'h650a7354, 32'h766a0abb, 32'h81c2c92e, 32'h92722c85,
    32'ha2bfe8a1, 32'ha81a664b, 32'hc24b8b70, 32'hc76c51a3, 32'hd192e819, 32'hd6990624, 32'hf40e3585, 32'h106aa070,
    32'h19a4c116, 32'h1e376c08, 32'h2748774c, 32'h34b0bcb5, 32'h391c0cb3, 32'h4ed8aa4a, 32'h5b9cca4f, 32'h682e6ff3,
    32'h748f82ee, 32'h78a5636f, 32'h84c87814, 32'h8cc70208, 32'h90befffa, 32'ha4506ceb, 32'hbef9a3f7, 32'hc67178f2};

class sha256_ref;

    static function bit [31:0] rotr(bit [31:0] x, int unsigned n);
        return (x >> n) | (x << (32 - n));
    endfunction

    // Compress 1 block: new H = old H + result of the 64 rounds
    static function bit [255:0] compress(bit [255:0] hin, bit [511:0] blk);
        bit [31:0] w [64];
        bit [31:0] a, b, c, d, e, f, g, h, t1, t2, s0, s1;
        for (int i = 0; i < 16; i++)
            w[i] = blk[511 - 32*i -: 32];
        for (int i = 16; i < 64; i++) begin
            s0   = rotr(w[i-15], 7)  ^ rotr(w[i-15], 18) ^ (w[i-15] >> 3);
            s1   = rotr(w[i-2], 17)  ^ rotr(w[i-2], 19)  ^ (w[i-2] >> 10);
            w[i] = w[i-16] + s0 + w[i-7] + s1;
        end
        {a, b, c, d, e, f, g, h} = hin;
        for (int i = 0; i < 64; i++) begin
            t1 = h + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g))
                          + SHA256_K_ALL[2047 - 32*i -: 32] + w[i];
            t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
            h = g;
            g = f;
            f = e;
            e = d + t1;
            d = c;
            c = b;
            b = a;
            a = t1 + t2;
        end
        return {hin[255:224] + a, hin[223:192] + b, hin[191:160] + c, hin[159:128] + d,
                        hin[127:96]  + e, hin[95:64]    + f, hin[63:32]    + g, hin[31:0]    + h};
    endfunction

    // Standard SHA-256 padding -> list of 512-bit blocks (first message byte in bits [511:504])
    static function void pad(input byte unsigned msg[$], output bit [511:0] blocks[$]);
        byte unsigned m[$];
        bit [63:0]    nbits = 64'(msg.size()) * 8;
        bit [511:0]   blk;
        m = msg;
        m.push_back(8'h80);
        while (m.size() % 64 != 56)
            m.push_back(8'h00);
        for (int i = 7; i >= 0; i--)
            m.push_back(nbits[8*i +: 8]);
        blocks.delete();
        for (int k = 0; k < m.size() / 64; k++) begin
            for (int j = 0; j < 64; j++)
                blk[511 - 8*j -: 8] = m[64*k + j];
            blocks.push_back(blk);
        end
    endfunction

    static function bit [255:0] digest(byte unsigned msg[$]);
        bit [511:0] blocks[$];
        bit [255:0] hs = SHA256_IV;
        pad(msg, blocks);
        foreach (blocks[k])
            hs = compress(hs, blocks[k]);
        return hs;
    endfunction

endclass
