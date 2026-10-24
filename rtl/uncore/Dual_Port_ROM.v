// ROM cua App Core
// - Port A: App Core Fetch
// - Port B: chi doc, noi lam Slave tren bus AXI cua Master de bam (hash) firmware App
module Dual_Port_ROM #(
    parameter INIT_FILE = "../fw/build/app_firmware.hex"
)(
    // Port A:  App Core Fetch
    input  [31:0] addrA,
    output [31:0] dataOutA,

    // Port B: Master Core Check (qua AXI)
    input  [31:0] addrB,
    output [31:0] dataOutB
);
    // ROM dung lượng 4KB (1024 words x 32-bit)
    reg [31:0] rom [0:1023];

    initial begin
        $readmemh(INIT_FILE, rom);
    end

    // Doc to hop: core lay lenh cung chu ky voi PC (IF_Stage khong co chu ky cho).
    // shortcut: doc to hop -> Vivado suy ra distributed ROM (LUT), khong phai BRAM; muon dung BRAM thi IF phai stall 1 chu ky.
    // << 2 bit (chia 4) do CPU Address = Byte-Addressable
    assign dataOutA = rom[addrA[11:2]];
    assign dataOutB = rom[addrB[11:2]];
endmodule
