`timescale 1ns / 1ps

module Forwarding_Unit (
    input      [4:0] Rs1_EX,
    input      [4:0] Rs2_EX,
    input      [4:0] Rd_MEM,
    input      [4:0] Rd_WB,
    input            RegWrite_MEM,
    input            RegWrite_WB,
    output reg [1:0] ForwardA,
    output reg [1:0] ForwardB
);
    always @(*) begin
        // Default: no forwarding
        ForwardA = 2'b00;
        ForwardB = 2'b00;

        // Forward A for Rs1_EX (operand 1)
        if (RegWrite_MEM && (Rd_MEM != 0) && (Rd_MEM == Rs1_EX))
            ForwardA = 2'b10; // Forward from MEM
        else if (RegWrite_WB && (Rd_WB != 0) && (Rd_WB == Rs1_EX))
            ForwardA = 2'b01; // Forward from WB

        // Forward B for Rs2_EX (operand 2), same priority: MEM before WB
        if (RegWrite_MEM && (Rd_MEM != 0) && (Rd_MEM == Rs2_EX))
            ForwardB = 2'b10;
        else if (RegWrite_WB && (Rd_WB != 0) && (Rd_WB == Rs2_EX))
            ForwardB = 2'b01;
    end
endmodule
