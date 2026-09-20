#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
static inline bool validVCPReply(const uint8_t *b, size_t n, uint8_t code) {
    if(n < 11 || b[0] != 0x6e || b[1] != 0x88 || b[2] != 0x02 || b[3] != 0 || b[4] != code) return false;
    uint8_t checksum = 0x50;
    for(size_t i = 0; i < 11; i++) checksum ^= b[i];
    return checksum == 0;
}
