`timescale 1ns / 1ps

// UART 8N1, 16x oversampling, 8-byte TX/RX FIFOs (APB slave, zero wait states)
//
// Registers (offset):
//   0x00 TXDATA   WO  [7:0] push into the TX FIFO (dropped if full)
//   0x04 RXDATA   RO  [7:0] pop from the RX FIFO, bit31 = 1 when the RX FIFO is empty
//   0x08 STATUS   RO  bit0 TX_FULL, bit1 TX_IDLE (FIFO empty and nothing on the wire),
//                     bit2 RX_VALID, bit3 RX_OVERRUN, bit4 FRAME_ERR
//                 W1C bit3, bit4
//   0x0C BAUD_DIV RW  [15:0] = f_clk / (16 * baud) - 1   (default 26: 115200 baud at 50 MHz)
//   0x10 IRQ_EN   RW  bit0 interrupt on RX_VALID, bit1 interrupt on TX_IDLE
module UART #(
    parameter [15:0] BAUD_DIV_RST = 16'd26
)(
    input             clk, reset,
    output            uart_tx,
    input             uart_rx,
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

    wire wr = PSEL && PENABLE &&  PWRITE;
    wire rd = PSEL && PENABLE && !PWRITE;

    reg [15:0] baud_div;
    reg [1:0]  irq_en;
    reg        overrun, frame_err;

    // ---- 16x baud tick ----
    reg [15:0] tick_cnt;
    wire       tick = (tick_cnt == 16'd0);
    wire baud_wr = wr && (PADDR == 12'h00C);
    always @(posedge clk) begin
        if (reset)
            tick_cnt <= BAUD_DIV_RST;
        else if (baud_wr)
            tick_cnt <= PWDATA[15:0];   // a new divisor applies at once, no waiting out the old period
        else if (tick)
            tick_cnt <= baud_div;
        else
            tick_cnt <= tick_cnt - 16'd1;
    end

    // ---- FIFO ----
    wire       tx_full, tx_empty, rx_full, rx_empty;
    wire [7:0] tx_dout, rx_dout;
    reg        tx_pop, rx_push;
    reg  [7:0] rx_byte;

    Sync_FIFO #(.DW(8), .AW(3)) tx_fifo (
        .clk(clk), .reset(reset),
        .push(wr && PADDR == 12'h000), .din(PWDATA[7:0]),
        .pop(tx_pop), .dout(tx_dout), .full(tx_full), .empty(tx_empty)
    );
    Sync_FIFO #(.DW(8), .AW(3)) rx_fifo (
        .clk(clk), .reset(reset),
        .push(rx_push), .din(rx_byte),
        .pop(rd && PADDR == 12'h004), .dout(rx_dout), .full(rx_full), .empty(rx_empty)
    );

    // ---- TX: 10-bit frame {stop, data[7:0], start} ----
    reg [9:0] tx_shift;
    reg [3:0] tx_bits;      // bits left to send, 0 = idle
    reg [3:0] tx_sub;       // 16 ticks per bit
    always @(posedge clk) begin
        tx_pop <= 1'b0;
        if (reset) begin
            tx_shift <= 10'h3FF;
            tx_bits  <= 4'd0;
            tx_sub   <= 4'd0;
        end else if (tx_bits == 4'd0) begin
            if (!tx_empty && !tx_pop) begin
                tx_shift <= {1'b1, tx_dout, 1'b0};
                tx_bits  <= 4'd10;
                tx_sub   <= 4'd0;
                tx_pop   <= 1'b1;
            end
        end else if (tick) begin
            if (tx_sub == 4'd15) begin
                tx_shift <= {1'b1, tx_shift[9:1]};
                tx_bits  <= tx_bits - 4'd1;
            end
            tx_sub <= tx_sub + 4'd1;
        end
    end
    assign uart_tx = tx_shift[0];
    wire tx_idle = tx_empty && (tx_bits == 4'd0);

    // ---- RX: 2-flop synchronizer, sample in the middle of each bit ----
    reg [1:0] rx_sync;
    always @(posedge clk) rx_sync <= reset ? 2'b11 : {rx_sync[0], uart_rx};
    wire rx_in = rx_sync[1];

    reg [3:0] rx_sub;
    reg [3:0] rx_bits;      // 0 = waiting for start, 1..8 data, 9 stop
    reg [7:0] rx_shift;
    always @(posedge clk) begin
        rx_push <= 1'b0;
        if (reset) begin
            rx_sub    <= 4'd0;
            rx_bits   <= 4'd0;
            rx_shift  <= 8'd0;
            rx_byte   <= 8'd0;
            overrun   <= 1'b0;
            frame_err <= 1'b0;
        end else begin
            if (wr && PADDR == 12'h008) begin
                if (PWDATA[3])
                    overrun <= 1'b0;
                if (PWDATA[4])
                    frame_err <= 1'b0;
            end
            if (tick) begin
                if (rx_bits == 4'd0) begin
                    // wait for a falling edge, then re-check it mid start bit
                    if (!rx_in) begin
                        if (rx_sub == 4'd7) begin
                            rx_sub  <= 4'd0;
                            rx_bits <= 4'd1;
                        end else
                            rx_sub <= rx_sub + 4'd1;
                    end else
                        rx_sub <= 4'd0;
                end else begin
                    if (rx_sub == 4'd15) begin
                        rx_sub <= 4'd0;
                        if (rx_bits == 4'd9) begin
                            rx_bits <= 4'd0;
                            if (!rx_in)
                                frame_err <= 1'b1;
                            else if (rx_full)
                                overrun <= 1'b1;
                            else begin
                                rx_byte <= rx_shift;
                                rx_push <= 1'b1;
                            end
                        end else begin
                            rx_shift <= {rx_in, rx_shift[7:1]};
                            rx_bits  <= rx_bits + 4'd1;
                        end
                    end else
                        rx_sub <= rx_sub + 4'd1;
                end
            end
        end
    end

    // ---- Config registers ----
    always @(posedge clk) begin
        if (reset) begin
            baud_div <= BAUD_DIV_RST;
            irq_en   <= 2'b00;
        end else if (wr) begin
            if (PADDR == 12'h00C)
                baud_div <= PWDATA[15:0];
            if (PADDR == 12'h010)
                irq_en <= PWDATA[1:0];
        end
    end

    assign irq = (irq_en[0] && !rx_empty) || (irq_en[1] && tx_idle);

    always @(*) begin
        case (PADDR)
            12'h004:
                PRDATA = {rx_empty, 23'b0, rx_dout};
            12'h008:
                PRDATA = {27'b0, frame_err, overrun, !rx_empty, tx_idle, tx_full};
            12'h00C:
                PRDATA = {16'b0, baud_div};
            12'h010:
                PRDATA = {30'b0, irq_en};
            default:
                PRDATA = 32'b0;
        endcase
    end
endmodule
