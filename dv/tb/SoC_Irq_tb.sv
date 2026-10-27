`timescale 1ns/1ps
// SoC_Irq_tb: interrupts of both cores on the whole SoC (P-14), with the interrupt lines wired in SoC_Top (I-01).
//  - Boot ROM = dv/tests/asm/soc_irq_master.hex, App ROM = dv/tests/asm/soc_irq_app.hex, no RAM preload
//  - Master: TIMER0 -> irq_timer, GPIO0 pin 0 -> PLIC-lite -> irq_ext, MEI before MTI, Mailbox from the App
//  - App   : TIMER1 -> irq_timer, Mailbox from the Secure world -> irq_ext
//  - The testbench pulses gpio0_i[0] when the Master shows 0xA1 and again on 0xA2
//  - Each program shows its result on its LEDs: 0x01 = PASS, 0x80 | step = FAIL
// Run from sim/ (sim/run_fw.do with TB = SoC_Irq_tb). Ends with "SoC_Irq_tb RESULT: PASS|FAIL".
module SoC_Irq_tb;

    localparam MAXC = 200000;

    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;

    wire [7:0] led0;
    wire [7:0] led1;
    reg  [7:0] gpio0_i = 8'h00;
    wire       uart0_tx;
    wire       uart1_tx;

    SoC_Top #(.BOOT_HEX("../dv/tests/asm/soc_irq_master.hex"), .RAM_HEX(""),
              .APP_HEX("../dv/tests/asm/soc_irq_app.hex")) dut(
        .clk(clk), .reset_system(rst), .app_running(),
        .uart0_tx(uart0_tx), .uart0_rx(1'b1), .gpio0_o(led0), .gpio0_i(gpio0_i), .boot_strap(4'h0),
        .uart1_tx(uart1_tx), .uart1_rx(1'b1), .gpio1_o(led1), .gpio1_i(8'h00));

    task pulse_pin0;
        begin
            repeat (20) @(posedge clk);
            gpio0_i[0] = 1'b1;
            repeat (20) @(posedge clk);
            gpio0_i[0] = 1'b0;
        end
    endtask

    initial begin
        wait (led0 === 8'hA1);
        pulse_pin0;
        wait (led0 === 8'hA2);
        pulse_pin0;
    end

    // Count interrupts taken by each core (trap entry with mcause bit 31)
    integer m_irq = 0;
    integer a_irq = 0;
    always @(posedge clk) begin
        if (dut.master_core.u_CSR_Unit.redirect && dut.master_core.u_CSR_Unit.kill && !dut.master_core.u_CSR_Unit.illegal)
            m_irq = m_irq + 1;
        if (dut.app_core.u_CSR_Unit.redirect && dut.app_core.u_CSR_Unit.kill && !dut.app_core.u_CSR_Unit.illegal)
            a_irq = a_irq + 1;
    end

    integer cyc = 0;
    reg     ok;
    initial begin
        repeat (3) @(posedge clk);
        #1 rst = 0;
        // Done when each LED shows PASS (0x01) or a FAIL code (0x8n). 0xA1/0xA2 only ask for a GPIO pulse
        while (!((led0 === 8'h01 || led0[7:4] === 4'h8) && (led1 === 8'h01 || led1[7:4] === 4'h8)) && cyc < MAXC) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        repeat (20) @(posedge clk);
        $display("Master LED=%h  App LED=%h  after %0d cycles", led0, led1, cyc);
        $display("interrupts taken: Master %0d (expected 5), App %0d (expected 2)", m_irq, a_irq);
        $display("Master mcause=%h mepc=%h  App mcause=%h mepc=%h",
                 dut.master_core.u_CSR_Unit.mcause, {dut.master_core.u_CSR_Unit.mepc_q, 2'b00},
                 dut.app_core.u_CSR_Unit.mcause, {dut.app_core.u_CSR_Unit.mepc_q, 2'b00});
        ok = (cyc < MAXC) && led0 === 8'h01 && led1 === 8'h01 && m_irq == 5 && a_irq == 2;
        $display("SoC_Irq_tb RESULT: %s", ok ? "PASS" : "FAIL");
        $finish;
    end

endmodule
