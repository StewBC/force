#include "core/screen.h"

#include "core/font.h"

#include <stddef.h>

/* VIC-II-ish palette (common tutorial / "pepto simplified" RGB). */
static const uint32_t palette[FORCE_COLOR_COUNT] = {
    0x000000u, /* black */
    0xFFFFFFu, /* white */
    0x880000u, /* red */
    0xAAFFEEu, /* cyan */
    0xCC44CCu, /* purple */
    0x00CC55u, /* green */
    0x0000AAu, /* blue */
    0xEEEE77u, /* yellow */
    0xDD8855u, /* orange */
    0x664400u, /* brown */
    0xFF7777u, /* light red */
    0x333333u, /* dark grey */
    0x777777u, /* grey */
    0xAAFF66u, /* light green */
    0x0088FFu, /* light blue */
    0xBBBBBBu  /* light grey */
};

static uint8_t clamp_color(uint8_t c)
{
    return (c < FORCE_COLOR_COUNT) ? c : FORCE_WHITE;
}

void force_screen_clear(force_screen *s, uint8_t ch, uint8_t fg, uint8_t bg)
{
    force_screen_fill(s, 0, 0, FORCE_COLS, FORCE_ROWS, ch, fg, bg);
}

void force_screen_putc(force_screen *s, int x, int y, uint8_t ch, uint8_t fg, uint8_t bg)
{
    if (x < 0 || y < 0 || x >= FORCE_COLS || y >= FORCE_ROWS) {
        return;
    }
    s->cells[y][x].ch = ch;
    s->cells[y][x].fg = clamp_color(fg);
    s->cells[y][x].bg = clamp_color(bg);
}

void force_screen_puts(force_screen *s, int x, int y, const char *str, uint8_t fg, uint8_t bg)
{
    if (y < 0 || y >= FORCE_ROWS || str == NULL) {
        return;
    }
    for (; *str != '\0' && x < FORCE_COLS; ++str, ++x) {
        if (x >= 0) {
            force_screen_putc(s, x, y, (uint8_t)*str, fg, bg);
        }
    }
}

void force_screen_fill(force_screen *s, int x, int y, int w, int h,
                       uint8_t ch, uint8_t fg, uint8_t bg)
{
    int x1 = x + w;
    int y1 = y + h;
    int yy, xx;

    if (x < 0) {
        x = 0;
    }
    if (y < 0) {
        y = 0;
    }
    if (x1 > FORCE_COLS) {
        x1 = FORCE_COLS;
    }
    if (y1 > FORCE_ROWS) {
        y1 = FORCE_ROWS;
    }
    fg = clamp_color(fg);
    bg = clamp_color(bg);
    for (yy = y; yy < y1; ++yy) {
        for (xx = x; xx < x1; ++xx) {
            s->cells[yy][xx].ch = ch;
            s->cells[yy][xx].fg = fg;
            s->cells[yy][xx].bg = bg;
        }
    }
}

void force_screen_rasterize(const force_screen *s, uint32_t *pixels)
{
    int cy, cx, row, col;
    const uint32_t opaque = 0xFF000000u;

    for (cy = 0; cy < FORCE_ROWS; ++cy) {
        for (cx = 0; cx < FORCE_COLS; ++cx) {
            const force_cell *cell = &s->cells[cy][cx];
            const uint8_t *glyph = force_glyph(cell->ch);
            const uint32_t fg = opaque | palette[clamp_color(cell->fg)];
            const uint32_t bg = opaque | palette[clamp_color(cell->bg)];
            const int px = cx * FORCE_CELL_PX;
            const int py = cy * FORCE_CELL_PX;

            for (row = 0; row < FORCE_CELL_PX; ++row) {
                const uint8_t bits = glyph[row];
                uint32_t *dst = pixels + (py + row) * FORCE_FB_W + px;
                for (col = 0; col < FORCE_CELL_PX; ++col) {
                    dst[col] = ((bits >> col) & 1u) ? fg : bg;
                }
            }
        }
    }
}
