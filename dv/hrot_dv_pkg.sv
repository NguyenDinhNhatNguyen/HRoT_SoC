`timescale 1ns/1ps
// Gom toàn bộ lớp UVM vào một package. Biên dịch SAU axi4_lite_if.sv,
// với +incdir tới dv/agents, dv/env, dv/tests.
// Quy ước đuôi file: *.svh = file chỉ được `include vào package (KHÔNG biên dịch riêng),
//                    *.sv  = đơn vị biên dịch (interface, package, slave model, tb_top).
package hrot_dv_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "axi4_lite_agent_cfg.svh"
  `include "axi4_lite_item.svh"
  `include "axi4_lite_sequencer.svh"
  `include "axi4_lite_driver.svh"
  `include "axi4_lite_monitor.svh"
  `include "axi4_lite_agent.svh"
  `include "axi4_lite_scoreboard.svh"
  `include "hrot_env.svh"
  `include "axi4_lite_seq_lib.svh"
  `include "base_test.svh"
endpackage
