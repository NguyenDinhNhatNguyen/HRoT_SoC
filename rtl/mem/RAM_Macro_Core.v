`timescale 1ns / 1ps
`default_nettype none

// RAM_Macro_Core: the 4 KB App RAM on one SRAM hard macro (sram_2k_macro) for the ASIC build.
// Same ports as Data_Memory plus stall. Used for app_ram, which sits right on the App Core, so the
// core waits through stall (bus_stall, I-09). The macro reads on the rising edge: Q is valid one
// cycle after the address, and it has one port and no byte write.
//
//   read          cycle 0: macro read, stall = 1.   cycle 1: read_data = Q, stall = 0
//   partial write cycle 0: macro reads the old word, stall = 1.
//   (SB, SH)      cycle 1: the written bytes are merged into Q and written back, stall = 0
//   full write    one cycle (wstrb = 4'hF), stall = 0. The Boot Guard zeroization uses this
//
// The core keeps the request and the address stable while stall = 1, so cycle 1 sees the same
// request as cycle 0. In cycle 1 of a read the macro is idle (CEN = 1), so Q holds.
// Q after a write cycle is not used: the model of the macro gives X and the real behavior is
// unknown. MemWrite and MemRead are never high together (one MEM stage access).
// rst clears done_q at once (asynchronous, like the other flops of the SoC) so the macro never sees
// an unknown control pin. Verilog-2001 only (Genus).
module RAM_Macro_Core (
    input  wire        clk,
    input  wire        rst,
    input  wire        MemWrite,
    input  wire        MemRead,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    input  wire [3:0]  wstrb,
    output wire [31:0] read_data,
    output wire        stall
);
    wire        full     = MemWrite & (wstrb == 4'hF);
    wire        part     = MemWrite & (wstrb != 4'hF);
    wire        two      = MemRead | part;          // needs the read cycle first
    reg         done_q;                             // cycle 0 of a two-cycle access is over
    wire        rd_cycle = two & ~done_q;
    wire        wr_cycle = full | (part & done_q);

    wire [31:0] q;
    wire [31:0] merged = {wstrb[3] ? write_data[31:24] : q[31:24],
                          wstrb[2] ? write_data[23:16] : q[23:16],
                          wstrb[1] ? write_data[15:8]  : q[15:8],
                          wstrb[0] ? write_data[7:0]   : q[7:0]};

    always @(posedge clk or posedge rst) begin
        if (rst) done_q <= 1'b0;
        else     done_q <= two & ~done_q;
    end

    sram_2k_macro u_macro (
        .CLK(clk),
        .CEN(rst | ~(rd_cycle | wr_cycle)),   // off while in reset: the control inputs may still be unknown then
        .WEN(~wr_cycle),
        .A(addr[11:2]),
        .D(part ? merged : write_data),
        .Q(q)
    );

    assign stall     = rd_cycle & ~rst;
    assign read_data = (MemRead & done_q) ? q : 32'b0;

    wire unused = &{1'b0, addr[31:12], addr[1:0]};
endmodule

`default_nettype wire
