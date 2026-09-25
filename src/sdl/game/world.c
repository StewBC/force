#include "game/world.h"

#include "core/types.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

force_world force_world_bss;

void force_copy_u8(uint8_t *dst, const uint8_t *src, uint16_t n)
{
    if (n == 0u) {
        return;
    }
    memcpy(dst, src, (size_t)n);
}

static void zero_u8(uint8_t *dst, uint16_t n)
{
    uint16_t i;
    for (i = 0; i < n; ++i) {
        dst[i] = 0u;
    }
}

static void copy_column(uint8_t *dst, const uint8_t *src,
                        uint8_t count, uint16_t cap)
{
    if (count > 0u) {
        force_copy_u8(dst, src, (uint16_t)count);
    }
    if ((uint16_t)count < cap) {
        zero_u8(dst + count, (uint16_t)(cap - (uint16_t)count));
    }
}

static uint8_t unit_region_at(const force_world *world, uint8_t x, uint8_t y)
{
    uint8_t i;

    for (i = 0u; i < world->room_count; ++i) {
        uint8_t x0 = world->room_x0[i];
        uint8_t y0 = world->room_y0[i];
        uint8_t x1 = (uint8_t)(x0 + world->room_w[i]);
        uint8_t y1 = (uint8_t)(y0 + world->room_h[i]);
        if (x >= x0 && x < x1 && y >= y0 && y < y1) {
            return i;
        }
    }
    return FORCE_UNIT_NONE;
}

static void note_contact(force_world *w, uint8_t x, uint8_t y)
{
    uint8_t r = unit_region_at(w, x, y);

    if (r < FORCE_ROOM_MAX) {
        w->room_heat[r] = FORCE_HEAT_START;
    }
}

static int is_portal_cell(const force_world *w, uint8_t x, uint8_t y);
static uint8_t manhattan(uint8_t x0, uint8_t y0, uint8_t x1, uint8_t y1);
static uint8_t effective_verb(const force_world *w, uint8_t i);
static uint8_t move_reload(const force_world *w, uint8_t i);
static int dest_remains(const force_world *w, uint8_t i);
static int move_dest(const force_world *w, uint8_t i, uint8_t sec,
                     uint8_t *ox, uint8_t *oy);
static int verb_takes_cover(uint8_t verb);
static void intel_pulse(force_world *w);

static int trace_on(void)
{
    static int v = -1;

    if (v < 0) {
        v = (getenv("FORCE_TRACE") != NULL) ? 1 : 0;
    }
    return v;
}

static int script_trace_on(void)
{
    static int v = -1;

    if (v < 0) {
        v = (getenv("FORCE_SCRIPT") != NULL ||
             getenv("FORCE_TRACE") != NULL) ? 1 : 0;
    }
    return v;
}

static int combat_trace_on(void)
{
    static int v = -1;

    if (v < 0) {
        v = (getenv("FORCE_COMBAT") != NULL ||
             getenv("FORCE_TRACE") != NULL) ? 1 : 0;
    }
    return v;
}

typedef struct combat_stats {
    uint8_t fire;
    uint8_t none;
    uint8_t dmg0;
    uint8_t silent;
    uint8_t nade;
} combat_stats;

static char section_ch(uint8_t s)
{
    if (s < FORCE_LETTER_MAX) {
        return (char)('A' + s);
    }
    if (s < FORCE_SECTION_MAX) {
        return (char)('a' + (s - FORCE_LETTER_MAX));
    }
    return '?';
}

static unsigned room_num(const force_world *w, uint8_t r)
{
    if (r >= w->room_count) {
        return 0u;
    }
    return (unsigned)w->room_colour[r];
}

static const char *script_beat_name(const force_script *sc, uint8_t i)
{
    if (sc != NULL && sc->beat_name != NULL && i < sc->beat_count) {
        return sc->beat_name[i];
    }
    return "?";
}

static const char *script_watch_name(const force_script *sc, uint8_t i)
{
    if (sc != NULL && sc->watch_name != NULL && i < sc->watch_count) {
        return sc->watch_name[i];
    }
    return "?";
}

static char face_ch(uint8_t f)
{
    if (f == FORCE_FACE_N) {
        return 'N';
    }
    if (f == FORCE_FACE_E) {
        return 'E';
    }
    if (f == FORCE_FACE_S) {
        return 'S';
    }
    if (f == FORCE_FACE_W) {
        return 'W';
    }
    return '-';
}

static const char *script_op_word(uint8_t op)
{
    if (op == FORCE_OP_SPAWN) {
        return "spawn";
    }
    if (op == FORCE_OP_ORDER) {
        return "order";
    }
    if (op == FORCE_OP_SET_SPAWN) {
        return "set spawn_room";
    }
    if (op == FORCE_OP_APPROACH) {
        return "approach";
    }
    if (op == FORCE_OP_GOTO) {
        return "goto";
    }
    if (op == FORCE_OP_WAIT) {
        return "wait";
    }
    if (op == FORCE_OP_WIN) {
        return "win";
    }
    if (op == FORCE_OP_LOSE) {
        return "lose";
    }
    return "?";
}

#define FORCE_SX_NEG  0xFFu

/* Rifle damage by where the target is, then by distance. A hole he
   was assigned and is standing on wins. Grade 3 from any side.
   Grades 2 and 1 only from the side that hole watches; any other
   side is the open number. Otherwise the verb, and only while he
   is still on the way. Dist 1–4 keeps that number. Dist 5–9 halves
   it. Dist 10 and out is not a target. */
#define FORCE_DMG_COVER3  1u
#define FORCE_DMG_COVER2  2u
#define FORCE_DMG_COVER1  3u
#define FORCE_DMG_SPRINT  5u
#define FORCE_DMG_WALK    7u
#define FORCE_DMG_OPEN   10u

static int8_t s8(uint8_t b)
{
    return (int8_t)b;
}

static int add_s(uint8_t pos, uint8_t s)
{
    return (int)pos + (int)s8(s);
}

static uint16_t hop_index(uint8_t from, uint8_t goal)
{
    return (uint16_t)from * (uint16_t)FORCE_ROOM_MAX + (uint16_t)goal;
}

static void infer_portals(force_world *world)
{
    static const int8_t dx[4] = { 0, 1, 0, -1 };
    static const int8_t dy[4] = { -1, 0, 1, 0 };
    uint8_t i, d;

    for (i = 0u; i < FORCE_PORTAL_MAX; ++i) {
        world->portal_from[i] = FORCE_UNIT_NONE;
        world->portal_to[i] = FORCE_UNIT_NONE;
    }
    for (i = 0u; i < world->portal_count; ++i) {
        uint8_t x = world->portal_x[i];
        uint8_t y = world->portal_y[i];
        uint8_t from = unit_region_at(world, x, y);
        uint8_t to = FORCE_UNIT_NONE;
        uint8_t n_foreign = 0u;
        uint8_t found = FORCE_UNIT_NONE;

        world->portal_from[i] = from;
        if (from == FORCE_UNIT_NONE) {
            continue;
        }
        for (d = 0u; d < 4u; ++d) {
            int nx = (int)x + (int)dx[d];
            int ny = (int)y + (int)dy[d];
            uint8_t r;
            if (nx < 0 || ny < 0 ||
                nx >= (int)world->width || ny >= (int)world->height) {
                continue;
            }
            r = unit_region_at(world, (uint8_t)nx, (uint8_t)ny);
            if (r != FORCE_UNIT_NONE && r != from) {
                n_foreign = (uint8_t)(n_foreign + 1u);
                found = r;
            }
        }
        if (n_foreign == 1u) {
            to = found;
        }
        world->portal_to[i] = to;
    }
}

static int tile_open(const force_world *w, int x, int y)
{
    uint8_t tid;
    uint8_t cls;

    if (x < 0 || y < 0 ||
        x >= (int)w->width || y >= (int)w->height) {
        return 0;
    }
    tid = w->tiles[(int)w->row_off[y] + x];
    cls = force_tile_class[tid];
    if (cls == FORCE_CLASS_WALLS || cls == FORCE_CLASS_BARRIERS) {
        return 0;
    }
    return 1;
}

static uint8_t collect_seam(const force_world *w, uint8_t here, uint8_t next,
                            uint8_t *hx, uint8_t *hy,
                            uint8_t *nx, uint8_t *ny)
{
    uint8_t n = 0u;
    uint8_t ax0, ay0, ax1, ay1;
    uint8_t bx0, by0, bx1, by1;
    uint8_t lo, hi;

    if (here >= w->room_count || next >= w->room_count || here == next) {
        return 0u;
    }
    ax0 = w->room_x0[here];
    ay0 = w->room_y0[here];
    ax1 = (uint8_t)(ax0 + w->room_w[here]);
    ay1 = (uint8_t)(ay0 + w->room_h[here]);
    bx0 = w->room_x0[next];
    by0 = w->room_y0[next];
    bx1 = (uint8_t)(bx0 + w->room_w[next]);
    by1 = (uint8_t)(by0 + w->room_h[next]);

    if (ax1 == bx0 || bx1 == ax0) {
        uint8_t x_here;
        uint8_t x_next;
        uint8_t y;

        lo = (ay0 > by0) ? ay0 : by0;
        hi = (ay1 < by1) ? ay1 : by1;
        if (ax1 == bx0) {
            x_here = (uint8_t)(ax1 - 1u);
            x_next = bx0;
        } else {
            x_here = ax0;
            x_next = (uint8_t)(bx1 - 1u);
        }
        for (y = lo; y < hi && n < FORCE_MAP_W_MAX; ++y) {
            if (tile_open(w, (int)x_here, (int)y) &&
                tile_open(w, (int)x_next, (int)y)) {
                hx[n] = x_here;
                hy[n] = y;
                nx[n] = x_next;
                ny[n] = y;
                n = (uint8_t)(n + 1u);
            }
        }
        return n;
    }
    if (ay1 == by0 || by1 == ay0) {
        uint8_t y_here;
        uint8_t y_next;
        uint8_t x;

        lo = (ax0 > bx0) ? ax0 : bx0;
        hi = (ax1 < bx1) ? ax1 : bx1;
        if (ay1 == by0) {
            y_here = (uint8_t)(ay1 - 1u);
            y_next = by0;
        } else {
            y_here = ay0;
            y_next = (uint8_t)(by1 - 1u);
        }
        for (x = lo; x < hi && n < FORCE_MAP_W_MAX; ++x) {
            if (tile_open(w, (int)x, (int)y_here) &&
                tile_open(w, (int)x, (int)y_next)) {
                hx[n] = x;
                hy[n] = y_here;
                nx[n] = x;
                ny[n] = y_next;
                n = (uint8_t)(n + 1u);
            }
        }
    }
    return n;
}

static int painted_link(const force_world *w, uint8_t a, uint8_t b)
{
    uint8_t i;

    for (i = 0u; i < w->portal_count; ++i) {
        uint8_t f = w->portal_from[i];
        uint8_t t = w->portal_to[i];
        if (f == FORCE_UNIT_NONE || t == FORCE_UNIT_NONE) {
            continue;
        }
        if ((f == a && t == b) || (f == b && t == a)) {
            return 1;
        }
    }
    return 0;
}

static int rooms_linked(const force_world *w, uint8_t a, uint8_t b)
{
    uint8_t hx[FORCE_MAP_W_MAX];
    uint8_t hy[FORCE_MAP_W_MAX];
    uint8_t nx[FORCE_MAP_W_MAX];
    uint8_t ny[FORCE_MAP_W_MAX];

    if (collect_seam(w, a, b, hx, hy, nx, ny) > 0u) {
        return 1;
    }
    return painted_link(w, a, b);
}

static void bake_next_hop(force_world *world)
{
    uint8_t src;
    uint16_t n;

    for (n = 0u; n < (uint16_t)FORCE_ROOM_MAX * (uint16_t)FORCE_ROOM_MAX; ++n) {
        world->next_hop[n] = FORCE_UNIT_NONE;
    }
    for (src = 0u; src < world->room_count; ++src) {
        uint8_t visited[FORCE_ROOM_MAX];
        uint8_t q[FORCE_ROOM_MAX];
        uint8_t qh = 0u, qt = 0u, i, u;

        for (i = 0u; i < FORCE_ROOM_MAX; ++i) {
            visited[i] = 0u;
        }
        q[qt++] = src;
        visited[src] = 1u;
        while (qh < qt) {
            u = q[qh++];
            for (i = 0u; i < world->room_count; ++i) {
                if (i == u || visited[i] || !rooms_linked(world, u, i)) {
                    continue;
                }
                visited[i] = 1u;
                if (u == src) {
                    world->next_hop[hop_index(src, i)] = i;
                } else {
                    world->next_hop[hop_index(src, i)] =
                        world->next_hop[hop_index(src, u)];
                }
                q[qt++] = i;
            }
        }
    }
}

static int cell_free(const force_world *w, uint8_t x, uint8_t y,
                     uint8_t self)
{
    uint8_t tid, cls, i;

    if (x >= w->width || y >= w->height) {
        return 0;
    }
    tid = w->tiles[(int)w->row_off[y] + x];
    cls = force_tile_class[tid];
    if (cls == FORCE_CLASS_WALLS || cls == FORCE_CLASS_BARRIERS) {
        return 0;
    }
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        if (i == self || w->unit_count[i] == 0u) {
            continue;
        }
        if (w->unit_x[i] == x && w->unit_y[i] == y) {
            return 0;
        }
    }
    return 1;
}

static int cell_terrain_solid(const force_world *w, int x, int y)
{
    uint8_t tid, cls;

    if (x < 0 || y < 0 ||
        x >= (int)w->width || y >= (int)w->height) {
        return 1;
    }
    tid = w->tiles[(int)w->row_off[y] + x];
    cls = force_tile_class[tid];
    return cls == FORCE_CLASS_WALLS || cls == FORCE_CLASS_BARRIERS;
}

static void stepper_aim(force_world *w, uint8_t i, uint8_t tx, uint8_t ty)
{
    int dx = (int)tx - (int)w->unit_x[i];
    int dy = (int)ty - (int)w->unit_y[i];
    uint8_t ax = (uint8_t)(dx < 0 ? -dx : dx);
    uint8_t ay = (uint8_t)(dy < 0 ? -dy : dy);

    w->unit_tgt_x[i] = tx;
    w->unit_tgt_y[i] = ty;
    w->unit_step_sx[i] = (dx > 0) ? 1u : (dx < 0) ? FORCE_SX_NEG : 0u;
    w->unit_step_sy[i] = (dy > 0) ? 1u : (dy < 0) ? FORCE_SX_NEG : 0u;
    w->unit_step_ax[i] = ax;
    w->unit_step_ay[i] = ay;
    w->unit_step_err[i] = (uint8_t)(int8_t)((int)ax - (int)ay);
    /* Cardinal far-run only. Both signs → diagonal each think. */
    if ((dx == 0 || dy == 0) &&
        (ax > FORCE_STEP_FAR || ay > FORCE_STEP_FAR)) {
        uint8_t major = (ax >= ay) ? ax : ay;
        w->unit_step_run[i] =
            (major < FORCE_STEP_CAP) ? major : (uint8_t)FORCE_STEP_CAP;
    } else {
        w->unit_step_run[i] = 0u;
    }
}

/* Goodguys 0-7 / enemies 8-15: N, NE, E, SE, S, SW, W, NW. */
static void apply_face_glyph(force_world *w, uint8_t i, uint8_t oct)
{
    uint8_t base = (w->unit_section[i] >= FORCE_LETTER_MAX) ? 8u : 0u;

    if (oct > 7u) {
        return;
    }
    w->unit_glyph[i] = (uint8_t)(base + oct);
}

static void face_step(force_world *w, uint8_t i, int nx, int ny)
{
    int dx = nx - (int)w->unit_x[i];
    int dy = ny - (int)w->unit_y[i];
    uint8_t oct;

    if (dx == 0 && dy == 0) {
        return;
    }
    if (dx > 0) {
        oct = (dy < 0) ? 1u : (dy > 0) ? 3u : 2u;
    } else if (dx < 0) {
        oct = (dy < 0) ? 7u : (dy > 0) ? 5u : 6u;
    } else {
        oct = (dy > 0) ? 4u : 0u;
    }
    apply_face_glyph(w, i, oct);
}

static void face_slot(force_world *w, uint8_t i, uint8_t facing)
{
    if (facing == FORCE_FACE_N) {
        apply_face_glyph(w, i, 0u);
    } else if (facing == FORCE_FACE_E) {
        apply_face_glyph(w, i, 2u);
    } else if (facing == FORCE_FACE_S) {
        apply_face_glyph(w, i, 4u);
    } else if (facing == FORCE_FACE_W) {
        apply_face_glyph(w, i, 6u);
    }
}

static int try_land(force_world *w, uint8_t i, int nx, int ny)
{
    if (nx < 0 || ny < 0 ||
        nx >= (int)w->width || ny >= (int)w->height) {
        return 0;
    }
    if (!cell_free(w, (uint8_t)nx, (uint8_t)ny, i)) {
        return 0;
    }
    face_step(w, i, nx, ny);
    w->unit_x[i] = (uint8_t)nx;
    w->unit_y[i] = (uint8_t)ny;
    w->unit_region[i] = unit_region_at(w, w->unit_x[i], w->unit_y[i]);
    return 1;
}

static int try_step(force_world *w, uint8_t i, int nx, int ny, int dodge)
{
    uint8_t nr;
    uint8_t orr = w->unit_region[i];

    if (nx < 0 || ny < 0 ||
        nx >= (int)w->width || ny >= (int)w->height) {
        return 0;
    }
    nr = unit_region_at(w, (uint8_t)nx, (uint8_t)ny);
    if (is_portal_cell(w, (uint8_t)nx, (uint8_t)ny)) {
        if (dodge) {
            return 0;
        }
        return try_land(w, i, nx, ny);
    }
    if (orr != FORCE_UNIT_NONE && nr != FORCE_UNIT_NONE && nr != orr) {
        /* Front: a preferred step may leave the room onto open dirt.
           Sidesteps stay in-room so they do not pop through the line. */
        if (dodge) {
            return 0;
        }
        return try_land(w, i, nx, ny);
    }
    return try_land(w, i, nx, ny);
}

static int stepper_step(force_world *w, uint8_t i)
{
    uint8_t ax = w->unit_step_ax[i];
    uint8_t ay = w->unit_step_ay[i];
    uint8_t sx = w->unit_step_sx[i];
    uint8_t sy = w->unit_step_sy[i];
    int8_t err = s8(w->unit_step_err[i]);
    int pref_x;
    int nx, ny;
    int moved = 0;

    if (ax == 0u && ay == 0u) {
        return 0;
    }

    if (sx != 0u && sy != 0u) {
        int cx = (int)w->unit_x[i];
        int cy = (int)w->unit_y[i];

        nx = add_s(w->unit_x[i], sx);
        ny = add_s(w->unit_y[i], sy);
        /* Both cardinals wall/barrier: no corner cut. Occupancy is dest. */
        if (!(cell_terrain_solid(w, nx, cy) &&
              cell_terrain_solid(w, cx, ny)) &&
            try_step(w, i, nx, ny, 0)) {
            w->unit_move_wait[i] = move_reload(w, i);
            return 1;
        }
    }

    if (w->unit_step_run[i] > 0u) {
        pref_x = (ax >= ay);
    } else {
        pref_x = (err >= 0);
    }

    if (pref_x && sx != 0u) {
        nx = add_s(w->unit_x[i], sx);
        ny = (int)w->unit_y[i];
        if (try_step(w, i, nx, ny, 0)) {
            if (w->unit_step_run[i] == 0u) {
                w->unit_step_err[i] = (uint8_t)(int8_t)(err - (int8_t)ay);
            } else {
                w->unit_step_run[i]--;
                if (w->unit_step_run[i] == 0u) {
                    stepper_aim(w, i, w->unit_tgt_x[i], w->unit_tgt_y[i]);
                }
            }
            w->unit_move_wait[i] = move_reload(w, i);
            return 1;
        }
    } else if (!pref_x && sy != 0u) {
        nx = (int)w->unit_x[i];
        ny = add_s(w->unit_y[i], sy);
        if (try_step(w, i, nx, ny, 0)) {
            if (w->unit_step_run[i] == 0u) {
                w->unit_step_err[i] = (uint8_t)(int8_t)(err + (int8_t)ax);
            } else {
                w->unit_step_run[i]--;
                if (w->unit_step_run[i] == 0u) {
                    stepper_aim(w, i, w->unit_tgt_x[i], w->unit_tgt_y[i]);
                }
            }
            w->unit_move_wait[i] = move_reload(w, i);
            return 1;
        }
    }

    if (pref_x && sy != 0u) {
        nx = (int)w->unit_x[i];
        ny = add_s(w->unit_y[i], sy);
        moved = try_step(w, i, nx, ny, 0);
    } else if (!pref_x && sx != 0u) {
        nx = add_s(w->unit_x[i], sx);
        ny = (int)w->unit_y[i];
        moved = try_step(w, i, nx, ny, 0);
    }

    /* Packed: sidestep RIGHT then LEFT. Dodges never land on a
       portal — that was u2's (22,8)/(21,8) bounce. Preferred
       steps still walk onto the chip to leave the room. */
    if (!moved) {
        if (pref_x && sx != 0u) {
            int sdy = (sx == 1u) ? 1 : -1;
            nx = (int)w->unit_x[i];
            ny = (int)w->unit_y[i] + sdy;
            moved = try_step(w, i, nx, ny, 1);
            if (!moved) {
                ny = (int)w->unit_y[i] - sdy;
                moved = try_step(w, i, nx, ny, 1);
            }
        } else if (!pref_x && sy != 0u) {
            int sdx = (sy == 1u) ? -1 : 1;
            nx = (int)w->unit_x[i] + sdx;
            ny = (int)w->unit_y[i];
            moved = try_step(w, i, nx, ny, 1);
            if (!moved) {
                nx = (int)w->unit_x[i] - sdx;
                moved = try_step(w, i, nx, ny, 1);
            }
        }
    }

    w->unit_step_run[i] = 0u;
    w->unit_move_wait[i] = move_reload(w, i);
    return moved;
}

static void fail_path(force_world *world, uint8_t sec)
{
    if ((world->section_flags[sec] & FORCE_SECTION_FLAG_NOPATH) == 0u) {
        world->section_flags[sec] =
            (uint8_t)(world->section_flags[sec] | FORCE_SECTION_FLAG_NOPATH);
        if (sec < FORCE_LETTER_MAX) {
            world->path_fail_who = sec;
        }
    }
}

static int cover_cell(const force_world *w, uint8_t c,
                      uint8_t *x, uint8_t *y)
{
    if (c == FORCE_UNIT_NONE) {
        return 0;
    }
    if (c < FORCE_COVER_MAX) {
        if (c >= w->cover_count) {
            return 0;
        }
        *x = w->cover_x[c];
        *y = w->cover_y[c];
        return 1;
    }
    c = (uint8_t)(c - FORCE_COVER_MAX);
    if (c >= w->scout_count) {
        return 0;
    }
    *x = w->scout_x[c];
    *y = w->scout_y[c];
    return 1;
}

static uint8_t opposite_face(uint8_t face)
{
    if (face == FORCE_FACE_N) {
        return FORCE_FACE_S;
    }
    if (face == FORCE_FACE_S) {
        return FORCE_FACE_N;
    }
    if (face == FORCE_FACE_E) {
        return FORCE_FACE_W;
    }
    if (face == FORCE_FACE_W) {
        return FORCE_FACE_E;
    }
    return FORCE_FACE_NONE;
}

static uint8_t snap_axis(uint8_t axis, int dx, int dy)
{
    if (axis == FORCE_AXIS_EW) {
        if (dx > 0) {
            return FORCE_FACE_E;
        }
        if (dx < 0) {
            return FORCE_FACE_W;
        }
        return FORCE_FACE_NONE;
    }
    if (axis == FORCE_AXIS_NS) {
        if (dy > 0) {
            return FORCE_FACE_S;
        }
        if (dy < 0) {
            return FORCE_FACE_N;
        }
        return FORCE_FACE_NONE;
    }
    return FORCE_FACE_NONE;
}

static uint8_t approach_front(uint8_t axis, uint8_t mask)
{
    if (axis == FORCE_AXIS_EW) {
        if ((mask & FORCE_APPROACH_E) != 0u) {
            return FORCE_FACE_E;
        }
        if ((mask & FORCE_APPROACH_W) != 0u) {
            return FORCE_FACE_W;
        }
        return FORCE_FACE_NONE;
    }
    if (axis == FORCE_AXIS_NS) {
        if ((mask & FORCE_APPROACH_S) != 0u) {
            return FORCE_FACE_S;
        }
        if ((mask & FORCE_APPROACH_N) != 0u) {
            return FORCE_FACE_N;
        }
        return FORCE_FACE_NONE;
    }
    if ((mask & FORCE_APPROACH_N) != 0u) {
        return FORCE_FACE_N;
    }
    if ((mask & FORCE_APPROACH_E) != 0u) {
        return FORCE_FACE_E;
    }
    if ((mask & FORCE_APPROACH_S) != 0u) {
        return FORCE_FACE_S;
    }
    if ((mask & FORCE_APPROACH_W) != 0u) {
        return FORCE_FACE_W;
    }
    return FORCE_FACE_NONE;
}

static uint8_t front_from_occupied(const force_world *w, uint8_t who,
                                   uint8_t room)
{
    uint8_t i;

    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        uint8_t c;
        uint8_t tag;

        if (w->unit_count[i] == 0u || w->unit_section[i] != who) {
            continue;
        }
        if (w->unit_over_verb[i] != FORCE_VERB_NONE) {
            continue;
        }
        if (w->unit_region[i] != room) {
            continue;
        }
        c = w->unit_cover[i];
        if (c >= w->cover_count) {
            continue;
        }
        tag = w->cover_facing[c];
        if (tag >= FORCE_COVER_SOFT_N || tag == FORCE_FACE_NONE) {
            continue;
        }
        return opposite_face(tag);
    }
    return FORCE_FACE_NONE;
}

static uint8_t section_front(const force_world *w, uint8_t who)
{
    uint8_t dest_r;
    uint8_t axis;
    uint8_t front;
    uint8_t verb;
    uint8_t lead;
    uint8_t here;
    uint8_t from_holes;
    int dx;
    int dy;

    if (who >= FORCE_SECTION_MAX) {
        return FORCE_FACE_NONE;
    }
    dest_r = unit_region_at(w, w->section_order_x[who],
                            w->section_order_y[who]);
    if (dest_r == FORCE_UNIT_NONE || dest_r >= w->room_count) {
        return FORCE_FACE_NONE;
    }
    axis = w->room_axis[dest_r];
    verb = w->section_order_verb[who];
    front = FORCE_FACE_NONE;
    from_holes = 0u;
    lead = w->section_lead[who];
    if (lead < FORCE_UNIT_MAX && w->unit_count[lead] != 0u &&
        w->unit_over_verb[lead] != FORCE_VERB_NONE) {
        uint8_t k;
        lead = FORCE_UNIT_NONE;
        for (k = 0u; k < FORCE_UNIT_MAX; ++k) {
            if (w->unit_count[k] == 0u || w->unit_section[k] != who) {
                continue;
            }
            if (w->unit_over_verb[k] != FORCE_VERB_NONE) {
                continue;
            }
            lead = k;
            break;
        }
    }
    if (lead < FORCE_UNIT_MAX && w->unit_count[lead] != 0u) {
        here = w->unit_region[lead];
        if (here != dest_r && here != FORCE_UNIT_NONE &&
            here < w->room_count) {
            dx = (int)w->room_x0[dest_r] + (int)(w->room_w[dest_r] / 2u)
               - ((int)w->room_x0[here] + (int)(w->room_w[here] / 2u));
            dy = (int)w->room_y0[dest_r] + (int)(w->room_h[dest_r] / 2u)
               - ((int)w->room_y0[here] + (int)(w->room_h[here] / 2u));
            front = snap_axis(axis, dx, dy);
        } else if (here == dest_r) {
            front = front_from_occupied(w, who, dest_r);
            if (front != FORCE_FACE_NONE) {
                from_holes = 1u;
            } else {
                dx = (int)w->section_order_x[who] - (int)w->unit_x[lead];
                dy = (int)w->section_order_y[who] - (int)w->unit_y[lead];
                front = snap_axis(axis, dx, dy);
            }
        } else {
            dx = (int)w->section_order_x[who] - (int)w->unit_x[lead];
            dy = (int)w->section_order_y[who] - (int)w->unit_y[lead];
            front = snap_axis(axis, dx, dy);
        }
    }
    if (front == FORCE_FACE_NONE) {
        front = approach_front(axis, w->room_approach[dest_r]);
    }
    if (verb == FORCE_VERB_RETREAT && from_holes == 0u) {
        front = opposite_face(front);
    }
    return front;
}

static int verb_takes_cover(uint8_t verb)
{
    return verb == FORCE_VERB_DEFEND ||
           verb == FORCE_VERB_ATTACK ||
           verb == FORCE_VERB_RETREAT;
}

static uint8_t cover_dir(uint8_t tag)
{
    if (tag >= FORCE_COVER_HARD_N) {
        return (uint8_t)(tag - FORCE_COVER_HARD_N + FORCE_FACE_N);
    }
    if (tag >= FORCE_COVER_SOFT_N) {
        return (uint8_t)(tag - FORCE_COVER_SOFT_N + FORCE_FACE_N);
    }
    return tag;
}

static uint8_t cover_look(const force_world *w, uint8_t who, uint8_t tag)
{
    if (tag >= FORCE_COVER_HARD_N) {
        return cover_dir(tag);
    }
    if (tag >= FORCE_COVER_SOFT_N || tag == FORCE_FACE_NONE) {
        return section_front(w, who);
    }
    return opposite_face(tag);
}

static uint8_t manhattan(uint8_t x0, uint8_t y0, uint8_t x1, uint8_t y1)
{
    int dx = (int)x0 - (int)x1;
    int dy = (int)y0 - (int)y1;
    if (dx < 0) {
        dx = -dx;
    }
    if (dy < 0) {
        dy = -dy;
    }
    return (uint8_t)(dx + dy);
}

static int cover_taken(const force_world *w, uint8_t encoded)
{
    uint8_t i;

    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        if (w->unit_count[i] == 0u) {
            continue;
        }
        if (w->unit_cover[i] == encoded) {
            return 1;
        }
    }
    return 0;
}

static uint8_t effective_verb(const force_world *w, uint8_t i)
{
    if (w->unit_over_verb[i] != FORCE_VERB_NONE) {
        return w->unit_over_verb[i];
    }
    return w->section_order_verb[w->unit_section[i]];
}

static uint8_t move_reload(const force_world *w, uint8_t i)
{
    if (effective_verb(w, i) == FORCE_VERB_MOVE) {
        return FORCE_MOVE_WAIT_SPRINT;
    }
    return FORCE_MOVE_WAIT_DEFAULT;
}

static uint8_t chip_at(const force_world *w, uint8_t x, uint8_t y)
{
    uint8_t c;
    uint8_t s;

    for (c = 0u; c < w->cover_count; ++c) {
        if (w->cover_x[c] == x && w->cover_y[c] == y) {
            return c;
        }
    }
    for (s = 0u; s < w->scout_count; ++s) {
        if (w->scout_x[s] == x && w->scout_y[s] == y) {
            return (uint8_t)(FORCE_COVER_MAX + s);
        }
    }
    return FORCE_UNIT_NONE;
}

static void occupy_if_chip(force_world *w, uint8_t i, uint8_t x, uint8_t y)
{
    uint8_t enc;

    if (w->unit_cover[i] != FORCE_UNIT_NONE) {
        return;
    }
    enc = chip_at(w, x, y);
    if (enc == FORCE_UNIT_NONE || cover_taken(w, enc)) {
        return;
    }
    w->unit_cover[i] = enc;
}

static int unit_dest(const force_world *w, uint8_t i, uint8_t *ox, uint8_t *oy)
{
    uint8_t sec = w->unit_section[i];
    uint8_t verb = effective_verb(w, i);

    if (w->unit_over_verb[i] != FORCE_VERB_NONE) {
        *ox = w->unit_over_x[i];
        *oy = w->unit_over_y[i];
        return 1;
    }
    if (verb == FORCE_VERB_MOVE) {
        return move_dest(w, i, sec, ox, oy);
    }
    if (verb_takes_cover(verb)) {
        if (!cover_cell(w, w->unit_cover[i], ox, oy)) {
            return move_dest(w, i, sec, ox, oy);
        }
        return 1;
    }
    return 0;
}

static uint8_t pick_best(const force_world *w, uint8_t i, uint8_t room,
                         uint8_t front)
{
    uint8_t best = FORCE_UNIT_NONE;
    uint8_t best_tier = 0u;
    uint8_t best_manh = 0xFFu;
    uint8_t have = 0u;
    uint8_t b, n, j, start, rear, lo, none, hi, axis, who;

    who = w->unit_section[i];
    axis = w->room_axis[room];
    b = w->room_cover_base[room];
    lo = w->room_cover_lo[room];
    none = w->room_cover_none[room];
    hi = w->room_cover_hi[room];
    rear = opposite_face(front);
    if (front == FORCE_FACE_NONE || axis == FORCE_AXIS_NONE) {
        start = (uint8_t)(b + lo);
        n = none;
    } else if ((axis == FORCE_AXIS_EW && rear == FORCE_FACE_E) ||
               (axis == FORCE_AXIS_NS && rear == FORCE_FACE_N)) {
        start = b;
        n = (uint8_t)(lo + none);
    } else if ((axis == FORCE_AXIS_EW && rear == FORCE_FACE_W) ||
               (axis == FORCE_AXIS_NS && rear == FORCE_FACE_S)) {
        start = (uint8_t)(b + lo);
        n = (uint8_t)(none + hi);
    } else {
        start = (uint8_t)(b + lo);
        n = none;
    }
    for (j = 0u; j < n; ++j) {
        uint8_t c = (uint8_t)(start + j);
        uint8_t g, tier, manh;
        if (c >= w->cover_count) {
            break;
        }
        if (w->section_order_verb[who] == FORCE_VERB_KILL &&
            w->cover_x[c] == w->section_order_x[who] &&
            w->cover_y[c] == w->section_order_y[who]) {
            continue;
        }
        if (cover_taken(w, c)) {
            continue;
        }
        g = w->cover_grade[c];
        if (g == 3u) {
            tier = 4u;
        } else if (g == 2u) {
            tier = 2u;
        } else if (g == 1u) {
            tier = 0u;
        } else {
            continue;
        }
        manh = manhattan(w->unit_x[i], w->unit_y[i],
                         w->cover_x[c], w->cover_y[c]);
        if (!have || tier > best_tier ||
            (tier == best_tier && manh < best_manh) ||
            (tier == best_tier && manh == best_manh && c < best)) {
            have = 1u;
            best = c;
            best_tier = tier;
            best_manh = manh;
        }
    }

    b = w->room_scout_base[room];
    n = w->room_scout_count[room];
    for (j = 0u; j < n; ++j) {
        uint8_t s = (uint8_t)(b + j);
        uint8_t enc, manh;
        if (s >= w->scout_count) {
            break;
        }
        if (w->section_order_verb[who] == FORCE_VERB_KILL &&
            w->scout_x[s] == w->section_order_x[who] &&
            w->scout_y[s] == w->section_order_y[who]) {
            continue;
        }
        if (front == FORCE_FACE_NONE ||
            w->scout_facing[s] != front) {
            continue;
        }
        enc = (uint8_t)(FORCE_COVER_MAX + s);
        if (cover_taken(w, enc)) {
            continue;
        }
        manh = manhattan(w->unit_x[i], w->unit_y[i],
                         w->scout_x[s], w->scout_y[s]);
        if (!have || 3u > best_tier ||
            (3u == best_tier && manh < best_manh) ||
            (3u == best_tier && manh == best_manh && enc < best)) {
            have = 1u;
            best = enc;
            best_tier = 3u;
            best_manh = manh;
        }
    }
    return have ? best : FORCE_UNIT_NONE;
}

void force_cover_release(force_world *world, uint8_t who)
{
    uint8_t i;

    if (who >= FORCE_SECTION_MAX) {
        return;
    }
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        if (world->unit_section[i] != who) {
            continue;
        }
        if (world->unit_over_verb[i] != FORCE_VERB_NONE) {
            continue;
        }
        world->unit_cover[i] = FORCE_UNIT_NONE;
    }
}

void force_cover_assign(force_world *world, uint8_t who)
{
    uint8_t i;
    uint8_t dest_r;
    uint8_t front;

    if (who >= FORCE_SECTION_MAX) {
        return;
    }
    dest_r = unit_region_at(world,
                            world->section_order_x[who],
                            world->section_order_y[who]);
    if (dest_r == FORCE_UNIT_NONE || dest_r >= world->room_count) {
        force_cover_release(world, who);
        return;
    }
    front = section_front(world, who);
    force_cover_release(world, who);
    if (script_trace_on()) {
        fprintf(stderr,
                "script t=%u cover who %u verb %u front %c dest %u\n",
                (unsigned)world->script_clock,
                (unsigned)who,
                (unsigned)world->section_order_verb[who],
                face_ch(front),
                (unsigned)dest_r);
    }
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        if (world->unit_count[i] == 0u) {
            continue;
        }
        if (world->unit_section[i] != who) {
            continue;
        }
        if (world->unit_kind[i] == FORCE_KIND_EMPLACEMENT) {
            continue;
        }
        if (world->unit_over_verb[i] != FORCE_VERB_NONE) {
            continue;
        }
        world->unit_cover[i] = pick_best(world, i, dest_r, front);
    }
}

static int same_portal_edge(const force_world *w, uint8_t a, uint8_t b)
{
    uint8_t af, at, bf, bt;

    if (a >= w->portal_count || b >= w->portal_count) {
        return 0;
    }
    af = w->portal_from[a];
    at = w->portal_to[a];
    bf = w->portal_from[b];
    bt = w->portal_to[b];
    if (af == FORCE_UNIT_NONE || at == FORCE_UNIT_NONE ||
        bf == FORCE_UNIT_NONE || bt == FORCE_UNIT_NONE) {
        return 0;
    }
    return (af == bf && at == bt) || (af == bt && at == bf);
}

/* Keep-right lane among chips that share seed's from/to.
   West → northernmost, east → southernmost, north → east, south → west. */
static int pick_front_aim(const force_world *w, uint8_t i,
                          uint8_t here, uint8_t next,
                          uint8_t dest_x, uint8_t dest_y,
                          uint8_t *dx, uint8_t *dy)
{
    uint8_t hx[FORCE_MAP_W_MAX];
    uint8_t hy[FORCE_MAP_W_MAX];
    uint8_t nx[FORCE_MAP_W_MAX];
    uint8_t ny[FORCE_MAP_W_MAX];
    uint8_t n;
    uint8_t k;
    uint8_t ux = w->unit_x[i];
    uint8_t uy = w->unit_y[i];
    uint8_t best;
    uint8_t best_manh;
    int tdx;
    int tdy;
    int adx;
    int ady;
    int horiz;

    n = collect_seam(w, here, next, hx, hy, nx, ny);
    if (n == 0u) {
        return 0;
    }
    for (k = 0u; k < n; ++k) {
        if (ux == hx[k] && uy == hy[k]) {
            *dx = nx[k];
            *dy = ny[k];
            return 1;
        }
    }
    tdx = (int)dest_x - (int)ux;
    tdy = (int)dest_y - (int)uy;
    adx = (tdx < 0) ? -tdx : tdx;
    ady = (tdy < 0) ? -tdy : tdy;
    horiz = (adx >= ady);
    best = 0u;
    best_manh = 0xFFu;
    for (k = 0u; k < n; ++k) {
        uint8_t manh;
        int better;

        if (n > 2u) {
            manh = manhattan(ux, uy, hx[k], hy[k]);
            if (k == 0u || manh < best_manh ||
                (manh == best_manh && k < best)) {
                best = k;
                best_manh = manh;
            }
            continue;
        }
        better = 0;
        if (horiz) {
            if (tdx < 0) {
                better = (hy[k] < hy[best]) ||
                         (hy[k] == hy[best] && hx[k] < hx[best]);
            } else {
                better = (hy[k] > hy[best]) ||
                         (hy[k] == hy[best] && hx[k] > hx[best]);
            }
        } else {
            if (tdy < 0) {
                better = (hx[k] > hx[best]) ||
                         (hx[k] == hx[best] && hy[k] < hy[best]);
            } else {
                better = (hx[k] < hx[best]) ||
                         (hx[k] == hx[best] && hy[k] > hy[best]);
            }
        }
        if (k == 0u || better) {
            best = k;
        }
    }
    *dx = hx[best];
    *dy = hy[best];
    return 1;
}

static uint8_t pick_keep_right(const force_world *w, uint8_t i,
                               uint8_t seed, uint8_t dest_x, uint8_t dest_y)
{
    int tdx = (int)dest_x - (int)w->unit_x[i];
    int tdy = (int)dest_y - (int)w->unit_y[i];
    int adx = (tdx < 0) ? -tdx : tdx;
    int ady = (tdy < 0) ? -tdy : tdy;
    int horiz = (adx >= ady);
    uint8_t best = seed;
    uint8_t bx = w->portal_x[seed];
    uint8_t by = w->portal_y[seed];
    uint8_t k;

    for (k = 0u; k < w->portal_count; ++k) {
        uint8_t px, py;
        int better = 0;
        if (k == seed || !same_portal_edge(w, seed, k)) {
            continue;
        }
        px = w->portal_x[k];
        py = w->portal_y[k];
        if (horiz) {
            if (tdx < 0) {
                better = (py < by) || (py == by && px < bx);
            } else {
                better = (py > by) || (py == by && px > bx);
            }
        } else {
            if (tdy < 0) {
                better = (px > bx) || (px == bx && py < by);
            } else {
                better = (px < bx) || (px == bx && py > by);
            }
        }
        if (better) {
            best = k;
            bx = px;
            by = py;
        }
    }
    return best;
}

static int portal_exit(const force_world *w, uint8_t p, uint8_t here,
                       uint8_t *ex, uint8_t *ey)
{
    static const int8_t dx[4] = { 0, 1, 0, -1 };
    static const int8_t dy[4] = { -1, 0, 1, 0 };
    uint8_t other;
    uint8_t d;

    if (p >= w->portal_count) {
        return 0;
    }
    if (w->portal_from[p] == here) {
        other = w->portal_to[p];
    } else if (w->portal_to[p] == here) {
        other = w->portal_from[p];
    } else {
        return 0;
    }
    if (other == FORCE_UNIT_NONE) {
        return 0;
    }
    for (d = 0u; d < 4u; ++d) {
        int nx = (int)w->portal_x[p] + (int)dx[d];
        int ny = (int)w->portal_y[p] + (int)dy[d];
        uint8_t r;

        if (nx < 0 || ny < 0 ||
            nx >= (int)w->width || ny >= (int)w->height) {
            continue;
        }
        r = unit_region_at(w, (uint8_t)nx, (uint8_t)ny);
        if (r == other) {
            *ex = (uint8_t)nx;
            *ey = (uint8_t)ny;
            return 1;
        }
    }
    return 0;
}

static int is_portal_cell(const force_world *w, uint8_t x, uint8_t y)
{
    uint8_t k;

    for (k = 0u; k < w->portal_count; ++k) {
        if (w->portal_x[k] == x && w->portal_y[k] == y &&
            w->portal_from[k] != FORCE_UNIT_NONE &&
            w->portal_to[k] != FORCE_UNIT_NONE) {
            return 1;
        }
    }
    return 0;
}

static int blob_passable(const force_world *w, int x, int y, uint8_t dest_r)
{
    uint8_t tid, cls;

    if (x < 0 || y < 0 || x >= (int)w->width || y >= (int)w->height) {
        return 0;
    }
    if (unit_region_at(w, (uint8_t)x, (uint8_t)y) != dest_r) {
        return 0;
    }
    if (is_portal_cell(w, (uint8_t)x, (uint8_t)y)) {
        return 0;
    }
    tid = w->tiles[(int)w->row_off[y] + x];
    cls = force_tile_class[tid];
    if (cls == FORCE_CLASS_WALLS || cls == FORCE_CLASS_BARRIERS) {
        return 0;
    }
    return 1;
}

/* 3x3 rank around WHERE. Fill: C, N, S, W, E, NW, SE, NE, SW. */
static int move_dest(const force_world *w, uint8_t i, uint8_t sec,
                     uint8_t *ox, uint8_t *oy)
{
    static const int8_t bdx[9] = { 0,  0,  0, -1, 1, -1,  1,  1, -1 };
    static const int8_t bdy[9] = { 0, -1,  1,  0, 0, -1,  1, -1,  1 };
    uint8_t wx = w->section_order_x[sec];
    uint8_t wy = w->section_order_y[sec];
    uint8_t dest_r = unit_region_at(w, wx, wy);
    uint8_t rank = 0u;
    uint8_t seen = 0u;
    uint8_t j, k;
    uint8_t last_x = wx;
    uint8_t last_y = wy;
    int have = 0;

    for (j = 0u; j < i; ++j) {
        if (w->unit_count[j] == 0u) {
            continue;
        }
        if (w->unit_section[j] != sec) {
            continue;
        }
        if (w->unit_kind[j] == FORCE_KIND_EMPLACEMENT) {
            continue;
        }
        rank = (uint8_t)(rank + 1u);
    }
    for (k = 0u; k < 9u; ++k) {
        int x = (int)wx + (int)bdx[k];
        int y = (int)wy + (int)bdy[k];
        if (!blob_passable(w, x, y, dest_r)) {
            continue;
        }
        last_x = (uint8_t)x;
        last_y = (uint8_t)y;
        have = 1;
        if (seen == rank) {
            *ox = (uint8_t)x;
            *oy = (uint8_t)y;
            return 1;
        }
        seen = (uint8_t)(seen + 1u);
    }
    *ox = have ? last_x : wx;
    *oy = have ? last_y : wy;
    return 1;
}

static int pull_desired(force_world *w, uint8_t i, uint8_t sec,
                        uint8_t ox, uint8_t oy,
                        uint8_t *here_out, uint8_t *dest_out,
                        uint8_t *p_out, uint8_t *dx, uint8_t *dy)
{
    uint8_t dest_r = unit_region_at(w, ox, oy);
    uint8_t here = w->unit_region[i];
    uint8_t p = FORCE_UNIT_NONE;

    *here_out = here;
    *dest_out = dest_r;
    *p_out = FORCE_UNIT_NONE;
    if (here == FORCE_UNIT_NONE || here >= w->room_count ||
        dest_r == FORCE_UNIT_NONE || dest_r >= w->room_count) {
        fail_path(w, sec);
        return 0;
    }
    if (here == dest_r) {
        *dx = ox;
        *dy = oy;
        return 1;
    }
    p = w->next_hop[hop_index(here, dest_r)];
    if (p == FORCE_UNIT_NONE || p >= w->room_count) {
        fail_path(w, sec);
        return 0;
    }
    if (pick_front_aim(w, i, here, p, ox, oy, dx, dy)) {
        *p_out = FORCE_UNIT_NONE;
        return 1;
    }
    /* No open seam: fall back to a painted door chip. */
    {
        uint8_t seed = FORCE_UNIT_NONE;
        uint8_t k;
        for (k = 0u; k < w->portal_count; ++k) {
            uint8_t a = w->portal_from[k];
            uint8_t b = w->portal_to[k];
            if (a == FORCE_UNIT_NONE || b == FORCE_UNIT_NONE) {
                continue;
            }
            if ((a == here && b == p) || (a == p && b == here)) {
                seed = k;
                break;
            }
        }
        if (seed == FORCE_UNIT_NONE) {
            fail_path(w, sec);
            return 0;
        }
        p = pick_keep_right(w, i, seed, ox, oy);
    }
    *p_out = p;
    {
        uint8_t on = FORCE_UNIT_NONE;
        uint8_t k;
        uint8_t ux = w->unit_x[i];
        uint8_t uy = w->unit_y[i];

        for (k = 0u; k < w->portal_count; ++k) {
            if (w->portal_x[k] == ux && w->portal_y[k] == uy &&
                (k == p || same_portal_edge(w, p, k))) {
                on = k;
                break;
            }
        }
        if (on != FORCE_UNIT_NONE) {
            /* On the chip: step into the other room, do not aim at self. */
            if (!portal_exit(w, on, here, dx, dy)) {
                fail_path(w, sec);
                return 0;
            }
        } else {
            *dx = w->portal_x[p];
            *dy = w->portal_y[p];
        }
    }
    return 1;
}

static int try_portal_cross(force_world *w, uint8_t i, uint8_t here,
                            uint8_t p)
{
    uint8_t on = FORCE_UNIT_NONE;
    uint8_t k;
    uint8_t ex, ey;
    uint8_t ux = w->unit_x[i];
    uint8_t uy = w->unit_y[i];

    for (k = 0u; k < w->portal_count; ++k) {
        if (w->portal_x[k] == ux && w->portal_y[k] == uy &&
            (k == p || same_portal_edge(w, p, k))) {
            on = k;
            break;
        }
    }
    if (on == FORCE_UNIT_NONE) {
        return 0;
    }
    if (!portal_exit(w, on, here, &ex, &ey)) {
        return 0;
    }
    return try_land(w, i, (int)ex, (int)ey);
}

static void unit_think(force_world *w, uint8_t i)
{
    uint8_t sec = w->unit_section[i];
    uint8_t verb = effective_verb(w, i);
    uint8_t here, dest_r, p, dx, dy;
    uint8_t ox, oy;

    w->unit_region[i] = unit_region_at(w, w->unit_x[i], w->unit_y[i]);

    if (!unit_dest(w, i, &ox, &oy)) {
        return;   /* NONE / HALT / K: hold here. Shoot already ran. */
    }
    if (!pull_desired(w, i, sec, ox, oy, &here, &dest_r, &p, &dx, &dy)) {
        return;
    }
    if (w->unit_x[i] == ox && w->unit_y[i] == oy && here == dest_r) {
        if (verb == FORCE_VERB_MOVE) {
            occupy_if_chip(w, i, ox, oy);
        }
        if (verb_takes_cover(verb) ||
            (verb == FORCE_VERB_MOVE && w->unit_cover[i] != FORCE_UNIT_NONE)) {
            uint8_t c = w->unit_cover[i];
            if (c < FORCE_COVER_MAX) {
                face_slot(w, i, cover_look(w, sec, w->cover_facing[c]));
            } else if (c != FORCE_UNIT_NONE) {
                uint8_t s = (uint8_t)(c - FORCE_COVER_MAX);
                if (s < w->scout_count) {
                    face_slot(w, i, w->scout_facing[s]);
                }
            }
        }
        return;
    }
    if (trace_on()) {
        fprintf(stderr,
                "u%u (%u,%u) r%u -> (%u,%u) R%u v%u c%u p%u aim(%u,%u)\n",
                (unsigned)i,
                (unsigned)w->unit_x[i], (unsigned)w->unit_y[i],
                (unsigned)here,
                (unsigned)ox, (unsigned)oy, (unsigned)dest_r,
                (unsigned)verb, (unsigned)w->unit_cover[i],
                (unsigned)p, (unsigned)dx, (unsigned)dy);
    }
    if (here != dest_r && p != FORCE_UNIT_NONE) {
        if (try_portal_cross(w, i, here, p)) {
            if (verb == FORCE_VERB_RETREAT) {
                face_slot(w, i, section_front(w, sec));
            }
            if (trace_on()) {
                fprintf(stderr, "  cross -> (%u,%u) r%u\n",
                        (unsigned)w->unit_x[i], (unsigned)w->unit_y[i],
                        (unsigned)w->unit_region[i]);
            }
            return;
        }
    }
    stepper_aim(w, i, dx, dy);
    (void)stepper_step(w, i);
    if (verb == FORCE_VERB_RETREAT) {
        face_slot(w, i, section_front(w, sec));
    }
    if (verb == FORCE_VERB_MOVE &&
        w->unit_x[i] == ox && w->unit_y[i] == oy) {
        occupy_if_chip(w, i, ox, oy);
    }
    if (trace_on()) {
        fprintf(stderr, "  step -> (%u,%u) r%u\n",
                (unsigned)w->unit_x[i], (unsigned)w->unit_y[i],
                (unsigned)w->unit_region[i]);
    }
}

static int blocks_sight(const force_world *w, int x, int y)
{
    uint8_t tid, cls;

    if (x < 0 || y < 0 ||
        x >= (int)w->width || y >= (int)w->height) {
        return 1;
    }
    tid = w->tiles[(int)w->row_off[y] + x];
    cls = force_tile_class[tid];
    return (cls == FORCE_CLASS_WALLS || cls == FORCE_CLASS_ROOFS);
}

static uint8_t chebyshev(uint8_t x0, uint8_t y0, uint8_t x1, uint8_t y1)
{
    int dx = (int)x0 - (int)x1;
    int dy = (int)y0 - (int)y1;
    if (dx < 0) {
        dx = -dx;
    }
    if (dy < 0) {
        dy = -dy;
    }
    return (uint8_t)((dx > dy) ? dx : dy);
}

/* Parked. Rifles do not call this. The walk stays so a later pass
   can turn sight back on without rewriting it. */
__attribute__((unused))
static int los_clear(const force_world *w,
                     uint8_t x0, uint8_t y0, uint8_t x1, uint8_t y1)
{
    int dx = (int)x1 - (int)x0;
    int dy = (int)y1 - (int)y0;
    int adx = (dx < 0) ? -dx : dx;
    int ady = (dy < 0) ? -dy : dy;
    int sx = (dx > 0) - (dx < 0);
    int sy = (dy > 0) - (dy < 0);
    int x = (int)x0;
    int y = (int)y0;
    int n = (adx > ady) ? adx : ady;
    int i, err;

    if (n <= 1) {
        return 1;
    }
    if (n >= (int)FORCE_RANGE_MAX) {
        return 0;
    }
    if (adx >= ady) {
        err = adx / 2;
        for (i = 1; i < n; ++i) {
            x += sx;
            err += ady;
            if (err >= adx) {
                err -= adx;
                y += sy;
            }
            if (blocks_sight(w, x, y)) {
                return 0;
            }
        }
    } else {
        err = ady / 2;
        for (i = 1; i < n; ++i) {
            y += sy;
            err += adx;
            if (err >= ady) {
                err -= ady;
                x += sx;
            }
            if (blocks_sight(w, x, y)) {
                return 0;
            }
        }
    }
    return 1;
}

static int blocks_blast(const force_world *w, int x, int y)
{
    uint8_t tid, cls;

    if (x < 0 || y < 0 ||
        x >= (int)w->width || y >= (int)w->height) {
        return 1;
    }
    tid = w->tiles[(int)w->row_off[y] + x];
    cls = force_tile_class[tid];
    return cls == FORCE_CLASS_WALLS;
}

/* Skip endpoints. Walls occlude; roofs do not. */
static int blast_clear(const force_world *w,
                       uint8_t x0, uint8_t y0, uint8_t x1, uint8_t y1)
{
    int dx = (int)x1 - (int)x0;
    int dy = (int)y1 - (int)y0;
    int adx = (dx < 0) ? -dx : dx;
    int ady = (dy < 0) ? -dy : dy;
    int sx = (dx > 0) - (dx < 0);
    int sy = (dy > 0) - (dy < 0);
    int x = (int)x0;
    int y = (int)y0;
    int n = (adx > ady) ? adx : ady;
    int i, err;

    if (n <= 1) {
        return 1;
    }
    if (n > (int)FORCE_GRENADE_BLAST) {
        return 0;
    }
    if (adx >= ady) {
        err = adx / 2;
        for (i = 1; i < n; ++i) {
            x += sx;
            err += ady;
            if (err >= adx) {
                err -= adx;
                y += sy;
            }
            if (blocks_blast(w, x, y)) {
                return 0;
            }
        }
    } else {
        err = ady / 2;
        for (i = 1; i < n; ++i) {
            y += sy;
            err += adx;
            if (err >= ady) {
                err -= ady;
                x += sx;
            }
            if (blocks_blast(w, x, y)) {
                return 0;
            }
        }
    }
    return 1;
}

static int in_blast(const force_world *w,
                    uint8_t ox, uint8_t oy, uint8_t x, uint8_t y)
{
    uint8_t d = chebyshev(ox, oy, x, y);

    if (d > FORCE_GRENADE_BLAST) {
        return 0;
    }
    return blast_clear(w, ox, oy, x, y);
}

static uint8_t grenade_bank(uint8_t sec)
{
    return (sec >= FORCE_LETTER_MAX) ? 1u : 0u;
}

int force_grenade_fx_at(const force_world *w, uint8_t x, uint8_t y)
{
    uint8_t b;
    uint8_t tid;
    uint8_t cls;

    if (x >= w->width || y >= w->height) {
        return 0;
    }
    tid = w->tiles[(int)w->row_off[y] + x];
    cls = force_tile_class[tid];
    if (cls == FORCE_CLASS_WALLS || cls == FORCE_CLASS_ROOFS) {
        return 0;
    }
    for (b = 0u; b < FORCE_GRENADE_BANK; ++b) {
        if (w->nade_fx_ttl[b] == 0u) {
            continue;
        }
        if (in_blast(w, w->nade_fx_x[b], w->nade_fx_y[b], x, y)) {
            return 1;
        }
    }
    return 0;
}

int force_room_seen(const force_world *w, uint8_t r)
{
    if (r >= w->room_count) {
        return 1;
    }
#if FORCE_FOG
    return (w->room_flags[r] & (FORCE_ROOM_SEEN | FORCE_ROOM_HOME)) != 0u;
#else
    (void)w;
    return 1;
#endif
}

int force_room_enemy_visible(const force_world *w, uint8_t r)
{
    if (r >= w->room_count) {
        return 1;
    }
#if FORCE_FOG
    return (w->room_flags[r] & (FORCE_ROOM_LIVE | FORCE_ROOM_HOME)) != 0u;
#else
    (void)w;
    return 1;
#endif
}

static uint8_t intel_next_flag(const force_world *w, uint8_t prev, uint8_t want)
{
    uint8_t i;
    uint8_t n = w->room_count;
    uint8_t start;

    if (n == 0u) {
        return FORCE_UNIT_NONE;
    }
    if (n > FORCE_ROOM_MAX) {
        n = FORCE_ROOM_MAX;
    }
    start = (prev < n) ? (uint8_t)((prev + 1u) % n) : 0u;
    for (i = 0u; i < n; ++i) {
        uint8_t r = (uint8_t)((start + i) % n);

        if (want == 0u) {
            if (w->room_heat[r] > 0u) {
                return r;
            }
        } else if ((w->room_flags[r] & want) != 0u) {
            return r;
        }
    }
    return FORCE_UNIT_NONE;
}

uint8_t force_intel_next_hot(const force_world *w, uint8_t prev)
{
    return intel_next_flag(w, prev, 0u);
}

uint8_t force_intel_next_mark(const force_world *w, uint8_t prev)
{
    return intel_next_flag(w, prev, FORCE_ROOM_MARK);
}

uint8_t force_intel_player_in_room(const force_world *w, uint8_t r)
{
    uint8_t i;

    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        uint8_t s;
        if (w->unit_count[i] == 0u) {
            continue;
        }
        if (w->unit_region[i] != r) {
            continue;
        }
        s = w->unit_section[i];
        if (s < FORCE_LETTER_MAX) {
            return s;
        }
    }
    return FORCE_UNIT_NONE;
}

static void intel_pulse(force_world *w)
{
    uint8_t i;
    uint8_t enemy_in[FORCE_ROOM_MAX];

    zero_u8(enemy_in, FORCE_ROOM_MAX);
    for (i = 0u; i < FORCE_ROOM_MAX; ++i) {
        w->room_flags[i] = (uint8_t)(w->room_flags[i] &
            (uint8_t)~FORCE_ROOM_LIVE);
    }
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        uint8_t r;
        if (w->unit_count[i] == 0u || w->unit_hp[i] == 0u) {
            continue;
        }
        if (w->unit_section[i] >= FORCE_LETTER_MAX) {
            continue;
        }
        r = w->unit_region[i];
        if (r >= FORCE_ROOM_MAX) {
            r = unit_region_at(w, w->unit_x[i], w->unit_y[i]);
        }
        if (r < w->room_count && r < FORCE_ROOM_MAX) {
            w->room_flags[r] = (uint8_t)(w->room_flags[r] |
                FORCE_ROOM_LIVE | FORCE_ROOM_SEEN);
        }
    }
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        uint8_t r;
        uint8_t s;
        if (w->unit_count[i] == 0u || w->unit_hp[i] == 0u) {
            continue;
        }
        s = w->unit_section[i];
        if (s < FORCE_LETTER_MAX || s >= FORCE_SECTION_MAX) {
            continue;
        }
        r = w->unit_region[i];
        if (r >= FORCE_ROOM_MAX) {
            r = unit_region_at(w, w->unit_x[i], w->unit_y[i]);
        }
        if (r >= w->room_count || r >= FORCE_ROOM_MAX) {
            continue;
        }
        enemy_in[r] = 1u;
        if (force_room_enemy_visible(w, r)) {
            if ((w->room_flags[r] & FORCE_ROOM_MARK) == 0u) {
                w->room_heat[r] = FORCE_HEAT_START;
            }
            w->room_flags[r] = (uint8_t)(w->room_flags[r] |
                FORCE_ROOM_MARK);
            w->last_x[r] = w->unit_x[i];
            w->last_y[r] = w->unit_y[i];
        }
    }
    for (i = 0u; i < w->room_count && i < FORCE_ROOM_MAX; ++i) {
        if ((w->room_flags[i] & FORCE_ROOM_LIVE) != 0u &&
            enemy_in[i] == 0u) {
            w->room_flags[i] = (uint8_t)(w->room_flags[i] &
                (uint8_t)~FORCE_ROOM_MARK);
        }
        if (w->room_heat[i] > 0u) {
            w->room_heat[i]--;
        }
    }
}

static uint8_t snap_cardinal(int dx, int dy)
{
    int adx = (dx < 0) ? -dx : dx;
    int ady = (dy < 0) ? -dy : dy;

    if (adx > ady) {
        return (dx > 0) ? (uint8_t)FORCE_FACE_E : (uint8_t)FORCE_FACE_W;
    }
    if (ady > 0) {
        return (dy > 0) ? (uint8_t)FORCE_FACE_S : (uint8_t)FORCE_FACE_N;
    }
    if (adx > 0) {
        return (dx > 0) ? (uint8_t)FORCE_FACE_E : (uint8_t)FORCE_FACE_W;
    }
    return FORCE_FACE_NONE;
}

static int dest_remains(const force_world *w, uint8_t i)
{
    uint8_t ox, oy;

    if (!unit_dest(w, i, &ox, &oy)) {
        return 0;
    }
    return (w->unit_x[i] != ox || w->unit_y[i] != oy);
}

/* Assigned cover chip, and he is standing on it. Scouts are not chips. */
static int on_assigned_hole(const force_world *w, uint8_t i, uint8_t *grade)
{
    uint8_t c = w->unit_cover[i];
    uint8_t hx, hy;

    if (c >= FORCE_COVER_MAX || !cover_cell(w, c, &hx, &hy)) {
        return 0;
    }
    if (w->unit_x[i] != hx || w->unit_y[i] != hy) {
        return 0;
    }
    if (grade != NULL) {
        *grade = w->cover_grade[c];
    }
    return 1;
}

static uint8_t posture_damage(const force_world *w, uint8_t tgt,
                              uint8_t sh_x, uint8_t sh_y)
{
    uint8_t grade = 0u;
    uint8_t verb;
    uint8_t incoming;
    uint8_t look;
    uint8_t dmg;
    uint8_t dist;

    dmg = FORCE_DMG_OPEN;
    if (on_assigned_hole(w, tgt, &grade)) {
        if (grade == 3u) {
            dmg = FORCE_DMG_COVER3;
        } else if (grade == 1u || grade == 2u) {
            incoming = snap_cardinal((int)sh_x - (int)w->unit_x[tgt],
                                     (int)sh_y - (int)w->unit_y[tgt]);
            look = cover_look(w, w->unit_section[tgt],
                              w->cover_facing[w->unit_cover[tgt]]);
            if (incoming == look && incoming != FORCE_FACE_NONE) {
                dmg = (grade == 2u) ? FORCE_DMG_COVER2 : FORCE_DMG_COVER1;
            }
        }
    } else if (dest_remains(w, tgt)) {
        verb = effective_verb(w, tgt);
        if (verb == FORCE_VERB_MOVE) {
            dmg = FORCE_DMG_SPRINT;
        } else if (verb == FORCE_VERB_ATTACK ||
                   verb == FORCE_VERB_DEFEND ||
                   verb == FORCE_VERB_RETREAT) {
            dmg = FORCE_DMG_WALK;
        }
    }
    dist = chebyshev(sh_x, sh_y, w->unit_x[tgt], w->unit_y[tgt]);
    if (dist >= FORCE_RIFLE_FAR) {
        return 0u;
    }
    if (dist >= FORCE_RIFLE_HALF) {
        dmg = (uint8_t)(dmg >> 1);
    }
    return dmg;
}

static uint8_t other_bank(uint8_t sec)
{
    return (sec >= FORCE_LETTER_MAX) ? 0u : FORCE_LETTER_MAX;
}

typedef struct smear_scan {
    uint8_t tgt;
    uint8_t n_other;
    uint8_t n_rng;
} smear_scan;

static void smear_closest(const force_world *w, uint8_t i, smear_scan *out)
{
    uint8_t best = FORCE_UNIT_NONE;
    uint8_t best_d = 0xFFu;
    uint8_t j;
    uint8_t bank = other_bank(w->unit_section[i]);
    uint8_t bank_hi = (uint8_t)(bank + FORCE_LETTER_MAX);

    out->n_other = 0u;
    out->n_rng = 0u;
    for (j = 0u; j < FORCE_UNIT_MAX; ++j) {
        uint8_t d;
        uint8_t s;
        if (j == i || w->unit_count[j] == 0u || w->unit_hp[j] == 0u) {
            continue;
        }
        s = w->unit_section[j];
        if (s < bank || s >= bank_hi) {
            continue;
        }
        out->n_other = (uint8_t)(out->n_other + 1u);
        d = chebyshev(w->unit_x[i], w->unit_y[i],
                      w->unit_x[j], w->unit_y[j]);
        if (d >= FORCE_RIFLE_FAR) {
            continue;
        }
        out->n_rng = (uint8_t)(out->n_rng + 1u);
        if (best != FORCE_UNIT_NONE && d >= best_d) {
            continue;
        }
        best = j;
        best_d = d;
    }
    out->tgt = best;
}

static uint8_t occupied_grade(const force_world *w, uint8_t i)
{
    uint8_t c = w->unit_cover[i];
    uint8_t hx, hy;

    if (!cover_cell(w, c, &hx, &hy) ||
        w->unit_x[i] != hx || w->unit_y[i] != hy) {
        return 0u;
    }
    if (c >= FORCE_COVER_MAX) {
        return 1u;
    }
    return w->cover_grade[c];
}

static uint8_t find_on_cell(const force_world *w, uint8_t i,
                            uint8_t x, uint8_t y)
{
    uint8_t j;
    uint8_t bank = other_bank(w->unit_section[i]);
    uint8_t bank_hi = (uint8_t)(bank + FORCE_LETTER_MAX);

    for (j = 0u; j < FORCE_UNIT_MAX; ++j) {
        uint8_t s;
        if (j == i || w->unit_count[j] == 0u || w->unit_hp[j] == 0u) {
            continue;
        }
        s = w->unit_section[j];
        if (s < bank || s >= bank_hi) {
            continue;
        }
        if (w->unit_x[j] != x || w->unit_y[j] != y) {
            continue;
        }
        if (chebyshev(w->unit_x[i], w->unit_y[i], x, y) >= FORCE_RIFLE_FAR) {
            return FORCE_UNIT_NONE;
        }
        return j;
    }
    return FORCE_UNIT_NONE;
}

static void apply_hit(force_world *w, uint8_t tgt, uint8_t dmg)
{
    if (dmg == 0u) {
        return;
    }
    if (dmg >= w->unit_hp[tgt]) {
        w->unit_hp[tgt] = 0u;
    } else {
        w->unit_hp[tgt] = (uint8_t)(w->unit_hp[tgt] - dmg);
    }
    w->unit_fx[tgt] = (uint8_t)((w->unit_fx[tgt] & 0xF0u) | FORCE_FX_HURT);
}

static int weapons_free(const force_world *w, uint8_t i)
{
    uint8_t verb = effective_verb(w, i);

    if (verb == FORCE_VERB_MOVE) {
        return !dest_remains(w, i);
    }
    return verb == FORCE_VERB_ATTACK ||
           verb == FORCE_VERB_DEFEND ||
           verb == FORCE_VERB_RETREAT ||
           verb == FORCE_VERB_HALT   ||
           verb == FORCE_VERB_KILL;
}

static void combat_log_unit(const force_world *w, uint8_t i, char *buf,
                            unsigned bufn)
{
    (void)snprintf(buf, bufn, "u%u%c (%u,%u) R%u",
                   (unsigned)i,
                   section_ch(w->unit_section[i]),
                   (unsigned)w->unit_x[i],
                   (unsigned)w->unit_y[i],
                   room_num(w, w->unit_region[i]));
}

/* Same-bank living body in the disk (thrower included). */
static int grenade_friendly_in(const force_world *w, uint8_t i,
                               uint8_t ox, uint8_t oy)
{
    uint8_t j;
    uint8_t bank = other_bank(w->unit_section[i]);
    uint8_t bank_hi = (uint8_t)(bank + FORCE_LETTER_MAX);

    for (j = 0u; j < FORCE_UNIT_MAX; ++j) {
        uint8_t s;
        if (w->unit_count[j] == 0u || w->unit_hp[j] == 0u) {
            continue;
        }
        s = w->unit_section[j];
        if (s >= bank && s < bank_hi) {
            continue;
        }
        if (in_blast(w, ox, oy, w->unit_x[j], w->unit_y[j])) {
            return 1;
        }
    }
    return 0;
}

static uint8_t pick_grenade_tgt(const force_world *w, uint8_t i)
{
    uint8_t best = FORCE_UNIT_NONE;
    uint8_t best_d = 0xFFu;
    uint8_t j;
    uint8_t bank = other_bank(w->unit_section[i]);
    uint8_t bank_hi = (uint8_t)(bank + FORCE_LETTER_MAX);

    for (j = 0u; j < FORCE_UNIT_MAX; ++j) {
        uint8_t d;
        uint8_t s;
        if (j == i || w->unit_count[j] == 0u || w->unit_hp[j] == 0u) {
            continue;
        }
        s = w->unit_section[j];
        if (s < bank || s >= bank_hi) {
            continue;
        }
        d = chebyshev(w->unit_x[i], w->unit_y[i],
                      w->unit_x[j], w->unit_y[j]);
        if (d < FORCE_GRENADE_MIN || d > FORCE_GRENADE_RANGE) {
            continue;
        }
        if (!on_assigned_hole(w, j, NULL)) {
            continue;
        }
        if (grenade_friendly_in(w, i, w->unit_x[j], w->unit_y[j])) {
            continue;
        }
        if (best != FORCE_UNIT_NONE && d >= best_d) {
            continue;
        }
        best = j;
        best_d = d;
    }
    return best;
}

static void apply_grenade_blast(force_world *w, uint8_t i, uint8_t tgt)
{
    uint8_t ox = w->unit_x[tgt];
    uint8_t oy = w->unit_y[tgt];
    uint8_t bank = grenade_bank(w->unit_section[i]);
    uint8_t other = other_bank(w->unit_section[i]);
    uint8_t other_hi = (uint8_t)(other + FORCE_LETTER_MAX);
    uint8_t j;
    uint8_t hits = 0u;
    uint8_t cool = 0u;
    int traced = combat_trace_on();

    for (j = 0u; j < FORCE_UNIT_MAX; ++j) {
        uint8_t s;
        if (w->unit_count[j] == 0u || w->unit_hp[j] == 0u) {
            continue;
        }
        s = w->unit_section[j];
        if (s < other || s >= other_hi) {
            continue;
        }
        if (!in_blast(w, ox, oy, w->unit_x[j], w->unit_y[j])) {
            continue;
        }
        apply_hit(w, j, FORCE_GRENADE_DMG);
        hits++;
    }
    if (w->grenade_rem[bank] > 0u) {
        w->grenade_rem[bank]--;
    }
    if (w->script != NULL) {
        cool = (bank == 0u) ? w->script->player_grenade_wait
                            : w->script->enemy_grenade_wait;
    }
    w->grenade_wait[bank] = cool;
    w->nade_fx_x[bank] = ox;
    w->nade_fx_y[bank] = oy;
    w->nade_fx_ttl[bank] = FORCE_GRENADE_FX_TTL;
    w->unit_fire_wait[i] = FORCE_FIRE_WAIT_RIFLE;
    note_contact(w, w->unit_x[i], w->unit_y[i]);
    note_contact(w, ox, oy);
    if (traced) {
        char me[32];
        char him[32];
        uint8_t dist = chebyshev(w->unit_x[i], w->unit_y[i], ox, oy);
        combat_log_unit(w, i, me, sizeof(me));
        combat_log_unit(w, tgt, him, sizeof(him));
        fprintf(stderr,
                "t=%u nade %s -> %s d%u hits%u dmg%u rem%u hp%u%s\n",
                (unsigned)w->script_clock, me, him,
                (unsigned)dist, (unsigned)hits,
                (unsigned)FORCE_GRENADE_DMG,
                (unsigned)w->grenade_rem[bank],
                (unsigned)w->unit_hp[tgt],
                (w->unit_hp[tgt] == 0u) ? " dead" : "");
    }
}

static int try_grenade(force_world *w, uint8_t i, combat_stats *st)
{
    uint8_t bank = grenade_bank(w->unit_section[i]);
    uint8_t tgt;

    if (w->grenade_rem[bank] == 0u || w->grenade_wait[bank] != 0u) {
        return 0;
    }
    tgt = pick_grenade_tgt(w, i);
    if (tgt == FORCE_UNIT_NONE) {
        return 0;
    }
    apply_grenade_blast(w, i, tgt);
    if (st->nade < 0xFFu) {
        st->nade++;
    }
    return 1;
}

static void unit_shoot(force_world *w, uint8_t i, uint8_t *due,
                       combat_stats *st)
{
    uint8_t sec = w->unit_section[i];
    uint8_t verb = effective_verb(w, i);
    smear_scan smear;
    uint8_t tgt;
    uint8_t dist;
    uint8_t dmg;
    int traced = combat_trace_on();

    smear.tgt = FORCE_UNIT_NONE;
    smear.n_other = 0u;
    smear.n_rng = 0u;

    if (w->unit_kind[i] != FORCE_KIND_INFANTRY) {
        return;
    }
    if (!weapons_free(w, i)) {
        if (st->silent < 0xFFu) {
            st->silent++;
        }
        return;
    }
    if (w->unit_fire_wait[i] > 0u) {
        w->unit_fire_wait[i]--;
        if (w->unit_fire_wait[i] > 0u) {
            return;
        }
    }
    if (try_grenade(w, i, st)) {
        return;
    }
    if (verb == FORCE_VERB_KILL) {
        if (w->unit_over_verb[i] == FORCE_VERB_KILL) {
            tgt = find_on_cell(w, i, w->unit_over_x[i], w->unit_over_y[i]);
            if (tgt == FORCE_UNIT_NONE) {
                smear_closest(w, i, &smear);
                tgt = smear.tgt;
            }
        } else {
            due[sec]++;
            if ((due[sec] & 3u) != 0u) {
                uint8_t k = find_on_cell(w, i, w->section_order_x[sec],
                                         w->section_order_y[sec]);
                if (k != FORCE_UNIT_NONE) {
                    tgt = k;
                } else {
                    smear_closest(w, i, &smear);
                    tgt = smear.tgt;
                }
            } else {
                smear_closest(w, i, &smear);
                tgt = smear.tgt;
            }
        }
    } else {
        smear_closest(w, i, &smear);
        tgt = smear.tgt;
    }
    if (tgt == FORCE_UNIT_NONE) {
        if (st->none < 0xFFu) {
            st->none++;
        }
        if (traced) {
            char me[32];
            combat_log_unit(w, i, me, sizeof(me));
            fprintf(stderr,
                    "t=%u shoot %s v%u -> none other%u rng%u\n",
                    (unsigned)w->script_clock, me, (unsigned)verb,
                    (unsigned)smear.n_other, (unsigned)smear.n_rng);
        }
        return;
    }
    dist = chebyshev(w->unit_x[i], w->unit_y[i],
                     w->unit_x[tgt], w->unit_y[tgt]);
    dmg = posture_damage(w, tgt, w->unit_x[i], w->unit_y[i]);
    if (dmg == 0u) {
        if (st->dmg0 < 0xFFu) {
            st->dmg0++;
        }
        if (traced) {
            char me[32];
            char him[32];
            combat_log_unit(w, i, me, sizeof(me));
            combat_log_unit(w, tgt, him, sizeof(him));
            fprintf(stderr,
                    "t=%u shoot %s v%u -> %s d%u g%u dmg0 hp%u\n",
                    (unsigned)w->script_clock, me, (unsigned)verb, him,
                    (unsigned)dist, (unsigned)occupied_grade(w, tgt),
                    (unsigned)w->unit_hp[tgt]);
        }
        return;
    }
    apply_hit(w, tgt, dmg);
    if (st->fire < 0xFFu) {
        st->fire++;
    }
    if (traced) {
        char me[32];
        char him[32];
        combat_log_unit(w, i, me, sizeof(me));
        combat_log_unit(w, tgt, him, sizeof(him));
        fprintf(stderr,
                "t=%u shoot %s v%u -> %s d%u g%u dmg%u hp%u%s\n",
                (unsigned)w->script_clock, me, (unsigned)verb, him,
                (unsigned)dist, (unsigned)occupied_grade(w, tgt),
                (unsigned)dmg, (unsigned)w->unit_hp[tgt],
                (w->unit_hp[tgt] == 0u) ? " dead" : "");
    }
    w->unit_fire_wait[i] = FORCE_FIRE_WAIT_RIFLE;
    if (w->shot_this_tick < 0xFFu) {
        w->shot_this_tick++;
    }
    note_contact(w, w->unit_x[i], w->unit_y[i]);
    note_contact(w, w->unit_x[tgt], w->unit_y[tgt]);
}

void force_section_relead(force_world *world, uint8_t who)
{
    uint8_t lead;
    uint8_t dest_r;
    uint8_t i;
    uint8_t fallback = FORCE_UNIT_NONE;

    if (who >= FORCE_SECTION_MAX) {
        return;
    }
    lead = world->section_lead[who];
    if (lead < FORCE_UNIT_MAX &&
        world->unit_count[lead] != 0u &&
        world->unit_section[lead] == who) {
        world->section_last_x[who] = world->unit_x[lead];
        world->section_last_y[who] = world->unit_y[lead];
        return;
    }
    dest_r = unit_region_at(world,
                            world->section_order_x[who],
                            world->section_order_y[who]);
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        if (world->unit_count[i] == 0u ||
            world->unit_section[i] != who) {
            continue;
        }
        if (dest_r != FORCE_UNIT_NONE &&
            world->unit_region[i] == dest_r) {
            world->section_lead[who] = i;
            world->section_last_x[who] = world->unit_x[i];
            world->section_last_y[who] = world->unit_y[i];
            return;
        }
        if (fallback == FORCE_UNIT_NONE) {
            fallback = i;
        }
    }
    if (fallback != FORCE_UNIT_NONE) {
        world->section_lead[who] = fallback;
        world->section_last_x[who] = world->unit_x[fallback];
        world->section_last_y[who] = world->unit_y[fallback];
        return;
    }
    world->section_lead[who] = FORCE_UNIT_NONE;
}

static int death_reassign(const force_world *w, uint8_t who)
{
    uint8_t verb;

    if (who >= FORCE_SECTION_MAX) {
        return 0;
    }
    verb = w->section_order_verb[who];
    if (who < FORCE_LETTER_MAX) {
        return verb == FORCE_VERB_ATTACK ||
               verb == FORCE_VERB_DEFEND ||
               verb == FORCE_VERB_RETREAT ||
               verb == FORCE_VERB_HALT   ||
               verb == FORCE_VERB_KILL;
    }
    if (verb == FORCE_VERB_DEFEND || verb == FORCE_VERB_RETREAT) {
        return 1;
    }
    if ((verb == FORCE_VERB_ATTACK || verb == FORCE_VERB_HALT) &&
        (w->section_flags[who] & FORCE_SECTION_FLAG_CONTACT) != 0u) {
        return 1;
    }
    return 0;
}

static int force_broken(uint8_t force, uint8_t snap, uint8_t now)
{
    if (force >= 10u) {
        return 0;
    }
    if (now >= snap) {
        return 0;
    }
    if (force <= 3u) {
        return 1;
    }
    if (force <= 6u) {
        return now <= (uint8_t)(snap >> 1);
    }
    return now <= 1u;
}

static void apply_deaths(force_world *w)
{
    uint8_t i;
    uint16_t letters = 0u;

    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        uint8_t s;
        if (w->unit_count[i] == 0u) {
            continue;
        }
        if (w->unit_hp[i] != 0u) {
            continue;
        }
        s = w->unit_section[i];
        w->unit_count[i] = 0u;
        w->unit_cover[i] = FORCE_UNIT_NONE;
        w->unit_over_verb[i] = FORCE_VERB_NONE;
        w->unit_fx[i]    = 0u;
        if (s < FORCE_SECTION_MAX) {
            letters = (uint16_t)(letters | (uint16_t)(1u << s));
        }
    }
    for (i = 0u; i < FORCE_SECTION_MAX; ++i) {
        if ((letters & (uint16_t)(1u << i)) == 0u) {
            continue;
        }
        force_section_relead(w, i);
        if (death_reassign(w, i)) {
            w->section_flags[i] = (uint8_t)(
                (w->section_flags[i]
                    & (uint8_t)~FORCE_SECTION_FLAG_COVER_RELEASE)
                | FORCE_SECTION_FLAG_COVER_ASSIGN);
        }
    }
    force_section_recount(w);
    for (i = 0u; i < FORCE_SECTION_MAX; ++i) {
        if ((letters & (uint16_t)(1u << i)) == 0u) {
            continue;
        }
        if (w->spawn_job_rem > 0u && w->spawn_job_letter == i) {
            continue;   /* partial group; issued n is TOE, not now */
        }
        if (force_broken(w->section_order_force[i],
                         w->section_order_str[i],
                         w->section_strength[i])) {
            w->section_order_verb[i] = FORCE_VERB_HALT;
            w->section_flags[i] = (uint8_t)(
                w->section_flags[i] | FORCE_SECTION_FLAG_BREAKING);
        }
    }
}

/* First step is slot % FORCE_MOVE_WAIT_DEFAULT ticks out.
   A stored 0 is due now, and so is a stored 1: the countdown thinks
   on the tick it reaches 0. Phases 1..6 are stored as 2..7. A step
   reloads 7 and keeps that phase. Sprint reloads 4 and drifts. */
static uint8_t spawn_move_wait(uint8_t slot)
{
    uint8_t phase = (uint8_t)(slot % FORCE_MOVE_WAIT_DEFAULT);

    if (phase == 0u) {
        return 0u;
    }
    return (uint8_t)(phase + 1u);
}

uint8_t force_unit_spawn(force_world *world,
                         uint8_t x, uint8_t y,
                         uint8_t section, uint8_t kind,
                         uint8_t count, uint8_t glyph)
{
    uint8_t i;
    uint8_t slot;

    if (count == 0u || section >= FORCE_SECTION_MAX) {
        return FORCE_UNIT_NONE;
    }
    slot = FORCE_UNIT_NONE;
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        if (world->unit_count[i] == 0u) {
            slot = i;
            break;
        }
    }
    if (slot == FORCE_UNIT_NONE) {
        return FORCE_UNIT_NONE;
    }

    world->unit_x[slot] = x;
    world->unit_y[slot] = y;
    world->unit_section[slot] = section;
    world->unit_count[slot] = count;
    world->unit_kind[slot] = kind;
    world->unit_glyph[slot] = glyph;
    world->unit_region[slot] = unit_region_at(world, x, y);
    world->unit_cover[slot] = FORCE_UNIT_NONE;
    world->unit_over_verb[slot] = FORCE_VERB_NONE;
    world->unit_over_x[slot] = 0u;
    world->unit_over_y[slot] = 0u;
    world->unit_tgt_x[slot] = x;
    world->unit_tgt_y[slot] = y;
    world->unit_step_sx[slot] = 0u;
    world->unit_step_sy[slot] = 0u;
    world->unit_step_ax[slot] = 0u;
    world->unit_step_ay[slot] = 0u;
    world->unit_step_err[slot] = 0u;
    world->unit_step_run[slot] = 0u;
    world->unit_move_wait[slot] = spawn_move_wait(slot);
    world->unit_hp[slot] = FORCE_HP_INFANTRY;
    world->unit_fire_wait[slot] = 0u;
    world->unit_fx[slot] = 0u;

    if (world->section_lead[section] == FORCE_UNIT_NONE) {
        world->section_lead[section] = slot;
        world->section_last_x[section] = x;
        world->section_last_y[section] = y;
    }
    return slot;
}

void force_section_recount(force_world *world)
{
    uint8_t i;

    for (i = 0u; i < FORCE_SECTION_MAX; ++i) {
        world->section_strength[i] = 0u;
    }
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        uint8_t c = world->unit_count[i];
        uint8_t s;
        if (c == 0u) {
            continue;
        }
        s = world->unit_section[i];
        if (s < FORCE_SECTION_MAX) {
            world->section_strength[s] =
                (uint8_t)(world->section_strength[s] + c);
        }
    }
}

void force_section_issue(force_world *w, uint8_t who,
                         uint8_t verb, uint8_t x, uint8_t y,
                         uint8_t force)
{
    uint8_t f;
    uint8_t i;

    if (who >= FORCE_SECTION_MAX) {
        return;
    }
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        if (w->unit_section[i] == who) {
            w->unit_over_verb[i] = FORCE_VERB_NONE;
        }
    }
    w->section_order_verb[who]  = verb;
    w->section_order_x[who]     = x;
    w->section_order_y[who]     = y;
    w->section_order_force[who] = force;
    w->section_order_str[who]   = w->section_strength[who];
    f = w->section_flags[who];
    f = (uint8_t)(f & (uint8_t)~(FORCE_SECTION_FLAG_NOPATH |
                                 FORCE_SECTION_FLAG_BREAKING |
                                 FORCE_SECTION_FLAG_CONTACT));
    if (verb_takes_cover(verb)) {
        f = (uint8_t)(f & (uint8_t)~FORCE_SECTION_FLAG_COVER_RELEASE);
        f = (uint8_t)(f | FORCE_SECTION_FLAG_COVER_ASSIGN);
    } else if (verb == FORCE_VERB_MOVE) {
        f = (uint8_t)(f & (uint8_t)~FORCE_SECTION_FLAG_COVER_ASSIGN);
        f = (uint8_t)(f | FORCE_SECTION_FLAG_COVER_RELEASE);
    }
    w->section_flags[who] = f;
}

int force_section_peel(force_world *w,
                       uint8_t src, uint8_t dst,
                       uint8_t first, uint8_t n)
{
    uint8_t picked[FORCE_UNIT_MAX];
    uint8_t n_picked = 0u;
    uint8_t i;
    uint8_t k;
    uint8_t dest_was_empty;

    if (src >= FORCE_LETTER_MAX || dst >= FORCE_LETTER_MAX ||
        src == dst || n == 0u) {
        return 0;
    }
    if (w->section_order_verb[src] == FORCE_VERB_KILL) {
        return 0;
    }
    dest_was_empty = (w->section_lead[dst] == FORCE_UNIT_NONE) ? 1u : 0u;
    if (first < FORCE_UNIT_MAX &&
        w->unit_count[first] != 0u &&
        w->unit_section[first] == src &&
        w->unit_kind[first] != FORCE_KIND_EMPLACEMENT) {
        picked[n_picked] = first;
        n_picked = 1u;
    }
    for (i = 0u; i < FORCE_UNIT_MAX && n_picked < n; ++i) {
        if (w->unit_count[i] == 0u || w->unit_section[i] != src) {
            continue;
        }
        if (w->unit_kind[i] == FORCE_KIND_EMPLACEMENT) {
            continue;
        }
        for (k = 0u; k < n_picked; ++k) {
            if (picked[k] == i) {
                break;
            }
        }
        if (k < n_picked) {
            continue;
        }
        picked[n_picked] = i;
        n_picked = (uint8_t)(n_picked + 1u);
    }
    if (n_picked == 0u) {
        return 0;
    }
    for (k = 0u; k < n_picked; ++k) {
        i = picked[k];
        w->unit_section[i] = dst;
        w->unit_cover[i] = FORCE_UNIT_NONE;
        w->unit_over_verb[i] = FORCE_VERB_NONE;
    }
    force_section_relead(w, src);
    force_section_recount(w);
    if (dest_was_empty) {
        w->section_lead[dst] = picked[0];
        w->section_last_x[dst] = w->unit_x[picked[0]];
        w->section_last_y[dst] = w->unit_y[picked[0]];
    } else {
        force_section_relead(w, dst);
    }
    force_section_recount(w);
    return 1;
}

int force_section_join(force_world *w, uint8_t src, uint8_t dst)
{
    uint8_t i;
    uint8_t src_lead;

    if (src >= FORCE_LETTER_MAX || dst >= FORCE_LETTER_MAX || src == dst) {
        return 0;
    }
    if (w->section_strength[src] == 0u) {
        return 0;
    }
    if (w->section_order_verb[dst] == FORCE_VERB_NONE &&
        w->section_strength[dst] == 0u) {
        return 0;
    }
    src_lead = w->section_lead[src];
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        if (w->unit_count[i] == 0u || w->unit_section[i] != src) {
            continue;
        }
        w->unit_section[i] = dst;
        w->unit_over_verb[i] = FORCE_VERB_NONE;
    }
    if (w->section_lead[dst] == FORCE_UNIT_NONE &&
        src_lead < FORCE_UNIT_MAX &&
        w->unit_section[src_lead] == dst) {
        w->section_lead[dst] = src_lead;
        w->section_last_x[dst] = w->unit_x[src_lead];
        w->section_last_y[dst] = w->unit_y[src_lead];
    }
    w->section_lead[src] = FORCE_UNIT_NONE;
    force_section_recount(w);
    if (verb_takes_cover(w->section_order_verb[dst])) {
        w->section_flags[dst] = (uint8_t)(
            (w->section_flags[dst]
                & (uint8_t)~FORCE_SECTION_FLAG_COVER_RELEASE)
            | FORCE_SECTION_FLAG_COVER_ASSIGN);
    }
    return 1;
}

int force_unit_nudge(force_world *w, uint8_t i,
                     uint8_t verb, uint8_t x, uint8_t y)
{
    uint8_t enc;
    uint8_t hole;
    uint8_t dest_r;
    uint8_t hx, hy;

    if (i >= FORCE_UNIT_MAX || w->unit_count[i] == 0u ||
        w->unit_hp[i] == 0u || w->unit_section[i] >= FORCE_LETTER_MAX) {
        return 0;
    }
    if (verb == FORCE_VERB_MOVE) {
        w->unit_over_verb[i] = FORCE_VERB_MOVE;
        w->unit_over_x[i] = x;
        w->unit_over_y[i] = y;
        w->unit_cover[i] = FORCE_UNIT_NONE;
        return 1;
    }
    if (verb == FORCE_VERB_HALT) {
        w->unit_over_verb[i] = FORCE_VERB_HALT;
        w->unit_over_x[i] = w->unit_x[i];
        w->unit_over_y[i] = w->unit_y[i];
        return 1;
    }
    if (verb == FORCE_VERB_KILL) {
        w->unit_over_verb[i] = FORCE_VERB_KILL;
        w->unit_over_x[i] = x;
        w->unit_over_y[i] = y;
        return 1;
    }
    if (!verb_takes_cover(verb)) {
        return 0;
    }
    enc = chip_at(w, x, y);
    if (enc != FORCE_UNIT_NONE) {
        if (cover_taken(w, enc) && w->unit_cover[i] != enc) {
            return 0;
        }
        w->unit_over_verb[i] = verb;
        w->unit_cover[i] = enc;
        if (cover_cell(w, enc, &hx, &hy)) {
            w->unit_over_x[i] = hx;
            w->unit_over_y[i] = hy;
        } else {
            w->unit_over_x[i] = x;
            w->unit_over_y[i] = y;
        }
        return 1;
    }
    dest_r = unit_region_at(w, x, y);
    w->unit_cover[i] = FORCE_UNIT_NONE;
    hole = FORCE_UNIT_NONE;
    if (dest_r != FORCE_UNIT_NONE && dest_r < w->room_count) {
        hole = pick_best(w, i, dest_r, section_front(w, w->unit_section[i]));
    }
    w->unit_over_verb[i] = verb;
    if (hole != FORCE_UNIT_NONE && cover_cell(w, hole, &hx, &hy)) {
        w->unit_cover[i] = hole;
        w->unit_over_x[i] = hx;
        w->unit_over_y[i] = hy;
    } else {
        w->unit_cover[i] = FORCE_UNIT_NONE;
        w->unit_over_x[i] = x;
        w->unit_over_y[i] = y;
    }
    return 1;
}

static void fit_play(uint16_t map_w, uint16_t map_h,
                     uint16_t mx, uint16_t my, uint16_t mw, uint16_t mh,
                     uint8_t *x, uint8_t *y, uint8_t *w, uint8_t *h)
{
    unsigned lim_w = map_w;
    unsigned lim_h = map_h;
    unsigned px, py, pw, ph;

    if (lim_w > 255u) {
        lim_w = 255u;
    }
    if (lim_h > 255u) {
        lim_h = 255u;
    }
    if (lim_w == 0u) {
        lim_w = 1u;
    }
    if (lim_h == 0u) {
        lim_h = 1u;
    }
    px = mx;
    py = my;
    if (px >= lim_w) {
        px = lim_w - 1u;
    }
    if (py >= lim_h) {
        py = lim_h - 1u;
    }
    pw = (mw == 0u) ? 1u : mw;
    ph = (mh == 0u) ? 1u : mh;
    if (px + pw > lim_w) {
        pw = lim_w - px;
    }
    if (py + ph > lim_h) {
        ph = lim_h - py;
    }
    *x = (uint8_t)px;
    *y = (uint8_t)py;
    *w = (uint8_t)pw;
    *h = (uint8_t)ph;
}

void force_world_clamp_play(const force_world *world, uint8_t *x, uint8_t *y)
{
    unsigned x1;
    unsigned y1;

    if (world->play_w == 0u || world->play_h == 0u) {
        return;
    }
    x1 = (unsigned)world->play_x + (unsigned)world->play_w - 1u;
    y1 = (unsigned)world->play_y + (unsigned)world->play_h - 1u;
    if (*x < world->play_x) {
        *x = world->play_x;
    }
    if (*y < world->play_y) {
        *y = world->play_y;
    }
    if ((unsigned)*x > x1) {
        *x = (uint8_t)x1;
    }
    if ((unsigned)*y > y1) {
        *y = (uint8_t)y1;
    }
}

void force_world_load(force_world *world, const force_mission *mission)
{
    const force_map *map = mission->map;
    uint8_t width;
    uint8_t height;
    uint8_t i;
    uint16_t y;
    uint16_t cells;
    unsigned view_w;
    unsigned view_h;

    world->width = (uint8_t)map->width;
    world->height = (uint8_t)map->height;
    fit_play(map->width, map->height,
             mission->x, mission->y, mission->w, mission->h,
             &world->play_x, &world->play_y, &world->play_w, &world->play_h);
    view_w = world->play_w;
    view_h = world->play_h;
    if (view_w > (unsigned)FORCE_COLS) {
        view_w = (unsigned)FORCE_COLS;
    }
    if (view_h > (unsigned)FORCE_FIELD_ROWS) {
        view_h = (unsigned)FORCE_FIELD_ROWS;
    }
    if (view_w == 0u) {
        view_w = 1u;
    }
    if (view_h == 0u) {
        view_h = 1u;
    }
    world->win_w = (uint8_t)view_w;
    world->win_h = (uint8_t)view_h;
    {
        /* cam is the opening top-left. Pull it so the view stays in the rect. */
        unsigned max_x = world->play_x;
        unsigned max_y = world->play_y;
        unsigned cam_x = mission->cam_x;
        unsigned cam_y = mission->cam_y;

        if (world->play_w > world->win_w) {
            max_x += (unsigned)(world->play_w - world->win_w);
        }
        if (world->play_h > world->win_h) {
            max_y += (unsigned)(world->play_h - world->win_h);
        }
        if (cam_x < world->play_x) {
            cam_x = world->play_x;
        }
        if (cam_y < world->play_y) {
            cam_y = world->play_y;
        }
        if (cam_x > max_x) {
            cam_x = max_x;
        }
        if (cam_y > max_y) {
            cam_y = max_y;
        }
        world->win_x = (uint8_t)cam_x;
        world->win_y = (uint8_t)cam_y;
    }

    width = world->width;
    height = world->height;

    for (y = 0u; y < (uint16_t)height; ++y) {
        world->row_off[y] = y * (uint16_t)width;
    }
    for (y = (uint16_t)height; y < (uint16_t)FORCE_MAP_H_MAX; ++y) {
        world->row_off[y] = 0u;
    }

    cells = (uint16_t)width * (uint16_t)height;
    force_copy_u8(world->tiles, map->tiles, cells);
    if (cells < (uint16_t)FORCE_MAP_CELLS_MAX) {
        zero_u8(world->tiles + cells,
                (uint16_t)FORCE_MAP_CELLS_MAX - cells);
    }
    force_copy_u8(world->color, map->color, cells);
    if (cells < (uint16_t)FORCE_MAP_CELLS_MAX) {
        zero_u8(world->color + cells,
                (uint16_t)FORCE_MAP_CELLS_MAX - cells);
    }

    world->room_count = map->room_count;
    copy_column(world->room_x0, map->room_x0, map->room_count, FORCE_ROOM_MAX);
    copy_column(world->room_y0, map->room_y0, map->room_count, FORCE_ROOM_MAX);
    copy_column(world->room_w, map->room_w, map->room_count, FORCE_ROOM_MAX);
    copy_column(world->room_h, map->room_h, map->room_count, FORCE_ROOM_MAX);
    copy_column(world->room_colour, map->room_colour, map->room_count,
                FORCE_ROOM_MAX);
    copy_column(world->room_cover_base, map->room_cover_base, map->room_count,
                FORCE_ROOM_MAX);
    copy_column(world->room_cover_count, map->room_cover_count, map->room_count,
                FORCE_ROOM_MAX);
    copy_column(world->room_scout_base, map->room_scout_base, map->room_count,
                FORCE_ROOM_MAX);
    copy_column(world->room_scout_count, map->room_scout_count, map->room_count,
                FORCE_ROOM_MAX);
    copy_column(world->room_axis, map->room_axis, map->room_count,
                FORCE_ROOM_MAX);
    copy_column(world->room_cover_lo, map->room_cover_lo, map->room_count,
                FORCE_ROOM_MAX);
    copy_column(world->room_cover_none, map->room_cover_none, map->room_count,
                FORCE_ROOM_MAX);
    copy_column(world->room_cover_hi, map->room_cover_hi, map->room_count,
                FORCE_ROOM_MAX);
    zero_u8(world->room_flags, FORCE_ROOM_MAX);
    zero_u8(world->room_heat, FORCE_ROOM_MAX);
    zero_u8(world->last_x, FORCE_ROOM_MAX);
    zero_u8(world->last_y, FORCE_ROOM_MAX);
    for (i = 0u; i < FORCE_ROOM_MAX; ++i) {
        uint8_t axis;
        uint8_t mask;

        if (i >= world->room_count) {
            world->room_approach[i] = 0u;
            continue;
        }
        axis = world->room_axis[i];
        if (axis == FORCE_AXIS_EW) {
            mask = (uint8_t)FORCE_APPROACH_W;
        } else {
            mask = (uint8_t)FORCE_APPROACH_S;
        }
        world->room_approach[i] = mask;
    }

    world->cover_count = map->cover_count;
    copy_column(world->cover_x, map->cover_x, map->cover_count, FORCE_COVER_MAX);
    copy_column(world->cover_y, map->cover_y, map->cover_count, FORCE_COVER_MAX);
    copy_column(world->cover_grade, map->cover_grade, map->cover_count,
                FORCE_COVER_MAX);
    copy_column(world->cover_facing, map->cover_facing, map->cover_count,
                FORCE_COVER_MAX);

    world->portal_count = map->portal_count;
    copy_column(world->portal_x, map->portal_x, map->portal_count,
                FORCE_PORTAL_MAX);
    copy_column(world->portal_y, map->portal_y, map->portal_count,
                FORCE_PORTAL_MAX);
    infer_portals(world);
    bake_next_hop(world);

    world->scout_count = map->scout_count;
    copy_column(world->scout_x, map->scout_x, map->scout_count, FORCE_SCOUT_MAX);
    copy_column(world->scout_y, map->scout_y, map->scout_count, FORCE_SCOUT_MAX);
    copy_column(world->scout_facing, map->scout_facing, map->scout_count,
                FORCE_SCOUT_MAX);

    world->objective_count = map->objective_count;
    copy_column(world->objective_x, map->objective_x, map->objective_count,
                FORCE_OBJECTIVE_MAX);
    copy_column(world->objective_y, map->objective_y, map->objective_count,
                FORCE_OBJECTIVE_MAX);

    world->mine_count = map->mine_count;
    copy_column(world->mine_x, map->mine_x, map->mine_count, FORCE_MINE_MAX);
    copy_column(world->mine_y, map->mine_y, map->mine_count, FORCE_MINE_MAX);

    zero_u8(world->unit_x, FORCE_UNIT_MAX);
    zero_u8(world->unit_y, FORCE_UNIT_MAX);
    zero_u8(world->unit_section, FORCE_UNIT_MAX);
    zero_u8(world->unit_count, FORCE_UNIT_MAX);
    zero_u8(world->unit_kind, FORCE_UNIT_MAX);
    zero_u8(world->unit_glyph, FORCE_UNIT_MAX);
    zero_u8(world->unit_region, FORCE_UNIT_MAX);
    zero_u8(world->unit_cover, FORCE_UNIT_MAX);
    zero_u8(world->unit_over_verb, FORCE_UNIT_MAX);
    zero_u8(world->unit_over_x, FORCE_UNIT_MAX);
    zero_u8(world->unit_over_y, FORCE_UNIT_MAX);
    zero_u8(world->unit_tgt_x, FORCE_UNIT_MAX);
    zero_u8(world->unit_tgt_y, FORCE_UNIT_MAX);
    zero_u8(world->unit_step_sx, FORCE_UNIT_MAX);
    zero_u8(world->unit_step_sy, FORCE_UNIT_MAX);
    zero_u8(world->unit_step_ax, FORCE_UNIT_MAX);
    zero_u8(world->unit_step_ay, FORCE_UNIT_MAX);
    zero_u8(world->unit_step_err, FORCE_UNIT_MAX);
    zero_u8(world->unit_step_run, FORCE_UNIT_MAX);
    zero_u8(world->unit_move_wait, FORCE_UNIT_MAX);
    zero_u8(world->unit_hp, FORCE_UNIT_MAX);
    zero_u8(world->unit_fire_wait, FORCE_UNIT_MAX);
    zero_u8(world->unit_fx, FORCE_UNIT_MAX);
    zero_u8(world->section_order_str, FORCE_SECTION_MAX);
    world->shot_this_tick = 0u;
    world->path_fail_who = FORCE_UNIT_NONE;
    zero_u8(world->grenade_rem, FORCE_GRENADE_BANK);
    zero_u8(world->grenade_wait, FORCE_GRENADE_BANK);
    zero_u8(world->nade_fx_x, FORCE_GRENADE_BANK);
    zero_u8(world->nade_fx_y, FORCE_GRENADE_BANK);
    zero_u8(world->nade_fx_ttl, FORCE_GRENADE_BANK);

    for (i = 0u; i < FORCE_SECTION_MAX; ++i) {
        world->section_lead[i] = FORCE_UNIT_NONE;
        world->section_last_x[i] = 0u;
        world->section_last_y[i] = 0u;
        world->section_strength[i] = 0u;
        world->section_flags[i] = 0u;
        world->section_order_verb[i] = 0u;
        world->section_order_x[i] = 0u;
        world->section_order_y[i] = 0u;
        world->section_order_force[i] = 0u;
        world->section_order_str[i] = 0u;
    }

    if (map->spawn_count > 0u) {
        for (i = 0u; i < map->spawn_count; ++i) {
            uint8_t tile = map->spawn_tile[i];
            uint8_t cls = force_tile_class[tile];
            uint8_t section;

            if (cls == FORCE_CLASS_GOODGUYS) {
                section = 0u;
            } else if (cls == FORCE_CLASS_ENEMIES) {
                if (mission->script != NULL) {
                    continue;
                }
                section = FORCE_LETTER_MAX;
            } else {
                continue;
            }
            force_unit_spawn(world,
                             map->spawn_x[i], map->spawn_y[i],
                             section, FORCE_KIND_INFANTRY, 1u, tile);
        }
    }

    force_section_recount(world);

    world->script = mission->script;
    world->script_pc = 0u;
    world->script_waiting = 0u;
    world->script_wait_pred0 = 0u;
    world->script_wait_pred1 = 0u;
    world->script_wait_beat = 0u;
    world->spawn_room = 0u;
    world->spawn_job_rem = 0u;
    world->spawn_job_letter = 0u;
    world->spawn_job_room = 0u;
    world->spawn_job_batch = 0u;
    world->spawn_job_period = 0u;
    world->spawn_job_wait = 0u;
    world->script_fired = 0u;
    world->script_clock = 0u;
    world->script_outcome = FORCE_SCRIPT_PLAYING;
    if (world->script != NULL) {
        world->spawn_room = world->script->start_spawn_room;
        world->script_pc = world->script->beat_pc[world->script->start_beat];
        world->grenade_rem[0] = world->script->player_grenades;
        world->grenade_rem[1] = world->script->enemy_grenades;
        if (script_trace_on()) {
            fprintf(stderr, "script t=0 beat %s\n",
                    script_beat_name(world->script,
                                     world->script->start_beat));
        }
    }
    intel_pulse(world);
}

static void consume_cover_jobs(force_world *world)
{
    uint8_t s;

    for (s = 0u; s < FORCE_SECTION_MAX; ++s) {
        uint8_t f = world->section_flags[s];
        if ((f & FORCE_SECTION_FLAG_COVER_ASSIGN) != 0u) {
            world->section_flags[s] = (uint8_t)(f &
                (uint8_t)~(FORCE_SECTION_FLAG_COVER_ASSIGN |
                           FORCE_SECTION_FLAG_COVER_RELEASE));
            force_cover_assign(world, s);
        } else if ((f & FORCE_SECTION_FLAG_COVER_RELEASE) != 0u) {
            world->section_flags[s] = (uint8_t)(f &
                (uint8_t)~FORCE_SECTION_FLAG_COVER_RELEASE);
            force_cover_release(world, s);
        }
    }
}

static uint8_t bank_strength(const force_world *w, uint8_t who)
{
    uint8_t i, s = 0u;

    if (who == FORCE_SCRIPT_WHO_PLAYER) {
        for (i = 0u; i < FORCE_LETTER_MAX; ++i) {
            s = (uint8_t)(s + w->section_strength[i]);
        }
        return s;
    }
    if (who < FORCE_SECTION_MAX) {
        return w->section_strength[who];
    }
    return 0u;
}

static uint8_t count_in_room(const force_world *w, uint8_t who, uint8_t room)
{
    uint8_t i, n = 0u;

    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        uint8_t s;
        if (w->unit_count[i] == 0u) {
            continue;
        }
        if (w->unit_region[i] != room) {
            continue;
        }
        s = w->unit_section[i];
        if (who == FORCE_SCRIPT_WHO_PLAYER) {
            if (s < FORCE_LETTER_MAX) {
                n++;
            }
        } else if (s == who) {
            n++;
        }
    }
    return n;
}

static uint8_t pred_true(const force_world *w, const force_script *sc,
                         uint8_t pi)
{
    uint8_t kind, who, a, b, i;

    if (pi >= sc->pred_count) {
        return 0u;
    }
    kind = sc->pred_kind[pi];
    who  = sc->pred_who[pi];
    a    = sc->pred_a[pi];
    b    = sc->pred_b[pi];
    switch (kind) {
    case FORCE_PRED_NONE:
        return 1u;
    case FORCE_PRED_STR_EQ:
        return (uint8_t)(bank_strength(w, who) == a);
    case FORCE_PRED_STR_LE:
        return (uint8_t)(bank_strength(w, who) <= a);
    case FORCE_PRED_STR_GE:
        return (uint8_t)(bank_strength(w, who) >= a);
    case FORCE_PRED_IN_GE:
        return (uint8_t)(count_in_room(w, who, a) >= b);
    case FORCE_PRED_REACHED:
        return (uint8_t)(count_in_room(w, who, a) >= 1u);
    case FORCE_PRED_AT_CELL:
        for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
            uint8_t s;
            if (w->unit_count[i] == 0u) {
                continue;
            }
            if (w->unit_x[i] != a || w->unit_y[i] != b) {
                continue;
            }
            s = w->unit_section[i];
            if (who == FORCE_SCRIPT_WHO_PLAYER) {
                if (s < FORCE_LETTER_MAX) {
                    return 1u;
                }
            } else if (s == who) {
                return 1u;
            }
        }
        return 0u;
    case FORCE_PRED_CLOCK_GE: {
        uint16_t n = (uint16_t)((uint16_t)a | ((uint16_t)b << 8));
        return (uint8_t)(w->script_clock >= n);
    }
    case FORCE_PRED_REL_GE: {
        uint8_t pc = 0u;
        uint8_t ec = 0u;
        for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
            uint8_t s;
            if (w->unit_count[i] == 0u) {
                continue;
            }
            if (w->unit_region[i] != a) {
                continue;
            }
            s = w->unit_section[i];
            if (s < FORCE_LETTER_MAX) {
                pc++;
            } else {
                ec++;
            }
        }
        return (uint8_t)(pc >= ec);
    }
    case FORCE_PRED_JOB_IDLE:
        return (uint8_t)(w->spawn_job_rem == 0u);
    default:
        return 0u;
    }
}

static int pred_pair(const force_world *w, const force_script *sc,
                     uint8_t p0, uint8_t p1)
{
    if (pred_true(w, sc, p0) == 0u) {
        return 0;
    }
    if (p1 == 0xFFu) {
        return 1;
    }
    return pred_true(w, sc, p1) != 0u;
}

static void script_set_outcome(force_world *w, uint8_t outcome)
{
    w->script_outcome = outcome;
    if (script_trace_on()) {
        fprintf(stderr, "script t=%u %s pc %u rem %u\n",
                (unsigned)w->script_clock,
                (outcome == FORCE_SCRIPT_WIN) ? "win" :
                (outcome == FORCE_SCRIPT_LOSE) ? "lose" : "outcome",
                (unsigned)w->script_pc,
                (unsigned)w->spawn_job_rem);
    }
}

static int room_canonical_cell(const force_world *w, uint8_t r,
                               uint8_t *ox, uint8_t *oy)
{
    uint8_t x0, y0, ww, hh, axis, mask, i;
    int x, y;

    if (r >= w->room_count) {
        return 0;
    }
    if (w->room_cover_count[r] > 0u) {
        uint8_t c = w->room_cover_base[r];
        *ox = w->cover_x[c];
        *oy = w->cover_y[c];
        return 1;
    }
    x0 = w->room_x0[r];
    y0 = w->room_y0[r];
    ww = w->room_w[r];
    hh = w->room_h[r];
    x = (int)x0 + (int)(ww / 2u);
    y = (int)y0 + (int)(hh / 2u);
    if (tile_open(w, x, y)) {
        *ox = (uint8_t)x;
        *oy = (uint8_t)y;
        return 1;
    }
    axis = w->room_axis[r];
    mask = w->room_approach[r];
    if (axis == FORCE_AXIS_NS) {
        if ((mask & FORCE_APPROACH_S) != 0u && hh > 0u) {
            y = (int)y0 + (int)hh - 1;
        } else {
            y = (int)y0;
        }
        for (i = 0u; i < ww && i < 20u; ++i) {
            x = (int)x0 + (int)i;
            if (tile_open(w, x, y)) {
                *ox = (uint8_t)x;
                *oy = (uint8_t)y;
                return 1;
            }
        }
    } else {
        if ((mask & FORCE_APPROACH_E) != 0u && ww > 0u) {
            x = (int)x0 + (int)ww - 1;
        } else {
            x = (int)x0;
        }
        for (i = 0u; i < hh && i < 20u; ++i) {
            y = (int)y0 + (int)i;
            if (tile_open(w, x, y)) {
                *ox = (uint8_t)x;
                *oy = (uint8_t)y;
                return 1;
            }
        }
    }
    return 0;
}

static int player_strongest_cell(const force_world *w,
                                 uint8_t *ox, uint8_t *oy)
{
    uint8_t tally[FORCE_ROOM_MAX];
    uint8_t i, best, best_n, lead;

    zero_u8(tally, FORCE_ROOM_MAX);
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        uint8_t r;
        if (w->unit_count[i] == 0u) {
            continue;
        }
        if (w->unit_section[i] >= FORCE_LETTER_MAX) {
            continue;
        }
        r = w->unit_region[i];
        if (r < FORCE_ROOM_MAX) {
            tally[r] = (uint8_t)(tally[r] + 1u);
        }
    }
    best = 0u;
    best_n = 0u;
    for (i = 0u; i < w->room_count && i < FORCE_ROOM_MAX; ++i) {
        if (tally[i] > best_n) {
            best_n = tally[i];
            best = i;
        }
    }
    if (best_n > 0u && room_canonical_cell(w, best, ox, oy)) {
        return 1;
    }
    lead = w->section_lead[0];
    if (lead != FORCE_UNIT_NONE) {
        *ox = w->unit_x[lead];
        *oy = w->unit_y[lead];
        return 1;
    }
    return 0;
}

static int room_hits_play(const force_world *w, uint8_t r)
{
    unsigned x0 = w->room_x0[r];
    unsigned y0 = w->room_y0[r];
    unsigned x1 = x0 + w->room_w[r];
    unsigned y1 = y0 + w->room_h[r];
    unsigned px0 = w->play_x;
    unsigned py0 = w->play_y;
    unsigned px1 = px0 + w->play_w;
    unsigned py1 = py0 + w->play_h;

    return x1 > px0 && x0 < px1 && y1 > py0 && y0 < py1;
}

static int exit_face_cell(const force_world *w, uint8_t face,
                          uint8_t *ox, uint8_t *oy)
{
    uint8_t r;
    unsigned px0 = w->play_x;
    unsigned py0 = w->play_y;
    unsigned px1 = px0 + w->play_w;
    unsigned py1 = py0 + w->play_h;

    for (r = 0u; r < w->room_count; ++r) {
        uint8_t x0 = w->room_x0[r];
        uint8_t y0 = w->room_y0[r];
        uint8_t ww = w->room_w[r];
        uint8_t hh = w->room_h[r];
        int x, y, i, along, cap;

        if (!room_hits_play(w, r)) {
            continue;
        }
        if (face == FORCE_FACE_W) {
            if ((unsigned)x0 != px0) {
                continue;
            }
            x = (int)px0;
            y = (int)y0 + (int)(hh / 2u);
            along = 1;
            cap = (int)hh;
        } else if (face == FORCE_FACE_E) {
            if ((unsigned)x0 + (unsigned)ww != px1) {
                continue;
            }
            x = (int)px1 - 1;
            y = (int)y0 + (int)(hh / 2u);
            along = 1;
            cap = (int)hh;
        } else if (face == FORCE_FACE_N) {
            if ((unsigned)y0 != py0) {
                continue;
            }
            y = (int)py0;
            x = (int)x0 + (int)(ww / 2u);
            along = 0;
            cap = (int)ww;
        } else if (face == FORCE_FACE_S) {
            if ((unsigned)y0 + (unsigned)hh != py1) {
                continue;
            }
            y = (int)py1 - 1;
            x = (int)x0 + (int)(ww / 2u);
            along = 0;
            cap = (int)ww;
        } else {
            return 0;
        }
        if (tile_open(w, x, y)) {
            *ox = (uint8_t)x;
            *oy = (uint8_t)y;
            return 1;
        }
        if (cap > 20) {
            cap = 20;
        }
        for (i = 1; i < cap; ++i) {
            int ax = x;
            int ay = y;
            int bx = x;
            int by = y;
            if (along != 0) {
                ay = y + i;
                by = y - i;
            } else {
                ax = x + i;
                bx = x - i;
            }
            if (tile_open(w, ax, ay)) {
                *ox = (uint8_t)ax;
                *oy = (uint8_t)ay;
                return 1;
            }
            if (tile_open(w, bx, by)) {
                *ox = (uint8_t)bx;
                *oy = (uint8_t)by;
                return 1;
            }
        }
    }
    return 0;
}

static int resolve_script_where(const force_world *w, uint8_t where_i,
                                uint8_t *ox, uint8_t *oy)
{
    const force_script *sc = w->script;
    uint8_t kind, a, b;

    if (sc == NULL || where_i >= sc->where_count) {
        return 0;
    }
    kind = sc->where_kind[where_i];
    a = sc->where_a[where_i];
    b = sc->where_b[where_i];
    if (kind == FORCE_WHERE_CELL) {
        *ox = a;
        *oy = b;
        return 1;
    }
    if (kind == FORCE_WHERE_ROOM) {
        return room_canonical_cell(w, a, ox, oy);
    }
    if (kind == FORCE_WHERE_PLAYER) {
        return player_strongest_cell(w, ox, oy);
    }
    if (kind == FORCE_WHERE_EXIT) {
        return exit_face_cell(w, a, ox, oy);
    }
    return 0;
}

static int spawn_cell_ok(const force_world *w, uint8_t letter,
                         uint8_t cx, uint8_t cy)
{
    uint8_t tid, cls, verb;

    if (!cell_free(w, cx, cy, FORCE_UNIT_NONE)) {
        return 0;
    }
    tid = w->tiles[(int)w->row_off[cy] + cx];
    cls = force_tile_class[tid];
    if (cls == FORCE_CLASS_ROOFS) {
        return 0;
    }
    if (letter < FORCE_SECTION_MAX) {
        verb = w->section_order_verb[letter];
        if (verb == FORCE_VERB_MOVE &&
            chebyshev(cx, cy, w->section_order_x[letter],
                      w->section_order_y[letter]) <= 1u) {
            return 0;   /* same-tick MOVE dest would despawn this pulse */
        }
    }
    return 1;
}

static int pick_spawn_cell(const force_world *w, uint8_t letter,
                           uint8_t *ox, uint8_t *oy)
{
    uint8_t room = w->spawn_job_room;
    uint8_t x0, y0, ww, hh, axis, probes, x, y;

    if (room == 0xFFu) {
        room = w->spawn_room;
    }
    if (room >= w->room_count) {
        return 0;
    }
    x0 = w->room_x0[room];
    y0 = w->room_y0[room];
    ww = w->room_w[room];
    hh = w->room_h[room];
    axis = w->room_axis[room];
    probes = 0u;
    if (axis == FORCE_AXIS_NS) {
        for (y = 0u; y < hh; ++y) {
            for (x = 0u; x < ww; ++x) {
                uint8_t cx, cy;
                if (probes >= 32u) {
                    return 0;
                }
                probes++;
                cx = (uint8_t)(x0 + x);
                cy = (uint8_t)(y0 + y);
                if (spawn_cell_ok(w, letter, cx, cy)) {
                    *ox = cx;
                    *oy = cy;
                    return 1;
                }
            }
        }
    } else {
        for (x = 0u; x < ww; ++x) {
            for (y = 0u; y < hh; ++y) {
                uint8_t cx, cy;
                if (probes >= 32u) {
                    return 0;
                }
                probes++;
                cx = (uint8_t)(x0 + x);
                cy = (uint8_t)(y0 + y);
                if (spawn_cell_ok(w, letter, cx, cy)) {
                    *ox = cx;
                    *oy = cy;
                    return 1;
                }
            }
        }
    }
    return 0;
}

static void start_spawn_job(force_world *w, uint8_t tmpl)
{
    const force_script *sc = w->script;

    if (sc == NULL || tmpl >= sc->spawn_tmpl_count) {
        return;
    }
    w->spawn_job_rem    = sc->spawn_n[tmpl];
    w->spawn_job_letter = sc->spawn_letter[tmpl];
    w->spawn_job_room   = sc->spawn_room[tmpl];
    w->spawn_job_batch  = sc->spawn_batch[tmpl];
    w->spawn_job_period = sc->spawn_period[tmpl];
    w->spawn_job_wait   = 0u;
    if (script_trace_on()) {
        fprintf(stderr, "script t=%u spawn letter %u n %u rem %u\n",
                (unsigned)w->script_clock,
                (unsigned)w->spawn_job_letter,
                (unsigned)sc->spawn_n[tmpl],
                (unsigned)w->spawn_job_rem);
    }
}

static void issue_script_order(force_world *w, uint8_t letter,
                               uint8_t packed, uint8_t where_i)
{
    uint8_t verb = (uint8_t)(packed & 0x0Fu);
    uint8_t force = (uint8_t)(packed >> 4);
    uint8_t x, y;

    if (letter >= FORCE_SECTION_MAX) {
        return;
    }
    if (!resolve_script_where(w, where_i, &x, &y)) {
        return;
    }
    force_section_issue(w, letter, verb, x, y, force);
    if (verb == FORCE_VERB_ATTACK) {
        w->section_flags[letter] = (uint8_t)(
            w->section_flags[letter] &
            (uint8_t)~FORCE_SECTION_FLAG_COVER_ASSIGN);
    }
    if (w->spawn_job_rem > 0u && w->spawn_job_letter == letter) {
        w->section_order_str[letter] = (uint8_t)(
            w->section_strength[letter] + w->spawn_job_rem);
    }
    if (script_trace_on()) {
        fprintf(stderr,
                "script t=%u order letter %u verb %u at %u,%u force %u\n",
                (unsigned)w->script_clock,
                (unsigned)letter, (unsigned)verb,
                (unsigned)x, (unsigned)y, (unsigned)force);
    }
}

static void script_approach(force_world *w, uint8_t room, uint8_t bits)
{
    uint8_t who;

    if (room >= w->room_count) {
        return;
    }
    w->room_approach[room] = bits;
    for (who = FORCE_LETTER_MAX; who < FORCE_SECTION_MAX; ++who) {
        uint8_t verb, dest_r, f;
        dest_r = unit_region_at(w, w->section_order_x[who],
                                w->section_order_y[who]);
        if (dest_r != room) {
            continue;
        }
        verb = w->section_order_verb[who];
        f = w->section_flags[who];
        if (verb == FORCE_VERB_DEFEND ||
            verb == FORCE_VERB_RETREAT ||
            (verb == FORCE_VERB_ATTACK &&
             (f & FORCE_SECTION_FLAG_CONTACT) != 0u)) {
            w->section_flags[who] = (uint8_t)(
                f | FORCE_SECTION_FLAG_COVER_ASSIGN);
        }
    }
}

static void apply_watch_action(force_world *w, const force_script *sc,
                               uint8_t op, uint8_t arg)
{
    if (op == FORCE_OP_WIN) {
        script_set_outcome(w, FORCE_SCRIPT_WIN);
    } else if (op == FORCE_OP_LOSE) {
        script_set_outcome(w, FORCE_SCRIPT_LOSE);
    } else if (op == FORCE_OP_SET_SPAWN) {
        w->spawn_room = arg;
    } else if (op == FORCE_OP_APPROACH) {
        script_approach(w, (uint8_t)(arg & 0x0Fu),
                        (uint8_t)(arg >> 4));
    } else if (op == FORCE_OP_GOTO) {
        w->script_waiting = 0u;
        w->script_pc = sc->beat_pc[arg];
    }
}

static void script_step(force_world *w)
{
    const force_script *sc = w->script;
    uint8_t n, steps;

    if (sc == NULL || w->script_outcome != FORCE_SCRIPT_PLAYING) {
        return;
    }
    for (n = 0u; n < sc->watch_count; ++n) {
        uint8_t flags = sc->watch_flags[n];
        if ((flags & FORCE_SCRIPT_WATCH_ONCE) != 0u &&
            (w->script_fired & (uint8_t)(1u << n)) != 0u) {
            continue;
        }
        if (!pred_pair(w, sc, sc->watch_pred0[n], sc->watch_pred1[n])) {
            continue;
        }
        w->script_fired = (uint8_t)(w->script_fired | (uint8_t)(1u << n));
        if (script_trace_on()) {
            uint8_t wop = sc->watch_op[n];
            uint8_t warg = sc->watch_arg[n];
            if (wop == FORCE_OP_GOTO) {
                fprintf(stderr, "script t=%u watch %s -> %s\n",
                        (unsigned)w->script_clock,
                        script_watch_name(sc, n),
                        script_beat_name(sc, warg));
            } else {
                fprintf(stderr, "script t=%u watch %s -> %s\n",
                        (unsigned)w->script_clock,
                        script_watch_name(sc, n),
                        script_op_word(wop));
            }
        }
        apply_watch_action(w, sc, sc->watch_op[n], sc->watch_arg[n]);
        if (w->script_outcome != FORCE_SCRIPT_PLAYING) {
            return;
        }
    }
    if (w->script_waiting != 0u) {
        if (pred_pair(w, sc, w->script_wait_pred0, w->script_wait_pred1)) {
            if (script_trace_on()) {
                fprintf(stderr, "script t=%u -> %s\n",
                        (unsigned)w->script_clock,
                        script_beat_name(sc, w->script_wait_beat));
            }
            w->script_waiting = 0u;
            w->script_pc = sc->beat_pc[w->script_wait_beat];
        } else {
            return;
        }
    }
    steps = 0u;
    while (w->script_pc < sc->op_count &&
           w->script_waiting == 0u &&
           w->script_outcome == FORCE_SCRIPT_PLAYING &&
           steps < FORCE_SCRIPT_OPS_MAX) {
        uint8_t pc = w->script_pc;
        uint8_t op = sc->op_code[pc];
        uint8_t a  = sc->op_a[pc];
        uint8_t b  = sc->op_b[pc];
        uint8_t c  = sc->op_c[pc];
        w->script_pc = (uint8_t)(pc + 1u);
        steps++;
        switch (op) {
        case FORCE_OP_SPAWN:
            start_spawn_job(w, a);
            break;
        case FORCE_OP_ORDER:
            issue_script_order(w, a, b, c);
            break;
        case FORCE_OP_SET_SPAWN:
            w->spawn_room = a;
            break;
        case FORCE_OP_APPROACH:
            script_approach(w, a, b);
            break;
        case FORCE_OP_GOTO:
            if (script_trace_on()) {
                fprintf(stderr, "script t=%u goto %s\n",
                        (unsigned)w->script_clock,
                        script_beat_name(sc, a));
            }
            w->script_pc = sc->beat_pc[a];
            break;
        case FORCE_OP_WAIT:
            w->script_waiting = 1u;
            w->script_wait_pred0 = a;
            w->script_wait_pred1 = b;
            w->script_wait_beat  = c;
            if (script_trace_on()) {
                fprintf(stderr, "script t=%u wait %s\n",
                        (unsigned)w->script_clock,
                        script_beat_name(sc, c));
            }
            break;
        case FORCE_OP_WIN:
            script_set_outcome(w, FORCE_SCRIPT_WIN);
            break;
        case FORCE_OP_LOSE:
            script_set_outcome(w, FORCE_SCRIPT_LOSE);
            break;
        default:
            break;
        }
    }
}

static void spawn_job_pulse(force_world *w)
{
    uint8_t n, want, landed, who, slot, x, y;

    if (w->spawn_job_rem == 0u) {
        return;
    }
    if (w->spawn_job_wait > 0u) {
        w->spawn_job_wait--;
        if (w->spawn_job_wait > 0u) {
            return;
        }
    }
    who = w->spawn_job_letter;
    want = w->spawn_job_batch;
    if (want > w->spawn_job_rem) {
        want = w->spawn_job_rem;
    }
    landed = 0u;
    for (n = 0u; n < want; ++n) {
        if (!pick_spawn_cell(w, who, &x, &y)) {
            continue;
        }
        slot = force_unit_spawn(w, x, y, who, FORCE_KIND_INFANTRY, 1u,
                                FORCE_GLYPH_ENEMY_E);
        if (slot == FORCE_UNIT_NONE) {
            break;
        }
        w->spawn_job_rem--;
        landed++;
    }
    if (landed > 0u) {
        uint8_t verb, f;
        force_section_recount(w);
        if (who < FORCE_SECTION_MAX) {
            verb = w->section_order_verb[who];
            f = w->section_flags[who];
            if (verb == FORCE_VERB_DEFEND ||
                verb == FORCE_VERB_RETREAT ||
                (verb == FORCE_VERB_ATTACK &&
                 (f & FORCE_SECTION_FLAG_CONTACT) != 0u)) {
                w->section_flags[who] = (uint8_t)(
                    f | FORCE_SECTION_FLAG_COVER_ASSIGN);
            }
        }
    }
    w->spawn_job_wait = w->spawn_job_period;
}

static void contact_start(force_world *w)
{
    uint8_t who;

    for (who = FORCE_LETTER_MAX; who < FORCE_SECTION_MAX; ++who) {
        uint8_t dest_r, i, f;
        if (w->section_order_verb[who] != FORCE_VERB_ATTACK) {
            continue;
        }
        f = w->section_flags[who];
        if ((f & FORCE_SECTION_FLAG_CONTACT) != 0u) {
            continue;
        }
        dest_r = unit_region_at(w, w->section_order_x[who],
                                w->section_order_y[who]);
        if (dest_r == FORCE_UNIT_NONE) {
            continue;
        }
        for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
            if (w->unit_count[i] == 0u || w->unit_section[i] != who) {
                continue;
            }
            if (w->unit_region[i] == dest_r) {
                w->section_flags[who] = (uint8_t)(
                    f | FORCE_SECTION_FLAG_CONTACT
                      | FORCE_SECTION_FLAG_COVER_ASSIGN);
                break;
            }
        }
    }
}

static int where_on_edge(const force_world *w, uint8_t x, uint8_t y)
{
    unsigned x1;
    unsigned y1;

    if (w->play_w == 0u || w->play_h == 0u) {
        return 0;
    }
    x1 = (unsigned)w->play_x + (unsigned)w->play_w - 1u;
    y1 = (unsigned)w->play_y + (unsigned)w->play_h - 1u;
    return (unsigned)x == (unsigned)w->play_x || (unsigned)x == x1 ||
           (unsigned)y == (unsigned)w->play_y || (unsigned)y == y1;
}

static void despawn_exits(force_world *w)
{
    uint8_t i;
    uint16_t letters = 0u;

    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        uint8_t who, ox, oy;
        if (w->unit_count[i] == 0u) {
            continue;
        }
        who = w->unit_section[i];
        if (who < FORCE_LETTER_MAX || who >= FORCE_SECTION_MAX) {
            continue;
        }
        if (w->section_order_verb[who] != FORCE_VERB_MOVE) {
            continue;
        }
        ox = w->section_order_x[who];
        oy = w->section_order_y[who];
        if (!where_on_edge(w, ox, oy)) {
            continue;
        }
        if (chebyshev(w->unit_x[i], w->unit_y[i], ox, oy) > 1u) {
            continue;
        }
        w->unit_count[i] = 0u;
        w->unit_cover[i] = FORCE_UNIT_NONE;
        w->unit_over_verb[i] = FORCE_VERB_NONE;
        w->unit_fx[i] = 0u;
        letters = (uint16_t)(letters | (uint16_t)(1u << who));
    }
    if (letters == 0u) {
        return;
    }
    for (i = 0u; i < FORCE_SECTION_MAX; ++i) {
        if ((letters & (uint16_t)(1u << i)) == 0u) {
            continue;
        }
        force_section_relead(w, i);
    }
    force_section_recount(w);
}

void force_world_tick(force_world *world)
{
    uint8_t i;
    uint8_t due[FORCE_SECTION_MAX];
    combat_stats st;

    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        uint8_t fx = world->unit_fx[i];
        uint8_t hurt = (uint8_t)(fx & 0x0Fu);
        uint8_t muz = (uint8_t)(fx >> 4);
        if (hurt > 0u) {
            hurt--;
        }
        if (muz > 0u) {
            muz--;
        }
        world->unit_fx[i] = (uint8_t)(hurt | (uint8_t)(muz << 4));
    }
    for (i = 0u; i < FORCE_GRENADE_BANK; ++i) {
        if (world->nade_fx_ttl[i] > 0u) {
            world->nade_fx_ttl[i]--;
        }
    }
    if (world->script_outcome != FORCE_SCRIPT_PLAYING) {
        return;
    }

    world->script_clock = (uint16_t)(world->script_clock + 1u);
    world->path_fail_who = FORCE_UNIT_NONE;
    world->shot_this_tick = 0u;
    consume_cover_jobs(world);
    zero_u8(due, FORCE_SECTION_MAX);
    st.fire = 0u;
    st.none = 0u;
    st.dmg0 = 0u;
    st.silent = 0u;
    st.nade = 0u;
    for (i = 0u; i < FORCE_GRENADE_BANK; ++i) {
        if (world->grenade_wait[i] > 0u) {
            world->grenade_wait[i]--;
        }
    }
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        if (world->unit_count[i] == 0u) {
            continue;
        }
        unit_shoot(world, i, due, &st);
    }
    if (combat_trace_on() &&
        (st.fire != 0u || st.none != 0u || st.dmg0 != 0u ||
         st.nade != 0u)) {
        uint8_t p = 0u;
        uint8_t e = 0u;
        for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
            uint8_t s;
            if (world->unit_count[i] == 0u || world->unit_hp[i] == 0u) {
                continue;
            }
            s = world->unit_section[i];
            if (s < FORCE_LETTER_MAX) {
                p++;
            } else if (s < FORCE_SECTION_MAX) {
                e++;
            }
        }
        fprintf(stderr,
                "t=%u combat fire %u none %u dmg0 %u silent %u nade %u "
                "p%u e%u\n",
                (unsigned)world->script_clock,
                (unsigned)st.fire, (unsigned)st.none, (unsigned)st.dmg0,
                (unsigned)st.silent, (unsigned)st.nade,
                (unsigned)p, (unsigned)e);
    }
    apply_deaths(world);
    script_step(world);
    if (world->script_outcome != FORCE_SCRIPT_PLAYING) {
        return;
    }
    spawn_job_pulse(world);
    contact_start(world);
    consume_cover_jobs(world);
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        if (world->unit_count[i] == 0u) {
            continue;
        }
        if (world->unit_kind[i] == FORCE_KIND_EMPLACEMENT) {
            continue;
        }
        if (world->unit_move_wait[i] > 0u) {
            world->unit_move_wait[i]--;
            if (world->unit_move_wait[i] > 0u) {
                continue;
            }
        }
        unit_think(world, i);
    }
    despawn_exits(world);
    intel_pulse(world);
}
