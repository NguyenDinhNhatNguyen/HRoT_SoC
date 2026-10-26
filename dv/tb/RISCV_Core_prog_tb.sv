`timescale 1ns/1ps

// RISCV_Core_prog_tb: runs the self-checking programs in dv/tests/asm/
//   core_isa_test.hex  (RV32I) and core_trap_test.hex (Zicsr, traps, interrupts, P-09)
//  - Instruction ROM (2 KB) and data RAM (1 KB) read combinationally (meets the RISCV_Core timing contract)
//  - RAM writes per byte lane (data_wstrb)
//  - irq_timer / irq_ext follow bit0 / bit1 of the RAM word at IRQ (0x3F8), so the program raises
//    and clears its own interrupt lines (level, synchronous to clk, as in I-01)
//  - Every finished access (load or store, bus not stalled) to ACC (0x3F4) bumps a counter that the
//    program reads back at ACC_CNT (0x3F0), like a register with a side effect: an access that is
//    cancelled and repeated, or that runs when it should have been cancelled, shows up in the count
//  - Each program runs twice: without stall, and with random bus_stall (the pipeline must freeze correctly)
//  - Result read from TOHOST (0x3FC): 1 = PASS, (n<<1)|1 = FAIL at CHECK number n
// Plusarg: +HEX=<path to .hex> runs only that program (default paths are relative to sim/)
module RISCV_Core_prog_tb;

    localparam TOHOST    = 32'h3FC;
    localparam IRQ       = 32'h3F8;
    localparam ACC       = 32'h3F4;
    localparam ACC_CNT   = 32'h3F0;
    localparam MAX_CYCLE = 5000;

    reg clk = 1'b0, rst = 1'b1, bus_stall = 1'b0;
    always #5 clk = ~clk;

    wire [31:0] instr_addr, data_addr, data_wdata;
    wire [3:0]  data_wstrb;
    wire        data_we, data_re;

    reg  [31:0] imem [0:511];
    reg  [31:0] dmem [0:255];

    wire [31:0] instr_rdata = imem[instr_addr[10:2]];
    wire        irq_timer   = dmem[IRQ[9:2]][0];
    wire        irq_ext     = dmem[IRQ[9:2]][1];
    wire [31:0] data_rdata  = dmem[data_addr[9:2]];

    always @(posedge clk) begin
        if ((data_we || data_re) && !bus_stall && data_addr == ACC)
            dmem[ACC_CNT[9:2]] <= dmem[ACC_CNT[9:2]] + 32'd1;
        if (data_we) begin
            if (data_wstrb[0])
                dmem[data_addr[9:2]][7:0]   <= data_wdata[7:0];
            if (data_wstrb[1])
                dmem[data_addr[9:2]][15:8]  <= data_wdata[15:8];
            if (data_wstrb[2])
                dmem[data_addr[9:2]][23:16] <= data_wdata[23:16];
            if (data_wstrb[3])
                dmem[data_addr[9:2]][31:24] <= data_wdata[31:24];
        end
    end

    RISCV_Core dut (
        .clk(clk), .rst(rst), .bus_stall(bus_stall),
        .irq_timer(irq_timer), .irq_ext(irq_ext),
        .instr_rdata(instr_rdata), .instr_addr(instr_addr),
        .data_rdata(data_rdata), .data_addr(data_addr), .data_wdata(data_wdata),
        .data_wstrb(data_wstrb), .data_we(data_we), .data_re(data_re),
        .PC_debug(), .Instr_debug(), .RegWrite_WB_debug(), .Rd_WB_debug(), .Result_WB_debug()
    );

    reg [1023:0] hex_file;
    integer      i, fail_count = 0, stall_mode = 0;

    // Random bus_stall on ~30% of cycles (second run only)
    always @(negedge clk)
        bus_stall <= (stall_mode != 0) && !rst && (($urandom % 10) < 3);

    task automatic run_program(input [255:0] name);
        integer cycles;
        begin
            for (i = 0; i < 512; i = i + 1)
                imem[i] = 32'h00000013;
            for (i = 0; i < 256; i = i + 1)
                dmem[i] = 32'h0;
            $readmemh(hex_file, imem);
            rst = 1'b1;
            repeat (3) @(posedge clk);
            #1 rst = 1'b0;

            cycles = 0;
            while (dmem[TOHOST[9:2]] == 32'h0 && cycles < MAX_CYCLE) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            #1;

            if (dmem[TOHOST[9:2]] == 32'h1)
                $display("[PASS] %0s (%0d cycles)", name, cycles);
            else begin
                fail_count = fail_count + 1;
                if (dmem[TOHOST[9:2]] == 32'h0)
                    $display("[FAIL] %0s: timeout after %0d cycles, PC=%h", name, cycles, instr_addr);
                else
                    $display("[FAIL] %0s: failed at CHECK #%0d", name, dmem[TOHOST[9:2]] >> 1);
                for (i = 1; i < 32; i = i + 1)
                    $display("       x%0d = %h", i, dut.u_ID_Stage.u_Register_File.REG_MEM_BLOCK[i]);
            end
        end
    endtask

    task automatic run_both(input [1023:0] file);
        begin
            hex_file = file;
            $display("\n=== RISCV_Core program test: %0s ===", hex_file);
            stall_mode = 0;
            run_program("No stall");
            stall_mode = 1;
            run_program("Random bus_stall");
        end
    endtask

    initial begin
        if ($value$plusargs("HEX=%s", hex_file))
            run_both(hex_file);
        else begin
            run_both("../dv/tests/asm/core_isa_test.hex");
            run_both("../dv/tests/asm/core_trap_test.hex");
        end

        $display("\n=== SUMMARY: %0s ===", (fail_count == 0) ? "PASS" : "FAIL");
        $finish;
    end

endmodule
