`timescale 1ns / 1ps
`default_nettype none
// Home model of the school SRAM hard macro sram_2k_macro, FOR SIMULATION ONLY. Written from the
// description of the macro (RV32i-SoC docs/macro_notes.md): 1024 words x 32 bits, one port,
// CEN and WEN active low, no byte write, read data one cycle after the address.
// The file is not named sram_2k_macro*.v on purpose: .gitignore blocks that name because the real
// macro files come from the school PDK. On the server the real ~/PDK_GPDK45/lib/sram_2k_macro.v
// replaces this model, and it is never committed.
//
// Behavior of this model (the real macro may differ, the wrappers do not rely on the parts marked X):
//   CEN = 0, WEN = 1: read, Q gets the word at the next rising edge
//   CEN = 0, WEN = 0: write D, Q becomes X (behavior of the real macro during a write is unknown)
//   CEN = 1         : Q holds
// A control pin at X while the macro is enabled is reported, so the wrappers must never drive one.
module sram_2k_macro (
    input  wire        CLK,
    input  wire        CEN,
    input  wire        WEN,
    input  wire [9:0]  A,
    input  wire [31:0] D,
    output reg  [31:0] Q
);
    // The words start unknown (X) like the RTL memories, so a test sees a word nobody wrote
    reg [31:0] mem [0:1023];
    initial Q = 32'hxxxx_xxxx;

    always @(posedge CLK) begin
        if (CEN === 1'b0) begin
            if (WEN === 1'b0) begin
                mem[A] <= D;
                Q      <= 32'hxxxx_xxxx;
            end else if (WEN === 1'b1) begin
                Q      <= mem[A];
            end else begin
                Q      <= 32'hxxxx_xxxx;
                $display("MACRO ERROR: %m WEN is X while CEN = 0 (t=%0t)", $time);
            end
        end else if (CEN !== 1'b1) begin
            Q <= 32'hxxxx_xxxx;
            $display("MACRO ERROR: %m CEN is X (t=%0t)", $time);
        end
    end
endmodule
`default_nettype wire
