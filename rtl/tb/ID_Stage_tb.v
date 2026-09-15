`timescale 1ns / 1ps

// ============================================================
// ID_Stage_tb.v - Testbench toi uu cho tang ID RISC-V (Ban Fix Cuoi Cung)
// ============================================================

module ID_Stage_tb;

    // ========================================================
    // 1. Tin hieu he thong
    // ========================================================
    reg         clk;

    reg [31:0]  PC_ID, Instr_ID, PC_Plus_4_ID;
    reg         RegWrite_WB;
    reg [4:0]   Rd_WB;
    reg [31:0]  Result_WB;

    wire        RegWrite_ID_out, MemWrite_ID_out, MemRead_ID_out;
    wire        Branch_ID_out, Jump_ID_out, Jalr_ID_out, ALUSrc_ID_out;
    wire [1:0]  ResultSrc_ID_out;
    wire [3:0]  ALUControl_ID_out;

    wire [31:0] PC_ID_out, RD1_ID_out, RD2_ID_out, ImmExt_ID_out, PC_Plus_4_ID_out;
    wire [4:0]  Rs1_ID_out, Rs2_ID_out, Rd_ID_out;
    wire [2:0]  funct3_ID_out;

    integer pass_count, fail_count, i; 

    // ========================================================
    // 2. Encoding hang so (Localparams)
    // ========================================================
    localparam [1:0] SRC_ALU = 2'b00, SRC_MEM = 2'b01, SRC_PC4 = 2'b10, SRC_PCT = 2'b11;
    localparam [3:0] ALU_ADD = 4'b0000, ALU_SUB = 4'b0001, ALU_AND = 4'b0010, 
                     ALU_OR  = 4'b0011, ALU_XOR = 4'b0100, ALU_SLT = 4'b0101, 
                     ALU_SLL = 4'b1010, ALU_SRL = 4'b1100, ALU_SRA = 4'b1011, 
                     ALU_LUI = 4'b1001; 

    // Khoi tao DUT
    ID_Stage DUT (
        .clk                (clk),
        .PC_ID              (PC_ID), .Instr_ID(Instr_ID), .PC_Plus_4_ID(PC_Plus_4_ID),
        .RegWrite_WB        (RegWrite_WB), .Rd_WB(Rd_WB), .Result_WB(Result_WB),
        
        .RegWrite_ID_out    (RegWrite_ID_out), .MemWrite_ID_out(MemWrite_ID_out),
        .MemRead_ID_out     (MemRead_ID_out), .Branch_ID_out(Branch_ID_out),
        .Jump_ID_out        (Jump_ID_out), .Jalr_ID_out(Jalr_ID_out),
        .ALUSrc_ID_out      (ALUSrc_ID_out), .ResultSrc_ID_out(ResultSrc_ID_out),
        .ALUControl_ID_out  (ALUControl_ID_out),
        
        .PC_ID_out          (PC_ID_out), .RD1_ID_out(RD1_ID_out), .RD2_ID_out(RD2_ID_out),
        .ImmExt_ID_out      (ImmExt_ID_out), .PC_Plus_4_ID_out(PC_Plus_4_ID_out),
        .Rs1_ID_out         (Rs1_ID_out), .Rs2_ID_out(Rs2_ID_out),
        .Rd_ID_out          (Rd_ID_out), .funct3_ID_out(funct3_ID_out)
    );

    // Tao Clock
    initial begin
        clk = 1'b0; forever #5 clk = ~clk;
    end

    // ========================================================
    // 3. Task Kiem tra 
    // ========================================================
    task check;
        input [31:0] exp_PC, exp_PC4, exp_RD1, exp_RD2, exp_Imm;
        input [4:0]  exp_Rs1, exp_Rs2, exp_Rd;
        input [2:0]  exp_funct3;
        input        exp_RegWrite, exp_MemWrite, exp_MemRead, exp_Branch, exp_Jump, exp_Jalr, exp_ALUSrc;
        input [1:0]  exp_ResultSrc;
        input [3:0]  exp_ALUControl;
        input [8*60:1] test_name; 
        begin
            #1; // Doi tin hieu on dinh
            if ((PC_ID_out         === exp_PC)       && (PC_Plus_4_ID_out  === exp_PC4)      &&
                (RD1_ID_out        === exp_RD1)      && (RD2_ID_out        === exp_RD2)      &&
                (ImmExt_ID_out     === exp_Imm)      && (Rs1_ID_out        === exp_Rs1)      &&
                (Rs2_ID_out        === exp_Rs2)      && (Rd_ID_out         === exp_Rd)       &&
                (funct3_ID_out     === exp_funct3)   && (RegWrite_ID_out   === exp_RegWrite) &&
                (MemWrite_ID_out   === exp_MemWrite) && (MemRead_ID_out    === exp_MemRead)  &&
                (Branch_ID_out     === exp_Branch)   && (Jump_ID_out       === exp_Jump)     &&
                (Jalr_ID_out       === exp_Jalr)     && (ALUSrc_ID_out     === exp_ALUSrc)   &&
                (ResultSrc_ID_out  === exp_ResultSrc)&& (ALUControl_ID_out === exp_ALUControl)) begin
                
                pass_count = pass_count + 1;
                $display("[PASS] %0s", test_name);
            end
            else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s", test_name);
                $display("       [ACTUAL] Rs1=%d Rs2=%d Rd=%d Funct3=%b RD1=%h RD2=%h", Rs1_ID_out, Rs2_ID_out, Rd_ID_out, funct3_ID_out, RD1_ID_out, RD2_ID_out);
                $display("       [EXPECT] Rs1=%d Rs2=%d Rd=%d Funct3=%b RD1=%h RD2=%h", exp_Rs1, exp_Rs2, exp_Rd, exp_funct3, exp_RD1, exp_RD2);
                $display("       [ACTUAL] Ctrl: RegW=%b MemW=%b MemR=%b Br=%b Jmp=%b Jlr=%b ASrc=%b RSrc=%b ALU=%b",
                         RegWrite_ID_out, MemWrite_ID_out, MemRead_ID_out, Branch_ID_out, Jump_ID_out, Jalr_ID_out, ALUSrc_ID_out, ResultSrc_ID_out, ALUControl_ID_out);
            end
        end
    endtask

    // ========================================================
    // 4. Luong Test Kich Ban
    // ========================================================
    initial begin
        pass_count = 0; fail_count = 0;

        // Trang thai mac dinh
        PC_ID = 32'h0000_1000; PC_Plus_4_ID = 32'h0000_1004;
        RegWrite_WB = 1'b0; Rd_WB = 5'd0; Result_WB = 32'h0000_0000;

        // Xoa sach Register File ve 0 de tranh loi 'x'
        for (i = 0; i < 32; i = i + 1) begin
            DUT.u_Register_File.REG_MEM_BLOCK[i] = 32'h0000_0000;
        end

        // Bom du lieu gia lap
        DUT.u_Register_File.REG_MEM_BLOCK[5]  = 32'h1111_1111;
        DUT.u_Register_File.REG_MEM_BLOCK[6]  = 32'h2222_2222;
        DUT.u_Register_File.REG_MEM_BLOCK[8]  = 32'h4444_4444; // Dung cho test 19, 20
        DUT.u_Register_File.REG_MEM_BLOCK[10] = 32'hAAAA_AAAA; 

        $display("\n=========================================================================");
        $display("                         BAT DAU TEST TANG ID                            ");
        $display("=========================================================================");

        Instr_ID = 32'h00A0_0293; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h0000_0000, 32'hAAAA_AAAA, 32'h0000_000A, 5'd0, 5'd10, 5'd5, 3'b000,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, SRC_ALU, ALU_ADD, " 1. I-Type: ADDI x5, x0, 10");

        Instr_ID = 32'h0052_8333; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h1111_1111, 32'h1111_1111, 32'h0000_0005, 5'd5, 5'd5, 5'd6, 3'b000,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_ADD, " 2. R-Type: ADD x6, x5, x5");

        Instr_ID = 32'h4053_03B3; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h2222_2222, 32'h1111_1111, 32'h0000_0405, 5'd6, 5'd5, 5'd7, 3'b000,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_SUB, " 3. R-Type: SUB x7, x6, x5");

        Instr_ID = 32'h0053_7433; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h2222_2222, 32'h1111_1111, 32'h0000_0005, 5'd6, 5'd5, 5'd8, 3'b111,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_AND, " 4. R-Type: AND x8, x6, x5");

        Instr_ID = 32'h0053_64B3; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h2222_2222, 32'h1111_1111, 32'h0000_0005, 5'd6, 5'd5, 5'd9, 3'b110,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_OR,  " 5. R-Type: OR  x9, x6, x5");

        Instr_ID = 32'h0053_4533; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h2222_2222, 32'h1111_1111, 32'h0000_0005, 5'd6, 5'd5, 5'd10, 3'b100,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_XOR, " 6. R-Type: XOR x10, x6, x5");

        Instr_ID = 32'h0053_25B3; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h2222_2222, 32'h1111_1111, 32'h0000_0005, 5'd6, 5'd5, 5'd11, 3'b010,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_SLT, " 7. R-Type: SLT x11, x6, x5");

        Instr_ID = 32'h0053_1633; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h2222_2222, 32'h1111_1111, 32'h0000_0005, 5'd6, 5'd5, 5'd12, 3'b001,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_SLL, " 8. R-Type: SLL x12, x6, x5");

        Instr_ID = 32'h0053_56B3; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h2222_2222, 32'h1111_1111, 32'h0000_0005, 5'd6, 5'd5, 5'd13, 3'b101,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_SRL, " 9. R-Type: SRL x13, x6, x5");

        Instr_ID = 32'h4053_5733; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h2222_2222, 32'h1111_1111, 32'h0000_0405, 5'd6, 5'd5, 5'd14, 3'b101,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_SRA, "10. R-Type: SRA x14, x6, x5");

        Instr_ID = 32'h0053_2823; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h2222_2222, 32'h1111_1111, 32'h0000_0010, 5'd6, 5'd5, 5'd16, 3'b010,
              1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, SRC_ALU, ALU_ADD, "11. S-Type: SW x5, 16(x6)");

        Instr_ID = 32'h0103_2783; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h2222_2222, 32'h0000_0000, 32'h0000_0010, 5'd6, 5'd16, 5'd15, 3'b010,
              1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, SRC_MEM, ALU_ADD, "12. I-Type: LW x15, 16(x6)");

        Instr_ID = 32'h0062_8463; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h1111_1111, 32'h2222_2222, 32'h0000_0008, 5'd5, 5'd6, 5'd8, 3'b000,
              1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_SUB, "13. B-Type: BEQ x5, x6, +8");

        Instr_ID = 32'h0062_9463; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h1111_1111, 32'h2222_2222, 32'h0000_0008, 5'd5, 5'd6, 5'd8, 3'b001,
              1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_SUB, "14. B-Type: BNE x5, x6, +8");

        Instr_ID = 32'h0062_C463; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h1111_1111, 32'h2222_2222, 32'h0000_0008, 5'd5, 5'd6, 5'd8, 3'b100,
              1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_SUB, "15. B-Type: BLT x5, x6, +8");

        Instr_ID = 32'h0062_D463; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h1111_1111, 32'h2222_2222, 32'h0000_0008, 5'd5, 5'd6, 5'd8, 3'b101,
              1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_SUB, "16. B-Type: BGE x5, x6, +8");

        Instr_ID = 32'h0062_E463; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h1111_1111, 32'h2222_2222, 32'h0000_0008, 5'd5, 5'd6, 5'd8, 3'b110,
              1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_SUB, "17. B-Type: BLTU x5, x6, +8");

        Instr_ID = 32'h0062_F463; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h1111_1111, 32'h2222_2222, 32'h0000_0008, 5'd5, 5'd6, 5'd8, 3'b111,
              1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_SUB, "18. B-Type: BGEU x5, x6, +8");

        // [DA FIX LUI]: rs1 rac=8, rs2 rac=3, RD1 doc duoc h4444_4444
        Instr_ID = 32'h1234_5837; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h4444_4444, 32'h0000_0000, 32'h1234_5000, 5'd8, 5'd3, 5'd16, 3'b101,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, SRC_ALU, ALU_LUI, "19. U-Type: LUI x16, 0x12345");

        // [DA FIX AUIPC]: rs1 rac=8, rs2 rac=3, RD1 doc duoc h4444_4444
        Instr_ID = 32'h1234_5897; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h4444_4444, 32'h0000_0000, 32'h1234_5000, 5'd8, 5'd3, 5'd17, 3'b101,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, SRC_PCT, ALU_ADD, "20. U-Type: AUIPC x17, 0x12345");

        // [DA FIX JAL]: rs2 rac = 16
        Instr_ID = 32'h0100_00EF; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h0000_0000, 32'h0000_0000, 32'h0000_0010, 5'd0, 5'd16, 5'd1, 3'b000,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, SRC_PC4, ALU_ADD, "21. J-Type: JAL x1, +16");

        // [DA FIX JALR]: rs2 rac = 4. 
        Instr_ID = 32'h0042_80E7; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h1111_1111, 32'h0000_0000, 32'h0000_0004, 5'd5, 5'd4, 5'd1, 3'b000,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, SRC_PC4, ALU_ADD, "22. I-Type: JALR x1, 4(x5)");

        Instr_ID = 32'h0000_09B3; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 5'd0, 5'd0, 5'd19, 3'b000,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SRC_ALU, ALU_ADD, "23. x0 Read (ADD x19, x0, x0)");

        // [DA FIX Bypass]: rs2 rac = 1.
        RegWrite_WB = 1'b1; Rd_WB = 5'd10; Result_WB = 32'hDEAD_BEEF;
        Instr_ID = 32'h0015_0A13; #1;
        check(32'h0000_1000, 32'h0000_1004, 32'hDEAD_BEEF, 32'h0000_0000, 32'h0000_0001, 5'd10, 5'd1, 5'd20, 3'b000,
              1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, SRC_ALU, ALU_ADD, "24. Write-First (WB -> ID bypass)");
        @(posedge clk); #1; 
        RegWrite_WB = 1'b0; Rd_WB = 5'd0; Result_WB = 32'h0000_0000;

        Instr_ID = 32'h0000_0513; #1; 
        Instr_ID = 32'h0000_0A13; #1; 
        if (RD1_ID_out === 32'h0000_0000) begin
            pass_count = pass_count + 1;
            $display("[PASS] 25. x0 Read sau Write-First van la 0");
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] 25. x0 Read = %h (Expected 0)", RD1_ID_out);
        end

        DUT.u_Register_File.REG_MEM_BLOCK[21] = 32'h1357_9BDF;
        Instr_ID = 32'h0000_0A93; #1;
        if (RD1_ID_out === 32'h0000_0000) begin
            pass_count = pass_count + 1;
            $display("[PASS] 26. RegWrite_WB = 0 khong anh huong x0");
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] 26. x0 Read = %h (Expected 0)", RD1_ID_out);
        end

        $display("\n=========================================================================");
        $display("SUMMARY ID_STAGE: PASS = %0d | FAIL = %0d", pass_count, fail_count);
        if (fail_count == 0) $display(">>> ALL ID_STAGE TESTS PASSED. READY FOR EX_STAGE! <<<");
        else                 $display(">>> SOME TESTS FAILED. PLEASE CHECK LOGS. <<<");
        $display("=========================================================================\n");

        $finish;
    end
endmodule