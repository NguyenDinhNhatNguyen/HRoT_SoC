`timescale 1ns / 1ps

// Register_File_tb - Testbench tu kiem tra: ghi/doc, bypass ghi-doc cung chu ky, x0, 2 cong doc
module Register_File_tb;

    reg         clk = 1'b0;
    reg         WE3;
    reg  [4:0]  RA1, RA2, WA3;
    reg  [31:0] WD3;
    wire [31:0] RD1, RD2;

    integer pass_count = 0, fail_count = 0;
    reg [4:0] r;                       // so thanh ghi trong vong lap

    Register_File u_RegFile (
        .clk(clk), .WE3(WE3), .RA1(RA1), .RA2(RA2),
        .WA3(WA3), .WD3(WD3), .RD1(RD1), .RD2(RD2)
    );

    always #5 clk = ~clk;

    task check;
        input [31:0]   actual, expected;
        input [8*32:1] name;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : %h", name, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : %h (expect %h)", name, actual, expected);
            end
        end
    endtask

    // Ghi 1 thanh ghi tai canh len ke tiep
    task write_reg;
        input [4:0]  addr;
        input [31:0] data;
        begin
            @(negedge clk); WE3 = 1'b1; WA3 = addr; WD3 = data;
            @(negedge clk); WE3 = 1'b0;
        end
    endtask

    initial begin
        WE3 = 1'b0; RA1 = 5'd0; RA2 = 5'd0; WA3 = 5'd0; WD3 = 32'd0;
        $display("\n=== REGISTER FILE TESTBENCH ===");

        // 1. Ghi va doc lai tat ca x1..x31 qua ca 2 cong
        // Gia tri ghi vao xN = 0xA5A5_00NN. Cong 2 doc nguoc: RA2 = 32 - N (mod 32)
        r = 5'd1;
        repeat (31) begin write_reg(r, {16'hA5A5, 11'd0, r}); r = r + 5'd1; end
        r = 5'd1;
        repeat (31) begin
            RA1 = r; RA2 = 5'd0 - r; #1;
            if (RD1 !== {16'hA5A5, 11'd0, r} || RD2 !== {16'hA5A5, 11'd0, 5'd0 - r}) begin
                fail_count = fail_count + 1;
                $display("[FAIL] Doc x%0d/x%0d : RD1=%h RD2=%h", RA1, RA2, RD1, RD2);
            end else pass_count = pass_count + 1;
            r = r + 5'd1;
        end
        $display("[INFO] Da kiem tra ghi/doc x1..x31 tren 2 cong");

        // 2. Bypass: ghi va doc cung chu ky -> RD tra WD3 ngay (truoc canh len)
        @(negedge clk); WE3 = 1'b1; WA3 = 5'd8; WD3 = 32'd123; RA2 = 5'd8; RA1 = 5'd9; #1;
        check(RD2, 32'd123, "Bypass RD2 = WD3 (x8)");
        check(RD1, 32'hA5A5_0009, "RD1 cong khac khong bi bypass");
        @(negedge clk); WE3 = 1'b0; #1;
        check(RD2, 32'd123, "x8 da ghi sau canh len");

        // 3. x0 luon bang 0, ke ca khi dang ghi (khong bypass)
        @(negedge clk); WE3 = 1'b1; WA3 = 5'd0; WD3 = 32'd999; RA1 = 5'd0; RA2 = 5'd0; #1;
        check(RD1, 32'd0, "x0 khi dang ghi (RD1)");
        check(RD2, 32'd0, "x0 khi dang ghi (RD2)");
        @(negedge clk); WE3 = 1'b0; #1;
        check(RD1, 32'd0, "x0 sau khi ghi");

        // 4. WE3 = 0 thi khong ghi
        @(negedge clk); WA3 = 5'd5; WD3 = 32'hDEAD_BEEF; RA1 = 5'd5;
        @(negedge clk); #1;
        check(RD1, 32'hA5A5_0005, "WE3=0 khong ghi");

        $display("\nSUMMARY REGISTER_FILE: PASS = %0d | FAIL = %0d", pass_count, fail_count);
        $finish;
    end

endmodule
