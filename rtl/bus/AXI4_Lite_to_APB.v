`timescale 1ns / 1ps

// AXI4-Lite (slave) to APB4 (master) bridge
// - One transaction at a time, and a pending write wins over a pending read
// - APB: SETUP (PSEL=1, PENABLE=0), then ACCESS (PENABLE=1) until PREADY
// - PSLVERR is returned as SLVERR on BRESP/RRESP
module AXI4_Lite_to_APB (
    input             clk, reset,

    // AXI4-Lite slave
    input             S_AXI_AWVALID,
    output            S_AXI_AWREADY,
    input      [31:0] S_AXI_AWADDR,
    input             S_AXI_WVALID,
    output            S_AXI_WREADY,
    input      [31:0] S_AXI_WDATA,
    input      [3:0]  S_AXI_WSTRB,
    output            S_AXI_BVALID,
    input             S_AXI_BREADY,
    output     [1:0]  S_AXI_BRESP,
    input             S_AXI_ARVALID,
    output            S_AXI_ARREADY,
    input      [31:0] S_AXI_ARADDR,
    output            S_AXI_RVALID,
    input             S_AXI_RREADY,
    output     [31:0] S_AXI_RDATA,
    output     [1:0]  S_AXI_RRESP,

    // APB4 master
    output     [31:0] PADDR,
    output            PSEL,
    output            PENABLE,
    output            PWRITE,
    output     [31:0] PWDATA,
    output     [3:0]  PSTRB,
    input      [31:0] PRDATA,
    input             PREADY,
    input             PSLVERR
);
    localparam IDLE = 3'd0, SETUP = 3'd1, ACCESS = 3'd2, WRESP = 3'd3, RRESP = 3'd4;
    reg [2:0]  state;
    reg [31:0] addr_q, wdata_q, rdata_q;
    reg [3:0]  strb_q;
    reg        write_q, err_q;

    wire take_w = (state == IDLE) && S_AXI_AWVALID && S_AXI_WVALID;
    wire take_r = (state == IDLE) && S_AXI_ARVALID && !(S_AXI_AWVALID && S_AXI_WVALID);

    // READY may depend on VALID in AXI (the reverse is what's forbidden)
    assign S_AXI_AWREADY = take_w;
    assign S_AXI_WREADY  = take_w;
    assign S_AXI_ARREADY = take_r;

    assign S_AXI_BVALID = (state == WRESP);
    assign S_AXI_BRESP  = err_q ? 2'b10 : 2'b00;
    assign S_AXI_RVALID = (state == RRESP);
    assign S_AXI_RDATA  = rdata_q;
    assign S_AXI_RRESP  = err_q ? 2'b10 : 2'b00;

    assign PADDR   = addr_q;
    assign PSEL    = (state == SETUP) || (state == ACCESS);
    assign PENABLE = (state == ACCESS);
    assign PWRITE  = write_q;
    assign PWDATA  = wdata_q;
    assign PSTRB   = write_q ? strb_q : 4'b0000;   // APB4: PSTRB must be 0 on reads

    always @(posedge clk) begin
        if (reset) begin
            state   <= IDLE;
            addr_q  <= 32'b0;
            wdata_q <= 32'b0;
            rdata_q <= 32'b0;
            strb_q  <= 4'b0;
            write_q <= 1'b0;
            err_q   <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (take_w) begin
                        addr_q  <= S_AXI_AWADDR;
                        wdata_q <= S_AXI_WDATA;
                        strb_q  <= S_AXI_WSTRB;
                        write_q <= 1'b1;
                        state   <= SETUP;
                    end else if (take_r) begin
                        addr_q  <= S_AXI_ARADDR;
                        write_q <= 1'b0;
                        state   <= SETUP;
                    end
                end
                SETUP:
                    state <= ACCESS;
                ACCESS: begin
                    if (PREADY) begin
                        rdata_q <= PRDATA;
                        err_q   <= PSLVERR;
                        state   <= write_q ? WRESP : RRESP;
                    end
                end
                WRESP:
                    if (S_AXI_BREADY)
                        state <= IDLE;
                RRESP:
                    if (S_AXI_RREADY)
                        state <= IDLE;
                default:
                    state <= IDLE;
            endcase
        end
    end
endmodule
