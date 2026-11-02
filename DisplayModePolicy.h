#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <math.h>

// A non-owned virtual display must not be counted as physical hardware.
static inline bool RDIsPhysicalDisplay(uint32_t vendor, uint32_t product) {
    return vendor != 0xB33F && product != 0x76697274;
}

static inline bool RDMatchesHiDPI(size_t width, size_t height, size_t pixelWidth,
                                  size_t pixelHeight, double rate,
                                  size_t requestedWidth, size_t requestedHeight,
                                  double requestedRate) {
    return width == requestedWidth && height == requestedHeight &&
        pixelWidth == requestedWidth * 2 && pixelHeight == requestedHeight * 2 &&
        isfinite(rate) && rate > 0 && fabs(rate - requestedRate) < 0.6;
}
