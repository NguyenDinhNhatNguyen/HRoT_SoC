`timescale 1ns / 1ps

// GPIO: 8 outputs, 8 inputs, rising-edge interrupts (APB slave, zero wait states)
//
// Registers (offset):
//   0x00 DATA_OUT RW  [7:0] -> gpio_o (LEDs)
//   0x04 DATA_IN  RO  [7:0] <- gpio_i (switches/keys), through a 2-flop synchronizer
//   0x08 IRQ_EN   RW  [7:0] per-pin rising-edge interrupt enable
//   0x0C IRQ_STAT W1C [7:0] pins that saw a rising edge (write 1 to clear)
module GPIO (
    input             clk, reset,
    output     [7:0]  gpio_o,
    input      [7:0]  gpio_i,
    output            irq,

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

    reg [7:0] out_q, en_q, stat_q;
    reg [7:0] s1, s2, s3;           // s1,s2 synchronize, s3 holds the previous value for edge detect

    always @(posedge clk) begin
        if (reset) begin
            s1 <= 8'b0;
            s2 <= 8'b0;
            s3 <= 8'b0;
        end else begin
            s1 <= gpio_i;
            s2 <= s1;
            s3 <= s2;
        end
    end

    wire [7:0] rise = s2 & ~s3;

    always @(posedge clk) begin
        if (reset) begin
            out_q  <= 8'b0;
            en_q   <= 8'b0;
            stat_q <= 8'b0;
        end else begin
            if (wr && PADDR == 12'h000 && PSTRB[0])
                out_q <= PWDATA[7:0];
            if (wr && PADDR == 12'h008 && PSTRB[0])
                en_q <= PWDATA[7:0];
            // an edge sets the flag, writing 1 clears it, and an edge in the same cycle wins
            stat_q <= (stat_q & ~((wr && PADDR == 12'h00C) ? PWDATA[7:0] : 8'b0)) | rise;
        end
    end

    assign gpio_o = out_q;
    assign irq    = |(stat_q & en_q);

    always @(*) begin
        case (PADDR)
            12'h000:
                PRDATA = {24'b0, out_q};
            12'h004:
                PRDATA = {24'b0, s2};
            12'h008:
                PRDATA = {24'b0, en_q};
            12'h00C:
                PRDATA = {24'b0, stat_q};
            default:
                PRDATA = 32'b0;
        endcase
    end
endmodule
