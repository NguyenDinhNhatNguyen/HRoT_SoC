`timescale 1ns/1ps
// ASIC_Top_tb: the ASIC wrapper (asic/ASIC_Top.v) around SoC_Top, with the real firmware of both cores
// from the build (make fw first), like SoC_App_tb.
//  1. The pad reset asserts with the clock stopped: reset_system must rise at once (asynchronous)
//  2. The pad reset is released in the middle of a clock cycle: reset_system must stay high through the
//     first rising edge and fall exactly on the second one (synchronous release)
//  3. Secure Boot runs through the wrapper: LED 0x01 (released) and the App Core running
//  4. The pad reset asserts again between clock edges: reset_system rises at once, and after the
//     release the App is held in reset until Secure Boot releases it again
// Run from sim/: vsim -c -do "set TB ASIC_Top_tb; do run_fw.do". Ends with "ASIC_Top_tb RESULT: PASS|FAIL".
module ASIC_Top_tb;

    localparam MAXC = 3000000;

    reg clk = 1'b0;
    reg clk_en = 1'b0;
    reg rst_n = 1'b1;
    always #5 if (clk_en) clk = ~clk;

    wire [7:0] led0;
    wire       app_running;

    ASIC_Top #(.BOOT_HEX("../fw/build/firmware_imem.hex"), .RAM_HEX("../fw/build/firmware_dmem.hex"),
               .APP_HEX("../fw/build/app_firmware.hex")) dut (
        .clk(clk), .rst_pad_n(rst_n), .app_running(app_running),
        .uart0_tx(), .uart0_rx(1'b1), .gpio0_o(led0), .gpio0_i(8'h00), .boot_strap(4'h0),
        .uart1_tx(), .uart1_rx(1'b1), .gpio1_o(), .gpio1_i(8'h00));

    wire reset_system = dut.soc.reset_system;

    integer errors = 0;
    integer cyc;
    integer edges;

    task automatic check(input bit ok, input string what);
        if (!ok) begin
            errors = errors + 1;
            $display("FAIL: %0s", what);
        end else
            $display("ok  : %0s", what);
    endtask

    task automatic boot(output integer cycles);
        cycles = 0;
        while (led0 !== 8'h01 && cycles < MAXC) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
    endtask

    initial begin
        // 1. Asynchronous assert with the clock stopped
        #20 rst_n = 1'b0;
        #1;
        check(reset_system === 1'b1, "reset_system rises with the clock stopped");

        // 2. Start the clock, release the pad reset 3 ns after a rising edge
        clk_en = 1'b1;
        repeat (4) @(posedge clk);
        #3 rst_n = 1'b1;
        @(posedge clk);
        #1 check(reset_system === 1'b1, "reset_system still high after the first edge");
        @(posedge clk);
        #1 check(reset_system === 1'b0, "reset_system falls on the second edge");

        // 3. Secure Boot through the wrapper
        boot(cyc);
        repeat (2000) @(posedge clk);
        $display("Boot after %0d cycles: LED=%h app_running=%b", cyc, led0, app_running);
        check(led0 === 8'h01 && app_running === 1'b1, "Secure Boot releases the App through ASIC_Top");

        // 4. Asynchronous assert between edges, then a second boot
        @(posedge clk);
        #2 rst_n = 1'b0;
        #1 check(reset_system === 1'b1, "reset_system rises between clock edges");
        repeat (3) @(posedge clk);
        #1 check(app_running === 1'b0, "App held in reset while the pad reset is low");
        #4 rst_n = 1'b1;
        edges = 0;
        while (reset_system === 1'b1 && edges < 10) begin
            @(posedge clk);
            #1 edges = edges + 1;
        end
        check(edges == 2, "second release also takes two edges");
        boot(cyc);
        repeat (2000) @(posedge clk);
        check(led0 === 8'h01 && app_running === 1'b1, "Secure Boot releases the App again after the reset");

        $display("ASIC_Top_tb RESULT: %s", (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end

endmodule
