// APB sequences for tb_apb_top (P-17). The scoreboard predicts every read on its own, the directed
// sequence also checks the pins (gpio_o, interrupt lines) and the GPIO input path.
// Secure bus windows: 0x4000_0000 GPIO, 0x4000_1000 TIMER, 0x4000_2000 Mailbox, 0x4000_3000 RAM model,
// 0x4000_4000 and up no slave. App bus: Mailbox App side at 0x4000_3000 (as in the App world map).

class apb_base_seq extends uvm_sequence #(apb_item);
    `uvm_object_utils(apb_base_seq)

    localparam bit [31:0] GPIO  = 32'h4000_0000;
    localparam bit [31:0] TMR   = 32'h4000_1000;
    localparam bit [31:0] MBOXS = 32'h4000_2000;
    localparam bit [31:0] RAM   = 32'h4000_3000;
    localparam bit [31:0] NONE  = 32'h4000_4000;
    localparam bit [31:0] MBOXA = 32'h4000_3000;

    apb_sequencer app_sqr;              // the App bus, for sequences that use both buses
    int unsigned  n_errors;

    function new(string name = "apb_base_seq");
        super.new(name);
    endfunction

    // One transfer on the Secure bus (app = 0) or the App bus (app = 1)
    task op(bit app, bit is_wr, bit [31:0] addr, bit [31:0] data, bit [3:0] strb, output apb_item t);
        t = apb_item::type_id::create("t");
        start_item(t, -1, app ? app_sqr : m_sequencer);
        // Fixed transfer: set the fields, nothing to randomize
        t.is_write = is_wr;
        t.addr     = addr;
        t.data     = data;
        t.strb     = strb;
        t.idle     = 0;
        finish_item(t);
    endtask

    task wr(bit app, bit [31:0] addr, bit [31:0] data, bit [3:0] strb = 4'hF);
        apb_item t;
        op(app, 1'b1, addr, data, strb, t);
    endtask

    task rd(bit app, bit [31:0] addr, output bit [31:0] data);
        apb_item t;
        op(app, 1'b0, addr, 32'h0, 4'h0, t);
        data = t.rdata;
    endtask

    function void check(bit ok, string msg);
        if (!ok) begin
            n_errors++;
            `uvm_error("APB_SEQ", msg)
        end
    endfunction
endclass


// Reads every register of every block after reset, plus unused offsets and windows without a slave
class apb_reset_seq extends apb_base_seq;
    `uvm_object_utils(apb_reset_seq)

    function new(string name = "apb_reset_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] d;
        bit [31:0] bases[4] = '{GPIO, TMR, MBOXS, RAM};
        foreach (bases[b])
            for (int off = 0; off <= 'h10; off += 4)
                rd(1'b0, bases[b] + off, d);
        rd(1'b0, GPIO + 'hFFC, d);
        rd(1'b0, NONE, d);
        rd(1'b0, 32'h4000_F000, d);
        for (int off = 0; off <= 'h10; off += 4)
            rd(1'b1, MBOXA + off, d);
    endtask
endclass


// Random transfers on one bus. Secure bus: weighted over the blocks, the registers, unused offsets,
// windows without a slave, random strobes and idle gaps. App bus: the App side of the Mailbox.
class apb_rand_seq extends apb_base_seq;
    `uvm_object_utils(apb_rand_seq)

    int unsigned num_trans = 300;
    bit          app;

    function new(string name = "apb_rand_seq");
        super.new(name);
    endfunction

    function bit [31:0] pick_addr();
        bit [31:0] base;
        bit [11:0] off;
        if (app) begin
            base = MBOXA;
            randcase
                9: off = 12'h4 * $urandom_range(3, 0);
                1: off = 12'h4 * $urandom_range(1023, 4);
            endcase
            return base + off;
        end
        randcase
            3: base = GPIO;
            3: base = TMR;
            3: base = MBOXS;
            4: base = RAM;
            1: base = NONE + 32'h1000 * $urandom_range(11, 0);
        endcase
        randcase
            9: off = (base == RAM) ? 12'h4 * $urandom_range(255, 0) : 12'h4 * $urandom_range(3, 0);
            1: off = 12'h4 * $urandom_range(1023, 0);
        endcase
        return base + off;
    endfunction

    task body();
        apb_item t;
        repeat (num_trans) begin
            t = apb_item::type_id::create("t");
            start_item(t);
            if (!t.randomize())
                `uvm_fatal("APB_SEQ", "randomize failed")
            t.addr = pick_addr();
            randcase
                3: t.strb = 4'hF;
                1: t.strb = $urandom_range(14, 0);
            endcase
            finish_item(t);
        end
    endtask
endclass


// Directed checks of what the scoreboard cannot see: pins and the GPIO input path (P-17)
class apb_periph_seq extends apb_base_seq;
    `uvm_object_utils(apb_periph_seq)

    virtual apb_sb_if sb;

    function new(string name = "apb_periph_seq");
        super.new(name);
    endfunction

    task wait_cycles(int n);
        repeat (n) @(posedge sb.clk);
    endtask

    task body();
        bit [31:0] d;
        bit [31:0] lo;
        if (!uvm_config_db#(virtual apb_sb_if)::get(null, get_full_name(), "sb_vif", sb))
            `uvm_fatal("APB_SEQ", "sb_vif not found")

        // GPIO: outputs, then inputs through the synchronizer and the rising-edge flags
        wr(1'b0, GPIO + 'h0, 32'hA5);
        wait_cycles(1);
        check(sb.gpio_o == 8'hA5, $sformatf("gpio_o = %02h after DATA_OUT = A5", sb.gpio_o));
        wr(1'b0, GPIO + 'h0, 32'h3C, 4'h0);
        wait_cycles(1);
        check(sb.gpio_o == 8'hA5, "DATA_OUT written with PSTRB = 0");
        wr(1'b0, GPIO + 'h8, 32'h0F);
        @(negedge sb.clk) sb.gpio_i = 8'h81;
        wait_cycles(4);
        rd(1'b0, GPIO + 'h4, d);
        check(d == 32'h81, $sformatf("DATA_IN = %08h, expected 81", d));
        rd(1'b0, GPIO + 'hC, d);
        check(d == 32'h81, $sformatf("IRQ_STAT = %08h after rising edges on pins 0 and 7", d));
        check(sb.gpio_irq === 1'b1, "GPIO irq low with pin 0 flagged and enabled");
        wr(1'b0, GPIO + 'hC, 32'h01);
        wait_cycles(1);
        check(sb.gpio_irq === 1'b0, "GPIO irq still high with only pin 7 (disabled) flagged");
        rd(1'b0, GPIO + 'hC, d);
        check(d == 32'h80, $sformatf("IRQ_STAT = %08h after clearing pin 0", d));
        @(negedge sb.clk) sb.gpio_i = 8'h00;
        wr(1'b0, GPIO + 'hC, 32'hFF);
        wait_cycles(4);
        rd(1'b0, GPIO + 'hC, d);
        check(d == 32'h0, $sformatf("IRQ_STAT = %08h after a falling edge and a clear", d));

        // TIMER: irq once mtime reaches mtimecmp, gone when mtimecmp moves away. Start from a known
        // state, the random part before may have written any value into MTIME and MTIMECMP
        wr(1'b0, TMR + 'hC, 32'hFFFF_FFFF);
        wr(1'b0, TMR + 'h4, 32'h0);
        wr(1'b0, TMR + 'h0, 32'h0);
        wait_cycles(2);
        check(sb.timer_irq === 1'b0, "TIMER irq high with MTIMECMP_HI = all ones");
        rd(1'b0, TMR + 'h0, lo);
        wr(1'b0, TMR + 'h8, lo + 60);
        wr(1'b0, TMR + 'hC, 32'h0);
        check(sb.timer_irq === 1'b0, "TIMER irq high before mtime reached MTIMECMP");
        wait_cycles(80);
        check(sb.timer_irq === 1'b1, "TIMER irq low after mtime passed MTIMECMP");
        wr(1'b0, TMR + 'hC, 32'hFFFF_FFFF);
        wait_cycles(2);
        check(sb.timer_irq === 1'b0, "TIMER irq still high after MTIMECMP_HI = all ones");

        // Mailbox both ways with the interrupt lines. First empty both slots (reading IN pops the word)
        rd(1'b0, MBOXS + 'h4, d);
        rd(1'b1, MBOXA + 'h4, d);
        wr(1'b0, MBOXS + 'hC, 32'h1);
        wr(1'b1, MBOXA + 'hC, 32'h1);
        wr(1'b0, MBOXS + 'h0, 32'h1234_5678);
        wait_cycles(1);
        check(sb.mbox_irq_a === 1'b1, "App side irq low with a word waiting");
        wr(1'b0, MBOXS + 'h0, 32'h9999_9999);
        rd(1'b1, MBOXA + 'h4, d);
        check(d == 32'h1234_5678, $sformatf("App got %08h, expected 12345678 (second send must be ignored)", d));
        wait_cycles(1);
        check(sb.mbox_irq_a === 1'b0, "App side irq still high after reading IN");
        wr(1'b1, MBOXA + 'h0, 32'hBEEF_0001);
        wait_cycles(1);
        check(sb.mbox_irq_s === 1'b1, "Secure side irq low with a word waiting");
        rd(1'b0, MBOXS + 'h4, d);
        check(d == 32'hBEEF_0001, $sformatf("Secure got %08h, expected beef0001", d));
        wait_cycles(1);
        check(sb.mbox_irq_s === 1'b0, "Secure side irq still high after reading IN");

        // Both sides at once for a while: the scoreboard checks the same-edge cases
        `uvm_info("APB_SEQ", $sformatf("directed checks done, %0d errors", n_errors), UVM_LOW)
    endtask
endclass
