`timescale 1ns/1ps

// Self-checking testbench for Boot_Verifier and the SYSCSR release gate (VERIFY_GATE = 1).
// SHA-256 and the Boot ROM are replaced by plain registers so every verdict can be forced.
// Ends with "Boot_Verifier_tb RESULT: PASS|FAIL", which sim/regress.sh looks for.
module Boot_Verifier_tb;
    reg clk = 0, por = 1;
    always #5 clk = ~clk;

    reg  [11:0] PADDR;
    reg         PENABLE = 0, PWRITE = 0;
    reg  [31:0] PWDATA;
    reg  [1:0]  sel = 0;                  // 1 = Boot_Verifier, 2 = SYSCSR
    wire [31:0] rd_bv, rd_sys;

    // Fake SHA-256 digest and Boot ROM (negedge read, like Dual_Port_ROM)
    reg  [255:0] dig = 0;
    reg          sha_done = 0, sha_busy = 0;
    reg  [31:0]  rom [0:1023];
    wire [11:0]  rom_addr;
    reg  [31:0]  rom_data;
    always @(negedge clk)
        rom_data <= rom[rom_addr[11:2]];

    wire sys_rst, app_rst, verified;

    Boot_Verifier #(.KEY(256'h0123456789ABCDEF_FEDCBA9876543210_0F1E2D3C4B5A6978_8796A5B4C3D2E1F0)) dut (
        .clk(clk), .por_rst(por), .sys_rst(sys_rst),
        .sha_digest(dig), .sha_done(sha_done), .sha_busy(sha_busy),
        .rom_addr(rom_addr), .rom_data(rom_data), .verified(verified),
        .PADDR(PADDR), .PSEL(sel == 1), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PWDATA(PWDATA), .PSTRB(4'hF), .PRDATA(rd_bv), .PREADY(), .PSLVERR()
    );

    SYSCSR #(.VERIFY_GATE(1), .RST_HOLD(3), .ZERO_WORDS(16)) sys (
        .clk(clk), .por_rst(por), .wdt_rst_req(1'b0),
        .sys_rst(sys_rst), .app_rst(app_rst), .app_zero_en(), .app_zero_addr(),
        .boot_strap(4'h0), .verified(verified),
        .bus_err(1'b0), .bus_err_write(1'b0), .bus_err_resp(2'b00), .bus_err_addr(32'b0),
        .PADDR(PADDR), .PSEL(sel == 2), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PWDATA(PWDATA), .PSTRB(4'hF), .PRDATA(rd_sys), .PREADY(), .PSLVERR()
    );

    integer pass = 0, fail = 0;

    task apb_wr(input [1:0] s, input [11:0] a, input [31:0] d);
        begin
            @(posedge clk);
            sel     <= s;
            PADDR   <= a;
            PWDATA  <= d;
            PWRITE  <= 1;
            PENABLE <= 0;
            @(posedge clk);
            PENABLE <= 1;
            @(posedge clk);
            sel     <= 0;
            PENABLE <= 0;
            PWRITE  <= 0;
            #1;
        end
    endtask

    task apb_rd(input [1:0] s, input [11:0] a, output [31:0] d);
        begin
            @(posedge clk);
            sel     <= s;
            PADDR   <= a;
            PWRITE  <= 0;
            PENABLE <= 0;
            @(posedge clk);
            PENABLE <= 1;
            #1 d = (s == 1) ? rd_bv : rd_sys;
            @(posedge clk);
            sel     <= 0;
            PENABLE <= 0;
            #1;
        end
    endtask

    task chk(input [31:0] got, input [31:0] exp, input [8*56-1:0] name);
        if (got !== exp) begin
            fail = fail + 1;
            $display("[FAIL] %0s: got %h, expected %h", name, got, exp);
        end else begin
            pass = pass + 1;
            $display("[PASS] %0s", name);
        end
    endtask

    // Put the digest into the fake SHA and the same words into a ROM slot (slot base is a byte address)
    task load(input [255:0] d, input [11:0] slot);
        integer w;
        begin
            dig      = d;
            sha_done = 1;
            sha_busy = 0;
            for (w = 0; w < 8; w = w + 1)
                rom[slot[11:2] + w] = d[255 - 32*w -: 32];
        end
    endtask

    task check_cmd(input mode);
        begin
            apb_wr(1, 12'h000, {29'b0, mode, 1'b0, 1'b1});
            repeat (12) @(posedge clk);
            #1;
        end
    endtask

    task sw_reset;
        begin
            apb_wr(2, 12'h014, 32'h5A5A0001);
            repeat (3) @(posedge clk);
            wait (!sys_rst);
            repeat (2) @(posedge clk);
        end
    endtask

    localparam [255:0] D = 256'hAAAA0000_BBBB1111_CCCC2222_DDDD3333_EEEE4444_FFFF5555_66660000_77771111;
    reg [31:0] r;
    integer i;

    initial begin
        for (i = 0; i < 1024; i = i + 1)
            rom[i] = 32'hDEAD0000 + i;
        repeat (3) @(posedge clk);
        por <= 0;
        wait (!sys_rst);
        repeat (2) @(posedge clk);

        // ---- Before any CHECK the gate is shut, whatever the firmware writes ----
        apb_rd(1, 12'h004, r);
        chk(r, 32'h0, "STATUS is clear after reset");
        apb_wr(2, 12'h000, 32'h1);
        chk({31'b0, app_rst}, 32'h1, "APP_RUN ignored before CHECK");
        apb_rd(2, 12'h000, r);
        chk(r, 32'h0, "APP_CTRL still reads 0");

        // ---- Matching golden hash ----
        load(D, 12'hFE0);
        apb_wr(1, 12'h00C, 32'd5);
        check_cmd(0);
        apb_rd(1, 12'h004, r);
        chk(r, 32'h9, "good hash: VERIFIED and CHECKED, no FAIL");
        apb_rd(1, 12'h008, r);
        chk(r, 32'd5, "MIN_VER raised to APP_VER");
        apb_wr(2, 12'h000, 32'h1);
        chk({31'b0, app_rst}, 32'h0, "APP_RUN accepted once VERIFIED");

        // ---- CHECK runs once per reset, APP_VER is frozen after it ----
        load(~D, 12'hFE0);
        check_cmd(0);
        apb_rd(1, 12'h004, r);
        chk(r, 32'h9, "second CHECK is ignored");
        apb_wr(1, 12'h00C, 32'd99);
        apb_rd(1, 12'h00C, r);
        chk(r, 32'd5, "APP_VER write after CHECK is ignored");

        // ---- A system reset clears the verdict and re-closes the gate ----
        sw_reset;
        apb_rd(1, 12'h004, r);
        chk(r, 32'h0, "software reset clears the verdict");
        chk({31'b0, app_rst}, 32'h1, "App held in reset again");
        apb_rd(1, 12'h008, r);
        chk(r, 32'd5, "MIN_VER survives a software reset");

        // ---- One wrong bit in the first and in the last word ----
        load(D, 12'hFE0);
        rom[12'hFE0 >> 2] = rom[12'hFE0 >> 2] ^ 32'h1;
        apb_wr(1, 12'h00C, 32'd5);
        check_cmd(0);
        apb_rd(1, 12'h004, r);
        chk(r, 32'hA, "wrong word 0: FAIL, not VERIFIED");
        apb_wr(2, 12'h000, 32'h1);
        chk({31'b0, app_rst}, 32'h1, "APP_RUN ignored after FAIL");
        sw_reset;
        load(D, 12'hFE0);
        rom[(12'hFE0 >> 2) + 7] = rom[(12'hFE0 >> 2) + 7] ^ 32'h8000_0000;
        apb_wr(1, 12'h00C, 32'd5);
        check_cmd(0);
        apb_rd(1, 12'h004, r);
        chk(r, 32'hA, "wrong word 7: FAIL, not VERIFIED");

        // ---- SHA-256 not finished ----
        sw_reset;
        load(D, 12'hFE0);
        sha_done = 0;
        apb_wr(1, 12'h00C, 32'd5);
        check_cmd(0);
        apb_rd(1, 12'h004, r);
        chk(r, 32'hA, "SHA not done: FAIL");
        sw_reset;
        load(D, 12'hFE0);
        sha_busy = 1;
        apb_wr(1, 12'h00C, 32'd5);
        check_cmd(0);
        apb_rd(1, 12'h004, r);
        chk(r, 32'hA, "SHA busy: FAIL");
        sha_busy = 0;

        // ---- Rollback: an older App image is refused, an equal or newer one is accepted ----
        sw_reset;
        load(D, 12'hFE0);
        apb_wr(1, 12'h00C, 32'd4);
        check_cmd(0);
        apb_rd(1, 12'h004, r);
        chk(r, 32'hA, "APP_VER 4 < MIN_VER 5: FAIL");
        sw_reset;
        apb_wr(1, 12'h00C, 32'd7);
        check_cmd(0);
        apb_rd(1, 12'h004, r);
        chk(r, 32'h9, "APP_VER 7: VERIFIED");
        apb_rd(1, 12'h008, r);
        chk(r, 32'd7, "MIN_VER follows to 7");
        apb_wr(1, 12'h008, 32'd3);
        apb_rd(1, 12'h008, r);
        chk(r, 32'd7, "MIN_VER write that lowers it is ignored");
        apb_wr(1, 12'h008, 32'd9);
        apb_rd(1, 12'h008, r);
        chk(r, 32'd9, "MIN_VER write that raises it is accepted");

        // ---- HMAC tag slot (MODE = 1) is a different ROM slot from the golden hash ----
        sw_reset;
        load(D, 12'hFC0);
        for (i = 0; i < 8; i = i + 1)
            rom[(12'hFE0 >> 2) + i] = 32'h0;
        apb_wr(1, 12'h00C, 32'd9);
        check_cmd(1);
        apb_rd(1, 12'h004, r);
        chk(r, 32'h9, "MODE 1: tag slot matches, VERIFIED");
        sw_reset;
        apb_wr(1, 12'h00C, 32'd9);
        check_cmd(0);
        apb_rd(1, 12'h004, r);
        chk(r, 32'hA, "MODE 0 with a blank golden slot: FAIL");

        // ---- Key: readable until KEY_LOCK, then 0 until power-on reset ----
        apb_rd(1, 12'h040, r);
        chk(r, 32'h01234567, "KEY0 readable before KEY_LOCK");
        apb_rd(1, 12'h05C, r);
        chk(r, 32'hC3D2E1F0, "KEY7 readable before KEY_LOCK");
        apb_wr(1, 12'h000, 32'h2);
        apb_rd(1, 12'h040, r);
        chk(r, 32'h0, "KEY0 reads 0 after KEY_LOCK");
        apb_rd(1, 12'h004, r);
        chk(r[2], 1'b1, "STATUS shows KEY_LOCKED");
        sw_reset;
        apb_rd(1, 12'h040, r);
        chk(r, 32'h0, "KEY_LOCK survives a software reset");
        por = 1;
        repeat (3) @(posedge clk);
        por = 0;
        wait (!sys_rst);
        repeat (2) @(posedge clk);
        apb_rd(1, 12'h040, r);
        chk(r, 32'h01234567, "power-on reset reopens the key");
        apb_rd(1, 12'h008, r);
        chk(r, 32'h0, "power-on reset clears MIN_VER");

        $display("Boot_Verifier_tb SUMMARY: PASS = %0d | FAIL = %0d", pass, fail);
        $display("Boot_Verifier_tb RESULT: %0s", fail == 0 ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #2000000;
        $display("Boot_Verifier_tb RESULT: FAIL (timeout)");
        $finish;
    end
endmodule
