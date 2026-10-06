`timescale 1ns / 1ps

module Branch_Unit_tb;

    // Khai bao tin hieu
    reg       Branch;
    reg       Jump;
    reg       Jalr;
    reg [2:0] funct3;
    reg       Zero;
    
    wire      PCSrc;

    // Instantiate module Branch_Unit
    Branch_Unit u_BU (
        .Branch(Branch),
        .Jump(Jump),
        .Jalr(Jalr),
        .funct3(funct3),
        .Zero(Zero),
        .PCSrc(PCSrc)
    );

    initial begin
        $display("===============================================================");
        $display("                   BAT DAU TEST BRANCH UNIT                    ");
        $display("===============================================================");
        $display("Loai Lenh   | Branch | Jump | Jalr | funct3 | Zero || PCSrc");
        $display("---------------------------------------------------------------");

        // 1. Khong re nhanh (Lenh thuong nhu ADD, SUB, LW...)
        Branch = 0; Jump = 0; Jalr = 0; funct3 = 3'b000; Zero = 0; #10;
        $display("Binh thuong |   %b    |  %b   |  %b   |  %b   |  %b   ||   %b   (Ky vong 0)", Branch, Jump, Jalr, funct3, Zero, PCSrc);

        // 2. Lenh BEQ (funct3 = 000)
        Branch = 1; Jump = 0; Jalr = 0; funct3 = 3'b000; 
        Zero = 1; #10; // Bang nhau (Zero = 1) -> Chon nhay
        $display("BEQ (A==B)  |   %b    |  %b   |  %b   |  %b   |  %b   ||   %b   (Ky vong 1)", Branch, Jump, Jalr, funct3, Zero, PCSrc);
        
        Zero = 0; #10; // Khac nhau (Zero = 0) -> Khong nhay
        $display("BEQ (A!=B)  |   %b    |  %b   |  %b   |  %b   |  %b   ||   %b   (Ky vong 0)", Branch, Jump, Jalr, funct3, Zero, PCSrc);

        // 3. Lenh BNE (funct3 = 001)
        Branch = 1; Jump = 0; Jalr = 0; funct3 = 3'b001; 
        Zero = 0; #10; // Khac nhau (Zero = 0) -> Chon nhay
        $display("BNE (A!=B)  |   %b    |  %b   |  %b   |  %b   |  %b   ||   %b   (Ky vong 1)", Branch, Jump, Jalr, funct3, Zero, PCSrc);
        
        Zero = 1; #10; // Bang nhau (Zero = 1) -> Khong nhay
        $display("BNE (A==B)  |   %b    |  %b   |  %b   |  %b   |  %b   ||   %b   (Ky vong 0)", Branch, Jump, Jalr, funct3, Zero, PCSrc);

        // 4. Lenh JAL (Jump)
        Branch = 0; Jump = 1; Jalr = 0; funct3 = 3'bxxx; Zero = 1'bx; #10;
        $display("JAL (Jump)  |   %b    |  %b   |  %b   |  %bx   |  %bx   ||   %b   (Ky vong 1)", Branch, Jump, Jalr, funct3[2], Zero, PCSrc);

        // 5. Lenh JALR
        Branch = 0; Jump = 0; Jalr = 1; funct3 = 3'bxxx; Zero = 1'bx; #10;
        $display("JALR        |   %b    |  %b   |  %b   |  %bx   |  %bx   ||   %b   (Ky vong 1)", Branch, Jump, Jalr, funct3[2], Zero, PCSrc);

        $display("===============================================================");
        $display("                       KET THUC TEST                           ");
        $display("===============================================================");
        $stop;
    end

endmodule