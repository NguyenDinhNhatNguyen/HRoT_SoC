`timescale 1ns / 1ps

// Extend_tb - Testbench tu kiem tra mo rong immediate (I/S/B/J/U)
module Extend_tb;

    reg  [31:0] Instr;
    reg  [1:0]  ImmSrc;
    wire [31:0] ImmExt;

    integer pass_count = 0, fail_count = 0;

    Extend u_Extend (.Instr(Instr), .ImmSrc(ImmSrc), .ImmExt(ImmExt));

    task check;
        input [31:0]   instr;
        input [1:0]    src;
        input [31:0]   e_imm;
        input [8*24:1] name;
        begin
            Instr = instr; ImmSrc = src; #10;
            if (ImmExt === e_imm) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : ImmExt=%h", name, ImmExt);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : ImmExt=%h (expect %h)", name, ImmExt, e_imm);
            end
        end
    endtask

    initial begin
        $display("\n=== EXTEND TESTBENCH ===");

        // U-type: opcode quyet dinh, ImmSrc bo qua
        check(32'h1234_5037, 2'b00, 32'h1234_5000, "LUI 0x12345");
        check(32'hABCD_E017, 2'b11, 32'hABCD_E000, "AUIPC 0xABCDE");

        // I-type: imm = Instr[31:20]
        check(32'h00F0_0013, 2'b00, 32'h0000_000F, "I  +15");
        check(32'hFFF0_0013, 2'b00, 32'hFFFF_FFFF, "I  -1");
        check(32'h8000_0013, 2'b00, 32'hFFFF_F800, "I  -2048");

        // S-type: imm = {Instr[31:25], Instr[11:7]}
        check(32'hFE00_0FA3, 2'b01, 32'hFFFF_FFFF, "S  -1");
        check(32'h0200_04A3, 2'b01, 32'h0000_0029, "S  +41");

        // B-type: imm = {Instr[31], Instr[7], Instr[30:25], Instr[11:8], 0}
        check(32'hFE00_0FE3, 2'b10, 32'hFFFF_FFFE, "B  -2");
        check(32'h0000_0463, 2'b10, 32'h0000_0008, "B  +8");
        check(32'h0000_00E3, 2'b10, 32'h0000_0800, "B  +2048 (bit 11)");

        // J-type: imm = {Instr[31], Instr[19:12], Instr[20], Instr[30:21], 0}
        check(32'h8000_006F, 2'b11, 32'hFFF0_0000, "J  -1048576");
        check(32'h00C0_006F, 2'b11, 32'h0000_000C, "J  +12");
        check(32'h0010_006F, 2'b11, 32'h0000_0800, "J  +2048 (bit 11)");
        check(32'h0000_106F, 2'b11, 32'h0000_1000, "J  +4096 (bit 12)");

        $display("\nSUMMARY EXTEND: PASS = %0d | FAIL = %0d", pass_count, fail_count);
        $finish;
    end

endmodule
