`timescale 1ns / 1ps
// RAM_Macro_tb: random test of the two SRAM macro wrappers against a reference array.
//  1. RAM_Macro_Core (App RAM): a core-like driver keeps its request while stall = 1. Checks the data,
//     the exact number of stall cycles (read 1, partial write 1, full write 0), SB/SH/any byte mask,
//     and a zeroization sweep with full-word writes
//  2. RAM_Macro_Axi (Master RAM) behind the real AXI4_Lite_Slave_Template: random reads, full and
//     partial writes with 0 to 3 idle cycles between transactions. A transaction starts the cycle after
//     the previous B or R handshake, the fastest SoC_Top allows (bus_idle). Also checks that the
//     read-modify-write cycle never meets a new write strobe
// Run from sim/: vsim -c -do run_ram.do. Ends with "RAM_Macro_tb RESULT: PASS|FAIL".
module RAM_Macro_tb;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;

    integer errors = 0;
    integer checks = 0;

    task automatic expect32(input [31:0] got, input [31:0] exp, input string what);
        checks = checks + 1;
        if (got !== exp) begin
            errors = errors + 1;
            if (errors <= 10) $display("FAIL: %0s got %h expected %h (t=%0t)", what, got, exp, $time);
        end
    endtask

    // ------------------------------------------------------------------ 1. RAM_Macro_Core
    reg         c_wr = 1'b0, c_rd = 1'b0;
    reg  [31:0] c_addr = 32'h0, c_wdata = 32'h0;
    reg  [3:0]  c_wstrb = 4'h0;
    wire [31:0] c_rdata;
    wire        c_stall;
    reg  [31:0] ref_c [0:1023];

    RAM_Macro_Core u_core (.clk(clk), .rst(rst), .MemWrite(c_wr), .MemRead(c_rd), .addr(c_addr),
                           .write_data(c_wdata), .wstrb(c_wstrb), .read_data(c_rdata), .stall(c_stall));

    function automatic [31:0] merge(input [31:0] old, input [31:0] nw, input [3:0] s);
        merge = {s[3] ? nw[31:24] : old[31:24], s[2] ? nw[23:16] : old[23:16],
                 s[1] ? nw[15:8]  : old[15:8],  s[0] ? nw[7:0]   : old[7:0]};
    endfunction

    // One access of the core. Called at a rising edge plus 1 ns, returns at the next one that ends it
    task automatic core_op(input bit rd, input bit wr, input [9:0] w, input [31:0] d, input [3:0] s);
        integer stalls;
        integer want;
        bit     done;
        begin
            c_rd = rd; c_wr = wr; c_addr = {20'h0, w, 2'b00}; c_wdata = d; c_wstrb = s;
            want = rd ? 1 : ((wr && s != 4'hF) ? 1 : 0);
            stalls = 0;
            done = 0;
            while (!done) begin
                @(posedge clk);
                if (c_stall) stalls = stalls + 1;
                else begin
                    if (rd) expect32(c_rdata, ref_c[w], "core read data");
                    if (wr) ref_c[w] = merge(ref_c[w], d, s);
                    expect32(stalls, want, "core stall cycles");
                    done = 1;
                end
                if (stalls > 4) begin
                    errors = errors + 1;
                    $display("FAIL: core stall never ended");
                    done = 1;
                end
            end
        end
    endtask

    task automatic core_idle(input integer n);
        begin
            c_rd = 1'b0; c_wr = 1'b0; c_wstrb = 4'h0;
            repeat (n) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------ 2. RAM_Macro_Axi
    reg         awvalid = 0, wvalid = 0, bready = 1, arvalid = 0, rready = 1;
    reg  [31:0] awaddr = 0, wdata = 0, araddr = 0;
    reg  [3:0]  wstrb = 0;
    wire        awready, wready, bvalid, arready, rvalid;
    wire [1:0]  bresp, rresp;
    wire [31:0] rdata;
    wire        reg_wen;
    wire [31:0] reg_waddr, reg_wdata, reg_raddr, reg_rdata;
    wire [3:0]  reg_wstrb;
    reg  [31:0] ref_a [0:1023];

    AXI4_Lite_Slave_Template u_axi (
        .clk(clk), .reset(rst),
        .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready), .S_AXI_AWADDR(awaddr),
        .S_AXI_WVALID(wvalid),   .S_AXI_WREADY(wready),   .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb),
        .S_AXI_BVALID(bvalid),   .S_AXI_BREADY(bready),   .S_AXI_BRESP(bresp),
        .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready), .S_AXI_ARADDR(araddr),
        .S_AXI_RVALID(rvalid),   .S_AXI_RREADY(rready),   .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp),
        .reg_wen(reg_wen), .reg_waddr(reg_waddr), .reg_wdata(reg_wdata), .reg_wstrb(reg_wstrb),
        .reg_raddr(reg_raddr), .reg_rdata(reg_rdata));

    RAM_Macro_Axi u_ram (.clk(clk), .rst(rst), .reg_wen(reg_wen), .reg_waddr(reg_waddr),
                         .reg_wdata(reg_wdata), .reg_wstrb(reg_wstrb), .reg_raddr(reg_raddr),
                         .reg_rdata(reg_rdata));

    // The write cycle of a read-modify-write (pend_q) must never meet a new write strobe
    always @(posedge clk) if (!rst && u_ram.pend_q && reg_wen) begin
        errors = errors + 1;
        $display("FAIL: new write strobe in the cycle of a read-modify-write (t=%0t)", $time);
    end

    // Called at a rising edge plus 1 ns, returns at the edge that ends the B handshake
    task automatic axi_write(input [9:0] w, input [31:0] d, input [3:0] s);
        begin
            awvalid = 1; awaddr = {20'h0, w, 2'b00}; wvalid = 1; wdata = d; wstrb = s;
            do @(posedge clk); while (!(awready && wready));
            // AXI leaves the payload undefined once VALID is low, so the wrapper must keep its own copy
            #1; awvalid = 0; wvalid = 0; awaddr = $urandom; wdata = $urandom; wstrb = $urandom;
            do @(posedge clk); while (!bvalid);
            ref_a[w] = merge(ref_a[w], d, s);
        end
    endtask

    task automatic axi_read(input [9:0] w);
        begin
            arvalid = 1; araddr = {20'h0, w, 2'b00};
            do @(posedge clk); while (!arready);
            #1; arvalid = 0; araddr = $urandom;
            do @(posedge clk); while (!rvalid);
            expect32(rdata, ref_a[w], "axi read data");
        end
    endtask

    // ------------------------------------------------------------------ test
    integer i, n, r, nops;
    reg [9:0]  wa;
    reg [3:0]  ws;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin ref_c[i] = 32'h0; ref_a[i] = 32'h0; end
        repeat (3) @(posedge clk);
        #1 rst = 1'b0;
        @(posedge clk); #1;

        // The macro starts unknown. Write zero everywhere first, as the Boot Guard zeroization does
        for (i = 0; i < 1024; i = i + 1) begin core_op(0, 1, i[9:0], 32'h0, 4'hF); #1; end

        // 1. Core wrapper: random mix on a small window (many hits on the same word), then on all words
        for (n = 0; n < 6000; n = n + 1) begin
            wa = (n < 4000) ? $urandom_range(0, 31) : $urandom_range(0, 1023);
            r  = $urandom_range(0, 99);
            if (r < 35)      core_op(1, 0, wa, 32'h0, 4'h0);
            else if (r < 60) core_op(0, 1, wa, $urandom, 4'hF);
            else begin
                ws = $urandom_range(1, 14);
                core_op(0, 1, wa, $urandom, ws);
            end
            #1;
            if ($urandom_range(0, 3) == 0) begin core_idle($urandom_range(1, 3)); #1; end
        end
        // SB, SH exactly as the core does them
        core_op(0, 1, 10'd5, 32'hAABBCCDD, 4'hF); #1;
        core_op(0, 1, 10'd5, 32'h000000EE, 4'h1); #1;
        core_op(0, 1, 10'd5, 32'h11220000, 4'hC); #1;
        core_op(1, 0, 10'd5, 32'h0, 4'h0); #1;
        expect32(ref_c[5], 32'h1122CCEE, "SB then SH reference");
        // Zeroization sweep: full-word zero writes of every word, then read all back
        for (i = 0; i < 1024; i = i + 1) begin core_op(0, 1, i[9:0], 32'h0, 4'hF); #1; end
        for (i = 0; i < 1024; i = i + 1) begin core_op(1, 0, i[9:0], 32'h0, 4'h0); #1; end
        core_idle(2);

        // 2. AXI wrapper
        #1;
        for (i = 0; i < 1024; i = i + 1) begin axi_write(i[9:0], 32'h0, 4'hF); #1; end
        for (n = 0; n < 6000; n = n + 1) begin
            wa = (n < 4000) ? $urandom_range(0, 31) : $urandom_range(0, 1023);
            r  = $urandom_range(0, 99);
            if (r < 40)      axi_read(wa);
            else if (r < 60) axi_write(wa, $urandom, 4'hF);
            else begin
                ws = $urandom_range(1, 14);
                axi_write(wa, $urandom, ws);
            end
            #1;
            repeat ($urandom_range(0, 3)) begin @(posedge clk); #1; end
        end
        // Write then read the same word with no gap, partial and full
        axi_write(10'd7, 32'hDEADBEEF, 4'hF); #1;
        axi_write(10'd7, 32'h000000AA, 4'h1); #1;
        axi_read(10'd7); #1;
        expect32(ref_a[7], 32'hDEADBEAA, "axi SB reference");
        for (i = 0; i < 1024; i = i + 1) begin axi_read(i[9:0]); #1; end

        $display("RAM_Macro_tb: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("RAM_Macro_tb RESULT: PASS");
        else             $display("RAM_Macro_tb RESULT: FAIL");
        $finish;
    end

    initial begin
        #200000000;
        $display("RAM_Macro_tb RESULT: FAIL (timeout)");
        $finish;
    end
endmodule
