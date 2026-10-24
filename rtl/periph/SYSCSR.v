`timescale 1ns / 1ps

// SYSCSR: system registers of the Secure world (APB slave, zero wait states).
// Also owns the system reset generator (sys_rst) and the App Core reset hold.
//
// Registers (offset):
//   0x00 APP_CTRL   RW  bit0 APP_RUN: 1 = release the App Core, 0 = hold it in reset
//   0x04 CHIP_ID    RO  0x48524F54 ("HROT")
//   0x08 VERSION    RO  0x0002_0000 (v2.0)
//   0x0C BOOT_STRAP RO  [3:0] boot_strap pins, latched during reset
//   0x10 RST_CAUSE  RW1C bit0 POR, bit1 WDT, bit2 SW (only POR or a write of 1 clears a bit)
//   0x14 SW_RESET   WO  write 0x5A5A_0001 to reset the whole Secure world
//   other offsets: read 0, writes ignored
module SYSCSR #(
    parameter RST_HOLD = 4              // cycles sys_rst stays high after a reset request
)(
    input             clk,
    input             por_rst,         // power-on / push-button reset, already synchronized outside
    input             wdt_rst_req,     // reset request pulse from the WDT
    output            sys_rst,         // reset for the rest of the Secure world
    output            app_rst,         // App Core reset (1 = held)
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

    // ---- System reset generator ----
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

    // ---- Reset cause: survives SW/WDT resets, cleared only by POR ----
    reg [2:0] rst_cause;
    always @(posedge clk) begin
        if (por_rst)
            rst_cause <= 3'b001;
        else begin
            if (wr && PADDR == 12'h010)
                rst_cause <= rst_cause & ~PWDATA[2:0];
            if (wdt_rst_req)
                rst_cause[1] <= 1'b1;
            if (sw_req)
                rst_cause[2] <= 1'b1;
        end
    end

    // ---- Registers reset by sys_rst ----
    reg       app_run;
    reg [3:0] strap_q;
    always @(posedge clk) begin
        if (sys_rst_q) begin
            app_run <= 1'b0;
            strap_q <= boot_strap;      // latch the straps while in reset
        end else if (wr && PADDR == 12'h000 && PSTRB[0]) begin
            app_run <= PWDATA[0];
        end
    end
    assign app_rst = sys_rst_q | ~app_run;

    always @(*) begin
        case (PADDR)
            12'h000:
                PRDATA = {31'b0, app_run};
            12'h004:
                PRDATA = CHIP_ID;
            12'h008:
                PRDATA = VERSION;
            12'h00C:
                PRDATA = {28'b0, strap_q};
            12'h010:
                PRDATA = {29'b0, rst_cause};
            default:
                PRDATA = 32'b0;
        endcase
    end
endmodule
