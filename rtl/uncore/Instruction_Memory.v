module Instruction_Memory #(
    parameter MEM_SIZE = 1024 // 4KB
)(
    input  wire [31:0] addr_i,
    output wire [31:0] inst_o
);

    reg [31:0] rom [0:MEM_SIZE-1];

        initial begin
        // File firmware.txt do Makefile sinh ra
        $readmemh("../fw/firmware.txt", rom);
    end

    // CPU gui address byte (+4), ROM save word (+1) => addr_i chia 4 (>> 2 bit)
    assign inst_o = rom[addr_i[31:2]];

endmodule