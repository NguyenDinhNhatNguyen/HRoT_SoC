`timescale 1ns / 1ps

module MEM_Stage(
    input         clk,
    //Inputs tu EX_MEM_Reg
    input         RegWrite_MEM,
    input         MemWrite_MEM,
    input         MemRead_MEM,
    input  [1:0]  ResultSrc_MEM,

    input  [31:0] ALUResult_MEM,
    input  [31:0] WriteData_MEM,
    input  [31:0] PC_Plus_4_MEM,
    input  [31:0] PCTarget_MEM,
    input  [4:0]  Rd_MEM,
    //Outputs den MEM_WB_Reg
    output        RegWrite_MEM_out,
    output [1:0]  ResultSrc_MEM_out,
 
    output [31:0] ALUResult_MEM_out,
    output [31:0] ReadData_MEM_out,
    output [31:0] PC_Plus_4_MEM_out,
    output [31:0] PCTarget_MEM_out,
    output [4:0]  Rd_MEM_out
);

assign RegWrite_MEM_out  = RegWrite_MEM;
assign ResultSrc_MEM_out = ResultSrc_MEM;
 
assign ALUResult_MEM_out = ALUResult_MEM;
assign PC_Plus_4_MEM_out = PC_Plus_4_MEM;
assign PCTarget_MEM_out  = PCTarget_MEM;
assign Rd_MEM_out        = Rd_MEM;

Data_Memory #(
    .MEM_SIZE(1024)
) u_Data_Memory(
    .clk_i  (clk),
    .we_i   (MemWrite_MEM),
    .addr_i (ALUResult_MEM),
    .data_w (WriteData_MEM),
    .data_r (ReadData_MEM_out)
);

endmodule