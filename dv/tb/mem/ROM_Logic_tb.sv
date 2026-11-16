`timescale 1ns / 1ps
// ROM_Logic_tb: the generated ROM logic (fw/tools/gen_rom_v.py) returns exactly the words of the hex
// files, on both ports, for the Boot ROM and the App ROM. The reference is a plain $readmemh array,
// the same file Dual_Port_ROM would load.
//  - every word on port A, then on port B, then both ports together with different addresses
//  - random addresses on both ports at once
//  - the two ports are independent: a change on one never moves the other
// Run from sim/: vsim -c -do run_rom.do. Ends with "ROM_Logic_tb RESULT: PASS|FAIL".
module ROM_Logic_tb;
    reg  [31:0] boot_ref [0:1023];
    reg  [31:0] app_ref  [0:1023];
    reg  [31:0] aA0 = 0, aB0 = 0, aA1 = 0, aB1 = 0;
    wire [31:0] dA0, dB0, dA1, dB1;
    reg  clk = 0;

    ROM_Logic #(.IMAGE(0)) u_boot (.clk(clk), .addrA(aA0), .dataOutA(dA0), .addrB(aB0), .dataOutB(dB0));
    ROM_Logic #(.IMAGE(1)) u_app  (.clk(clk), .addrA(aA1), .dataOutA(dA1), .addrB(aB1), .dataOutB(dB1));

    integer errors = 0, checks = 0, i, n;
    task automatic chk(input [31:0] got, input [31:0] exp, input string what, input integer idx);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                if (errors <= 10) $display("FAIL: %0s word %0d got %h expected %h", what, idx, got, exp);
            end
        end
    endtask

    initial begin
        for (i = 0; i < 1024; i = i + 1) begin boot_ref[i] = 32'h0; app_ref[i] = 32'h0; end
        $readmemh("../fw/build/firmware_imem.hex", boot_ref);
        $readmemh("../fw/build/app_firmware.hex", app_ref);

        for (i = 0; i < 1024; i = i + 1) begin
            aA0 = i * 4; aA1 = i * 4; aB0 = 32'h0; aB1 = 32'h0; #1;
            chk(dA0, boot_ref[i], "boot port A", i);
            chk(dA1, app_ref[i],  "app port A", i);
            aB0 = i * 4; aB1 = i * 4; aA0 = 32'h0; aA1 = 32'h0; #1;
            chk(dB0, boot_ref[i], "boot port B", i);
            chk(dB1, app_ref[i],  "app port B", i);
            // Both ports together, different words. Byte address bits [1:0] and [31:12] are ignored
            aA0 = i * 4 + 32'd1; aB0 = ((i + 517) % 1024) * 4 + 32'h1000_0000; #1;
            chk(dA0, boot_ref[i], "boot A with B moving", i);
            chk(dB0, boot_ref[(i + 517) % 1024], "boot B with A moving", i);
        end
        for (n = 0; n < 20000; n = n + 1) begin
            aA0 = {$urandom} & 32'hFFC; aB0 = {$urandom} & 32'hFFC;
            aA1 = {$urandom} & 32'hFFC; aB1 = {$urandom} & 32'hFFC; #1;
            chk(dA0, boot_ref[aA0[11:2]], "random boot A", aA0[11:2]);
            chk(dB0, boot_ref[aB0[11:2]], "random boot B", aB0[11:2]);
            chk(dA1, app_ref[aA1[11:2]],  "random app A",  aA1[11:2]);
            chk(dB1, app_ref[aB1[11:2]],  "random app B",  aB1[11:2]);
        end
        $display("ROM_Logic_tb: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("ROM_Logic_tb RESULT: PASS");
        else             $display("ROM_Logic_tb RESULT: FAIL");
        $finish;
    end
endmodule
