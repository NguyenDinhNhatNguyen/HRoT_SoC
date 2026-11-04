`timescale 1ns / 1ps

// Boot_Verifier: hardware gate between "the App image was hashed" and "the App Core may run".
// The expected digest is fetched by this block straight from the Boot ROM, so a firmware that
// skips or fakes the compare cannot produce a VERIFIED flag. SYSCSR releases the App Core
// only while VERIFIED is high.
//
// APB slave, zero wait states, full 32-bit writes only. Registers (offset):
//   0x00 CTRL     WO  bit0 CHECK (accepted once per reset)
//                     bit1 KEY_LOCK (sticky until POR)
//                     bit2 MODE (taken with CHECK: 0 = compare with the golden hash, 1 = with the HMAC tag)
//   0x04 STATUS   RO  bit0 VERIFIED, bit1 FAIL, bit2 KEY_LOCKED, bit3 CHECKED, bit4 BUSY
//   0x08 MIN_VER  RW  anti-rollback floor, a write only raises it (OTP model, cleared by POR)
//   0x0C APP_VER  RW  version from the App image header, written by firmware before CHECK
//   0x40-0x5C KEY0..7 RO  HMAC key, reads 0 after KEY_LOCK
//   other offsets: read 0, writes ignored
//
// CHECK fails when SHA-256 does not hold a finished digest, when APP_VER < MIN_VER, or when any of
// the 8 digest words differs from the Boot ROM slot. A passing CHECK raises MIN_VER to APP_VER.
module Boot_Verifier #(
    parameter [255:0] KEY         = 256'h0123456789ABCDEFFEDCBA98765432100F1E2D3C4B5A69788796A5B4C3D2E1F0,
    parameter [11:0]  GOLDEN_ADDR = 12'hFE0,     // 8 words in the Boot ROM, byte address
    parameter [11:0]  TAG_ADDR    = 12'hFC0      // 8 words in the Boot ROM, byte address
)(
    input             clk,
    input             por_rst,         // power-on reset: clears KEY_LOCK and MIN_VER
    input             sys_rst,         // system reset: clears the verdict

    // SHA-256 digest (SHA256_Wrapper)
    input  [255:0]    sha_digest,
    input             sha_done,
    input             sha_busy,

    // Boot ROM read port (negedge registered, the data follows the address within the cycle)
    output reg [11:0] rom_addr,
    input      [31:0] rom_data,

    output            verified,

    // APB4 slave
    input      [11:0] PADDR,
    input             PSEL,
    input             PENABLE,
    input             PWRITE,
    input      [31:0] PWDATA,
    input      [3:0]  PSTRB,
    output reg [31:0] PRDATA,
    output            PREADY,
    output            PSLVERR
);
    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    wire wr = PSEL && PENABLE && PWRITE && (PSTRB == 4'hF);
    wire rd = PSEL && !PWRITE;

    localparam S_IDLE = 1'b0, S_FETCH = 1'b1;

    reg        st;
    reg [2:0]  cnt;
    reg        checked, ok_q, fail_q;
    reg        mismatch;
    reg        key_lock;
    reg [31:0] min_ver, app_ver;

    wire        check_req = wr && PADDR == 12'h000 && PWDATA[0] && !checked;
    wire [31:0] want      = sha_digest[255 - 32*cnt -: 32];
    wire        ver_ok    = (app_ver >= min_ver);
    wire        digest_ok = sha_done && !sha_busy;

    assign verified = ok_q;

    // ---- Verdict, cleared by any system reset ----
    always @(posedge clk) begin
        if (sys_rst) begin
            st       <= S_IDLE;
            cnt      <= 3'd0;
            checked  <= 1'b0;
            ok_q     <= 1'b0;
            fail_q   <= 1'b0;
            mismatch <= 1'b0;
            rom_addr <= GOLDEN_ADDR;
        end else if (st == S_IDLE) begin
            if (check_req) begin
                checked <= 1'b1;
                if (digest_ok && ver_ok) begin
                    st       <= S_FETCH;
                    cnt      <= 3'd0;
                    mismatch <= 1'b0;
                    rom_addr <= PWDATA[2] ? TAG_ADDR : GOLDEN_ADDR;
                end else begin
                    fail_q <= 1'b1;
                end
            end
        end else begin
            // The word for the address of the previous cycle is valid now
            if (rom_data != want)
                mismatch <= 1'b1;
            if (cnt == 3'd7) begin
                st <= S_IDLE;
                if (mismatch || rom_data != want)
                    fail_q <= 1'b1;
                else
                    ok_q <= 1'b1;
            end else begin
                cnt      <= cnt + 3'd1;
                rom_addr <= rom_addr + 12'd4;
            end
        end
    end

    // ---- Key lock and anti-rollback floor, cleared only by POR ----
    wire min_up = (st == S_FETCH) && (cnt == 3'd7) && !mismatch && (rom_data == want);
    wire min_wr = wr && PADDR == 12'h008 && (PWDATA > min_ver);
    always @(posedge clk) begin
        if (por_rst) begin
            key_lock <= 1'b0;
            min_ver  <= 32'd0;
        end else begin
            if (wr && PADDR == 12'h000 && PWDATA[1])
                key_lock <= 1'b1;
            if (min_up)
                min_ver <= app_ver;
            else if (min_wr)
                min_ver <= PWDATA;
        end
    end

    always @(posedge clk) begin
        if (sys_rst)
            app_ver <= 32'd0;
        else if (wr && PADDR == 12'h00C && st == S_IDLE && !checked)
            app_ver <= PWDATA;
    end

    // ---- Read side ----
    wire [2:0] key_idx = PADDR[4:2];
    always @(*) begin
        PRDATA = 32'b0;
        if (rd) begin
            case (PADDR)
                12'h004: PRDATA = {27'b0, st == S_FETCH, checked, key_lock, fail_q, ok_q};
                12'h008: PRDATA = min_ver;
                12'h00C: PRDATA = app_ver;
                default: begin
                    if (PADDR >= 12'h040 && PADDR <= 12'h05C && !key_lock)
                        PRDATA = KEY[255 - 32*key_idx -: 32];
                end
            endcase
        end
    end
endmodule
