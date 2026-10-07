#include "game/game.h"

#include "core/screen.h"
#include "game/command.h"

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

void force_game_cursor_span(const force_game *g,
                            uint8_t *x0, uint8_t *y0,
                            uint8_t *x1, uint8_t *y1)
{
    const force_world *w = g->world;
    int ax, ay, bx, by;

    ax = (int)w->win_x + g->cursor_x;
    ay = (int)w->win_y + g->cursor_y;
    bx = ax + 1;
    by = ay + 1;
    if (ax < 0) {
        ax = 0;
    }
    if (ay < 0) {
        ay = 0;
    }
    if (bx < ax + 1) {
        bx = ax + 1;
    }
    if (by < ay + 1) {
        by = ay + 1;
    }
    if (w->width > 0 && bx > (int)w->width) {
        bx = (int)w->width;
    }
    if (w->height > 0 && by > (int)w->height) {
        by = (int)w->height;
    }
    if (w->width > 0 && ax >= (int)w->width) {
        ax = (int)w->width - 1;
        bx = (int)w->width;
    }
    if (w->height > 0 && ay >= (int)w->height) {
        ay = (int)w->height - 1;
        by = (int)w->height;
    }
    *x0 = (uint8_t)ax;
    *y0 = (uint8_t)ay;
    *x1 = (uint8_t)bx;
    *y1 = (uint8_t)by;
}

void force_game_cursor_cell(const force_game *g, uint8_t *mx, uint8_t *my)
{
    uint8_t x0, y0, x1, y1;

    force_game_cursor_span(g, &x0, &y0, &x1, &y1);
    (void)x1;
    (void)y1;
    *mx = x0;
    *my = y0;
}

static void camera_save(force_game *g)
{
    g->cam_prev_ok = 1u;
    g->cam_prev_x = g->world->win_x;
    g->cam_prev_y = g->world->win_y;
    g->cam_prev_cx = (uint8_t)g->cursor_x;
    g->cam_prev_cy = (uint8_t)g->cursor_y;
}

static void camera_limits(const force_game *g,
                          int *min_x, int *min_y,
                          int *max_x, int *max_y)
{
    const force_world *w = g->world;
    int fw = field_w(g);
    int fh = field_h(g);
    int lo_x = (int)w->play_x;
    int lo_y = (int)w->play_y;
    int hi_x;
    int hi_y;

    if (fw < 1) {
        fw = 1;
    }
    if (fh < 1) {
        fh = 1;
    }
    hi_x = lo_x + (int)w->play_w - fw;
    hi_y = lo_y + (int)w->play_h - fh;
    if (hi_x < lo_x) {
        hi_x = lo_x;
    }
    if (hi_y < lo_y) {
        hi_y = lo_y;
    }
    *min_x = lo_x;
    *min_y = lo_y;
    *max_x = hi_x;
    *max_y = hi_y;
}

static void camera_clamp_win(force_game *g)
{
    force_world *w = g->world;
    int min_x;
    int min_y;
    int max_x;
    int max_y;

    camera_limits(g, &min_x, &min_y, &max_x, &max_y);
    if ((int)w->win_x < min_x) {
        w->win_x = (uint8_t)min_x;
    }
    if ((int)w->win_y < min_y) {
        w->win_y = (uint8_t)min_y;
    }
    if ((int)w->win_x > max_x) {
        w->win_x = (uint8_t)max_x;
    }
    if ((int)w->win_y > max_y) {
        w->win_y = (uint8_t)max_y;
    }
}

void force_game_camera_focus(force_game *g, uint8_t mx, uint8_t my)
{
    force_world *w = g->world;
    int fw = field_w(g);
    int fh = field_h(g);
    int nx;
    int ny;
    int cx;
    int cy;

    force_world_clamp_play(w, &mx, &my);
    camera_save(g);
    if (fw < 1) {
        fw = 1;
    }
    if (fh < 1) {
        fh = 1;
    }
    nx = (int)mx - fw / 2;
    ny = (int)my - fh / 2;
    if (nx < 0) {
        nx = 0;
    }
    if (ny < 0) {
        ny = 0;
    }
    w->win_x = (uint8_t)nx;
    w->win_y = (uint8_t)ny;
    camera_clamp_win(g);
    cx = (int)mx - (int)w->win_x;
    cy = (int)my - (int)w->win_y;
    if (cx < 0) {
        cx = 0;
    }
    if (cy < 0) {
        cy = 0;
    }
    if (cx >= fw) {
        cx = fw - 1;
    }
    if (cy >= fh) {
        cy = fh - 1;
    }
    g->cursor_x = cx;
    g->cursor_y = cy;
    g->cam_ttl = 0;
}

int force_game_camera_back(force_game *g)
{
    uint8_t ox, oy, ocx, ocy;

    if (g->cam_prev_ok == 0u) {
        return 0;
    }
    ox = g->world->win_x;
    oy = g->world->win_y;
    ocx = (uint8_t)g->cursor_x;
    ocy = (uint8_t)g->cursor_y;
    g->world->win_x = g->cam_prev_x;
    g->world->win_y = g->cam_prev_y;
    g->cursor_x = (int)g->cam_prev_cx;
    g->cursor_y = (int)g->cam_prev_cy;
    g->cam_prev_x = ox;
    g->cam_prev_y = oy;
    g->cam_prev_cx = ocx;
    g->cam_prev_cy = ocy;
    camera_clamp_win(g);
    g->cam_ttl = 0;
    return 1;
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

static uint32_t lerp_nade_fill(uint32_t d)
{
    const uint32_t tint = 0xFFCC3333u;
    uint8_t r = (uint8_t)(((uint8_t)(d >> 16) + (uint8_t)(tint >> 16)) >> 1);
    uint8_t g = (uint8_t)(((uint8_t)(d >> 8) + (uint8_t)(tint >> 8)) >> 1);
    uint8_t b = (uint8_t)(((uint8_t)d + (uint8_t)tint) >> 1);

    return 0xFF000000u |
           ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
}

static void lerp_hurt_glyph(uint32_t *pixels, int cx, int cy, uint8_t tid)
{
    const uint32_t tint = 0xFFCC3333u;
    const uint8_t tr = (uint8_t)(tint >> 16);
    const uint8_t tg = (uint8_t)(tint >> 8);
    const uint8_t tb = (uint8_t)tint;
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
            uint32_t d;
            uint8_t r, g, b;
            if ((p >> 24) == 0u) {
                continue;
            }
            d = dst[px];
            r = (uint8_t)(((uint8_t)(d >> 16) + tr) >> 1);
            g = (uint8_t)(((uint8_t)(d >> 8) + tg) >> 1);
            b = (uint8_t)(((uint8_t)d + tb) >> 1);
            dst[px] = 0xFF000000u |
                      ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
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
            uint8_t color_id;
            uint32_t fill = 0xFF000000u;
            int idx;

            if (mx < 0 || my < 0 ||
                mx >= (int)w->width || my >= (int)w->height) {
                fill_cell(g->pixels, x, y, 0xFF000000u);
                continue;
            }
            idx = (int)w->row_off[my] + mx;
            color_id = w->color[idx];
            if (color_id < FORCE_TILESET_COUNT) {
                uint32_t sample = force_tileset[color_id][0][0];
                if ((sample >> 24) != 0u) {
                    fill = opaque(sample);
                }
            }
            if (force_grenade_fx_at(w, (uint8_t)mx, (uint8_t)my)) {
                fill = lerp_nade_fill(fill);
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
        if ((w->unit_fx[i] & 0x0Fu) != 0u) {
            lerp_hurt_glyph(g->pixels, sx - origin_x, sy - origin_y,
                            w->unit_glyph[i]);
        }
        /* A roof covers the man. Anything else, including the opaque
           built deck (tile 81), stays under the glyph. */
        {
            uint8_t tid = w->tiles[(int)w->row_off[sy] + sx];

            if (tid < FORCE_TILESET_COUNT &&
                force_tile_class[tid] == FORCE_CLASS_ROOFS) {
                stamp_tile(g->pixels, sx - origin_x, sy - origin_y, tid);
            }
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

static uint8_t player_strength(const force_world *w)
{
    unsigned sum = 0u;
    uint8_t i;

    for (i = 0u; i < FORCE_LETTER_MAX; ++i) {
        sum += w->section_strength[i];
    }
    if (sum > 99u) {
        sum = 99u;
    }
    return (uint8_t)sum;
}

static void session_reset(force_game *g)
{
    force_world_load(g->world, g->mission);
    g->cursor_x = field_w(g) / 2;
    g->cursor_y = field_h(g) / 2;
    g->frames = 0;
    g->cmd_nopath = 0;
    g->cam_prev_ok = 0;
    g->cam_prev_x = 0;
    g->cam_prev_y = 0;
    g->cam_prev_cx = 0;
    g->cam_prev_cy = 0;
    g->cam_ttl = 0;
    g->cycle_kind = 0;
    g->cycle_room = FORCE_UNIT_NONE;
    g->score_snap = 0;
    g->snap_score = 0;
    force_command_init(g);
}

void force_game_init(force_game *g)
{
    g->world = &force_world_bss;
    g->joy_present = false;
    g->stick_latched = false;
    g->leave = 0;
    force_game_begin(g, &force_missions[0]);
}

void force_game_begin(force_game *g, const force_mission *mission)
{
    g->mission = mission;
    g->leave = 0;
    session_reset(g);
}

void force_game_tick(force_game *g, const force_input *in)
{
    const int w = field_w(g);
    const int h = field_h(g);

    g->joy_present = in->joy_present;
    g->stick_latched = in->stick_latched;
    g->leave = 0;

    if (in->restart) {
        session_reset(g);
    } else if (g->world->script_outcome != FORCE_SCRIPT_PLAYING &&
               in->cmd_kind == FORCE_CMD_RETURN) {
        /* Banner is up. RETURN leaves; it does not confirm an order. */
        g->leave = 1;
    } else {
        if (g->cmd_flash > 0u) {
            g->cmd_flash -= 1u;
            if (g->cmd_flash == 0u) {
                g->cmd_nopath = 0;
            }
        }

        g->cursor_x += in->cursor_dx;
        g->cursor_y += in->cursor_dy;
        {
            force_world *world = g->world;
            int min_x, min_y, max_x, max_y;

            camera_limits(g, &min_x, &min_y, &max_x, &max_y);
            if (g->cursor_x < 0) {
                if ((int)world->win_x > min_x) {
                    world->win_x--;
                }
                g->cursor_x = 0;
            } else if (g->cursor_x >= w) {
                if ((int)world->win_x < max_x) {
                    world->win_x++;
                }
                g->cursor_x = w - 1;
            }
            if (g->cursor_y < 0) {
                if ((int)world->win_y > min_y) {
                    world->win_y--;
                }
                g->cursor_y = 0;
            } else if (g->cursor_y >= h) {
                if ((int)world->win_y < max_y) {
                    world->win_y++;
                }
                g->cursor_y = h - 1;
            }
        }
        force_command_feed(g, in);
    }

    if ((g->frames % (int)FORCE_LOGIC_PERIOD) == 0) {
        force_world_tick(g->world);
        if (!in->restart &&
            g->world->script_outcome == FORCE_SCRIPT_WIN &&
            g->score_snap == 0u) {
            g->score_snap = 1u;
            g->snap_score = player_strength(g->world);
        }
        if (!in->restart &&
            g->world->script_outcome == FORCE_SCRIPT_PLAYING &&
            g->world->path_fail_who < FORCE_LETTER_MAX) {
            g->cmd_nopath = 1;
            g->cmd_flash = 8;
        }
        if (!in->restart && g->cam_ttl > 0u) {
            g->cam_ttl--;
            if (g->cam_ttl == 0u) {
                (void)force_game_camera_back(g);
            }
        }
    }
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
    force_command_paint(g);
    {
        uint8_t mx, my;
        force_game_cursor_cell(g, &mx, &my);
        (void)snprintf(line, sizeof(line), "CURSOR %02d,%02d",
                       (int)mx, (int)my);
    }
    force_screen_puts(s, 1, 22, line, FORCE_WHITE, FORCE_BLACK);
    {
        const force_world *w = g->world;
        uint8_t implied = force_command_implied_who(g);
        uint8_t i;

        if (g->cmd_who < FORCE_LETTER_MAX) {
            implied = g->cmd_who;
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
    (void)snprintf(line, sizeof(line), "SDL  %s  JOY %s  %s",
                   g->mission->name,
                   g->joy_present ? "YES" : "NO",
                   g->stick_latched ? "LINE" : "WASD");
    force_screen_puts(s, 1, 24, line, FORCE_CYAN, FORCE_DARK_GREY);

    force_screen_rasterize(s, g->pixels);
    blit_playfield(g);
    blit_cursor(g);
}
