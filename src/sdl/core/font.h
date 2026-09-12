#ifndef FORCE_FONT_H
#define FORCE_FONT_H

#include <stdint.h>

/* 8 bytes, one per row. Bit 0 is the leftmost pixel. */
const uint8_t *force_glyph(unsigned char ch);

#endif
