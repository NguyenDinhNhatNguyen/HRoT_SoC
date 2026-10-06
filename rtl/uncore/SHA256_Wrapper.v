module SHA256_Wrapper (
    input             clk, reset,
    // Port AXI4-Lite (Nối vào Master Core)
    input             S_AXI_AWVALID, 
    output            S_AXI_AWREADY, 
    input      [31:0] S_AXI_AWADDR,
    input             S_AXI_WVALID, 
    output            S_AXI_WREADY, 
    input      [31:0] S_AXI_WDATA,
    input             S_AXI_ARVALID, 
    output            S_AXI_ARREADY, 
    input      [31:0] S_AXI_ARADDR,
    output reg        S_AXI_RVALID, 
    output reg [31:0] S_AXI_RDATA
);
    reg start; 
    wire done; 
    wire [255:0] hash_out; 
    reg [511:0] block_in;
    
    SHA256_Core core_inst (
        .clk(clk), 
        .reset(reset), 
        .start(start), 
        .block_in(block_in), 
        .hash_out(hash_out), 
        .done(done)
    );

    always @(posedge clk) begin
        if (S_AXI_WVALID && S_AXI_AWVALID) begin
            if (S_AXI_AWADDR[7:0] == 8'h40) 
                start <= S_AXI_WDATA[0];
            else if (S_AXI_AWADDR[7:0] == 8'h00) 
                block_in[31:0] <= S_AXI_WDATA;
        end else start <= 0;
    end

    always @(posedge clk) begin
        if (S_AXI_ARVALID) begin
            S_AXI_RVALID <= 1;
            if (S_AXI_ARADDR[7:0] == 8'h44) 
                S_AXI_RDATA <= {31'b0, done};
            else if (S_AXI_ARADDR[7:0] == 8'h50) 
                S_AXI_RDATA <= hash_out[255:224];
        end else S_AXI_RVALID <= 0;
    end
endmodule