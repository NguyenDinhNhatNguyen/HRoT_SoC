`timescale 1ns / 1ps

// IMEM_tb: the shared instruction memory of the two-world design (SoC_Memory_Map.md), written before
// rtl/mem/IMEM.v. It fixes the block's interface and checks:
//   - unlocked: the Secure side writes whole words, reads answer an error
//   - locked  : reads work, writes answer an error and change nothing
//   - byte and halfword writes are refused
//   - the Normal side fetches the stored words and has no write input at all
//   - Boot Guard zeroization clears every word, locked or not
//   - HASHED is set only by a clean DMA run over the locked IMEM, and any later SHA-256 use clears it
module IMEM_tb;
    localparam [31:0] BASE  = 32'h7000_0000;
    localparam [31:0] STORE = 32'h6000_0000;
    localparam        WORDS = 1024;

    logic        clk = 0, rst = 1;
    logic [31:0] fetch_addr = 0;
    logic        locked = 0, zero_en = 0;
    logic [9:0]  zero_addr = 0;
    logic        reg_wen = 0;
    logic [31:0] reg_waddr = BASE, reg_wdata = 0, reg_raddr = BASE;
    logic [3:0]  reg_wstrb = 4'hF;
    logic        dma_start = 0, dma_done_ok = 0, cpu_sha_wr = 0;
    logic [31:0] dma_src = BASE, dma_nblk = 64;
    wire  [31:0] fetch_data, reg_rdata;
    wire         werr, rerr, hashed;

    int checks = 0, errors = 0;
    logic [31:0] ref_mem [0:WORDS-1];

    always #5 clk = ~clk;

    IMEM dut (
        .clk(clk), .rst(rst),
        .fetch_addr(fetch_addr), .fetch_data(fetch_data),
        .locked(locked), .zero_en(zero_en), .zero_addr(zero_addr),
        .reg_wen(reg_wen), .reg_waddr(reg_waddr), .reg_wdata(reg_wdata), .reg_wstrb(reg_wstrb),
        .reg_raddr(reg_raddr), .reg_rdata(reg_rdata), .werr(werr), .rerr(rerr),
        .dma_start(dma_start), .dma_done_ok(dma_done_ok), .dma_src(dma_src), .dma_nblk(dma_nblk),
        .cpu_sha_wr(cpu_sha_wr), .hashed(hashed)
    );

    task automatic chk(input logic [31:0] got, input logic [31:0] want, input string what);
        checks++;
        if (got !== want) begin
            errors++;
            $display("  FAIL %s: got %h, want %h", what, got, want);
        end
    endtask

    // Inputs change right after the rising edge, the memory works on the falling edge
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
        @(negedge clk); #1;
        chk(rerr, 1'b0, {what, " (no error)"});
        chk(reg_rdata, want, what);
    endtask

    task automatic fetch(input int word, input logic [31:0] want, input string what);
        @(posedge clk); #1;
        fetch_addr = word * 4;
        @(negedge clk); #1;
        chk(fetch_data, want, what);
    endtask

    task automatic pulse(ref logic s);
        @(posedge clk); #1; s = 1;
        @(posedge clk); #1; s = 0;
    endtask

    task automatic dma_run(input logic [31:0] src, input logic [31:0] nblk);
        dma_src = src; dma_nblk = nblk;
        pulse(dma_start);
        repeat (3) @(posedge clk);
        pulse(dma_done_ok);
        @(posedge clk); #1;
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
        for (int i = 0; i < WORDS; i += 7) begin
            read_secure(i, ref_mem[i], "locked read");
            fetch(i, ref_mem[i], "fetch");
        end
        fetch(WORDS - 1, ref_mem[WORDS - 1], "fetch of the last word (APP_VER)");

        // ---- HASHED ----
        chk(hashed, 1'b0, "HASHED low before any DMA run");
        dma_run(STORE, 64);
        chk(hashed, 1'b0, "hashing the image store does not set HASHED");
        dma_run(BASE, 63);
        chk(hashed, 1'b0, "a partial run does not set HASHED");
        dma_run(BASE + 64, 64);
        chk(hashed, 1'b0, "a run with a shifted source does not set HASHED");
        dma_run(BASE, 64);
        chk(hashed, 1'b1, "clean run over the locked IMEM sets HASHED");
        pulse(cpu_sha_wr);
        @(posedge clk); #1 chk(hashed, 1'b0, "CPU write to SHA-256 clears HASHED");
        dma_run(BASE, 64);
        dma_run(STORE, 64);
        chk(hashed, 1'b0, "a later run on another source clears HASHED");

        // CPU touches SHA-256 while the DMA is running: the run must not count
        dma_src = BASE; dma_nblk = 64;
        pulse(dma_start);
        pulse(cpu_sha_wr);
        pulse(dma_done_ok);
        @(posedge clk); #1 chk(hashed, 1'b0, "a run disturbed by the CPU does not set HASHED");

        // run started while unlocked
        @(posedge clk); #1 locked = 0;
        dma_run(BASE, 64);
        chk(hashed, 1'b0, "a run started while unlocked does not set HASHED");

        // system reset clears the flag
        @(posedge clk); #1 locked = 1;
        dma_run(BASE, 64);
        @(posedge clk); #1 rst = 1;
        repeat (2) @(posedge clk);
        #1 rst = 0;
        chk(hashed, 1'b0, "reset clears HASHED");

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
