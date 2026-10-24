`timescale 1ns/1ps
module soc_tb;
  `include "labels.vh"
  reg clk=0, rst=1; always #5 clk=~clk;
  SoC_Top #(.BOOT_HEX("boot.hex"), .RAM_HEX(""), .APP_HEX("app.hex")) dut(.clk(clk), .reset_system(rst), .app_running());
  integer cyc=0;
  // Dem cac response loi tren bus AXI cua Master
  integer slverr=0, decerr_w=0, decerr_r=0;
  always @(posedge clk) begin
    if (dut.M_AXI_BVALID && dut.M_AXI_BREADY && dut.M_AXI_BRESP == 2'b10) slverr   = slverr + 1;
    if (dut.M_AXI_BVALID && dut.M_AXI_BREADY && dut.M_AXI_BRESP == 2'b11) decerr_w = decerr_w + 1;
    if (dut.M_AXI_RVALID && dut.M_AXI_RREADY && dut.M_AXI_RRESP == 2'b11) decerr_r = decerr_r + 1;
  end
  initial begin
    repeat(3) @(posedge clk); #1 rst=0;
    while (dut.app_core_reset_n !== 1'b1 && cyc < 5000) begin @(posedge clk); cyc=cyc+1; end
    repeat(30) @(posedge clk);
    $display("app released after %0d cycles", cyc);
    $display("app_core_reset_n=%b  app_ram[0]=%0d", dut.app_core_reset_n, dut.app_ram.ram[0]);
    $display("SLVERR=%0d DECERR_W=%0d DECERR_R=%0d", slverr, decerr_w, decerr_r);
    $display("SOC RESULT: %s", (cyc < 5000 && dut.app_core_reset_n===1 && dut.app_ram.ram[0]===42 && slverr==1 && decerr_w==1 && decerr_r==1) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
