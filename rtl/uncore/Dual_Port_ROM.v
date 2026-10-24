// ROM cua App Core
// - Port A: App Core Fetch
// - Port B: chi doc, noi lam Slave tren bus AXI cua Master de bam (hash) firmware App
module Dual_Port_ROM #(
    parameter INIT_FILE = "../fw/build/app_firmware.hex"
)(
    input             clk,
    // Port A:  App Core Fetch
    input      [31:0] addrA,
    output reg [31:0] dataOutA,

    // Port B: Master Core Check (qua AXI)
    input      [31:0] addrB,
    output reg [31:0] dataOutB
);
    // ROM dung lượng 4KB (1024 words x 32-bit)
    reg [31:0] rom [0:1023];

    initial begin
        $readmemh(INIT_FILE, rom);
    end

    // Doc dong bo o canh xuong (xem Instruction_Memory): dung M4K/BRAM 2 cong doc,
    // core van nhan lenh trong cung chu ky voi PC. Duong doc con nua chu ky (10 ns @ 50 MHz).
    // << 2 bit (chia 4) do CPU Address = Byte-Addressable
    always @(negedge clk) begin
        dataOutA <= rom[addrA[11:2]];
        dataOutB <= rom[addrB[11:2]];
    end
endmodule
