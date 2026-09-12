`timescale 1ns / 1ps

module ALU(
    input  wire [31:0] A,
    input  wire [31:0] B,
    input  wire [3:0]  ALUControl,

    output wire        Zero,
    output wire [31:0] Result
);

reg [31:0] ResultReg;

wire [31:0] temp;
wire [31:0] Sum;
wire        slt;
wire        sltu;

// ADD / SUB
// ALUControl[0] = 0 -> ADD
// ALUControl[0] = 1 -> SUB

assign temp = ALUControl[0] ? ~B : B;

assign Sum = A + temp + ALUControl[0];

// Comparison
assign slt  = ($signed(A) < $signed(B));
assign sltu = (A < B);

always @(*) begin
    case (ALUControl)

        4'b0000: ResultReg = Sum;                   // ADD
        4'b0001: ResultReg = Sum;                   // SUB
        4'b0010: ResultReg = A & B;                 // AND
        4'b0011: ResultReg = A | B;                 // OR
        4'b0100: ResultReg = A ^ B;                 // XOR

        4'b0101: ResultReg = {31'b0, slt};          // SLT
        4'b0110: ResultReg = {31'b0, sltu};         // SLTU

        4'b1000: ResultReg = A + B;                 // AUIPC
        4'b1001: ResultReg = B;                     // LUI

        4'b1010: ResultReg = A << B[4:0];           // SLL
        4'b1011: ResultReg = $signed(A) >>> B[4:0]; // SRA
        4'b1100: ResultReg = A >> B[4:0];           // SRL

        default: ResultReg = 32'b0;

    endcase
end

// Zero Flag

assign Zero   = (ResultReg == 32'b0);
assign Result = ResultReg;

endmodule