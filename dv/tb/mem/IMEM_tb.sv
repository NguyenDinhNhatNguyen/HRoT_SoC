`timescale 1ns / 1ps

// IMEM_tb: the shared instruction memory of the two-world design (SoC_Memory_Map.md), written before
// rtl/mem/IMEM.v. It fixes the block's interface and checks:
//   - unlocked: the Secure side writes whole words, reads answer an error
//   - locked  : reads work, writes answer an error and change nothing
//   - byte and halfword writes are refused
//   - released: the Normal side fetches the stored words, the Secure side gets errors only
//   - the memory reads on the rising edge, a new fetch address stalls for one cycle
//   - a fetch outside the 4 KB answers an all-zero word, it does not wrap around
//   - Boot Guard zeroization clears every word, locked or not
// The HASHED flag lives in SYSCSR and is tested there.
module IMEM_tb;
    localparam [31:0] BASE  = 32'h7000_0000;
    localparam        WORDS = 1024;

    logic        clk = 0, rst = 1;
    logic [31:0] fetch_addr = 0;
    logic        locked = 0, released = 0, zero_en = 0;
    logic [9:0]  zero_addr = 0;
    logic        reg_wen = 0;
    logic [31:0] reg_waddr = BASE, reg_wdata = 0, reg_raddr = BASE;
    logic [3:0]  reg_wstrb = 4'hF;
    wire  [31:0] fetch_data, reg_rdata;
    wire         fetch_stall, werr, rerr;

    int checks = 0, errors = 0;
    logic [31:0] ref_mem [0:WORDS-1];

    always #5 clk = ~clk;

    IMEM dut (
        .clk(clk), .rst(rst), .released(released),
        .fetch_addr(fetch_addr), .fetch_data(fetch_data), .fetch_stall(fetch_stall),
        .locked(locked), .zero_en(zero_en), .zero_addr(zero_addr),
        .reg_wen(reg_wen), .reg_waddr(reg_waddr), .reg_wdata(reg_wdata), .reg_wstrb(reg_wstrb),
        .reg_raddr(reg_raddr), .reg_rdata(reg_rdata), .werr(werr), .rerr(rerr)
    );

    task automatic chk(input logic [31:0] got, input logic [31:0] want, input string what);
        checks++;
        if (got !== want) begin
            errors++;
            $display("  FAIL %s: got %h, want %h", what, got, want);
        end
    endtask

    // Inputs change right after a rising edge, the memory works on the next one
    task automatic write(input int word, input logic [31:0] data, input logic [3:0] strb, input logic want_err,
                         input string what);
        @(posedge clk); #1;
        reg_waddr = BASE + word * 4; reg_wdata = data; reg_wstrb = strb; reg_wen = 1;
        #1 chk(werr, want_err, what);
        @(posedge clk); #1;
        reg_wen = 0;
    endtask

    task automatic read_secure(input int word, input logic [31:0] want, input string what);
        @(posedge clk); #1;
        reg_raddr = BASE + word * 4;
        @(posedge clk); #1;
        chk(rerr, 1'b0, {what, " (no error)"});
        chk(reg_rdata, want, what);
    endtask

    task automatic fetch(input int word, input logic [31:0] want, input string what);
        @(posedge clk); #1;
        fetch_addr = word * 4;
        #1 chk(fetch_stall, 1'b1, {what, " (new address stalls)"});
        @(posedge clk); #1;
        chk(fetch_stall, 1'b0, {what, " (ready after one cycle)"});
        chk(fetch_data, want, what);
    endtask

    initial begin
        repeat (3) @(posedge clk);
        #1 rst = 0;

        // ---- unlocked: write whole words, no reads ----
        for (int i = 0; i < WORDS; i++) begin
            ref_mem[i] = $urandom;
            write(i, ref_mem[i], 4'hF, 1'b0, "unlocked word write accepted");
        end
        @(posedge clk); #1 reg_raddr = BASE;
        #1 chk(rerr, 1'b1, "unlocked read refused");
        write(5, 32'hDEAD_BEEF, 4'h1, 1'b1, "byte write refused");
        write(6, 32'hDEAD_BEEF, 4'hC, 1'b1, "halfword write refused");

        // ---- locked: read, no writes ----
        @(posedge clk); #1 locked = 1;
        read_secure(5, ref_mem[5], "byte write changed nothing");
        read_secure(6, ref_mem[6], "halfword write changed nothing");
        write(7, 32'h1234_5678, 4'hF, 1'b1, "locked write refused");
        read_secure(7, ref_mem[7], "locked write changed nothing");
        for (int i = 0; i < WORDS; i += 7)
            read_secure(i, ref_mem[i], "locked read");

        // ---- released: fetch only ----
        @(posedge clk); #1 released = 1;
        for (int i = 1; i < WORDS; i += 7)
            fetch(i, ref_mem[i], "fetch");               // ends on the last word (APP_VER)
        fetch(0, ref_mem[0], "fetch of the first word");
        // low power: a held address does not read the RAM again (backdoor change must stay invisible)
        dut.ram[0] = ~ref_mem[0];
        repeat (3) @(posedge clk);
        #1 chk(fetch_stall, 1'b0, "held address does not stall");
        chk(fetch_data, ref_mem[0], "held address does not read the RAM again");
        dut.ram[0] = ref_mem[0];
        // outside the 4 KB: an all-zero word (illegal instruction), never an alias of word 0
        fetch(WORDS, 32'h0, "fetch one word past the end");
        fetch(0, ref_mem[0], "fetch back inside");
        fetch(32'h1000_0000, 32'h0, "fetch with only a high address bit set");
        chk(reg_rdata, 32'h0, "no data on the Secure read port after release");
        @(posedge clk); #1 reg_raddr = BASE;
        @(posedge clk); #1 chk(rerr, 1'b1, "read after release refused");
        write(8, 32'h1234_5678, 4'hF, 1'b1, "write after release refused");
        // VERIFY_GATE = 0 can release an unlocked IMEM: the release alone must refuse the write
        @(posedge clk); #1 locked = 0;
        write(9, 32'h1234_5678, 4'hF, 1'b1, "write after release refused although unlocked");
        @(posedge clk); #1 locked = 1;

        // ---- a system reset holds the Normal core again, the words are still there ----
        @(posedge clk); #1 released = 0;
        read_secure(8, ref_mem[8], "write after release changed nothing");
        read_secure(9, ref_mem[9], "unlocked write after release changed nothing");

        // ---- Boot Guard zeroization works although the memory is locked ----
        for (int i = 0; i < WORDS; i++) begin
            @(posedge clk); #1;
            zero_addr = i; zero_en = 1;
        end
        @(posedge clk); #1 zero_en = 0;
        for (int i = 0; i < WORDS; i++)
            read_secure(i, 32'h0, "zeroized word");

        $display("checks=%0d errors=%0d", checks, errors);
        $display("IMEM_tb RESULT: %s", (errors == 0 && checks > 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
