#include "game/world.h"

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
            for (i = 0u; i < world->portal_count; ++i) {
                uint8_t a = world->portal_from[i];
                uint8_t b = world->portal_to[i];
                uint8_t v;
                if (a == FORCE_UNIT_NONE || b == FORCE_UNIT_NONE) {
                    continue;
                }
                if (a == u) {
                    v = b;
                } else if (b == u) {
                    v = a;
                } else {
                    continue;
                }
                if (v >= world->room_count || visited[v]) {
                    continue;
                }
                visited[v] = 1u;
                if (u == src) {
                    world->next_hop[hop_index(src, v)] = i;
                } else {
                    world->next_hop[hop_index(src, v)] =
                        world->next_hop[hop_index(src, u)];
                }
                q[qt++] = v;
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

static int try_step(force_world *w, uint8_t i, int nx, int ny)
{
    if (nx < 0 || ny < 0 ||
        nx >= (int)w->width || ny >= (int)w->height) {
        return 0;
    }
    if (!cell_free(w, (uint8_t)nx, (uint8_t)ny, i)) {
        return 0;
    }
    w->unit_x[i] = (uint8_t)nx;
    w->unit_y[i] = (uint8_t)ny;
    return 1;
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
        if (try_step(w, i, nx, ny)) {
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
        if (try_step(w, i, nx, ny)) {
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
        moved = try_step(w, i, nx, ny);
    } else if (!pref_x && sx != 0u) {
        nx = add_s(w->unit_x[i], sx);
        ny = (int)w->unit_y[i];
        moved = try_step(w, i, nx, ny);
    }

    if (!moved) {
        if (pref_x) {
            int sdy = (sy != 0u) ? -(int)s8(sy) : -1;
            nx = (int)w->unit_x[i];
            ny = (int)w->unit_y[i] + sdy;
            moved = try_step(w, i, nx, ny);
        } else {
            int sdx = (sx != 0u) ? -(int)s8(sx) : -1;
            nx = (int)w->unit_x[i] + sdx;
            ny = (int)w->unit_y[i];
            moved = try_step(w, i, nx, ny);
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

static void portal_flip(force_world *w, uint8_t i, uint8_t p)
{
    if (w->unit_region[i] == w->portal_from[p]) {
        w->unit_region[i] = w->portal_to[p];
    } else {
        w->unit_region[i] = w->portal_from[p];
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

static uint8_t face_approach_bit(uint8_t facing)
{
    if (facing == FORCE_FACE_N) {
        return FORCE_APPROACH_N;
    }
    if (facing == FORCE_FACE_E) {
        return FORCE_APPROACH_E;
    }
    if (facing == FORCE_FACE_S) {
        return FORCE_APPROACH_S;
    }
    if (facing == FORCE_FACE_W) {
        return FORCE_APPROACH_W;
    }
    return 0u;
}

static int facing_matches(uint8_t facing, uint8_t approach)
{
    uint8_t bit;

    if (approach == 0u) {
        return 0;
    }
    if (facing == FORCE_FACE_NONE) {
        return 1;
    }
    bit = face_approach_bit(facing);
    if (bit == 0u) {
        return 0;
    }
    if (bit == FORCE_APPROACH_N) {
        bit = FORCE_APPROACH_S;
    } else if (bit == FORCE_APPROACH_S) {
        bit = FORCE_APPROACH_N;
    } else if (bit == FORCE_APPROACH_E) {
        bit = FORCE_APPROACH_W;
    } else {
        bit = FORCE_APPROACH_E;
    }
    return (approach & bit) != 0u;
}

static int scout_live(uint8_t facing, uint8_t approach)
{
    uint8_t bit = face_approach_bit(facing);

    if (bit == 0u || approach == 0u) {
        return 0;
    }
    return (approach & bit) != 0u;
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

static uint8_t pick_best(const force_world *w, uint8_t i, uint8_t room)
{
    uint8_t best = FORCE_UNIT_NONE;
    uint8_t best_tier = 0u;
    uint8_t best_manh = 0xFFu;
    uint8_t have = 0u;
    uint8_t approach = w->room_approach[room];
    uint8_t b, n, j;

    b = w->room_cover_base[room];
    n = w->room_cover_count[room];
    for (j = 0u; j < n; ++j) {
        uint8_t c = (uint8_t)(b + j);
        uint8_t g, f, tier, manh;
        if (c >= w->cover_count) {
            break;
        }
        if (cover_taken(w, c)) {
            continue;
        }
        g = w->cover_grade[c];
        f = w->cover_facing[c];
        if (g == 3u) {
            tier = 4u;
        } else if (g == 2u) {
            tier = facing_matches(f, approach) ? 2u : 1u;
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
        if (!scout_live(w->scout_facing[s], approach)) {
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

    force_cover_release(world, who);
    if (who >= FORCE_SECTION_MAX) {
        return;
    }
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        uint8_t r;
        if (world->unit_count[i] == 0u) {
            continue;
        }
        if (world->unit_section[i] != who) {
            continue;
        }
        if (world->unit_kind[i] == FORCE_KIND_EMPLACEMENT) {
            continue;
        }
        r = world->unit_region[i];
        if (r == FORCE_UNIT_NONE || r >= world->room_count) {
            continue;
        }
        world->unit_cover[i] = pick_best(world, i, r);
    }
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
    if (p == FORCE_UNIT_NONE || p >= w->portal_count) {
        fail_path(w, sec);
        return 0;
    }
    *p_out = p;
    *dx = w->portal_x[p];
    *dy = w->portal_y[p];
    return 1;
}

static void unit_think(force_world *w, uint8_t i)
{
    uint8_t sec = w->unit_section[i];
    uint8_t verb = w->section_order_verb[sec];
    uint8_t here, dest_r, p, dx, dy;
    uint8_t here0;
    uint8_t ox, oy;

    if (verb == FORCE_VERB_MOVE) {
        ox = w->section_order_x[sec];
        oy = w->section_order_y[sec];
    } else if (verb == FORCE_VERB_DEFEND) {
        if (!cover_cell(w, w->unit_cover[i], &ox, &oy)) {
            return;
        }
    } else {
        return;
    }
    if (!pull_desired(w, i, sec, ox, oy, &here, &dest_r, &p, &dx, &dy)) {
        return;
    }
    if (w->unit_x[i] == ox && w->unit_y[i] == oy && here == dest_r) {
        return;
    }
    if (dx != w->unit_tgt_x[i] || dy != w->unit_tgt_y[i]) {
        stepper_aim(w, i, dx, dy);
    }

    here0 = here;
    if (p != FORCE_UNIT_NONE &&
        w->unit_x[i] == w->portal_x[p] &&
        w->unit_y[i] == w->portal_y[p] &&
        here != dest_r) {
        portal_flip(w, i, p);
        if (!pull_desired(w, i, sec, ox, oy, &here, &dest_r, &p, &dx, &dy)) {
            return;
        }
        stepper_aim(w, i, dx, dy);
        return;
    }

    if (!stepper_step(w, i)) {
        return;
    }
    if (p != FORCE_UNIT_NONE &&
        w->unit_x[i] == w->portal_x[p] &&
        w->unit_y[i] == w->portal_y[p] &&
        here0 != dest_r) {
        portal_flip(w, i, p);
        if (pull_desired(w, i, sec, ox, oy, &here, &dest_r, &p, &dx, &dy)) {
            stepper_aim(w, i, dx, dy);
        }
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
    for (i = 0u; i < FORCE_ROOM_MAX; ++i) {
        world->room_approach[i] =
            (i < world->room_count) ? (uint8_t)FORCE_APPROACH_S : 0u;
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
