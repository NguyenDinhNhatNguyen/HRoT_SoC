// Boot ROM rieng cua Master Core (chua firmware secure_boot)
module Instruction_Memory #(
    parameter MEM_SIZE  = 1024, // 4KB
    parameter INIT_FILE = "../fw/build/secure_boot.hex"
)(
    input  wire [31:0] pc,
    output wire [31:0] instr
);

    reg [31:0] rom [0:MEM_SIZE-1];

    initial begin
        $readmemh(INIT_FILE, rom);
    end

    // CPU gui address byte (+4), ROM save word (+1) => chia 4 (>> 2 bit)
    // Doc to hop: core lay lenh cung chu ky voi PC
    assign instr = rom[pc[$clog2(MEM_SIZE)+1:2]];

endmodule
