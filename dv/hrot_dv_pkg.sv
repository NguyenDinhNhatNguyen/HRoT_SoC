`timescale 1ns/1ps
// All UVM classes in one package. Compile AFTER axi4_lite_if.sv,
// with +incdir to dv/agents, dv/env, dv/tests.
// File suffix rule: *.svh = only `included into the package (NEVER compiled alone),
//                   *.sv  = compilation unit (interface, package, slave model, tb_top).
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
    `include "sha256_ref.svh"
    `include "axi4_lite_seq_lib.svh"
    `include "sha256_seq_lib.svh"
    `include "base_test.svh"
    `include "sha256_tests.svh"
endpackage
