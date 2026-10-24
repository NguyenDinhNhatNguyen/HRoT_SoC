`timescale 1ns / 1ps

// Watchdog cua the gioi Secure (APB slave, 0 wait state)
// Dem xuong tu LOAD; ve 0 khi dang bat -> xung rst_req 1 chu ky sang SYSCSR (reset he thong, RST_CAUSE.WDT)
//
// Ban do thanh ghi (offset):
//   0x00 CTRL  RW  bit0 EN: ghi 1 de bat (nap COUNT = LOAD); da bat thi chi reset moi tat
//   0x04 LOAD  RW  so chu ky toi han; khoa (ghi bo qua) khi EN = 1. Reset = 50_000_000 (1 s @ 50 MHz)
//   0x08 COUNT RO  gia tri dem hien tai
//   0x0C KICK  WO  ghi 0x5A5A_0002 -> nap lai COUNT = LOAD; gia tri khac bi bo qua
//   offset khac: doc 0, ghi bo qua
module WDT #(
    parameter [31:0] LOAD_RST = 32'd50_000_000
)(
    input             clk, reset,
    output            rst_req,

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
    localparam [31:0] KICK_KEY = 32'h5A5A0002;

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    wire wr = PSEL && PENABLE && PWRITE;

    reg        en;
    reg [31:0] load, count;

    wire en_set = wr && PADDR == 12'h000 && PWDATA[0] && !en;
    wire kick   = wr && PADDR == 12'h00C && PWDATA == KICK_KEY;

    always @(posedge clk) begin
        if (reset) begin
            en    <= 1'b0;
            load  <= LOAD_RST;
            count <= LOAD_RST;
        end else begin
            if (en_set) en <= 1'b1;
            if (wr && PADDR == 12'h004 && !en) load <= PWDATA;
            if (en_set || (en && kick)) count <= load;
            else if (en && count != 0)  count <= count - 32'd1;
        end
    end

    // giu 1 khi count = 0, nhung SYSCSR reset ca WDT ngay chu ky sau nen thuc te la 1 xung
    assign rst_req = en && (count == 0);

    always @(*) begin
        case (PADDR)
            12'h000: PRDATA = {31'b0, en};
            12'h004: PRDATA = load;
            12'h008: PRDATA = count;
            default: PRDATA = 32'b0;
        endcase
    end
endmodule
