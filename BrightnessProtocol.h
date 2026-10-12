#pragma once
#include <stdint.h>
#include <stddef.h>
#include <math.h>
// DDC/CI Get VCP 0x10 reply: validate source, length, opcode, result,
// feature, checksum and range before presenting any value as brightness.
static inline int RetinaDecodeBrightness(const uint8_t *p, size_t n, uint16_t *current, uint16_t *maximum) {
    if (n < 11 || p[0] != 0x6e || p[1] != 0x88 || p[2] != 0x02 || p[3] != 0 || p[4] != 0x10) return 0;
    uint8_t checksum = 0x50;
    for (size_t i = 0; i < 11; i++) checksum ^= p[i];
    if (checksum) return 0;
    uint16_t max = (uint16_t)p[6] << 8 | p[7], cur = (uint16_t)p[8] << 8 | p[9];
    if (!max || cur > max) return 0;
    *current = cur; *maximum = max;
    return 1;
}
static inline uint16_t RetinaBrightnessValue(double percent, uint16_t maximum) {
    if (!isfinite(percent)) return 0;
    return (uint16_t)lround(fmax(0, fmin(100, percent)) * maximum / 100.0);
}
