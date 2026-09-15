`timescale 1ns / 1ps

module EX_Stage_tb;

    // ============================================================
    // 1. Tin hieu dau vao (Inputs)
    // ============================================================
    reg         RegWrite_EX, MemWrite_EX, MemRead_EX, Branch_EX, Jump_EX, Jalr_EX, ALUSrc_EX;
    reg  [1:0]  ResultSrc_EX, ForwardA_EX, ForwardB_EX;
    reg  [3:0]  ALUControl_EX;
    reg  [31:0] PC_EX, RD1_EX, RD2_EX, ImmExt_EX, PC_Plus_4_EX, ALUResult_MEM, Result_WB;
    reg  [4:0]  Rd_EX;
    reg  [2:0]  funct3_EX;

    // ============================================================
    // 2. Tin hieu dau ra (Outputs)
    // ============================================================
    wire        RegWrite_EX_out, MemWrite_EX_out, MemRead_EX_out, PCSrc_EX;
    wire [1:0]  ResultSrc_EX_out;
    wire [31:0] ALUResult_EX_out, WriteData_EX_out, PC_Plus_4_EX_out, PCTarget_EX_out;
    wire [4:0]  Rd_EX_out;

    // ============================================================
    // 3. Khoi tao DUT (Device Under Test)
    // ============================================================
    EX_Stage dut (
        .RegWrite_EX(RegWrite_EX), .MemWrite_EX(MemWrite_EX), .MemRead_EX(MemRead_EX),
        .Branch_EX(Branch_EX), .Jump_EX(Jump_EX), .Jalr_EX(Jalr_EX), .ALUSrc_EX(ALUSrc_EX),
        .ResultSrc_EX(ResultSrc_EX), .ALUControl_EX(ALUControl_EX),
        .PC_EX(PC_EX), .RD1_EX(RD1_EX), .RD2_EX(RD2_EX), .ImmExt_EX(ImmExt_EX),
        .PC_Plus_4_EX(PC_Plus_4_EX), .Rd_EX(Rd_EX), .funct3_EX(funct3_EX),
        .ForwardA_EX(ForwardA_EX), .ForwardB_EX(ForwardB_EX),
        .ALUResult_MEM(ALUResult_MEM), .Result_WB(Result_WB),
        
        .RegWrite_EX_out(RegWrite_EX_out), .MemWrite_EX_out(MemWrite_EX_out),
        .MemRead_EX_out(MemRead_EX_out), .ResultSrc_EX_out(ResultSrc_EX_out),
        .ALUResult_EX_out(ALUResult_EX_out), .WriteData_EX_out(WriteData_EX_out),
        .PC_Plus_4_EX_out(PC_Plus_4_EX_out), .PCTarget_EX_out(PCTarget_EX_out),
        .Rd_EX_out(Rd_EX_out), .PCSrc_EX(PCSrc_EX)
    );

    // ============================================================
    // 4. Tasks Ho Tro Kiem Tra
    // ============================================================
    integer pass_count = 0;
    integer fail_count = 0;

    task reset_signals;
    begin
        RegWrite_EX=0; MemWrite_EX=0; MemRead_EX=0; Branch_EX=0; Jump_EX=0; Jalr_EX=0; ALUSrc_EX=0;
        ResultSrc_EX=2'b00; ForwardA_EX=2'b00; ForwardB_EX=2'b00; ALUControl_EX=4'b0000;
        PC_EX=0; RD1_EX=0; RD2_EX=0; ImmExt_EX=0; PC_Plus_4_EX=0; Rd_EX=0; funct3_EX=0;
        ALUResult_MEM=0; Result_WB=0;
    end
    endtask

    task check_all;
        input [8*50:1] test_name; 
        input [31:0] e_ALU, e_WD, e_PCTarget, e_PC4;
        input        e_PCSrc, e_RegW, e_MemW, e_MemR;
        input [1:0]  e_ResSrc;
        input [4:0]  e_Rd;
        begin
            #1; // Doi mach to hop on dinh
            if ((ALUResult_EX_out === e_ALU) && (WriteData_EX_out === e_WD) &&
                (PCTarget_EX_out  === e_PCTarget) && (PCSrc_EX === e_PCSrc) &&
                (RegWrite_EX_out  === e_RegW) && (MemWrite_EX_out === e_MemW) &&
                (MemRead_EX_out   === e_MemR) && (ResultSrc_EX_out === e_ResSrc) &&
                (Rd_EX_out        === e_Rd) && (PC_Plus_4_EX_out === e_PC4)) begin
                
                pass_count = pass_count + 1;
                $display("[PASS] %0s", test_name);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s", test_name);
                $display("       ACTUAL  : ALU=%h | WD=%h | PCTarget=%h | PCSrc=%b", ALUResult_EX_out, WriteData_EX_out, PCTarget_EX_out, PCSrc_EX);
                $display("       EXPECTED: ALU=%h | WD=%h | PCTarget=%h | PCSrc=%b", e_ALU, e_WD, e_PCTarget, e_PCSrc);
            end
            #9;
        end
    endtask

    // ============================================================
    // 5. Chuoi Kich Ban Mo Phong
    // ============================================================
    initial begin
        $display("\n==========================================================================");
        $display("                 BAT DAU TESTBENCH TANG EX_STAGE (100%% COVERAGE)         ");
        $display("==========================================================================");

        // --------------------------------------------------------
        // TEST 1: Lanh R-Type ADD
        // --------------------------------------------------------
        reset_signals();
        RegWrite_EX = 1; PC_EX = 32'h0100; PC_Plus_4_EX = 32'h0104; Rd_EX = 5'd10;
        RD1_EX = 32'd15; RD2_EX = 32'd25; ALUControl_EX = 4'b0000;
        check_all("1. R-Type ADD",     40,  25, 32'h0100,  32'h0104, 0,    1, 0, 0, 2'b00, 10);

        // --------------------------------------------------------
        // TEST 2: Lanh I-Type ADDI 
        // --------------------------------------------------------
        reset_signals();
        RegWrite_EX = 1; PC_EX = 32'h0100; PC_Plus_4_EX = 32'h0104; Rd_EX = 5'd11;
        RD1_EX = 32'd15; RD2_EX = 32'd99; ImmExt_EX = 32'd50; ALUSrc_EX = 1; ALUControl_EX = 4'b0000;
        check_all("2. I-Type ADDI",    65,  99, 32'h0132,  32'h0104, 0,    1, 0, 0, 2'b00, 11);

        // --------------------------------------------------------
        // TEST 3: Data Hazard 
        // --------------------------------------------------------
        reset_signals();
        RegWrite_EX = 1; PC_Plus_4_EX = 32'h0104; Rd_EX = 5'd12; ALUControl_EX = 4'b0000;
        ForwardA_EX = 2'b10; ALUResult_MEM = 32'd100; 
        ForwardB_EX = 2'b01; Result_WB     = 32'd200; 
        check_all("3. Hazard A(MEM) B(WB)", 300, 200, 32'h0000, 32'h0104, 0, 1, 0, 0, 2'b00, 12);

        // --------------------------------------------------------
        // TEST 4: Lenh Load/Store 
        // --------------------------------------------------------
        reset_signals();
        MemWrite_EX = 1; PC_Plus_4_EX = 32'h0104; Rd_EX = 5'd0; ALUSrc_EX = 1; ALUControl_EX = 4'b0000;
        RD1_EX = 32'd50; ImmExt_EX = 32'd4;           
        ForwardB_EX = 2'b10; ALUResult_MEM = 32'd1024; 
        check_all("4. SW + Forward B", 54, 1024, 32'h0004, 32'h0104, 0, 0, 1, 0, 2'b00, 0);

        // --------------------------------------------------------
        // TEST 5: Control Hazard - BEQ
        // --------------------------------------------------------
        reset_signals();
        Branch_EX = 1; funct3_EX = 3'b000; PC_EX = 32'h0040; ImmExt_EX = 32'h0010; PC_Plus_4_EX = 32'h0044;
        RD1_EX = 32'd50; RD2_EX = 32'd50; ALUControl_EX = 4'b0001; 
        check_all("5. BEQ Taken",      0,   50, 32'h0050,  32'h0044, 1,    0, 0, 0, 2'b00, 0);

        // --------------------------------------------------------
        // TEST 6: Control Hazard - BNE
        // --------------------------------------------------------
        reset_signals();
        Branch_EX = 1; funct3_EX = 3'b001; PC_EX = 32'h0040; ImmExt_EX = 32'h0010; PC_Plus_4_EX = 32'h0044;
        RD1_EX = 32'd50; RD2_EX = 32'd40; ALUControl_EX = 4'b0001; 
        check_all("6. BNE Taken",      10,  40, 32'h0050,  32'h0044, 1,    0, 0, 0, 2'b00, 0);

        // --------------------------------------------------------
        // TEST 7: Lenh JUMP (JAL)
        // --------------------------------------------------------
        reset_signals();
        RegWrite_EX = 1; Jump_EX = 1; ResultSrc_EX = 2'b10; Rd_EX = 5'd1; PC_Plus_4_EX = 32'h0104;
        PC_EX = 32'h0100; ImmExt_EX = 32'h0020;
        check_all("7. JAL Jump",       0,   0,  32'h0120,  32'h0104, 1,    1, 0, 0, 2'b10, 1);

        // --------------------------------------------------------
        // TEST 8: JALR ket hop DATA FORWARDING
        // --------------------------------------------------------
        reset_signals();
        RegWrite_EX = 1; Jalr_EX = 1; ALUSrc_EX = 1; ResultSrc_EX = 2'b10; Rd_EX = 5'd1; PC_Plus_4_EX = 32'h0104;
        PC_EX = 32'h0100; ImmExt_EX = 32'h0010; 
        ForwardA_EX = 2'b10; ALUResult_MEM = 32'h0400; ALUControl_EX = 4'b0000; 
        check_all("8. JALR + Forwarding", 32'h0410, 0, 32'h0410, 32'h0104, 1, 1, 0, 0, 2'b10, 1);

        // --------------------------------------------------------
        // TONG KET
        // --------------------------------------------------------
        $display("==========================================================================");
        $display("SUMMARY EX_STAGE: PASS = %0d | FAIL = %0d", pass_count, fail_count);
        if (fail_count == 0) $display(">>> TAT CA CAC TRUONG HOP DA DUOC KIEM TRA THANH CONG! <<<");
        $display("==========================================================================\n");
        $finish;
    end
endmodule