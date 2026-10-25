`timescale 1ns / 1ps

// Register_File_tb - Self-checking testbench: write/read, same-cycle write-read bypass, x0, both read ports
module Register_File_tb;

    reg         clk = 1'b0;
    reg         WE3;
    reg  [4:0]  RA1, RA2, WA3;
    reg  [31:0] WD3;
    wire [31:0] RD1, RD2;

    integer pass_count = 0, fail_count = 0;
    reg [4:0] r;                       // register index in the loop

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

    // Write one register on the next rising edge
    task write_reg;
        input [4:0]  addr;
        input [31:0] data;
        begin
            @(negedge clk);
            WE3 = 1'b1;
            WA3 = addr;
            WD3 = data;
            @(negedge clk);
            WE3 = 1'b0;
        end
    endtask

    initial begin
        WE3 = 1'b0;
        RA1 = 5'd0;
        RA2 = 5'd0;
        WA3 = 5'd0;
        WD3 = 32'd0;
        $display("\n=== REGISTER FILE TESTBENCH ===");

        // 1. Write and read back x1..x31 through both ports
        // xN gets 0xA5A5_00NN. Port 2 reads in reverse: RA2 = 32 - N (mod 32)
        r = 5'd1;
        repeat (31) begin
            write_reg(r, {16'hA5A5, 11'd0, r});
            r = r + 5'd1;
        end
        r = 5'd1;
        repeat (31) begin
            RA1 = r;
            RA2 = 5'd0 - r;
            #1;
            if (RD1 !== {16'hA5A5, 11'd0, r} || RD2 !== {16'hA5A5, 11'd0, 5'd0 - r}) begin
                fail_count = fail_count + 1;
                $display("[FAIL] Read x%0d/x%0d : RD1=%h RD2=%h", RA1, RA2, RD1, RD2);
            end
            else
                pass_count = pass_count + 1;
            r = r + 5'd1;
        end
        $display("[INFO] Checked write/read of x1..x31 on both ports");

        // 2. Bypass: write and read in the same cycle -> RD returns WD3 at once (before the edge)
        @(negedge clk);
        WE3 = 1'b1;
        WA3 = 5'd8;
        WD3 = 32'd123;
        RA2 = 5'd8;
        RA1 = 5'd9;
        #1;
        check(RD2, 32'd123, "Bypass RD2 = WD3 (x8)");
        check(RD1, 32'hA5A5_0009, "RD1 on the other port not bypassed");
        @(negedge clk);
        WE3 = 1'b0;
        #1;
        check(RD2, 32'd123, "x8 written after the edge");

        // 3. x0 always reads 0, even while being written (no bypass)
        @(negedge clk);
        WE3 = 1'b1;
        WA3 = 5'd0;
        WD3 = 32'd999;
        RA1 = 5'd0;
        RA2 = 5'd0;
        #1;
        check(RD1, 32'd0, "x0 while written (RD1)");
        check(RD2, 32'd0, "x0 while written (RD2)");
        @(negedge clk);
        WE3 = 1'b0;
        #1;
        check(RD1, 32'd0, "x0 after write");

        // 4. WE3 = 0 -> no write
        @(negedge clk);
        WA3 = 5'd5;
        WD3 = 32'hDEAD_BEEF;
        RA1 = 5'd5;
        @(negedge clk);
        #1;
        check(RD1, 32'hA5A5_0005, "WE3=0 does not write");

        $display("\nSUMMARY REGISTER_FILE: PASS = %0d | FAIL = %0d", pass_count, fail_count);
        $finish;
    end

endmodule
