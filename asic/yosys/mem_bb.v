// Black boxes for the four 4 KB memories of SoC_Top, used only by the home Yosys flow (run_yosys.sh).
// The real RTL (rtl/mem/) would map to about 131,000 flip-flops, which says nothing about the ASIC:
// Genus uses SRAM macros there. Ports and parameters follow rtl/mem/Dual_Port_ROM.v and Data_Memory.v.
// Not read together with rtl/mem/*.v. Data_Memory also gates read_data with MemRead (32 AND gates),
// which this black box leaves out.
(* blackbox *)
module Dual_Port_ROM #(
    parameter INIT_FILE = ""
)(
    input             clk,
    input      [31:0] addrA,
    output     [31:0] dataOutA,
    input      [31:0] addrB,
    output     [31:0] dataOutB
);
endmodule

(* blackbox *)
module Data_Memory #(
    parameter MEM_SIZE  = 1024,
    parameter INIT_FILE = ""
)(
    input             clk,
    input             MemWrite,
    input             MemRead,
    input      [31:0] addr,
    input      [31:0] write_data,
    input      [3:0]  wstrb,
    output     [31:0] read_data
);
endmodule
