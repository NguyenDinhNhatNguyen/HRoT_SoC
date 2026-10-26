`timescale 1ns / 1ps

// Decodes the SYSTEM opcode (Zicsr, ECALL, EBREAK, MRET, WFI) and flags illegal instructions.
// Main_Decoder still drives the normal control signals. RISCV_Core uses these outputs to
// turn on RegWrite for CSR instructions and to cancel every side effect of an illegal one.
module Sys_Decoder(
    input  [31:0] Instr,

    output        csr_op,     // CSRRW/CSRRS/CSRRC and the immediate forms
    output        csr_imm,    // operand is the zero-extended rs1 field (zimm)
    output [1:0]  csr_cmd,    // 01 write, 10 set bits, 11 clear bits (funct3[1:0])
    output        csr_we,     // the instruction writes the CSR (CSRRS/CSRRC with rs1 = 0 only read)
    output        ecall,
    output        ebreak,
    output        mret,
    output        illegal
);

wire [6:0] op = Instr[6:0];
wire [2:0] f3 = Instr[14:12];
wire [6:0] f7 = Instr[31:25];

localparam [31:0] ECALL  = 32'h0000_0073;
localparam [31:0] EBREAK = 32'h0010_0073;
localparam [31:0] MRET   = 32'h3020_0073;
localparam [31:0] WFI    = 32'h1050_0073;

wire is_system = (op == 7'b1110011);

assign csr_op  = is_system && (f3[1:0] != 2'b00);
assign csr_imm = f3[2];
assign csr_cmd = f3[1:0];
assign csr_we  = csr_op && ((f3[1:0] == 2'b01) || (Instr[19:15] != 5'd0));
assign ecall   = (Instr == ECALL);
assign ebreak  = (Instr == EBREAK);
assign mret    = (Instr == MRET);

reg legal;
always @(*) begin
    case (op)
        7'b0110111, 7'b0010111, 7'b1101111:                        // LUI, AUIPC, JAL
            legal = 1'b1;
        7'b1100111:                                                 // JALR
            legal = (f3 == 3'b000);
        7'b1100011:                                                 // branches
            legal = (f3 != 3'b010) && (f3 != 3'b011);
        7'b0000011:                                                 // LB LH LW LBU LHU
            legal = (f3 == 3'b000) || (f3 == 3'b001) || (f3 == 3'b010) || (f3 == 3'b100) || (f3 == 3'b101);
        7'b0100011:                                                 // SB SH SW
            legal = (f3 == 3'b000) || (f3 == 3'b001) || (f3 == 3'b010);
        7'b0010011:                                                 // OP-IMM, shift amounts need a clean funct7
            if (f3 == 3'b001)
                legal = (f7 == 7'b0000000);
            else if (f3 == 3'b101)
                legal = (f7 == 7'b0000000) || (f7 == 7'b0100000);
            else
                legal = 1'b1;
        7'b0110011:                                                 // OP, only SUB and SRA use funct7 = 0100000
            legal = (f7 == 7'b0000000) || ((f7 == 7'b0100000) && ((f3 == 3'b000) || (f3 == 3'b101)));
        7'b0001111:                                                 // FENCE, FENCE.I run as NOP
            legal = (f3 == 3'b000) || (f3 == 3'b001);
        7'b1110011:                                                 // SYSTEM
            if (f3 == 3'b000)
                legal = (Instr == ECALL) || (Instr == EBREAK) || (Instr == MRET) || (Instr == WFI);
            else
                legal = (f3 != 3'b100);
        default:
            legal = 1'b0;
    endcase
end

assign illegal = !legal;

endmodule
