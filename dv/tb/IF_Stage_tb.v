`timescale 1ns / 1ps

module IF_Stage_tb;

    // DUT control signals
    reg         clk;
    reg         rst;
    reg         stall_IF;
    reg         flush_IF;
    reg  [31:0] PCFlushTarget_EX;

    // DUT outputs
    wire [31:0] PC_IF;
    wire [31:0] Instr_IF;
    wire [31:0] PC_Plus_4_IF;

    // Model ROM (combinational read), the instruction memory sits outside IF_Stage
    reg  [31:0] rom [0:63];
    wire [31:0] instr_addr;
    wire [31:0] instr_rdata = rom[instr_addr[7:2]];
    integer     k;
    integer     pass_count = 0, fail_count = 0;

    // DUT
    IF_Stage dut (
        .clk               (clk),
        .rst               (rst),
        .stall_IF          (stall_IF),
        .flush_IF          (flush_IF),
        .PCFlushTarget_EX  (PCFlushTarget_EX),
        .instr_rdata       (instr_rdata),
        .instr_addr        (instr_addr),
        .PC_IF_out         (PC_IF),
        .Instr_IF_out      (Instr_IF),
        .PC_Plus_4_IF_out  (PC_Plus_4_IF)
    );

    // 10 ns clock (100 MHz)
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Check PC, PC+4 and the instruction
    task check_output_with_instr;
        input [31:0] exp_PC;
        input [31:0] exp_PC4;
        input [31:0] exp_Instr;
        input [1023:0] test_name;
        begin
            #1; // Let the outputs settle after the rising edge
            if ((PC_IF === exp_PC) &&
                (PC_Plus_4_IF === exp_PC4) &&
                (Instr_IF === exp_Instr)) begin

                pass_count = pass_count + 1;
                $display("[PASS] %0s | PC_IF = 32'h%h | PC+4 = 32'h%h | Instr_IF = 32'h%h",
                         test_name, PC_IF, PC_Plus_4_IF, Instr_IF);

            end else begin
                fail_count = fail_count + 1;
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
        // Load sample instructions into the model ROM
        for (k = 0; k < 64; k = k + 1)
            rom[k] = 32'h00000013;
        rom[0]  = 32'h00100093; // addi x1, x0, 1 (PC = 0x00)
        rom[1]  = 32'h00200113; // addi x2, x0, 2 (PC = 0x04)
        rom[2]  = 32'h00300193; // addi x3, x0, 3 (PC = 0x08)
        rom[3]  = 32'h00400213; // addi x4, x0, 4 (PC = 0x0C)
        rom[10] = 32'h00A00513; // addi x10, x0, 10 (PC = 0x28)

        // Initial values
        rst              = 1'b0;
        stall_IF         = 1'b0;
        flush_IF         = 1'b0;
        PCFlushTarget_EX = 32'h00000000;

        $display("\n==================================================");
        $display("              IF STAGE TESTBENCH                  ");
        $display("==================================================");

        // TEST 1: RESET
        rst = 1'b1;
        @(posedge clk);
        check_output_with_instr(
            32'h00000000,
            32'h00000004,
            32'h00100093,
            "1. Reset -> PC = 0x0"
        );
        rst = 1'b0;

        // TEST 2: NORMAL OPERATION (PC increments by 4)
        @(posedge clk);
        check_output_with_instr(
            32'h00000004,
            32'h00000008,
            32'h00200113,
            "2. Normal -> PC = 0x4"
        );

        @(posedge clk);
        check_output_with_instr(
            32'h00000008,
            32'h0000000C,
            32'h00300193,
            "3. Normal -> PC = 0x8"
        );

        // TEST 3: STALL (PC holds)
        stall_IF = 1'b1;
        @(posedge clk);
        check_output_with_instr(
            32'h00000008,
            32'h0000000C,
            32'h00300193,
            "4. Stall -> PC holds 0x8"
        );

        // TEST 4: MULTI-CYCLE STALL (PC keeps holding)
        @(posedge clk);
        check_output_with_instr(
            32'h00000008,
            32'h0000000C,
            32'h00300193,
            "5. Stall 2 cycles -> PC holds 0x8"
        );

        @(posedge clk);
        check_output_with_instr(
            32'h00000008,
            32'h0000000C,
            32'h00300193,
            "6. Stall 3 cycles -> PC holds 0x8"
        );

        // TEST 5: RESUME AFTER STALL
        stall_IF = 1'b0;
        @(posedge clk);
        check_output_with_instr(
            32'h0000000C,
            32'h00000010,
            32'h00400213,
            "7. Resume -> PC = 0xC"
        );

        // TEST 6: FLUSH (redirect to the branch target)
        flush_IF = 1'b1;
        PCFlushTarget_EX = 32'h00000028; // Jump to PC = 0x28
        @(posedge clk);
        check_output_with_instr(
            32'h00000028,
            32'h0000002C,
            32'h00A00513,
            "8. Flush -> PC = 0x28"
        );

        // TEST 7: FLUSH + STALL (flush has priority over stall)
        flush_IF = 1'b1;
        stall_IF = 1'b1;
        PCFlushTarget_EX = 32'h00000004; // Redirect to PC = 0x04
        @(posedge clk);
        check_output_with_instr(
            32'h00000004,
            32'h00000008,
            32'h00200113,
            "9. Flush + Stall -> Flush wins, PC = 0x4"
        );

        // BACK TO NORMAL
        flush_IF = 1'b0;
        stall_IF = 1'b0;
        @(posedge clk);
        check_output_with_instr(
            32'h00000008,
            32'h0000000C,
            32'h00300193,
            "10. Final Normal -> Continues from 0x8"
        );

        $display("\nSUMMARY IF_STAGE: PASS = %0d | FAIL = %0d", pass_count, fail_count);

        #10 $finish;
    end

endmodule
