`timescale 1ns/1ps
// Behavioural AXI4-Lite slave (plain SystemVerilog, no UVM).
//  - Sparse memory (associative array), unwritten addresses read 0, WSTRB supported.
//  - Random READY/response delay: +SLAVE_MAX_DELAY=<n> (default 3, 0 = no delay).
//  - AW and W are accepted independently in any order. BVALID rises only after both arrive.
//  - BVALID/RVALID stay high until the master raises BREADY/RREADY.
//  - At most 1 write and 1 read in flight.
//  - Reset clears the whole memory (the scoreboard clears its model on reset too).
module axi4_lite_slave_model #(
    parameter int unsigned DEFAULT_MAX_DELAY = 3
)(
    input  logic        clk,
    input  logic        rst_n,
    // AW
    input  logic [31:0] awaddr,
    input  logic        awvalid,
    output logic        awready,
    // W
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    input  logic        wvalid,
    output logic        wready,
    // B
    output logic [1:0]  bresp,
    output logic        bvalid,
    input  logic        bready,
    // AR
    input  logic [31:0] araddr,
    input  logic        arvalid,
    output logic        arready,
    // R
    output logic [31:0] rdata,
    output logic [1:0]  rresp,
    output logic        rvalid,
    input  logic        rready
);

    int unsigned max_delay;
    initial begin
        if (!$value$plusargs("SLAVE_MAX_DELAY=%d", max_delay))
            max_delay = DEFAULT_MAX_DELAY;
    end

    logic [31:0] mem [bit [29:0]];

    function automatic bit pick();                 // 1 -> READY may be raised this cycle
        if (max_delay == 0)
            return 1'b1;
        return ($urandom_range(max_delay, 0) == 0);
    endfunction

    function automatic int unsigned rnd_delay();
        if (max_delay == 0)
            return 0;
        return $urandom_range(max_delay, 0);
    endfunction

    function automatic void do_write(input logic [31:0] a, input logic [31:0] d,
                                                                      input logic [3:0] s);
        bit [29:0]   idx = a[31:2];
        logic [31:0] cur = mem.exists(idx) ? mem[idx] : 32'h0;
        for (int i = 0; i < 4; i++)
            if (s[i])
                cur[8*i +: 8] = d[8*i +: 8];
        mem[idx] = cur;
    endfunction

    function automatic logic [31:0] do_read(input logic [31:0] a);
        bit [29:0] idx = a[31:2];
        return mem.exists(idx) ? mem[idx] : 32'h0;
    endfunction

    // Write path
    logic        have_aw, have_w, b_pend;
    logic [31:0] aw_addr_q, w_data_q;
    logic [3:0]  w_strb_q;
    int unsigned b_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            awready <= 1'b0;
            wready <= 1'b0;
            bvalid  <= 1'b0;
            bresp  <= 2'b00;
            have_aw <= 1'b0;
            have_w <= 1'b0;
            b_pend  <= 1'b0;
            b_cnt  <= 0;
            mem.delete();
        end else begin
            // 1) complete the AW / W handshakes
            if (awvalid && awready) begin
                aw_addr_q <= awaddr;
                have_aw <= 1'b1;
                awready <= 1'b0;
            end
            if (wvalid && wready) begin
                w_data_q <= wdata;
                w_strb_q <= wstrb;
                have_w <= 1'b1;
                wready <= 1'b0;
            end
            // 2) raise READY at random while there is room
            if (!have_aw && !awready && !b_pend && !bvalid && pick())
                awready <= 1'b1;
            if (!have_w  && !wready  && !b_pend && !bvalid && pick())
                wready  <= 1'b1;
            // 3) AW and W both in -> write memory, schedule the B response
            if (have_aw && have_w && !b_pend && !bvalid) begin
                do_write(aw_addr_q, w_data_q, w_strb_q);
                have_aw <= 1'b0;
                have_w <= 1'b0;
                b_pend  <= 1'b1;
                b_cnt  <= rnd_delay();
            end
            // 4) raise BVALID after the delay
            if (b_pend) begin
                if (b_cnt == 0) begin
                    bvalid <= 1'b1;
                    bresp <= 2'b00;
                    b_pend <= 1'b0;
                end else begin
                    b_cnt <= b_cnt - 1;
                end
            end
            // 5) B handshake
            if (bvalid && bready)
                bvalid <= 1'b0;
        end
    end

    // Read path
    logic        r_pend;
    logic [31:0] ar_addr_q;
    int unsigned r_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            arready <= 1'b0;
            rvalid <= 1'b0;
            rdata   <= 32'h0;
            rresp  <= 2'b00;
            r_pend  <= 1'b0;
            r_cnt  <= 0;
        end else begin
            if (arvalid && arready) begin
                ar_addr_q <= araddr;
                arready <= 1'b0;
                r_pend    <= 1'b1;
                r_cnt   <= rnd_delay();
            end
            if (!arready && !r_pend && !rvalid && pick())
                arready <= 1'b1;
            if (r_pend) begin
                if (r_cnt == 0) begin
                    rvalid <= 1'b1;
                    rdata <= do_read(ar_addr_q);
                    rresp <= 2'b00;
                    r_pend <= 1'b0;
                end else begin
                    r_cnt <= r_cnt - 1;
                end
            end
            if (rvalid && rready)
                rvalid <= 1'b0;
        end
    end
endmodule
