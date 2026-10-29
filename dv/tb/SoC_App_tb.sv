`timescale 1ns/1ps
// SoC_App_tb: the real firmware of both cores on the whole SoC, straight from the build (P-16).
//  - Boot ROM = fw/build/firmware_imem.hex with the golden hash already at 0xFE0 (the I-04 build step,
//    nothing is patched in here), RAM = firmware_dmem.hex, App ROM = fw/build/app_firmware.hex (4 KB)
//  - default run : Secure Boot releases the App, the App says "App running" on UART1, sends APP_MSG_HELLO
//    and then one APP_MSG_STEP per LED step through the Mailbox, the Master logs them on UART0, GPIO1 runs
//  - +TAMPER     : one App ROM bit flipped after the load, the Master locks the App out and the App never runs
//  - TIMER1 is moved forward by the testbench while the App runs, so a 0.25 s LED step takes about
//    100,000 cycles instead of 12.5 million (the firmware only looks at the elapsed time)
// Run from sim/ (sim/run_fw.do with TB = SoC_App_tb, after make fw). Ends with "SoC_App_tb RESULT: PASS|FAIL".
module SoC_App_tb;

    localparam MAXC       = 3000000;
    localparam STEPS      = 3;          // LED steps the good run waits for (each one relayed to UART0)
    localparam MSG_HELLO  = 32'h4150_5031;
    localparam MSG_STEP   = 32'h5354_0000;

    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;

    wire [7:0] led0;
    wire [7:0] led1;
    wire       uart0_tx;
    wire       uart1_tx;

    SoC_Top #(.BOOT_HEX("../fw/build/firmware_imem.hex"), .RAM_HEX("../fw/build/firmware_dmem.hex"),
              .APP_HEX("../fw/build/app_firmware.hex")) dut(
        .clk(clk), .reset_system(rst), .app_running(),
        .uart0_tx(uart0_tx), .uart0_rx(1'b1), .gpio0_o(led0), .gpio0_i(8'h00), .boot_strap(4'h0),
        .uart1_tx(uart1_tx), .uart1_rx(1'b1), .gpio1_o(led1), .gpio1_i(8'h00));

    integer tamper = 0;
    initial begin
        if ($test$plusargs("TAMPER"))
            tamper = 1;
        #1;
        if (tamper)
            dut.app_rom.rom[0] = dut.app_rom.rom[0] ^ 32'h1;
    end

    // TIMER1 fast-forward: 125,000 ticks every 1,000 cycles once the App runs
    integer ff = 0;
    always @(negedge clk) begin
        if (dut.app_core_reset_n === 1'b1) begin
            ff = ff + 1;
            if (ff == 1000) begin
                dut.timer1.mtime = dut.timer1.mtime + 64'd125000;
                ff = 0;
            end
        end
    end

    // UART0 log (Master): "App says <hex>" lines, taken from the APB writes to TXDATA
    reg [8*32-1:0] win0 = 0;
    reg [8*8-1:0]  word_txt = 0;
    integer        word_left = 0;
    integer        n_says = 0;
    reg     [31:0] says [0:15];
    reg            seen_released = 0;
    reg            seen_locked = 0;
    reg      [7:0] ch0;

    function [31:0] hex_val(input [8*8-1:0] t);
        integer k;
        reg [7:0] c;
        begin
            hex_val = 0;
            for (k = 7; k >= 0; k = k - 1) begin
                c = t >> (8 * k);
                hex_val = {hex_val[27:0], (c >= 8'd97) ? c[3:0] + 4'd9 : c[3:0]};
            end
        end
    endfunction

    always @(posedge clk) begin
        if (dut.uart0.PSEL && dut.uart0.PENABLE && dut.uart0.PWRITE && dut.uart0.PADDR == 12'h000) begin
            ch0 = dut.uart0.PWDATA[7:0];
            win0 = {win0[8*31-1:0], ch0};
            if (word_left > 0) begin
                word_txt = {word_txt[8*7-1:0], ch0};
                word_left = word_left - 1;
                if (word_left == 0 && n_says < 16) begin
                    says[n_says] = hex_val(word_txt);
                    n_says = n_says + 1;
                end
            end
            if (win0[8*9-1:0] == "App says ")
                word_left = 8;
            if (win0[8*12-1:0] == "App released")
                seen_released = 1;
            if (win0[8*14-1:0] == "App locked out")
                seen_locked = 1;
        end
    end

    // UART1 (App world): the bus is single cycle, so every write with PSEL is one character
    reg [8*16-1:0] win1 = 0;
    integer        n_uart1 = 0;
    reg            seen_running = 0;
    always @(posedge clk) begin
        if (dut.uart1.PSEL && dut.uart1.PWRITE && dut.uart1.PADDR == 12'h000) begin
            win1 = {win1[8*15-1:0], dut.uart1.PWDATA[7:0]};
            n_uart1 = n_uart1 + 1;
            if (win1[8*11-1:0] == "App running")
                seen_running = 1;
        end
    end

    // GPIO1 running light: each change must be the previous pattern rotated left by one
    // (X before the reset reaches GPIO1 is not a change)
    reg [7:0] led1_q = 8'h00;
    integer   led1_steps = 0;
    integer   led1_bad = 0;
    always @(posedge clk) begin
        if (led1 !== led1_q && ^led1 !== 1'bx) begin
            if (led1_q == 8'h00)
                led1_bad = led1_bad + (led1 !== 8'h01);
            else if (led1 !== {led1_q[6:0], led1_q[7]})
                led1_bad = led1_bad + 1;
            else
                led1_steps = led1_steps + 1;
            led1_q = led1;
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

    integer cyc = 0;
    integer i;
    reg     ok;
    reg     says_ok;
    initial begin
        repeat (3) @(posedge clk);
        #1 rst = 0;
        // Good run: until the Master has relayed HELLO and STEPS step words. Tampered run: until the
        // Master has finished, then long enough for an App that should not run to show itself
        if (tamper) begin
            while (led0 === 8'h00 && cyc < MAXC) begin
                @(posedge clk);
                cyc = cyc + 1;
            end
            repeat (300000) @(posedge clk);
        end else begin
            while (n_says < STEPS + 1 && cyc < MAXC) begin
                @(posedge clk);
                cyc = cyc + 1;
            end
            repeat (2000) @(posedge clk);
        end

        $display("%s run after %0d cycles: Master LED=%h, App LED=%h (%0d steps, %0d bad), app_core_reset_n=%b lock=%b",
                 tamper ? "Tampered" : "Good", cyc, led0, led1, led1_steps, led1_bad, dut.app_core_reset_n, dut.syscsr.lock_q);
        $display("UART1 %0d chars, \"App running\" %0s. Master relayed %0d Mailbox words:", n_uart1,
                 seen_running ? "seen" : "missing", n_says);
        for (i = 0; i < n_says; i = i + 1)
            $display("  App says %h", says[i]);
        $display("Master mcause=%h App mcause=%h bus errors=%0d", dut.master_core.u_CSR_Unit.mcause,
                 dut.app_core.u_CSR_Unit.mcause, bus_errs);

        ok = (cyc < MAXC) && bus_errs == 0 && dut.master_core.u_CSR_Unit.mcause === 32'b0;
        if (tamper) begin
            ok = ok && led0 == 8'hEE && seen_locked && !seen_released && dut.app_core_reset_n === 1'b0
                    && dut.syscsr.lock_q === 1'b1 && n_uart1 == 0 && n_says == 0 && led1 === 8'h00;
        end else begin
            // HELLO first, then the step words 1, 2, 3 ... in order
            says_ok = n_says >= STEPS + 1 && says[0] === MSG_HELLO;
            for (i = 1; i < n_says; i = i + 1)
                says_ok = says_ok && says[i] === (MSG_STEP | i);
            ok = ok && led0 == 8'h01 && seen_released && !seen_locked && dut.app_core_reset_n === 1'b1
                    && seen_running && says_ok && led1_steps >= STEPS && led1_bad == 0
                    && dut.app_core.u_CSR_Unit.mcause === 32'b0;
        end
        $display("SoC_App_tb RESULT: %s", ok ? "PASS" : "FAIL");
        $finish;
    end

endmodule
