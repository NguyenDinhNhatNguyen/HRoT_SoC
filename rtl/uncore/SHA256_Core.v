// 1 round / 1 clock cycle
module SHA256_Core (
    input              clk, reset, start,
    input      [511:0] block_in,
    output reg         done,
    output reg [255:0] hash_out
);
    reg [6:0] round; // Count: 0 -> 63
    reg [31:0] a, b, c, d, e, f, g, h;
    
    // Mảng 64 hằng số K của SHA-256
    wire [31:0] K [0:63]; 
    // Mảng W cho Message Schedule
    reg [31:0] W [0:63];
    
    always @(posedge clk) begin
        if (reset) begin
            round <= 0;
            done <= 0;
            // Gán giá trị băm khởi tạo (H0-H7)
            a <= 32'h6a09e667;
            b <= 32'hbb67ae85;
            c <= 32'h3c6ef372;
            d <= 32'ha54ff53a;
            e <= 32'h510e527f;
            f <= 32'h9b05688c;
            g <= 32'h1f83d9ab;
            h <= 32'h5be0cd19;
        end else if (start) begin
            if (round < 64) begin
                // Thực hiện các phép toán Ch, Maj, Sigma0, Sigma1 của SHA-256 tại đây
                // Cập nhật giá trị 8 thanh ghi a, b, c, d, e, f, g, h mỗi nhịp Clock
                round <= round + 1;
            end else begin
                // Ghép 8 thanh ghi 32-bit thành mã hash 256-bit
                hash_out <= {a, b, c, d, e, f, g, h}; 
                done <= 1;
                round <= 0; // Reset counter 
            end
        end else done <= 0;
    end
endmodule