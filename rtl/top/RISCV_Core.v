`timescale 1ns / 1ps

// RISC-V 5-Stage Pipeline Core
// IF -> ID -> EX -> MEM -> WB
//
// - Branch/Jump resolved at EX and flushes IF/ID, ID/EX
// - bus_stall freezes the global pipeline
// - Forwarding_Unit and Hazard_Detection are integrated inside RISCV_Core
// - Instruction and data memories sit outside the core:
//     instr_rdata must be valid before the next rising edge after instr_addr changes
//     data_rdata must be valid before the next rising edge after data_addr changes, otherwise hold bus_stall = 1
//     (the SoC memories read synchronously on the falling edge, so the core still sees the data in the same cycle)
// - Byte/half load and store: data_wstrb selects the byte lanes, MEM_Stage sign- or zero-extends loads
// - Zicsr and machine-mode traps (P-09): CSR_Unit works on the instruction in MEM. CSR results arrive
//   late like loads, so a dependent instruction waits one cycle (load-use stall). Interrupt inputs
//   irq_timer and irq_ext follow I-01: level-high, synchronous to clk, held until the source clears them
//
// Integration notes:
// - Keep ALUResult_MEM declared only once
// - Use exact port names (Verilog is case-sensitive)
// - Current Top interface must match each Stage module

module RISCV_Core(
    input         clk, rst,
    input         bus_stall,

    // Interrupt lines (I-01) -> mip.MTIP (bit 7) / mip.MEIP (bit 11), MEI before MTI
    input         irq_timer,
    input         irq_ext,

    input  [31:0] instr_rdata,
    output [31:0] instr_addr,

    input  [31:0] data_rdata,
    output [31:0] data_addr,
    output [31:0] data_wdata,
    output [3:0]  data_wstrb,
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

wire        LoadUseStall;
wire        PipelineStall;

assign PipelineStall = bus_stall | LoadUseStall;

wire flush_IF_ID;
wire flush_ID_EX;

// Trap or MRET in MEM (CSR_Unit, already gated by bus_stall) wins over a branch resolving in EX
wire        trap_redirect;
wire [31:0] trap_target;
wire        redirect_any = PCSrc_EX | trap_redirect;
wire [31:0] redirect_pc  = trap_redirect ? trap_target : PCTarget_EX_out;

assign flush_IF_ID = redirect_any & ~bus_stall;
assign flush_ID_EX = (redirect_any | LoadUseStall) & ~bus_stall;

// WB feedback to ID_EX
wire        RegWrite_WB;
wire [4:0]  Rd_WB;
wire [31:0] Result_WB;

// Stage 1: IF
wire [31:0] PC_IF_out;
wire [31:0] Instr_IF_out;
wire [31:0] PC_Plus_4_IF_out;

IF_Stage u_IF_Stage(
    .clk              (clk),
    .rst              (rst),
    .stall_IF         (PipelineStall),
    .flush_IF         (flush_IF_ID),
    .PCFlushTarget_EX (redirect_pc),
    // ROM
    .instr_addr       (instr_addr),
    .instr_rdata      (instr_rdata),

    .PC_IF_out        (PC_IF_out),
    .Instr_IF_out     (Instr_IF_out),
    .PC_Plus_4_IF_out (PC_Plus_4_IF_out)
);

// Pipeline Register: IF -> ID
wire [31:0] PC_ID, Instr_ID, PC_Plus_4_ID;

IF_ID_Reg u_IF_ID_Reg(
    .clk          (clk),
    .rst          (rst),
    .stall        (PipelineStall),
    .flush        (flush_IF_ID),

    .PC_IF        (PC_IF_out),
    .Instr_IF     (Instr_IF_out),
    .PC_Plus_4_IF (PC_Plus_4_IF_out),

    .PC_ID        (PC_ID),
    .Instr_ID     (Instr_ID),
    .PC_Plus_4_ID (PC_Plus_4_ID)
);

// Valid bit of the instruction in ID (0 for reset and flush bubbles)
wire valid_ID;

Pipe_Reg #(.W(1)) u_valid_IF_ID(
    .clk   (clk),
    .rst   (rst),
    .flush (flush_IF_ID),
    .stall (PipelineStall),
    .d     (1'b1),
    .q     (valid_ID)
);

// Stage 2: ID
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

// SYSTEM decode and illegal-instruction check. An illegal instruction keeps no side effect,
// it only raises the trap when it reaches MEM
wire        csr_op_ID, csr_imm_ID, csr_we_ID, ecall_ID, ebreak_ID, mret_ID, illegal_ID;
wire [1:0]  csr_cmd_ID;

Sys_Decoder u_Sys_Decoder(
    .Instr   (Instr_ID),
    .csr_op  (csr_op_ID),
    .csr_imm (csr_imm_ID),
    .csr_cmd (csr_cmd_ID),
    .csr_we  (csr_we_ID),
    .ecall   (ecall_ID),
    .ebreak  (ebreak_ID),
    .mret    (mret_ID),
    .illegal (illegal_ID)
);

wire RegWrite_ID_fin = (RegWrite_ID_out | csr_op_ID) & ~illegal_ID;
wire MemWrite_ID_fin = MemWrite_ID_out & ~illegal_ID;
wire MemRead_ID_fin  = MemRead_ID_out & ~illegal_ID;
wire Branch_ID_fin   = Branch_ID_out & ~illegal_ID;
wire Jump_ID_fin     = Jump_ID_out & ~illegal_ID;
wire Jalr_ID_fin     = Jalr_ID_out & ~illegal_ID;

// Pipeline Register: ID -> EX
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

    // Receive ID Stage Outputs
    .RegWrite_ID   (RegWrite_ID_fin),
    .MemWrite_ID   (MemWrite_ID_fin),
    .MemRead_ID    (MemRead_ID_fin),
    .Branch_ID     (Branch_ID_fin),
    .Jump_ID       (Jump_ID_fin),
    .Jalr_ID       (Jalr_ID_fin),
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

// Sideband ID -> EX: {valid, csr_op, csr_imm, csr_cmd, csr_we, ecall, ebreak, mret, illegal, csr_addr}
wire        valid_EX, csr_op_EX, csr_imm_EX, csr_we_EX, ecall_EX, ebreak_EX, mret_EX, illegal_EX;
wire [1:0]  csr_cmd_EX;
wire [11:0] csr_addr_EX;

Pipe_Reg #(.W(22)) u_sys_ID_EX(
    .clk   (clk),
    .rst   (rst),
    .flush (flush_ID_EX),
    .stall (bus_stall),
    .d     ({valid_ID, csr_op_ID, csr_imm_ID, csr_cmd_ID, csr_we_ID, ecall_ID, ebreak_ID, mret_ID, illegal_ID, Instr_ID[31:20]}),
    .q     ({valid_EX, csr_op_EX, csr_imm_EX, csr_cmd_EX, csr_we_EX, ecall_EX, ebreak_EX, mret_EX, illegal_EX, csr_addr_EX})
);

// Hazard Detection: Load-Use
// Only check Rs1/Rs2 when the instruction in ID really reads them (no false stall on LUI/AUIPC/JAL)
wire [6:0] opcode_ID = Instr_ID[6:0];
wire uses_rs1_ID = (opcode_ID != 7'b0110111) &&   // LUI
                   (opcode_ID != 7'b0010111) &&   // AUIPC
                   (opcode_ID != 7'b1101111);     // JAL
wire uses_rs2_ID = (opcode_ID == 7'b0110011) ||   // R-type
                   (opcode_ID == 7'b0100011) ||   // Store
                   (opcode_ID == 7'b1100011);     // Branch

// Hazard Detection: Load-Use
// A CSR instruction gives its result in MEM, so it stalls a dependent instruction like a load
Hazard_Detection u_Hazard_Detection(
    .MemRead_EX (MemRead_EX | csr_op_EX),
    .Rd_EX      (Rd_EX),
    .Rs1_ID     (uses_rs1_ID ? Rs1_ID_out : 5'd0),
    .Rs2_ID     (uses_rs2_ID ? Rs2_ID_out : 5'd0),
    .Stall      (LoadUseStall)
);

// Forwarding select, declared before EX_Stage uses it
wire [1:0] ForwardA_EX_internal;
wire [1:0] ForwardB_EX_internal;

// Stage 3: EX
wire        RegWrite_EX_out, MemWrite_EX_out, MemRead_EX_out;
wire [1:0]  ResultSrc_EX_out;
wire [31:0] ALUResult_EX_out, WriteData_EX_out, PC_Plus_4_EX_out, SrcA_EX_out;
wire [4:0]  Rd_EX_out;
wire [31:0] ALUResult_MEM;
reg  [31:0] ForwardResult_MEM;

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
    .ForwardA_EX       (ForwardA_EX_internal),
    .ForwardB_EX       (ForwardB_EX_internal),
    .ALUResult_MEM     (ForwardResult_MEM),
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

    .PCSrc_EX          (PCSrc_EX),
    .SrcA_EX_out       (SrcA_EX_out)
);

// CSR instructions carry their write operand (rs1 or zimm) to MEM in the ALU result slot
wire [31:0] ExResult_EX = csr_op_EX ? (csr_imm_EX ? {27'b0, Rs1_EX} : SrcA_EX_out) : ALUResult_EX_out;

// Pipeline Register: EX -> MEM
wire        RegWrite_MEM, MemWrite_MEM, MemRead_MEM;
wire [1:0]  ResultSrc_MEM;
wire [31:0] WriteData_MEM, PC_Plus_4_MEM, PCTarget_MEM;
wire [4:0]  Rd_MEM;
wire [2:0]  funct3_MEM;

EX_MEM_Reg u_EX_MEM_Reg(
    .clk            (clk),
    .rst            (rst),
    .stall          (bus_stall),

    // Receive EX Stage Outputs
    // A trap or MRET in MEM turns the instruction leaving EX into a bubble
    .RegWrite_EX    (RegWrite_EX_out & ~trap_redirect),
    .MemWrite_EX    (MemWrite_EX_out & ~trap_redirect),
    .MemRead_EX     (MemRead_EX_out & ~trap_redirect),
    .ResultSrc_EX   (ResultSrc_EX_out),

    .ALUResult_EX   (ExResult_EX),
    .WriteData_EX   (WriteData_EX_out),
    .PC_Plus_4_EX   (PC_Plus_4_EX_out),
    .PCTarget_EX    (PCTarget_EX_out),
    .Rd_EX          (Rd_EX_out),
    .funct3_EX      (funct3_EX),

    // Drive MEM Wires
    .RegWrite_MEM   (RegWrite_MEM),
    .MemWrite_MEM   (MemWrite_MEM),
    .MemRead_MEM    (MemRead_MEM),
    .ResultSrc_MEM  (ResultSrc_MEM),

    .ALUResult_MEM  (ALUResult_MEM),
    .WriteData_MEM  (WriteData_MEM),
    .PC_Plus_4_MEM  (PC_Plus_4_MEM),
    .PCTarget_MEM   (PCTarget_MEM),
    .Rd_MEM         (Rd_MEM),
    .funct3_MEM     (funct3_MEM)
);

// Sideband EX -> MEM: {valid, csr_op, csr_cmd, csr_we, ecall, ebreak, mret, illegal, csr_addr, PC[31:2]}
wire        valid_MEM, csr_op_MEM, csr_we_MEM, ecall_MEM, ebreak_MEM, mret_MEM, illegal_MEM;
wire [1:0]  csr_cmd_MEM;
wire [11:0] csr_addr_MEM;
wire [31:2] PC_MEM;

Pipe_Reg #(.W(51)) u_sys_EX_MEM(
    .clk   (clk),
    .rst   (rst),
    .flush (trap_redirect),
    .stall (bus_stall),
    .d     ({valid_EX, csr_op_EX, csr_cmd_EX, csr_we_EX, ecall_EX, ebreak_EX, mret_EX, illegal_EX, csr_addr_EX, PC_EX[31:2]}),
    .q     ({valid_MEM, csr_op_MEM, csr_cmd_MEM, csr_we_MEM, ecall_MEM, ebreak_MEM, mret_MEM, illegal_MEM, csr_addr_MEM, PC_MEM})
);

// Forwarding Unit: MEM has priority over WB
Forwarding_Unit u_Forwarding_Unit(
    .Rs1_EX       (Rs1_EX),
    .Rs2_EX       (Rs2_EX),
    .Rd_MEM       (Rd_MEM),
    .Rd_WB        (Rd_WB),
    .RegWrite_MEM (RegWrite_MEM),
    .RegWrite_WB  (RegWrite_WB),
    .ForwardA     (ForwardA_EX_internal),
    .ForwardB     (ForwardB_EX_internal)
);

// MEM stage outputs (declared before the forwarding mux below uses them)
wire        RegWrite_MEM_out;
wire [1:0]  ResultSrc_MEM_out;
wire [31:0] ALUResult_MEM_out, ReadData_MEM_out, PC_Plus_4_MEM_out, PCTarget_MEM_out;
wire [4:0]  Rd_MEM_out;

always @(*) begin
    case (ResultSrc_MEM_out)
        2'b00:
            ForwardResult_MEM = ALUResult_MEM_out;
        2'b01:
            ForwardResult_MEM = ALUResult_MEM_out; // Load: wait for WB (load-use already stalled)
        2'b10:
            ForwardResult_MEM = PC_Plus_4_MEM_out;
        2'b11:
            ForwardResult_MEM = PCTarget_MEM_out;
        default:
            ForwardResult_MEM = 32'b0;
    endcase
end

// Stage 4: MEM
MEM_Stage u_MEM_Stage(
    .RegWrite_MEM       (RegWrite_MEM),
    .MemWrite_MEM       (MemWrite_MEM),
    .MemRead_MEM        (MemRead_MEM),
    .ResultSrc_MEM      (ResultSrc_MEM),

    .ALUResult_MEM      (ALUResult_MEM),
    .WriteData_MEM      (WriteData_MEM),
    .PC_Plus_4_MEM      (PC_Plus_4_MEM),
    .PCTarget_MEM       (PCTarget_MEM),
    .Rd_MEM             (Rd_MEM),
    .funct3_MEM         (funct3_MEM),
    // AXI
    .data_rdata         (data_rdata),
    .data_addr          (data_addr),
    .data_wdata         (data_wdata),
    .data_wstrb         (data_wstrb),
    .data_we            (data_we),
    .data_re            (data_re),
    // MEM Outputs
    .RegWrite_MEM_out   (RegWrite_MEM_out),
    .ResultSrc_MEM_out  (ResultSrc_MEM_out),
    .ALUResult_MEM_out  (ALUResult_MEM_out),
    .ReadData_MEM_out   (ReadData_MEM_out),
    .PC_Plus_4_MEM_out  (PC_Plus_4_MEM_out),
    .PCTarget_MEM_out   (PCTarget_MEM_out),
    .Rd_MEM_out         (Rd_MEM_out)
);

// CSRs and traps on the instruction in MEM
wire        trap_kill;
wire [31:0] csr_rdata;

CSR_Unit u_CSR_Unit(
    .clk        (clk),
    .rst        (rst),
    .stall      (bus_stall),
    .valid      (valid_MEM),
    .mem_access (MemRead_MEM | MemWrite_MEM),
    .csr_op     (csr_op_MEM),
    .csr_cmd    (csr_cmd_MEM),
    .csr_we     (csr_we_MEM),
    .csr_addr   (csr_addr_MEM),
    .csr_wdata  (ALUResult_MEM),
    .ecall      (ecall_MEM),
    .ebreak     (ebreak_MEM),
    .mret       (mret_MEM),
    .illegal    (illegal_MEM),
    .pc         (PC_MEM),
    .irq_timer  (irq_timer),
    .irq_ext    (irq_ext),
    .csr_rdata  (csr_rdata),
    .kill       (trap_kill),
    .redirect   (trap_redirect),
    .target     (trap_target)
);

// Pipeline Register: MEM -> WB
wire [1:0]  ResultSrc_WB;
wire [31:0] ALUResult_WB, ReadData_WB, PC_Plus_4_WB, PCTarget_WB;

MEM_WB_Reg u_MEM_WB_Reg(
    .clk            (clk),
    .rst            (rst),
    .stall          (bus_stall),

    // Receive MEM Stage Outputs
    .RegWrite_MEM   (RegWrite_MEM_out & ~trap_kill),
    .ResultSrc_MEM  (ResultSrc_MEM_out),
    .ALUResult_MEM  (csr_op_MEM ? csr_rdata : ALUResult_MEM_out),
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

// Stage 5: WB
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

assign PC_debug          = PC_IF_out;
assign Instr_debug       = Instr_IF_out;
assign RegWrite_WB_debug = RegWrite_WB_out;
assign Rd_WB_debug       = Rd_WB_out;
assign Result_WB_debug   = Result_WB;

endmodule
