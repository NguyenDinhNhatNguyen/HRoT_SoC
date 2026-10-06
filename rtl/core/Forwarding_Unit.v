module Forwarding_Unit (
    input      [4:0] Rs1_EX,
    input      [4:0] Rs2_EX,
    input      [4:0] Rd_MEM,
    input      [4:0] Rd_WB,
    input            RegWrite_MEM,
    input            RegWrite_WB,
    output reg [1:0] ForwardA,
    output reg [1:0] ForwardB
);
    always @(*) begin
        // Giá trị mặc định (không forward)
        ForwardA = 2'b00;
        ForwardB = 2'b00;

        // Xử lý Forward A cho Rs1_EX (Toán hạng 1)
        if (RegWrite_MEM && (Rd_MEM != 0) && (Rd_MEM == Rs1_EX))
            ForwardA = 2'b10; // Forward từ tầng MEM
        else if (RegWrite_WB && (Rd_WB != 0) && (Rd_WB == Rs1_EX))
            ForwardA = 2'b01; // Forward từ tầng WB

        // Xử lý Forward B cho Rs2_EX (Toán hạng 2)
        if (RegWrite_MEM && (Rd_MEM != 0) && (Rd_MEM == Rs2_EX))
            ForwardB = 2'b10;
        else if (RegWrite_WB && (Rd_WB != 0) && (Rd_WB == Rs2_EX))
            ForwardB = 2'b01;
    end
endmodule