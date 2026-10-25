`timescale 1ns / 1ps

// Firewall on the Secure DMA's bus port. Whatever the DMA registers say, it may only
//   - read the App ROM window (0x6000_0000 + 4 KB) and the SHA-256 STATUS register,
//   - write the SHA-256 block registers and CTRL (0x5000_0000 to 0x5000_0043).
// Everything else (RAM, APB peripherals, the Boot ROM, unmapped space) is blocked. The block is
// combinational: a blocked request never reaches the AXI master, and the DMA gets fw_viol instead.
module DMA_Firewall #(
    parameter [31:0] ROM_BASE = 32'h6000_0000,
    parameter [31:0] ROM_SIZE = 32'h0000_1000,
    parameter [31:0] SHA_BASE = 32'h5000_0000
)(
    input             req_valid,
    input             req_write,
    input      [31:0] req_addr,
    output            allow,         // 1 = the request may go to the bus
    output            violation      // 1 = a request is pending and the firewall blocks it
);
    wire aligned = (req_addr[1:0] == 2'b00);
    wire rd_rom  = (req_addr - ROM_BASE) < ROM_SIZE;
    wire rd_sha  = (req_addr == SHA_BASE + 32'h44);
    wire wr_sha  = (req_addr - SHA_BASE) < 32'h44;
    wire ok      = aligned && (req_write ? wr_sha : (rd_rom || rd_sha));

    assign allow     = req_valid && ok;
    assign violation = req_valid && !ok;
endmodule
