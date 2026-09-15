`timescale 1ns / 1ps

module EX_Stage(
    //Control va Data tu ID_EX
    input         RegWrite_EX,
    input         MemWrite_EX,
    input         MemRead_EX,
    input         Branch_EX,
    input         Jump_EX,
    input         Jalr_EX,
    input         ALUSrc_EX,
    input  [1:0]  ResultSrc_EX,
    input  [3:0]  ALUControl_EX,

    input  [31:0] PC_EX,
    input  [31:0] RD1_EX,
    input  [31:0] RD2_EX,
    input  [31:0] ImmExt_EX,
    input  [31:0] PC_Plus_4_EX,

    input  [4:0]  Rd_EX,
    input  [2:0]  funct3_EX,
    //Control input tu Forwarding Unit (giai quyet Data )
    input  [1:0]  ForwardA_EX,
    input  [1:0]  ForwardB_EX,
    input  [31:0] ALUResult_MEM,     // Dữ liệu đi tắt từ tầng MEM
    input  [31:0] Result_WB,         // Dữ liệu đi tắt từ tầng WB
    //Control/Data output day sang thanh ghi EX_MEM
    output        RegWrite_EX_out,
    output        MemWrite_EX_out,
    output        MemRead_EX_out,
    output [1:0]  ResultSrc_EX_out,

    output [31:0] ALUResult_EX_out,
    output [31:0] WriteData_EX_out,
    output [31:0] PC_Plus_4_EX_out,
    output [31:0] PCTarget_EX_out,
    output [4:0]  Rd_EX_out,
    //Output vong phan hoi ve tang IF
    output        PCSrc_EX
);

assign RegWrite_EX_out  = RegWrite_EX;
assign MemWrite_EX_out  = MemWrite_EX;
assign MemRead_EX_out   = MemRead_EX;
assign ResultSrc_EX_out = ResultSrc_EX;

assign PC_Plus_4_EX_out = PC_Plus_4_EX;
assign Rd_EX_out        = Rd_EX;

wire [31:0] SrcA_EX;
wire [31:0] SrcB_EX;
wire Zero_EX;

assign SrcA_EX = (ForwardA_EX == 2'b10) ? ALUResult_MEM : (ForwardA_EX == 2'b01) ? Result_WB : RD1_EX;

assign WriteData_EX_out = (ForwardB_EX == 2'b10) ? ALUResult_MEM : (ForwardB_EX == 2'b01) ? Result_WB : RD2_EX;

ALU_Mux u_ALU_Mux(
    .WD     (WriteData_EX_out),
    .ImmExt (ImmExt_EX),
    .ALUSrc (ALUSrc_EX),
    .B      (SrcB_EX)
);

ALU u_ALU(
    .A          (SrcA_EX),
    .B          (SrcB_EX),
    .ALUControl (ALUControl_EX),
    .Zero       (Zero_EX),
    .Result     (ALUResult_EX_out)
);

wire [31:0] PCTarget_Calc_EX;

PC_Target u_PC_Target(
    .PC       (PC_EX),
    .ImmExt   (ImmExt_EX),
    .PCTarget (PCTarget_Calc_EX)
);

assign PCTarget_EX_out = (Jalr_EX) ? ALUResult_EX_out : PCTarget_Calc_EX;

Branch_Unit u_Branch_Unit(
    .Branch (Branch_EX),
    .Jump   (Jump_EX),
    .Jalr   (Jalr_EX),
    .funct3 (funct3_EX),
    .Zero   (Zero_EX),
    .PCSrc  (PCSrc_EX)
);

endmodule