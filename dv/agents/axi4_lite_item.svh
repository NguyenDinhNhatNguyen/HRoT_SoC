// One AXI4-Lite transaction (write or read)
class axi4_lite_item extends uvm_sequence_item;

    // Stimulus (rand)
    rand bit          is_write;     // 1: write, 0: read
    rand bit [31:0]   addr;
    rand bit [31:0]   data;         // WDATA (write only)
    rand bit [3:0]    wstrb;
    // Delays (cycles) to create back-pressure and different channel orders
    rand int unsigned addr_delay;   // before AWVALID/WVALID (write) or ARVALID (read)
    rand int unsigned data_delay;   // before WVALID (write only)
    rand int unsigned resp_delay;   // before BREADY/RREADY

    // Results
    bit [31:0]        rdata;
    bit [1:0]         bresp;
    bit [1:0]         rresp;
    bit               aborted;      // 1: aborted by a reset mid-transaction (rdata/resp invalid)
    // Monitor only: time of the clock edge where the slave took the request (AW and W both done for a
    // write, AR for a read). Register slaves act on that edge, so scoreboards order events by it (P-17)
    time              accept_time;
    // Monitor only, for coverage (P-19): edges where AWVALID (ARVALID for a read) and WVALID were first
    // seen high, and edge of the B/R handshake
    time              a_time;
    time              w_time;
    time              resp_time;

    `uvm_object_utils(axi4_lite_item)

    constraint c_align { addr[1:0] == 2'b00; }
    constraint c_strb  { soft wstrb == 4'hF; }
    constraint c_delay { addr_delay <= 8; data_delay <= 8; resp_delay <= 8; }

    function new(string name = "axi4_lite_item");
        super.new(name);
    endfunction

    virtual function void do_copy(uvm_object rhs);
        axi4_lite_item r;
        if (!$cast(r, rhs))
            `uvm_fatal("CAST", "do_copy: rhs is not an axi4_lite_item")
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
        aborted    = r.aborted;
        accept_time = r.accept_time;
        a_time      = r.a_time;
        w_time      = r.w_time;
        resp_time   = r.resp_time;
    endfunction

    virtual function string convert2string();
        string s;
        if (is_write)
            s = $sformatf("WR addr=0x%08h data=0x%08h strb=%04b bresp=%0d",
                                        addr, data, wstrb, bresp);
        else
            s = $sformatf("RD addr=0x%08h data=0x%08h rresp=%0d",
                                        addr, rdata, rresp);
        return aborted ? {s, " [ABORTED]"} : s;
    endfunction
endclass
