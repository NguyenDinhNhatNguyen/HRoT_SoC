`timescale 1ns / 1ps

module IF_ID_Reg(
    input             clk, rst,
    input             stall,
    input             flush, // Flush: Xoa lenh rac khi re nhanh (chen NOP)

    input      [31:0] PC_IF,
    input      [31:0] Instr_IF,
    input      [31:0] PC_Plus_4_IF,

    output reg [31:0] PC_ID,
    output reg [31:0] Instr_ID,
    output reg [31:0] PC_Plus_4_ID
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        PC_ID        <= 32'b0;
        Instr_ID     <= 32'h00000013; //Lenh NOP
        PC_Plus_4_ID <= 32'b0;
    end
    else if (flush) begin
        PC_ID <= 32'b0;
        Instr_ID <= 32'h00000013; //Chen NOP khi re nhanh sai
        PC_Plus_4_ID <= 32'b0;
        end
        else if (!stall) begin
            PC_ID <= PC_IF;
            Instr_ID <= Instr_IF;
            PC_Plus_4_ID <= PC_Plus_4_IF;
        end
        // else: stall = 1 -> Giu nguyen gia tri cu (dong bang tang ID)
end

endmodule