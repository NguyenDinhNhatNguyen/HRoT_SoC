`timescale 1ns / 1ps

// ============================================================
// RISC-V 5-Stage Pipeline Core
// IF -> ID -> EX -> MEM -> WB
//
// - Branch/Jump resolved at EX and flushes IF/ID, ID/EX
// - bus_stall freezes the global pipeline
// - Forwarding_Unit is external to RISC_Core
// - Instruction/Data Memory are currently internal
// - AXI4-Lite integration will be added later
//
// Integration notes:
// - Keep ALUResult_MEM declared only once
// - Use exact port names (Verilog is case-sensitive)
// - Current Top interface must match each Stage module
// ============================================================

module RISCV_Core(
    input         clk, rst,
    input         bus_stall,

    input [31:0]  instr_rdata,
    input [31:0]  data_rdata,

    input [1:0]   ForwardA_EX,
    input [1:0]   ForwardB_EX,

    output [31:0] instr_addr,
    output [31:0] data_wdata,
    output        data_we,
    output        data_re,

    output [31:0] PC_debug,
    output [31:0] Instr_debug,
    output        RegWrite_WB_debug,
    output [4:0]  Rd_WB_debug,
    output [31:0] Result_WB_debug
);

wire        PCSrc_EX;
wire [31:0] PCTarget_EX_out;

wire flush_IF_ID = PCSrc_EX;
wire flush_ID_EX = PCSrc_EX;

//WB feedback to ID_EX
wire        RegWrite_WB;
wire [4:0]  Rd_WB;
wire [31:0] Result_WB;

//Stage 1: IF
wire [31:0] PC_IF_out;
wire [31:0] Instr_IF_out;
wire [31:0] PC_Plus_4_IF_out;

IF_Stage u_IF_Stage(
    .clk              (clk),
    .rst              (rst),
    .stall_IF         (bus_stall),
    .flush_IF         (PCSrc_EX),
    .PCFlushTarget_EX (PCTarget_EX_out),
    .PC_IF_out        (PC_IF_out),
    .Instr_IF_out     (Instr_IF_out),
    .PC_Plus_4_IF_out (PC_Plus_4_IF_out)
);

assign instr_addr = PC_IF_out;

//Pipeline Register: IF -> ID
wire [31:0] PC_ID, Instr_ID, PC_Plus_4_ID;

IF_ID_Reg u_IF_ID_Reg(
    .clk          (clk),
    .rst          (rst),
    .stall        (bus_stall),
    .flush        (flush_IF_ID),

    .PC_IF        (PC_IF_out),
    .Instr_IF     (Instr_IF_out),
    .PC_Plus_4_IF (PC_Plus_4_IF_out),

    .PC_ID        (PC_ID),
    .Instr_ID     (Instr_ID),
    .PC_Plus_4_ID (PC_Plus_4_ID)
);

//Stage 2: ID
wire        RegWrite_ID_out, MemWrite_ID_out, MemRead_ID_out, Branch_ID_out, Jump_ID_out, Jalr_ID_out, ALUSrc_ID_out;
wire [1:0]  ResultSrc_ID_out;
wire [3:0]  ALUControl_ID_out;
wire [31:0] RD1_ID_out, RD2_ID_out, ImmExt_ID_out, PC_ID_out, PC_Plus_4_ID_out;
wire [4:0]  Rs1_ID_out, Rs2_ID_out, Rd_ID_out;
wire [2:0]  funct3_ID_out;

ID_Stage u_ID_Stage(
    .clk                (clk),
    .PC_ID              (PC_ID),
    .Instr_ID           (Instr_ID), 
    .PC_Plus_4_ID       (PC_Plus_4_ID),
        
    // WB Feedback
    .RegWrite_WB        (RegWrite_WB),
    .Result_WB          (Result_WB),
    .Rd_WB              (Rd_WB),
        
    // ID Outputs
    .RegWrite_ID_out    (RegWrite_ID_out),
    .MemWrite_ID_out    (MemWrite_ID_out),
    .MemRead_ID_out     (MemRead_ID_out),
    .Branch_ID_out      (Branch_ID_out),
    .Jump_ID_out        (Jump_ID_out),
    .Jalr_ID_out        (Jalr_ID_out),
    .ALUSrc_ID_out      (ALUSrc_ID_out),
    .ResultSrc_ID_out   (ResultSrc_ID_out),
    .ALUControl_ID_out  (ALUControl_ID_out),

    .PC_ID_out          (PC_ID_out),   
    .RD1_ID_out         (RD1_ID_out),
    .RD2_ID_out         (RD2_ID_out),
    .ImmExt_ID_out      (ImmExt_ID_out),
    .PC_Plus_4_ID_out   (PC_Plus_4_ID_out),
    .Rs1_ID_out         (Rs1_ID_out),
    .Rs2_ID_out         (Rs2_ID_out),
    .Rd_ID_out          (Rd_ID_out),
    .funct3_ID_out      (funct3_ID_out)
);

//Pipeline Register: ID -> EX
wire        RegWrite_EX, MemWrite_EX, MemRead_EX, Branch_EX, Jump_EX, Jalr_EX, ALUSrc_EX;
wire [1:0]  ResultSrc_EX;
wire [3:0]  ALUControl_EX;
wire [31:0] RD1_EX, RD2_EX, PC_EX, ImmExt_EX, PC_Plus_4_EX;
wire [4:0]  Rs1_EX, Rs2_EX, Rd_EX;
wire [2:0]  funct3_EX;

ID_EX_Reg u_ID_EX_Reg(
    .clk           (clk),
    .rst           (rst),
    .flush         (flush_ID_EX),
    .stall         (bus_stall),

    //Receive ID Stage Outputs
    .RegWrite_ID   (RegWrite_ID_out),
    .MemWrite_ID   (MemWrite_ID_out),
    .MemRead_ID    (MemRead_ID_out),
    .Branch_ID     (Branch_ID_out),
    .Jump_ID       (Jump_ID_out),
    .Jalr_ID       (Jalr_ID_out),
    .ALUSrc_ID     (ALUSrc_ID_out),
    .ResultSrc_ID  (ResultSrc_ID_out),
    .ALUControl_ID (ALUControl_ID_out),
        
    .PC_ID         (PC_ID_out),
    .RD1_ID        (RD1_ID_out),
    .RD2_ID        (RD2_ID_out),
    .ImmExt_ID     (ImmExt_ID_out),
    .PC_Plus_4_ID  (PC_Plus_4_ID_out),
        
    .Rs1_ID        (Rs1_ID_out),
    .Rs2_ID        (Rs2_ID_out),
    .Rd_ID         (Rd_ID_out),
    .funct3_ID     (funct3_ID_out),
        
    // Drive EX Wires
    .RegWrite_EX   (RegWrite_EX),
    .MemWrite_EX   (MemWrite_EX),
    .MemRead_EX    (MemRead_EX),
    .Branch_EX     (Branch_EX),
    .Jump_EX       (Jump_EX),
    .Jalr_EX       (Jalr_EX),
    .ALUSrc_EX     (ALUSrc_EX),
    .ResultSrc_EX  (ResultSrc_EX),
    .ALUControl_EX (ALUControl_EX),
        
    .PC_EX         (PC_EX),
    .RD1_EX        (RD1_EX),
    .RD2_EX        (RD2_EX),
    .ImmExt_EX     (ImmExt_EX),
    .PC_Plus_4_EX  (PC_Plus_4_EX),
        
    .Rs1_EX        (Rs1_EX),
    .Rs2_EX        (Rs2_EX),
    .Rd_EX         (Rd_EX),
    .funct3_EX     (funct3_EX)
);

//Stage 3: EX
wire        RegWrite_EX_out, MemWrite_EX_out, MemRead_EX_out;
wire [1:0]  ResultSrc_EX_out;
wire [31:0] ALUResult_EX_out, WriteData_EX_out, PC_Plus_4_EX_out;
wire [4:0]  Rd_EX_out;
wire [31:0] ALUResult_MEM;

EX_Stage u_EX_Stage(
    // Control & Data from EX Register
    .RegWrite_EX       (RegWrite_EX),
    .MemWrite_EX       (MemWrite_EX),
    .MemRead_EX        (MemRead_EX),
    .Branch_EX         (Branch_EX),
    .Jump_EX           (Jump_EX),
    .Jalr_EX           (Jalr_EX),
    .ALUSrc_EX         (ALUSrc_EX),
    .ResultSrc_EX      (ResultSrc_EX),
    .ALUControl_EX     (ALUControl_EX),
    
    .PC_EX             (PC_EX),
    .RD1_EX            (RD1_EX),
    .RD2_EX            (RD2_EX),
    .ImmExt_EX         (ImmExt_EX),
    .PC_Plus_4_EX      (PC_Plus_4_EX),
        
    .Rd_EX             (Rd_EX),
    .funct3_EX         (funct3_EX),
        
    // Forwarding
    .ForwardA_EX       (ForwardA_EX),
    .ForwardB_EX       (ForwardB_EX),
    .ALUResult_MEM     (ALUResult_MEM),
    .Result_WB         (Result_WB),
        
    // EX Outputs
    .RegWrite_EX_out   (RegWrite_EX_out),
    .MemWrite_EX_out   (MemWrite_EX_out),
    .MemRead_EX_out    (MemRead_EX_out),
    .ResultSrc_EX_out  (ResultSrc_EX_out),
        
    .ALUResult_EX_out  (ALUResult_EX_out),
    .WriteData_EX_out  (WriteData_EX_out),
    .PC_Plus_4_EX_out  (PC_Plus_4_EX_out),
    .PCTarget_EX_out   (PCTarget_EX_out),
    .Rd_EX_out         (Rd_EX_out),
        
    .PCSrc_EX          (PCSrc_EX)
);

//Pipeline Register: EX -> MEM
wire        RegWrite_MEM, MemWrite_MEM, MemRead_MEM;
wire [1:0]  ResultSrc_MEM;
wire [31:0] WriteData_MEM, PC_Plus_4_MEM, PCTarget_MEM;
wire [4:0]  Rd_MEM;

EX_MEM_Reg u_EX_MEM_Reg(
    .clk            (clk),
    .rst            (rst),
    .stall          (bus_stall),
        
    // Receive EX Stage Outputs
    .RegWrite_EX    (RegWrite_EX_out),
    .MemWrite_EX    (MemWrite_EX_out),
    .MemRead_EX     (MemRead_EX_out),
    .ResultSrc_EX   (ResultSrc_EX_out),
        
    .ALUResult_EX   (ALUResult_EX_out),
    .WriteData_EX   (WriteData_EX_out),
    .PC_Plus_4_EX   (PC_Plus_4_EX_out),
    .PCTarget_EX    (PCTarget_EX_out),
    .Rd_EX          (Rd_EX_out),
        
    // Drive MEM Wires
    .RegWrite_MEM   (RegWrite_MEM),
    .MemWrite_MEM   (MemWrite_MEM),
    .MemRead_MEM    (MemRead_MEM),
    .ResultSrc_MEM  (ResultSrc_MEM),
        
    .ALUResult_MEM  (ALUResult_MEM),
    .WriteData_MEM  (WriteData_MEM),
    .PC_Plus_4_MEM  (PC_Plus_4_MEM),
    .PCTarget_MEM   (PCTarget_MEM),
    .Rd_MEM         (Rd_MEM)
);

//Stage 4: MEM
wire        RegWrite_MEM_out;
wire [1:0]  ResultSrc_MEM_out;
wire [31:0] ALUResult_MEM_out, ReadData_MEM_out, PC_Plus_4_MEM_out, PCTarget_MEM_out;
wire [4:0]  Rd_MEM_out;

MEM_Stage u_MEM_Stage(
    .clk                (clk),
    .RegWrite_MEM       (RegWrite_MEM),
    .MemWrite_MEM       (MemWrite_MEM),
    .MemRead_MEM        (MemRead_MEM),
    .ResultSrc_MEM      (ResultSrc_MEM),
        
    .ALUResult_MEM      (ALUResult_MEM),
    .WriteData_MEM      (WriteData_MEM),
    .PC_Plus_4_MEM      (PC_Plus_4_MEM),
    .PCTarget_MEM       (PCTarget_MEM),
    .Rd_MEM             (Rd_MEM),

    // MEM Outputs
    .RegWrite_MEM_out   (RegWrite_MEM_out),
    .ResultSrc_MEM_out  (ResultSrc_MEM_out),
    .ALUResult_MEM_out  (ALUResult_MEM_out),
    .ReadData_MEM_out   (ReadData_MEM_out),
    .PC_Plus_4_MEM_out  (PC_Plus_4_MEM_out),
    .PCTarget_MEM_out   (PCTarget_MEM_out),
    .Rd_MEM_out         (Rd_MEM_out)
);

//Pipeline Register: MEM -> WB
wire [1:0]  ResultSrc_WB;
wire [31:0] ALUResult_WB, ReadData_WB, PC_Plus_4_WB, PCTarget_WB;

MEM_WB_Reg u_MEM_WB_Reg(
    .clk            (clk),
    .rst            (rst),
    .stall          (bus_stall),
        
    // Receive MEM Stage Outputs
    .RegWrite_MEM   (RegWrite_MEM_out),
    .ResultSrc_MEM  (ResultSrc_MEM_out),
    .ALUResult_MEM  (ALUResult_MEM_out),
    .ReadData_MEM   (ReadData_MEM_out),
    .PC_Plus_4_MEM  (PC_Plus_4_MEM_out),
    .PCTarget_MEM   (PCTarget_MEM_out),
    .Rd_MEM         (Rd_MEM_out),
        
    // Drive WB Wires
    .RegWrite_WB    (RegWrite_WB),
    .ResultSrc_WB   (ResultSrc_WB),
    .ALUResult_WB   (ALUResult_WB),
    .ReadData_WB    (ReadData_WB),
    .PC_Plus_4_WB   (PC_Plus_4_WB),
    .PCTarget_WB    (PCTarget_WB),
    .Rd_WB          (Rd_WB)
);

//Stage 5: WB
wire        RegWrite_WB_out;
wire [4:0]  Rd_WB_out;

WB_Stage u_WB_Stage(
    .RegWrite_WB      (RegWrite_WB),
    .ResultSrc_WB     (ResultSrc_WB),
    .ALUResult_WB     (ALUResult_WB),
    .ReadData_WB      (ReadData_WB),
    .PC_Plus_4_WB     (PC_Plus_4_WB),
    .PCTarget_WB      (PCTarget_WB),
    .Rd_WB            (Rd_WB),
        
    // WB Outputs
    .RegWrite_WB_out  (RegWrite_WB_out),
    .Rd_WB_out        (Rd_WB_out),
    .Result_WB        (Result_WB)
);

assign PC_debug        = PC_IF_out;
assign Instr_debug     = Instr_IF_out;
assign RegWrite_WB_debug = RegWrite_WB_out;
assign Rd_WB_debug       = Rd_WB_out;
assign Result_WB_debug   = Result_WB;

endmodule