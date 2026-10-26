`timescale 1ns/1ps
// UVM top for SHA256_Wrapper (P-08): the AXI4-Lite agent drives the real DUT directly.
// The wrapper has no BRESP/RRESP outputs (always OKAY) and ignores WSTRB (registers take whole words, HAL #7).
module tb_sha256_top;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import hrot_dv_pkg::*;

    logic clk   = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;                       // 100 MHz

    axi4_lite_if axi_if (.clk(clk), .rst_n(rst_n));

    SHA256_Wrapper dut (
        .clk(clk), .reset(~rst_n),                // RTL reset active-high
        .S_AXI_AWVALID(axi_if.awvalid), .S_AXI_AWREADY(axi_if.awready), .S_AXI_AWADDR(axi_if.awaddr),
        .S_AXI_WVALID (axi_if.wvalid),  .S_AXI_WREADY (axi_if.wready),  .S_AXI_WDATA (axi_if.wdata),
        .S_AXI_BVALID (axi_if.bvalid),  .S_AXI_BREADY (axi_if.bready),
        .S_AXI_ARVALID(axi_if.arvalid), .S_AXI_ARREADY(axi_if.arready), .S_AXI_ARADDR(axi_if.araddr),
        .S_AXI_RVALID (axi_if.rvalid),  .S_AXI_RREADY (axi_if.rready),  .S_AXI_RDATA (axi_if.rdata)
    );
    assign axi_if.bresp = 2'b00;
    assign axi_if.rresp = 2'b00;

    // 5-cycle reset. +RESET_AT_NS=<t>: add a 5-cycle reset pulse after t ns (same as tb_top)
    initial begin
        int unsigned reset_at_ns;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        if ($value$plusargs("RESET_AT_NS=%d", reset_at_ns)) begin
            #(real'(reset_at_ns) * 1ns);
            @(negedge clk) rst_n = 1'b0;
            repeat (5) @(negedge clk);
            rst_n = 1'b1;
        end
    end

    initial begin
        uvm_config_db#(virtual axi4_lite_if)::set(null, "*", "vif", axi_if);
        run_test();
    end
endmodule
