`timescale 1ns / 1ps

module PC(
    input           clk, rst,
    // Pipeline control
    input           stall,          // Freeze the PC (load-use hazard or bus stall)
    input           flush,          // Redirect the PC (branch/jump resolved in EX)
    input   [31:0]  PCNext,
    input   [31:0]  PCflush_target, // Target address on flush (from EX)
    output  [31:0]  PC
);

reg [31:0] PCReg;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        PCReg <= 32'h0000_0000;
    end
    else if (flush) begin
        PCReg <= PCflush_target;            // Priority 1: branch/jump target
    end
    else if (!stall) begin
        PCReg <= PCNext;                    // Priority 2: next sequential instruction
    end
    // else: hold PCReg while stall = 1
end

assign PC = PCReg;

endmodule
