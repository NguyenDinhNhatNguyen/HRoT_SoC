`timescale 1ns / 1ps

module IF_ID_Reg_tb;

    // Khai bao tin hieu
    reg         clk, rst, stall, flush;
    reg  [31:0] PC_IF, Instr_IF, PC_Plus_4_IF;
    wire [31:0] PC_ID, Instr_ID, PC_Plus_4_ID;

    // Lenh NOP (ADDI x0, x0, 0)
    localparam [31:0] NOP = 32'h00000013;

    // Khoi tao DUT
    IF_ID_Reg dut (
        .clk(clk), .rst(rst), .stall(stall), .flush(flush),
        .PC_IF(PC_IF), .Instr_IF(Instr_IF), .PC_Plus_4_IF(PC_Plus_4_IF),
        .PC_ID(PC_ID), .Instr_ID(Instr_ID), .PC_Plus_4_ID(PC_Plus_4_ID)
    );

    // Tao Clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Task kiem tra ket qua
    task check_output;
        input [31:0] exp_PC, exp_Instr, exp_PC_Plus_4;
        input [1023:0] test_name;
        begin
            #1; // Loi tin hieu on dinh sau suon clock
            if ((PC_ID === exp_PC) && (Instr_ID === exp_Instr) && (PC_Plus_4_ID === exp_PC_Plus_4)) begin
                $display("[PASS] %0s", test_name); // Thay %s bang %0s
            end else begin
                $display("[FAIL] %0s", test_name); // Thay %s bang %0s
                $display("       Expected: PC=%h | Instr=%h | PC+4=%h", exp_PC, exp_Instr, exp_PC_Plus_4);
                $display("       Actual  : PC=%h | Instr=%h | PC+4=%h", PC_ID, Instr_ID, PC_Plus_4_ID);
            end
        end
    endtask

    // Main Test Sequence
    initial begin
        // Khoi tao gia tri
        rst = 0; stall = 0; flush = 0;
        PC_IF = 32'h0; Instr_IF = NOP; PC_Plus_4_IF = 32'h4;
        
        $display("\n--- BAT DAU TESTBENCH IF_ID_Reg ---");

        // TEST 1: RESET
        rst = 1; @(posedge clk);
        check_output(32'h0, NOP, 32'h0, "1. Reset -> NOP");
        rst = 0;

        // TEST 2: NORMAL OPERATION
        PC_IF = 32'h10; Instr_IF = 32'h00100093; PC_Plus_4_IF = 32'h14; 
        @(posedge clk);
        check_output(32'h10, 32'h00100093, 32'h14, "2. Normal -> Data transferred");

        // TEST 3: STALL
        PC_IF = 32'h20; Instr_IF = 32'h00200113; PC_Plus_4_IF = 32'h24; stall = 1;
        @(posedge clk);
        check_output(32'h10, 32'h00100093, 32'h14, "3. Stall -> Hold previous data");

        // TEST 4: CONTINUE AFTER STALL
        stall = 0;
        @(posedge clk);
        check_output(32'h20, 32'h00200113, 32'h24, "4. After Stall -> New data transferred");

        // TEST 5: FLUSH
        PC_IF = 32'h30; Instr_IF = 32'h00300193; PC_Plus_4_IF = 32'h34; flush = 1;
        @(posedge clk);
        check_output(32'h0, NOP, 32'h0, "5. Flush -> Insert NOP");

        // TEST 6: CONTINUE AFTER FLUSH
        flush = 0; PC_IF = 32'h40; Instr_IF = 32'h00400213; PC_Plus_4_IF = 32'h44;
        @(posedge clk);
        check_output(32'h40, 32'h00400213, 32'h44, "6. After Flush -> New data transferred");

        // TEST 7: FLUSH + STALL (Priority check)
        PC_IF = 32'h50; Instr_IF = 32'h00500293; PC_Plus_4_IF = 32'h54; stall = 1; flush = 1;
        @(posedge clk);
        check_output(32'h0, NOP, 32'h0, "7. Flush + Stall -> Flush has priority");

        // TEST 8: STALL AFTER FLUSH
        PC_IF = 32'h60; Instr_IF = 32'h00600313; PC_Plus_4_IF = 32'h64; flush = 0; stall = 1;
        @(posedge clk);
        check_output(32'h0, NOP, 32'h0, "8. Stall after Flush -> Hold NOP");

        // TEST 9: FINAL NORMAL OPERATION
        stall = 0; PC_IF = 32'h70; Instr_IF = 32'h00700393; PC_Plus_4_IF = 32'h74;
        @(posedge clk);
        check_output(32'h70, 32'h00700393, 32'h74, "9. Final Normal -> Data transferred");

        $display("--- KET THUC TESTBENCH ---\n");
        #10 $finish;
    end

endmodule