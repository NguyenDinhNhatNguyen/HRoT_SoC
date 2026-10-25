`ifndef AXI4_LITE_IF_SV
`define AXI4_LITE_IF_SV
`timescale 1ns/1ps

// AXI4-Lite interface (reset active-low).
//  - drv_cb : clocking block for the driver (drives master signals, samples slave signals)
//  - mon_cb : clocking block for the monitor (sample only)
//  - SVA    : protocol checks (disable with +define+AXI4_LITE_NO_ASSERT)
// Note: the project RTL uses an active-high reset ("reset"), connect ~rst_n to it.
interface axi4_lite_if (input logic clk, input logic rst_n);

    // Write address channel
    logic [31:0] awaddr;
    logic        awvalid;
    logic        awready;
    // Write data channel
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;
    // Write response channel
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;
    // Read address channel
    logic [31:0] araddr;
    logic        arvalid;
    logic        arready;
    // Read data channel
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;

    // Count SVA failures. An SVA $error does NOT reach the UVM error count,
    // so base_test.check_phase reads this and raises uvm_error if it is not 0.
    int unsigned assert_fail_count = 0;

    // Count resets (falling edges of rst_n). A sequence compares it before/after a multi-transaction
    // operation to see whether the DUT was reset in between (the driver only aborts the running transaction).
    int unsigned reset_count = 0;
    always @(negedge rst_n) reset_count++;

    clocking drv_cb @(posedge clk);
        output awaddr, awvalid, wdata, wstrb, wvalid, bready, araddr, arvalid, rready;
        input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid;
    endclocking

    clocking mon_cb @(posedge clk);
        input rst_n;
        input awaddr, awvalid, awready, wdata, wstrb, wvalid, wready;
        input bresp, bvalid, bready;
        input araddr, arvalid, arready, rdata, rresp, rvalid, rready;
    endclocking

`ifndef AXI4_LITE_NO_ASSERT
    // Once VALID is high, VALID and the payload must stay stable until READY
    a_aw_stable : assert property (@(posedge clk) disable iff (!rst_n)
            (awvalid && !awready) |=> (awvalid && $stable(awaddr)))
        else begin
            assert_fail_count++;
            $error("AXI4L: AWVALID/AWADDR changed before AWREADY");
        end
    a_w_stable  : assert property (@(posedge clk) disable iff (!rst_n)
            (wvalid && !wready) |=> (wvalid && $stable(wdata) && $stable(wstrb)))
        else begin
            assert_fail_count++;
            $error("AXI4L: WVALID/WDATA/WSTRB changed before WREADY");
        end
    a_ar_stable : assert property (@(posedge clk) disable iff (!rst_n)
            (arvalid && !arready) |=> (arvalid && $stable(araddr)))
        else begin
            assert_fail_count++;
            $error("AXI4L: ARVALID/ARADDR changed before ARREADY");
        end
    a_b_stable  : assert property (@(posedge clk) disable iff (!rst_n)
            (bvalid && !bready) |=> (bvalid && $stable(bresp)))
        else begin
            assert_fail_count++;
            $error("AXI4L: BVALID/BRESP changed before BREADY");
        end
    a_r_stable  : assert property (@(posedge clk) disable iff (!rst_n)
            (rvalid && !rready) |=> (rvalid && $stable(rdata) && $stable(rresp)))
        else begin
            assert_fail_count++;
            $error("AXI4L: RVALID/RDATA/RRESP changed before RREADY");
        end
    // No X on control signals after reset
    a_no_x : assert property (@(posedge clk) disable iff (!rst_n)
            !$isunknown({awvalid, awready, wvalid, wready, bvalid, bready,
                                      arvalid, arready, rvalid, rready}))
        else begin
            assert_fail_count++;
            $error("AXI4L: VALID/READY signal is X/Z");
        end
`endif

endinterface
`endif
