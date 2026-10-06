module AXI4_Lite_Slave_Template (
    input             clk, reset,
    
    // AXI Write Address Channel
    input             S_AXI_AWVALID,
    output reg        S_AXI_AWREADY,
    input      [31:0] S_AXI_AWADDR,
    
    // AXI Write Data Channel
    input             S_AXI_WVALID,
    output reg        S_AXI_WREADY,
    input      [31:0] S_AXI_WDATA,
    
    // AXI Write Response Channel
    output reg        S_AXI_BVALID,
    input             S_AXI_BREADY,
    
    // AXI Read Address Channel
    input             S_AXI_ARVALID,
    output reg        S_AXI_ARREADY,
    input      [31:0] S_AXI_ARADDR,
    
    // AXI Read Data Channel
    output reg        S_AXI_RVALID,
    input             S_AXI_RREADY,
    output reg [31:0] S_AXI_RDATA
);

localparam IDLE = 2'b00, ACTIVE = 2'b01, RESP = 2'b10;
    reg [1:0] w_state, r_state;

    // Máy trạng thái luồng Write
    always @(posedge clk) begin
        if (reset) begin
            w_state <= IDLE;
            S_AXI_AWREADY <= 0;
            S_AXI_WREADY <= 0;
            S_AXI_BVALID <= 0;
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
                    S_AXI_BRESP <= 2'b00; // OKAY
                    w_state <= RESP;
                end
                RESP: begin
                    if (S_AXI_BREADY) begin
                        S_AXI_BVALID <= 0;
                        w_state <= IDLE;
                    end
                end
            endcase
        end
    end

    // Máy trạng thái luồng Read 
    always @(posedge clk) begin
        if (reset) begin
            r_state <= IDLE;
            S_AXI_ARREADY <= 0;
            S_AXI_RVALID <= 0;
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
                    S_AXI_RRESP <= 2'b00;
                    // S_AXI_RDATA <= [Dữ liệu từ Memory/Register];
                    r_state <= RESP;
                end
                RESP: begin
                    if (S_AXI_RREADY) begin
                        S_AXI_RVALID <= 0;
                        r_state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule