`timescale 1ns/1ps
// Top-level UVM độc lập với RTL của SoC: tạo clock/reset, interface và slave mô hình.
// (Thay cho uvm_top.sv cũ; đổi tên để không trùng biến toàn cục uvm_top của UVM.)
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

  // Reset giữ 5 chu kỳ, nhả ở cạnh xuống để tránh race với các process lấy mẫu cạnh lên
  initial begin
    repeat (5) @(negedge clk);
    rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual axi4_lite_if)::set(null, "*", "vif", axi_if);
    run_test();                               // chọn test bằng +UVM_TESTNAME=<test>
  end
endmodule