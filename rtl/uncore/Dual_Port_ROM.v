module Dual_Port_ROM (
    input clk,
    
    // Port A:  App Core Fetch
    input [31:0] addrA,
    output reg [31:0] dataOutA,
    
    // Port B: Master Core Check
    input [31:0] addrB,
    output reg [31:0] dataOutB
);
    // ROM dung lượng 4KB (1024 words x 32-bit)
    reg [31:0] rom [0:1023];

    initial begin
        $readmemh("../fw/app_firmware.hex", rom);
    end

    always @(posedge clk) begin
        // << 2 bit (chia 4) do CPU Address = Byte-Addressable
        dataOutA <= rom[addrA[11:2]];
        dataOutB <= rom[addrB[11:2]];
    end
endmodule