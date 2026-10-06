module Data_Memory #(
    parameter MEM_SIZE = 1024 // 4KB
)(
    input             clk,
    input             MemWrite,
    input             MemRead,
    input      [31:0] addr,   
    input      [31:0] write_data,   
    output reg [31:0] read_data    
);

    reg [31:0] ram [0:MEM_SIZE-1];

    wire [29:0] word_addr = addr[31:2];

    assign read_data = ram[word_addr];

    always @(posedge clk) begin
        if (MemWrite) begin
            ram[word_addr] <= write_data;
        end
    end
        always @(*) begin
        if (MemRead) read_data = ram[word_addr];
        else read_data = 32'b0;
        end

endmodule