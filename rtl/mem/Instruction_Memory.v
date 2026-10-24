// Boot ROM rieng cua Master Core (chua firmware secure_boot)
module Instruction_Memory #(
    parameter MEM_SIZE  = 1024, // 4KB
    parameter INIT_FILE = "../fw/build/firmware_imem.hex"
)(
    input  wire        clk,
    input  wire [31:0] pc,
    output reg  [31:0] instr
);

    reg [31:0] rom [0:MEM_SIZE-1];

    initial begin
        $readmemh(INIT_FILE, rom);
    end

    // CPU gui address byte (+4), ROM save word (+1) => chia 4 (>> 2 bit)
    // Doc dong bo o canh xuong: PC on dinh sau canh len, lenh co truoc canh len ke tiep
    // -> core van thay "doc trong cung chu ky", nhung suy ra duoc M4K (Cyclone II) / BRAM (Xilinx)
    always @(negedge clk)
        instr <= rom[pc[$clog2(MEM_SIZE)+1:2]];

endmodule
