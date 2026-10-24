`timescale 1ns / 1ps
`default_nettype none

// Top boc chan cho kit Xilinx (kit chua chot). Logic SoC nam o rtl/ (dung chung voi DE2).
// Khi chot kit: sua ten/so chan o day va constraints.xdc, khong sua rtl/.
module Xilinx_Top #(
    parameter BOOT_HEX = "firmware_imem.hex",
    parameter RAM_HEX  = "firmware_dmem.hex",
    parameter APP_HEX  = "app_firmware.hex"
)(
    input  wire       clk,           // clock board (constraints.xdc dat chu ky)
    input  wire       btn_rst,       // nut reset, muc cao khi nhan
    input  wire [7:0] sw,
    input  wire [3:0] sw_boot,
    output wire [7:0] led,
    output wire       led_app,
    input  wire       uart_rx,
    output wire       uart_tx
);
    reg [1:0] rst_sync;
    always @(posedge clk) rst_sync <= {rst_sync[0], btn_rst};

    SoC_Top #(.BOOT_HEX(BOOT_HEX), .RAM_HEX(RAM_HEX), .APP_HEX(APP_HEX)) soc (
        .clk(clk),
        .reset_system(rst_sync[1]),
        .app_running(led_app),
        .uart0_tx(uart_tx),
        .uart0_rx(uart_rx),
        .gpio0_o(led),
        .gpio0_i(sw),
        .boot_strap(sw_boot)
    );
endmodule

`default_nettype wire
