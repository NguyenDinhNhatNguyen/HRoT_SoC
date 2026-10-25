`timescale 1ns / 1ps
`default_nettype none

// Board wrapper for the Terasic DE2 (Cyclone II EP2C35F672C6).
// Board-specific glue only: reset button sync and LED/SW/UART mapping. The SoC itself lives in rtl/
// and is shared with the Xilinx build.
module DE2_Top #(
    parameter BOOT_HEX = "firmware_imem.hex",
    parameter RAM_HEX  = "firmware_dmem.hex",
    parameter APP_HEX  = "app_firmware.hex"
)(
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,          // push buttons, active low, KEY[0] = reset
    input  wire [17:0] SW,
    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,
    input  wire        UART_RXD,
    output wire        UART_TXD
);
    // KEY[0] is asynchronous: pass it through a 2-flop synchronizer
    reg [1:0] rst_sync;
    always @(posedge CLOCK_50) rst_sync <= {rst_sync[0], ~KEY[0]};

    wire       app_running;
    wire [7:0] led;
    wire [7:0] gpio1_o;               // App-world GPIO1, shown on the green LEDs

    SoC_Top #(.BOOT_HEX(BOOT_HEX), .RAM_HEX(RAM_HEX), .APP_HEX(APP_HEX)) soc (
        .clk(CLOCK_50),
        .reset_system(rst_sync[1]),
        .app_running(app_running),
        .uart0_tx(UART_TXD),
        .uart0_rx(UART_RXD),
        .gpio0_o(led),
        .gpio0_i(SW[7:0]),
        .boot_strap(SW[17:14]),
        .uart1_tx(),                      // the DE2 has one RS-232 port, UART1 stays unconnected
        .uart1_rx(1'b1),
        .gpio1_o(gpio1_o),
        .gpio1_i({2'b00, SW[13:8]})
    );

    assign LEDR = {10'b0, led};
    assign LEDG = {gpio1_o, app_running};   // LEDG0 on = App Core released, LEDG[8:1] = App GPIO1
endmodule

`default_nettype wire
