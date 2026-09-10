module Data_Memory #(
    parameter MEM_SIZE = 1024 // 4KB
)(
    input  wire        clk_i,
    input  wire        we_i,     
    input  wire [31:0] addr_i,   
    input  wire [31:0] data_w,   
    output wire [31:0] data_r    
);

    reg [31:0] ram [0:MEM_SIZE-1];

    wire [29:0] word_addr = addr_i[31:2];

    assign data_r = ram[word_addr];

    always @(posedge clk_i) begin
        if (we_i) begin
            ram[word_addr] <= data_w;
        end
    end

endmodule