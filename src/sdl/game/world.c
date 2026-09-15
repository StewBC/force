#include "game/world.h"

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

static int is_portal_cell(const force_world *w, uint8_t x, uint8_t y);
static uint8_t manhattan(uint8_t x0, uint8_t y0, uint8_t x1, uint8_t y1);

static int trace_on(void)
{
    static int v = -1;

    if (v < 0) {
        v = (getenv("FORCE_TRACE") != NULL) ? 1 : 0;
    }
    return v;
}

#define FORCE_SX_NEG  0xFFu

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
    if (ax > FORCE_STEP_FAR || ay > FORCE_STEP_FAR) {
        uint8_t major = (ax >= ay) ? ax : ay;
        w->unit_step_run[i] =
            (major < FORCE_STEP_CAP) ? major : (uint8_t)FORCE_STEP_CAP;
    } else {
        w->unit_step_run[i] = 0u;
    }
}

/* Goodguys 0-7 / enemies 8-15: N, NE, E, SE, S, SW, W, NW. */
static void apply_cardinal_glyph(force_world *w, uint8_t i, uint8_t card)
{
    uint8_t base = (w->unit_section[i] >= FORCE_LETTER_MAX) ? 8u : 0u;
    static const uint8_t id[4] = { 0, 2, 4, 6 };

    if (card > 3u) {
        return;
    }
    w->unit_glyph[i] = (uint8_t)(base + id[card]);
}

static void face_step(force_world *w, uint8_t i, int nx, int ny)
{
    if (nx > (int)w->unit_x[i]) {
        apply_cardinal_glyph(w, i, 1u);
    } else if (nx < (int)w->unit_x[i]) {
        apply_cardinal_glyph(w, i, 3u);
    } else if (ny > (int)w->unit_y[i]) {
        apply_cardinal_glyph(w, i, 2u);
    } else if (ny < (int)w->unit_y[i]) {
        apply_cardinal_glyph(w, i, 0u);
    }
}

static void face_slot(force_world *w, uint8_t i, uint8_t facing)
{
    if (facing == FORCE_FACE_N) {
        apply_cardinal_glyph(w, i, 0u);
    } else if (facing == FORCE_FACE_E) {
        apply_cardinal_glyph(w, i, 1u);
    } else if (facing == FORCE_FACE_S) {
        apply_cardinal_glyph(w, i, 2u);
    } else if (facing == FORCE_FACE_W) {
        apply_cardinal_glyph(w, i, 3u);
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
            w->unit_move_wait[i] = FORCE_MOVE_WAIT_DEFAULT;
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
            w->unit_move_wait[i] = FORCE_MOVE_WAIT_DEFAULT;
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
    w->unit_move_wait[i] = FORCE_MOVE_WAIT_DEFAULT;
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

static uint8_t section_front(const force_world *w, uint8_t who)
{
    uint8_t dest_r;
    uint8_t axis;
    uint8_t front;
    uint8_t verb;
    uint8_t lead;
    uint8_t here;
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
    if (verb == FORCE_VERB_RETREAT) {
        return approach_front(axis, w->room_approach[dest_r]);
    }
    front = FORCE_FACE_NONE;
    lead = w->section_lead[who];
    if (lead < FORCE_UNIT_MAX && w->unit_count[lead] != 0u) {
        here = w->unit_region[lead];
        if (here != dest_r && here != FORCE_UNIT_NONE &&
            here < w->room_count) {
            dx = (int)w->room_x0[dest_r] + (int)(w->room_w[dest_r] / 2u)
               - ((int)w->room_x0[here] + (int)(w->room_w[here] / 2u));
            dy = (int)w->room_y0[dest_r] + (int)(w->room_h[dest_r] / 2u)
               - ((int)w->room_y0[here] + (int)(w->room_h[here] / 2u));
        } else {
            dx = (int)w->section_order_x[who] - (int)w->unit_x[lead];
            dy = (int)w->section_order_y[who] - (int)w->unit_y[lead];
        }
        front = snap_axis(axis, dx, dy);
    }
    if (front == FORCE_FACE_NONE) {
        front = approach_front(axis, w->room_approach[dest_r]);
    }
    return front;
}

static uint8_t cover_look(const force_world *w, uint8_t who, uint8_t adv)
{
    if (adv == FORCE_FACE_NONE) {
        return section_front(w, who);
    }
    return opposite_face(adv);
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

static uint8_t pick_best(const force_world *w, uint8_t i, uint8_t room,
                         uint8_t front)
{
    uint8_t best = FORCE_UNIT_NONE;
    uint8_t best_tier = 0u;
    uint8_t best_manh = 0xFFu;
    uint8_t have = 0u;
    uint8_t b, n, j, start, rear, lo, none, hi, axis;

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
        if (world->unit_section[i] == who) {
            world->unit_cover[i] = FORCE_UNIT_NONE;
        }
    }
}

void force_cover_assign(force_world *world, uint8_t who)
{
    uint8_t i;
    uint8_t dest_r;
    uint8_t front;

    force_cover_release(world, who);
    if (who >= FORCE_SECTION_MAX) {
        return;
    }
    dest_r = unit_region_at(world,
                            world->section_order_x[who],
                            world->section_order_y[who]);
    if (dest_r == FORCE_UNIT_NONE || dest_r >= world->room_count) {
        return;
    }
    front = section_front(world, who);
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
    uint8_t verb = w->section_order_verb[sec];
    uint8_t here, dest_r, p, dx, dy;
    uint8_t ox, oy;

    w->unit_region[i] = unit_region_at(w, w->unit_x[i], w->unit_y[i]);

    if (verb == FORCE_VERB_MOVE) {
        (void)move_dest(w, i, sec, &ox, &oy);
    } else if (verb == FORCE_VERB_DEFEND) {
        if (!cover_cell(w, w->unit_cover[i], &ox, &oy)) {
            /* No hole in the WHERE room: march there, then prone. */
            (void)move_dest(w, i, sec, &ox, &oy);
        }
    } else {
        return;
    }
    if (!pull_desired(w, i, sec, ox, oy, &here, &dest_r, &p, &dx, &dy)) {
        return;
    }
    if (w->unit_x[i] == ox && w->unit_y[i] == oy && here == dest_r) {
        if (verb == FORCE_VERB_DEFEND) {
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
    if (trace_on()) {
        fprintf(stderr, "  step -> (%u,%u) r%u\n",
                (unsigned)w->unit_x[i], (unsigned)w->unit_y[i],
                (unsigned)w->unit_region[i]);
    }
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
    world->unit_tgt_x[slot] = x;
    world->unit_tgt_y[slot] = y;
    world->unit_step_sx[slot] = 0u;
    world->unit_step_sy[slot] = 0u;
    world->unit_step_ax[slot] = 0u;
    world->unit_step_ay[slot] = 0u;
    world->unit_step_err[slot] = 0u;
    world->unit_step_run[slot] = 0u;
    world->unit_move_wait[slot] = 0u;

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

void force_world_load(force_world *world, const force_mission *mission)
{
    const force_map *map = mission->map;
    uint8_t width;
    uint8_t height;
    uint8_t i;
    uint16_t y;
    uint16_t cells;

    world->width = (uint8_t)map->width;
    world->height = (uint8_t)map->height;
    world->win_x = (uint8_t)mission->x;
    world->win_y = (uint8_t)mission->y;
    world->win_w = (uint8_t)mission->w;
    world->win_h = (uint8_t)mission->h;

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
    zero_u8(world->unit_tgt_x, FORCE_UNIT_MAX);
    zero_u8(world->unit_tgt_y, FORCE_UNIT_MAX);
    zero_u8(world->unit_step_sx, FORCE_UNIT_MAX);
    zero_u8(world->unit_step_sy, FORCE_UNIT_MAX);
    zero_u8(world->unit_step_ax, FORCE_UNIT_MAX);
    zero_u8(world->unit_step_ay, FORCE_UNIT_MAX);
    zero_u8(world->unit_step_err, FORCE_UNIT_MAX);
    zero_u8(world->unit_step_run, FORCE_UNIT_MAX);
    zero_u8(world->unit_move_wait, FORCE_UNIT_MAX);
    world->path_fail_who = FORCE_UNIT_NONE;

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
    }

    if (map->spawn_count > 0u) {
        for (i = 0u; i < map->spawn_count; ++i) {
            uint8_t tile = map->spawn_tile[i];
            uint8_t cls = force_tile_class[tile];
            uint8_t section;

            if (cls == FORCE_CLASS_GOODGUYS) {
                section = 0u;
            } else if (cls == FORCE_CLASS_ENEMIES) {
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

void force_world_tick(force_world *world)
{
    uint8_t i;

    world->path_fail_who = FORCE_UNIT_NONE;
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
}
