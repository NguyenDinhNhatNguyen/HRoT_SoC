`timescale 1ns / 1ps

module EX_MEM_Reg(
    input        clk, rst,
    input        stall, // [FUTURE] Freeze EX/MEM khi Bus/Memory stall
    //Control signals tu EX
    input        RegWrite_EX,
    input        MemWrite_EX,
    input        MemRead_EX,
    input [1:0]  ResultSrc_EX,
    //Data signals tu EX
    input [31:0] ALUResult_EX,
    input [31:0] WriteData_EX, //Du lieu ghi vao Data Memory cho lenh SW, gia tri nay nen la WriteData sau Forwarding.
    input [31:0] PC_Plus_4_EX, // Can cho cac lenh JAL/JALR khi ghi gia tri vao rd.
    input [31:0] PCTarget_EX, // Dia chi dich = PC + Immediate. Co the dung cho Branch/JAL/JALR va tuy thiet ke. Co the lam ket qua cho AUIPC.
    input [4:0]  Rd_EX, // Thanh ghi dich

    // Control signals 
    output reg         RegWrite_MEM,
    output reg         MemWrite_MEM,
    output reg         MemRead_MEM,
    output reg  [1:0]  ResultSrc_MEM,
    // Data signals
    output reg  [31:0] ALUResult_MEM,
    output reg  [31:0] WriteData_MEM,
    output reg  [31:0] PC_Plus_4_MEM,
    output reg  [31:0] PCTarget_MEM,
    output reg  [4:0]  Rd_MEM
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        RegWrite_MEM  <= 1'b0;
        MemWrite_MEM  <= 1'b0;
        MemRead_MEM   <= 1'b0;
        ResultSrc_MEM <= 2'b00;

        ALUResult_MEM <= 32'b0;
        WriteData_MEM <= 32'b0;
        PC_Plus_4_MEM <= 32'b0;
        PCTarget_MEM  <= 32'b0;
        Rd_MEM        <= 5'b0;   
    end
    else if (stall) begin
            // HOLD current EX/MEM values
    end
    else begin
        // Control
        RegWrite_MEM  <= RegWrite_EX;
        MemWrite_MEM  <= MemWrite_EX;
        MemRead_MEM   <= MemRead_EX;
        ResultSrc_MEM <= ResultSrc_EX;

        // Data
        ALUResult_MEM <= ALUResult_EX;
        WriteData_MEM <= WriteData_EX;
        PC_Plus_4_MEM <= PC_Plus_4_EX;
        Rd_MEM        <= Rd_EX;
        
        PCTarget_MEM  <= PCTarget_EX;
    end
end

endmodule