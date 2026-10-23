`timescale 1ns/1ps

// ============================================================
// RISCV_Core_prog_tb: chay chuong trinh tu kiem tra dv/tests/asm/core_isa_test.hex
//  - ROM lenh va RAM du lieu doc to hop (dung giao uoc cua RISCV_Core)
//  - RAM ghi theo byte lane (data_wstrb)
//  - Chay 2 lan: khong stall, va bus_stall ngau nhien (pipeline phai dong bang dung)
//  - Ket qua doc tu TOHOST (0x3FC): 1 = PASS, (n<<1)|1 = FAIL tai CHECK thu n
// Tham so: +HEX=<duong dan .hex> (mac dinh tinh tu thu muc sim/)
// ============================================================
module RISCV_Core_prog_tb;

    localparam TOHOST    = 32'h3FC;
    localparam MAX_CYCLE = 5000;

    reg clk = 1'b0, rst = 1'b1, bus_stall = 1'b0;
    always #5 clk = ~clk;

    wire [31:0] instr_addr, data_addr, data_wdata;
    wire [3:0]  data_wstrb;
    wire        data_we, data_re;

    reg  [31:0] imem [0:255];
    reg  [31:0] dmem [0:255];

    wire [31:0] instr_rdata = imem[instr_addr[9:2]];
    wire [31:0] data_rdata  = dmem[data_addr[9:2]];

    always @(posedge clk) begin
        if (data_we) begin
            if (data_wstrb[0]) dmem[data_addr[9:2]][7:0]   <= data_wdata[7:0];
            if (data_wstrb[1]) dmem[data_addr[9:2]][15:8]  <= data_wdata[15:8];
            if (data_wstrb[2]) dmem[data_addr[9:2]][23:16] <= data_wdata[23:16];
            if (data_wstrb[3]) dmem[data_addr[9:2]][31:24] <= data_wdata[31:24];
        end
    end

    RISCV_Core dut (
        .clk(clk), .rst(rst), .bus_stall(bus_stall),
        .instr_rdata(instr_rdata), .instr_addr(instr_addr),
        .data_rdata(data_rdata), .data_addr(data_addr), .data_wdata(data_wdata),
        .data_wstrb(data_wstrb), .data_we(data_we), .data_re(data_re),
        .PC_debug(), .Instr_debug(), .RegWrite_WB_debug(), .Rd_WB_debug(), .Result_WB_debug()
    );

    reg [1023:0] hex_file;
    integer      i, fail_count = 0, stall_mode = 0;

    // bus_stall ngau nhien ~30% so chu ky (chi trong lan chay thu 2)
    always @(negedge clk)
        bus_stall <= (stall_mode != 0) && !rst && (($urandom % 10) < 3);

    task automatic run_program(input [255:0] name);
        integer cycles;
        begin
            for (i = 0; i < 256; i = i + 1) begin imem[i] = 32'h00000013; dmem[i] = 32'h0; end
            $readmemh(hex_file, imem);
            rst = 1'b1;
            repeat (3) @(posedge clk);
            #1 rst = 1'b0;

            cycles = 0;
            while (dmem[TOHOST[9:2]] == 32'h0 && cycles < MAX_CYCLE) begin
                @(posedge clk); cycles = cycles + 1;
            end
            #1;

            if (dmem[TOHOST[9:2]] == 32'h1)
                $display("[PASS] %0s (%0d chu ky)", name, cycles);
            else begin
                fail_count = fail_count + 1;
                if (dmem[TOHOST[9:2]] == 32'h0)
                    $display("[FAIL] %0s: timeout sau %0d chu ky, PC=%h", name, cycles, instr_addr);
                else
                    $display("[FAIL] %0s: sai tai CHECK #%0d", name, dmem[TOHOST[9:2]] >> 1);
                for (i = 1; i < 32; i = i + 1)
                    $display("       x%0d = %h", i, dut.u_ID_Stage.u_Register_File.REG_MEM_BLOCK[i]);
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("HEX=%s", hex_file))
            hex_file = "../dv/tests/asm/core_isa_test.hex";

        $display("\n=== RISCV_Core program test: %0s ===", hex_file);
        stall_mode = 0; run_program("Khong stall");
        stall_mode = 1; run_program("bus_stall ngau nhien");

        $display("\n=== SUMMARY: %0s ===", (fail_count == 0) ? "PASS" : "FAIL");
        $finish;
    end

endmodule
