`timescale 1ns / 1ps

// ============================================================
// ALU_tb - Testbench tu kiem tra cho ALU (Result, Zero, lt, ltu)
// ============================================================
module ALU_tb;

    reg  [31:0] A, B;
    reg  [3:0]  ALUControl;

    wire        Zero, lt, ltu;
    wire [31:0] Result;

    integer pass_count = 0, fail_count = 0;

    ALU u_ALU (
        .A(A), .B(B), .ALUControl(ALUControl),
        .Zero(Zero), .lt(lt), .ltu(ltu), .Result(Result)
    );

    // Dat dau vao, doi to hop on dinh, so Result va Zero
    task check;
        input [31:0]   a, b;
        input [3:0]    ctrl;
        input [31:0]   e_result;
        input [8*24:1] name;
        begin
            A = a; B = b; ALUControl = ctrl; #10;
            if ((Result === e_result) && (Zero === (e_result == 32'b0))) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : Result=%h", name, Result);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : Result=%h Zero=%b (expect %h)", name, Result, Zero, e_result);
            end
        end
    endtask

    // Co so sanh lt/ltu (dung cho BLT/BGE/BLTU/BGEU), doc lap voi ALUControl
    task check_cmp;
        input [31:0]   a, b;
        input          e_lt, e_ltu;
        input [8*24:1] name;
        begin
            A = a; B = b; ALUControl = 4'b0001; #10;
            if ((lt === e_lt) && (ltu === e_ltu)) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : lt=%b ltu=%b", name, lt, ltu);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : lt=%b ltu=%b (expect %b %b)", name, lt, ltu, e_lt, e_ltu);
            end
        end
    endtask

    initial begin
        $display("\n=== ALU TESTBENCH ===");

        // So hoc
        check(32'd150,        32'd50,         4'b0000, 32'd200,        "ADD");
        check(32'hFFFF_FFFF,  32'd1,          4'b0000, 32'h0,          "ADD tran -> Zero");
        check(32'd150,        32'd50,         4'b0001, 32'd100,        "SUB");
        check(32'd50,         32'd50,         4'b0001, 32'h0,          "SUB bang nhau -> Zero");
        check(32'd5,          32'd7,          4'b0001, 32'hFFFF_FFFE,  "SUB am");
        check(32'h0040_0000,  32'h0000_1234,  4'b1000, 32'h0040_1234,  "AUIPC (A+B)");

        // Logic
        check(32'hFFFF_0000,  32'h0F0F_0F0F,  4'b0010, 32'h0F0F_0000,  "AND");
        check(32'hFFFF_0000,  32'h0F0F_0F0F,  4'b0011, 32'hFFFF_0F0F,  "OR");
        check(32'hFFFF_0000,  32'h0F0F_0F0F,  4'b0100, 32'hF0F0_0F0F,  "XOR");

        // LUI: bo qua A
        check(32'h1234_5678,  32'hABCD_E000,  4'b1001, 32'hABCD_E000,  "LUI");

        // So sanh ghi ket qua
        check(-32'd10,        32'd5,          4'b0101, 32'd1,          "SLT  -10 < 5");
        check(32'd5,          -32'd10,        4'b0101, 32'd0,          "SLT  5 < -10");
        check(-32'd10,        32'd5,          4'b0110, 32'd0,          "SLTU 0xFFFFFFF6 < 5");
        check(32'd5,          -32'd10,        4'b0110, 32'd1,          "SLTU 5 < 0xFFFFFFF6");

        // Dich bit (chi dung B[4:0])
        check(32'h0000_0001,  32'd4,          4'b1010, 32'h0000_0010,  "SLL 4");
        check(32'h0000_0001,  32'd36,         4'b1010, 32'h0000_0010,  "SLL 36 -> 4");
        check(32'h0000_0001,  32'd31,         4'b1010, 32'h8000_0000,  "SLL 31");
        check(32'hF000_0000,  32'd4,          4'b1100, 32'h0F00_0000,  "SRL 4");
        check(32'hF000_0000,  32'd4,          4'b1011, 32'hFF00_0000,  "SRA 4 (giu dau)");
        check(32'h7000_0000,  32'd4,          4'b1011, 32'h0700_0000,  "SRA 4 (so duong)");

        // ALUControl khong dinh nghia -> 0
        check(32'd100,        32'd200,        4'b1111, 32'h0,          "Default -> 0");

        // Co lt/ltu cho lenh re nhanh
        check_cmp(32'd3,         32'd3,         1'b0, 1'b0, "cmp 3 vs 3");
        check_cmp(-32'd1,        32'd1,         1'b1, 1'b0, "cmp -1 vs 1");
        check_cmp(32'd1,         -32'd1,        1'b0, 1'b1, "cmp 1 vs -1");
        check_cmp(32'h8000_0000, 32'h7FFF_FFFF, 1'b1, 1'b0, "cmp INT_MIN vs MAX");

        $display("\nSUMMARY ALU: PASS = %0d | FAIL = %0d", pass_count, fail_count);
        $finish;
    end

endmodule
