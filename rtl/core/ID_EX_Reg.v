`timescale 1ns / 1ps

module ID_EX_Reg(
    input        clk, rst,
    input        flush,
    input        stall, // [FUTURE] Freeze ID/EX khi Bus/Memory stall    
    //Control signal tu ID
    input        RegWrite_ID,
    input        MemWrite_ID,
    input        MemRead_ID,
    input        Branch_ID,
    input        Jump_ID,
    input        Jalr_ID,
    input        ALUSrc_ID,
    input [1:0]  ResultSrc_ID,
    input [3:0]  ALUControl_ID,
    //Data tu ID
    input [31:0] PC_ID,
    input [31:0] RD1_ID,
    input [31:0] RD2_ID,
    input [31:0] ImmExt_ID,
    input [31:0] PC_Plus_4_ID,
    //Register information tu ID
    input [4:0]  Rs1_ID,
    input [4:0]  Rs2_ID,
    input [4:0]  Rd_ID,
    input [2:0]  funct3_ID,

    // Control signals sang EX
    output reg         RegWrite_EX,
    output reg         MemWrite_EX,
    output reg         MemRead_EX,
    output reg         Branch_EX,
    output reg         Jump_EX,
    output reg         Jalr_EX,
    output reg         ALUSrc_EX,
    output reg  [1:0]  ResultSrc_EX,
    output reg  [3:0]  ALUControl_EX,
    // Data sang EX
    output reg [31:0]  PC_EX,
    output reg [31:0]  RD1_EX,
    output reg [31:0]  RD2_EX,
    output reg [31:0]  ImmExt_EX,
    output reg [31:0]  PC_Plus_4_EX,
    // Register information sang EX
    output reg [4:0]   Rs1_EX,
    output reg [4:0]   Rs2_EX,
    output reg [4:0]   Rd_EX,
    output reg [2:0]   funct3_EX
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        // Control signals
        RegWrite_EX   <= 1'b0;
        MemWrite_EX   <= 1'b0;
        MemRead_EX    <= 1'b0;
        Branch_EX     <= 1'b0;
        Jump_EX       <= 1'b0;
        Jalr_EX       <= 1'b0;
        ALUSrc_EX     <= 1'b0;
        ResultSrc_EX  <= 2'b00;
        ALUControl_EX <= 4'b0000;
        // Data
        PC_EX         <= 32'b0;
        RD1_EX        <= 32'b0;
        RD2_EX        <= 32'b0;
        ImmExt_EX     <= 32'b0;
        PC_Plus_4_EX  <= 32'b0;
        // Register information
        Rs1_EX        <= 5'b0;
        Rs2_EX        <= 5'b0;
        Rd_EX         <= 5'b0;
        funct3_EX     <= 3'b0;
    end
    else if (flush) begin
            // Control signals
            RegWrite_EX   <= 1'b0;
            MemWrite_EX   <= 1'b0;
            MemRead_EX    <= 1'b0;
            Branch_EX     <= 1'b0;
            Jump_EX       <= 1'b0;
            Jalr_EX       <= 1'b0;
            ALUSrc_EX     <= 1'b0;
            ResultSrc_EX  <= 2'b00;
            ALUControl_EX <= 4'b0000;

            // Data
            PC_EX         <= 32'b0;
            RD1_EX        <= 32'b0;
            RD2_EX        <= 32'b0;
            ImmExt_EX     <= 32'b0;
            PC_Plus_4_EX  <= 32'b0;

            // Register information
            Rs1_EX        <= 5'b0;
            Rs2_EX        <= 5'b0;
            Rd_EX         <= 5'b0;
            funct3_EX     <= 3'b0;
        end
        else if (stall) begin
            // HOLD current ID/EX values
        end
        else begin
            // Control signals
            RegWrite_EX   <= RegWrite_ID;
            MemWrite_EX   <= MemWrite_ID;
            MemRead_EX    <= MemRead_ID;
            Branch_EX     <= Branch_ID;
            Jump_EX       <= Jump_ID;
            Jalr_EX       <= Jalr_ID;
            ALUSrc_EX     <= ALUSrc_ID;
            ResultSrc_EX  <= ResultSrc_ID;
            ALUControl_EX <= ALUControl_ID;
            // Data
            PC_EX         <= PC_ID;
            RD1_EX        <= RD1_ID;
            RD2_EX        <= RD2_ID;
            ImmExt_EX     <= ImmExt_ID;
            PC_Plus_4_EX  <= PC_Plus_4_ID;
            // Register information
            Rs1_EX        <= Rs1_ID;
            Rs2_EX        <= Rs2_ID;
            Rd_EX         <= Rd_ID;
            funct3_EX     <= funct3_ID;
        end
end

endmodule