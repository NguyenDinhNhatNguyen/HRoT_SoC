`timescale 1ns/1ps
// Whole-SoC test with the hand-written test firmware from dv/sw/mkhex.py. The Master checks RAM,
// SHA-256, bus errors, UART and GPIO, then runs the secure boot: it hashes the whole 4 KB App ROM
// with the CPU and twice with the Secure DMA, compares with the golden hashes in the Boot ROM,
// checks PLIC-lite and the DMA firewall, and only then releases the App Core.
//   default run : good image, the App must be released and run
//   +TAMPER     : one bit of the App ROM is flipped, the hash must not match and Boot Guard must lock the
//                 App out for good and clear its RAM, even though the firmware then tries to release it
// Ends with "SoC_Top_tb RESULT: PASS|FAIL".
module soc_tb;
    `include "labels.vh"

    localparam MAXC = 600000;           // cycle limit for the whole boot

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    wire       uart_tx;
    reg        uart_rx = 1;
    wire [7:0] led;
    wire       uart1_tx;
    wire [7:0] gpio1_o;

    SoC_Top #(.BOOT_HEX("boot.hex"), .RAM_HEX(""), .APP_HEX("app.hex")) dut(
        .clk(clk), .reset_system(rst), .app_running(),
        .uart0_tx(uart_tx), .uart0_rx(uart_rx), .gpio0_o(led), .gpio0_i(8'h00), .boot_strap(4'h0),
        .uart1_tx(uart1_tx), .uart1_rx(1'b1), .gpio1_o(gpio1_o), .gpio1_i(8'h00));

    // +TAMPER: flip one bit of the App ROM after its own initial block has loaded it
    integer tamper = 0;
    initial begin
        if ($test$plusargs("TAMPER"))
            tamper = 1;
        #1;
        if (tamper)
            dut.app_rom.rom[0] = dut.app_rom.rom[0] ^ 32'h1;
    end

    // UART receiver on the tb side (BAUD_DIV = 0 -> 16 clocks per bit)
    reg [8*8-1:0] uart_str = 0;
    integer       nchar = 0, b;
    reg   [7:0]   ch;
    initial forever begin
        @(negedge uart_tx);
        repeat (8) @(posedge clk);
        for (b = 0; b < 8; b = b + 1) begin
            repeat (16) @(posedge clk);
            ch[b] = uart_tx;
        end
        repeat (16) @(posedge clk);
        uart_str = {uart_str[8*7-1:0], ch};
        nchar = nchar + 1;
        $display("[%0t] UART tx byte %h", $time, ch);
    end

    // Once the firmware shows 0xA5 on the LEDs, send 0x5A back on RX
    task send_byte(input [7:0] v);
        integer j;
        begin
            uart_rx = 0;
            repeat (16) @(posedge clk);
            for (j = 0; j < 8; j = j + 1) begin
                uart_rx = v[j];
                repeat (16) @(posedge clk);
            end
            uart_rx = 1;
            repeat (16) @(posedge clk);
        end
    endtask

    initial begin
        wait (led === 8'hA5);
        send_byte(8'h5A);
    end

    // Count error responses on the Master AXI bus
    integer cyc = 0;
    integer slverr = 0, slverr_r = 0, decerr_w = 0, decerr_r = 0;
    always @(posedge clk) begin
        if (dut.M_AXI_BVALID && dut.M_AXI_BREADY && dut.M_AXI_BRESP == 2'b10)
            slverr = slverr + 1;
        if (dut.M_AXI_BVALID && dut.M_AXI_BREADY && dut.M_AXI_BRESP == 2'b11)
            decerr_w = decerr_w + 1;
        if (dut.M_AXI_RVALID && dut.M_AXI_RREADY && dut.M_AXI_RRESP == 2'b11)
            decerr_r = decerr_r + 1;
        if (dut.M_AXI_RVALID && dut.M_AXI_RREADY && dut.M_AXI_RRESP == 2'b10)
            slverr_r = slverr_r + 1;
    end

    // The Secure DMA may only ever put these on the bus: no RAM, no APB, nothing but ROM reads and SHA writes
    integer dma_stray = 0;
    always @(posedge clk) begin
        if (dut.axi_req_valid && dut.bus_idle && dut.sel_dma) begin
            if (dut.axi_req_write && dut.axi_req_addr[31:8] !== 24'h500000)
                dma_stray = dma_stray + 1;
            if (!dut.axi_req_write && dut.axi_req_addr[31:12] !== 20'h60000 && dut.axi_req_addr !== 32'h50000044)
                dma_stray = dma_stray + 1;
        end
    end

    integer i, zeros;
    reg     ok;
    initial begin
        repeat (3) @(posedge clk);
        #1 rst = 0;
        if (tamper) begin
            while (led !== 8'hEE && cyc < MAXC) begin
                @(posedge clk);
                cyc = cyc + 1;
            end
        end else begin
            while (dut.app_core_reset_n !== 1'b1 && cyc < MAXC) begin
                @(posedge clk);
                cyc = cyc + 1;
            end
        end
        repeat (400) @(posedge clk);
        zeros = 0;
        for (i = 0; i < 1024; i = i + 1)
            if (dut.app_ram.ram[i] === 32'b0)
                zeros = zeros + 1;
        $display("%s run: boot took %0d cycles", tamper ? "Tampered" : "Good", cyc);
        $display("app_core_reset_n=%b  app_ram[0]=%0d  zeroed RAM words=%0d", dut.app_core_reset_n, dut.app_ram.ram[0], zeros);
        $display("SLVERR=%0d SLVERR_R=%0d DECERR_W=%0d DECERR_R=%0d  stray DMA requests=%0d", slverr, slverr_r, decerr_w, decerr_r, dma_stray);
        $display("UART received %0d chars: \"%0s\"  LED=%h", nchar, uart_str, led);
        ok = (cyc < MAXC) && slverr == 1 && slverr_r == 1 && decerr_w == 1 && decerr_r == 1
             && nchar == 2 && uart_str[15:0] == "OK" && dma_stray == 0;
        if (tamper)
            ok = ok && dut.app_core_reset_n === 1'b0 && dut.syscsr.lock_q === 1'b1
                    && dut.syscsr.zero_done === 1'b1 && led == 8'hEE && zeros == 1024;
        else
            ok = ok && dut.app_core_reset_n === 1'b1 && dut.app_ram.ram[0] === 42
                    && dut.syscsr.lock_q === 1'b0 && led == 8'h5A;
        $display("SoC_Top_tb RESULT: %s", ok ? "PASS" : "FAIL");
        $finish;
    end
endmodule
