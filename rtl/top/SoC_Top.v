`timescale 1ns / 1ps
`default_nettype none   // bat buoc khai bao moi day: dat ten sai se bao loi thay vi tao day 1 bit

// ============================================================
// SoC Top - 2 the gioi cach ly:
//  - Master (Secure): Master Core + Boot ROM rieng + bus AXI4-Lite rieng
//      0x1000_0000 : RAM cua Master (stack/bien cua firmware secure_boot)
//      0x4000_0000 : Reset Controller (ghi 1 -> nha reset App Core)
//      0x5000_0000 : SHA-256
//      0x6000_0000 : ROM cua App, port B (chi doc) de bam firmware App; ghi -> SLVERR
//      dia chi khac : default slave tra DECERR (khong treo bus)
//  - App: App Core + ROM port A + RAM rieng, khong noi vao bus cua Master
// ============================================================
module SoC_Top #(
    parameter BOOT_HEX = "../fw/build/firmware_imem.hex",   // .text cua secure_boot (fw/CMakeLists.txt)
    parameter RAM_HEX  = "../fw/build/firmware_dmem.hex",   // .rodata/.data, word 0 = 0x1000_0000
    parameter APP_HEX  = "../fw/build/app_firmware.hex"
)(
    input  wire clk,
    input  wire reset_system,
    output wire app_running      // = 1 khi Master da nha reset App (noi LED tren board)
);
    // ---------------- Master Core ----------------
    wire [31:0] boot_addr, boot_data;
    wire [31:0] master_data_addr, master_data_wdata, master_data_rdata;
    wire        master_data_we, master_data_re;
    wire [3:0]  master_data_wstrb;
    wire        master_req_ready, master_resp_valid;

    // Stall khi MEM co request ma chua co ket qua (to hop, khong tre 1 chu ky)
    wire master_bus_stall = (master_data_we | master_data_re) & ~master_resp_valid;

    RISCV_Core master_core (
        .clk(clk),
        .rst(reset_system),
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

    AXI4_Lite_Master axi_master (
        .clk(clk),
        .reset(reset_system),
        .req_valid(master_data_we | master_data_re),
        .req_write(master_data_we),
        .req_addr(master_data_addr),
        .req_wdata(master_data_wdata),
        .req_wstrb(master_data_wstrb),
        .req_ready(master_req_ready),
        .resp_valid(master_resp_valid),
        .resp_rdata(master_data_rdata),

        .M_AXI_AWVALID(M_AXI_AWVALID), .M_AXI_AWREADY(M_AXI_AWREADY), .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_WVALID(M_AXI_WVALID),   .M_AXI_WREADY(M_AXI_WREADY),   .M_AXI_WDATA(M_AXI_WDATA),
        .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_BVALID(M_AXI_BVALID),   .M_AXI_BREADY(M_AXI_BREADY),   .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_ARVALID(M_AXI_ARVALID), .M_AXI_ARREADY(M_AXI_ARREADY), .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_RVALID(M_AXI_RVALID),   .M_AXI_RREADY(M_AXI_RREADY),   .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP)
    );

    // ---------------- Giai ma dia chi (Interconnect 1 master - 5 slave) ----------------
    // Thu tu slave: 0 = RAM, 1 = Reset Controller, 2 = SHA-256, 3 = App ROM port B, 4 = default (DECERR)
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

    // Chi slave duoc chon moi bat READY/VALID, nen OR lai la du
    assign M_AXI_AWREADY = |s_awready;
    assign M_AXI_WREADY  = |s_wready;
    assign M_AXI_BVALID  = |s_bvalid;
    assign M_AXI_ARREADY = |s_arready;
    assign M_AXI_RVALID  = |s_rvalid;
    assign M_AXI_RDATA   = sel_r[0] ? s_rdata[0] :
                           sel_r[1] ? s_rdata[1] :
                           sel_r[2] ? s_rdata[2] :
                           sel_r[3] ? s_rdata[3] : s_rdata[4];
    // AWADDR/ARADDR giu on dinh toi khi co response, nen chon theo sel la dung
    assign M_AXI_BRESP   = sel_w[0] ? s_bresp[0] : sel_w[1] ? s_bresp[1] : sel_w[2] ? s_bresp[2] :
                           sel_w[3] ? s_bresp[3] : s_bresp[4];
    assign M_AXI_RRESP   = sel_r[0] ? s_rresp[0] : sel_r[1] ? s_rresp[1] : sel_r[2] ? s_rresp[2] :
                           sel_r[3] ? s_rresp[3] : s_rresp[4];

    // Cong thanh ghi cua cac slave don gian (RAM, Reset Controller, App ROM, default); index 2 (SHA) khong dung
    wire [4:0]  reg_wen;
    wire [31:0] reg_waddr [0:4];
    wire [31:0] reg_wdata [0:4];
    wire [3:0]  reg_wstrb [0:4];
    wire [31:0] reg_raddr [0:4];
    wire [31:0] reg_rdata [0:4];

    genvar k;
    generate
        for (k = 0; k < 5; k = k + 1) begin : g_slave
            if (k == 2) begin : g_sha
                // ---- Slave 2: SHA-256 ----
                SHA256_Wrapper sha256 (
                    .clk(clk), .reset(reset_system),
                    .S_AXI_AWVALID(M_AXI_AWVALID & sel_w[k]), .S_AXI_AWREADY(s_awready[k]), .S_AXI_AWADDR(M_AXI_AWADDR),
                    .S_AXI_WVALID(M_AXI_WVALID & sel_w[k]),   .S_AXI_WREADY(s_wready[k]),   .S_AXI_WDATA(M_AXI_WDATA),
                    .S_AXI_BVALID(s_bvalid[k]),               .S_AXI_BREADY(M_AXI_BREADY),
                    .S_AXI_ARVALID(M_AXI_ARVALID & sel_r[k]), .S_AXI_ARREADY(s_arready[k]), .S_AXI_ARADDR(M_AXI_ARADDR),
                    .S_AXI_RVALID(s_rvalid[k]),               .S_AXI_RREADY(M_AXI_RREADY),  .S_AXI_RDATA(s_rdata[k])
                );
                assign s_bresp[k] = 2'b00;
                assign s_rresp[k] = 2'b00;
            end else begin : g_reg
                // ---- Slave 0, 1, 3, 4: adapter AXI -> cong thanh ghi ----
                // ROM App: ghi tra SLVERR; default slave: tra DECERR ca ghi lan doc
                AXI4_Lite_Slave_Template #(
                    .WRESP(k == 4 ? 2'b11 : k == 3 ? 2'b10 : 2'b00),
                    .RRESP(k == 4 ? 2'b11 : 2'b00)
                ) axi_slave (
                    .clk(clk), .reset(reset_system),
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

    // Slave 0: RAM cua Master
    Data_Memory #(.INIT_FILE(RAM_HEX)) master_ram (
        .clk(clk),
        .MemWrite(reg_wen[0]),
        .MemRead(1'b1),
        .addr(reg_wen[0] ? reg_waddr[0] : reg_raddr[0]),
        .write_data(reg_wdata[0]),
        .wstrb(reg_wstrb[0]),
        .read_data(reg_rdata[0])
    );

    // Slave 1: Reset Controller
    wire app_core_reset_n;

    Reset_Controller reset_controller (
        .clk(clk),
        .reset(reset_system),
        .axi_wen(reg_wen[1]),
        .axi_wdata(reg_wdata[1]),
        .app_core_reset_n(app_core_reset_n)
    );
    assign reg_rdata[1] = {31'b0, app_core_reset_n};
    assign app_running  = app_core_reset_n;

    // Slave 4: default slave, doc ra 0
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

    // Slave 3: ROM cua App - port A cho App Core fetch, port B chi doc qua AXI cua Master (ghi bi bo qua)
    Dual_Port_ROM #(.INIT_FILE(APP_HEX)) app_rom (
        .addrA(app_instr_addr),
        .dataOutA(app_instr),
        .addrB(reg_raddr[3]),
        .dataOutB(reg_rdata[3])
    );

endmodule

`default_nettype wire
