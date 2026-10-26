`timescale 1ns/1ps
// UVM top-level independent of the SoC RTL: clock/reset, interface and the model slave.
// (Replaces the old uvm_top.sv, renamed so it does not clash with the UVM global uvm_top.)
module tb_top;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import hrot_dv_pkg::*;

    logic clk   = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;                       // 100 MHz

    axi4_lite_if axi_if (.clk(clk), .rst_n(rst_n));

    axi4_lite_slave_model u_slave (
        .clk(clk), .rst_n(rst_n),
        .awaddr(axi_if.awaddr), .awvalid(axi_if.awvalid), .awready(axi_if.awready),
        .wdata (axi_if.wdata),  .wstrb (axi_if.wstrb),
        .wvalid(axi_if.wvalid), .wready(axi_if.wready),
        .bresp (axi_if.bresp),  .bvalid(axi_if.bvalid),   .bready(axi_if.bready),
        .araddr(axi_if.araddr), .arvalid(axi_if.arvalid), .arready(axi_if.arready),
        .rdata (axi_if.rdata),  .rresp (axi_if.rresp),
        .rvalid(axi_if.rvalid), .rready(axi_if.rready)
    );

    // Reset is held 5 cycles and released on a falling edge to avoid races with rising-edge samplers.
    // +RESET_AT_NS=<t>: add a 5-cycle reset pulse after t ns (reset in the middle of a transaction).
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
        run_test();                               // pick the test with +UVM_TESTNAME=<test>
    end
endmodule
