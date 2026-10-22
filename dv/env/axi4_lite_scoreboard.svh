// Scoreboard: giữ mô hình bộ nhớ tham chiếu (theo word, có xử lý WSTRB).
//  - Ghi : kiểm tra BRESP; chỉ cập nhật mô hình khi BRESP = OKAY.
//  - Đọc : so RDATA với mô hình (địa chỉ chưa ghi => cfg.default_read_value),
//          kiểm tra RRESP = OKAY.
class axi4_lite_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(axi4_lite_scoreboard)

  uvm_analysis_imp #(axi4_lite_item, axi4_lite_scoreboard) item_export;
  axi4_lite_agent_cfg cfg;

  bit [31:0]   mem [bit [31:0]];
  int unsigned n_wr, n_rd, n_err;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    item_export = new("item_export", this);
    if (!uvm_config_db#(axi4_lite_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "axi4_lite_scoreboard: khong tim thay cfg")
  endfunction

  function void write(axi4_lite_item t);
    bit [31:0] key = {t.addr[31:2], 2'b00};
    bit [31:0] cur;
    bit [31:0] exp;

    if (t.is_write) begin
      n_wr++;
      if (t.bresp === 2'b00) begin
        // Chỉ ghi vào mô hình khi slave xác nhận thành công (OKAY)
        cur = mem.exists(key) ? mem[key] : cfg.default_read_value;
        for (int i = 0; i < 4; i++)
          if (t.wstrb[i]) cur[8*i +: 8] = t.data[8*i +: 8];
        mem[key] = cur;
        `uvm_info("SCB", $sformatf("Cap nhat mo hinh: addr=0x%08h data=0x%08h", key, cur), UVM_HIGH)
      end else if (cfg.check_resp) begin
        // Response lỗi: không cập nhật mô hình (coi như ghi không có hiệu lực)
        n_err++;
        `uvm_error("SCB", $sformatf("BRESP khong phai OKAY, bo qua cap nhat mo hinh: %s", t.convert2string()))
      end
    end else begin
      n_rd++;
      exp = mem.exists(key) ? mem[key] : cfg.default_read_value;
      if (t.rdata !== exp) begin
        n_err++;
        `uvm_error("SCB", $sformatf("Sai du lieu doc: addr=0x%08h expected=0x%08h actual=0x%08h",
                                    t.addr, exp, t.rdata))
      end else begin
        `uvm_info("SCB", $sformatf("Doc khop: addr=0x%08h data=0x%08h", t.addr, t.rdata), UVM_HIGH)
      end
      if (cfg.check_resp && t.rresp !== 2'b00) begin
        n_err++;
        `uvm_error("SCB", $sformatf("RRESP khong phai OKAY: %s", t.convert2string()))
      end
    end
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (n_wr + n_rd == 0)
      `uvm_error("SCB", "Scoreboard khong nhan duoc giao dich nao (kiem tra monitor/ket noi)")
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB", $sformatf("Tong ket: ghi=%0d doc=%0d loi=%0d", n_wr, n_rd, n_err), UVM_NONE)
  endfunction
endclass