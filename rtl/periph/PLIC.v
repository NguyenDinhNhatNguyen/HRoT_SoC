`timescale 1ns / 1ps

// PLIC-lite: 8 level-sensitive interrupt sources merged into one external-interrupt line
// (APB slave, zero wait states). Fixed priority, the lowest source index wins. There is no
// per-source priority, threshold or claim latching: a source stays pending until its own
// device clears it.
//
// Registers (offset):
//   0x00 PENDING RO  [7:0] raw state of the source inputs
//   0x04 ENABLE  RW  [7:0] per-source enable
//   0x08 CLAIM   RO  1 + index of the lowest pending and enabled source, 0 if there is none
//                    Writing 0x08 (the usual COMPLETE) is accepted and does nothing: the sources are
//                    levels, so a source drops when its own device is serviced
//   other offsets: read 0, writes ignored
module PLIC (
    input             clk, reset,
    input      [7:0]  src,
    output            irq,           // to the Master Core's irq_ext (P-09, I-01)

    // APB4 slave
    input      [11:0] PADDR,
    input             PSEL,
    input             PENABLE,
    input             PWRITE,
    input      [31:0] PWDATA,
    input      [3:0]  PSTRB,
    output reg [31:0] PRDATA,
    output            PREADY,
    output            PSLVERR
);
    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    wire wr = PSEL && PENABLE && PWRITE;

    reg [7:0] en_q;
    always @(posedge clk) begin
        if (reset)
            en_q <= 8'b0;
        else if (wr && PADDR == 12'h004 && PSTRB[0])
            en_q <= PWDATA[7:0];
    end

    wire [7:0] act = src & en_q;
    assign irq = |act;

    reg [3:0] claim;
    always @(*) begin
        casez (act)
            8'b???????1:
                claim = 4'd1;
            8'b??????10:
                claim = 4'd2;
            8'b?????100:
                claim = 4'd3;
            8'b????1000:
                claim = 4'd4;
            8'b???10000:
                claim = 4'd5;
            8'b??100000:
                claim = 4'd6;
            8'b?1000000:
                claim = 4'd7;
            8'b10000000:
                claim = 4'd8;
            default:
                claim = 4'd0;
        endcase
    end

    always @(*) begin
        case (PADDR)
            12'h000:
                PRDATA = {24'b0, src};
            12'h004:
                PRDATA = {24'b0, en_q};
            12'h008:
                PRDATA = {28'b0, claim};
            default:
                PRDATA = 32'b0;
        endcase
    end
endmodule
