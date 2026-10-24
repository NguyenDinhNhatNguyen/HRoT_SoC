`timescale 1ns / 1ps

// MEM_Stage_tb.v - Functional Testbench for MEM_Stage + Data RAM

module MEM_Stage_tb;

    // 1. Khai bao tin hieu (Signals)
    reg         clk;
    reg         RegWrite_MEM, MemWrite_MEM, MemRead_MEM;
    reg  [1:0]  ResultSrc_MEM;
    reg  [31:0] ALUResult_MEM, WriteData_MEM, PC_Plus_4_MEM, PCTarget_MEM;
    reg  [4:0]  Rd_MEM;
    reg  [2:0]  funct3_MEM;

    // Giao tiep bo nho du lieu (Data RAM nam ngoai MEM_Stage)
    wire [31:0] data_addr, data_wdata, data_rdata;
    wire [3:0]  data_wstrb;
    wire        data_we, data_re;

    wire        RegWrite_MEM_out;
    wire [1:0]  ResultSrc_MEM_out;
    wire [31:0] ALUResult_MEM_out, ReadData_MEM_out, PC_Plus_4_MEM_out, PCTarget_MEM_out;
    wire [4:0]  Rd_MEM_out;

    integer pass_count = 0;
    integer fail_count = 0;

    // 2. Khoi tao DUT
    MEM_Stage dut (
        .clk                (clk),
        .RegWrite_MEM       (RegWrite_MEM), .MemWrite_MEM     (MemWrite_MEM),
        .MemRead_MEM        (MemRead_MEM),  .ResultSrc_MEM    (ResultSrc_MEM),
        .ALUResult_MEM      (ALUResult_MEM),.WriteData_MEM    (WriteData_MEM),
        .PC_Plus_4_MEM      (PC_Plus_4_MEM),.PCTarget_MEM     (PCTarget_MEM),
        .Rd_MEM             (Rd_MEM),           .funct3_MEM       (funct3_MEM),
        .data_rdata         (data_rdata),       .data_addr        (data_addr),
        .data_wdata         (data_wdata),       .data_wstrb       (data_wstrb),
        .data_we            (data_we),          .data_re          (data_re),

        .RegWrite_MEM_out   (RegWrite_MEM_out), .ResultSrc_MEM_out (ResultSrc_MEM_out),
        .ALUResult_MEM_out  (ALUResult_MEM_out),.ReadData_MEM_out  (ReadData_MEM_out),
        .PC_Plus_4_MEM_out  (PC_Plus_4_MEM_out),.PCTarget_MEM_out  (PCTarget_MEM_out),
        .Rd_MEM_out         (Rd_MEM_out)
    );

    // Data RAM mo phong: doc to hop theo word, ghi dong bo theo byte lane (WSTRB)
    reg [31:0] ram [0:63];
    integer    k;
    assign data_rdata = ram[data_addr[7:2]];
    always @(posedge clk) begin
        if (data_we) begin
            if (data_wstrb[0]) ram[data_addr[7:2]][7:0]   <= data_wdata[7:0];
            if (data_wstrb[1]) ram[data_addr[7:2]][15:8]  <= data_wdata[15:8];
            if (data_wstrb[2]) ram[data_addr[7:2]][23:16] <= data_wdata[23:16];
            if (data_wstrb[3]) ram[data_addr[7:2]][31:24] <= data_wdata[31:24];
        end
    end

    task check_bus;
        input [8*60:1] test_name;
        input [3:0]    e_strb;
        input [31:0]   e_wdata;
        begin
            #1;
            if ((data_wstrb === e_strb) && (data_wdata === e_wdata)) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s", test_name);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : wstrb=%b wdata=%h (expect wstrb=%b wdata=%h)",
                         test_name, data_wstrb, data_wdata, e_strb, e_wdata);
            end
        end
    endtask

    // 3. Tao Clock 100MHz (Chu ky 10ns)
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // 4. Task Kiem Tra (Dung %0s de triet tieu khoang trang)
    task check_all;
        input [8*60:1] test_name; // Toi da 60 ky tu
        input [31:0]   e_ALURes, e_ReadData, e_PC4, e_PCTarget;
        input          e_RegW;
        input [1:0]    e_ResSrc;
        input [4:0]    e_Rd;
        begin
            #1; // Doi mach to hop on dinh

            if ((RegWrite_MEM_out  === e_RegW)   && (ResultSrc_MEM_out === e_ResSrc) &&
                (ALUResult_MEM_out === e_ALURes) && ((ReadData_MEM_out === e_ReadData) || (e_ReadData === 32'hx)) &&
                (PC_Plus_4_MEM_out === e_PC4)    && (PCTarget_MEM_out  === e_PCTarget) &&
                (Rd_MEM_out        === e_Rd)) begin
                
                pass_count = pass_count + 1;
                $display("[PASS] %0s", test_name); // %0s giup bo di toan bo dau space thua
            end
            else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s", test_name);
                $display("       [ACTUAL] RegW=%b | ResSrc=%b | ALU=%h | ReadData=%h | PC4=%h | PCTarget=%h | Rd=%d",
                         RegWrite_MEM_out, ResultSrc_MEM_out, ALUResult_MEM_out, ReadData_MEM_out, PC_Plus_4_MEM_out, PCTarget_MEM_out, Rd_MEM_out);
                $display("       [EXPECT] RegW=%b | ResSrc=%b | ALU=%h | ReadData=%h | PC4=%h | PCTarget=%h | Rd=%d",
                         e_RegW, e_ResSrc, e_ALURes, e_ReadData, e_PC4, e_PCTarget, e_Rd);
            end
            #9;
        end
    endtask

    // 5. Chuoi Kich Ban Mo Phong
    initial begin
        // Khoi tao gia tri an toan
        RegWrite_MEM=0; MemWrite_MEM=0; MemRead_MEM=0; ResultSrc_MEM=2'b00; Rd_MEM=5'd0;
        ALUResult_MEM=0; WriteData_MEM=0; PC_Plus_4_MEM=0; PCTarget_MEM=0; 
        funct3_MEM=3'b010; // LW/SW
        for (k = 0; k < 64; k = k + 1) ram[k] = 32'h0;
        
        #10;
        $display("\n=========================================================================");
        $display("                 MEM_STAGE + DATA_MEMORY FUNCTIONAL TEST                 ");
        $display("=========================================================================");

        // TEST 1: PASS-THROUGH
        RegWrite_MEM=1; MemWrite_MEM=0; MemRead_MEM=0; ResultSrc_MEM=2'b10; Rd_MEM=5'd15;
        ALUResult_MEM=32'h40; WriteData_MEM=32'h0; PC_Plus_4_MEM=32'h104; PCTarget_MEM=32'h120;
        //        Ten Kich Ban                  ALURes  ReadData  PC4      PCTarget RW  RSrc   Rd
        check_all("1. Pass-through signals",    32'h40, 32'hx,    32'h104, 32'h120, 1,  2'b10, 15);

        // TEST 2: STORE WORD at 0x20
        RegWrite_MEM=0; MemWrite_MEM=1; ResultSrc_MEM=2'b00; Rd_MEM=5'd0;
        ALUResult_MEM=32'h20; WriteData_MEM=32'hDEADBEEF; PC_Plus_4_MEM=32'h104; PCTarget_MEM=32'h0;
        @(posedge clk); #1; MemWrite_MEM = 0; // Chot du lieu vao RAM
        check_all("2. Store Word (SW) at 0x20", 32'h20, 32'hDEADBEEF, 32'h104, 32'h0, 0, 2'b00, 0);

        // TEST 3: LOAD WORD from 0x20
        RegWrite_MEM=1; MemRead_MEM=1; ResultSrc_MEM=2'b01; Rd_MEM=5'd10;
        ALUResult_MEM=32'h20; PC_Plus_4_MEM=32'h108;
        check_all("3. Load Word (LW) from 0x20",32'h20, 32'hDEADBEEF, 32'h108, 32'h0, 1, 2'b01, 10);

        // TEST 4: WORD ALIGNMENT at 0x24
        RegWrite_MEM=0; MemWrite_MEM=1; MemRead_MEM=0; ResultSrc_MEM=2'b00; Rd_MEM=5'd0;
        ALUResult_MEM=32'h24; WriteData_MEM=32'hCAFEBABE; PC_Plus_4_MEM=32'h10C;
        @(posedge clk); #1; MemWrite_MEM = 0;
        check_all("4. Word alignment at 0x24",  32'h24, 32'hCAFEBABE, 32'h10C, 32'h0, 0, 2'b00, 0);

        // TEST 5: NON-MEMORY INSTRUCTION
        RegWrite_MEM=1; MemRead_MEM=0; ResultSrc_MEM=2'b00; Rd_MEM=5'd5;
        ALUResult_MEM=32'h30; WriteData_MEM=32'h0; PC_Plus_4_MEM=32'h110;
        check_all("5. Non-memory instruction",  32'h30, 32'hx,        32'h110, 32'h0, 1, 2'b00, 5);

        // TEST 6: ResultSrc = 2'b11 / PCTarget PATH
        RegWrite_MEM=1; ResultSrc_MEM=2'b11; Rd_MEM=5'd1;
        ALUResult_MEM=32'h44; PC_Plus_4_MEM=32'h114; PCTarget_MEM=32'h200;
        check_all("6. ResultSrc = 2'b11 (PCT)", 32'h44, 32'hx,        32'h114, 32'h200, 1, 2'b11, 1);

        // TEST 7: BOUNDARY DATA = FFFFFFFF
        RegWrite_MEM=0; MemWrite_MEM=1; ResultSrc_MEM=2'b00; Rd_MEM=5'd0;
        ALUResult_MEM=32'h28; WriteData_MEM=32'hFFFFFFFF; PC_Plus_4_MEM=32'h118; PCTarget_MEM=32'h0;
        @(posedge clk); #1; MemWrite_MEM = 0;
        check_all("7. Boundary FFFFFFFF",       32'h28, 32'hFFFFFFFF, 32'h118, 32'h0, 0, 2'b00, 0);

        // TEST 8: ZERO DATA
        MemWrite_MEM=1; ALUResult_MEM=32'h2C; WriteData_MEM=32'h0; PC_Plus_4_MEM=32'h11C;
        @(posedge clk); #1; MemWrite_MEM = 0;
        check_all("8. Zero data 0x00000000",    32'h2C, 32'h00000000, 32'h11C, 32'h0, 0, 2'b00, 0);

        // TEST 9a: MULTIPLE ADDRESS - 0x40
        MemWrite_MEM=1; ALUResult_MEM=32'h40; WriteData_MEM=32'h12345678; PC_Plus_4_MEM=32'h120;
        @(posedge clk); #1; MemWrite_MEM = 0;
        check_all("9a. Address 0x40",           32'h40, 32'h12345678, 32'h120, 32'h0, 0, 2'b00, 0);

        // TEST 9b: MULTIPLE ADDRESS - 0x44
        MemWrite_MEM=1; ALUResult_MEM=32'h44; WriteData_MEM=32'h87654321; PC_Plus_4_MEM=32'h124;
        @(posedge clk); #1; MemWrite_MEM = 0;
        check_all("9b. Address 0x44",           32'h44, 32'h87654321, 32'h124, 32'h0, 0, 2'b00, 0);

        // TEST 10: READ-AFTER-WRITE
        MemWrite_MEM=1; MemRead_MEM=0; RegWrite_MEM=0; ResultSrc_MEM=2'b00; Rd_MEM=5'd0;
        ALUResult_MEM=32'h50; WriteData_MEM=32'hA5A5A5A5; PC_Plus_4_MEM=32'h128;
        @(posedge clk); #1; MemWrite_MEM = 0;
        check_all("10a. Write A5A5A5A5 at 0x50",32'h50, 32'hA5A5A5A5, 32'h128, 32'h0, 0, 2'b00, 0);

        RegWrite_MEM=1; MemRead_MEM=1; ResultSrc_MEM=2'b01; Rd_MEM=5'd7; PC_Plus_4_MEM=32'h12C;
        check_all("10b. Read A5A5A5A5 from 0x50",32'h50, 32'hA5A5A5A5, 32'h12C, 32'h0, 1, 2'b01, 7);

        // TEST 11: STORE/LOAD BYTE & HALF (word 0x60 dang = 0)
        RegWrite_MEM=0; MemRead_MEM=0; ResultSrc_MEM=2'b00; Rd_MEM=5'd0; PC_Plus_4_MEM=32'h130;
        MemWrite_MEM=1; funct3_MEM=3'b000; ALUResult_MEM=32'h61; WriteData_MEM=32'h123456AB;
        check_bus("11a. SB @0x61 -> lane 1",       4'b0010, 32'hABABABAB);
        @(posedge clk); #1; MemWrite_MEM = 0;
        funct3_MEM=3'b010; ALUResult_MEM=32'h60;
        check_all("11b. Word 0x60 sau SB",          32'h60, 32'h0000AB00, 32'h130, 32'h0, 0, 2'b00, 0);

        MemWrite_MEM=1; funct3_MEM=3'b001; ALUResult_MEM=32'h62; WriteData_MEM=32'hFFFF8001;
        check_bus("11c. SH @0x62 -> lane 3:2",     4'b1100, 32'h80018001);
        @(posedge clk); #1; MemWrite_MEM = 0;

        RegWrite_MEM=1; MemRead_MEM=1; ResultSrc_MEM=2'b01; Rd_MEM=5'd9;
        funct3_MEM=3'b010; ALUResult_MEM=32'h60;
        check_all("11d. LW  @0x60",                 32'h60, 32'h8001AB00, 32'h130, 32'h0, 1, 2'b01, 9);
        funct3_MEM=3'b000; ALUResult_MEM=32'h61;
        check_all("11e. LB  @0x61 (mo rong dau)",   32'h61, 32'hFFFFFFAB, 32'h130, 32'h0, 1, 2'b01, 9);
        funct3_MEM=3'b100;
        check_all("11f. LBU @0x61 (mo rong 0)",     32'h61, 32'h000000AB, 32'h130, 32'h0, 1, 2'b01, 9);
        funct3_MEM=3'b000; ALUResult_MEM=32'h60;
        check_all("11g. LB  @0x60 (byte 0 = 00)",   32'h60, 32'h00000000, 32'h130, 32'h0, 1, 2'b01, 9);
        funct3_MEM=3'b001; ALUResult_MEM=32'h62;
        check_all("11h. LH  @0x62 (mo rong dau)",   32'h62, 32'hFFFF8001, 32'h130, 32'h0, 1, 2'b01, 9);
        funct3_MEM=3'b101;
        check_all("11i. LHU @0x62 (mo rong 0)",     32'h62, 32'h00008001, 32'h130, 32'h0, 1, 2'b01, 9);
        funct3_MEM=3'b001; ALUResult_MEM=32'h60;
        check_all("11j. LH  @0x60",                 32'h60, 32'hFFFFAB00, 32'h130, 32'h0, 1, 2'b01, 9);

        funct3_MEM=3'b010; MemWrite_MEM=1; MemRead_MEM=0; RegWrite_MEM=0;
        check_bus("11k. SW -> du 4 lane",          4'b1111, 32'hFFFF8001);
        MemWrite_MEM=0;

        // TONG KET
        $display("\n=========================================================================");
        $display("SUMMARY MEM_STAGE: PASS = %0d | FAIL = %0d", pass_count, fail_count);
        if (fail_count == 0) $display(">>> TAT CA CAC KICH BAN DA DUOC KIEM TRA THANH CONG! <<<");
        else                 $display(">>> CO LOI XAY RA, VUI LONG KIEM TRA LAI! <<<");
        $display("=========================================================================\n");

        $finish;
    end
endmodule
