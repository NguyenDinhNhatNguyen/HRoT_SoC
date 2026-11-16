`timescale 1ns / 1ps
`default_nettype none

// ROM_Logic: the 4 KB Boot ROM and App ROM as logic for the ASIC build. Drop-in for Dual_Port_ROM
// (same ports), selected in SoC_Top by `define ROM_LOGIC. The image comes from ROM_Image_Boot and
// ROM_Image_App, generated from the firmware hex by fw/tools/gen_rom_v.py (make rom-images).
//  - IMAGE = 0 is the Boot ROM, IMAGE = 1 is the App ROM
//  - Each port is its own copy of the lookup, so port A (fetch) and port B (AXI, Boot_Verifier) read
//    different words in the same cycle
//  - The read is combinational. Dual_Port_ROM answers from the falling edge, but every user samples
//    the data on a rising edge, so the data is the same there. The fetch path gets longer (PC to the
//    IF/ID register through the lookup), which Genus reports in the timing of the ROM paths
// clk is not used, it only keeps the port list of Dual_Port_ROM. Verilog-2001 only (Genus).
module ROM_Logic #(
    parameter IMAGE = 0
)(
    input  wire        clk,
    input  wire [31:0] addrA,
    output wire [31:0] dataOutA,
    input  wire [31:0] addrB,
    output wire [31:0] dataOutB
);
    generate
        if (IMAGE == 0) begin : g_boot
            ROM_Image_Boot port_a (.a(addrA[11:2]), .d(dataOutA));
            ROM_Image_Boot port_b (.a(addrB[11:2]), .d(dataOutB));
        end else begin : g_app
            ROM_Image_App port_a (.a(addrA[11:2]), .d(dataOutA));
            ROM_Image_App port_b (.a(addrB[11:2]), .d(dataOutB));
        end
    endgenerate

    wire unused = &{1'b0, addrA[31:12], addrA[1:0], addrB[31:12], addrB[1:0]};
endmodule

`default_nettype wire
