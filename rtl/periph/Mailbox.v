`timescale 1ns / 1ps

// Mailbox: the only data path between the Secure world and the App world besides the read-only
// App ROM port. One 32-bit word in each direction, each with a FULL flag. Two APB slaves,
// "s" on the Secure bus and "a" on the App bus, both with the same register layout seen from
// their own side.
//
// Registers (offset), same on both sides:
//   0x00 OUT      RW  write sends a word to the other side. Ignored while OUT_FULL is set
//   0x04 IN       RO  the word sent by the other side. Reading it clears IN_FULL
//   0x08 STATUS   RO  bit0 IN_FULL (a word is waiting for me), bit1 OUT_FULL (my word is not read yet)
//   0x0C IRQ_EN   RW  bit0 raise irq while IN_FULL is set
//   other offsets: read 0, writes ignored
module Mailbox (
    input             clk, reset,
    output            irq_s,         // Secure side: a word from the App is waiting (to PLIC source 3)
    output            irq_a,         // App side: a word from the Secure world is waiting (to the App core's irq_ext, P-09)

    // APB4 slave, Secure side
    input      [11:0] s_PADDR,
    input             s_PSEL,
    input             s_PENABLE,
    input             s_PWRITE,
    input      [31:0] s_PWDATA,
    input      [3:0]  s_PSTRB,
    output reg [31:0] s_PRDATA,
    output            s_PREADY,
    output            s_PSLVERR,

    // APB4 slave, App side
    input      [11:0] a_PADDR,
    input             a_PSEL,
    input             a_PENABLE,
    input             a_PWRITE,
    input      [31:0] a_PWDATA,
    input      [3:0]  a_PSTRB,
    output reg [31:0] a_PRDATA,
    output            a_PREADY,
    output            a_PSLVERR
);
    assign s_PREADY  = 1'b1;
    assign s_PSLVERR = 1'b0;
    assign a_PREADY  = 1'b1;
    assign a_PSLVERR = 1'b0;

    wire s_wr = s_PSEL && s_PENABLE && s_PWRITE;
    wire s_rd = s_PSEL && s_PENABLE && !s_PWRITE;
    wire a_wr = a_PSEL && a_PENABLE && a_PWRITE;
    wire a_rd = a_PSEL && a_PENABLE && !a_PWRITE;

    reg [31:0] m2a_data, a2m_data;       // Secure to App, App to Secure
    reg        m2a_full, a2m_full;
    reg        s_irq_en, a_irq_en;

    always @(posedge clk) begin
        if (reset) begin
            m2a_data <= 32'b0;
            a2m_data <= 32'b0;
            m2a_full <= 1'b0;
            a2m_full <= 1'b0;
            s_irq_en <= 1'b0;
            a_irq_en <= 1'b0;
        end else begin
            // A read pops the word. A send only happens while the flag is clear, so the two never collide
            if (a_rd && a_PADDR == 12'h004)
                m2a_full <= 1'b0;
            if (s_rd && s_PADDR == 12'h004)
                a2m_full <= 1'b0;
            if (s_wr && s_PADDR == 12'h000 && !m2a_full) begin
                m2a_data <= s_PWDATA;
                m2a_full <= 1'b1;
            end
            if (a_wr && a_PADDR == 12'h000 && !a2m_full) begin
                a2m_data <= a_PWDATA;
                a2m_full <= 1'b1;
            end
            if (s_wr && s_PADDR == 12'h00C && s_PSTRB[0])
                s_irq_en <= s_PWDATA[0];
            if (a_wr && a_PADDR == 12'h00C && a_PSTRB[0])
                a_irq_en <= a_PWDATA[0];
        end
    end

    assign irq_s = s_irq_en & a2m_full;
    assign irq_a = a_irq_en & m2a_full;

    always @(*) begin
        case (s_PADDR)
            12'h000:
                s_PRDATA = m2a_data;
            12'h004:
                s_PRDATA = a2m_data;
            12'h008:
                s_PRDATA = {30'b0, m2a_full, a2m_full};
            12'h00C:
                s_PRDATA = {31'b0, s_irq_en};
            default:
                s_PRDATA = 32'b0;
        endcase
    end

    always @(*) begin
        case (a_PADDR)
            12'h000:
                a_PRDATA = a2m_data;
            12'h004:
                a_PRDATA = m2a_data;
            12'h008:
                a_PRDATA = {30'b0, a2m_full, m2a_full};
            12'h00C:
                a_PRDATA = {31'b0, a_irq_en};
            default:
                a_PRDATA = 32'b0;
        endcase
    end
endmodule
