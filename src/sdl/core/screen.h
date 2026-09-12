#ifndef FORCE_SCREEN_H
#define FORCE_SCREEN_H

#include "core/types.h"

void force_screen_clear(force_screen *s, uint8_t ch, uint8_t fg, uint8_t bg);
void force_screen_putc(force_screen *s, int x, int y, uint8_t ch, uint8_t fg, uint8_t bg);
void force_screen_puts(force_screen *s, int x, int y, const char *str, uint8_t fg, uint8_t bg);
void force_screen_fill(force_screen *s, int x, int y, int w, int h,
                       uint8_t ch, uint8_t fg, uint8_t bg);

/* Rasterize 40x25 cells into a 320x200 XRGB8888 buffer. */
void force_screen_rasterize(const force_screen *s, uint32_t *pixels);

#endif
