`timescale 1ns / 1ps

module WB_Stage(
    input         RegWrite_WB,
    input  [1:0]  ResultSrc_WB,
 
    input  [31:0] ALUResult_WB,
    input  [31:0] ReadData_WB,
    input  [31:0] PC_Plus_4_WB,
    input  [31:0] PCTarget_WB,
    input  [4:0]  Rd_WB,

    output        RegWrite_WB_out,
    output [4:0]  Rd_WB_out,
    output [31:0] Result_WB
);

assign RegWrite_WB_out = RegWrite_WB;
assign Rd_WB_out       = Rd_WB;

Result_Mux u_Result_Mux(
    .ALUResult (ALUResult_WB),
    .ReadData  (ReadData_WB),
    .PC_Plus_4 (PC_Plus_4_WB),
    .PCTarget  (PCTarget_WB),
    .ResultSrc (ResultSrc_WB),
    .Result    (Result_WB)
);

endmodule