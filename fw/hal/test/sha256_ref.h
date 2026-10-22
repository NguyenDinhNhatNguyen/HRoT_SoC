/* Mô hình tham chiếu SHA-256 bằng phần mềm (độc lập với HAL).
 * Dùng cho: (1) lõi của mô hình ngoại vi giả lập trong unit test host,
 *           (2) có thể bọc DPI-C làm golden model cho UVM scoreboard (Tuần 7). */
#ifndef SHA256_REF_H
#define SHA256_REF_H
#include <stdint.h>
#include <stddef.h>
void sha256_ref_compress(uint32_t h[8], const uint32_t w_in[16]);   /* 1 khối, big-endian words */
void sha256_ref(const uint8_t *msg, size_t len, uint8_t out[32]);   /* băm trọn vẹn */
extern const uint32_t SHA256_REF_IV[8];
#endif