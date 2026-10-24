`timescale 1ns / 1ps

// CLINT-style timer: 64-bit mtime counts every clk, interrupt while mtime >= mtimecmp
// (APB slave, zero wait states)
//
// Registers (offset), full 32-bit writes only:
//   0x00 MTIME_LO    RW  mtime[31:0]
//   0x04 MTIME_HI    RW  mtime[63:32] (for a 64-bit read: HI, LO, then HI again, retry if HI moved)
//   0x08 MTIMECMP_LO RW  mtimecmp[31:0]
//   0x0C MTIMECMP_HI RW  mtimecmp[63:32] (resets to all ones, so no interrupt after reset)
//   other offsets: read 0, writes ignored
// irq is active high and one cycle late: the 64-bit compare is registered to keep it off the critical path
module TIMER (
    input             clk, reset,
    output reg        irq,

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

    reg [63:0] mtime, mtimecmp;

    always @(posedge clk) begin
        if (reset) begin
            mtime    <= 64'b0;
            mtimecmp <= {64{1'b1}};
            irq      <= 1'b0;
        end else begin
            // a bus write beats the increment in the same cycle
            if (wr && PADDR == 12'h000)
                mtime[31:0] <= PWDATA;
            else if (wr && PADDR == 12'h004)
                mtime[63:32] <= PWDATA;
            else
                mtime <= mtime + 64'd1;
            if (wr && PADDR == 12'h008)
                mtimecmp[31:0] <= PWDATA;
            if (wr && PADDR == 12'h00C)
                mtimecmp[63:32] <= PWDATA;
            irq <= (mtime >= mtimecmp);
        end
    end

    always @(*) begin
        case (PADDR)
            12'h000:
                PRDATA = mtime[31:0];
            12'h004:
                PRDATA = mtime[63:32];
            12'h008:
                PRDATA = mtimecmp[31:0];
            12'h00C:
                PRDATA = mtimecmp[63:32];
            default:
                PRDATA = 32'b0;
        endcase
    end
endmodule
