`timescale 1ns / 1ps

module ALU_tb;

    // Khai bao tin hieu
    reg  [31:0] A;
    reg  [31:0] B;
    reg  [3:0]  ALUControl;
    
    wire        Zero;
    wire [31:0] Result;

    // Instantiate (goi) module ALU
    ALU u_ALU (
        .A(A),
        .B(B),
        .ALUControl(ALUControl),
        .Zero(Zero),
        .Result(Result)
    );

    // Block khoi tao va cap gia tri test
    initial begin
        $display("==================================================");
        $display("          BAT DAU TEST TOAN DIEN ALU              ");
        $display("==================================================");

        // --------------------------------------------------------
        // 1. Nhom so hoc: ADD (0000), SUB (0001), AUIPC (1000)
        // --------------------------------------------------------
        $display("\n--- 1. Nhom Toan Hoc (ADD, SUB, AUIPC) ---");
        
        A = 32'd150; B = 32'd50; ALUControl = 4'b0000; #10; // ADD
        $display("ADD   : %d + %d = %d | Zero: %b", A, B, Result, Zero);

        A = 32'd150; B = 32'd50; ALUControl = 4'b0001; #10; // SUB
        $display("SUB   : %d - %d = %d | Zero: %b", A, B, Result, Zero);

        A = 32'd50;  B = 32'd50; ALUControl = 4'b0001; #10; // SUB (Check Zero flag)
        $display("SUB   : %d - %d = %d | Zero: %b (Ky vong Zero = 1)", A, B, Result, Zero);

        A = 32'h0040_0000; B = 32'h0000_1234; ALUControl = 4'b1000; #10; // AUIPC
        $display("AUIPC : %h + %h = %h", A, B, Result);

        // --------------------------------------------------------
        // 2. Nhom logic: AND (0010), OR (0011), XOR (0100)
        // --------------------------------------------------------
        $display("\n--- 2. Nhom Logic (AND, OR, XOR) ---");
        A = 32'hFFFF_0000; B = 32'h0F0F_0F0F; 
        
        ALUControl = 4'b0010; #10; // AND
        $display("AND   : %h & %h = %h", A, B, Result);
        
        ALUControl = 4'b0011; #10; // OR
        $display("OR    : %h | %h = %h", A, B, Result);
        
        ALUControl = 4'b0100; #10; // XOR
        $display("XOR   : %h ^ %h = %h", A, B, Result);

        // --------------------------------------------------------
        // 3. Nhom lenh dac biet: LUI (1001)
        // --------------------------------------------------------
        $display("\n--- 3. LUI (Load Upper Immediate) ---");
        A = 32'h1234_5678; B = 32'hABCD_E000; ALUControl = 4'b1001; #10; 
        $display("LUI   : Bo qua A, truyen thang B. Result = %h", Result);

        // --------------------------------------------------------
        // 4. Nhom so sanh: SLT (0101), SLTU (0110)
        // --------------------------------------------------------
        $display("\n--- 4. Nhom So Sanh (SLT, SLTU) ---");
        
        // SLT (So sanh co dau: -10 < 5 -> Dung)
        A = -32'd10; B = 32'd5; ALUControl = 4'b0101; #10;
        $display("SLT   : %d < %d -> Result = %d (Co dau)", $signed(A), $signed(B), Result);

        // SLTU (So sanh khong dau: -10 thanh so duong rat lon > 5 -> Sai)
        A = -32'd10; B = 32'd5; ALUControl = 4'b0110; #10;
        $display("SLTU  : %d < %d -> Result = %d (Khong dau)", A, B, Result);

        // --------------------------------------------------------
        // 5. Nhom dich bit: SLL (1010), SRL (1100), SRA (1011)
        // --------------------------------------------------------
        $display("\n--- 5. Nhom Dich Bit (SLL, SRL, SRA) ---");
        
        // SLL: Dich trai logic
        A = 32'h0000_0001; B = 32'd4; ALUControl = 4'b1010; #10; 
        $display("SLL   : %h << 4 = %h", A, Result);

        // Gioi han 5-bit (Test shift amount = 36 -> B[4:0] = 4)
        A = 32'h0000_0001; B = 32'd36; ALUControl = 4'b1010; #10; 
        $display("SLL   : %h << 36 (gioi han con 4) = %h", A, Result);

        // SRL: Dich phai logic (Chen bit 0)
        A = 32'hF000_0000; B = 32'd4; ALUControl = 4'b1100; #10; 
        $display("SRL   : %h >> 4 = %h", A, Result);

        // SRA: Dich phai so hoc (Bao toan bit dau)
        A = 32'hF000_0000; B = 32'd4; ALUControl = 4'b1011; #10; 
        $display("SRA   : %h >>> 4 = %h (Bao toan dau)", A, Result);

        // --------------------------------------------------------
        // 6. Truong hop Default
        // --------------------------------------------------------
        $display("\n--- 6. Default (Truong hop khong xac dinh) ---");
        A = 32'd100; B = 32'd200; ALUControl = 4'b1111; #10;
        $display("Undef : ALUControl = %b -> Result = %h", ALUControl, Result);

        $display("\n==================================================");
        $display("                KET THUC TEST                     ");
        $display("==================================================");
        $stop; // Dung mo phong ModelSim tai day
    end

endmodule