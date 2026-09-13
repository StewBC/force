#include "game/game.h"

#include "core/screen.h"

#include <stdio.h>

#if FORCE_TILE_PX != FORCE_CELL_PX
#error "generated tiles must be FORCE_CELL_PX square"
#endif

static int field_w(const force_game *g)
{
    int w = (int)g->mission->w;
    if (w > FORCE_COLS) {
        w = FORCE_COLS;
    }
    return w;
}

static int field_h(const force_game *g)
{
    int h = (int)g->mission->h;
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
    const force_map *map = g->mission->map;
    const int origin_x = (int)g->mission->x;
    const int origin_y = (int)g->mission->y;
    const int w = field_w(g);
    const int h = field_h(g);
    int x, y;

    for (y = 0; y < h; ++y) {
        for (x = 0; x < w; ++x) {
            const int mx = origin_x + x;
            const int my = origin_y + y;
            const int idx = my * (int)map->width + mx;
            uint8_t color_id = map->color[idx];
            uint32_t fill = 0xFF000000u;

            if (color_id < FORCE_TILESET_COUNT) {
                uint32_t sample = force_tileset[color_id][0][0];
                if ((sample >> 24) != 0u) {
                    fill = opaque(sample);
                }
            }
            fill_cell(g->pixels, x, y, fill);
            if (map->actors[idx] != 0u) {
                stamp_tile(g->pixels, x, y, map->actors[idx]);
            }
            stamp_tile(g->pixels, x, y, map->tiles[idx]);
        }
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
    /* A-H roster. All empty (light grey) until a section table exists. */
    for (int i = 0; i < 8; i++) {
        force_screen_putc(s, 1 + i * 2, 23, (uint8_t)('A' + i),
                          FORCE_LIGHT_GREY, FORCE_BLACK);
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
