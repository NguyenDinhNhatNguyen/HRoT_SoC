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
//  - Fault window (P-24): an access to 0xF000_0000 and up gets data_err in the cycle it completes, like a
//    SLVERR/DECERR on the SoC bus. A store there writes nothing
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
    wire        fault_win   = data_addr[31:28] == 4'hF;
    wire        data_err    = (data_we || data_re) && !bus_stall && fault_win;

    always @(posedge clk) begin
        if ((data_we || data_re) && !bus_stall && data_addr == ACC)
            dmem[ACC_CNT[9:2]] <= dmem[ACC_CNT[9:2]] + 32'd1;
        if (data_we && !fault_win) begin
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
        .clk(clk), .rst(rst), .bus_stall(bus_stall), .data_err(data_err),
        .irq_timer(irq_timer), .irq_ext(irq_ext),
        .instr_rdata(instr_rdata), .instr_addr(instr_addr),
        .data_rdata(data_rdata), .data_addr(data_addr), .data_wdata(data_wdata),
        .data_wstrb(data_wstrb), .data_we(data_we), .data_re(data_re),
        .PC_debug(), .Instr_debug(), .RegWrite_WB_debug(), .Rd_WB_debug(), .Result_WB_debug()
    );

    reg [1023:0] hex_file;
    integer      i, fail_count = 0, stall_mode = 0;

`ifdef HROT_COV
    // Functional coverage of the core (P-19, sim/cov.sh), only with +define+HROT_COV:
    //   cg_instr: every instruction the core executes, read from imem at PC_MEM when it leaves MEM (an
    //             instruction cut by an interrupt does not count). Key = {instr[30], funct3, opcode}, and
    //             {instr[31:20], funct3, opcode} for the system instructions. Loads and stores x stall mode
    //   cg_trap:  each trap cause and MRET, with and without random bus_stall
    //   cg_pipe:  forwarding paths, load-use stall, taken branch or jump, trap redirect, stalled access
    wire        leave_mem = !rst && dut.valid_MEM && !bus_stall && !dut.u_CSR_Unit.take_irq;
    wire [31:0] mem_instr = imem[dut.PC_MEM[10:2]];
    wire [10:0] key       = {mem_instr[30], mem_instr[14:12], mem_instr[6:0]};
    wire [21:0] sys_key   = {mem_instr[31:20], mem_instr[14:12], mem_instr[6:0]};

    covergroup cg_instr @(posedge clk iff leave_mem);
        cp_rv32i: coverpoint key {
            wildcard bins lui   = {11'b?_???_0110111};
            wildcard bins auipc = {11'b?_???_0010111};
            wildcard bins jal   = {11'b?_???_1101111};
            wildcard bins jalr  = {11'b?_000_1100111};
            wildcard bins beq   = {11'b?_000_1100011};
            wildcard bins bne   = {11'b?_001_1100011};
            wildcard bins blt   = {11'b?_100_1100011};
            wildcard bins bge   = {11'b?_101_1100011};
            wildcard bins bltu  = {11'b?_110_1100011};
            wildcard bins bgeu  = {11'b?_111_1100011};
            wildcard bins lb    = {11'b?_000_0000011};
            wildcard bins lh    = {11'b?_001_0000011};
            wildcard bins lw    = {11'b?_010_0000011};
            wildcard bins lbu   = {11'b?_100_0000011};
            wildcard bins lhu   = {11'b?_101_0000011};
            wildcard bins sb    = {11'b?_000_0100011};
            wildcard bins sh    = {11'b?_001_0100011};
            wildcard bins sw    = {11'b?_010_0100011};
            wildcard bins addi  = {11'b?_000_0010011};
            wildcard bins slti  = {11'b?_010_0010011};
            wildcard bins sltiu = {11'b?_011_0010011};
            wildcard bins xori  = {11'b?_100_0010011};
            wildcard bins ori   = {11'b?_110_0010011};
            wildcard bins andi  = {11'b?_111_0010011};
            wildcard bins slli  = {11'b0_001_0010011};
            wildcard bins srli  = {11'b0_101_0010011};
            wildcard bins srai  = {11'b1_101_0010011};
            wildcard bins add   = {11'b0_000_0110011};
            wildcard bins sub   = {11'b1_000_0110011};
            wildcard bins sll   = {11'b0_001_0110011};
            wildcard bins slt   = {11'b0_010_0110011};
            wildcard bins sltu  = {11'b0_011_0110011};
            wildcard bins xor_  = {11'b0_100_0110011};
            wildcard bins srl   = {11'b0_101_0110011};
            wildcard bins sra   = {11'b1_101_0110011};
            wildcard bins or_   = {11'b0_110_0110011};
            wildcard bins and_  = {11'b0_111_0110011};
            wildcard bins fence   = {11'b?_000_0001111};
            wildcard bins fence_i = {11'b?_001_0001111};
        }
        cp_sys: coverpoint sys_key {
            bins ecall  = {22'h000073};     // {imm12, funct3 0, opcode 0x73}
            bins ebreak = {22'h000473};
            bins mret   = {22'h0C0873};
            bins wfi    = {22'h041473};
            wildcard bins csrrw  = {22'b????????????_001_1110011};
            wildcard bins csrrs  = {22'b????????????_010_1110011};
            wildcard bins csrrc  = {22'b????????????_011_1110011};
            wildcard bins csrrwi = {22'b????????????_101_1110011};
            wildcard bins csrrsi = {22'b????????????_110_1110011};
            wildcard bins csrrci = {22'b????????????_111_1110011};
        }
        cp_mem: coverpoint key {
            wildcard bins load  = {11'b?_???_0000011};
            wildcard bins store = {11'b?_???_0100011};
        }
        cp_stall: coverpoint stall_mode {
            bins off = {0};
            bins on  = {1};
        }
        mem_x_stall: cross cp_mem, cp_stall;
    endgroup

    wire take_any = dut.u_CSR_Unit.take_irq || dut.u_CSR_Unit.take_exc || dut.u_CSR_Unit.take_mret;
    covergroup cg_trap @(posedge clk iff (!rst && take_any));
        cp_cause: coverpoint {dut.u_CSR_Unit.take_mret, dut.u_CSR_Unit.cause} {
            bins illegal = {33'h0_0000_0002};
            bins ebreak  = {33'h0_0000_0003};
            bins ld_flt  = {33'h0_0000_0005};
            bins st_flt  = {33'h0_0000_0007};
            bins ecall   = {33'h0_0000_000B};
            bins mti     = {33'h0_8000_0007};
            bins mei     = {33'h0_8000_000B};
            bins mret    = {[33'h1_0000_0000:33'h1_FFFF_FFFF]};
        }
        cp_stall: coverpoint stall_mode {
            bins off = {0};
            bins on  = {1};
        }
        cause_x_stall: cross cp_cause, cp_stall;
    endgroup

    covergroup cg_pipe @(posedge clk iff !rst);
        cp_fwd_a: coverpoint dut.ForwardA_EX_internal {
            bins none = {2'b00};
            bins wb   = {2'b01};
            bins mem  = {2'b10};
        }
        cp_fwd_b: coverpoint dut.ForwardB_EX_internal {
            bins none = {2'b00};
            bins wb   = {2'b01};
            bins mem  = {2'b10};
        }
        cp_load_use:  coverpoint dut.LoadUseStall  { bins hit = {1'b1}; }
        cp_taken:     coverpoint dut.PCSrc_EX      { bins hit = {1'b1}; }
        cp_trap_rd:   coverpoint dut.trap_redirect { bins hit = {1'b1}; }
        cp_mem_stall: coverpoint (bus_stall && (data_we || data_re)) { bins hit = {1'b1}; }
        load_use_x_stall: cross cp_load_use, cp_mem_stall;
    endgroup

    cg_instr c_instr = new();
    cg_trap  c_trap  = new();
    cg_pipe  c_pipe  = new();
`endif

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
