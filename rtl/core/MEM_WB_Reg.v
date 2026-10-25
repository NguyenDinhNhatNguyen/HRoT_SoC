`timescale 1ns / 1ps

module MEM_WB_Reg(
    input        clk,
    input        rst,
    input        stall, // Freeze MEM/WB on bus/memory stall
    // Control signals from MEM
    input        RegWrite_MEM,
    input [1:0]  ResultSrc_MEM,

    // Data signals
    input [31:0] ALUResult_MEM,
    input [31:0] ReadData_MEM,
    input [31:0] PC_Plus_4_MEM, // Link value written to rd by JAL/JALR
    input [31:0] PCTarget_MEM, // PC + imm, written to rd by AUIPC
    input [4:0]  Rd_MEM,
    // Control signals
    output reg         RegWrite_WB,
    output reg  [1:0]  ResultSrc_WB,

    // Data signals
    output reg  [31:0] ALUResult_WB,
    output reg  [31:0] ReadData_WB,
    output reg  [31:0] PC_Plus_4_WB,
    output reg  [31:0] PCTarget_WB,
    output reg  [4:0]  Rd_WB
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        // Control
        RegWrite_WB  <= 1'b0;
        ResultSrc_WB <= 2'b00;
        // Data
        ALUResult_WB <= 32'b0;
        ReadData_WB  <= 32'b0;
        PC_Plus_4_WB <= 32'b0;
        PCTarget_WB  <= 32'b0;
        Rd_WB        <= 5'b0;
    end
    else if (stall) begin
        // Hold the current MEM/WB values
    end
    else begin
        // Control
        RegWrite_WB  <= RegWrite_MEM;
        ResultSrc_WB <= ResultSrc_MEM;
        // Data
        ALUResult_WB <= ALUResult_MEM;
        ReadData_WB  <= ReadData_MEM;
        PC_Plus_4_WB <= PC_Plus_4_MEM;
        PCTarget_WB  <= PCTarget_MEM;
        Rd_WB        <= Rd_MEM;
    end
end

endmodule
