module Data_Memory #(
    parameter MEM_SIZE  = 1024, // 4KB
    parameter INIT_FILE = ""    // e.g. firmware_dmem.hex (.rodata/.data), empty = no preload
)(
    input             clk,
    input             MemWrite,
    input             MemRead,
    input      [31:0] addr,
    input      [31:0] write_data,
    input      [3:0]  wstrb,        // write byte lanes (SB/SH/SW)
    output reg [31:0] read_data
);

    reg [31:0] ram [0:MEM_SIZE-1];

    // Use only as many address bits as MEM_SIZE needs, so the index never runs past the array (X in sim)
    wire [$clog2(MEM_SIZE)-1:0] word_addr = addr[$clog2(MEM_SIZE)+1:2];

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, ram);
    end

    // Read and write on the falling edge: address and data from the rising-edge pipeline registers
    // are stable by then, and read data is ready before the next rising edge. This infers M4K/BRAM
    // without touching the core.
    reg [31:0] q;
    always @(negedge clk) begin
        q <= ram[word_addr];
        if (MemWrite) begin
            if (wstrb[0]) ram[word_addr][7:0]   <= write_data[7:0];
            if (wstrb[1]) ram[word_addr][15:8]  <= write_data[15:8];
            if (wstrb[2]) ram[word_addr][23:16] <= write_data[23:16];
            if (wstrb[3]) ram[word_addr][31:24] <= write_data[31:24];
        end
    end

    always @(*) begin
        if (MemRead) read_data = q;
        else read_data = 32'b0;
    end

endmodule
