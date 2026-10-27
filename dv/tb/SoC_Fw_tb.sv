`timescale 1ns/1ps
// SoC_Fw_tb: the real Secure Boot firmware (fw/secure_boot, P-13) on the whole SoC.
//  - Boot ROM = fw/build/firmware_imem.hex (make fw), RAM = firmware_dmem.hex, App ROM = sim/app.hex
//    (dv/sw/mkhex.py), golden hash = sim/fw_golden.hex (fw/tools/golden.py app.hex) written into the
//    Boot ROM slot at SB_GOLDEN_ADDR (0xFE0) right after the ROM loads its image
//  - default run : good image, the firmware must print the right hash, release the App, and the App must run
//  - +TAMPER     : one App ROM bit flipped, the firmware must lock the App out (Boot Guard) and clear its RAM
//  - UART0 log is taken from the APB writes to TXDATA (the firmware waits for room, so nothing is dropped)
//  - The Master must never trap (mcause stays 0) and the Master AXI bus must see no error response
// Run from sim/ (sim/run_fw.do). Ends with "SoC_Fw_tb RESULT: PASS|FAIL".
module SoC_Fw_tb;

    localparam MAXC      = 2000000;     // cycle limit: about 110 log characters at 115200 baud dominate
    localparam GOLD_WORD = 1016;        // 0xFE0 / 4

    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;

    wire [7:0] led;
    wire [7:0] gpio1_o;
    wire       uart0_tx;
    wire       uart1_tx;

    SoC_Top #(.BOOT_HEX("../fw/build/firmware_imem.hex"), .RAM_HEX("../fw/build/firmware_dmem.hex"),
              .APP_HEX("app.hex")) dut(
        .clk(clk), .reset_system(rst), .app_running(),
        .uart0_tx(uart0_tx), .uart0_rx(1'b1), .gpio0_o(led), .gpio0_i(8'h00), .boot_strap(4'h0),
        .uart1_tx(uart1_tx), .uart1_rx(1'b1), .gpio1_o(gpio1_o), .gpio1_i(8'h00));

    // Golden hash into the Boot ROM, +TAMPER after that (the ROMs load their images at time 0)
    reg [31:0] golden [0:7];
    integer    tamper = 0;
    integer    k;
    initial begin
        if ($test$plusargs("TAMPER"))
            tamper = 1;
        $readmemh("fw_golden.hex", golden);
        #1;
        for (k = 0; k < 8; k = k + 1)
            dut.boot_rom.rom[GOLD_WORD + k] = golden[k];
        if (tamper)
            dut.app_rom.rom[0] = dut.app_rom.rom[0] ^ 32'h1;
    end

    // UART0 log from the APB writes to TXDATA, plus a sliding window to spot the result lines
    reg [8*80-1:0] win = 0;
    reg [8*64-1:0] hash_txt = 0;
    integer        nchar = 0;
    integer        hash_left = 0;
    reg            seen_start = 0;
    reg            seen_released = 0;
    reg            seen_locked = 0;
    reg            seen_hash = 0;
    reg      [7:0] ch;
    always @(posedge clk) begin
        if (dut.uart0.PSEL && dut.uart0.PENABLE && dut.uart0.PWRITE && dut.uart0.PADDR == 12'h000) begin
            ch = dut.uart0.PWDATA[7:0];
            nchar = nchar + 1;
            win = {win[8*79-1:0], ch};
            if (hash_left > 0) begin
                hash_txt = {hash_txt[8*63-1:0], ch};
                hash_left = hash_left - 1;
            end
            if (win[8*16-1:0] == "HRoT secure boot")
                seen_start = 1;
            if (win[8*13-1:0] == "App ROM hash ") begin
                seen_hash = 1;
                hash_left = 64;
            end
            if (win[8*12-1:0] == "App released")
                seen_released = 1;
            if (win[8*14-1:0] == "App locked out")
                seen_locked = 1;
        end
    end

    // Error responses on the Master AXI bus
    integer bus_errs = 0;
    always @(posedge clk) begin
        if (dut.M_AXI_BVALID && dut.M_AXI_BREADY && dut.M_AXI_BRESP[1])
            bus_errs = bus_errs + 1;
        if (dut.M_AXI_RVALID && dut.M_AXI_RREADY && dut.M_AXI_RRESP[1])
            bus_errs = bus_errs + 1;
    end

    // Golden words as the hex text the firmware prints (digest bytes in order)
    function [8*64-1:0] golden_text(input integer dummy);
        integer w;
        integer b;
        integer n;
        reg [7:0] byte_v;
        reg [3:0] nib;
        begin
            golden_text = 0;
            for (w = 0; w < 8; w = w + 1) begin
                for (b = 0; b < 4; b = b + 1) begin
                    byte_v = golden[w] >> (8 * b);
                    for (n = 1; n >= 0; n = n - 1) begin
                        nib = byte_v >> (4 * n);
                        golden_text = {golden_text[8*63-1:0], (nib < 10) ? (8'd48 + nib) : (8'd87 + nib)};
                    end
                end
            end
        end
    endfunction

    integer cyc = 0;
    integer i;
    integer zeros;
    reg     ok;
    initial begin
        repeat (3) @(posedge clk);
        #1 rst = 0;
        while (led === 8'h00 && cyc < MAXC) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        repeat (2000) @(posedge clk);        // UART drains, the App gets to run
        zeros = 0;
        for (i = 0; i < 1024; i = i + 1)
            if (dut.app_ram.ram[i] === 32'b0)
                zeros = zeros + 1;
        $display("%s run: firmware finished after %0d cycles, LED=%h", tamper ? "Tampered" : "Good", cyc, led);
        $display("UART0 %0d chars, hash printed: %0s", nchar, seen_hash ? hash_txt : "(none)");
        $display("golden                 : %0s", golden_text(0));
        $display("app_core_reset_n=%b lock=%b zero_done=%b app_ram[0]=%0d zeroed words=%0d mcause=%h bus errors=%0d",
                 dut.app_core_reset_n, dut.syscsr.lock_q, dut.syscsr.zero_done, dut.app_ram.ram[0], zeros,
                 dut.master_core.u_CSR_Unit.mcause, bus_errs);
        ok = (cyc < MAXC) && seen_start && seen_hash && bus_errs == 0
             && dut.master_core.u_CSR_Unit.mcause === 32'b0;
        if (tamper)
            ok = ok && led == 8'hEE && seen_locked && !seen_released && dut.app_core_reset_n === 1'b0
                    && dut.syscsr.lock_q === 1'b1 && dut.syscsr.zero_done === 1'b1 && zeros == 1024
                    && hash_txt != golden_text(0);
        else
            ok = ok && led == 8'h01 && seen_released && !seen_locked && dut.app_core_reset_n === 1'b1
                    && dut.syscsr.lock_q === 1'b0 && dut.app_ram.ram[0] === 42 && hash_txt == golden_text(0);
        $display("SoC_Fw_tb RESULT: %s", ok ? "PASS" : "FAIL");
        $finish;
    end

endmodule
