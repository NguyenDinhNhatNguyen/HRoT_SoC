// Generic AXI4-Lite slave. It handles the AXI handshakes and exposes a plain register port:
// reg_wen/reg_waddr/reg_wdata for writes, reg_raddr/reg_rdata (combinational) for reads.
// RAM, App ROM port B, SHA-256 and the default slave all sit behind one of these.
module AXI4_Lite_Slave_Template #(
    parameter [1:0] WRESP = 2'b00,  // 00 OKAY, 10 SLVERR (e.g. write to ROM), 11 DECERR (default slave)
    parameter [1:0] RRESP = 2'b00
)(
    input             clk, reset,

    // AXI Write Address Channel
    input             S_AXI_AWVALID,
    output reg        S_AXI_AWREADY,
    input      [31:0] S_AXI_AWADDR,

    // AXI Write Data Channel
    input             S_AXI_WVALID,
    output reg        S_AXI_WREADY,
    input      [31:0] S_AXI_WDATA,
    input      [3:0]  S_AXI_WSTRB,

    // AXI Write Response Channel
    output reg        S_AXI_BVALID,
    input             S_AXI_BREADY,
    output reg [1:0]  S_AXI_BRESP,

    // AXI Read Address Channel
    input             S_AXI_ARVALID,
    output reg        S_AXI_ARREADY,
    input      [31:0] S_AXI_ARADDR,

    // AXI Read Data Channel
    output reg        S_AXI_RVALID,
    input             S_AXI_RREADY,
    output reg [31:0] S_AXI_RDATA,
    output reg [1:0]  S_AXI_RRESP,

    // Register port towards the peripheral
    output            reg_wen,      // one-cycle pulse when the write handshake completes
    output     [31:0] reg_waddr,
    output     [31:0] reg_wdata,
    output     [3:0]  reg_wstrb,    // write byte lanes
    output     [31:0] reg_raddr,
    input      [31:0] reg_rdata     // combinational read of reg_raddr
);

localparam IDLE = 2'b00, ACTIVE = 2'b01, RESP = 2'b10;
    reg [1:0] w_state, r_state;

    // The master holds AWADDR/WDATA/ARADDR stable for the whole transaction
    assign reg_wen   = S_AXI_AWVALID & S_AXI_AWREADY & S_AXI_WVALID & S_AXI_WREADY;
    assign reg_waddr = S_AXI_AWADDR;
    assign reg_wdata = S_AXI_WDATA;
    assign reg_wstrb = S_AXI_WSTRB;
    assign reg_raddr = S_AXI_ARADDR;

    // Write channel FSM
    always @(posedge clk) begin
        if (reset) begin
            w_state <= IDLE;
            S_AXI_AWREADY <= 0;
            S_AXI_WREADY <= 0;
            S_AXI_BVALID <= 0;
            S_AXI_BRESP <= 2'b00;
        end else begin
            case (w_state)
                IDLE: begin
                    if (S_AXI_AWVALID && S_AXI_WVALID) begin
                        S_AXI_AWREADY <= 1;
                        S_AXI_WREADY <= 1;
                        w_state <= ACTIVE;
                    end
                end
                ACTIVE: begin
                    S_AXI_AWREADY <= 0;
                    S_AXI_WREADY <= 0;
                    S_AXI_BVALID <= 1;
                    S_AXI_BRESP <= WRESP;
                    w_state <= RESP;
                end
                RESP: begin
                    if (S_AXI_BREADY) begin
                        S_AXI_BVALID <= 0;
                        w_state <= IDLE;
                    end
                end
                default: w_state <= IDLE;
            endcase
        end
    end

    // Read channel FSM
    always @(posedge clk) begin
        if (reset) begin
            r_state <= IDLE;
            S_AXI_ARREADY <= 0;
            S_AXI_RVALID <= 0;
            S_AXI_RDATA <= 32'b0;
            S_AXI_RRESP <= 2'b00;
        end else begin
            case (r_state)
                IDLE: begin
                    if (S_AXI_ARVALID) begin
                        S_AXI_ARREADY <= 1;
                        r_state <= ACTIVE;
                    end
                end
                ACTIVE: begin
                    S_AXI_ARREADY <= 0;
                    S_AXI_RVALID <= 1;
                    S_AXI_RRESP <= RRESP;
                    S_AXI_RDATA <= reg_rdata;
                    r_state <= RESP;
                end
                RESP: begin
                    if (S_AXI_RREADY) begin
                        S_AXI_RVALID <= 0;
                        r_state <= IDLE;
                    end
                end
                default: r_state <= IDLE;
            endcase
        end
    end
endmodule
