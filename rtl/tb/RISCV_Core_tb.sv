`timescale 1ns/1ps

module RISCV_Core_tb;

    // --- Khai bao tin hieu ---
    reg clk = 0, rst, bus_stall;
    reg [31:0] instr_rdata = 0, data_rdata = 0, imem_word, dmem_rdata_force, pc_before_stall;
    reg [31:0] instr_before_stall;
    reg [1:0]  ForwardA_EX = 0, ForwardB_EX = 0; 
    wire [31:0] instr_addr, data_wdata, PC_debug, Instr_debug, Result_WB_debug;
    wire        data_we, data_re, RegWrite_WB_debug;
    wire [4:0]  Rd_WB_debug;

    integer pass_count = 0, fail_count = 0, wb_seen = 0;

    // --- Khoi tao DUT ---
    RISCV_Core dut (
        .clk(clk), .rst(rst), .bus_stall(bus_stall),
        .instr_rdata(instr_rdata), .data_rdata(data_rdata),
        .ForwardA_EX(ForwardA_EX), .ForwardB_EX(ForwardB_EX), 
        .instr_addr(instr_addr), .data_wdata(data_wdata),
        .data_we(data_we), .data_re(data_re),
        .PC_debug(PC_debug), .Instr_debug(Instr_debug),
        .RegWrite_WB_debug(RegWrite_WB_debug), .Rd_WB_debug(Rd_WB_debug), .Result_WB_debug(Result_WB_debug)
    );

    always #5 clk = ~clk;

    // --- Cac ham ho tro (Chuan Verilog-2001 ANSI) ---
    function [31:0] enc_r(input [6:0] f7, input [4:0] rs2, input [4:0] rs1, input [2:0] f3, input [4:0] rd, input [6:0] op); enc_r = {f7,rs2,rs1,f3,rd,op}; endfunction
    function [31:0] enc_i(input [11:0] imm, input [4:0] rs1, input [2:0] f3, input [4:0] rd, input [6:0] op); enc_i = {imm,rs1,f3,rd,op}; endfunction
    function [31:0] enc_s(input [11:0] imm, input [4:0] rs2, input [4:0] rs1, input [2:0] f3, input [6:0] op); enc_s = {imm[11:5],rs2,rs1,f3,imm[4:0],op}; endfunction
    function [31:0] enc_b(input [12:0] imm, input [4:0] rs2, input [4:0] rs1, input [2:0] f3, input [6:0] op); enc_b = {imm[12],imm[10:5],rs2,rs1,f3,imm[4:1],imm[11],op}; endfunction
    function [31:0] enc_u(input [19:0] imm20, input [4:0] rd, input [6:0] op); enc_u = {imm20,rd,op}; endfunction
    function [31:0] enc_j(input [20:0] imm, input [4:0] rd, input [6:0] op); enc_j = {imm[20],imm[10:1],imm[11],imm[19:12],rd,op}; endfunction

    function [31:0] NOP();                                          NOP   = 32'h00000013; endfunction
    function [31:0] ADDI (input [4:0] rd, rs1, input [11:0] imm);   ADDI  = enc_i(imm,rs1,3'b000,rd,7'b0010011); endfunction
    function [31:0] ANDI (input [4:0] rd, rs1, input [11:0] imm);   ANDI  = enc_i(imm,rs1,3'b111,rd,7'b0010011); endfunction
    function [31:0] ORI  (input [4:0] rd, rs1, input [11:0] imm);   ORI   = enc_i(imm,rs1,3'b110,rd,7'b0010011); endfunction
    function [31:0] XORI (input [4:0] rd, rs1, input [11:0] imm);   XORI  = enc_i(imm,rs1,3'b100,rd,7'b0010011); endfunction
    function [31:0] SLTI (input [4:0] rd, rs1, input [11:0] imm);   SLTI  = enc_i(imm,rs1,3'b010,rd,7'b0010011); endfunction
    function [31:0] LW   (input [4:0] rd, rs1, input [11:0] imm);   LW    = enc_i(imm,rs1,3'b010,rd,7'b0000011); endfunction
    function [31:0] JALR (input [4:0] rd, rs1, input [11:0] imm);   JALR  = enc_i(imm,rs1,3'b000,rd,7'b1100111); endfunction
    function [31:0] SW   (input [4:0] rs2, rs1, input [11:0] imm);  SW    = enc_s(imm,rs2,rs1,3'b010,7'b0100011); endfunction
    function [31:0] ADD  (input [4:0] rd, rs1, rs2);                ADD   = enc_r(7'b0000000,rs2,rs1,3'b000,rd,7'b0110011); endfunction
    function [31:0] SUB  (input [4:0] rd, rs1, rs2);                SUB   = enc_r(7'b0100000,rs2,rs1,3'b000,rd,7'b0110011); endfunction
    function [31:0] AND_R(input [4:0] rd, rs1, rs2);                AND_R = enc_r(7'b0000000,rs2,rs1,3'b111,rd,7'b0110011); endfunction
    function [31:0] OR_R (input [4:0] rd, rs1, rs2);                OR_R  = enc_r(7'b0000000,rs2,rs1,3'b110,rd,7'b0110011); endfunction
    function [31:0] XOR_R(input [4:0] rd, rs1, rs2);                XOR_R = enc_r(7'b0000000,rs2,rs1,3'b100,rd,7'b0110011); endfunction
    function [31:0] SLL  (input [4:0] rd, rs1, rs2);                SLL   = enc_r(7'b0000000,rs2,rs1,3'b001,rd,7'b0110011); endfunction
    function [31:0] SRL  (input [4:0] rd, rs1, rs2);                SRL   = enc_r(7'b0000000,rs2,rs1,3'b101,rd,7'b0110011); endfunction
    function [31:0] SRA  (input [4:0] rd, rs1, rs2);                SRA   = enc_r(7'b0100000,rs2,rs1,3'b101,rd,7'b0110011); endfunction
    function [31:0] SLT  (input [4:0] rd, rs1, rs2);                SLT   = enc_r(7'b0000000,rs2,rs1,3'b010,rd,7'b0110011); endfunction
    function [31:0] SLTU (input [4:0] rd, rs1, rs2);                SLTU  = enc_r(7'b0000000,rs2,rs1,3'b011,rd,7'b0110011); endfunction
    function [31:0] BEQ  (input [4:0] rs1, rs2, input [12:0] imm);  BEQ   = enc_b(imm,rs2,rs1,3'b000,7'b1100011); endfunction
    function [31:0] BNE  (input [4:0] rs1, rs2, input [12:0] imm);  BNE   = enc_b(imm,rs2,rs1,3'b001,7'b1100011); endfunction
    function [31:0] JAL  (input [4:0] rd, input [20:0] imm);        JAL   = enc_j(imm,rd,7'b1101111); endfunction
    function [31:0] AUIPC(input [4:0] rd, input [19:0] imm20);      AUIPC = enc_u(imm20,rd,7'b0010111); endfunction

    // --- Hinh anh bo nho lenh (Program Image) ---
    always @(*) begin
        case (PC_debug)
            // Can ban & ALU
            32'h0000_0000: imem_word = ADDI(5'd1, 5'd0, 12'd5);        32'h0000_0004: imem_word = ADDI(5'd2, 5'd0, -12'd3);
            32'h0000_0008: imem_word = NOP();                          32'h0000_000C: imem_word = NOP(); 
            32'h0000_0010: imem_word = NOP();
            32'h0000_0014: imem_word = ADD(5'd3, 5'd1, 5'd1);          32'h0000_0018: imem_word = SUB(5'd4, 5'd1, 5'd2);
            32'h0000_001C: imem_word = AND_R(5'd5, 5'd1, 5'd2);        32'h0000_0020: imem_word = OR_R (5'd6, 5'd1, 5'd2);
            32'h0000_0024: imem_word = XOR_R(5'd7, 5'd1, 5'd2);        32'h0000_0028: imem_word = SLL(5'd8, 5'd1, 5'd1);
            32'h0000_002C: imem_word = SRL(5'd9, 5'd1, 5'd1);          32'h0000_0030: imem_word = SRA(5'd10, 5'd2, 5'd1);
            32'h0000_0034: imem_word = SLT(5'd11, 5'd2, 5'd1);         32'h0000_0038: imem_word = SLTU(5'd12, 5'd2, 5'd1);
            32'h0000_003C: imem_word = ANDI(5'd13, 5'd1, 12'h003);     32'h0000_0040: imem_word = ORI (5'd14, 5'd1, 12'h008);
            32'h0000_0044: imem_word = XORI(5'd15, 5'd1, 12'h00F);     32'h0000_0048: imem_word = SLTI(5'd16, 5'd2, 12'd1);
            
            // Bo nho & Bao ve x0
            32'h0000_004C: imem_word = ADDI(5'd17, 5'd0, 12'h100);     
            
            // CHEN 3 NOPs DE GIAI QUYET RAW HAZARD CHO x17
            32'h0000_0050: imem_word = NOP();
            32'h0000_0054: imem_word = NOP();
            32'h0000_0058: imem_word = NOP();

            32'h0000_005C: imem_word = SW(5'd1, 5'd17, 12'h000);       32'h0000_0060: imem_word = LW(5'd18, 5'd17, 12'h000);
            32'h0000_0064: imem_word = ADDI(5'd0, 5'd0, 12'd123);      32'h0000_0068: imem_word = ADDI(5'd19, 5'd0, 12'd9);       
            
            // DA DICH DIA CHI: Tinh toan AUIPC voi PC moi la 0x6C
            32'h0000_006C: imem_word = AUIPC(5'd20, 20'h1);
            
            // Lenh re nhanh BNE / BEQ
            32'h0000_0070: imem_word = BNE(5'd1, 5'd1, 13'd8);         32'h0000_0074: imem_word = ADDI(5'd21, 5'd0, 12'd21);
            32'h0000_0078: imem_word = BEQ(5'd1, 5'd1, 13'd8);         32'h0000_007C: imem_word = ADDI(5'd22, 5'd0, 12'd99); 
            32'h0000_0080: imem_word = ADDI(5'd23, 5'd0, 12'd23);      
            
            // Lenh nhay (Jumps)
            32'h0000_0084: imem_word = JAL(5'd24, 21'd12);
            32'h0000_0088: imem_word = ADDI(5'd25, 5'd0, 12'd99);      32'h0000_008C: imem_word = ADDI(5'd25, 5'd0, 12'd98);
            32'h0000_0090: imem_word = ADDI(5'd26, 5'd0, 12'd26);      
            
            // DA DICH DIA CHI: JALR target gio se nhay toi 0xC4
            32'h0000_0094: imem_word = ADDI(5'd27, 5'd0, 12'hC4);
            
            // CHEN 3 NOPs DE GIAI QUYET RAW HAZARD CHO x27
            32'h0000_0098: imem_word = NOP();
            32'h0000_009C: imem_word = NOP();
            32'h0000_00A0: imem_word = NOP();
            
            32'h0000_00A4: imem_word = JALR(5'd28, 5'd27, 12'd0);      32'h0000_00C4: imem_word = ADDI(5'd29, 5'd0, 12'd29);
            default:       imem_word = NOP();
        endcase
    end

    // --- Cac task kiem tra (Verification Tasks) ---
    task automatic check_equal32(input [31:0] actual, input [31:0] expected, input [255:0] name);
        if (actual === expected) begin pass_count++; $display("[PASS] %s : actual=%h", name, actual); end
        else begin fail_count++; $display("[FAIL] %s : actual=%h expected=%h", name, actual, expected); end
    endtask

    task automatic check_equal1(input actual, input expected, input [255:0] name);
        if (actual === expected) begin pass_count++; $display("[PASS] %s : actual=%b", name, actual); end
        else begin fail_count++; $display("[FAIL] %s : actual=%b expected=%b", name, actual, expected); end
    endtask

    task automatic expect_wb(input [4:0] expected_rd, input [31:0] expected_result, input [255:0] name);
        integer timeout = 0; reg found = 1'b0;
        while (!found && timeout < 40) begin
            @(posedge clk); #1; timeout++;
            if (RegWrite_WB_debug === 1'b1 && Rd_WB_debug === expected_rd && Result_WB_debug === expected_result) begin
                found = 1'b1; pass_count++; $display("[PASS] WB %-30s Rd=x%0d Result=%h", name, expected_rd, expected_result);
            end
        end
        if (!found) begin fail_count++; $display("[FAIL] WB %-30s expected Rd=x%0d Result=%h", name, expected_rd, expected_result); end
    endtask

    task automatic pulse_reset;
        begin
            rst = 1'b1; bus_stall = 1'b0; ForwardA_EX = 2'b00; ForwardB_EX = 2'b00; 
            repeat (3) @(posedge clk); #1; rst = 1'b0;
        end
    endtask

    // --- Trinh tu test chinh ---
    initial begin
        // Ep xung noi bo (Force signals)
        force dut.u_IF_Stage.Instr_IF_out = imem_word;
        force dut.u_MEM_Stage.ReadData_MEM_out = dmem_rdata_force;
        
        dmem_rdata_force = 32'hA5A5_5A5A;
        $display("\n=== RISC_Core COMPREHENSIVE TESTBENCH ===");
        
        // 1. Kiem tra Reset
        pulse_reset();
        check_equal32(PC_debug, 32'h0, "Reset -> PC = 0");
        check_equal1(RegWrite_WB_debug, 1'b0, "Reset -> no WB write");

        // 2. Kiem tra tuan tu & Write-Back
        expect_wb(5'd1, 32'h0000_0005, "ADDI x1, x0, 5");       expect_wb(5'd2, 32'hFFFF_FFFD, "ADDI x2, x0, -3");
        expect_wb(5'd3, 32'h0000_000A, "ADD x3,x1,x1");         expect_wb(5'd4, 32'h0000_0008, "SUB x4,x1,x2");
        expect_wb(5'd5, 32'h0000_0005 & 32'hFFFF_FFFD, "AND");  expect_wb(5'd6, 32'h0000_0005 | 32'hFFFF_FFFD, "OR");
        expect_wb(5'd7, 32'h0000_0005 ^ 32'hFFFF_FFFD, "XOR");  expect_wb(5'd8, 32'h0000_00A0, "SLL");
        expect_wb(5'd9, 32'h0000_0000, "SRL");                  expect_wb(5'd10, 32'hFFFF_FFFF, "SRA");
        expect_wb(5'd11,32'h0000_0001, "SLT");                  expect_wb(5'd12, 32'h0000_0000, "SLTU");
        expect_wb(5'd13,32'h0000_0001, "ANDI");                 expect_wb(5'd14, 32'h0000_000D, "ORI");
        expect_wb(5'd15,32'h0000_000A, "XORI");                 expect_wb(5'd16, 32'h0000_0001, "SLTI");
        expect_wb(5'd17,32'h0000_0100, "ADDI x17,0x100");
        
        while (dut.u_MEM_Stage.MemWrite_MEM !== 1'b1) @(posedge clk); 
        check_equal1(dut.u_MEM_Stage.MemWrite_MEM, 1'b1, "SW -> MemWrite");
        check_equal32(dut.u_MEM_Stage.ALUResult_MEM, 32'h0000_0100, "SW -> Address");
        expect_wb(5'd18,32'hA5A5_5A5A, "LW x18,0(x17)");
        
        #1; expect_wb(5'd19, 32'h0000_0009, "x0 Protection");
        
        expect_wb(5'd20, 32'h0000_106C, "AUIPC x20,0x1");
        
        expect_wb(5'd21, 32'h0000_0015, "BNE not taken");       expect_wb(5'd23, 32'h0000_0017, "BEQ taken");
        
        expect_wb(5'd24, 32'h0000_0088, "JAL -> PC+4");         expect_wb(5'd26, 32'h0000_001A, "JAL target");
        
        expect_wb(5'd27, 32'h0000_00C4, "ADDI x27,0xC4");       expect_wb(5'd28, 32'h0000_00A8, "JALR -> PC+4");
        
        expect_wb(5'd29, 32'h0000_001D, "JALR target");

        // 3. Kiem tra dong bang duong ong (bus_stall) mo rong
        repeat(5) @(posedge clk); #1; 
        bus_stall = 1'b1; #1; 
        pc_before_stall = PC_debug;
        instr_before_stall = Instr_debug;
        
        repeat(4) @(posedge clk); #1;
        check_equal32(PC_debug, pc_before_stall, "bus_stall -> PC frozen");
        check_equal32(Instr_debug, instr_before_stall, "bus_stall -> Instr frozen");
        
        bus_stall = 1'b0; repeat(3) @(posedge clk); #1;

        // ============================================================
        // 4. KIEM TRA FORWARDING
        // ============================================================
        force dut.u_EX_Stage.RD1_EX       = 32'h1111_1111;
        force dut.u_EX_Stage.RD2_EX       = 32'h2222_2222;
        force dut.u_EX_Stage.ALUResult_MEM = 32'hAAAA_AAAA;
        force dut.u_EX_Stage.Result_WB    = 32'hBBBB_BBBB;
        
        // ALUSrc = 0 -> ALU_Mux chon SrcB_EX thay vi ImmExt_EX
        force dut.u_EX_Stage.ALUSrc_EX = 1'b0;

        // ---------------- Forward = 00 ----------------
        ForwardA_EX = 2'b00;
        force dut.u_EX_Stage.ForwardB_EX = 2'b00; #1;
        check_equal32(dut.u_EX_Stage.SrcA_EX, 32'h1111_1111, "FwdA=00 -> RD1");
        check_equal32(dut.u_EX_Stage.SrcB_EX, 32'h2222_2222, "FwdB=00 -> RD2");

        // ---------------- Forward = 10 ----------------
        ForwardA_EX = 2'b10;
        force dut.u_EX_Stage.ForwardB_EX = 2'b10; #1;
        check_equal32(dut.u_EX_Stage.SrcA_EX, 32'hAAAA_AAAA, "FwdA=10 -> MEM");
        check_equal32(dut.u_EX_Stage.SrcB_EX, 32'hAAAA_AAAA, "FwdB=10 -> MEM");

        // ---------------- Forward = 01 ----------------
        ForwardA_EX = 2'b01;
        force dut.u_EX_Stage.ForwardB_EX = 2'b01; #1;
        check_equal32(dut.u_EX_Stage.SrcA_EX, 32'hBBBB_BBBB, "FwdA=01 -> WB");
        check_equal32(dut.u_EX_Stage.SrcB_EX, 32'hBBBB_BBBB, "FwdB=01 -> WB");

        // ---------------- Release ----------------
        release dut.u_EX_Stage.RD1_EX;
        release dut.u_EX_Stage.RD2_EX;
        release dut.u_EX_Stage.ALUResult_MEM;
        release dut.u_EX_Stage.Result_WB;
        release dut.u_EX_Stage.ForwardB_EX;
        release dut.u_EX_Stage.ALUSrc_EX;
        
        ForwardA_EX = 2'b00; ForwardB_EX = 2'b00;

        // ============================================================
        // 5. TEST ALUSrc = 1 (Xac nhan ALU_Mux chon Immediate thay vi ForwardB)
        // ============================================================
        force dut.u_EX_Stage.RD2_EX        = 32'h2222_2222;
        force dut.u_EX_Stage.ALUResult_MEM = 32'hAAAA_AAAA;
        force dut.u_EX_Stage.Result_WB     = 32'hBBBB_BBBB;
        force dut.u_EX_Stage.ForwardB_EX   = 2'b10;
        force dut.u_EX_Stage.ImmExt_EX     = 32'h0000_1234;
        
        // ALUSrc = 1 -> SrcB_EX phai lay ImmExt
        force dut.u_EX_Stage.ALUSrc_EX = 1'b1; #1;
        check_equal32(dut.u_EX_Stage.SrcB_EX, 32'h0000_1234, "ALUSrc=1 -> Immediate");
        
        release dut.u_EX_Stage.RD2_EX;
        release dut.u_EX_Stage.ALUResult_MEM;
        release dut.u_EX_Stage.Result_WB;
        release dut.u_EX_Stage.ForwardB_EX;
        release dut.u_EX_Stage.ImmExt_EX;
        release dut.u_EX_Stage.ALUSrc_EX;

        // ============================================================
        // 6. TEST RESET GIUA CHUNG
        // ============================================================
        repeat(3) @(posedge clk);
        rst = 1'b1; #1;
        check_equal32(PC_debug, 32'h0000_0000, "Mid-run reset -> PC = 0");
        check_equal1(RegWrite_WB_debug, 1'b0, "Mid-run reset -> no WB write");
        @(posedge clk); #1; rst = 1'b0;

        // ============================================================
        // 7. KIEM TRA NGO RA DEBUG
        // ============================================================
        check_equal32(instr_addr, PC_debug, "instr_addr mirrors PC_debug");
        check_equal32(Instr_debug, imem_word, "Instr_debug matches instruction");

        $display("\n=== SUMMARY ===\n PASS = %0d \n FAIL = %0d", pass_count, fail_count);
        $display("OVERALL: %s", (fail_count == 0) ? "PASS" : "FAIL");
        $finish;
    end

    // --- Giam sat dang song (Waveform Monitor) ---
    always @(posedge clk) begin
        if (!rst) $display("[%0t] PC=%h Instr=%h Stall=%b Flush=%b | WB=%b Rd=%0d Result=%h", $time, PC_debug, Instr_debug, bus_stall, dut.PCSrc_EX, RegWrite_WB_debug, Rd_WB_debug, Result_WB_debug);
    end

endmodule