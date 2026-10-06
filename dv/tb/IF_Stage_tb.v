`timescale 1ns / 1ps

module IF_Stage_tb;

    // Tin hieu dieu khien DUT
    reg         clk;
    reg         rst;
    reg         stall_IF;
    reg         flush_IF;
    reg  [31:0] PCFlushTarget_EX;

    // Ngo ra quan sat tu DUT
    wire [31:0] PC_IF;
    wire [31:0] Instr_IF;
    wire [31:0] PC_Plus_4_IF;

    // Khoi tao DUT (Device Under Test)
    IF_Stage dut (
        .clk               (clk),
        .rst               (rst),
        .stall_IF          (stall_IF),
        .flush_IF          (flush_IF),
        .PCFlushTarget_EX  (PCFlushTarget_EX),
        .PC_IF             (PC_IF),
        .Instr_IF          (Instr_IF),
        .PC_Plus_4_IF      (PC_Plus_4_IF)
    );

    // Tao Clock chu ky 10ns (100MHz)
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Task kiem tra ket qua ngo ra gon nhe, dung %0s tranh khoang trang thua
    task check_output;
        input [31:0] exp_PC;
        input [31:0] exp_PC4;
        input [1023:0] test_name;
        begin
            #1; // Cho on dinh sau suon len xung clock
            if ((PC_IF === exp_PC) && (PC_Plus_4_IF === exp_PC4)) begin
                $display("[PASS] %0s | PC_IF = 32'h%h | Instr_IF = 32'h%h", test_name, PC_IF, Instr_IF);
            end else begin
                $display("[FAIL] %0s", test_name);
                $display("  Expected: PC = %h | PC+4 = %h", exp_PC, exp_PC4);
                $display("  Actual  : PC = %h | PC+4 = %h", PC_IF, PC_Plus_4_IF);
            end
        end
    endtask

    // Task kiem tra PC, PC+4 và Instruction
    task check_output_with_instr;
        input [31:0] exp_PC;
        input [31:0] exp_PC4;
        input [31:0] exp_Instr;
        input [1023:0] test_name;
        begin
            #1; // Cho on dinh sau suon len xung clock
            if ((PC_IF === exp_PC) &&
                (PC_Plus_4_IF === exp_PC4) &&
                (Instr_IF === exp_Instr)) begin

                $display("[PASS] %0s | PC_IF = 32'h%h | PC+4 = 32'h%h | Instr_IF = 32'h%h",
                         test_name, PC_IF, PC_Plus_4_IF, Instr_IF);

            end else begin
                $display("[FAIL] %0s", test_name);
                $display("  Expected: PC = %h | PC+4 = %h | Instr = %h",
                         exp_PC, exp_PC4, exp_Instr);
                $display("  Actual  : PC = %h | PC+4 = %h | Instr = %h",
                         PC_IF, PC_Plus_4_IF, Instr_IF);
            end
        end
    endtask

    // Main Test Sequence
    initial begin
        // Nap thu du lieu mau vao ROM mo phong
        dut.u_Instruction_Memory.rom[0]  = 32'h00100093; // addi x1, x0, 1 (PC = 0x00)
        dut.u_Instruction_Memory.rom[1]  = 32'h00200113; // addi x2, x0, 2 (PC = 0x04)
        dut.u_Instruction_Memory.rom[2]  = 32'h00300193; // addi x3, x0, 3 (PC = 0x08)
        dut.u_Instruction_Memory.rom[3]  = 32'h00400213; // addi x4, x0, 4 (PC = 0x0C)
        dut.u_Instruction_Memory.rom[10] = 32'h00A00513; // addi x10, x0, 10 (PC = 0x28)

        // Tin hieu ban dau
        rst              = 1'b0;
        stall_IF         = 1'b0;
        flush_IF         = 1'b0;
        PCFlushTarget_EX = 32'h00000000;

        $display("\n==================================================");
        $display("          BAT DAU TESTBENCH TANG IF              ");
        $display("==================================================");

        // TEST 1: RESET
        rst = 1'b1;
        @(posedge clk);
        check_output_with_instr(
            32'h00000000,
            32'h00000004,
            32'h00100093,
            "1. Reset -> PC ve 0x0"
        );
        rst = 1'b0;

        // TEST 2: NORMAL OPERATION (PC tu tang +4)
        @(posedge clk);
        check_output_with_instr(
            32'h00000004,
            32'h00000008,
            32'h00200113,
            "2. Normal -> PC nhay 0x4"
        );

        @(posedge clk);
        check_output_with_instr(
            32'h00000008,
            32'h0000000C,
            32'h00300193,
            "3. Normal -> PC nhay 0x8"
        );

        // TEST 3: STALL (PC giu nguyen)
        stall_IF = 1'b1;
        @(posedge clk);
        check_output_with_instr(
            32'h00000008,
            32'h0000000C,
            32'h00300193,
            "4. Stall -> Giu nguyen PC = 0x8"
        );

        // TEST 4: STALL NHIEU CYCLE (PC tiep tuc giu nguyen)
        @(posedge clk);
        check_output_with_instr(
            32'h00000008,
            32'h0000000C,
            32'h00300193,
            "5. Stall 2 cycles -> PC van giu 0x8"
        );

        @(posedge clk);
        check_output_with_instr(
            32'h00000008,
            32'h0000000C,
            32'h00300193,
            "6. Stall 3 cycles -> PC van giu 0x8"
        );

        // TEST 5: KHOI PHUC BINH THUONG SAU STALL
        stall_IF = 1'b0;
        @(posedge clk);
        check_output_with_instr(
            32'h0000000C,
            32'h00000010,
            32'h00400213,
            "7. Resume -> PC tiep tuc 0xC"
        );

        // TEST 6: FLUSH (Ep nhay toi dia chi re nhanh)
        flush_IF = 1'b1;
        PCFlushTarget_EX = 32'h00000028; // Nhay den PC = 0x28
        @(posedge clk);
        check_output_with_instr(
            32'h00000028,
            32'h0000002C,
            32'h00A00513,
            "8. Flush -> Ep PC sang 0x28"
        );

        // TEST 7: FLUSH + STALL (Kiem tra uu tien Flush > Stall)
        flush_IF = 1'b1;
        stall_IF = 1'b1;
        PCFlushTarget_EX = 32'h00000004; // Ep ve PC = 0x04
        @(posedge clk);
        check_output_with_instr(
            32'h00000004,
            32'h00000008,
            32'h00200113,
            "9. Flush + Stall -> Uu tien Flush ve 0x4"
        );

        // KHOI PHUC BINH THUONG
        flush_IF = 1'b0;
        stall_IF = 1'b0;
        @(posedge clk);
        check_output_with_instr(
            32'h00000008,
            32'h0000000C,
            32'h00300193,
            "10. Final Normal -> Chay binh thuong tu 0x8"
        );

        $display("==================================================");
        $display("          KET THUC TESTBENCH TANG IF             ");
        $display("==================================================\n");

        #10 $finish;
    end

endmodule