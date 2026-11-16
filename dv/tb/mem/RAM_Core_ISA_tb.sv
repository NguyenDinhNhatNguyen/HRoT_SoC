`timescale 1ns / 1ps
// RAM_Core_ISA_tb: the real RISCV_Core runs the self-checking program dv/tests/asm/core_isa_test.hex
// with its data RAM on the SRAM macro wrapper RAM_Macro_Core (and the home macro model). The wrapper
// stalls the core through bus_stall exactly as in the ASIC build. This closes the gap the SoC tests
// leave: no firmware of the App Core loads from its RAM, but this program does every load and store
// (LB, LBU, LH, LHU, LW, SB, SH, SW) and a stack.
//   run 1: only the stall of the wrapper
//   run 2: the wrapper stall plus random bus_stall and instr_stall from outside (the access is repeated
//          while the core waits, which must stay harmless)
// Run from sim/: vsim -c -do "set TB RAM_Core_ISA_tb; do run_ram.do". Ends with "RAM_Core_ISA_tb RESULT: PASS|FAIL".
module RAM_Core_ISA_tb;
    localparam TOHOST    = 32'h3FC;
    localparam MAX_CYCLE = 20000;

    reg clk = 1'b0, rst = 1'b1;
    always #5 clk = ~clk;
    reg ext_bus_stall = 1'b0, ext_instr_stall = 1'b0;
    reg random_stall = 1'b0;

    wire [31:0] instr_addr, data_addr, data_wdata, data_rdata;
    wire [3:0]  data_wstrb;
    wire        data_we, data_re, ram_stall;

    reg [31:0] imem [0:511];
    wire [31:0] instr_rdata = ext_instr_stall ? 32'hFFFF_FFFF : imem[instr_addr[10:2]];

    RAM_Macro_Core u_ram (.clk(clk), .rst(rst), .MemWrite(data_we), .MemRead(data_re), .addr(data_addr),
                          .write_data(data_wdata), .wstrb(data_wstrb), .read_data(data_rdata), .stall(ram_stall));

    RISCV_Core dut (
        .clk(clk), .rst(rst), .bus_stall(ram_stall | ext_bus_stall), .data_err(1'b0),
        .irq_timer(1'b0), .irq_ext(1'b0),
        .instr_rdata(instr_rdata), .instr_addr(instr_addr), .instr_stall(ext_instr_stall),
        .data_rdata(data_rdata), .data_addr(data_addr), .data_wdata(data_wdata),
        .data_wstrb(data_wstrb), .data_we(data_we), .data_re(data_re),
        .PC_debug(), .Instr_debug(), .RegWrite_WB_debug(), .Rd_WB_debug(), .Result_WB_debug()
    );

    always @(negedge clk) begin
        ext_bus_stall   <= random_stall && !rst && (($urandom % 10) < 3);
        ext_instr_stall <= random_stall && !rst && (($urandom % 10) < 3);
    end

    integer fails = 0;
    integer i;

    task automatic run_program(input string name);
        integer cycles;
        begin
            for (i = 0; i < 512; i = i + 1) imem[i] = 32'h00000013;
            $readmemh("../dv/tests/asm/core_isa_test.hex", imem);
            // The macro model starts unknown, the program expects a zeroed data RAM
            for (i = 0; i < 1024; i = i + 1) u_ram.u_macro.mem[i] = 32'h0;
            rst = 1'b1;
            repeat (3) @(posedge clk);
            #1 rst = 1'b0;
            cycles = 0;
            while (u_ram.u_macro.mem[TOHOST[11:2]] === 32'h0 && cycles < MAX_CYCLE) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            #1;
            if (u_ram.u_macro.mem[TOHOST[11:2]] === 32'h1)
                $display("[PASS] %0s (%0d cycles)", name, cycles);
            else begin
                fails = fails + 1;
                $display("[FAIL] %0s: tohost = %h after %0d cycles, PC = %h", name,
                         u_ram.u_macro.mem[TOHOST[11:2]], cycles, instr_addr);
            end
        end
    endtask

    initial begin
        random_stall = 1'b0;
        run_program("wrapper stall only");
        random_stall = 1'b1;
        run_program("wrapper stall + random bus_stall and instr_stall");
        if (fails == 0) $display("RAM_Core_ISA_tb RESULT: PASS");
        else            $display("RAM_Core_ISA_tb RESULT: FAIL");
        $finish;
    end
endmodule
