`timescale 1ns / 1ps

// Secure DMA: streams the App ROM (read through port B on the Master bus) into the SHA-256 block
// registers, block by block, and optionally appends the SHA-256 padding block. The CPU only
// programs it and reads the digest, so hashing the whole 4 KB App image costs the CPU no bus cycles.
// It is a bus master of its own: its request port goes through an arbiter to the shared AXI master
// and through DMA_Firewall, so it can only ever touch the App ROM and the SHA-256 block.
// While BUSY the DMA owns the SHA-256 block: the CPU must not touch it.
//
// Registers (offset, APB slave, zero wait states):
//   0x00 SRC     RW  byte address of the first word to hash, word aligned. Reset 0x6000_0000
//   0x04 NBLK    RW  number of 64-byte blocks to read. Reset 64 (the whole 4 KB App ROM)
//   0x08 CTRL    RW  bit0 START (write 1, always reads 0), bit1 SWAP, bit2 PAD, bit3 IRQ_EN
//                    SWAP: reverse the bytes of every word, so the digest equals sha256 of the
//                    little-endian memory image (what sha256sum gives for the .bin)
//                    PAD: after the data blocks hash the padding block for NBLK * 64 bytes
//   0x0C STATUS  RW1C bit0 BUSY (RO), bit1 DONE, bit2 ERR_FW (firewall blocked a request),
//                    bit3 ERR_BUS (SLVERR or DECERR on the bus). START clears DONE and both errors
//   SRC, NBLK and the CTRL options are write-protected while BUSY
module Secure_DMA #(
    parameter [31:0] SHA_BASE = 32'h5000_0000
)(
    input             clk, reset,
    output            irq,           // DONE and IRQ_EN, to PLIC source 2

    // APB4 slave
    input      [11:0] PADDR,
    input             PSEL,
    input             PENABLE,
    input             PWRITE,
    input      [31:0] PWDATA,
    input      [3:0]  PSTRB,
    output reg [31:0] PRDATA,
    output            PREADY,
    output            PSLVERR,

    // Request port towards the Master bus arbiter. A request stays up until resp_valid
    output reg        req_valid,
    output reg        req_write,
    output reg [31:0] req_addr,
    output reg [31:0] req_wdata,
    input             resp_valid,    // one-cycle pulse for our request
    input      [31:0] resp_rdata,
    input             resp_err,      // that response was SLVERR or DECERR
    input             fw_viol        // DMA_Firewall blocked the pending request
);
    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    localparam [2:0] S_IDLE = 3'd0,
                     S_RD   = 3'd1,      // waiting for a read of the source word
                     S_WR   = 3'd2,      // waiting for a write of one word into the SHA-256 block
                     S_CTL  = 3'd3,      // waiting for the write of SHA-256 CTRL (start)
                     S_POLL = 3'd4;      // polling SHA-256 STATUS until the block is done

    reg [2:0]  st;
    reg [31:0] src_q, nblk_q;
    reg        swap_q, pad_q, irq_en_q;
    reg        busy, done, err_fw, err_bus;
    reg [31:0] ptr, left;
    reg [3:0]  w;                        // word index inside the 16-word block
    reg        first, in_pad;

    wire wr    = PSEL && PENABLE && PWRITE;
    wire start = wr && PADDR == 12'h008 && PWDATA[0] && st == S_IDLE;

    assign irq = irq_en_q & done;

    function [31:0] bswap;
        input [31:0] x;
        begin
            bswap = {x[7:0], x[15:8], x[23:16], x[31:24]};
        end
    endfunction

    // SHA-256 padding block for a message of n 64-byte blocks: 0x80, zeros, then the bit length
    function [31:0] padword;
        input [3:0]  i;
        input [31:0] n;
        begin
            if (i == 4'd0)
                padword = 32'h8000_0000;
            else if (i == 4'd15)
                padword = {n[22:0], 9'b0};
            else
                padword = 32'b0;
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            st        <= S_IDLE;
            src_q     <= 32'h6000_0000;
            nblk_q    <= 32'd64;
            swap_q    <= 1'b0;
            pad_q     <= 1'b0;
            irq_en_q  <= 1'b0;
            busy      <= 1'b0;
            done      <= 1'b0;
            err_fw    <= 1'b0;
            err_bus   <= 1'b0;
            ptr       <= 32'b0;
            left      <= 32'b0;
            w         <= 4'b0;
            first     <= 1'b0;
            in_pad    <= 1'b0;
            req_valid <= 1'b0;
            req_write <= 1'b0;
            req_addr  <= 32'b0;
            req_wdata <= 32'b0;
        end else begin
            if (wr && st == S_IDLE) begin
                if (PADDR == 12'h000)
                    src_q <= PWDATA;
                if (PADDR == 12'h004)
                    nblk_q <= PWDATA;
                if (PADDR == 12'h008) begin
                    swap_q   <= PWDATA[1];
                    pad_q    <= PWDATA[2];
                    irq_en_q <= PWDATA[3];
                end
            end
            if (wr && PADDR == 12'h00C) begin
                if (PWDATA[1])
                    done <= 1'b0;
                if (PWDATA[2])
                    err_fw <= 1'b0;
                if (PWDATA[3])
                    err_bus <= 1'b0;
            end

            case (st)
                S_IDLE: begin
                    if (start) begin
                        done    <= 1'b0;
                        err_fw  <= 1'b0;
                        err_bus <= 1'b0;
                        if (nblk_q == 32'd0) begin
                            done <= 1'b1;               // nothing to hash
                        end else begin
                            busy      <= 1'b1;
                            ptr       <= src_q;
                            left      <= nblk_q;
                            w         <= 4'd0;
                            first     <= 1'b1;
                            in_pad    <= 1'b0;
                            st        <= S_RD;
                            req_valid <= 1'b1;
                            req_write <= 1'b0;
                            req_addr  <= src_q;
                        end
                    end
                end

                S_RD: begin
                    if (fw_viol) begin
                        req_valid <= 1'b0;
                        busy      <= 1'b0;
                        done      <= 1'b1;
                        err_fw    <= 1'b1;
                        st        <= S_IDLE;
                    end else if (resp_valid) begin
                        if (resp_err) begin
                            req_valid <= 1'b0;
                            busy      <= 1'b0;
                            done      <= 1'b1;
                            err_bus   <= 1'b1;
                            st        <= S_IDLE;
                        end else begin
                            st        <= S_WR;
                            req_write <= 1'b1;
                            req_addr  <= SHA_BASE + {26'b0, w, 2'b00};
                            req_wdata <= swap_q ? bswap(resp_rdata) : resp_rdata;
                        end
                    end
                end

                S_WR: begin
                    if (fw_viol) begin
                        req_valid <= 1'b0;
                        busy      <= 1'b0;
                        done      <= 1'b1;
                        err_fw    <= 1'b1;
                        st        <= S_IDLE;
                    end else if (resp_valid) begin
                        if (resp_err) begin
                            req_valid <= 1'b0;
                            busy      <= 1'b0;
                            done      <= 1'b1;
                            err_bus   <= 1'b1;
                            st        <= S_IDLE;
                        end else begin
                            ptr <= ptr + 32'd4;
                            w   <= w + 4'd1;
                            if (w == 4'd15) begin
                                st        <= S_CTL;
                                req_addr  <= SHA_BASE + 32'h40;
                                req_wdata <= first ? 32'd3 : 32'd1;     // START, plus INIT on the first block
                            end else if (in_pad) begin
                                req_addr  <= SHA_BASE + {26'b0, w + 4'd1, 2'b00};
                                req_wdata <= padword(w + 4'd1, nblk_q);
                            end else begin
                                st        <= S_RD;
                                req_write <= 1'b0;
                                req_addr  <= ptr + 32'd4;
                            end
                        end
                    end
                end

                S_CTL: begin
                    if (fw_viol) begin
                        req_valid <= 1'b0;
                        busy      <= 1'b0;
                        done      <= 1'b1;
                        err_fw    <= 1'b1;
                        st        <= S_IDLE;
                    end else if (resp_valid) begin
                        if (resp_err) begin
                            req_valid <= 1'b0;
                            busy      <= 1'b0;
                            done      <= 1'b1;
                            err_bus   <= 1'b1;
                            st        <= S_IDLE;
                        end else begin
                            first     <= 1'b0;
                            st        <= S_POLL;
                            req_write <= 1'b0;
                            req_addr  <= SHA_BASE + 32'h44;
                        end
                    end
                end

                S_POLL: begin
                    if (fw_viol) begin
                        req_valid <= 1'b0;
                        busy      <= 1'b0;
                        done      <= 1'b1;
                        err_fw    <= 1'b1;
                        st        <= S_IDLE;
                    end else if (resp_valid) begin
                        if (resp_err) begin
                            req_valid <= 1'b0;
                            busy      <= 1'b0;
                            done      <= 1'b1;
                            err_bus   <= 1'b1;
                            st        <= S_IDLE;
                        end else if (resp_rdata[0]) begin
                            // This block is hashed. The request stays up, so a not-done answer just polls again
                            if (in_pad || (left == 32'd1 && !pad_q)) begin
                                req_valid <= 1'b0;
                                busy      <= 1'b0;
                                done      <= 1'b1;
                                st        <= S_IDLE;
                            end else if (left == 32'd1) begin
                                in_pad    <= 1'b1;
                                w         <= 4'd0;
                                st        <= S_WR;
                                req_write <= 1'b1;
                                req_addr  <= SHA_BASE;
                                req_wdata <= padword(4'd0, nblk_q);
                            end else begin
                                left      <= left - 32'd1;
                                w         <= 4'd0;
                                st        <= S_RD;
                                req_write <= 1'b0;
                                req_addr  <= ptr;
                            end
                        end
                    end
                end

                default:
                    st <= S_IDLE;
            endcase
        end
    end

    always @(*) begin
        case (PADDR)
            12'h000:
                PRDATA = src_q;
            12'h004:
                PRDATA = nblk_q;
            12'h008:
                PRDATA = {28'b0, irq_en_q, pad_q, swap_q, 1'b0};
            12'h00C:
                PRDATA = {28'b0, err_bus, err_fw, done, busy};
            default:
                PRDATA = 32'b0;
        endcase
    end
endmodule
