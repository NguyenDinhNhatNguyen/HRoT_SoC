`timescale 1ns / 1ps

// DE10 replacement for rtl/mem/Data_Memory.v, same ports and timing. Quartus 13.0sp1 builds the shared
// version out of flip-flops on Cyclone V, so this one uses four byte-wide arrays that map to M10K.
// shortcut: INIT_FILE is ignored (the PPA build loads an all-zero RAM image), add per-byte hex files
// before running real firmware on a board.
module Data_Memory #(
    parameter MEM_SIZE  = 1024, // 4KB
    parameter INIT_FILE = ""
)(
    input             clk,
    input             MemWrite,
    input             MemRead,
    input      [31:0] addr,
    input      [31:0] write_data,
    input      [3:0]  wstrb,
    output     [31:0] read_data
);
    wire [$clog2(MEM_SIZE)-1:0] word_addr = addr[$clog2(MEM_SIZE)+1:2];
    wire [31:0] q;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : lane
            reg [7:0] ram [0:MEM_SIZE-1];
            reg [7:0] qb;
            always @(negedge clk) begin
                qb <= ram[word_addr];
                if (MemWrite && wstrb[i])
                    ram[word_addr] <= write_data[8*i +: 8];
            end
            assign q[8*i +: 8] = qb;
        end
    endgenerate

    assign read_data = MemRead ? q : 32'b0;
endmodule
