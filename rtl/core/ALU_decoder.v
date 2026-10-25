`timescale 1ns / 1ps

module ALU_decoder(
    input             opb5,      // bit 5 of the opcode
    input       [2:0] funct3,    // instr[14:12]
    input             funct7b5,  // bit 30 of instruction
    input       [1:0] ALUOp,
    output reg  [3:0] ALUControl
);

wire RtypeSub;

assign RtypeSub = funct7b5 & opb5; // true for R-type SUB

always @(*) begin
    case (ALUOp)

        2'b00:
            ALUControl = 4'b0000; // add (load, store, JALR, AUIPC)

        2'b01:
            ALUControl = 4'b0001; // subtract (branch compare)

        2'b10: // R-type or I-type ALU, selected by funct3
            case (funct3)

                3'b000:
                    if (RtypeSub)
                        ALUControl = 4'b0001; // sub
                    else
                        ALUControl = 4'b0000; // add, addi

                3'b001:
                    ALUControl = 4'b1010; // sll, slli
                3'b010:
                    ALUControl = 4'b0101; // slt, slti
                3'b011:
                    ALUControl = 4'b0110; // sltu, sltiu
                3'b100:
                    ALUControl = 4'b0100; // xor, xori

                3'b101:
                    if (funct7b5)
                        ALUControl = 4'b1011; // sra, srai
                    else
                        ALUControl = 4'b1100; // srl, srli

                3'b110:
                    ALUControl = 4'b0011; // or, ori
                3'b111:
                    ALUControl = 4'b0010; // and, andi

                default:
                    ALUControl = 4'bxxxx;

            endcase

        2'b11:
            ALUControl = 4'b1001; // LUI (only LUI uses ALUOp = 11)

        default:
            ALUControl = 4'bxxxx;

        // ALUControl encoding (see ALU.v)
        // 4'b0000 = add
        // 4'b0001 = sub
        // 4'b0010 = and
        // 4'b0011 = or
        // 4'b0100 = xor
        // 4'b0101 = slt
        // 4'b0110 = sltu
        // 4'b1001 = pass B (LUI)
        // 4'b1010 = sll
        // 4'b1011 = sra
        // 4'b1100 = srl

    endcase
end

endmodule
