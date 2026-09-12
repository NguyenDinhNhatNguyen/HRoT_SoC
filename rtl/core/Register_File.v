`timescale 1ns / 1ps

module Register_File(
    input        clk,
    input        WE3,
    input  [4:0]  RA1,
    input  [4:0]  RA2,
    input  [4:0]  WA3,
    input  [31:0] WD3,

    output [31:0] RD1,
    output [31:0] RD2
);

reg [31:0] REG_MEM_BLOCK [31:0];

always @(posedge clk) begin
    if (WE3)
        REG_MEM_BLOCK[WA3] <= WD3;
end

assign RD1 = (RA1 != 0) ? ((WE3 && (RA1 == WA3)) ? WD3 : REG_MEM_BLOCK[RA1]) : 32'b0;
assign RD2 = (RA2 != 0) ? ((WE3 && (RA2 == WA3)) ? WD3 : REG_MEM_BLOCK[RA2]) : 32'b0;

endmodule