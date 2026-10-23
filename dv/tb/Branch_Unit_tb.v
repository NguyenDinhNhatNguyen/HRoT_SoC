`timescale 1ns / 1ps

// ============================================================
// Branch_Unit_tb - Testbench tu kiem tra: 6 lenh B-type x (taken/not taken), JAL, JALR
// ============================================================
module Branch_Unit_tb;

    reg       Branch, Jump, Jalr;
    reg [2:0] funct3;
    reg       Zero, lt, ltu;

    wire      PCSrc;

    integer pass_count = 0, fail_count = 0;

    Branch_Unit u_BU (
        .Branch(Branch), .Jump(Jump), .Jalr(Jalr),
        .funct3(funct3), .Zero(Zero), .lt(lt), .ltu(ltu),
        .PCSrc(PCSrc)
    );

    task check;
        input          br, j, jr;
        input [2:0]    f3;
        input          z, l, lu;
        input          e_pcsrc;
        input [8*24:1] name;
        begin
            Branch = br; Jump = j; Jalr = jr; funct3 = f3; Zero = z; lt = l; ltu = lu; #10;
            if (PCSrc === e_pcsrc) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : PCSrc=%b", name, PCSrc);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : PCSrc=%b (expect %b)", name, PCSrc, e_pcsrc);
            end
        end
    endtask

    initial begin
        $display("\n=== BRANCH UNIT TESTBENCH ===");
        //     Br J  Jr funct3  Z  lt ltu  PCSrc
        check(0, 0, 0, 3'b000, 1, 1, 1,   0, "Lenh thuong");
        check(1, 0, 0, 3'b000, 1, 0, 0,   1, "BEQ  bang");
        check(1, 0, 0, 3'b000, 0, 0, 0,   0, "BEQ  khac");
        check(1, 0, 0, 3'b001, 0, 0, 0,   1, "BNE  khac");
        check(1, 0, 0, 3'b001, 1, 0, 0,   0, "BNE  bang");
        check(1, 0, 0, 3'b100, 0, 1, 0,   1, "BLT  nho hon");
        check(1, 0, 0, 3'b100, 0, 0, 1,   0, "BLT  khong nho");
        check(1, 0, 0, 3'b101, 0, 0, 1,   1, "BGE  lon/bang");
        check(1, 0, 0, 3'b101, 0, 1, 0,   0, "BGE  nho hon");
        check(1, 0, 0, 3'b110, 0, 0, 1,   1, "BLTU nho hon");
        check(1, 0, 0, 3'b110, 0, 1, 0,   0, "BLTU khong nho");
        check(1, 0, 0, 3'b111, 0, 1, 0,   1, "BGEU lon/bang");
        check(1, 0, 0, 3'b111, 0, 0, 1,   0, "BGEU nho hon");
        check(1, 0, 0, 3'b010, 1, 1, 1,   0, "funct3 khong hop le");
        check(0, 1, 0, 3'b000, 0, 0, 0,   1, "JAL");
        check(0, 0, 1, 3'b000, 0, 0, 0,   1, "JALR");

        $display("\nSUMMARY BRANCH_UNIT: PASS = %0d | FAIL = %0d", pass_count, fail_count);
        $finish;
    end

endmodule
