module SoC_Top (
    input clk,
    input reset_system
);
    wire app_core_reset_n;
    wire [31:0] rom_addrA, rom_dataA, rom_addrB, rom_dataB;

    RISCV_Core master_core (
        .clk(clk), 
        .reset(reset_system),
        .bus_stall(~master_req_ready),    // Stall CPU nếu AXI Master đang bận xử lý
        .instr_addr(rom_addrB),
        .instr_rdata(rom_dataB),
        .data_wdata(master_data_wdata),
        .data_we(master_data_we),
        .data_re(master_data_re),
        .data_rdata(master_data_rdata),
        .ForwardA_EX(2'b00),
        .ForwardB_EX(2'b00),
        .data_addr(master_data_addr)    // Nối dây ALUResult_MEM ra port này
        
    );

    RISCV_Core app_core (
        .clk(clk), 
        .reset(~app_core_reset_n),
        // Lõi này chỉ được cấp quyền đọc Port A của ROM
        .bus_stall(1'b0),
        .instr_addr(rom_addrA),
        .instr_rdata(rom_dataA),
        .data_wdata(),
        .data_we(),
        .data_re(),
        .data_rdata(32'b0),
        .ForwardA_EX(2'b00),
        .ForwardB_EX(2'b00)
    );

    AXI4_Lite_Master axi_master (
        .clk(clk), 
        .reset(reset_system),
        // Kết nối vào CPU
        .req_valid(master_data_we | master_data_re),
        .req_write(master_data_we),
        .req_addr(master_data_addr),
        .req_wdata(master_data_wdata),
        .req_ready(master_req_ready),
        .resp_valid(master_resp_valid),
        .resp_rdata(master_data_rdata),
        
        // Cổng AXI Master
        .M_AXI_AWVALID(M_AXI_AWVALID), .M_AXI_AWREADY(M_AXI_AWREADY), .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_WVALID(M_AXI_WVALID),   .M_AXI_WREADY(M_AXI_WREADY),   .M_AXI_WDATA(M_AXI_WDATA),
        .M_AXI_BVALID(M_AXI_BVALID),   .M_AXI_BREADY(M_AXI_BREADY),   .M_AXI_BRESP(),
        .M_AXI_ARVALID(M_AXI_ARVALID), .M_AXI_ARREADY(M_AXI_ARREADY), .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_RVALID(M_AXI_RVALID),   .M_AXI_RREADY(M_AXI_RREADY),   .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP()
    );

    // Cấp phát không gian bộ nhớ:
    // - 0x5000_XXXX: Khu vực của SHA-256
    // - 0x4000_XXXX: Khu vực của Reset Controller
    wire sel_sha256 = (M_AXI_AWADDR[31:16] == 16'h5000) || (M_AXI_ARADDR[31:16] == 16'h5000);
    wire sel_reset  = (M_AXI_AWADDR[31:16] == 16'h4000);

    SHA256_Core sha256_core (
        .clk(clk), 
        .reset(reset_system),
        
        // Chèn cờ sel_sha256 vào tín hiệu VALID để kích hoạt đúng Slave
        .S_AXI_AWVALID(M_AXI_AWVALID & sel_sha256),
        .S_AXI_AWREADY(M_AXI_AWREADY), // Truyền READY ngược về Master
        .S_AXI_AWADDR(M_AXI_AWADDR),
        .S_AXI_WVALID(M_AXI_WVALID & sel_sha256),
        .S_AXI_WREADY(M_AXI_WREADY),
        .S_AXI_WDATA(M_AXI_WDATA),
        .S_AXI_ARVALID(M_AXI_ARVALID & sel_sha256),
        .S_AXI_ARREADY(M_AXI_ARREADY),
        .S_AXI_ARADDR(M_AXI_ARADDR),
        .S_AXI_RVALID(M_AXI_RVALID),
        .S_AXI_RDATA(M_AXI_RDATA)
    );

    Reset_Controller reset_controller (
        .clk(clk), 
        .reset(reset_system),
        .axi_wen(M_AXI_WVALID & M_AXI_AWVALID & sel_reset),
        .axi_wdata(M_AXI_WDATA),
        .app_core_reset_n(app_core_reset_n)
    );

    // Khởi tạo kênh BVALID giả lập (do SHA256_Wrapper và Reset_Controller hiện chưa có chân xuất BVALID)
    reg fake_bvalid;
    always @(posedge clk) begin
        if (reset_system) fake_bvalid <= 0;
        else if (M_AXI_WVALID) fake_bvalid <= 1; // Phát cờ Write Response
        else if (M_AXI_BREADY) fake_bvalid <= 0;
    end
    assign M_AXI_BVALID = fake_bvalid;

    Dual_Port_ROM dual_port_rom (
        .clk(clk),
        .addrA(rom_addrA),
        .dataOutA(rom_dataA),
        .addrB(rom_addrB),
        .dataOutB(rom_dataB)
    );