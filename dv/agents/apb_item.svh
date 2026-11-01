// One APB transfer (P-17)
class apb_item extends uvm_sequence_item;
    rand bit          is_write;
    rand bit [31:0]   addr;
    rand bit [31:0]   data;         // PWDATA (write only)
    rand bit [3:0]    strb;
    rand int unsigned idle;         // idle cycles before the setup phase

    bit [31:0]        rdata;
    bit               slverr;
    bit               aborted;      // reset mid-transfer: rdata/slverr invalid
    int unsigned      waits;        // monitor: wait states the slave inserted
    time              done_time;    // monitor: edge where the transfer completed (PREADY high)
    string            bus;          // monitor: cfg.bus_name

    `uvm_object_utils(apb_item)

    constraint c_align { addr[1:0] == 2'b00; }
    constraint c_strb  { soft strb == 4'hF; }
    constraint c_idle  { idle dist {0 := 6, [1:3] := 3, [4:8] := 1}; }

    function new(string name = "apb_item");
        super.new(name);
    endfunction

    virtual function void do_copy(uvm_object rhs);
        apb_item r;
        if (!$cast(r, rhs))
            `uvm_fatal("CAST", "do_copy: rhs is not an apb_item")
        super.do_copy(rhs);
        is_write  = r.is_write;
        addr      = r.addr;
        data      = r.data;
        strb      = r.strb;
        idle      = r.idle;
        rdata     = r.rdata;
        slverr    = r.slverr;
        aborted   = r.aborted;
        waits     = r.waits;
        done_time = r.done_time;
        bus       = r.bus;
    endfunction

    virtual function string convert2string();
        string s;
        if (is_write)
            s = $sformatf("%s WR addr=0x%08h data=0x%08h strb=%04b slverr=%0d", bus, addr, data, strb, slverr);
        else
            s = $sformatf("%s RD addr=0x%08h data=0x%08h slverr=%0d", bus, addr, rdata, slverr);
        return aborted ? {s, " [ABORTED]"} : s;
    endfunction
endclass
