`timescale 1ns/1ps
// Whole-SoC test with the hand-written test firmware from dv/sw/mkhex.py: the Master hashes "abc"
// on the SHA-256 block, reads App ROM port B, provokes SLVERR/DECERR, talks over UART and GPIO,
// then releases the App Core. Ends with "SoC_Top_tb RESULT: PASS|FAIL".
module soc_tb;
  `include "labels.vh"
  reg clk=0, rst=1; always #5 clk=~clk;
  wire       uart_tx;
  reg        uart_rx = 1;
  wire [7:0] led;
  SoC_Top #(.BOOT_HEX("boot.hex"), .RAM_HEX(""), .APP_HEX("app.hex")) dut(
    .clk(clk), .reset_system(rst), .app_running(),
    .uart0_tx(uart_tx), .uart0_rx(uart_rx), .gpio0_o(led), .gpio0_i(8'h00), .boot_strap(4'h0));

  // UART receiver on the tb side (BAUD_DIV = 0 -> 16 clocks per bit)
  reg [8*8-1:0] uart_str = 0;
  integer       nchar = 0, b;
  reg   [7:0]   ch;
  initial forever begin
    @(negedge uart_tx); repeat (8) @(posedge clk);
    for (b = 0; b < 8; b = b + 1) begin repeat (16) @(posedge clk); ch[b] = uart_tx; end
    repeat (16) @(posedge clk);
    uart_str = {uart_str[8*7-1:0], ch}; nchar = nchar + 1; $display("[%0t] UART tx byte %h", $time, ch);
  end
  // Once the firmware shows 0xA5 on the LEDs, send 0x5A back on RX
  task send_byte(input [7:0] v); integer j; begin
    uart_rx = 0; repeat (16) @(posedge clk);
    for (j = 0; j < 8; j = j + 1) begin uart_rx = v[j]; repeat (16) @(posedge clk); end
    uart_rx = 1; repeat (16) @(posedge clk);
  end endtask
  initial begin wait (led === 8'hA5); send_byte(8'h5A); end
  integer cyc=0;
  // Count error responses on the Master AXI bus
  integer slverr=0, slverr_r=0, decerr_w=0, decerr_r=0;
  always @(posedge clk) begin
    if (dut.M_AXI_BVALID && dut.M_AXI_BREADY && dut.M_AXI_BRESP == 2'b10) slverr   = slverr + 1;
    if (dut.M_AXI_BVALID && dut.M_AXI_BREADY && dut.M_AXI_BRESP == 2'b11) decerr_w = decerr_w + 1;
    if (dut.M_AXI_RVALID && dut.M_AXI_RREADY && dut.M_AXI_RRESP == 2'b11) decerr_r = decerr_r + 1;
    if (dut.M_AXI_RVALID && dut.M_AXI_RREADY && dut.M_AXI_RRESP == 2'b10) slverr_r = slverr_r + 1;
  end
  initial begin
    repeat(3) @(posedge clk); #1 rst=0;
    while (dut.app_core_reset_n !== 1'b1 && cyc < 20000) begin @(posedge clk); cyc=cyc+1; end
    repeat(400) @(posedge clk);
    $display("App released after %0d cycles", cyc);
    $display("app_core_reset_n=%b  app_ram[0]=%0d", dut.app_core_reset_n, dut.app_ram.ram[0]);
    $display("SLVERR=%0d SLVERR_R=%0d DECERR_W=%0d DECERR_R=%0d", slverr, slverr_r, decerr_w, decerr_r);
    $display("UART received %0d chars: \"%0s\"  LED=%h", nchar, uart_str, led);
    $display("SoC_Top_tb RESULT: %s", (cyc < 20000 && dut.app_core_reset_n===1 && dut.app_ram.ram[0]===42 && slverr==1 && slverr_r==1 && decerr_w==1 && decerr_r==1 && nchar==2 && uart_str[15:0]=="OK" && led==8'h5A) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
