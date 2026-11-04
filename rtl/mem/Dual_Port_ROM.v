// 4 KB read-only ROM, used as the Boot ROM and as the App ROM
// - Port A: instruction fetch (Master Core for the Boot ROM, App Core for the App ROM)
// - Port B: read-only AXI slave on the Master bus (loads, and hashing the App image)
// - Port C: Boot_Verifier fetch of the expected digest
module Dual_Port_ROM #(
    parameter INIT_FILE = "../fw/build/app_firmware.hex"
)(
    input             clk,
    // Port A: App Core fetch
    input      [31:0] addrA,
    output reg [31:0] dataOutA,

    // Port B: Master Core reads (over AXI)
    input      [31:0] addrB,
    output reg [31:0] dataOutB,

    // Port C: Boot_Verifier reads the expected digest (tie addrC to 0 when unused)
    input      [31:0] addrC,
    output reg [31:0] dataOutC
);
    // 4 KB (1024 x 32-bit words)
    reg [31:0] rom [0:1023];

    initial begin
        $readmemh(INIT_FILE, rom);
    end

    // Falling-edge synchronous read (same scheme as Data_Memory): maps to a dual-read-port M4K/BRAM
    // while the core still gets the instruction in the same cycle as its PC. The read path has
    // half a cycle (10 ns at 50 MHz). Addresses are byte addresses, hence the >> 2.
    always @(negedge clk) begin
        dataOutA <= rom[addrA[11:2]];
        dataOutB <= rom[addrB[11:2]];
        dataOutC <= rom[addrC[11:2]];
    end
endmodule
