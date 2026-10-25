`timescale 1ns / 1ps

module Hazard_Detection (
    input             MemRead_EX,
    input      [4:0] Rd_EX,
    input      [4:0] Rs1_ID,
    input      [4:0] Rs2_ID,
    output reg       Stall
);
    always @(*) begin
        // Load in EX (MemRead_EX) writes a register the instruction in ID reads (Rs1_ID or Rs2_ID) -> stall
        if (MemRead_EX && (Rd_EX != 5'd0) && ((Rd_EX == Rs1_ID) || (Rd_EX == Rs2_ID)))
            Stall = 1'b1; // Freeze PC and IF/ID, insert a NOP into ID/EX
        else
            Stall = 1'b0;
    end
endmodule
