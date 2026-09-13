#include "game/game.h"

#include "core/screen.h"

#include <stdio.h>

#if FORCE_TILE_PX != FORCE_CELL_PX
#error "generated tiles must be FORCE_CELL_PX square"
#endif

static int field_w(const force_game *g)
{
    int w = (int)g->world->win_w;
    if (w > FORCE_COLS) {
        w = FORCE_COLS;
    }
    return w;
}

static int field_h(const force_game *g)
{
    int h = (int)g->world->win_h;
    if (h > FORCE_FIELD_ROWS) {
        h = FORCE_FIELD_ROWS;
    }
    return h;
}

static uint32_t opaque(uint32_t p)
{
    return 0xFF000000u | (p & 0x00FFFFFFu);
}

static void fill_cell(uint32_t *pixels, int cx, int cy, uint32_t color)
{
    int ox = cx * FORCE_CELL_PX;
    int oy = cy * FORCE_CELL_PX;
    int py, px;

    for (py = 0; py < FORCE_CELL_PX; ++py) {
        uint32_t *dst = pixels + (oy + py) * FORCE_FB_W + ox;
        for (px = 0; px < FORCE_CELL_PX; ++px) {
            dst[px] = color;
        }
    }
}

static void stamp_tile(uint32_t *pixels, int cx, int cy, uint8_t tid)
{
    int ox, oy, py, px;

    if (tid >= FORCE_TILESET_COUNT) {
        return;
    }
    ox = cx * FORCE_CELL_PX;
    oy = cy * FORCE_CELL_PX;
    for (py = 0; py < FORCE_CELL_PX; ++py) {
        uint32_t *dst = pixels + (oy + py) * FORCE_FB_W + ox;
        for (px = 0; px < FORCE_CELL_PX; ++px) {
            uint32_t p = force_tileset[tid][py][px];
            if ((p >> 24) != 0u) {
                dst[px] = opaque(p);
            }
        }
    }
}

static void blit_playfield(force_game *g)
{
    const force_world *w = g->world;
    const int origin_x = (int)w->win_x;
    const int origin_y = (int)w->win_y;
    const int fw = field_w(g);
    const int fh = field_h(g);
    int x, y, i;

    for (y = 0; y < fh; ++y) {
        for (x = 0; x < fw; ++x) {
            const int mx = origin_x + x;
            const int my = origin_y + y;
            const int idx = (int)w->row_off[my] + mx;
            uint8_t color_id = w->color[idx];
            uint32_t fill = 0xFF000000u;

            if (color_id < FORCE_TILESET_COUNT) {
                uint32_t sample = force_tileset[color_id][0][0];
                if ((sample >> 24) != 0u) {
                    fill = opaque(sample);
                }
            }
            fill_cell(g->pixels, x, y, fill);
            stamp_tile(g->pixels, x, y, w->tiles[idx]);
        }
    }

    for (i = 0; i < (int)FORCE_UNIT_MAX; ++i) {
        int sx, sy;
        if (w->unit_count[i] == 0u) {
            continue;
        }
        sx = (int)w->unit_x[i];
        sy = (int)w->unit_y[i];
        if (sx < origin_x || sy < origin_y ||
            sx >= origin_x + fw || sy >= origin_y + fh) {
            continue;
        }
        stamp_tile(g->pixels, sx - origin_x, sy - origin_y, w->unit_glyph[i]);
        stamp_tile(g->pixels, sx - origin_x, sy - origin_y,
                   w->tiles[(int)w->row_off[sy] + sx]);
    }
}

static void blit_cursor(force_game *g)
{
    const bool blink = ((g->frames / 30u) & 1u) != 0u;
    const uint32_t yellow = 0xFFEEEE77u;
    int ox = g->cursor_x * FORCE_CELL_PX;
    int oy = g->cursor_y * FORCE_CELL_PX;
    int py, px;

    for (py = 0; py < FORCE_CELL_PX; ++py) {
        uint32_t *dst = g->pixels + (oy + py) * FORCE_FB_W + ox;
        for (px = 0; px < FORCE_CELL_PX; ++px) {
            const bool edge = (px == 0 || py == 0 ||
                               px == FORCE_CELL_PX - 1 ||
                               py == FORCE_CELL_PX - 1);
            if (blink || edge) {
                dst[px] = yellow;
            }
        }
    }
}

void force_game_init(force_game *g)
{
    g->mission = &force_missions[0];
    g->world = &force_world_bss;
    force_world_load(g->world, g->mission);
    g->cursor_x = field_w(g) / 2;
    g->cursor_y = field_h(g) / 2;
    g->frames = 0;
    g->joy_present = false;
}

void force_game_tick(force_game *g, const force_input *in)
{
    const int w = field_w(g);
    const int h = field_h(g);

    g->cursor_x += in->cursor_dx;
    g->cursor_y += in->cursor_dy;
    if (g->cursor_x < 0) {
        g->cursor_x = 0;
    }
    if (g->cursor_x >= w) {
        g->cursor_x = w - 1;
    }
    if (g->cursor_y < 0) {
        g->cursor_y = 0;
    }
    if (g->cursor_y >= h) {
        g->cursor_y = h - 1;
    }
    g->joy_present = in->joy_present;
    g->frames += 1;
}

void force_game_draw(force_game *g)
{
    force_screen *s = &g->screen;
    char line[FORCE_COLS + 1];

    force_screen_clear(s, ' ', FORCE_WHITE, FORCE_BLACK);

    /* Command strip: rows 20-23 — the portable 4-line UI. */
    force_screen_fill(s, 0, FORCE_FIELD_ROWS, FORCE_COLS, 4,
                      ' ', FORCE_WHITE, FORCE_BLACK);
    force_screen_puts(s, 1, 20, "VERB   WHO   WHERE   FORCE", FORCE_YELLOW, FORCE_BLACK);
    force_screen_puts(s, 1, 21, "READY", FORCE_LIGHT_GREEN, FORCE_BLACK);
    (void)snprintf(line, sizeof(line), "CURSOR %02d,%02d", g->cursor_x, g->cursor_y);
    force_screen_puts(s, 1, 22, line, FORCE_WHITE, FORCE_BLACK);
    {
        const force_world *w = g->world;
        const int mx = (int)w->win_x + g->cursor_x;
        const int my = (int)w->win_y + g->cursor_y;
        uint8_t implied = FORCE_UNIT_NONE;
        uint8_t i;

        for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
            if (w->unit_count[i] == 0u) {
                continue;
            }
            if ((int)w->unit_x[i] != mx || (int)w->unit_y[i] != my) {
                continue;
            }
            if (w->unit_section[i] >= FORCE_LETTER_MAX) {
                continue;
            }
            implied = w->unit_section[i];
            break;   /* first slot wins */
        }
        for (i = 0u; i < FORCE_LETTER_MAX; ++i) {
            uint8_t fg = FORCE_LIGHT_GREY;
            if (w->section_strength[i] > 0u) {
                fg = FORCE_WHITE;
            }
            if (implied == i) {
                fg = FORCE_YELLOW;
            }
            force_screen_putc(s, 1 + (int)i * 2, 23,
                              (uint8_t)('A' + i), fg, FORCE_BLACK);
        }
    }

    /* Row 24: C64 / SDL extra. Atari and Apple II will not have this. */
    force_screen_fill(s, 0, FORCE_PLAY_ROWS, FORCE_COLS, 1,
                      ' ', FORCE_WHITE, FORCE_DARK_GREY);
    (void)snprintf(line, sizeof(line), "SDL  %s  JOY %s",
                   g->mission->name,
                   g->joy_present ? "YES" : "NO");
    force_screen_puts(s, 1, 24, line, FORCE_CYAN, FORCE_DARK_GREY);

    force_screen_rasterize(s, g->pixels);
    blit_playfield(g);
    blit_cursor(g);
}
