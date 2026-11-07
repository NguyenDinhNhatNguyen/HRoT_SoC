`timescale 1ns / 1ps
`default_nettype none

// Kria KV260 top. The K26 PL has no clock of its own, so pl_clk0 and pl_resetn0 come from the
// Zynq UltraScale+ PS (kv260_bd.tcl, 50 MHz). Switches and boot strap are tied to 0. The only PL
// header with free pins is the PMOD (8 pins), so there are 5 LEDs, led_app, uart_tx and uart_rx.
// The result code is also logged on the UART. Pins are in kv260.xdc
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

    kv260_ps_wrapper ps (
        .pl_clk0(pl_clk0),
        .pl_resetn0(pl_resetn0)
    );

    reg [1:0] rst_sync;
    always @(posedge pl_clk0) rst_sync <= {rst_sync[0], ~pl_resetn0};

    wire [7:0] led8;

    SoC_Top #(.VERIFY_GATE(1), .BOOT_HEX(BOOT_HEX), .RAM_HEX(RAM_HEX), .APP_HEX(APP_HEX)) soc (
        .clk(pl_clk0),
        .reset_system(rst_sync[1]),
        .app_running(led_app),
        .uart0_tx(uart_tx),
        .uart0_rx(uart_rx),
        .gpio0_o(led8),
        .gpio0_i(8'h00),
        .boot_strap(4'h0),
        .uart1_tx(),                      // App-world UART1 and GPIO1 have no pins on the PMOD
        .uart1_rx(1'b1),
        .gpio1_o(),
        .gpio1_i(8'b0)
    );

    assign led = led8[4:0];
endmodule

`default_nettype wire
