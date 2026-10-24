`ifndef AXI4_LITE_IF_SV
`define AXI4_LITE_IF_SV
`timescale 1ns/1ps

// AXI4-Lite interface (reset active-low).
//  - drv_cb : clocking block cho Driver (lái tín hiệu phía Master, lấy mẫu phía Slave)
//  - mon_cb : clocking block cho Monitor (chỉ lấy mẫu)
//  - SVA    : kiểm tra giao thức (tắt bằng +define+AXI4_LITE_NO_ASSERT)
// Lưu ý: RTL của dự án dùng reset active-high ("reset"), khi ghép phải nối ~rst_n.
interface axi4_lite_if (input logic clk, input logic rst_n);

  // Write address channel
  logic [31:0] awaddr;
  logic        awvalid;
  logic        awready;
  // Write data channel
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wvalid;
  logic        wready;
  // Write response channel
  logic [1:0]  bresp;
  logic        bvalid;
  logic        bready;
  // Read address channel
  logic [31:0] araddr;
  logic        arvalid;
  logic        arready;
  // Read data channel
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rvalid;
  logic        rready;

  // Đếm số lần SVA thất bại. $error của SVA KHÔNG vào bộ đếm lỗi của UVM,
  // nên base_test.check_phase đọc biến này và báo uvm_error nếu khác 0.
  int unsigned assert_fail_count = 0;

  // Dem so lan reset (canh xuong rst_n). Sequence so sanh truoc/sau mot thao tac nhieu giao dich
  // de biet DUT co bi reset giua chung khong (driver chi huy duoc giao dich dang chay).
  int unsigned reset_count = 0;
  always @(negedge rst_n) reset_count++;

  clocking drv_cb @(posedge clk);
    output awaddr, awvalid, wdata, wstrb, wvalid, bready, araddr, arvalid, rready;
    input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid;
  endclocking

  clocking mon_cb @(posedge clk);
    input rst_n;
    input awaddr, awvalid, awready, wdata, wstrb, wvalid, wready;
    input bresp, bvalid, bready;
    input araddr, arvalid, arready, rdata, rresp, rvalid, rready;
  endclocking

`ifndef AXI4_LITE_NO_ASSERT
  // VALID đã lên thì phải giữ VALID và dữ liệu ổn định cho tới khi có READY
  a_aw_stable : assert property (@(posedge clk) disable iff (!rst_n)
      (awvalid && !awready) |=> (awvalid && $stable(awaddr)))
    else begin assert_fail_count++; $error("AXI4L: AWVALID/AWADDR thay doi truoc khi co AWREADY"); end
  a_w_stable  : assert property (@(posedge clk) disable iff (!rst_n)
      (wvalid && !wready) |=> (wvalid && $stable(wdata) && $stable(wstrb)))
    else begin assert_fail_count++; $error("AXI4L: WVALID/WDATA/WSTRB thay doi truoc khi co WREADY"); end
  a_ar_stable : assert property (@(posedge clk) disable iff (!rst_n)
      (arvalid && !arready) |=> (arvalid && $stable(araddr)))
    else begin assert_fail_count++; $error("AXI4L: ARVALID/ARADDR thay doi truoc khi co ARREADY"); end
  a_b_stable  : assert property (@(posedge clk) disable iff (!rst_n)
      (bvalid && !bready) |=> (bvalid && $stable(bresp)))
    else begin assert_fail_count++; $error("AXI4L: BVALID/BRESP thay doi truoc khi co BREADY"); end
  a_r_stable  : assert property (@(posedge clk) disable iff (!rst_n)
      (rvalid && !rready) |=> (rvalid && $stable(rdata) && $stable(rresp)))
    else begin assert_fail_count++; $error("AXI4L: RVALID/RDATA/RRESP thay doi truoc khi co RREADY"); end
  // Không có X trên tín hiệu điều khiển sau reset
  a_no_x : assert property (@(posedge clk) disable iff (!rst_n)
      !$isunknown({awvalid, awready, wvalid, wready, bvalid, bready,
                   arvalid, arready, rvalid, rready}))
    else begin assert_fail_count++; $error("AXI4L: tin hieu VALID/READY bi X/Z"); end
`endif

endinterface
`endif
