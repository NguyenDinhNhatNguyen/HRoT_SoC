`timescale 1ns / 1ps

module Control_Unit_tb;

    // ============================================================
    // Inputs
    // ============================================================
    reg [6:0] op;
    reg [2:0] funct3;
    reg       funct7b5;

    // ============================================================
    // Outputs
    // ============================================================
    wire [1:0] ResultSrc;
    wire       MemWrite;
    wire       MemRead;
    wire       Branch;
    wire       ALUSrc;
    wire       RegWrite;
    wire       Jump;
    wire [1:0] ImmSrc;
    wire [3:0] ALUControl;
    wire       Jalr;

    // ============================================================
    // Instantiate Control Unit
    // ============================================================
    Control_Unit u_CU (
        .op         (op),
        .funct3     (funct3),
        .funct7b5   (funct7b5),
        .ResultSrc  (ResultSrc),
        .MemWrite   (MemWrite),
        .MemRead    (MemRead),
        .Branch     (Branch),
        .ALUSrc     (ALUSrc),
        .RegWrite   (RegWrite),
        .Jump       (Jump),
        .ImmSrc     (ImmSrc),
        .ALUControl (ALUControl),
        .Jalr       (Jalr)
    );

    // ============================================================
    // Test counters
    // ============================================================
    integer test_count;
    integer pass_count;
    integer fail_count;

    // ============================================================
    // Check task
    // ============================================================
    task check_control;
        input [8*20:1] instr_name;
        input [1:0] exp_ResultSrc;
        input       exp_MemWrite;
        input       exp_MemRead;
        input       exp_Branch;
        input       exp_ALUSrc;
        input       exp_RegWrite;
        input       exp_Jump;
        input [1:0] exp_ImmSrc;
        input [3:0] exp_ALUControl;
        input       exp_Jalr;
        begin
            #1;

            test_count = test_count + 1;

            if ((ResultSrc  === exp_ResultSrc)  &&
                (MemWrite   === exp_MemWrite)   &&
                (MemRead    === exp_MemRead)    &&
                (Branch     === exp_Branch)     &&
                (ALUSrc     === exp_ALUSrc)     &&
                (RegWrite   === exp_RegWrite)   &&
                (Jump       === exp_Jump)       &&
                (ImmSrc     === exp_ImmSrc)     &&
                (ALUControl === exp_ALUControl) &&
                (Jalr       === exp_Jalr)) begin

                pass_count = pass_count + 1;
                $display("PASS | %-20s | RS=%b MW=%b MR=%b BR=%b AS=%b RW=%b JP=%b Imm=%b ALU=%b JALR=%b",
                    instr_name, ResultSrc, MemWrite, MemRead, Branch, ALUSrc, RegWrite, Jump, ImmSrc, ALUControl, Jalr);
            end
            else begin
                fail_count = fail_count + 1;
                $display("FAIL | %-20s | ACTUAL   RS=%b MW=%b MR=%b BR=%b AS=%b RW=%b JP=%b Imm=%b ALU=%b JALR=%b",
                    instr_name, ResultSrc, MemWrite, MemRead, Branch, ALUSrc, RegWrite, Jump, ImmSrc, ALUControl, Jalr);
                $display("     | %-20s | EXPECTED RS=%b MW=%b MR=%b BR=%b AS=%b RW=%b JP=%b Imm=%b ALU=%b JALR=%b",
                    "", exp_ResultSrc, exp_MemWrite, exp_MemRead, exp_Branch, exp_ALUSrc, exp_RegWrite, exp_Jump, exp_ImmSrc, exp_ALUControl, exp_Jalr);
            end
            #9; // Doi phan thoi gian con lai cua chu ky 10ns[cite: 1]
        end
    endtask

    // ============================================================
    // Test sequence
    // ============================================================
    initial begin
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        op       = 7'b0000000;
        funct3   = 3'b000;
        funct7b5 = 1'b0;

        $display("\n================================================================================================================");
        $display("                                  CONTROL UNIT TESTBENCH");
        $display("================================================================================================================");
        $display("Instr                | RS | MW | MR | BR | AS | RW | JP | Imm | ALU  | JALR");
        $display("----------------------------------------------------------------------------------------------------------------");

        // 1. R-TYPE
        op = 7'b0110011; funct3 = 3'b000; funct7b5 = 1'b0; check_control("R-Type ADD", 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 4'b0000, 1'b0);
        op = 7'b0110011; funct3 = 3'b000; funct7b5 = 1'b1; check_control("R-Type SUB", 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 4'b0001, 1'b0);
        op = 7'b0110011; funct3 = 3'b111; funct7b5 = 1'b0; check_control("R-Type AND", 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 4'b0010, 1'b0);
        op = 7'b0110011; funct3 = 3'b110; funct7b5 = 1'b0; check_control("R-Type OR", 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 4'b0011, 1'b0);
        op = 7'b0110011; funct3 = 3'b100; funct7b5 = 1'b0; check_control("R-Type XOR", 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 4'b0100, 1'b0);
        op = 7'b0110011; funct3 = 3'b010; funct7b5 = 1'b0; check_control("R-Type SLT", 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 4'b0101, 1'b0);
        op = 7'b0110011; funct3 = 3'b011; funct7b5 = 1'b0; check_control("R-Type SLTU", 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 4'b0110, 1'b0);
        op = 7'b0110011; funct3 = 3'b001; funct7b5 = 1'b0; check_control("R-Type SLL", 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 4'b1010, 1'b0);
        op = 7'b0110011; funct3 = 3'b101; funct7b5 = 1'b0; check_control("R-Type SRL", 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 4'b1100, 1'b0);
        op = 7'b0110011; funct3 = 3'b101; funct7b5 = 1'b1; check_control("R-Type SRA", 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 4'b1011, 1'b0);

        // 2. I-TYPE ALU (Da sua exp_Branch thanh 0)[cite: 1]
        op = 7'b0010011; funct3 = 3'b000; funct7b5 = 1'b0; check_control("I-Type ADDI", 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 2'b00, 4'b0000, 1'b0);
        op = 7'b0010011; funct3 = 3'b111; funct7b5 = 1'b0; check_control("I-Type ANDI", 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 2'b00, 4'b0010, 1'b0);
        op = 7'b0010011; funct3 = 3'b110; funct7b5 = 1'b0; check_control("I-Type ORI", 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 2'b00, 4'b0011, 1'b0);
        op = 7'b0010011; funct3 = 3'b100; funct7b5 = 1'b0; check_control("I-Type XORI", 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 2'b00, 4'b0100, 1'b0);
        op = 7'b0010011; funct3 = 3'b010; funct7b5 = 1'b0; check_control("I-Type SLTI", 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 2'b00, 4'b0101, 1'b0);
        op = 7'b0010011; funct3 = 3'b011; funct7b5 = 1'b0; check_control("I-Type SLTIU", 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 2'b00, 4'b0110, 1'b0);
        op = 7'b0010011; funct3 = 3'b001; funct7b5 = 1'b0; check_control("I-Type SLLI", 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 2'b00, 4'b1010, 1'b0);
        op = 7'b0010011; funct3 = 3'b101; funct7b5 = 1'b0; check_control("I-Type SRLI", 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 2'b00, 4'b1100, 1'b0);
        op = 7'b0010011; funct3 = 3'b101; funct7b5 = 1'b1; check_control("I-Type SRAI", 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 2'b00, 4'b1011, 1'b0);

        // 3. LOAD / STORE
        op = 7'b0000011; funct3 = 3'b010; funct7b5 = 1'b0; check_control("LW", 2'b01, 1'b0, 1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 2'b00, 4'b0000, 1'b0);
        op = 7'b0100011; funct3 = 3'b010; funct7b5 = 1'b0; check_control("SW", 2'b00, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 2'b01, 4'b0000, 1'b0);

        // 4. BRANCH (Da sua exp_Branch thanh 1)[cite: 1]
        op = 7'b1100011; funct3 = 3'b000; funct7b5 = 1'b0; check_control("BEQ", 2'b00, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 2'b10, 4'b0001, 1'b0);
        op = 7'b1100011; funct3 = 3'b001; funct7b5 = 1'b0; check_control("BNE", 2'b00, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 2'b10, 4'b0001, 1'b0);

        // 5. JUMP
        // JAL (Da sua exp_ALUSrc thanh 0)[cite: 1]
        op = 7'b1101111; funct3 = 3'b000; funct7b5 = 1'b0; check_control("JAL", 2'b10, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 2'b11, 4'b0000, 1'b0);
        // JALR (Da sua exp_Branch thanh 0)[cite: 1]
        op = 7'b1100111; funct3 = 3'b000; funct7b5 = 1'b0; check_control("JALR", 2'b10, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 2'b00, 4'b0000, 1'b1);

        // 6. U-TYPE
        // LUI (Da sua exp_Branch thanh 0)[cite: 1]
        op = 7'b0110111; funct3 = 3'b000; funct7b5 = 1'b0; check_control("LUI", 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 2'b00, 4'b1001, 1'b0);
        // AUIPC (Da sua exp_Branch thanh 0 va exp_ALUControl thanh 1000)[cite: 1]
        op = 7'b0010111; funct3 = 3'b000; funct7b5 = 1'b0; check_control("AUIPC", 2'b11, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 2'b00, 4'b0000, 1'b0);

        // 7. INVALID / DEFAULT
        op = 7'b1111111; funct3 = 3'b000; funct7b5 = 1'b0; check_control("INVALID", 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 4'b0000, 1'b0);

        $display("\n================================================================================================================");
        $display("                                      TEST SUMMARY");
        $display("================================================================================================================");
        $display("Total Tests : %0d", test_count);
        $display("Passed      : %0d", pass_count);
        $display("Failed      : %0d", fail_count);

        if (fail_count == 0) begin
            $display("\n************************************************************");
            $display("*                  ALL TESTS PASSED                        *");
            $display("*        CONTROL UNIT IS READY FOR INTEGRATION             *");
            $display("************************************************************\n");
        end
        $stop;
    end
endmodule