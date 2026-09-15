`timescale 1ns / 1ps

module ID_Stage(
    input        clk,
    //Input tu IF_ID_Reg
    input [31:0] PC_ID,
    input [31:0] Instr_ID,
    input [31:0] PC_Plus_4_ID,
    //Tin hieu phan hoi tu tang WB (Write-Back) de ghi thanh ghi
    input        RegWrite_WB,
    input [31:0] Result_WB,
    input [4:0]  Rd_WB,
    //Control  chuyen sang ID_EX_Reg
    output        RegWrite_ID_out,
    output        MemWrite_ID_out,
    output        MemRead_ID_out,
    output        Branch_ID_out,
    output        Jump_ID_out,
    output        Jalr_ID_out,
    output        ALUSrc_ID_out,
    output [1:0]  ResultSrc_ID_out,
    output [3:0]  ALUControl_ID_out,
    //Data outputs sang ID_EX_Reg
    output [31:0] PC_ID_out,
    output [31:0] RD1_ID_out,
    output [31:0] RD2_ID_out,
    output [31:0] ImmExt_ID_out,
    output [31:0] PC_Plus_4_ID_out,
    //Address outputs sang ID_EX_Reg
    output [4:0]  Rs1_ID_out,
    output [4:0]  Rs2_ID_out,
    output [4:0]  Rd_ID_out,
    output [2:0]  funct3_ID_out
);

assign PC_ID_out        = PC_ID;
assign PC_Plus_4_ID_out = PC_Plus_4_ID;

wire [6:0] op_ID;
wire       funct7b5_ID;
wire [1:0] ImmSrc_ID;

assign op_ID         = Instr_ID[6:0];
assign funct7b5_ID   = Instr_ID[30];

assign funct3_ID_out = Instr_ID[14:12];
assign Rs1_ID_out    = Instr_ID[19:15];
assign Rs2_ID_out    = Instr_ID[24:20];
assign Rd_ID_out     = Instr_ID[11:7];

Control_Unit u_Control_Unit(
    .op         (op_ID),
    .funct3     (funct3_ID_out),
    .funct7b5   (funct7b5_ID),
    .ResultSrc  (ResultSrc_ID_out),
    .MemWrite   (MemWrite_ID_out),
    .MemRead    (MemRead_ID_out),
    .Branch     (Branch_ID_out),
    .ALUSrc     (ALUSrc_ID_out),
    .RegWrite   (RegWrite_ID_out),
    .Jump       (Jump_ID_out),
    .ImmSrc     (ImmSrc_ID),
    .ALUControl (ALUControl_ID_out),
    .Jalr       (Jalr_ID_out)
);

Register_File u_Register_File(
    .clk        (clk),
    .WE3        (RegWrite_WB),
    .RA1        (Rs1_ID_out),
    .RA2        (Rs2_ID_out),
    .WA3        (Rd_WB),
    .WD3        (Result_WB),
    .RD1        (RD1_ID_out),
    .RD2        (RD2_ID_out)
);

Extend u_Extend(
    .Instr      (Instr_ID),
    .ImmSrc     (ImmSrc_ID),
    .ImmExt     (ImmExt_ID_out)
);

endmodule