// SHA-256 core behind an AXI4-Lite slave
// Registers (offset from 0x5000_0000):
//   0x00-0x3C : W      (WO) the 16 block words, 0x00 = W0
//   0x40      : CTRL   (WO) bit0 = start, bit1 = init (first block of a message)
//   0x44      : STATUS (RO) bit0 = done, bit1 = busy
//   0x50-0x6C : HASH   (RO) 8 words, 0x50 = H0
module SHA256_Wrapper (
    input             clk, reset,
    // AXI4-Lite port (Master Core bus)
    input             S_AXI_AWVALID,
    output            S_AXI_AWREADY,
    input      [31:0] S_AXI_AWADDR,
    input             S_AXI_WVALID,
    output            S_AXI_WREADY,
    input      [31:0] S_AXI_WDATA,
    output            S_AXI_BVALID,
    input             S_AXI_BREADY,
    input             S_AXI_ARVALID,
    output            S_AXI_ARREADY,
    input      [31:0] S_AXI_ARADDR,
    output            S_AXI_RVALID,
    input             S_AXI_RREADY,
    output     [31:0] S_AXI_RDATA
);
    wire        reg_wen;
    wire [31:0] reg_waddr, reg_wdata, reg_raddr;
    reg  [31:0] reg_rdata;

    AXI4_Lite_Slave_Template axi_slave (
        .clk(clk), .reset(reset),
        .S_AXI_AWVALID(S_AXI_AWVALID), .S_AXI_AWREADY(S_AXI_AWREADY), .S_AXI_AWADDR(S_AXI_AWADDR),
        .S_AXI_WVALID(S_AXI_WVALID),   .S_AXI_WREADY(S_AXI_WREADY),   .S_AXI_WDATA(S_AXI_WDATA),
        .S_AXI_WSTRB(4'hF),            // SHA registers take full 32-bit writes only (HAL contract #7)
        .S_AXI_BVALID(S_AXI_BVALID),   .S_AXI_BREADY(S_AXI_BREADY),   .S_AXI_BRESP(),
        .S_AXI_ARVALID(S_AXI_ARVALID), .S_AXI_ARREADY(S_AXI_ARREADY), .S_AXI_ARADDR(S_AXI_ARADDR),
        .S_AXI_RVALID(S_AXI_RVALID),   .S_AXI_RREADY(S_AXI_RREADY),   .S_AXI_RDATA(S_AXI_RDATA),
        .S_AXI_RRESP(),
        .reg_wen(reg_wen), .reg_waddr(reg_waddr), .reg_wdata(reg_wdata), .reg_wstrb(),
        .reg_raddr(reg_raddr), .reg_rdata(reg_rdata)
    );

    reg  [511:0] block_in;
    wire         busy, done;
    wire [255:0] hash_out;
    // The SoC gives SHA a 64 KB window. Offsets >= 0x100 are empty (read 0, writes ignored)
    // instead of aliasing onto the real registers (I-05)
    wire         wen   = reg_wen && (reg_waddr[15:8] == 8'h00);
    wire         ren   = (reg_raddr[15:8] == 8'h00);
    wire         start = wen && (reg_waddr[7:0] == 8'h40) && reg_wdata[0];
    wire         init  = reg_wdata[1];

    SHA256_Core core_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .init(init),
        .block_in(block_in),
        .busy(busy),
        .done(done),
        .hash_out(hash_out)
    );

    // W0..W15 writes are ignored while busy so block_in can't change mid-hash
    always @(posedge clk) begin
        if (wen && !busy && reg_waddr[7:6] == 2'b00)
            block_in[511 - 32*reg_waddr[5:2] -: 32] <= reg_wdata;
    end

    wire [2:0] hash_idx = reg_raddr[4:2] + 3'd4;   // 0x50 -> 0 ... 0x6C -> 7

    always @(*) begin
        if (ren && reg_raddr[7:0] == 8'h44)
            reg_rdata = {30'b0, busy, done};
        else if (ren && reg_raddr[7:0] >= 8'h50 && reg_raddr[7:0] <= 8'h6C)
            reg_rdata = hash_out[255 - 32*hash_idx -: 32];
        else
            reg_rdata = 32'b0;
    end
endmodule
