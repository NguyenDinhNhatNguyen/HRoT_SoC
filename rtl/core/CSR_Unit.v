`timescale 1ns / 1ps

// Machine-mode CSRs and trap control (Zicsr + M-mode traps, P-09). Works on the instruction in MEM,
// so every older instruction has already finished and every younger one can still be cancelled.
//
// CSRs: mstatus (MIE, MPIE, MPP reads 11), misa (RV32I, read-only), mie (MTIE, MEIE), mip (MTIP, MEIP,
// read-only, straight from irq_timer/irq_ext), mtvec (direct mode only), mscratch, mepc, mcause, mtval,
// mvendorid/marchid/mimpid/mhartid (read 0). Any other CSR, or a write to a read-only CSR, is illegal.
//
// Traps, taken only when the bus is not stalled:
//   - interrupt (I-01): mstatus.MIE and an enabled pending line, MEI before MTI. Only taken on a valid
//     instruction that does not access memory, so no bus transfer is ever cut or repeated. The
//     instruction in MEM is cancelled and mepc points at it
//   - illegal instruction (mcause 2), EBREAK (3), ECALL from M-mode (11), mtval = 0
// MRET jumps to mepc and restores MIE from MPIE.
// Access fault through data_err (mcause 5/7, I-01) is not in this version (planned after P-09).
module CSR_Unit(
    input             clk, rst,
    input             stall,          // bus_stall: the pipeline is frozen

    // Instruction in MEM
    input             valid,
    input             mem_access,     // MemRead or MemWrite
    input             csr_op,
    input      [1:0]  csr_cmd,
    input             csr_we,
    input      [11:0] csr_addr,
    input      [31:0] csr_wdata,      // rs1 value or zimm, computed in EX
    input             ecall,
    input             ebreak,
    input             mret,
    input             illegal,
    input      [31:2] pc,             // word address of the instruction (mepc)

    // Interrupt lines (I-01): level, synchronous to clk, held until the source clears them
    input             irq_timer,
    input             irq_ext,

    output reg [31:0] csr_rdata,
    output            kill,           // cancel the instruction in MEM (no register write)
    output            redirect,       // flush IF, ID, EX and load the PC with target
    output     [31:0] target
);

localparam [11:0] A_MSTATUS   = 12'h300;
localparam [11:0] A_MISA      = 12'h301;
localparam [11:0] A_MIE       = 12'h304;
localparam [11:0] A_MTVEC     = 12'h305;
localparam [11:0] A_MSCRATCH  = 12'h340;
localparam [11:0] A_MEPC      = 12'h341;
localparam [11:0] A_MCAUSE    = 12'h342;
localparam [11:0] A_MTVAL     = 12'h343;
localparam [11:0] A_MIP       = 12'h344;
localparam [11:0] A_MVENDORID = 12'hF11;
localparam [11:0] A_MARCHID   = 12'hF12;
localparam [11:0] A_MIMPID    = 12'hF13;
localparam [11:0] A_MHARTID   = 12'hF14;

localparam [31:0] MISA_RV32I  = 32'h4000_0100;   // MXL = 1 (32-bit), extension I

reg        mstatus_mie;
reg        mstatus_mpie;
reg        mie_mtie;
reg        mie_meie;
reg [29:0] mtvec_base;
reg [31:0] mscratch;
reg [29:0] mepc_q;
reg [31:0] mcause;
reg [31:0] mtval;

wire [31:0] mstatus = {19'b0, 2'b11, 3'b0, mstatus_mpie, 3'b0, mstatus_mie, 3'b0};
wire [31:0] mie     = {20'b0, mie_meie, 3'b0, mie_mtie, 7'b0};
wire [31:0] mip     = {20'b0, irq_ext, 3'b0, irq_timer, 7'b0};

// CSR read and address check
reg known;
always @(*) begin
    known = 1'b1;
    case (csr_addr)
        A_MSTATUS:
            csr_rdata = mstatus;
        A_MISA:
            csr_rdata = MISA_RV32I;
        A_MIE:
            csr_rdata = mie;
        A_MTVEC:
            csr_rdata = {mtvec_base, 2'b00};
        A_MSCRATCH:
            csr_rdata = mscratch;
        A_MEPC:
            csr_rdata = {mepc_q, 2'b00};
        A_MCAUSE:
            csr_rdata = mcause;
        A_MTVAL:
            csr_rdata = mtval;
        A_MIP:
            csr_rdata = mip;
        A_MVENDORID, A_MARCHID, A_MIMPID, A_MHARTID:
            csr_rdata = 32'b0;
        default:
        begin
            csr_rdata = 32'b0;
            known     = 1'b0;
        end
    endcase
end

// Addresses 0xCxx-0xFxx are read-only by encoding (csr_addr[11:10] == 11)
wire csr_bad = csr_op && (!known || (csr_we && (csr_addr[11:10] == 2'b11)));

// New value for CSRRW / CSRRS / CSRRC
reg [31:0] csr_new;
always @(*) begin
    case (csr_cmd)
        2'b01:
            csr_new = csr_wdata;
        2'b10:
            csr_new = csr_rdata | csr_wdata;
        2'b11:
            csr_new = csr_rdata & ~csr_wdata;
        default:
            csr_new = csr_rdata;
    endcase
end

// Trap decision
wire meip      = irq_ext & mie_meie;
wire mtip      = irq_timer & mie_mtie;
wire take_irq  = !stall && valid && !mem_access && mstatus_mie && (meip || mtip);
wire take_exc  = !stall && valid && !take_irq && (illegal || csr_bad || ecall || ebreak);
wire take_mret = !stall && valid && !take_irq && !take_exc && mret;
wire do_csr_wr = !stall && valid && !take_irq && !take_exc && csr_op && csr_we;

reg [31:0] cause;
always @(*) begin
    if (take_irq)
        cause = meip ? 32'h8000_000B : 32'h8000_0007;
    else if (illegal || csr_bad)
        cause = 32'd2;
    else if (ebreak)
        cause = 32'd3;
    else
        cause = 32'd11;
end

assign kill     = take_irq || take_exc;
assign redirect = take_irq || take_exc || take_mret;
assign target   = take_mret ? {mepc_q, 2'b00} : {mtvec_base, 2'b00};

always @(posedge clk) begin
    if (rst) begin
        mstatus_mie  <= 1'b0;
        mstatus_mpie <= 1'b0;
        mie_mtie     <= 1'b0;
        mie_meie     <= 1'b0;
        mtvec_base   <= 30'b0;
        mscratch     <= 32'b0;
        mepc_q       <= 30'b0;
        mcause       <= 32'b0;
        mtval        <= 32'b0;
    end
    else if (take_irq || take_exc) begin
        mepc_q       <= pc;
        mcause       <= cause;
        mtval        <= 32'b0;
        mstatus_mpie <= mstatus_mie;
        mstatus_mie  <= 1'b0;
    end
    else if (take_mret) begin
        mstatus_mie  <= mstatus_mpie;
        mstatus_mpie <= 1'b1;
    end
    else if (do_csr_wr) begin
        case (csr_addr)
            A_MSTATUS:
            begin
                mstatus_mie  <= csr_new[3];
                mstatus_mpie <= csr_new[7];
            end
            A_MIE:
            begin
                mie_mtie <= csr_new[7];
                mie_meie <= csr_new[11];
            end
            A_MTVEC:
                mtvec_base <= csr_new[31:2];
            A_MSCRATCH:
                mscratch <= csr_new;
            A_MEPC:
                mepc_q <= csr_new[31:2];
            A_MCAUSE:
                mcause <= csr_new;
            A_MTVAL:
                mtval <= csr_new;
            default:
                ;                       // misa and mip ignore writes
        endcase
    end
end

endmodule
