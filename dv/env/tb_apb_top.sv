`timescale 1ns/1ps
// UVM top for the APB peripherals (P-17): two APB master agents drive the real RTL.
//   Secure bus (apb_if "secure"): APB_Decoder with 4 windows of 4 KB (PADDR[15:12])
//     0 GPIO, 1 TIMER, 2 Mailbox (Secure side), 3 apb_slave_model (RAM with wait states),
//     windows 4..15 have no slave: the decoder answers at once with PSLVERR
//   App bus (apb_if "app"): straight to the App side of the same Mailbox
// apb_sb_if (dv/agents/apb_if.sv) carries the pins around the peripherals: gpio_i is driven by the
// sequences, the outputs (gpio_o and the interrupt lines) are checked by them.
module tb_apb_top;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import hrot_dv_pkg::*;

    logic clk   = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    apb_if    s_if (.clk(clk), .rst_n(rst_n));
    apb_if    a_if (.clk(clk), .rst_n(rst_n));
    apb_sb_if sb   (.clk(clk));

    // The package holds the AXI4-Lite classes too (virtual axi4_lite_if). Questa needs an instance of every
    // virtual interface type in the design, so this one stays unused. rst_n = 0 keeps its SVA disabled
    axi4_lite_if axi_unused (.clk(clk), .rst_n(1'b0));

    localparam NUM_SLV = 4;
    wire [NUM_SLV-1:0]    psel_s;
    wire [32*NUM_SLV-1:0] prdata_s;
    wire [NUM_SLV-1:0]    pready_s;
    wire [NUM_SLV-1:0]    pslverr_s;

    APB_Decoder #(.NUM_SLV(NUM_SLV)) dec (
        .PADDR(s_if.paddr), .PSEL(s_if.psel), .PSEL_S(psel_s),
        .PRDATA_S(prdata_s), .PREADY_S(pready_s), .PSLVERR_S(pslverr_s),
        .PRDATA(s_if.prdata), .PREADY(s_if.pready), .PSLVERR(s_if.pslverr)
    );

    GPIO gpio (
        .clk(clk), .reset(~rst_n), .gpio_o(sb.gpio_o), .gpio_i(sb.gpio_i), .irq(sb.gpio_irq),
        .PADDR(s_if.paddr[11:0]), .PSEL(psel_s[0]), .PENABLE(s_if.penable), .PWRITE(s_if.pwrite),
        .PWDATA(s_if.pwdata), .PSTRB(s_if.pstrb), .PRDATA(prdata_s[31:0]), .PREADY(pready_s[0]),
        .PSLVERR(pslverr_s[0])
    );

    TIMER timer (
        .clk(clk), .reset(~rst_n), .irq(sb.timer_irq),
        .PADDR(s_if.paddr[11:0]), .PSEL(psel_s[1]), .PENABLE(s_if.penable), .PWRITE(s_if.pwrite),
        .PWDATA(s_if.pwdata), .PSTRB(s_if.pstrb), .PRDATA(prdata_s[63:32]), .PREADY(pready_s[1]),
        .PSLVERR(pslverr_s[1])
    );

    Mailbox mbox (
        .clk(clk), .reset(~rst_n), .irq_s(sb.mbox_irq_s), .irq_a(sb.mbox_irq_a),
        .s_PADDR(s_if.paddr[11:0]), .s_PSEL(psel_s[2]), .s_PENABLE(s_if.penable), .s_PWRITE(s_if.pwrite),
        .s_PWDATA(s_if.pwdata), .s_PSTRB(s_if.pstrb), .s_PRDATA(prdata_s[95:64]), .s_PREADY(pready_s[2]),
        .s_PSLVERR(pslverr_s[2]),
        .a_PADDR(a_if.paddr[11:0]), .a_PSEL(a_if.psel), .a_PENABLE(a_if.penable), .a_PWRITE(a_if.pwrite),
        .a_PWDATA(a_if.pwdata), .a_PSTRB(a_if.pstrb), .a_PRDATA(a_if.prdata), .a_PREADY(a_if.pready),
        .a_PSLVERR(a_if.pslverr)
    );

    apb_slave_model ram (
        .clk(clk), .reset(~rst_n),
        .PADDR(s_if.paddr[11:0]), .PSEL(psel_s[3]), .PENABLE(s_if.penable), .PWRITE(s_if.pwrite),
        .PWDATA(s_if.pwdata), .PSTRB(s_if.pstrb), .PRDATA(prdata_s[127:96]), .PREADY(pready_s[3]),
        .PSLVERR(pslverr_s[3])
    );

    // 5-cycle reset. +RESET_AT_NS=<t>: add a 5-cycle reset pulse after t ns (same as the other tops)
    initial begin
        int unsigned reset_at_ns;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        if ($value$plusargs("RESET_AT_NS=%d", reset_at_ns)) begin
            #(real'(reset_at_ns) * 1ns);
            @(negedge clk) rst_n = 1'b0;
            repeat (5) @(negedge clk);
            rst_n = 1'b1;
        end
    end

    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "s_vif", s_if);
        uvm_config_db#(virtual apb_if)::set(null, "*", "a_vif", a_if);
        uvm_config_db#(virtual apb_sb_if)::set(null, "*", "sb_vif", sb);
        run_test();
    end
endmodule
