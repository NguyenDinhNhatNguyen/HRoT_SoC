`timescale 1ns / 1ps

// SYSCSR - thanh ghi he thong cua the gioi Secure (APB slave, 0 wait state)
// Kiem luon bo sinh reset he thong (sys_rst) va giu reset App Core (thay Reset_Controller cu)
//
// Ban do thanh ghi (offset):
//   0x00 APP_CTRL   RW  bit0 APP_RUN: 1 = nha reset App Core, 0 = giu reset (tuong thich 0x4000_0000 cu)
//   0x04 CHIP_ID    RO  0x48524F54 ("HROT")
//   0x08 VERSION    RO  0x0002_0000 (v2.0)
//   0x0C BOOT_STRAP RO  [3:0] chan boot_strap chot luc reset
//   0x10 RST_CAUSE  RW1C bit0 POR, bit1 WDT, bit2 SW (chi bi xoa boi POR hoac ghi 1)
//   0x14 SW_RESET   WO  ghi 0x5A5A_0001 -> reset toan he thong
//   offset khac: doc 0, ghi bo qua
module SYSCSR #(
    parameter RST_HOLD = 4              // so chu ky giu sys_rst sau yeu cau reset
)(
    input             clk,
    input             por_rst,         // reset nguon / nut bam (bat dong bo phia ngoai da dong bo hoa)
    input             wdt_rst_req,     // xung yeu cau reset tu WDT
    output            sys_rst,         // reset cho phan con lai cua the gioi Secure
    output            app_rst,         // reset App Core (1 = giu reset)
    input      [3:0]  boot_strap,

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
    localparam [31:0] CHIP_ID = 32'h48524F54;
    localparam [31:0] VERSION = 32'h00020000;
    localparam [31:0] SW_KEY  = 32'h5A5A0001;

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    wire wr = PSEL && PENABLE && PWRITE;

    // ---- Bo sinh reset he thong ----
    wire sw_req = wr && (PADDR == 12'h014) && (PWDATA == SW_KEY);
    reg  [3:0] hold_cnt;
    reg        sys_rst_q;
    always @(posedge clk) begin
        if (por_rst) begin
            hold_cnt  <= RST_HOLD;
            sys_rst_q <= 1'b1;
        end else if (sw_req || wdt_rst_req) begin
            hold_cnt  <= RST_HOLD;
            sys_rst_q <= 1'b1;
        end else if (hold_cnt != 0) begin
            hold_cnt  <= hold_cnt - 4'd1;
        end else begin
            sys_rst_q <= 1'b0;
        end
    end
    assign sys_rst = sys_rst_q;

    // ---- Nguyen nhan reset: chi POR moi xoa ----
    reg [2:0] rst_cause;
    always @(posedge clk) begin
        if (por_rst)
            rst_cause <= 3'b001;
        else begin
            if (wr && PADDR == 12'h010) rst_cause <= rst_cause & ~PWDATA[2:0];
            if (wdt_rst_req) rst_cause[1] <= 1'b1;
            if (sw_req)      rst_cause[2] <= 1'b1;
        end
    end

    // ---- Thanh ghi reset theo sys_rst ----
    reg       app_run;
    reg [3:0] strap_q;
    always @(posedge clk) begin
        if (sys_rst_q) begin
            app_run <= 1'b0;
            strap_q <= boot_strap;      // chot strap khi dang reset
        end else if (wr && PADDR == 12'h000 && PSTRB[0]) begin
            app_run <= PWDATA[0];
        end
    end
    assign app_rst = sys_rst_q | ~app_run;

    always @(*) begin
        case (PADDR)
            12'h000: PRDATA = {31'b0, app_run};
            12'h004: PRDATA = CHIP_ID;
            12'h008: PRDATA = VERSION;
            12'h00C: PRDATA = {28'b0, strap_q};
            12'h010: PRDATA = {29'b0, rst_cause};
            default: PRDATA = 32'b0;
        endcase
    end
endmodule
