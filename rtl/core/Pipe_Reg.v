`timescale 1ns / 1ps

// Generic pipeline register for the sideband signals that the stage registers do not carry
// (valid bit, CSR and trap decode, PC in MEM). Same rules as IF_ID_Reg: synchronous reset,
// flush clears it to a bubble, stall holds it.
module Pipe_Reg #(
    parameter W = 1
)(
    input              clk, rst,
    input              flush,
    input              stall,
    input      [W-1:0] d,
    output reg [W-1:0] q
);

always @(posedge clk) begin
    if (rst || flush)
        q <= {W{1'b0}};
    else if (!stall)
        q <= d;
end

endmodule
