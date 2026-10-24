`timescale 1ns / 1ps

// Secure-world watchdog (APB slave, zero wait states).
// Counts down from LOAD. Reaching 0 while enabled sends rst_req to SYSCSR, which resets the
// Secure world and sets RST_CAUSE.WDT.
//
// Registers (offset):
//   0x00 CTRL  RW  bit0 EN: write 1 to start (COUNT = LOAD). Once on, only a reset turns it off
//   0x04 LOAD  RW  timeout in cycles, locked (writes ignored) while EN = 1. Reset value 50_000_000 (1 s at 50 MHz)
//   0x08 COUNT RO  current count
//   0x0C KICK  WO  write 0x5A5A_0002 to reload COUNT = LOAD, any other value is ignored
//   other offsets: read 0, writes ignored
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
            if (en_set)
                en <= 1'b1;
            if (wr && PADDR == 12'h004 && !en)
                load <= PWDATA;
            if (en_set || (en && kick))
                count <= load;
            else if (en && count != 0)
                count <= count - 32'd1;
        end
    end

    // Level while count == 0, but SYSCSR resets the WDT on the next cycle, so in practice it's a pulse
    assign rst_req = en && (count == 0);

    always @(*) begin
        case (PADDR)
            12'h000:
                PRDATA = {31'b0, en};
            12'h004:
                PRDATA = load;
            12'h008:
                PRDATA = count;
            default:
                PRDATA = 32'b0;
        endcase
    end
endmodule
