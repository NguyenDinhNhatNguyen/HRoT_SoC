`timescale 1ns / 1ps
`default_nettype none   // every net must be declared: a typo is an error, not a silent 1-bit wire

// ============================================================
// SoC top: two isolated worlds
//  - Master (Secure): Master Core + its own boot ROM + its own AXI4-Lite bus
//      0x0000_0000 : Boot ROM. The core fetches from it, and port B also serves loads (read-only),
//                    so constants such as the golden hash can live in ROM. Writes -> SLVERR
//      0x1000_0000 : Master RAM (secure boot stack and data)
//      0x4000_0000 : AXI-to-APB bridge, one 4 KB window per peripheral:
//                    0x4000_0000 SYSCSR (APP_CTRL at offset 0: write 1 to release the App Core)
//                    0x4000_1000 UART0, 0x4000_2000 GPIO0, 0x4000_3000 TIMER0, 0x4000_4000 WDT,
//                    0x4000_5000 PLIC-lite, 0x4000_6000 Mailbox (Secure side), 0x4000_7000 Secure DMA
//      0x5000_0000 : SHA-256
//      0x6000_0000 : App ROM port B (read-only) for hashing the App image, writes -> SLVERR
//      elsewhere   : default slave answers DECERR, so the bus never hangs
//    The bus has one AXI master that the CPU and the Secure DMA share (round robin).
//    The DMA sits behind DMA_Firewall, so it can only reach the App ROM and the SHA-256 block.
//  - App: App Core + ROM port A + its own RAM and its own APB peripherals. No path onto the Master bus
//      0x4000_0000 UART1, 0x4000_1000 GPIO1, 0x4000_2000 TIMER1, 0x4000_3000 Mailbox (App side)
//      any other address is the App RAM (aliased, as before)
//  - Bridges between the worlds: App ROM port B (Master reads App), Mailbox (one word each way),
//    and Boot Guard in SYSCSR (Master locks the App out and clears its RAM)
// ============================================================
module SoC_Top #(
    parameter BOOT_HEX = "../fw/build/firmware_imem.hex",   // secure_boot .text (fw/CMakeLists.txt)
    parameter RAM_HEX  = "../fw/build/firmware_dmem.hex",   // .rodata/.data, word 0 = 0x1000_0000
    parameter APP_HEX  = "../fw/build/app_firmware.hex"
)(
    input  wire       clk,
    input  wire       reset_system,  // power-on / push-button reset
    output wire       app_running,   // high once the Master releases the App (drives an LED on the board)
    // Secure-world peripherals
    output wire       uart0_tx,
    input  wire       uart0_rx,
    output wire [7:0] gpio0_o,       // LED
    input  wire [7:0] gpio0_i,       // switches / keys
    input  wire [3:0] boot_strap,    // boot mode switches (read through SYSCSR)
    // App-world peripherals
    output wire       uart1_tx,
    input  wire       uart1_rx,
    output wire [7:0] gpio1_o,
    input  wire [7:0] gpio1_i
);
    // sys_rst: Secure-world reset from SYSCSR (POR, SW reset or WDT)
    wire sys_rst;

    // ---------------- Master Core ----------------
    wire [31:0] boot_addr, boot_data;
    wire [31:0] master_data_addr, master_data_wdata, master_data_rdata;
    wire        master_data_we, master_data_re;
    wire [3:0]  master_data_wstrb;
    wire        master_resp_valid;

    // Interrupts for the Master Core.
    // TODO(P-09, I-01): RISCV_Core has no irq_timer/irq_ext ports yet (Phat is adding Zicsr and traps).
    // When it does, connect .irq_timer(timer0_irq) and .irq_ext(plic_irq) on master_core below.
    wire timer0_irq;
    wire plic_irq;

    // Stall while MEM has a request without a response yet (combinational, no extra cycle)
    wire master_bus_stall = (master_data_we | master_data_re) & ~master_resp_valid;

    RISCV_Core master_core (
        .clk(clk),
        .rst(sys_rst),
        .bus_stall(master_bus_stall),
        .instr_addr(boot_addr),
        .instr_rdata(boot_data),
        .data_addr(master_data_addr),
        .data_wdata(master_data_wdata),
        .data_wstrb(master_data_wstrb),
        .data_we(master_data_we),
        .data_re(master_data_re),
        .data_rdata(master_data_rdata),
        .PC_debug(), .Instr_debug(), .RegWrite_WB_debug(), .Rd_WB_debug(), .Result_WB_debug()
    );

    // ---------------- Shared AXI4-Lite master: CPU and Secure DMA ----------------
    wire        M_AXI_AWVALID, M_AXI_AWREADY, M_AXI_WVALID, M_AXI_WREADY;
    wire        M_AXI_BVALID, M_AXI_BREADY, M_AXI_ARVALID, M_AXI_ARREADY;
    wire        M_AXI_RVALID, M_AXI_RREADY;
    wire [31:0] M_AXI_AWADDR, M_AXI_WDATA, M_AXI_ARADDR, M_AXI_RDATA;
    wire [1:0]  M_AXI_BRESP, M_AXI_RRESP;
    wire [3:0]  M_AXI_WSTRB;
    wire        bus_err, bus_err_write;   // error responses reported to SYSCSR.BUS_ERR
    wire [1:0]  bus_err_resp;
    wire [31:0] bus_err_addr;

    // The DMA's request, filtered by the firewall before it can reach the bus
    wire        dma_req, dma_req_write, dma_req_ok, dma_fw_viol;
    wire [31:0] dma_req_addr, dma_req_wdata;
    DMA_Firewall dma_fw (
        .req_valid(dma_req), .req_write(dma_req_write), .req_addr(dma_req_addr),
        .allow(dma_req_ok), .violation(dma_fw_viol)
    );

    // Arbitration happens where the master accepts a request (idle and no response pending).
    // The master latches the request at that moment, so only the owner of the transfer is remembered.
    // Round robin: if both want the bus, the one that did not use it last goes first
    wire        cpu_req = master_data_we | master_data_re;
    wire        axi_req_ready, axi_resp_valid;
    wire [31:0] axi_resp_rdata;
    reg         own_dma_q;
    wire        bus_idle = axi_req_ready & ~axi_resp_valid;
    wire        pick_dma = dma_req_ok & (~cpu_req | ~own_dma_q);
    wire        sel_dma  = bus_idle ? pick_dma : own_dma_q;

    wire        axi_req_valid = sel_dma ? dma_req_ok : cpu_req;
    wire        axi_req_write = sel_dma ? dma_req_write : master_data_we;
    wire [31:0] axi_req_addr  = sel_dma ? dma_req_addr : master_data_addr;
    wire [31:0] axi_req_wdata = sel_dma ? dma_req_wdata : master_data_wdata;
    wire [3:0]  axi_req_wstrb = sel_dma ? 4'hF : master_data_wstrb;

    always @(posedge clk) begin
        if (sys_rst)
            own_dma_q <= 1'b0;
        else if (axi_req_valid & bus_idle)
            own_dma_q <= sel_dma;
    end

    assign master_resp_valid = axi_resp_valid & ~own_dma_q;
    assign master_data_rdata = axi_resp_rdata;
    wire dma_resp_valid = axi_resp_valid & own_dma_q;

    // TODO(P-09, I-01): access fault. data_err is high in the same cycle as resp_valid when a CPU access
    // got SLVERR or DECERR (DMA errors are reported to the DMA and SYSCSR.BUS_ERR, not trapped).
    // Connect .data_err(master_data_err) on master_core once the core has the port
    wire master_data_err = bus_err & master_resp_valid;

    AXI4_Lite_Master axi_master (
        .clk(clk),
        .reset(sys_rst),
        .req_valid(axi_req_valid),
        .req_write(axi_req_write),
        .req_addr(axi_req_addr),
        .req_wdata(axi_req_wdata),
        .req_wstrb(axi_req_wstrb),
        .req_ready(axi_req_ready),
        .resp_valid(axi_resp_valid),
        .resp_rdata(axi_resp_rdata),
        .err_valid(bus_err),
        .err_write(bus_err_write),
        .err_resp(bus_err_resp),
        .err_addr(bus_err_addr),

        .M_AXI_AWVALID(M_AXI_AWVALID), .M_AXI_AWREADY(M_AXI_AWREADY), .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_WVALID(M_AXI_WVALID),   .M_AXI_WREADY(M_AXI_WREADY),   .M_AXI_WDATA(M_AXI_WDATA),
        .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_BVALID(M_AXI_BVALID),   .M_AXI_BREADY(M_AXI_BREADY),   .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_ARVALID(M_AXI_ARVALID), .M_AXI_ARREADY(M_AXI_ARREADY), .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_RVALID(M_AXI_RVALID),   .M_AXI_RREADY(M_AXI_RREADY),   .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP)
    );

    // ---------------- Address decode (1 master, 6 slaves) ----------------
    // Slave order: 0 = RAM, 1 = APB bridge, 2 = SHA-256, 3 = App ROM port B, 4 = Boot ROM port B,
    // 5 = default (DECERR)
    wire [4:0] hit_w = {M_AXI_AWADDR[31:16] == 16'h0000, M_AXI_AWADDR[31:16] == 16'h6000,
                        M_AXI_AWADDR[31:16] == 16'h5000, M_AXI_AWADDR[31:16] == 16'h4000,
                        M_AXI_AWADDR[31:16] == 16'h1000};
    wire [4:0] hit_r = {M_AXI_ARADDR[31:16] == 16'h0000, M_AXI_ARADDR[31:16] == 16'h6000,
                        M_AXI_ARADDR[31:16] == 16'h5000, M_AXI_ARADDR[31:16] == 16'h4000,
                        M_AXI_ARADDR[31:16] == 16'h1000};
    wire [5:0] sel_w = {~|hit_w, hit_w};
    wire [5:0] sel_r = {~|hit_r, hit_r};

    wire [5:0]  s_awready, s_wready, s_bvalid, s_arready, s_rvalid;
    wire [31:0] s_rdata [0:5];
    wire [1:0]  s_bresp [0:5];
    wire [1:0]  s_rresp [0:5];

    // Only the selected slave drives READY/VALID, so OR-ing them is enough
    assign M_AXI_AWREADY = |s_awready;
    assign M_AXI_WREADY  = |s_wready;
    assign M_AXI_BVALID  = |s_bvalid;
    assign M_AXI_ARREADY = |s_arready;
    assign M_AXI_RVALID  = |s_rvalid;
    assign M_AXI_RDATA   = sel_r[0] ? s_rdata[0] :
                           sel_r[1] ? s_rdata[1] :
                           sel_r[2] ? s_rdata[2] :
                           sel_r[3] ? s_rdata[3] :
                           sel_r[4] ? s_rdata[4] : s_rdata[5];
    // AWADDR/ARADDR stay stable until the response, so muxing on sel is safe
    assign M_AXI_BRESP   = sel_w[0] ? s_bresp[0] : sel_w[1] ? s_bresp[1] : sel_w[2] ? s_bresp[2] :
                           sel_w[3] ? s_bresp[3] : sel_w[4] ? s_bresp[4] : s_bresp[5];
    assign M_AXI_RRESP   = sel_r[0] ? s_rresp[0] : sel_r[1] ? s_rresp[1] : sel_r[2] ? s_rresp[2] :
                           sel_r[3] ? s_rresp[3] : sel_r[4] ? s_rresp[4] : s_rresp[5];

    // Register ports of the simple slaves (RAM, App ROM, Boot ROM, default). Indexes 1 (APB) and 2 (SHA) unused
    wire [5:0]  reg_wen;
    wire [31:0] reg_waddr [0:5];
    wire [31:0] reg_wdata [0:5];
    wire [3:0]  reg_wstrb [0:5];
    wire [31:0] reg_raddr [0:5];
    wire [31:0] reg_rdata [0:5];

    // APB bus (bridge on slave 1 -> APB_Decoder -> peripherals)
    localparam NUM_APB = 8;
    wire [31:0] PADDR, PWDATA, PRDATA;
    wire [3:0]  PSTRB;
    wire        PSEL, PENABLE, PWRITE, PREADY, PSLVERR;
    wire [NUM_APB-1:0]    psel_s, pready_s, pslverr_s;
    wire [32*NUM_APB-1:0] prdata_s;

    genvar k;
    generate
        for (k = 0; k < 6; k = k + 1) begin : g_slave
            if (k == 2) begin : g_sha
                // ---- Slave 2: SHA-256 ----
                SHA256_Wrapper sha256 (
                    .clk(clk), .reset(sys_rst),
                    .S_AXI_AWVALID(M_AXI_AWVALID & sel_w[k]), .S_AXI_AWREADY(s_awready[k]), .S_AXI_AWADDR(M_AXI_AWADDR),
                    .S_AXI_WVALID(M_AXI_WVALID & sel_w[k]),   .S_AXI_WREADY(s_wready[k]),   .S_AXI_WDATA(M_AXI_WDATA),
                    .S_AXI_BVALID(s_bvalid[k]),               .S_AXI_BREADY(M_AXI_BREADY),
                    .S_AXI_ARVALID(M_AXI_ARVALID & sel_r[k]), .S_AXI_ARREADY(s_arready[k]), .S_AXI_ARADDR(M_AXI_ARADDR),
                    .S_AXI_RVALID(s_rvalid[k]),               .S_AXI_RREADY(M_AXI_RREADY),  .S_AXI_RDATA(s_rdata[k])
                );
                assign s_bresp[k] = 2'b00;
                assign s_rresp[k] = 2'b00;
            end else if (k == 1) begin : g_apb
                // ---- Slave 1: AXI-to-APB bridge ----
                AXI4_Lite_to_APB axi2apb (
                    .clk(clk), .reset(sys_rst),
                    .S_AXI_AWVALID(M_AXI_AWVALID & sel_w[k]), .S_AXI_AWREADY(s_awready[k]), .S_AXI_AWADDR(M_AXI_AWADDR),
                    .S_AXI_WVALID(M_AXI_WVALID & sel_w[k]),   .S_AXI_WREADY(s_wready[k]),   .S_AXI_WDATA(M_AXI_WDATA),
                    .S_AXI_WSTRB(M_AXI_WSTRB),
                    .S_AXI_BVALID(s_bvalid[k]),               .S_AXI_BREADY(M_AXI_BREADY),  .S_AXI_BRESP(s_bresp[k]),
                    .S_AXI_ARVALID(M_AXI_ARVALID & sel_r[k]), .S_AXI_ARREADY(s_arready[k]), .S_AXI_ARADDR(M_AXI_ARADDR),
                    .S_AXI_RVALID(s_rvalid[k]),               .S_AXI_RREADY(M_AXI_RREADY),  .S_AXI_RDATA(s_rdata[k]),
                    .S_AXI_RRESP(s_rresp[k]),
                    .PADDR(PADDR), .PSEL(PSEL), .PENABLE(PENABLE), .PWRITE(PWRITE),
                    .PWDATA(PWDATA), .PSTRB(PSTRB), .PRDATA(PRDATA), .PREADY(PREADY), .PSLVERR(PSLVERR)
                );
            end else begin : g_reg
                // ---- Slaves 0, 3, 4, 5: AXI-to-register adapters ----
                // The ROMs answer writes with SLVERR, the default slave answers everything with DECERR
                AXI4_Lite_Slave_Template #(
                    .WRESP(k == 5 ? 2'b11 : (k == 3 || k == 4) ? 2'b10 : 2'b00),
                    .RRESP(k == 5 ? 2'b11 : 2'b00)
                ) axi_slave (
                    .clk(clk), .reset(sys_rst),
                    .S_AXI_AWVALID(M_AXI_AWVALID & sel_w[k]), .S_AXI_AWREADY(s_awready[k]), .S_AXI_AWADDR(M_AXI_AWADDR),
                    .S_AXI_WVALID(M_AXI_WVALID & sel_w[k]),   .S_AXI_WREADY(s_wready[k]),   .S_AXI_WDATA(M_AXI_WDATA),
                    .S_AXI_WSTRB(M_AXI_WSTRB),
                    .S_AXI_BVALID(s_bvalid[k]),               .S_AXI_BREADY(M_AXI_BREADY),  .S_AXI_BRESP(s_bresp[k]),
                    .S_AXI_ARVALID(M_AXI_ARVALID & sel_r[k]), .S_AXI_ARREADY(s_arready[k]), .S_AXI_ARADDR(M_AXI_ARADDR),
                    .S_AXI_RVALID(s_rvalid[k]),               .S_AXI_RREADY(M_AXI_RREADY),  .S_AXI_RDATA(s_rdata[k]),
                    .S_AXI_RRESP(s_rresp[k]),
                    .reg_wen(reg_wen[k]), .reg_waddr(reg_waddr[k]), .reg_wdata(reg_wdata[k]), .reg_wstrb(reg_wstrb[k]),
                    .reg_raddr(reg_raddr[k]), .reg_rdata(reg_rdata[k])
                );
            end
        end
    endgenerate

    // Slave 0: Master RAM
    Data_Memory #(.INIT_FILE(RAM_HEX)) master_ram (
        .clk(clk),
        .MemWrite(reg_wen[0]),
        .MemRead(1'b1),
        .addr(reg_wen[0] ? reg_waddr[0] : reg_raddr[0]),
        .write_data(reg_wdata[0]),
        .wstrb(reg_wstrb[0]),
        .read_data(reg_rdata[0])
    );

    // Slave 4: Boot ROM. Port A feeds the Master Core's fetch, port B serves loads over AXI (read-only)
    Dual_Port_ROM #(.INIT_FILE(BOOT_HEX)) boot_rom (
        .clk(clk),
        .addrA(boot_addr),
        .dataOutA(boot_data),
        .addrB(reg_raddr[4]),
        .dataOutB(reg_rdata[4])
    );

    // Slave 5: default slave, reads 0
    assign reg_rdata[5] = 32'b0;

    // ---------------- APB peripheral bus (Secure world) ----------------
    // APB slaves: 0 = SYSCSR, 1 = UART0, 2 = GPIO0, 3 = TIMER0, 4 = WDT, 5 = PLIC-lite, 6 = Mailbox, 7 = Secure DMA
    APB_Decoder #(.NUM_SLV(NUM_APB)) apb_dec (
        .PADDR(PADDR), .PSEL(PSEL), .PSEL_S(psel_s),
        .PRDATA_S(prdata_s), .PREADY_S(pready_s), .PSLVERR_S(pslverr_s),
        .PRDATA(PRDATA), .PREADY(PREADY), .PSLVERR(PSLVERR)
    );

    wire app_rst;
    wire wdt_rst;
    wire zero_en;
    wire [9:0] zero_addr;

    SYSCSR syscsr (
        .clk(clk), .por_rst(reset_system), .wdt_rst_req(wdt_rst),
        .sys_rst(sys_rst), .app_rst(app_rst), .app_zero_en(zero_en), .app_zero_addr(zero_addr),
        .boot_strap(boot_strap),
        .bus_err(bus_err), .bus_err_write(bus_err_write), .bus_err_resp(bus_err_resp), .bus_err_addr(bus_err_addr),
        .PADDR(PADDR[11:0]), .PSEL(psel_s[0]), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PWDATA(PWDATA), .PSTRB(PSTRB), .PRDATA(prdata_s[31:0]), .PREADY(pready_s[0]), .PSLVERR(pslverr_s[0])
    );

    wire uart0_irq, gpio0_irq, dma_irq, mbox_irq_s;

    UART uart0 (
        .clk(clk), .reset(sys_rst), .uart_tx(uart0_tx), .uart_rx(uart0_rx), .irq(uart0_irq),
        .PADDR(PADDR[11:0]), .PSEL(psel_s[1]), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PWDATA(PWDATA), .PSTRB(PSTRB), .PRDATA(prdata_s[63:32]), .PREADY(pready_s[1]), .PSLVERR(pslverr_s[1])
    );

    GPIO gpio0 (
        .clk(clk), .reset(sys_rst), .gpio_o(gpio0_o), .gpio_i(gpio0_i), .irq(gpio0_irq),
        .PADDR(PADDR[11:0]), .PSEL(psel_s[2]), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PWDATA(PWDATA), .PSTRB(PSTRB), .PRDATA(prdata_s[95:64]), .PREADY(pready_s[2]), .PSLVERR(pslverr_s[2])
    );

    TIMER timer0 (
        .clk(clk), .reset(sys_rst), .irq(timer0_irq),
        .PADDR(PADDR[11:0]), .PSEL(psel_s[3]), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PWDATA(PWDATA), .PSTRB(PSTRB), .PRDATA(prdata_s[127:96]), .PREADY(pready_s[3]), .PSLVERR(pslverr_s[3])
    );

    WDT wdt (
        .clk(clk), .reset(sys_rst), .rst_req(wdt_rst),
        .PADDR(PADDR[11:0]), .PSEL(psel_s[4]), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PWDATA(PWDATA), .PSTRB(PSTRB), .PRDATA(prdata_s[159:128]), .PREADY(pready_s[4]), .PSLVERR(pslverr_s[4])
    );

    // PLIC-lite sources: 0 UART0, 1 GPIO0, 2 Secure DMA done, 3 Mailbox (a word from the App is waiting)
    PLIC plic (
        .clk(clk), .reset(sys_rst), .src({4'b0, mbox_irq_s, dma_irq, gpio0_irq, uart0_irq}), .irq(plic_irq),
        .PADDR(PADDR[11:0]), .PSEL(psel_s[5]), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PWDATA(PWDATA), .PSTRB(PSTRB), .PRDATA(prdata_s[191:160]), .PREADY(pready_s[5]), .PSLVERR(pslverr_s[5])
    );

    Secure_DMA dma (
        .clk(clk), .reset(sys_rst), .irq(dma_irq),
        .PADDR(PADDR[11:0]), .PSEL(psel_s[7]), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PWDATA(PWDATA), .PSTRB(PSTRB), .PRDATA(prdata_s[255:224]), .PREADY(pready_s[7]), .PSLVERR(pslverr_s[7]),
        .req_valid(dma_req), .req_write(dma_req_write), .req_addr(dma_req_addr), .req_wdata(dma_req_wdata),
        .resp_valid(dma_resp_valid), .resp_rdata(axi_resp_rdata), .resp_err(bus_err & dma_resp_valid),
        .fw_viol(dma_fw_viol)
    );

    wire app_core_reset_n = ~app_rst;
    assign app_running    = app_core_reset_n;

    // ---------------- App Core ----------------
    wire [31:0] app_instr_addr, app_instr;
    wire [31:0] app_data_addr, app_data_wdata, app_data_rdata;
    wire        app_data_we, app_data_re;
    wire [3:0]  app_data_wstrb;

    // Interrupts for the App Core.
    // TODO(P-09, I-01): connect .irq_timer(app_irq_timer) and .irq_ext(app_irq_ext) on app_core when RISCV_Core has the ports
    wire timer1_irq, uart1_irq, gpio1_irq, mbox_irq_a;
    wire app_irq_timer = timer1_irq;
    wire app_irq_ext   = uart1_irq | gpio1_irq | mbox_irq_a;

    RISCV_Core app_core (
        .clk(clk),
        .rst(~app_core_reset_n),
        .bus_stall(1'b0),
        .instr_addr(app_instr_addr),
        .instr_rdata(app_instr),
        .data_addr(app_data_addr),
        .data_wdata(app_data_wdata),
        .data_wstrb(app_data_wstrb),
        .data_we(app_data_we),
        .data_re(app_data_re),
        .data_rdata(app_data_rdata),
        .PC_debug(), .Instr_debug(), .RegWrite_WB_debug(), .Rd_WB_debug(), .Result_WB_debug()
    );

    // App data map: 0x4000_xxxx goes to the App APB peripherals, everything else is the App RAM.
    // The core never stalls, so the APB port is a single-cycle access: PENABLE is tied high and every
    // peripheral answers in the same cycle (all are zero-wait-state). The core has no bus-error trap
    // yet, so PSLVERR on the App APB is ignored (P-09).
    wire        app_apb_hit = (app_data_addr[31:28] == 4'h4);
    wire [31:0] app_ram_rdata;

    // Boot Guard zeroization borrows the RAM write port while the App Core is held in reset
    Data_Memory app_ram (
        .clk(clk),
        .MemWrite(zero_en | (app_data_we & ~app_apb_hit)),
        .MemRead(app_data_re & ~app_apb_hit),
        .addr(zero_en ? {20'b0, zero_addr, 2'b00} : app_data_addr),
        .write_data(zero_en ? 32'b0 : app_data_wdata),
        .wstrb(zero_en ? 4'hF : app_data_wstrb),
        .read_data(app_ram_rdata)
    );

    wire        app_psel = app_apb_hit & (app_data_we | app_data_re);
    wire [3:0]  app_pstrb = app_data_we ? app_data_wstrb : 4'b0;
    wire [31:0] app_prdata;
    wire        app_pready, app_pslverr;
    wire [3:0]  app_psel_s, app_pready_s, app_pslverr_s;
    wire [127:0] app_prdata_s;

    APB_Decoder #(.NUM_SLV(4)) app_apb_dec (
        .PADDR(app_data_addr), .PSEL(app_psel), .PSEL_S(app_psel_s),
        .PRDATA_S(app_prdata_s), .PREADY_S(app_pready_s), .PSLVERR_S(app_pslverr_s),
        .PRDATA(app_prdata), .PREADY(app_pready), .PSLVERR(app_pslverr)
    );
    assign app_data_rdata = app_apb_hit ? app_prdata : app_ram_rdata;

    UART uart1 (
        .clk(clk), .reset(app_rst), .uart_tx(uart1_tx), .uart_rx(uart1_rx), .irq(uart1_irq),
        .PADDR(app_data_addr[11:0]), .PSEL(app_psel_s[0]), .PENABLE(1'b1), .PWRITE(app_data_we),
        .PWDATA(app_data_wdata), .PSTRB(app_pstrb), .PRDATA(app_prdata_s[31:0]), .PREADY(app_pready_s[0]), .PSLVERR(app_pslverr_s[0])
    );

    GPIO gpio1 (
        .clk(clk), .reset(app_rst), .gpio_o(gpio1_o), .gpio_i(gpio1_i), .irq(gpio1_irq),
        .PADDR(app_data_addr[11:0]), .PSEL(app_psel_s[1]), .PENABLE(1'b1), .PWRITE(app_data_we),
        .PWDATA(app_data_wdata), .PSTRB(app_pstrb), .PRDATA(app_prdata_s[63:32]), .PREADY(app_pready_s[1]), .PSLVERR(app_pslverr_s[1])
    );

    TIMER timer1 (
        .clk(clk), .reset(app_rst), .irq(timer1_irq),
        .PADDR(app_data_addr[11:0]), .PSEL(app_psel_s[2]), .PENABLE(1'b1), .PWRITE(app_data_we),
        .PWDATA(app_data_wdata), .PSTRB(app_pstrb), .PRDATA(app_prdata_s[95:64]), .PREADY(app_pready_s[2]), .PSLVERR(app_pslverr_s[2])
    );

    // Mailbox: Secure side on APB slot 6 of the Secure bus, App side on slot 3 of the App bus
    Mailbox mailbox (
        .clk(clk), .reset(sys_rst), .irq_s(mbox_irq_s), .irq_a(mbox_irq_a),
        .s_PADDR(PADDR[11:0]), .s_PSEL(psel_s[6]), .s_PENABLE(PENABLE), .s_PWRITE(PWRITE),
        .s_PWDATA(PWDATA), .s_PSTRB(PSTRB), .s_PRDATA(prdata_s[223:192]), .s_PREADY(pready_s[6]), .s_PSLVERR(pslverr_s[6]),
        .a_PADDR(app_data_addr[11:0]), .a_PSEL(app_psel_s[3]), .a_PENABLE(1'b1), .a_PWRITE(app_data_we),
        .a_PWDATA(app_data_wdata), .a_PSTRB(app_pstrb), .a_PRDATA(app_prdata_s[127:96]), .a_PREADY(app_pready_s[3]), .a_PSLVERR(app_pslverr_s[3])
    );

    // Slave 3: App ROM. Port A feeds App Core fetch, port B is read-only over the Master AXI bus
    Dual_Port_ROM #(.INIT_FILE(APP_HEX)) app_rom (
        .clk(clk),
        .addrA(app_instr_addr),
        .dataOutA(app_instr),
        .addrB(reg_raddr[3]),
        .dataOutB(reg_rdata[3])
    );

endmodule

`default_nettype wire
