`timescale 1ns / 1ps

module IF_ID_Reg(
    input             clk, rst,
    input             stall,
    input             flush, // Drop the wrong-path instruction on a taken branch/jump (insert NOP)

    input      [31:0] PC_IF,
    input      [31:0] Instr_IF,
    input      [31:0] PC_Plus_4_IF,

    output reg [31:0] PC_ID,
    output reg [31:0] Instr_ID,
    output reg [31:0] PC_Plus_4_ID
);

always @(posedge clk) begin // synchronous reset: rst || flush on an async edge fails Quartus (error 10200)
    if (rst || flush) begin
        PC_ID        <= 32'b0;
        Instr_ID     <= 32'h00000013; // NOP (addi x0, x0, 0)
        PC_Plus_4_ID <= 32'b0;
    end
    else if (!stall) begin
        PC_ID        <= PC_IF;
        Instr_ID     <= Instr_IF;
        PC_Plus_4_ID <= PC_Plus_4_IF;
    end
    // else: stall = 1 -> hold the current values (ID stage frozen)
end

endmodule
