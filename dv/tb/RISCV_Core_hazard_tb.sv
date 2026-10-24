`timescale 1ns/1ps
// Back-to-back dependent instructions with no NOPs in between: exercises forwarding from MEM and WB,
// store-data forwarding, load-use stalls and JAL link forwarding. Ends with "... RESULT: PASS|FAIL".
module RISCV_Core_hazard_tb;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg  [31:0] imem[0:63], dmem[0:63];
    wire [31:0] ia, da, dw, pcd, ind, res;
    wire        we, re, rw;
    wire [4:0]  rd;

    RISCV_Core dut(.clk(clk),.rst(rst),.bus_stall(1'b0),.instr_rdata(imem[ia[7:2]]),.instr_addr(ia),
        .data_rdata(dmem[da[7:2]]),.data_addr(da),.data_wdata(dw),.data_we(we),.data_re(re),
        .PC_debug(pcd),.Instr_debug(ind),.RegWrite_WB_debug(rw),.Rd_WB_debug(rd),.Result_WB_debug(res));

    always @(posedge clk)
        if (we)
            dmem[da[7:2]] <= dw;

    // Shadow register file built from the WB debug port
    reg [31:0] x[0:31];
    always @(posedge clk)
        if (rw && rd != 0)
            x[rd] <= res;

    integer i, f = 0;
    task chk(input [4:0] r, input [31:0] e);
        if (x[r] !== e) begin
            f = f + 1;
            $display("[FAIL] x%0d = %h, expected %h", r, x[r], e);
        end
    endtask

    initial begin
        for (i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'h13;
            dmem[i] = 0;
        end
        imem[0]  = 32'h00500093; // addi x1,x0,5
        imem[1]  = 32'h00308113; // addi x2,x1,3   (MEM fwd)
        imem[2]  = 32'h002081b3; // add  x3,x1,x2  (WB+MEM fwd)
        imem[3]  = 32'h00302023; // sw   x3,0(x0)  (store data fwd)
        imem[4]  = 32'h00002203; // lw   x4,0(x0)
        imem[5]  = 32'h00120293; // addi x5,x4,1   (load-use)
        imem[6]  = 32'h0080036f; // jal  x6,+8
        imem[7]  = 32'h06300393; // addi x7,x0,99  (skipped)
        imem[8]  = 32'h00030433; // add  x8,x6,x0  (fwd JAL link from MEM)
        imem[9]  = 32'h00502423; // sw   x5,8(x0)
        imem[10] = 32'h00802483; // lw   x9,8(x0)
        imem[11] = 32'h00948533; // add  x10,x9,x9 (load-use both operands)
        x[7] = 0;

        repeat (2) @(posedge clk);
        #1 rst = 0;
        repeat (40) @(posedge clk);

        chk(1, 5);
        chk(2, 8);
        chk(3, 13);
        chk(4, 13);
        chk(5, 14);
        chk(6, 32'h1c);
        chk(7, 0);
        chk(8, 32'h1c);
        chk(9, 14);
        chk(10, 28);
        if (dmem[0] !== 13) begin
            f = f + 1;
            $display("[FAIL] dmem[0] = %h, expected 0000000d", dmem[0]);
        end
        $display("RISCV_Core_hazard_tb RESULT: %s (%0d of 11 checks failed)", f ? "FAIL" : "PASS", f);
        $finish;
    end
endmodule
