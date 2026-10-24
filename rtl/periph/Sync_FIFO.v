`timescale 1ns / 1ps

// Synchronous FIFO, DEPTH = 2^AW, combinational read (dout is the head of the queue).
// full/empty come from comparing pointers that carry one extra wrap bit.
module Sync_FIFO #(
    parameter DW = 8,
    parameter AW = 3
)(
    input               clk, reset,
    input               push,
    input      [DW-1:0] din,
    input               pop,
    output     [DW-1:0] dout,
    output              full,
    output              empty
);
    reg [DW-1:0] mem [0:(1<<AW)-1];
    reg [AW:0]   wp, rp;

    assign empty = (wp == rp);
    assign full  = (wp[AW] != rp[AW]) && (wp[AW-1:0] == rp[AW-1:0]);
    assign dout  = mem[rp[AW-1:0]];

    always @(posedge clk) begin
        if (reset) begin
            wp <= 0;
            rp <= 0;
        end else begin
            if (push && !full) begin
                mem[wp[AW-1:0]] <= din;
                wp <= wp + 1'b1;
            end
            if (pop && !empty)
                rp <= rp + 1'b1;
        end
    end
endmodule
