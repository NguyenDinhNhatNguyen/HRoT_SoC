`timescale 1ns / 1ps

module IF_Stage(
    input         clk, rst,
    input         stall_IF,         // Freeze the PC
    input         flush_IF,         // Redirect when a branch/jump resolves taken in EX
    input  [31:0] PCFlushTarget_EX, // Target address from EX on flush

    // Instruction memory interface
    input  [31:0] instr_rdata,
    output [31:0] instr_addr,

    output [31:0] PC_IF_out,            // Current PC
    output [31:0] Instr_IF_out,         // Current instruction
    output [31:0] PC_Plus_4_IF_out      // PC + 4
);

wire [31:0] PCNext_IF;

assign PCNext_IF    = PC_Plus_4_IF_out;
assign instr_addr   = PC_IF_out;
assign Instr_IF_out = instr_rdata;

PC u_PC(
    .clk            (clk),
    .rst            (rst),
    .stall          (stall_IF),
    .flush          (flush_IF),
    .PCNext         (PCNext_IF),
    .PCflush_target (PCFlushTarget_EX),
    .PC             (PC_IF_out)
);

PC_Plus_4 u_PC_Plus_4(
    .PC            (PC_IF_out),
    .PCPlus4       (PC_Plus_4_IF_out)
);

endmodule
