module AXI4_Lite_Master (
    input             clk, reset,
    
    input             req_valid,
    input             req_write,
    input      [31:0] req_addr,
    input      [31:0] req_wdata,
    output reg        req_ready,
    output reg        resp_valid,
    output reg [31:0] resp_rdata,

    // AXI Write Address Channel
    output reg        M_AXI_AWVALID,
    input             M_AXI_AWREADY,
    output reg [31:0] M_AXI_AWADDR,
    
    // AXI Write Data Channel
    output reg        M_AXI_WVALID,
    input             M_AXI_WREADY,
    output reg [31:0] M_AXI_WDATA,
    
    // AXI Write Response Channel
    input             M_AXI_BVALID,
    output reg        M_AXI_BREADY,
    input      [1:0]  M_AXI_BRESP,
    
    // AXI Read Address Channel
    output reg        M_AXI_ARVALID,
    input             M_AXI_ARREADY,
    output reg [31:0] M_AXI_ARADDR,
    
    // AXI Read Data Channel
    input             M_AXI_RVALID,
    output reg        M_AXI_RREADY,
    input      [31:0] M_AXI_RDATA,
    input      [1:0]  M_AXI_RRESP
);

    // FSM điều khiển luồng Master
    localparam IDLE = 0, WRITE_ADDR_DATA = 1, WRITE_RESP = 2, READ_ADDR = 3, READ_DATA = 4;
    reg [2:0] state;

    always @(posedge clk) begin
        if (reset) begin
            state         <= IDLE; 
            req_ready     <= 1; 
            resp_valid    <= 0;
            M_AXI_AWVALID <= 0; 
            M_AXI_WVALID  <= 0; 
            M_AXI_BREADY  <= 0;
            M_AXI_ARVALID <= 0; 
            M_AXI_RREADY  <= 0;
        end else begin
            case (state)
                IDLE: begin
                    resp_valid <= 0;
                    if (req_valid && req_ready) begin
                        req_ready <= 0;
                        if (req_write) begin
                            M_AXI_AWADDR  <= req_addr; 
                            M_AXI_WDATA   <= req_wdata;
                            M_AXI_AWVALID <= 1; 
                            M_AXI_WVALID  <= 1;
                            state         <= WRITE_ADDR_DATA;
                        end else begin
                            M_AXI_ARADDR  <= req_addr; 
                            M_AXI_ARVALID <= 1;
                            state         <= READ_ADDR;
                        end
                    end
                end
                
                // Xử lý luồng Write
                WRITE_ADDR_DATA: begin
                    if (M_AXI_AWREADY) M_AXI_AWVALID <= 0;
                    if (M_AXI_WREADY)  M_AXI_WVALID  <= 0;
                    
                    if (!M_AXI_AWVALID && !M_AXI_WVALID) begin
                        M_AXI_BREADY <= 1; 
                        state        <= WRITE_RESP;
                    end
                end
                
                WRITE_RESP: begin
                    if (M_AXI_BVALID) begin
                        M_AXI_BREADY <= 0; 
                        resp_valid   <= 1; 
                        req_ready    <= 1; 
                        state        <= IDLE;
                    end
                end
                
                // Xử lý luồng READ
                READ_ADDR: begin
                    if (M_AXI_ARREADY) begin
                        M_AXI_ARVALID <= 0; 
                        M_AXI_RREADY  <= 1; 
                        state         <= READ_DATA;
                    end
                end
                
                READ_DATA: begin
                    if (M_AXI_RVALID) begin
                        resp_rdata   <= M_AXI_RDATA; 
                        M_AXI_RREADY <= 0;
                        resp_valid   <= 1; 
                        req_ready    <= 1; 
                        state        <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule