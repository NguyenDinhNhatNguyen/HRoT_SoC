`timescale 1ns/1ps

// Self-checking testbench for the APB peripherals: SYSCSR (incl. BUS_ERR), GPIO, UART (TX looped back to RX),
// TIMER and WDT. Ends with "APB_Periph_tb RESULT: PASS|FAIL", which sim/regress.sh looks for.
module APB_Periph_tb;
    reg clk = 0, por = 1;
    always #5 clk = ~clk;

    reg  [11:0] PADDR;
    reg         PENABLE = 0, PWRITE = 0;
    reg  [31:0] PWDATA;
    reg  [3:0]  PSTRB;
    reg  [2:0]  sel = 0;                  // 1 = SYSCSR, 2 = GPIO, 3 = UART, 4 = TIMER, 5 = WDT
    wire [31:0] rd_sys, rd_gpio, rd_uart, rd_tim, rd_wdt;
    wire        sys_rst, app_rst, uart_tx, gpio_irq, uart_irq, timer_irq, wdt_rst;
    wire [7:0]  gpio_o;
    reg  [7:0]  gpio_i = 0;
    reg         rx_force = 0, rx_val = 1;
    wire        uart_rx = rx_force ? rx_val : uart_tx;   // loopback, or the tb drives RX itself
    reg         be_pulse = 0, be_write = 0;               // fake Master bus error into SYSCSR
    reg  [1:0]  be_resp = 0;
    reg  [31:0] be_addr = 0;

    SYSCSR #(.RST_HOLD(3)) u_sys (
        .clk(clk), .por_rst(por), .wdt_rst_req(wdt_rst), .sys_rst(sys_rst), .app_rst(app_rst), .boot_strap(4'hA),
        .bus_err(be_pulse), .bus_err_write(be_write), .bus_err_resp(be_resp), .bus_err_addr(be_addr),
        .PADDR(PADDR), .PSEL(sel == 1), .PENABLE(PENABLE), .PWRITE(PWRITE), .PWDATA(PWDATA), .PSTRB(PSTRB),
        .PRDATA(rd_sys), .PREADY(), .PSLVERR());
    GPIO u_gpio (
        .clk(clk), .reset(sys_rst), .gpio_o(gpio_o), .gpio_i(gpio_i), .irq(gpio_irq),
        .PADDR(PADDR), .PSEL(sel == 2), .PENABLE(PENABLE), .PWRITE(PWRITE), .PWDATA(PWDATA), .PSTRB(PSTRB),
        .PRDATA(rd_gpio), .PREADY(), .PSLVERR());
    UART u_uart (
        .clk(clk), .reset(sys_rst), .uart_tx(uart_tx), .uart_rx(uart_rx), .irq(uart_irq),
        .PADDR(PADDR), .PSEL(sel == 3), .PENABLE(PENABLE), .PWRITE(PWRITE), .PWDATA(PWDATA), .PSTRB(PSTRB),
        .PRDATA(rd_uart), .PREADY(), .PSLVERR());
    TIMER u_tim (
        .clk(clk), .reset(sys_rst), .irq(timer_irq),
        .PADDR(PADDR), .PSEL(sel == 4), .PENABLE(PENABLE), .PWRITE(PWRITE), .PWDATA(PWDATA), .PSTRB(PSTRB),
        .PRDATA(rd_tim), .PREADY(), .PSLVERR());
    WDT #(.LOAD_RST(32'd1000)) u_wdt (
        .clk(clk), .reset(sys_rst), .rst_req(wdt_rst),
        .PADDR(PADDR), .PSEL(sel == 5), .PENABLE(PENABLE), .PWRITE(PWRITE), .PWDATA(PWDATA), .PSTRB(PSTRB),
        .PRDATA(rd_wdt), .PREADY(), .PSLVERR());

    integer fail = 0, pass = 0;
    reg [31:0] r;

    task apb_wr(input [2:0] s, input [11:0] a, input [31:0] d);
        begin
            @(posedge clk);
            sel     <= s;
            PADDR   <= a;
            PWDATA  <= d;
            PSTRB   <= 4'hF;
            PWRITE  <= 1;
            PENABLE <= 0;
            @(posedge clk);
            PENABLE <= 1;
            @(posedge clk);
            sel     <= 0;
            PENABLE <= 0;
            PWRITE  <= 0;
            #1;
        end
    endtask

    task apb_rd(input [2:0] s, input [11:0] a, output [31:0] d);
        begin
            @(posedge clk);
            sel     <= s;
            PADDR   <= a;
            PWRITE  <= 0;
            PENABLE <= 0;
            PSTRB   <= 0;
            @(posedge clk);
            PENABLE <= 1;
            #1 d = (s == 1) ? rd_sys : (s == 2) ? rd_gpio : (s == 3) ? rd_uart : (s == 4) ? rd_tim : rd_wdt;
            @(posedge clk);
            sel     <= 0;
            PENABLE <= 0;
        end
    endtask

    task bus_err_pulse(input w, input [1:0] resp, input [31:0] a);
        begin
            @(posedge clk);
            be_pulse <= 1;
            be_write <= w;
            be_resp  <= resp;
            be_addr  <= a;
            @(posedge clk);
            be_pulse <= 0;
            #1;
        end
    endtask

    task chk(input [31:0] got, input [31:0] exp, input [8*48-1:0] name);
        if (got !== exp) begin
            fail = fail + 1;
            $display("[FAIL] %0s: got %h, expected %h", name, got, exp);
        end else begin
            pass = pass + 1;
            $display("[PASS] %0s", name);
        end
    endtask

    integer i;
    reg [31:0] r2;

    initial begin
        repeat (3) @(posedge clk);
        por <= 0;
        wait (!sys_rst);
        @(posedge clk);

        // ---------------- SYSCSR ----------------
        apb_rd(1, 12'h004, r);
        chk(r, 32'h48524F54, "SYSCSR CHIP_ID");
        apb_rd(1, 12'h008, r);
        chk(r, 32'h00020000, "SYSCSR VERSION");
        apb_rd(1, 12'h00C, r);
        chk(r, 32'hA, "SYSCSR BOOT_STRAP latched at reset");
        apb_rd(1, 12'h010, r);
        chk(r, 32'h1, "SYSCSR RST_CAUSE = POR");
        chk(app_rst, 1, "App held in reset after POR");
        apb_wr(1, 12'h000, 32'h1);
        chk(app_rst, 0, "APP_CTRL=1 releases the App");
        apb_wr(1, 12'h014, 32'h12345678);
        chk(sys_rst, 0, "SW_RESET with a wrong key is ignored");
        apb_wr(1, 12'h014, 32'h5A5A0001);
        chk(sys_rst, 1, "SW_RESET with the right key resets");
        wait (!sys_rst);
        @(posedge clk);
        chk(app_rst, 1, "App held in reset again after SW reset");
        apb_rd(1, 12'h010, r);
        chk(r, 32'h5, "RST_CAUSE = POR|SW, survives SW reset");
        apb_wr(1, 12'h010, 32'h5);
        apb_rd(1, 12'h010, r);
        chk(r, 32'h0, "RST_CAUSE W1C");

        // ---------------- SYSCSR bus error capture ----------------
        apb_rd(1, 12'h018, r);
        chk(r, 32'h0, "BUS_ERR clear after reset");
        bus_err_pulse(1, 2'b10, 32'h60000004);
        apb_rd(1, 12'h018, r);
        chk(r, 32'hB, "BUS_ERR records a write SLVERR");
        apb_rd(1, 12'h01C, r);
        chk(r, 32'h60000004, "BUS_ERR_ADDR holds its address");
        bus_err_pulse(0, 2'b11, 32'h70000000);
        apb_rd(1, 12'h018, r);
        chk(r, 32'h1B, "BUS_ERR keeps the first, flags overflow");
        apb_rd(1, 12'h01C, r);
        chk(r, 32'h60000004, "BUS_ERR_ADDR keeps the first address");
        apb_wr(1, 12'h018, 32'h1);
        apb_rd(1, 12'h018, r);
        chk(r, 32'h0, "BUS_ERR W1C clears it");
        bus_err_pulse(0, 2'b11, 32'h70000000);
        apb_rd(1, 12'h018, r);
        chk(r, 32'hD, "BUS_ERR records a read DECERR");

        // ---------------- GPIO ----------------
        apb_wr(2, 12'h000, 32'hA5);
        chk(gpio_o, 8'hA5, "GPIO DATA_OUT drives the pins");
        gpio_i = 8'h3C;
        repeat (4) @(posedge clk);
        apb_rd(2, 12'h004, r);
        chk(r, 32'h3C, "GPIO DATA_IN through the synchronizer");
        apb_rd(2, 12'h00C, r);
        chk(r, 32'h3C, "GPIO IRQ_STAT catches rising edges");
        chk(gpio_irq, 0, "GPIO irq stays low with IRQ_EN = 0");
        apb_wr(2, 12'h008, 32'h04);
        chk(gpio_irq, 1, "GPIO irq fires once pin 2 is enabled");
        apb_wr(2, 12'h00C, 32'h04);
        chk(gpio_irq, 0, "GPIO W1C clears the interrupt");
        apb_rd(2, 12'h00C, r);
        chk(r, 32'h38, "GPIO W1C clears only the written bits");

        // ---------------- UART (loopback) ----------------
        apb_wr(3, 12'h00C, 32'h1);      // 2 clk / tick -> 32 clk / bit
        apb_rd(3, 12'h008, r);
        chk(r[1], 1, "UART TX_IDLE after reset");
        apb_rd(3, 12'h004, r);
        chk(r[31], 1, "UART RXDATA bit31 flags empty");
        apb_wr(3, 12'h010, 32'h1);      // interrupt on RX_VALID
        apb_wr(3, 12'h000, 32'h55);
        apb_wr(3, 12'h000, 32'hA3);
        apb_wr(3, 12'h000, 32'h0F);
        wait (u_uart.tx_idle);
        repeat (200) @(posedge clk);
        chk(uart_irq, 1, "UART irq RX_VALID");
        apb_rd(3, 12'h004, r);
        chk(r, 32'h55, "UART loopback byte 1");
        apb_rd(3, 12'h004, r);
        chk(r, 32'hA3, "UART loopback byte 2");
        apb_rd(3, 12'h004, r);
        chk(r, 32'h0F, "UART loopback byte 3");
        apb_rd(3, 12'h008, r);
        chk(r[2], 0, "UART RX drained");
        // overrun: 9 bytes into an 8-entry RX FIFO
        for (i = 0; i < 9; i = i + 1)
            apb_wr(3, 12'h000, i);
        wait (u_uart.tx_idle);
        repeat (200) @(posedge clk);
        apb_rd(3, 12'h008, r);
        chk(r[3], 1, "UART RX_OVERRUN when the FIFO is full");
        apb_wr(3, 12'h008, 32'h8);
        apb_rd(3, 12'h008, r);
        chk(r[3], 0, "UART W1C clears OVERRUN");
        for (i = 0; i < 8; i = i + 1)
            apb_rd(3, 12'h004, r);
        // frame error: the tb holds RX low through the stop bit
        rx_force = 1;
        rx_val = 0;
        repeat (32 * 12) @(posedge clk);
        rx_val = 1;
        repeat (64) @(posedge clk);
        apb_rd(3, 12'h008, r);
        chk(r[4], 1, "UART FRAME_ERR on a zero stop bit");

        // ---------------- TIMER ----------------
        apb_rd(4, 12'h00C, r);
        chk(r, 32'hFFFFFFFF, "TIMER MTIMECMP_HI resets to all ones");
        chk(timer_irq, 0, "TIMER no interrupt after reset");
        apb_rd(4, 12'h000, r);
        apb_rd(4, 12'h000, r2);
        chk(r2 > r, 1, "TIMER mtime is counting");
        apb_wr(4, 12'h000, 32'h0);              // mtime ~ 0 (HI is still 0 this soon after reset)
        apb_wr(4, 12'h00C, 32'h0);
        apb_wr(4, 12'h008, 32'd200);
        chk(timer_irq, 0, "TIMER quiet while mtime < mtimecmp");
        repeat (250) @(posedge clk);
        chk(timer_irq, 1, "TIMER fires once mtime >= mtimecmp");
        apb_wr(4, 12'h008, 32'hFFFFFFFF);
        repeat (2) @(posedge clk);
        #1;
        chk(timer_irq, 0, "TIMER raising mtimecmp clears the irq");

        // ---------------- WDT ----------------
        apb_rd(5, 12'h004, r);
        chk(r, 32'd1000, "WDT LOAD reset");
        apb_rd(5, 12'h000, r);
        chk(r, 32'h0, "WDT disabled after reset");
        apb_wr(5, 12'h004, 32'd200);
        apb_wr(5, 12'h000, 32'h1);
        apb_wr(5, 12'h004, 32'd5);
        apb_rd(5, 12'h004, r);
        chk(r, 32'd200, "WDT LOAD locked while enabled");
        apb_wr(5, 12'h000, 32'h0);
        apb_rd(5, 12'h000, r);
        chk(r, 32'h1, "WDT cannot be disabled by software");
        repeat (20) @(posedge clk);
        apb_wr(5, 12'h00C, 32'h5A5A0002);
        apb_rd(5, 12'h008, r);
        chk(r > 32'd190, 1, "WDT KICK with the key reloads COUNT");
        apb_wr(5, 12'h00C, 32'h12345678);
        apb_rd(5, 12'h008, r2);
        chk(r2 < r, 1, "WDT KICK with a wrong key is ignored");
        repeat (250) @(posedge clk);
        wait (!sys_rst);
        @(posedge clk);
        apb_rd(1, 12'h010, r);
        chk(r[1], 1, "WDT timeout resets, sets RST_CAUSE.WDT");
        apb_rd(5, 12'h000, r);
        chk(r, 32'h0, "WDT disabled again after its reset");

        $display("APB_Periph_tb RESULT: %s (%0d of %0d checks passed)", fail ? "FAIL" : "PASS", pass, pass + fail);
        $finish;
    end
endmodule
