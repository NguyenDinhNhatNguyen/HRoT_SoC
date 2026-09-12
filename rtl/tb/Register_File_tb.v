`timescale 1ns / 1ps

module Register_File_tb;

    // Khai bao tin hieu
    reg         clk;
    reg         WE3;
    reg  [4:0]  RA1, RA2, WA3;
    reg  [31:0] WD3;
    
    wire [31:0] RD1, RD2;

    // Instantiate module Register_File
    Register_File u_RegFile (
        .clk(clk), 
        .WE3(WE3), 
        .RA1(RA1), 
        .RA2(RA2), 
        .WA3(WA3), 
        .WD3(WD3),
        .RD1(RD1), 
        .RD2(RD2)
    );

    // Tao xung nhip chu ky 10ns (5ns high, 5ns low)
    always #5 clk = ~clk;

    initial begin
        // Khoi tao cac tin hieu
        clk = 0; WE3 = 0; RA1 = 0; RA2 = 0; WA3 = 0; WD3 = 0;
        
        $display("==================================================");
        $display("        BAT DAU TEST REGISTER FILE                ");
        $display("==================================================");
        
        #15; // Doi qua canh len dau tien de on dinh he thong

        // --------------------------------------------------------
        // 1. Test ghi va doc binh thuong
        // --------------------------------------------------------
        $display("\n--- 1. Test Ghi va Doc binh thuong ---");
        
        // Ghi gia tri 99 vao thanh ghi x5
        WE3 = 1; WA3 = 5'd5; WD3 = 32'd99;
        #10; // Cho 1 chu ky xung nhip de du lieu duoc ghi vao RAM
        WE3 = 0;
        
        // Doc thanh ghi x5 ra ngo RD1
        RA1 = 5'd5;
        #10; 
        $display("Doc x5 (Ky vong 99): RD1 = %d", RD1);

        // --------------------------------------------------------
        // 2. Test Internal Forwarding (Ghi va Doc cung luc)
        // --------------------------------------------------------
        $display("\n--- 2. Test Internal Forwarding (Tranh Data Hazard) ---");
        
        // Ghi 123 vao x8, dong thoi yeu cau doc x8 o ngo RA2 trong cung chu ky
        WE3 = 1; WA3 = 5'd8; WD3 = 32'd123; RA2 = 5'd8;
        
        #1; // Chi delay 1ns (chua het 1 chu ky) de kiem tra MUX co tra ve du lieu ngay khong
        $display("Doc x8 ngay lap tuc (Ky vong 123): RD2 = %d", RD2);
        
        #9; // Doi het chu ky
        WE3 = 0;

        // --------------------------------------------------------
        // 3. Test thanh ghi x0 (Zero Register luon = 0)
        // --------------------------------------------------------
        $display("\n--- 3. Test thanh ghi x0 (Zero Register) ---");
        
        // Co gang ghi gia tri 999 vao thanh ghi x0
        WE3 = 1; WA3 = 5'd0; WD3 = 32'd999; 
        RA1 = 5'd0;
        
        #1; // Kiem tra MUX forwarding co chan loi ghi vao x0 khong
        $display("Doc x0 ngay khi ghi 999 (Ky vong 0): RD1 = %d", RD1);
        
        #9;
        WE3 = 0;
        
        #10; // Kiem tra lai sau khi ghi xong
        $display("Doc x0 sau khi ket thuc ghi (Ky vong 0): RD1 = %d", RD1);

        $display("\n==================================================");
        $display("                KET THUC TEST                     ");
        $display("==================================================");
        
        $stop; // Dung mo phong
    end

endmodule