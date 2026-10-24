// App Core ROM
// - Port A: App Core instruction fetch
// - Port B: read-only AXI slave on the Master bus, used to hash the App firmware
module Dual_Port_ROM #(
    parameter INIT_FILE = "../fw/build/app_firmware.hex"
)(
    input             clk,
    // Port A: App Core fetch
    input      [31:0] addrA,
    output reg [31:0] dataOutA,

    // Port B: Master Core reads (over AXI)
    input      [31:0] addrB,
    output reg [31:0] dataOutB
);
    // 4 KB (1024 x 32-bit words)
    reg [31:0] rom [0:1023];

    initial begin
        $readmemh(INIT_FILE, rom);
    end

    // Falling-edge synchronous read (see Instruction_Memory): maps to a dual-read-port M4K/BRAM
    // while the core still gets the instruction in the same cycle as its PC. The read path has
    // half a cycle (10 ns at 50 MHz). Addresses are byte addresses, hence the >> 2.
    always @(negedge clk) begin
        dataOutA <= rom[addrA[11:2]];
        dataOutB <= rom[addrB[11:2]];
    end
endmodule
