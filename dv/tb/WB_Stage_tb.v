`timescale 1ns / 1ps

// ============================================================
// WB_Stage_tb.v
// Functional Verification Testbench for WB_Stage & Result_Mux
// ============================================================

module WB_Stage_tb;

    // ========================================================
    // 1. DUT INPUTS & OUTPUTS
    // ========================================================
    reg         RegWrite_WB;
    reg  [1:0]  ResultSrc_WB;
    reg  [31:0] ALUResult_WB, ReadData_WB, PC_Plus_4_WB, PCTarget_WB;
    reg  [4:0]  Rd_WB;

    wire        RegWrite_WB_out;
    wire [4:0]  Rd_WB_out;
    wire [31:0] Result_WB;

    // ========================================================
    // 2. TEST STATISTICS & VARIABLES
    // ========================================================
    integer pass_count = 0;
    integer fail_count = 0;
    
    // Đã tách khai báo i, j ra ngoài để chuẩn hóa với Verilog-2001
    integer i, j; 

    // ========================================================
    // 3. DUT INSTANTIATION
    // ========================================================
    WB_Stage dut (
        .RegWrite_WB       (RegWrite_WB),
        .ResultSrc_WB      (ResultSrc_WB),
        .ALUResult_WB      (ALUResult_WB),
        .ReadData_WB       (ReadData_WB),
        .PC_Plus_4_WB      (PC_Plus_4_WB),
        .PCTarget_WB       (PCTarget_WB),
        .Rd_WB             (Rd_WB),
        
        .RegWrite_WB_out   (RegWrite_WB_out),
        .Rd_WB_out         (Rd_WB_out),
        .Result_WB         (Result_WB)
    );

    // ========================================================
    // 4. CHECK TASK (Optimized Transcript Output)
    // ========================================================
    task check_wb;
        input [8*60:1] test_name;
        input          expected_RegWrite;
        input [4:0]    expected_Rd;
        input [31:0]   expected_Result;
        begin
            #1;
            if ((RegWrite_WB_out === expected_RegWrite) &&
                (Rd_WB_out       === expected_Rd)       &&
                (Result_WB       === expected_Result)) begin
                
                pass_count = pass_count + 1;
                $display("[PASS] %0s", test_name);
            end
            else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s", test_name);
                $display("       ACTUAL   : RegW=%b | Rd=%02d | Result=%h", RegWrite_WB_out, Rd_WB_out, Result_WB);
                $display("       EXPECTED : RegW=%b | Rd=%02d | Result=%h", expected_RegWrite, expected_Rd, expected_Result);
            end
            #9;
        end
    endtask

    // ========================================================
    // 5. MAIN TEST SEQUENCE
    // ========================================================
    initial begin
        // INITIAL VALUES
        RegWrite_WB = 1'b0; ResultSrc_WB = 2'b00; Rd_WB = 5'd0;
        ALUResult_WB = 32'h0; ReadData_WB = 32'h0; PC_Plus_4_WB = 32'h0; PCTarget_WB = 32'h0;
        #10;

        $display("\n============================================================");
        $display("             WB_STAGE FUNCTIONAL VERIFICATION               ");
        $display("============================================================");

        // TEST 1: RESET-LIKE / ALL ZERO VALUES
        check_wb(" 1. All-zero inputs", 1'b0, 5'd0, 32'h00000000);

        // TEST 2: ResultSrc = ALU (RegWrite = 1)
        RegWrite_WB = 1'b1; ResultSrc_WB = 2'b00; Rd_WB = 5'd1;
        ALUResult_WB = 32'h12345678; ReadData_WB = 32'hAAAAAAAA; 
        PC_Plus_4_WB = 32'h00000104; PCTarget_WB = 32'h00000200;
        check_wb(" 2. ALU result with RegWrite=1", 1'b1, 5'd1, 32'h12345678);

        // TEST 3: ResultSrc = ReadData
        ResultSrc_WB = 2'b01; Rd_WB = 5'd2; ReadData_WB = 32'hDEADBEEF;
        check_wb(" 3. ReadData result", 1'b1, 5'd2, 32'hDEADBEEF);

        // TEST 4: ResultSrc = PC + 4
        ResultSrc_WB = 2'b10; Rd_WB = 5'd3;
        ALUResult_WB = 32'h11111111; ReadData_WB = 32'h22222222; 
        PC_Plus_4_WB = 32'h00000104; PCTarget_WB = 32'h33333333;
        check_wb(" 4. PC_Plus_4 result", 1'b1, 5'd3, 32'h00000104);

        // TEST 5: ResultSrc = PCTarget
        ResultSrc_WB = 2'b11; Rd_WB = 5'd4;
        PC_Plus_4_WB = 32'h33333333; PCTarget_WB = 32'h00000200;
        check_wb(" 5. PCTarget result", 1'b1, 5'd4, 32'h00000200);

        // TEST 6-9: RegWrite = 0 (MUX must still select correctly)
        RegWrite_WB = 1'b0; 
        ALUResult_WB = 32'hCAFEBABE; ReadData_WB = 32'hDEADBEEF; 
        PC_Plus_4_WB = 32'h12345678; PCTarget_WB = 32'h87654321;
        
        ResultSrc_WB = 2'b00; Rd_WB = 5'd5; check_wb(" 6. RegWrite=0 with ALU result", 1'b0, 5'd5, 32'hCAFEBABE);
        ResultSrc_WB = 2'b01; Rd_WB = 5'd6; check_wb(" 7. RegWrite=0 with ReadData",   1'b0, 5'd6, 32'hDEADBEEF);
        ResultSrc_WB = 2'b10; Rd_WB = 5'd7; check_wb(" 8. RegWrite=0 with PC_Plus_4",  1'b0, 5'd7, 32'h12345678);
        ResultSrc_WB = 2'b11; Rd_WB = 5'd8; check_wb(" 9. RegWrite=0 with PCTarget",   1'b0, 5'd8, 32'h87654321);

        // TEST 10: MUX Isolation (All 4 sources have different values)
        RegWrite_WB = 1'b1; Rd_WB = 5'd10;
        ALUResult_WB = 32'h11111111; ReadData_WB = 32'h22222222; 
        PC_Plus_4_WB = 32'h33333333; PCTarget_WB = 32'h44444444;

        ResultSrc_WB = 2'b00; check_wb("10a. Mux ALUResult selection", 1'b1, 5'd10, 32'h11111111);
        ResultSrc_WB = 2'b01; check_wb("10b. Mux ReadData selection",  1'b1, 5'd10, 32'h22222222);
        ResultSrc_WB = 2'b10; check_wb("10c. Mux PC_Plus_4 selection", 1'b1, 5'd10, 32'h33333333);
        ResultSrc_WB = 2'b11; check_wb("10d. Mux PCTarget selection",  1'b1, 5'd10, 32'h44444444);

        // TEST 11-14: Random Rd Values
        ALUResult_WB = 32'hAAAAAAAA; ReadData_WB = 32'hBBBBBBBB; 
        PC_Plus_4_WB = 32'hCCCCCCCC; PCTarget_WB = 32'hDDDDDDDD;
        
        ResultSrc_WB = 2'b00; Rd_WB = 5'd0;  check_wb("11. Rd = x0",  1'b1, 5'd0,  32'hAAAAAAAA);
        ResultSrc_WB = 2'b01; Rd_WB = 5'd31; check_wb("12. Rd = x31", 1'b1, 5'd31, 32'hBBBBBBBB);
        ResultSrc_WB = 2'b10; Rd_WB = 5'd15; check_wb("13. Rd = x15", 1'b1, 5'd15, 32'hCCCCCCCC);
        ResultSrc_WB = 2'b11; Rd_WB = 5'd16; check_wb("14. Rd = x16", 1'b1, 5'd16, 32'hDDDDDDDD);

        // TEST 15: Boundary Data Patterns
        Rd_WB = 5'd20;
        ALUResult_WB = 32'h00000001; ReadData_WB = 32'hFFFFFFFF; 
        PC_Plus_4_WB = 32'h80000000; PCTarget_WB = 32'h7FFFFFFF;
        
        ResultSrc_WB = 2'b00; check_wb("15a. ALU boundary 00000001",      1'b1, 5'd20, 32'h00000001);
        ResultSrc_WB = 2'b01; check_wb("15b. ReadData boundary FFFFFFFF", 1'b1, 5'd20, 32'hFFFFFFFF);
        ResultSrc_WB = 2'b10; check_wb("15c. PC_Plus_4 boundary 80000000",1'b1, 5'd20, 32'h80000000);
        ResultSrc_WB = 2'b11; check_wb("15d. PCTarget boundary 7FFFFFFF", 1'b1, 5'd20, 32'h7FFFFFFF);

        // TEST 16: Pattern A
        Rd_WB = 5'd21;
        ALUResult_WB = 32'hAAAAAAAA; ReadData_WB = 32'h55555555; 
        PC_Plus_4_WB = 32'hCCCCCCCC; PCTarget_WB = 32'h33333333;
        
        ResultSrc_WB = 2'b00; check_wb("16a. Pattern A - ALU",       1'b1, 5'd21, 32'hAAAAAAAA);
        ResultSrc_WB = 2'b01; check_wb("16b. Pattern A - ReadData",  1'b1, 5'd21, 32'h55555555);
        ResultSrc_WB = 2'b10; check_wb("16c. Pattern A - PC_Plus_4", 1'b1, 5'd21, 32'hCCCCCCCC);
        ResultSrc_WB = 2'b11; check_wb("16d. Pattern A - PCTarget",  1'b1, 5'd21, 32'h33333333);

        // TEST 17: Pattern B (RegWrite = 0)
        RegWrite_WB = 1'b0; Rd_WB = 5'd22;
        ALUResult_WB = 32'h00000000; ReadData_WB = 32'hFFFFFFFF; 
        PC_Plus_4_WB = 32'h7FFFFFFF; PCTarget_WB = 32'h80000000;
        
        ResultSrc_WB = 2'b00; check_wb("17a. Pattern B - ALU",       1'b0, 5'd22, 32'h00000000);
        ResultSrc_WB = 2'b01; check_wb("17b. Pattern B - ReadData",  1'b0, 5'd22, 32'hFFFFFFFF);
        ResultSrc_WB = 2'b10; check_wb("17c. Pattern B - PC_Plus_4", 1'b0, 5'd22, 32'h7FFFFFFF);
        ResultSrc_WB = 2'b11; check_wb("17d. Pattern B - PCTarget",  1'b0, 5'd22, 32'h80000000);

        // TEST 18: All 32 Rd Values
        RegWrite_WB = 1'b1; ResultSrc_WB = 2'b00;
        ALUResult_WB = 32'h12345678; ReadData_WB = 32'h87654321; 
        PC_Plus_4_WB = 32'h00001000; PCTarget_WB = 32'h00002000;
        
        // Đã sửa cú pháp vòng lặp for
        for (i = 0; i < 32; i = i + 1) begin
            Rd_WB = i[4:0];
            check_wb("18. All Rd values 0~31", 1'b1, i[4:0], 32'h12345678);
        end

        // TEST 19: All 32 Rd Values + RegWrite = 0
        RegWrite_WB = 1'b0; ResultSrc_WB = 2'b01;
        ALUResult_WB = 32'h11111111; ReadData_WB = 32'h22222222; 
        PC_Plus_4_WB = 32'h33333333; PCTarget_WB = 32'h44444444;
        
        // Đã sửa cú pháp vòng lặp for
        for (j = 0; j < 32; j = j + 1) begin
            Rd_WB = j[4:0];
            check_wb("19. All Rd values with RegWrite=0", 1'b0, j[4:0], 32'h22222222);
        end

        // TEST 20: Change Input Data While Keeping ResultSrc
        RegWrite_WB = 1'b1; ResultSrc_WB = 2'b00; Rd_WB = 5'd25;
        ALUResult_WB = 32'h00000001; check_wb("20a. Combinational ALU result = 1", 1'b1, 5'd25, 32'h00000001);
        ALUResult_WB = 32'h00000002; check_wb("20b. Combinational ALU result = 2", 1'b1, 5'd25, 32'h00000002);
        ALUResult_WB = 32'hFFFFFFFF; check_wb("20c. Combinational ALU result = F", 1'b1, 5'd25, 32'hFFFFFFFF);

        // TEST 21: Change ResultSrc Without Changing Data
        Rd_WB = 5'd30;
        ALUResult_WB = 32'hAAAAAAAA; ReadData_WB = 32'hBBBBBBBB; 
        PC_Plus_4_WB = 32'hCCCCCCCC; PCTarget_WB = 32'hDDDDDDDD;
        
        ResultSrc_WB = 2'b00; check_wb("21a. ResultSrc transition -> ALU",       1'b1, 5'd30, 32'hAAAAAAAA);
        ResultSrc_WB = 2'b01; check_wb("21b. ResultSrc transition -> ReadData",  1'b1, 5'd30, 32'hBBBBBBBB);
        ResultSrc_WB = 2'b10; check_wb("21c. ResultSrc transition -> PC_Plus_4", 1'b1, 5'd30, 32'hCCCCCCCC);
        ResultSrc_WB = 2'b11; check_wb("21d. ResultSrc transition -> PCTarget",  1'b1, 5'd30, 32'hDDDDDDDD);

        // TEST 22: Final Full Combination Check
        ALUResult_WB = 32'h13579BDF; ReadData_WB = 32'h2468ACE0; 
        PC_Plus_4_WB = 32'hFEDCBA98; PCTarget_WB = 32'h01234567;

        RegWrite_WB = 1'b0; Rd_WB = 5'd0;
        ResultSrc_WB = 2'b00; check_wb("22a. Full combo: W0 Rd0 Src00", 1'b0, 5'd0, 32'h13579BDF);
        ResultSrc_WB = 2'b01; check_wb("22b. Full combo: W0 Rd0 Src01", 1'b0, 5'd0, 32'h2468ACE0);
        ResultSrc_WB = 2'b10; check_wb("22c. Full combo: W0 Rd0 Src10", 1'b0, 5'd0, 32'hFEDCBA98);
        ResultSrc_WB = 2'b11; check_wb("22d. Full combo: W0 Rd0 Src11", 1'b0, 5'd0, 32'h01234567);

        RegWrite_WB = 1'b1; Rd_WB = 5'd31;
        ResultSrc_WB = 2'b00; check_wb("22e. Full combo: W1 Rd31 Src00", 1'b1, 5'd31, 32'h13579BDF);
        ResultSrc_WB = 2'b01; check_wb("22f. Full combo: W1 Rd31 Src01", 1'b1, 5'd31, 32'h2468ACE0);
        ResultSrc_WB = 2'b10; check_wb("22g. Full combo: W1 Rd31 Src10", 1'b1, 5'd31, 32'hFEDCBA98);
        ResultSrc_WB = 2'b11; check_wb("22h. Full combo: W1 Rd31 Src11", 1'b1, 5'd31, 32'h01234567);

        // FINAL SUMMARY
        $display("\n============================================================");
        $display("                   TEST SUMMARY");
        $display("============================================================");
        $display("PASS = %0d", pass_count);
        $display("FAIL = %0d", fail_count);

        if (fail_count == 0) $display("\n>>> ALL WB_STAGE FUNCTIONAL TESTS PASSED <<<");
        else                 $display("\n>>> SOME WB_STAGE TESTS FAILED <<<");
        $display("============================================================\n");

        #10;
        $finish;
    end
endmodule