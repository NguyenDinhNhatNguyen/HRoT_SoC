`timescale 1ns / 1ps
`default_nettype none

// Kria KV260 top. The K26 PL has no clock of its own, so pl_clk0 and pl_resetn0 come from the
// Zynq UltraScale+ PS (kv260_bd.tcl, 50 MHz). The rest reuses Xilinx_Top. Switches and boot strap
// are tied to 0. The only PL header with free pins is the PMOD (8 pins), so there are 5 LEDs, led_app,
// uart_tx and uart_rx. The result code is also logged on the UART. Pins are in kv260.xdc
module KV260_Top #(
    parameter BOOT_HEX = "firmware_imem.hex",
    parameter RAM_HEX  = "firmware_dmem.hex",
    parameter APP_HEX  = "app_firmware.hex"
)(
    output wire [4:0] led,
    output wire       led_app,
    input  wire       uart_rx,
    output wire       uart_tx
);
    wire pl_clk0, pl_resetn0;
    wire [7:0] led8;

    kv260_ps_wrapper ps (
        .pl_clk0(pl_clk0),
        .pl_resetn0(pl_resetn0)
    );

    Xilinx_Top #(.BOOT_HEX(BOOT_HEX), .RAM_HEX(RAM_HEX), .APP_HEX(APP_HEX)) top (
        .clk(pl_clk0),
        .btn_rst(~pl_resetn0),
        .sw(8'h00),
        .sw_boot(4'h0),
        .led(led8),
        .led_app(led_app),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );
    assign led = led8[4:0];
endmodule

`default_nettype wire
