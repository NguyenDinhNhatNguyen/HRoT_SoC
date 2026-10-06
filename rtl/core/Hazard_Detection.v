module Hazard_Detection (
    input             MemRead_EX,
    input      [4:0] Rd_EX, 
    input      [4:0] Rs1_ID, 
    input      [4:0] Rs2_ID,
    output reg       Stall
);
    always @(*) begin
        // Load (MemRead_EX) + Write vào Reg mà lệnh hiện tại đang đọc (Rs1_ID hoặc Rs2_ID) => Stall
        if (MemRead_EX && ((Rd_EX == Rs1_ID) || (Rd_EX == Rs2_ID)))
            Stall = 1'b1; // Kích hoạt Stall (khóa PC, khóa IF/ID và chèn lệnh NOP vào ID/EX)
        else 
            Stall = 1'b0;
    end
endmodule