`timescale 1ns / 1ps

// APB decoder, 1 master to NUM_SLV slaves, one 4 KB window each (PADDR[15:12] = slave index)
// A window with no slave answers at once with PSLVERR
module APB_Decoder #(
    parameter NUM_SLV = 8
)(
    input  [31:0]          PADDR,
    input                  PSEL,
    output [NUM_SLV-1:0]   PSEL_S,     // per-slave PSEL
    input  [32*NUM_SLV-1:0] PRDATA_S,  // slave i on bits [32*i+31:32*i]
    input  [NUM_SLV-1:0]   PREADY_S,
    input  [NUM_SLV-1:0]   PSLVERR_S,
    output [31:0]          PRDATA,
    output                 PREADY,
    output                 PSLVERR
);
    wire [3:0] idx   = PADDR[15:12];
    wire       valid = (idx < NUM_SLV);

    genvar i;
    generate
        for (i = 0; i < NUM_SLV; i = i + 1) begin : g_sel
            assign PSEL_S[i] = PSEL && (idx == i);
        end
    endgenerate

    assign PRDATA  = valid ? PRDATA_S[32*idx +: 32] : 32'b0;
    assign PREADY  = valid ? PREADY_S[idx]  : 1'b1;
    assign PSLVERR = valid ? PSLVERR_S[idx] : PSEL;
endmodule
