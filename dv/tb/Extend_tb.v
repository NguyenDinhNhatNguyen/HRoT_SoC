`timescale 1ns / 1ps

module Extend_tb;

    // Khai bao tin hieu
    reg  [31:0] Instr;
    reg  [1:0]  ImmSrc;
    wire [31:0] ImmExt;

    // Instantiate module Extend
    Extend u_Extend (
        .Instr(Instr),
        .ImmSrc(ImmSrc),
        .ImmExt(ImmExt)
    );

    initial begin
        $display("===============================================================");
        $display("                     BAT DAU TEST EXTEND                       ");
        $display("===============================================================");
        $display("Loai Lenh | ImmSrc | Instr (Hex) | ImmExt (Hex)  | Ghi chu");
        $display("---------------------------------------------------------------");

        // 1. U-Type (LUI) - Opcode = 0110111
        // Lay 20 bit cao, dien 12 bit 0 vao cuoi. ImmSrc khong quan trong.
        Instr = 32'h1234_5037; ImmSrc = 2'bxx; #10;
        $display("U-Type    |   %b   |  %h   |  %h   | LUI (0x12345000)", ImmSrc, Instr, ImmExt);

        // 2. U-Type (AUIPC) - Opcode = 0010111
        Instr = 32'hABCD_E017; ImmSrc = 2'bxx; #10;
        $display("U-Type    |   %b   |  %h   |  %h   | AUIPC (0xABCDE000)", ImmSrc, Instr, ImmExt);

        // 3. I-Type (ADDI) - ImmSrc = 00
        // So duong: Imm[31:20] = 0x00F
        Instr = 32'h00F0_0000; ImmSrc = 2'b00; #10;
        $display("I-Type (+)  |   %b   |  %h   |  %h   | Imm = 15 (0x00F)", ImmSrc, Instr, ImmExt);

        // So am: Imm[31:20] = 0xFFF (-1) -> Mo rong dau thanh 0xFFFFFFFF
        Instr = 32'hFFF0_0000; ImmSrc = 2'b00; #10;
        $display("I-Type (-)  |   %b   |  %h   |  %h   | Imm = -1 (0xFFF)", ImmSrc, Instr, ImmExt);

        // 4. S-Type (SW) - ImmSrc = 01
        // Imm = 0xFFF (-1): Instr[31:25] = 0x7F, Instr[11:7] = 0x1F
        Instr = 32'hFE00_0F80; ImmSrc = 2'b01; #10;
        $display("S-Type (-)  |   %b   |  %h   |  %h   | Imm = -1", ImmSrc, Instr, ImmExt);

        // 5. B-Type (BEQ) - ImmSrc = 10
        // Imm = -2 (0xFFFFFFFE): Bit0 luon = 0, cac bit con lai la 1
        Instr = 32'hFE00_0F80; ImmSrc = 2'b10; #10;
        $display("B-Type (-)  |   %b   |  %h   |  %h   | Imm = -2", ImmSrc, Instr, ImmExt);

        // 6. J-Type (JAL) - ImmSrc = 11
        // Kiem tra mo rong dau cho buoc nhay xa (J-type)
        Instr = 32'h8000_0000; ImmSrc = 2'b11; #10;
        $display("J-Type (-)  |   %b   |  %h   |  %h   | Mo rong bit dau", ImmSrc, Instr, ImmExt);

        $display("===============================================================");
        $display("                       KET THUC TEST                           ");
        $display("===============================================================");
        $stop;
    end

endmodule