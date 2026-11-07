`timescale 1ns/1ps
// RISCV_Core_sva: SystemVerilog assertions on the core (P-19), bound to every RISCV_Core instance, so they
// run in the core testbenches (sim/run_rtl.do) and on both cores of the SoC (sim/run_fw.do). Questa only:
// iverilog and the Verilator lint flow do not compile this file. A failing assertion prints
// "** Error: Assertion error", which make test and make cov count as a failure.
//
// What is checked (contracts from docs/guides/Dev_Guide.md section 2 and the RTL headers):
//   data port   a_no_we_and_re   load and store never in the same cycle
//               a_wstrb_aligned  every store strobe matches its address (word, half, byte lanes)
//               a_stall_holds    while bus_stall is high the access stays exactly the same (I-01 bus contract)
//   fetch       a_pc_aligned     the fetch address is word aligned
//               a_pc_redirect    a branch, jump or trap redirect lands on its target the next cycle
//               a_pc_hold        a load-use stall, instr_stall (R8) or bus_stall without a redirect holds the PC
//   traps       a_no_trap_stall  no trap and no redirect from MEM while bus_stall is high
//               a_irq_not_mem    an interrupt is taken only on an instruction that is not a load or store
//               a_trap_target    a trap jumps to mtvec, MRET to mepc
//               a_trap_mepc      after a trap, mepc holds the PC of the instruction in MEM
//               a_trap_mie       after a trap, MIE = 0 and MPIE = the old MIE
module RISCV_Core_sva (
    input        clk,
    input        rst,
    input        bus_stall,
    input [31:0] instr_addr,
    input [31:0] data_addr,
    input [31:0] data_wdata,
    input [3:0]  data_wstrb,
    input        data_we,
    input        data_re,
    input        PipelineStall,
    input        flush_IF_ID,
    input [31:0] redirect_pc,
    input        trap_redirect,
    input [31:0] trap_target,
    input        mem_access,
    input [31:2] PC_MEM,
    input        take_irq,
    input        take_exc,
    input        take_mret,
    input [29:0] mtvec_base,
    input [29:0] mepc_q,
    input        mstatus_mie,
    input        mstatus_mpie
);

    default clocking cb @(posedge clk);
    endclocking
    default disable iff (rst);

    // Data port
    a_no_we_and_re: assert property (!(data_we && data_re));

    a_wstrb_aligned: assert property (data_we |->
        (data_wstrb == 4'b1111 && data_addr[1:0] == 2'b00) ||
        (data_wstrb == 4'b0011 && data_addr[1:0] == 2'b00) ||
        (data_wstrb == 4'b1100 && data_addr[1:0] == 2'b10) ||
        (data_wstrb == 4'b0001 && data_addr[1:0] == 2'b00) ||
        (data_wstrb == 4'b0010 && data_addr[1:0] == 2'b01) ||
        (data_wstrb == 4'b0100 && data_addr[1:0] == 2'b10) ||
        (data_wstrb == 4'b1000 && data_addr[1:0] == 2'b11));

    // === because a store may carry X: the register file is not reset, and a function prologue saves
    // registers nothing has written yet. Holding X during the stall is fine, changing it is not
    a_stall_holds: assert property ((bus_stall && (data_we || data_re)) |=>
        data_we === $past(data_we) && data_re === $past(data_re) && data_addr === $past(data_addr) &&
        (!data_we || (data_wdata === $past(data_wdata) && data_wstrb === $past(data_wstrb))));

    // Fetch
    a_pc_aligned:  assert property (instr_addr[1:0] == 2'b00);
    a_pc_redirect: assert property (flush_IF_ID |=> instr_addr == $past(redirect_pc));
    a_pc_hold:     assert property ((PipelineStall && !flush_IF_ID) |=> instr_addr == $past(instr_addr));

    // Traps
    a_no_trap_stall: assert property (bus_stall |-> !trap_redirect);
    a_irq_not_mem:   assert property (take_irq |-> !mem_access);
    a_trap_target:   assert property (((take_irq || take_exc) |-> trap_target == {mtvec_base, 2'b00}) and
                                      (take_mret |-> trap_target == {mepc_q, 2'b00}));
    a_trap_mepc:     assert property ((take_irq || take_exc) |=> mepc_q == $past(PC_MEM));
    a_trap_mie:      assert property ((take_irq || take_exc) |=> !mstatus_mie && mstatus_mpie == $past(mstatus_mie));

endmodule

// The bind sits in its own module, loaded as a second top by vsim (... work.RISCV_Core_sva_bind), because
// Questa 10.2c does not elaborate a bind left in the compilation-unit scope
module RISCV_Core_sva_bind;
bind RISCV_Core RISCV_Core_sva u_sva (
    .clk          (clk),
    .rst          (rst),
    .bus_stall    (bus_stall),
    .instr_addr   (instr_addr),
    .data_addr    (data_addr),
    .data_wdata   (data_wdata),
    .data_wstrb   (data_wstrb),
    .data_we      (data_we),
    .data_re      (data_re),
    .PipelineStall(PipelineStall),
    .flush_IF_ID  (flush_IF_ID),
    .redirect_pc  (redirect_pc),
    .trap_redirect(trap_redirect),
    .trap_target  (trap_target),
    .mem_access   (MemRead_MEM | MemWrite_MEM),
    .PC_MEM       (PC_MEM),
    .take_irq     (u_CSR_Unit.take_irq),
    .take_exc     (u_CSR_Unit.take_exc),
    .take_mret    (u_CSR_Unit.take_mret),
    .mtvec_base   (u_CSR_Unit.mtvec_base),
    .mepc_q       (u_CSR_Unit.mepc_q),
    .mstatus_mie  (u_CSR_Unit.mstatus_mie),
    .mstatus_mpie (u_CSR_Unit.mstatus_mpie)
);
endmodule
