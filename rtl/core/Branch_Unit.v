`timescale 1ns / 1ps

// [!] LUU Y: Chi xu ly dung BEQ/BNE. Cac lenh BLT/BGE/BLTU/BGEU
//     (funct3=100/101/110/111) se SAI vi Zero khong du thong tin
//     so sanh lon/nho (gioi han ke thua tu ban single-cycle goc).
//     Can sua neu firmware sau nay dung cac lenh nay: them tin
//     hieu "LessThan" tu ALU va mo rong take_branch theo funct3.

module Branch_Unit(
    input       Branch,
    input       Jump,
    input       Jalr,
    input [2:0] funct3,
    input       Zero,

    output      PCSrc
);

// BEQ: funct3 = 000 -> branch when Zero = 1
// BNE: funct3 = 001 -> branch when Zero = 0
wire take_branch;

assign take_branch = (funct3 == 3'b001) ? ~Zero : Zero;

assign PCSrc = (Branch && take_branch) || Jump || Jalr;

endmodule