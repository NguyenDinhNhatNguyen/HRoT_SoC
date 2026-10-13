`timescale 1ns / 1ps

module Branch_Unit(
    input       Branch,
    input       Jump,
    input       Jalr,
    input [2:0] funct3,
    input       Zero,
    input       lt,
    input       ltu,
    output      PCSrc
);

reg take_branch;

always @(*) begin
    case (funct3)
        3'b000: take_branch = Zero;   //BEQ
        3'b001: take_branch = ~Zero;  // BNE
        3'b100: take_branch = lt;     // BLT
        3'b101: take_branch = ~lt;    // BGE
        3'b110: take_branch = ltu;    // BLTU
        3'b111: take_branch = ~ltu;   // BGEU
        default: take_branch = 1'b0;
    endcase
end

assign PCSrc = (Branch && take_branch) || Jump || Jalr;

endmodule