`timescale 1ns / 1ps

module Control_Unit(
    input [6:0] op,
    input [2:0] funct3,
    input       funct7b5,

    output [1:0] ResultSrc,
    output       MemWrite,
    output       MemRead,
    output       Branch,
    output       ALUSrc,
    output       RegWrite,
    output       Jump,
    output [1:0] ImmSrc,
    output [3:0] ALUControl,
    output       Jalr
);

wire [1:0] ALUop;

Main_Decoder Main_Decoder(
    .op        (op),
    .ResultSrc (ResultSrc),
    .MemWrite  (MemWrite),
    .MemRead   (MemRead),
    .Branch    (Branch),
    .ALUSrc    (ALUSrc),
    .RegWrite  (RegWrite),
    .Jump      (Jump),
    .ImmSrc    (ImmSrc),
    .ALUop     (ALUop)
);

ALU_decoder ALU_decoder(
    .opb5       (op[5]),
    .funct3     (funct3),
    .funct7b5   (funct7b5),
    .ALUOp      (ALUop),
    .ALUControl (ALUControl)
);

// RV32I JALR: opcode = 1100111, funct3 = 000
assign Jalr = (op == 7'b1100111) && (funct3 == 3'b000);

endmodule