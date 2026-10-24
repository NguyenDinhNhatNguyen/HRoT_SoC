`timescale 1ns / 1ps
`default_nettype none   // every net must be declared: a typo is an error, not a silent 1-bit wire

// ============================================================
// SoC top: two isolated worlds
//  - Master (Secure): Master Core + its own boot ROM + its own AXI4-Lite bus
//      0x1000_0000 : Master RAM (secure boot stack and data)
//      0x4000_0000 : AXI-to-APB bridge, one 4 KB window per peripheral:
//                    0x4000_0000 SYSCSR (APP_CTRL at offset 0: write 1 to release the App Core)
//                    0x4000_1000 UART0, 0x4000_2000 GPIO0, 0x4000_3000 TIMER0, 0x4000_4000 WDT,
//                    any other window -> PSLVERR
//      0x5000_0000 : SHA-256
//      0x6000_0000 : App ROM port B (read-only) for hashing the App image, writes -> SLVERR
//      elsewhere   : default slave answers DECERR, so the bus never hangs
//  - App: App Core + ROM port A + its own RAM, with no path onto the Master bus
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
    input  wire [3:0] boot_strap     // boot mode switches (read through SYSCSR)
);
    // sys_rst: Secure-world reset from SYSCSR (POR, SW reset or WDT)
    wire sys_rst;

    // ---------------- Master Core ----------------
    wire [31:0] boot_addr, boot_data;
    wire [31:0] master_data_addr, master_data_wdata, master_data_rdata;
    wire        master_data_we, master_data_re;
    wire [3:0]  master_data_wstrb;
    wire        master_req_ready, master_resp_valid;

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

    Instruction_Memory #(.INIT_FILE(BOOT_HEX)) boot_rom (
        .clk(clk),
        .pc(boot_addr),
        .instr(boot_data)
    );

    // ---------------- AXI4-Lite Master ----------------
    wire        M_AXI_AWVALID, M_AXI_AWREADY, M_AXI_WVALID, M_AXI_WREADY;
    wire        M_AXI_BVALID, M_AXI_BREADY, M_AXI_ARVALID, M_AXI_ARREADY;
    wire        M_AXI_RVALID, M_AXI_RREADY;
    wire [31:0] M_AXI_AWADDR, M_AXI_WDATA, M_AXI_ARADDR, M_AXI_RDATA;
    wire [1:0]  M_AXI_BRESP, M_AXI_RRESP;
    wire [3:0]  M_AXI_WSTRB;
    wire        bus_err, bus_err_write;   // error responses reported to SYSCSR.BUS_ERR
    wire [1:0]  bus_err_resp;
    wire [31:0] bus_err_addr;

    AXI4_Lite_Master axi_master (
        .clk(clk),
        .reset(sys_rst),
        .req_valid(master_data_we | master_data_re),
        .req_write(master_data_we),
        .req_addr(master_data_addr),
        .req_wdata(master_data_wdata),
        .req_wstrb(master_data_wstrb),
        .req_ready(master_req_ready),
        .resp_valid(master_resp_valid),
        .resp_rdata(master_data_rdata),
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

    // ---------------- Address decode (1 master, 5 slaves) ----------------
    // Slave order: 0 = RAM, 1 = APB bridge, 2 = SHA-256, 3 = App ROM port B, 4 = default (DECERR)
    wire [3:0] hit_w = {M_AXI_AWADDR[31:16] == 16'h6000, M_AXI_AWADDR[31:16] == 16'h5000,
                        M_AXI_AWADDR[31:16] == 16'h4000, M_AXI_AWADDR[31:16] == 16'h1000};
    wire [3:0] hit_r = {M_AXI_ARADDR[31:16] == 16'h6000, M_AXI_ARADDR[31:16] == 16'h5000,
                        M_AXI_ARADDR[31:16] == 16'h4000, M_AXI_ARADDR[31:16] == 16'h1000};
    wire [4:0] sel_w = {~|hit_w, hit_w};
    wire [4:0] sel_r = {~|hit_r, hit_r};

    wire [4:0]  s_awready, s_wready, s_bvalid, s_arready, s_rvalid;
    wire [31:0] s_rdata [0:4];
    wire [1:0]  s_bresp [0:4];
    wire [1:0]  s_rresp [0:4];

    // Only the selected slave drives READY/VALID, so OR-ing them is enough
    assign M_AXI_AWREADY = |s_awready;
    assign M_AXI_WREADY  = |s_wready;
    assign M_AXI_BVALID  = |s_bvalid;
    assign M_AXI_ARREADY = |s_arready;
    assign M_AXI_RVALID  = |s_rvalid;
    assign M_AXI_RDATA   = sel_r[0] ? s_rdata[0] :
                           sel_r[1] ? s_rdata[1] :
                           sel_r[2] ? s_rdata[2] :
                           sel_r[3] ? s_rdata[3] : s_rdata[4];
    // AWADDR/ARADDR stay stable until the response, so muxing on sel is safe
    assign M_AXI_BRESP   = sel_w[0] ? s_bresp[0] : sel_w[1] ? s_bresp[1] : sel_w[2] ? s_bresp[2] :
                           sel_w[3] ? s_bresp[3] : s_bresp[4];
    assign M_AXI_RRESP   = sel_r[0] ? s_rresp[0] : sel_r[1] ? s_rresp[1] : sel_r[2] ? s_rresp[2] :
                           sel_r[3] ? s_rresp[3] : s_rresp[4];

    // Register ports of the simple slaves (RAM, App ROM, default). Indexes 1 (APB) and 2 (SHA) are unused
    wire [4:0]  reg_wen;
    wire [31:0] reg_waddr [0:4];
    wire [31:0] reg_wdata [0:4];
    wire [3:0]  reg_wstrb [0:4];
    wire [31:0] reg_raddr [0:4];
    wire [31:0] reg_rdata [0:4];

    // APB bus (bridge on slave 1 -> APB_Decoder -> peripherals)
    localparam NUM_APB = 8;
    wire [31:0] PADDR, PWDATA, PRDATA;
    wire [3:0]  PSTRB;
    wire        PSEL, PENABLE, PWRITE, PREADY, PSLVERR;
    wire [NUM_APB-1:0]    psel_s, pready_s, pslverr_s;
    wire [32*NUM_APB-1:0] prdata_s;

    genvar k;
    generate
        for (k = 0; k < 5; k = k + 1) begin : g_slave
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
                // ---- Slaves 0, 3, 4: AXI-to-register adapters ----
                // App ROM answers writes with SLVERR, the default slave answers everything with DECERR
                AXI4_Lite_Slave_Template #(
                    .WRESP(k == 4 ? 2'b11 : k == 3 ? 2'b10 : 2'b00),
                    .RRESP(k == 4 ? 2'b11 : 2'b00)
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

    // ---------------- APB peripheral bus (Secure world) ----------------
    // APB slaves: 0 = SYSCSR, 1 = UART0, 2 = GPIO0, 3 = TIMER0, 4 = WDT, 5..7 = reserved (PLIC, MAILBOX)

    APB_Decoder #(.NUM_SLV(NUM_APB)) apb_dec (
        .PADDR(PADDR), .PSEL(PSEL), .PSEL_S(psel_s),
        .PRDATA_S(prdata_s), .PREADY_S(pready_s), .PSLVERR_S(pslverr_s),
        .PRDATA(PRDATA), .PREADY(PREADY), .PSLVERR(PSLVERR)
    );

    wire app_rst;
    wire wdt_rst;

    SYSCSR syscsr (
        .clk(clk), .por_rst(reset_system), .wdt_rst_req(wdt_rst),
        .sys_rst(sys_rst), .app_rst(app_rst), .boot_strap(boot_strap),
        .bus_err(bus_err), .bus_err_write(bus_err_write), .bus_err_resp(bus_err_resp), .bus_err_addr(bus_err_addr),
        .PADDR(PADDR[11:0]), .PSEL(psel_s[0]), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PWDATA(PWDATA), .PSTRB(PSTRB), .PRDATA(prdata_s[31:0]), .PREADY(pready_s[0]), .PSLVERR(pslverr_s[0])
    );

    wire uart0_irq, gpio0_irq;   // go to PLIC-lite in week 9
    wire timer0_irq;             // goes to the core's irq_timer once P-09 lands (I-01)

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

    // Empty APB windows answer PSLVERR
   assign prdata_s[32*NUM_APB-1:160] = {(32*(NUM_APB-5)){1'b0}};
    assign pready_s[NUM_APB-1:5]      = {(NUM_APB-5){1'b1}};
    assign pslverr_s[NUM_APB-1:5]     = {(NUM_APB-5){1'b1}};

    wire app_core_reset_n = ~app_rst;
    assign app_running    = app_core_reset_n;

    // Slave 4: default slave, reads 0
    assign reg_rdata[4] = 32'b0;

    // ---------------- App Core ----------------
    wire [31:0] app_instr_addr, app_instr;
    wire [31:0] app_data_addr, app_data_wdata, app_data_rdata;
    wire        app_data_we, app_data_re;
    wire [3:0]  app_data_wstrb;

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

    Data_Memory app_ram (
        .clk(clk),
        .MemWrite(app_data_we),
        .MemRead(app_data_re),
        .addr(app_data_addr),
        .write_data(app_data_wdata),
        .wstrb(app_data_wstrb),
        .read_data(app_data_rdata)
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
