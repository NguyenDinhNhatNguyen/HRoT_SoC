`timescale 1ns/1ps

// Testbench ngoai vi APB: SYSCSR, GPIO, UART (loopback TX -> RX)
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
    wire        uart_rx = rx_force ? rx_val : uart_tx;   // loopback, hoac tb tu lai chan RX

    SYSCSR #(.RST_HOLD(3)) u_sys (
        .clk(clk), .por_rst(por), .wdt_rst_req(wdt_rst), .sys_rst(sys_rst), .app_rst(app_rst), .boot_strap(4'hA),
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
        .PADDR(PADDR), .PSEL(sel == 5), .PENABLE(PENABLE), .PWRITE(PWRITE), .PWDATA(PWDATA), .PSTRB(PSTRB),        .PRDATA(rd_wdt), .PREADY(), .PSLVERR());

    integer fail = 0, pass = 0;
    reg [31:0] r;

    task apb_wr(input [2:0] s, input [11:0] a, input [31:0] d);
        begin
            @(posedge clk); sel <= s; PADDR <= a; PWDATA <= d; PSTRB <= 4'hF; PWRITE <= 1; PENABLE <= 0;
            @(posedge clk); PENABLE <= 1;
            @(posedge clk); sel <= 0; PENABLE <= 0; PWRITE <= 0; #1;
        end
    endtask
    task apb_rd(input [2:0] s, input [11:0] a, output [31:0] d);
        begin
            @(posedge clk); sel <= s; PADDR <= a; PWRITE <= 0; PENABLE <= 0; PSTRB <= 0;
            @(posedge clk); PENABLE <= 1;
            #1 d = (s == 1) ? rd_sys : (s == 2) ? rd_gpio : (s == 3) ? rd_uart : (s == 4) ? rd_tim : rd_wdt;
            @(posedge clk); sel <= 0; PENABLE <= 0;
        end
    endtask
    task chk(input [31:0] got, input [31:0] exp, input [255:0] name);
        if (got !== exp) begin 
            fail = fail + 1; 
            $display("[FAIL] %0s: got %h exp %h", name, got, exp); 
            end
        else begin 
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
        apb_rd(1, 12'h004, r); chk(r, 32'h48524F54, "SYSCSR CHIP_ID");
        apb_rd(1, 12'h008, r); chk(r, 32'h00020000, "SYSCSR VERSION");
        apb_rd(1, 12'h00C, r); chk(r, 32'hA, "SYSCSR BOOT_STRAP chot luc reset");
        apb_rd(1, 12'h010, r); chk(r, 32'h1, "SYSCSR RST_CAUSE = POR");
        chk(app_rst, 1, "App bi giu reset sau POR");
        apb_wr(1, 12'h000, 32'h1); chk(app_rst, 0, "APP_CTRL=1 nha reset App");
        apb_wr(1, 12'h014, 32'h12345678); chk(sys_rst, 0, "SW_RESET sai khoa -> khong reset");
        apb_wr(1, 12'h014, 32'h5A5A0001);
        chk(sys_rst, 1, "SW_RESET dung khoa -> sys_rst");
        wait (!sys_rst); @(posedge clk);
        chk(app_rst, 1, "Sau SW reset App bi giu reset lai");
        apb_rd(1, 12'h010, r); chk(r, 32'h5, "RST_CAUSE = POR|SW (song qua SW reset)");
        apb_wr(1, 12'h010, 32'h5);
        apb_rd(1, 12'h010, r); chk(r, 32'h0, "RST_CAUSE W1C");

        // ---------------- GPIO ----------------
        apb_wr(2, 12'h000, 32'hA5); chk(gpio_o, 8'hA5, "GPIO DATA_OUT -> chan");
        gpio_i = 8'h3C; repeat (4) @(posedge clk);
        apb_rd(2, 12'h004, r); chk(r, 32'h3C, "GPIO DATA_IN (dong bo 2 tang)");
        apb_rd(2, 12'h00C, r); chk(r, 32'h3C, "GPIO IRQ_STAT bat canh len");
        chk(gpio_irq, 0, "GPIO irq tat khi IRQ_EN = 0");
        apb_wr(2, 12'h008, 32'h04); chk(gpio_irq, 1, "GPIO irq bat khi IRQ_EN chan 2");
        apb_wr(2, 12'h00C, 32'h04); chk(gpio_irq, 0, "GPIO W1C xoa ngat");
        apb_rd(2, 12'h00C, r); chk(r, 32'h38, "GPIO W1C chi xoa bit duoc ghi");

        // ---------------- UART (loopback) ----------------
        apb_wr(3, 12'h00C, 32'h1);      // 2 clk / tick -> 32 clk / bit
        apb_rd(3, 12'h008, r); chk(r[1], 1, "UART TX_IDLE luc dau");
        apb_rd(3, 12'h004, r); chk(r[31], 1, "UART RXDATA bit31 = rong");
        apb_wr(3, 12'h010, 32'h1);      // ngat khi RX_VALID
        apb_wr(3, 12'h000, 32'h55); apb_wr(3, 12'h000, 32'hA3); apb_wr(3, 12'h000, 32'h0F);
        wait (u_uart.tx_idle); repeat (200) @(posedge clk);
        chk(uart_irq, 1, "UART irq RX_VALID");
        apb_rd(3, 12'h004, r); chk(r, 32'h55, "UART loopback byte 1");
        apb_rd(3, 12'h004, r); chk(r, 32'hA3, "UART loopback byte 2");
        apb_rd(3, 12'h004, r); chk(r, 32'h0F, "UART loopback byte 3");
        apb_rd(3, 12'h008, r); chk(r[2], 0, "UART RX het du lieu");
        // overrun: 9 byte vao FIFO RX 8 cho
        for (i = 0; i < 9; i = i + 1) apb_wr(3, 12'h000, i);
        wait (u_uart.tx_idle); repeat (200) @(posedge clk);
        apb_rd(3, 12'h008, r); chk(r[3], 1, "UART RX_OVERRUN khi FIFO day");
        apb_wr(3, 12'h008, 32'h8);
        apb_rd(3, 12'h008, r); chk(r[3], 0, "UART W1C xoa OVERRUN");
        for (i = 0; i < 8; i = i + 1) apb_rd(3, 12'h004, r);
        // frame error: tb giu RX = 0 qua ca bit stop
        rx_force = 1; rx_val = 0; repeat (32 * 12) @(posedge clk); rx_val = 1; repeat (64) @(posedge clk);
        apb_rd(3, 12'h008, r); chk(r[4], 1, "UART FRAME_ERR khi stop bit = 0");

        // ---------------- TIMER ----------------
        apb_rd(4, 12'h00C, r); chk(r, 32'hFFFFFFFF, "TIMER MTIMECMP_HI reset = toan 1");
        chk(timer_irq, 0, "TIMER khong ngat sau reset");
        apb_rd(4, 12'h000, r); apb_rd(4, 12'h000, r2); chk(r2 > r, 1, "TIMER mtime dang dem");
        apb_wr(4, 12'h000, 32'h0);              // mtime ~ 0 (HI van = 0 vi moi reset)
        apb_wr(4, 12'h00C, 32'h0);
        apb_wr(4, 12'h008, 32'd200);
        chk(timer_irq, 0, "TIMER chua ngat khi mtime < mtimecmp");
        repeat (250) @(posedge clk);
        chk(timer_irq, 1, "TIMER ngat khi mtime >= mtimecmp");
        apb_wr(4, 12'h008, 32'hFFFFFFFF); repeat (2) @(posedge clk); #1;
        chk(timer_irq, 0, "TIMER ghi mtimecmp lon -> het ngat");

        // ---------------- WDT ----------------
        apb_rd(5, 12'h004, r); chk(r, 32'd1000, "WDT LOAD reset");
        apb_rd(5, 12'h000, r); chk(r, 32'h0, "WDT tat sau reset");
        apb_wr(5, 12'h004, 32'd200);
        apb_wr(5, 12'h000, 32'h1);
        apb_wr(5, 12'h004, 32'd5);  apb_rd(5, 12'h004, r); chk(r, 32'd200, "WDT LOAD khoa khi EN = 1");
        apb_wr(5, 12'h000, 32'h0);  apb_rd(5, 12'h000, r); chk(r, 32'h1, "WDT phan mem khong tat duoc");        repeat (20) @(posedge clk);
        apb_wr(5, 12'h00C, 32'h5A5A0002); apb_rd(5, 12'h008, r);
        chk(r > 32'd190, 1, "WDT KICK dung khoa nap lai COUNT");
        apb_wr(5, 12'h00C, 32'h12345678); apb_rd(5, 12'h008, r2);
        chk(r2 < r, 1, "WDT KICK sai khoa bi bo qua");
        repeat (250) @(posedge clk);
        wait (!sys_rst); @(posedge clk);
        apb_rd(1, 12'h010, r); chk(r[1], 1, "WDT het gio -> reset, RST_CAUSE.WDT");
        apb_rd(5, 12'h000, r); chk(r, 32'h0, "WDT tat lai sau reset");

        $display("APB PERIPH RESULT: PASS = %0d, FAIL = %0d", pass, fail);
        $finish;
    end
endmodule
