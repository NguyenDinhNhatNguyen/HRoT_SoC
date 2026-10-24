`timescale 1ns / 1ps
`default_nettype none

// Board wrapper for a Xilinx kit (not chosen yet). The SoC itself lives in rtl/, shared with the DE2.
// Once the kit is picked, change the ports here and in constraints.xdc, never rtl/.
module Xilinx_Top #(
    parameter BOOT_HEX = "firmware_imem.hex",
    parameter RAM_HEX  = "firmware_dmem.hex",
    parameter APP_HEX  = "app_firmware.hex"
)(
    input  wire       clk,           // board clock (period set in constraints.xdc)
    input  wire       btn_rst,       // reset button, active high
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
