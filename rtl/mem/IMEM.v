`timescale 1ns / 1ps
`default_nettype none

// IMEM: 4 KB shared instruction memory of the two-world design (SoC_Memory_Map.md). One port, rising edge,
// full words only, so it maps to one block RAM or one SRAM macro. The port belongs to one side at a time:
//   released = 0 (Normal core in reset): zeroization first, then the Secure write, otherwise the Secure read
//     unlocked: the Secure side writes, reads answer rerr
//     locked  : the Secure side reads (data one cycle after reg_raddr), writes answer werr
//   released = 1: the Normal core fetches, every Secure access answers an error
// A new fetch address raises fetch_stall for one cycle (instr_stall, I-09). A fetch outside the 4 KB answers
// 32'h0, an illegal instruction, so it never wraps around to a stored word.
// rst only clears the fetch-valid flag, the words stay. Verilog-2001 only (Genus).
module IMEM (
    input  wire        clk,
    input  wire        rst,
    input  wire        released,        // the Normal core runs (~app_rst)

    // Normal side: fetch only, byte address as the core sees it (0 = first word)
    input  wire [31:0] fetch_addr,
    output wire [31:0] fetch_data,
    output wire        fetch_stall,

    // from SYSCSR
    input  wire        locked,          // IMEM_CTRL.LOCK
    input  wire        zero_en,         // Boot Guard zeroization
    input  wire [9:0]  zero_addr,

    // Secure side, register port of AXI4_Lite_Slave_Template. The 4 KB window is decoded outside
    input  wire        reg_wen,
    input  wire [31:0] reg_waddr,
    input  wire [31:0] reg_wdata,
    input  wire [3:0]  reg_wstrb,
    input  wire [31:0] reg_raddr,
    output wire [31:0] reg_rdata,
    output wire        werr,
    output wire        rerr
);
    assign werr = reg_wen & (locked | released | (reg_wstrb != 4'hF));
    assign rerr = ~locked | released;

    wire       wr_secure = reg_wen & ~werr;
    wire       wr        = zero_en | wr_secure;
    wire [9:0] a         = zero_en  ? zero_addr :
                           released ? fetch_addr[11:2] :
                           reg_wen  ? reg_waddr[11:2] : reg_raddr[11:2];
    wire [31:0] d        = zero_en ? 32'b0 : reg_wdata;

    reg [31:0] ram [0:1023];
    reg [31:0] q;
    always @(posedge clk) begin
        if (wr)
            ram[a] <= d;
        q <= ram[a];
    end

    // The word in q belongs to the address fa_q once the fetch side has had the port for one cycle
    reg        valid_q;
    reg [29:0] fa_q;
    always @(posedge clk or posedge rst) begin
        if (rst) valid_q <= 1'b0;
        else     valid_q <= released & ~zero_en;
    end
    always @(posedge clk) begin
        fa_q <= fetch_addr[31:2];
    end

    wire in_range = (fa_q[29:10] == 20'b0);

    assign fetch_stall = released & ~(valid_q & (fa_q == fetch_addr[31:2]));
    assign fetch_data  = (released & in_range) ? q : 32'b0;
    assign reg_rdata   = rerr ? 32'b0 : q;     // fetched words never show on the Secure bus

    wire unused = &{1'b0, fetch_addr[1:0], reg_waddr[31:12], reg_waddr[1:0], reg_raddr[31:12], reg_raddr[1:0]};
endmodule

`default_nettype wire
