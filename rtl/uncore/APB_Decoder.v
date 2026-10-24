`timescale 1ns / 1ps

// APB decoder 1 master -> NUM_SLV slave, moi slave 1 cua so 4 KB (PADDR[15:12] = so slave)
// Cua so khong co slave: PREADY = 1, PSLVERR = 1
module APB_Decoder #(
    parameter NUM_SLV = 8
)(
    input  [31:0]          PADDR,
    input                  PSEL,
    output [NUM_SLV-1:0]   PSEL_S,     // PSEL cho tung slave
    input  [32*NUM_SLV-1:0] PRDATA_S,  // slave i: bit [32*i+31:32*i]
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
