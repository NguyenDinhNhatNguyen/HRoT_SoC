module Reset_Controller (
    input        clk, reset,
    // Cổng kết nối với bus AXI của Master Core
    input        axi_wen,
    input [31:0] axi_wdata,
    // Cổng điều khiển App Core
    output reg   app_core_reset_n
);
    // Mặc định App Core locked Reset(0) 
    always @(posedge clk) begin
        if (reset) begin
            app_core_reset_n <= 1'b0; 
        end else if (axi_wen && (axi_wdata == 32'h00000001)) begin
            // Master Core ghi 1 vào Reg này => App Core nhả Reset(1)
            app_core_reset_n <= 1'b1;
        end
    end
endmodule