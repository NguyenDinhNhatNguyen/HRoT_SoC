`timescale 1ns / 1ps

module IF_Stage(
    input         clk, rst,
    input         stall_IF,         // Dong bang PC
    input         flush_IF,         // Flush khi branch/jump resolve o EX
    input  [31:0] PCFlushTarget_EX, // Dia chi dich tu EX khi flush

    output [31:0] PC_IF_out,            // PC hien tai
    output [31:0] Instr_IF_out,         // Lenh hien tai
    output [31:0] PC_Plus_4_IF_out      // PC + 4
);

wire [31:0] PCNext_IF;

assign PCNext_IF = PC_Plus_4_IF_out;

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

Instruction_Memory #(
    .MEM_SIZE      (1024)   
) u_Instruction_Memory (
    .addr_i        (PC_IF_out),
    .inst_o        (Instr_IF_out)
);

endmodule