// Một giao dịch AXI4-Lite (ghi hoặc đọc)
class axi4_lite_item extends uvm_sequence_item;

  // ---- Kích thích (rand) ----
  rand bit          is_write;     // 1: ghi, 0: đọc
  rand bit [31:0]   addr;
  rand bit [31:0]   data;         // WDATA (khi ghi)
  rand bit [3:0]    wstrb;
  // Độ trễ (số chu kỳ) để tạo back-pressure / các thứ tự kênh khác nhau
  rand int unsigned addr_delay;   // trước khi đưa AWVALID/WVALID(ghi) hoặc ARVALID(đọc)
  rand int unsigned data_delay;   // trước khi đưa WVALID (chỉ ghi)
  rand int unsigned resp_delay;   // trước khi đưa BREADY/RREADY

  // ---- Kết quả thu được ----
  bit [31:0]        rdata;
  bit [1:0]         bresp;
  bit [1:0]         rresp;

  `uvm_object_utils(axi4_lite_item)

  constraint c_align { addr[1:0] == 2'b00; }
  constraint c_strb  { soft wstrb == 4'hF; }
  constraint c_delay { addr_delay <= 8; data_delay <= 8; resp_delay <= 8; }

  function new(string name = "axi4_lite_item");
    super.new(name);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    axi4_lite_item r;
    if (!$cast(r, rhs)) `uvm_fatal("CAST", "do_copy: sai kieu axi4_lite_item")
    super.do_copy(rhs);
    is_write   = r.is_write;
    addr       = r.addr;
    data       = r.data;
    wstrb      = r.wstrb;
    addr_delay = r.addr_delay;
    data_delay = r.data_delay;
    resp_delay = r.resp_delay;
    rdata      = r.rdata;
    bresp      = r.bresp;
    rresp      = r.rresp;
  endfunction

  virtual function string convert2string();
    if (is_write)
      return $sformatf("WR addr=0x%08h data=0x%08h strb=%04b bresp=%0d",
                       addr, data, wstrb, bresp);
    else
      return $sformatf("RD addr=0x%08h data=0x%08h rresp=%0d",
                       addr, rdata, rresp);
  endfunction
endclass