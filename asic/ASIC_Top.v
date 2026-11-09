`timescale 1ns / 1ps
`default_nettype none

// ASIC_Top: chip-level wrapper of SoC_Top for the ASIC flow (P-20, P-21), the ASIC counterpart of
// DE2_Top. SoC_Top expects reset_system already synchronized to clk (SYSCSR por_rst), so the pad
// reset goes through a reset synchronizer here:
//  - assert: asynchronous, the reset reaches SoC_Top even before the clock runs
//  - release: synchronous, two flops, so recovery and removal are timed by STA and no flop sees the
//    reset fall close to a clock edge
// rst_pad_n is active low like a usual chip reset pin. boot_strap is only latched while in reset
// (SYSCSR), so the strap pins must be stable before the reset is released. The other inputs are
// synchronized inside SoC_Top (UART RX and GPIO in have two-flop synchronizers).
// The memories inside SoC_Top are still the RTL models, the SRAM macros replace them later (I-09).
module ASIC_Top #(
    parameter BOOT_HEX = "firmware_imem.hex",
    parameter RAM_HEX  = "firmware_dmem.hex",
    parameter APP_HEX  = "app_firmware.hex"
)(
    input  wire       clk,
    input  wire       rst_pad_n,     // chip reset pin, active low, asynchronous
    output wire       app_running,
    output wire       uart0_tx,
    input  wire       uart0_rx,
    output wire [7:0] gpio0_o,
    input  wire [7:0] gpio0_i,
    input  wire [3:0] boot_strap,
    output wire       uart1_tx,
    input  wire       uart1_rx,
    output wire [7:0] gpio1_o,
    input  wire [7:0] gpio1_i
);
    // Reset synchronizer: asynchronous assert, synchronous release
    reg [1:0] rst_sync;
    always @(posedge clk or negedge rst_pad_n) begin
        if (!rst_pad_n)
            rst_sync <= 2'b11;
        else
            rst_sync <= {rst_sync[0], 1'b0};
    end

    SoC_Top #(.VERIFY_GATE(1), .BOOT_HEX(BOOT_HEX), .RAM_HEX(RAM_HEX), .APP_HEX(APP_HEX)) soc (
        .clk(clk),
        .reset_system(rst_sync[1]),
        .app_running(app_running),
        .uart0_tx(uart0_tx),
        .uart0_rx(uart0_rx),
        .gpio0_o(gpio0_o),
        .gpio0_i(gpio0_i),
        .boot_strap(boot_strap),
        .uart1_tx(uart1_tx),
        .uart1_rx(uart1_rx),
        .gpio1_o(gpio1_o),
        .gpio1_i(gpio1_i)
    );
endmodule

`default_nettype wire
