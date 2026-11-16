`timescale 1ns / 1ps
`default_nettype none

// RAM_Macro_Axi: the 4 KB Master RAM on one SRAM hard macro (sram_2k_macro) for the ASIC build.
// It sits behind AXI4_Lite_Slave_Template, which has no wait signal, so the macro read delay is
// hidden in cycles the template already spends:
//   read   cycle 0 (template IDLE, ARVALID high): the macro reads raddr, and it keeps reading raddr
//          every cycle that has no write. Cycle 1 (ACTIVE): the template samples Q into RDATA
//   write  cycle 1 (ACTIVE, reg_wen = 1): a full word (wstrb = 4'hF) is written at once.
//          A partial word (SB, SH) reads the old word in this cycle and keeps address, data and
//          strobes. Cycle 2 (RESP): the bytes are merged into Q and written back
// The next AXI transaction can start in cycle 3 at the earliest, because SoC_Top starts a request
// only when the slave is idle and has no response pending (bus_idle), so cycle 2 is free.
// Q after a write cycle is not used (model gives X, real macro unknown).
// rst clears pend_q at once (asynchronous, like the other flops of the SoC) so the macro never sees
// an unknown control pin. Verilog-2001 only (Genus).
module RAM_Macro_Axi (
    input  wire        clk,
    input  wire        rst,
    input  wire        reg_wen,
    input  wire [31:0] reg_waddr,
    input  wire [31:0] reg_wdata,
    input  wire [3:0]  reg_wstrb,
    input  wire [31:0] reg_raddr,
    output wire [31:0] reg_rdata
);
    wire        part = reg_wen & (reg_wstrb != 4'hF);
    wire        full = reg_wen & (reg_wstrb == 4'hF);

    reg         pend_q;                 // cycle 2 of a partial write
    reg  [9:0]  a_q;
    reg  [31:0] d_q;
    reg  [3:0]  s_q;
    always @(posedge clk or posedge rst) begin
        if (rst) pend_q <= 1'b0;
        else     pend_q <= part;
    end
    always @(posedge clk) begin
        if (part) begin
            a_q <= reg_waddr[11:2];
            d_q <= reg_wdata;
            s_q <= reg_wstrb;
        end
    end

    wire [31:0] q;
    wire [31:0] merged = {s_q[3] ? d_q[31:24] : q[31:24],
                          s_q[2] ? d_q[23:16] : q[23:16],
                          s_q[1] ? d_q[15:8]  : q[15:8],
                          s_q[0] ? d_q[7:0]   : q[7:0]};
    wire        wr = pend_q | full;

    sram_2k_macro u_macro (
        .CLK(clk),
        .CEN(rst),                  // off while in reset: the control inputs may still be unknown then
        .WEN(~wr),
        .A(pend_q ? a_q : (reg_wen ? reg_waddr[11:2] : reg_raddr[11:2])),
        .D(pend_q ? merged : reg_wdata),
        .Q(q)
    );

    assign reg_rdata = q;

    wire unused = &{1'b0, reg_waddr[31:12], reg_waddr[1:0], reg_raddr[31:12], reg_raddr[1:0]};
endmodule

`default_nettype wire
