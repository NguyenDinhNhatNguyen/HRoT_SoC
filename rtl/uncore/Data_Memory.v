module Data_Memory #(
    parameter MEM_SIZE  = 1024, // 4KB
    parameter INIT_FILE = ""    // vd: firmware_dmem.hex (.rodata/.data), rong = khong nap
)(
    input             clk,
    input             MemWrite,
    input             MemRead,
    input      [31:0] addr,
    input      [31:0] write_data,
    input      [3:0]  wstrb,        // byte lane ghi (SB/SH/SW)
    output reg [31:0] read_data
);

    reg [31:0] ram [0:MEM_SIZE-1];

    // Chi lay so bit vua MEM_SIZE, tranh index vuot mang (ra X khi mo phong)
    wire [$clog2(MEM_SIZE)-1:0] word_addr = addr[$clog2(MEM_SIZE)+1:2];

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, ram);
    end

    always @(posedge clk) begin
        if (MemWrite) begin
            if (wstrb[0]) ram[word_addr][7:0]   <= write_data[7:0];
            if (wstrb[1]) ram[word_addr][15:8]  <= write_data[15:8];
            if (wstrb[2]) ram[word_addr][23:16] <= write_data[23:16];
            if (wstrb[3]) ram[word_addr][31:24] <= write_data[31:24];
        end
    end

    always @(*) begin
        if (MemRead) read_data = ram[word_addr];
        else read_data = 32'b0;
    end

endmodule
