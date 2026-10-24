// Master Core boot ROM (holds the secure boot firmware)
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

    // The CPU sends byte addresses and the ROM stores words, hence the >> 2.
    // Falling-edge synchronous read: PC is stable after the rising edge and the instruction is ready
    // before the next one, so the core still sees a same-cycle read, yet this infers M4K (Cyclone II)
    // or BRAM (Xilinx).
    always @(negedge clk)
        instr <= rom[pc[$clog2(MEM_SIZE)+1:2]];

endmodule
