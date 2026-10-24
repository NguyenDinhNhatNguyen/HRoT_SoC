`timescale 1ns/1ps
// Slave AXI4-Lite mô hình hành vi (thuần SystemVerilog, không dùng UVM).
//  - Bộ nhớ thưa (associative array), địa chỉ chưa ghi đọc ra 0, hỗ trợ WSTRB.
//  - READY/phản hồi có độ trễ ngẫu nhiên: +SLAVE_MAX_DELAY=<n> (mặc định 3, 0 = không trễ).
//  - AW và W được nhận độc lập, ở thứ tự bất kỳ; BVALID chỉ lên sau khi có đủ cả hai.
//  - BVALID/RVALID được giữ cho tới khi master đưa BREADY/RREADY.
//  - Mỗi lúc chỉ có 1 giao dịch ghi và 1 giao dịch đọc đang xử lý.
//  - Reset xóa toàn bộ bộ nhớ (scoreboard cũng xóa mô hình khi reset).
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

  function automatic bit pick();                 // 1 -> được phép mở READY ở chu kỳ này
    if (max_delay == 0) return 1'b1;
    return ($urandom_range(max_delay, 0) == 0);
  endfunction

  function automatic int unsigned rnd_delay();
    if (max_delay == 0) return 0;
    return $urandom_range(max_delay, 0);
  endfunction

  function automatic void do_write(input logic [31:0] a, input logic [31:0] d,
                                   input logic [3:0] s);
    bit [29:0]   idx = a[31:2];
    logic [31:0] cur = mem.exists(idx) ? mem[idx] : 32'h0;
    for (int i = 0; i < 4; i++)
      if (s[i]) cur[8*i +: 8] = d[8*i +: 8];
    mem[idx] = cur;
  endfunction

  function automatic logic [31:0] do_read(input logic [31:0] a);
    bit [29:0] idx = a[31:2];
    return mem.exists(idx) ? mem[idx] : 32'h0;
  endfunction

  // ------------------------------------------------------------- Write path
  logic        have_aw, have_w, b_pend;
  logic [31:0] aw_addr_q, w_data_q;
  logic [3:0]  w_strb_q;
  int unsigned b_cnt;

  always @(posedge clk) begin
    if (!rst_n) begin
      awready <= 1'b0;  wready <= 1'b0;
      bvalid  <= 1'b0;  bresp  <= 2'b00;
      have_aw <= 1'b0;  have_w <= 1'b0;
      b_pend  <= 1'b0;  b_cnt  <= 0;
      mem.delete();
    end else begin
      // 1) hoàn tất handshake AW / W
      if (awvalid && awready) begin
        aw_addr_q <= awaddr;  have_aw <= 1'b1;  awready <= 1'b0;
      end
      if (wvalid && wready) begin
        w_data_q <= wdata;  w_strb_q <= wstrb;  have_w <= 1'b1;  wready <= 1'b0;
      end
      // 2) mở READY ngẫu nhiên khi còn chỗ nhận
      if (!have_aw && !awready && !b_pend && !bvalid && pick()) awready <= 1'b1;
      if (!have_w  && !wready  && !b_pend && !bvalid && pick()) wready  <= 1'b1;
      // 3) đủ AW và W -> ghi bộ nhớ, hẹn phản hồi B
      if (have_aw && have_w && !b_pend && !bvalid) begin
        do_write(aw_addr_q, w_data_q, w_strb_q);
        have_aw <= 1'b0;  have_w <= 1'b0;
        b_pend  <= 1'b1;  b_cnt  <= rnd_delay();
      end
      // 4) phát BVALID sau độ trễ
      if (b_pend) begin
        if (b_cnt == 0) begin
          bvalid <= 1'b1;  bresp <= 2'b00;  b_pend <= 1'b0;
        end else begin
          b_cnt <= b_cnt - 1;
        end
      end
      // 5) B handshake
      if (bvalid && bready) bvalid <= 1'b0;
    end
  end

  // -------------------------------------------------------------- Read path
  logic        r_pend;
  logic [31:0] ar_addr_q;
  int unsigned r_cnt;

  always @(posedge clk) begin
    if (!rst_n) begin
      arready <= 1'b0;  rvalid <= 1'b0;
      rdata   <= 32'h0; rresp  <= 2'b00;
      r_pend  <= 1'b0;  r_cnt  <= 0;
    end else begin
      if (arvalid && arready) begin
        ar_addr_q <= araddr;  arready <= 1'b0;
        r_pend    <= 1'b1;    r_cnt   <= rnd_delay();
      end
      if (!arready && !r_pend && !rvalid && pick()) arready <= 1'b1;
      if (r_pend) begin
        if (r_cnt == 0) begin
          rvalid <= 1'b1;  rdata <= do_read(ar_addr_q);  rresp <= 2'b00;  r_pend <= 1'b0;
        end else begin
          r_cnt <= r_cnt - 1;
        end
      end
      if (rvalid && rready) rvalid <= 1'b0;
    end
  end
endmodule
