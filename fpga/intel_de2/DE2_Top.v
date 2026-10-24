`timescale 1ns / 1ps
`default_nettype none

// Top boc chan cho kit Terasic DE2 (Cyclone II EP2C35F672C6)
// Chi lam viec theo board: dong bo reset nut bam, map LED/SW/UART. Logic SoC nam o rtl/ (dung chung voi Xilinx).
module DE2_Top #(
    parameter BOOT_HEX = "firmware_imem.hex",
    parameter RAM_HEX  = "firmware_dmem.hex",
    parameter APP_HEX  = "app_firmware.hex"
)(
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,          // nut bam, muc thap khi nhan; KEY[0] = reset
    input  wire [17:0] SW,
    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,
    input  wire        UART_RXD,
    output wire        UART_TXD
);
    // Dong bo reset: KEY[0] bat dong bo -> reset dong bo 2 tang
    reg [1:0] rst_sync;
    always @(posedge CLOCK_50) rst_sync <= {rst_sync[0], ~KEY[0]};

    wire       app_running;
    wire [7:0] led;

    SoC_Top #(.BOOT_HEX(BOOT_HEX), .RAM_HEX(RAM_HEX), .APP_HEX(APP_HEX)) soc (
        .clk(CLOCK_50),
        .reset_system(rst_sync[1]),
        .app_running(app_running),
        .uart0_tx(UART_TXD),
        .uart0_rx(UART_RXD),
        .gpio0_o(led),
        .gpio0_i(SW[7:0]),
        .boot_strap(SW[17:14])
    );

    assign LEDR = {10'b0, led};
    assign LEDG = {8'b0, app_running};   // LEDG0 sang = App Core da duoc nha reset
endmodule

`default_nettype wire
