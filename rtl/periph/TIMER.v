`timescale 1ns / 1ps

// TIMER kieu CLINT: mtime 64-bit dem moi chu ky clk, ngat khi mtime >= mtimecmp (APB slave, 0 wait state)
//
// Ban do thanh ghi (offset), chi ghi ca word 32-bit:
//   0x00 MTIME_LO    RW  [31:0]  cua mtime
//   0x04 MTIME_HI    RW  [63:32] cua mtime (doc 64-bit: HI, LO, HI lai neu HI doi)
//   0x08 MTIMECMP_LO RW  [31:0]  cua mtimecmp
//   0x0C MTIMECMP_HI RW  [63:32] cua mtimecmp (reset = toan 1 -> khong ngat sau reset)
//   offset khac: doc 0, ghi bo qua
// irq muc cao, tre 1 chu ky (thanh ghi hoa so sanh 64-bit de khong vao duong gang)
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
            // ghi tu bus thang phep dem trong cung chu ky
            if (wr && PADDR == 12'h000)      mtime[31:0]  <= PWDATA;
            else if (wr && PADDR == 12'h004) mtime[63:32] <= PWDATA;
            else                             mtime        <= mtime + 64'd1;
            if (wr && PADDR == 12'h008) mtimecmp[31:0]  <= PWDATA;
            if (wr && PADDR == 12'h00C) mtimecmp[63:32] <= PWDATA;
            irq <= (mtime >= mtimecmp);
        end
    end

    always @(*) begin
        case (PADDR)
            12'h000: PRDATA = mtime[31:0];
            12'h004: PRDATA = mtime[63:32];
            12'h008: PRDATA = mtimecmp[31:0];
            12'h00C: PRDATA = mtimecmp[63:32];
            default: PRDATA = 32'b0;
        endcase
    end
endmodule
