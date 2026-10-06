module Instruction_Memory #(
    parameter MEM_SIZE = 1024 // 4KB
)(
    input  wire [31:0] pc,
    output wire [31:0] instr
);

    reg [31:0] rom [0:MEM_SIZE-1];

        initial begin
        // File firmware.txt do Makefile sinh ra
        $readmemh("../fw/firmware.txt", rom);
    end

    // CPU gui address byte (+4), ROM save word (+1) => addr_i chia 4 (>> 2 bit)
    assign instr = rom[pc[31:2]];

endmodule