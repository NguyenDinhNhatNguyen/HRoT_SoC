`ifndef APB_IF_SV
`define APB_IF_SV
`timescale 1ns/1ps

// APB4 interface (reset active-low), P-17. Same layout as axi4_lite_if:
//  - drv_cb : clocking block for the master driver
//  - mon_cb : clocking block for the monitor (sample only)
//  - SVA    : APB4 protocol checks (disable with +define+APB_NO_ASSERT)
// The project RTL uses an active-high reset, connect ~rst_n to it.
interface apb_if (input logic clk, input logic rst_n);

    logic [31:0] paddr;
    logic        psel;
    logic        penable;
    logic        pwrite;
    logic [31:0] pwdata;
    logic [3:0]  pstrb;
    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;

    // SVA failures, read by apb_base_test.check_phase (an SVA $error never reaches the UVM counters)
    int unsigned assert_fail_count = 0;
    int unsigned reset_count = 0;
    always @(negedge rst_n) reset_count++;

    clocking drv_cb @(posedge clk);
        output paddr, psel, penable, pwrite, pwdata, pstrb;
        input  prdata, pready, pslverr;
    endclocking

    clocking mon_cb @(posedge clk);
        input rst_n;
        input paddr, psel, penable, pwrite, pwdata, pstrb, prdata, pready, pslverr;
    endclocking

`ifndef APB_NO_ASSERT
    // PENABLE only in the access phase: it needs PSEL
    a_enable_sel : assert property (@(posedge clk) disable iff (!rst_n)
            penable |-> psel)
        else begin
            assert_fail_count++;
            $error("APB: PENABLE without PSEL");
        end
    // A setup cycle (PSEL, no PENABLE) is always followed by the access phase with the same request
    a_setup_access : assert property (@(posedge clk) disable iff (!rst_n)
            (psel && !penable) |=> (psel && penable && $stable(paddr) && $stable(pwrite)
                                    && $stable(pwdata) && $stable(pstrb)))
        else begin
            assert_fail_count++;
            $error("APB: setup phase not followed by a stable access phase");
        end
    // While the slave inserts wait states, the master holds everything
    a_wait_stable : assert property (@(posedge clk) disable iff (!rst_n)
            (psel && penable && !pready) |=> (psel && penable && $stable(paddr) && $stable(pwrite)
                                              && $stable(pwdata) && $stable(pstrb)))
        else begin
            assert_fail_count++;
            $error("APB: request changed during wait states");
        end
    // After the transfer completes, PENABLE drops (next transfer starts with a new setup phase)
    a_enable_drop : assert property (@(posedge clk) disable iff (!rst_n)
            (psel && penable && pready) |=> !penable)
        else begin
            assert_fail_count++;
            $error("APB: PENABLE still high after the transfer completed");
        end
    // No X on the control signals, and no X on PREADY/PSLVERR during the access phase
    a_no_x : assert property (@(posedge clk) disable iff (!rst_n)
            !$isunknown({psel, penable}) && (!(psel && penable) || !$isunknown({pready, pslverr})))
        else begin
            assert_fail_count++;
            $error("APB: PSEL/PENABLE/PREADY/PSLVERR is X/Z");
        end
`endif

endinterface

// Pins around the APB peripherals in tb_apb_top (P-17): gpio_i is driven by the sequences,
// the outputs and interrupt lines are read by them
interface apb_sb_if (input logic clk);
    logic [7:0] gpio_i = 8'h00;
    logic [7:0] gpio_o;
    logic       gpio_irq;
    logic       timer_irq;
    logic       mbox_irq_s;
    logic       mbox_irq_a;
endinterface
`endif
