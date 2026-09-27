#include "game/command.h"

#include "core/screen.h"

#include <stdio.h>

static void draft_reset(force_game *g)
{
    g->cmd_verb = FORCE_VERB_NONE;
    g->cmd_who = FORCE_UNIT_NONE;
    g->cmd_dot = 0;
    g->cmd_unit = FORCE_UNIT_NONE;
    g->cmd_x = 0;
    g->cmd_y = 0;
    g->cmd_force = 0xFFu;
    g->cmd_slot = FORCE_SLOT_IDLE;
    g->cmd_digits = 0;
    g->cmd_flash = 0;
    g->cmd_nopath = 0;
}

static void flash(force_game *g)
{
    g->cmd_flash = 8u;
}

static uint8_t digits_of(uint8_t v)
{
    if (v >= 10u) {
        return 2u;
    }
    if (v > 0u) {
        return 1u;
    }
    return 0u;
}

static uint8_t verb_from_letter(uint8_t letter)
{
    if (letter == 0u) {
        return FORCE_VERB_ATTACK;
    }
    if (letter == 12u) {
        return FORCE_VERB_MOVE;
    }
    if (letter == 3u) {
        return FORCE_VERB_DEFEND;
    }
    if (letter == 7u) {
        return FORCE_VERB_HALT;
    }
    if (letter == 10u) {
        return FORCE_VERB_KILL;
    }
    if (letter == 17u) {
        return FORCE_VERB_RETREAT;
    }
    if (letter == 18u) {
        return FORCE_VERB_SPLIT;
    }
    if (letter == 9u) {
        return FORCE_VERB_JOIN;
    }
    if (letter == 5u) {
        return FORCE_VERB_FOCUS;
    }
    return FORCE_VERB_NONE;
}

static const char *verb_name(uint8_t verb)
{
    if (verb == FORCE_VERB_MOVE) {
        return "MOVE";
    }
    if (verb == FORCE_VERB_DEFEND) {
        return "DEFEND";
    }
    if (verb == FORCE_VERB_HALT) {
        return "HALT";
    }
    if (verb == FORCE_VERB_ATTACK) {
        return "ATTACK";
    }
    if (verb == FORCE_VERB_KILL) {
        return "KILL";
    }
    if (verb == FORCE_VERB_RETREAT) {
        return "RETREAT";
    }
    if (verb == FORCE_VERB_SPLIT) {
        return "SPLIT";
    }
    if (verb == FORCE_VERB_JOIN) {
        return "JOIN";
    }
    if (verb == FORCE_VERB_FOCUS) {
        return "FOCUS";
    }
    return "";
}

uint8_t force_command_implied_who(const force_game *g)
{
    const force_world *w = g->world;
    uint8_t x0, y0, x1, y1;
    uint8_t i;

    force_game_cursor_span(g, &x0, &y0, &x1, &y1);
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        uint8_t ux, uy;
        if (w->unit_count[i] == 0u) {
            continue;
        }
        ux = w->unit_x[i];
        uy = w->unit_y[i];
        if (ux < x0 || uy < y0 || ux >= x1 || uy >= y1) {
            continue;
        }
        if (w->unit_section[i] >= FORCE_LETTER_MAX) {
            continue;
        }
        return w->unit_section[i];
    }
    return FORCE_UNIT_NONE;
}

static uint8_t implied_unit(const force_game *g)
{
    const force_world *w = g->world;
    uint8_t x0, y0, x1, y1;
    uint8_t i;

    force_game_cursor_span(g, &x0, &y0, &x1, &y1);
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        uint8_t ux, uy;
        if (w->unit_count[i] == 0u) {
            continue;
        }
        ux = w->unit_x[i];
        uy = w->unit_y[i];
        if (ux < x0 || uy < y0 || ux >= x1 || uy >= y1) {
            continue;
        }
        return i;
    }
    return FORCE_UNIT_NONE;
}

static int letter_where_verb(uint8_t verb)
{
    return verb == FORCE_VERB_SPLIT || verb == FORCE_VERB_JOIN;
}

static void clear_who(force_game *g)
{
    g->cmd_who = FORCE_UNIT_NONE;
    g->cmd_dot = 0;
    g->cmd_unit = FORCE_UNIT_NONE;
}

void force_command_init(force_game *g)
{
    uint8_t i;

    draft_reset(g);
    g->cmd_last_who = FORCE_UNIT_NONE;
    for (i = 0u; i < FORCE_LETTER_MAX; ++i) {
        if (g->world->section_strength[i] > 0u) {
            g->cmd_last_who = i;
            break;
        }
    }
}

static void accept_verb(force_game *g, uint8_t letter)
{
    uint8_t verb = verb_from_letter(letter);

    if (verb == FORCE_VERB_NONE) {
        flash(g);
        return;
    }
    g->cmd_verb = verb;
    g->cmd_who = FORCE_UNIT_NONE;
    g->cmd_dot = 0;
    g->cmd_unit = FORCE_UNIT_NONE;
    g->cmd_digits = 0;
    g->cmd_x = letter_where_verb(verb) ? 0xFFu : 0;
    g->cmd_y = 0;
    g->cmd_force = 0xFFu;
    if (verb == FORCE_VERB_FOCUS) {
        g->cmd_slot = FORCE_SLOT_WHERE_X;
        return;
    }
    g->cmd_slot = FORCE_SLOT_WHO;
}

static void accept_who(force_game *g, uint8_t letter)
{
    if (letter >= FORCE_LETTER_MAX) {
        flash(g);
        return;
    }
    g->cmd_who = letter;
    g->cmd_dot = 0;
    g->cmd_unit = FORCE_UNIT_NONE;
    g->cmd_digits = 0;
    if (g->cmd_verb == FORCE_VERB_HALT) {
        return;
    }
    g->cmd_slot = FORCE_SLOT_WHERE_X;
    if (letter_where_verb(g->cmd_verb)) {
        g->cmd_x = 0xFFu;
    } else {
        g->cmd_x = 0;
    }
}

static void accept_period(force_game *g)
{
    uint8_t i;
    uint8_t sec;

    if (letter_where_verb(g->cmd_verb) ||
        g->cmd_verb == FORCE_VERB_NONE) {
        flash(g);
        return;
    }
    i = implied_unit(g);
    if (i == FORCE_UNIT_NONE) {
        flash(g);
        return;
    }
    sec = g->world->unit_section[i];
    if (sec >= FORCE_LETTER_MAX) {
        flash(g);
        return;
    }
    g->cmd_dot = 1;
    g->cmd_unit = i;
    g->cmd_who = sec;
    g->cmd_digits = 0;
    if (g->cmd_verb == FORCE_VERB_HALT) {
        return;
    }
    g->cmd_slot = FORCE_SLOT_WHERE_X;
    g->cmd_x = 0;
}

static void accept_digit(force_game *g, uint8_t d)
{
    uint8_t slot = g->cmd_slot;

    if (g->cmd_digits >= 2u) {
        flash(g);
        return;
    }
    if (slot == FORCE_SLOT_WHERE_X) {
        g->cmd_x = (uint8_t)(g->cmd_x * 10u + d);
        g->cmd_digits = (uint8_t)(g->cmd_digits + 1u);
        return;
    }
    if (slot == FORCE_SLOT_WHERE_Y) {
        g->cmd_y = (uint8_t)(g->cmd_y * 10u + d);
        g->cmd_digits = (uint8_t)(g->cmd_digits + 1u);
        return;
    }
    if (slot == FORCE_SLOT_FORCE) {
        if (g->cmd_verb == FORCE_VERB_SPLIT && d == 0u &&
            g->cmd_digits == 0u) {
            flash(g);
            return;
        }
        if (g->cmd_digits == 0u) {
            g->cmd_force = d;
            g->cmd_digits = 1u;
            return;
        }
        if ((unsigned)g->cmd_force * 10u + (unsigned)d > 10u) {
            flash(g);
            return;
        }
        g->cmd_force = (uint8_t)(g->cmd_force * 10u + d);
        g->cmd_digits = 2u;
        return;
    }
    flash(g);
}

static void accept_sep(force_game *g)
{
    if (letter_where_verb(g->cmd_verb)) {
        flash(g);
        return;
    }
    if (g->cmd_slot == FORCE_SLOT_WHERE_X && g->cmd_digits > 0u) {
        g->cmd_slot = FORCE_SLOT_WHERE_Y;
        g->cmd_digits = 0;
        g->cmd_y = 0;
        return;
    }
    if (g->cmd_slot == FORCE_SLOT_WHERE_Y && g->cmd_digits > 0u) {
        g->cmd_slot = FORCE_SLOT_FORCE;
        g->cmd_digits = 0;
        g->cmd_force = 0xFFu;
        return;
    }
    flash(g);
}

static void pop_number(force_game *g, uint8_t *value, int is_force)
{
    *value = (uint8_t)(*value / 10u);
    g->cmd_digits = (uint8_t)(g->cmd_digits - 1u);
    if (is_force && g->cmd_digits == 0u) {
        *value = 0xFFu;
    }
}

static void pop_slot(force_game *g)
{
    uint8_t slot = g->cmd_slot;

    if (slot == FORCE_SLOT_IDLE) {
        return;
    }
    if (slot == FORCE_SLOT_SHOW) {
        draft_reset(g);
        return;
    }
    if (slot == FORCE_SLOT_WHERE_X || slot == FORCE_SLOT_WHERE_Y ||
        slot == FORCE_SLOT_FORCE) {
        if (g->cmd_digits > 0u) {
            if (slot == FORCE_SLOT_WHERE_X) {
                pop_number(g, &g->cmd_x, 0);
            } else if (slot == FORCE_SLOT_WHERE_Y) {
                pop_number(g, &g->cmd_y, 0);
            } else {
                pop_number(g, &g->cmd_force, 1);
            }
            return;
        }
        if (slot == FORCE_SLOT_FORCE) {
            if (g->cmd_verb == FORCE_VERB_SPLIT) {
                g->cmd_slot = FORCE_SLOT_WHERE_X;
                g->cmd_force = 0xFFu;
                g->cmd_digits = 0;
                return;
            }
            g->cmd_slot = FORCE_SLOT_WHERE_Y;
            g->cmd_force = 0xFFu;
            g->cmd_digits = digits_of(g->cmd_y);
            return;
        }
        if (slot == FORCE_SLOT_WHERE_Y) {
            g->cmd_slot = FORCE_SLOT_WHERE_X;
            g->cmd_digits = digits_of(g->cmd_x);
            return;
        }
        if (letter_where_verb(g->cmd_verb) && g->cmd_x != 0xFFu) {
            g->cmd_x = 0xFFu;
            g->cmd_digits = 0;
            return;
        }
        if (g->cmd_verb == FORCE_VERB_FOCUS) {
            draft_reset(g);
            return;
        }
        g->cmd_slot = FORCE_SLOT_WHO;
        clear_who(g);
        g->cmd_x = letter_where_verb(g->cmd_verb) ? 0xFFu : 0;
        g->cmd_digits = 0;
        return;
    }
    if (slot == FORCE_SLOT_WHO) {
        if (g->cmd_who == FORCE_UNIT_NONE && g->cmd_dot == 0u) {
            draft_reset(g);
        } else {
            clear_who(g);
        }
    }
}

static void show_ok(force_game *g, uint8_t who, uint8_t x, uint8_t y,
                    uint8_t force)
{
    g->cmd_nopath = 0;
    g->cmd_who = who;
    g->cmd_x = x;
    g->cmd_y = y;
    g->cmd_force = force;
    g->cmd_slot = FORCE_SLOT_SHOW;
    g->cmd_digits = 0;
}

static int commit_split(force_game *g)
{
    force_world *w = g->world;
    uint8_t src;
    uint8_t dst;
    uint8_t first;
    uint8_t n;
    uint8_t u;
    uint8_t named_src = 0u;

    if (g->cmd_x < FORCE_LETTER_MAX) {
        dst = g->cmd_x;
        if (g->cmd_who >= FORCE_LETTER_MAX) {
            flash(g);
            return 1;
        }
        src = g->cmd_who;
        named_src = 1u;
        u = implied_unit(g);
        if (u != FORCE_UNIT_NONE && w->unit_section[u] != src) {
            flash(g);
            return 1;
        }
        if (u != FORCE_UNIT_NONE && w->unit_section[u] == src) {
            first = u;
        } else {
            first = w->section_lead[src];
        }
    } else {
        if (g->cmd_who >= FORCE_LETTER_MAX) {
            flash(g);
            return 1;
        }
        dst = g->cmd_who;
        u = implied_unit(g);
        if (u == FORCE_UNIT_NONE || w->unit_section[u] >= FORCE_LETTER_MAX) {
            flash(g);
            return 1;
        }
        src = w->unit_section[u];
        first = u;
    }
    if (g->cmd_force == 0xFFu || g->cmd_slot != FORCE_SLOT_FORCE) {
        n = 1u;
    } else {
        n = g->cmd_force;
    }
    if (!force_section_peel(w, src, dst, first, n)) {
        flash(g);
        return 1;
    }
    g->cmd_dot = 0;
    g->cmd_unit = FORCE_UNIT_NONE;
    g->cmd_last_who = dst;
    show_ok(g, dst, named_src ? src : 0xFFu, 0, n);
    return 1;
}

static int commit_join(force_game *g)
{
    uint8_t src = g->cmd_who;
    uint8_t dst = g->cmd_x;

    if (src >= FORCE_LETTER_MAX || dst >= FORCE_LETTER_MAX) {
        flash(g);
        return 1;
    }
    if (!force_section_join(g->world, src, dst)) {
        flash(g);
        return 1;
    }
    g->cmd_dot = 0;
    g->cmd_unit = FORCE_UNIT_NONE;
    g->cmd_last_who = dst;
    show_ok(g, dst, src, 0, 10u);
    return 1;
}

static int commit_dot(force_game *g, uint8_t x, uint8_t y)
{
    force_world *w = g->world;
    uint8_t i = g->cmd_unit;
    uint8_t verb = g->cmd_verb;

    if (i >= FORCE_UNIT_MAX || w->unit_count[i] == 0u ||
        w->unit_hp[i] == 0u || w->unit_section[i] >= FORCE_LETTER_MAX) {
        flash(g);
        return 1;
    }
    if (verb == FORCE_VERB_HALT) {
        x = w->unit_x[i];
        y = w->unit_y[i];
    }
    if (!force_unit_nudge(w, i, verb, x, y)) {
        flash(g);
        return 1;
    }
    g->cmd_last_who = w->unit_section[i];
    show_ok(g, w->unit_section[i], x, y, 10u);
    return 1;
}

static void commit(force_game *g)
{
    force_world *w = g->world;
    uint8_t who = g->cmd_who;
    uint8_t x;
    uint8_t y;
    uint8_t force;
    uint8_t map_x;
    uint8_t map_y;
    uint8_t slot = g->cmd_slot;

    force_game_cursor_cell(g, &map_x, &map_y);

    if (g->cmd_verb == FORCE_VERB_SPLIT) {
        (void)commit_split(g);
        return;
    }
    if (g->cmd_verb == FORCE_VERB_JOIN) {
        (void)commit_join(g);
        return;
    }

    if (g->cmd_verb == FORCE_VERB_HALT && g->cmd_dot != 0u) {
        (void)commit_dot(g, 0, 0);
        return;
    }

    if (g->cmd_verb != FORCE_VERB_HALT) {
        if (slot == FORCE_SLOT_WHO ||
            (slot == FORCE_SLOT_WHERE_X && g->cmd_digits == 0u)) {
            x = map_x;
            y = map_y;
        } else if (slot == FORCE_SLOT_WHERE_X) {
            x = g->cmd_x;
            y = map_y;
        } else if (slot == FORCE_SLOT_WHERE_Y && g->cmd_digits == 0u) {
            x = g->cmd_x;
            y = map_y;
        } else {
            x = g->cmd_x;
            y = g->cmd_y;
        }
        if (g->cmd_force == 0xFFu || slot != FORCE_SLOT_FORCE) {
            force = 10u;
        } else {
            force = g->cmd_force;
        }
    } else {
        x = 0;
        y = 0;
        force = 10u;
    }

    force_world_clamp_play(w, &x, &y);

    if (g->cmd_dot != 0u) {
        (void)commit_dot(g, x, y);
        return;
    }

    if (g->cmd_verb == FORCE_VERB_FOCUS) {
        if (g->cmd_force == 0xFFu || slot != FORCE_SLOT_FORCE) {
            force = 0u;
        }
        force_game_camera_focus(g, x, y);
        g->cam_ttl = (uint8_t)(force * FORCE_FOCUS_TICKS);
        g->cycle_kind = 0;
        g->cycle_room = FORCE_UNIT_NONE;
        show_ok(g, FORCE_UNIT_NONE, x, y, force);
        return;
    }

    if (who == FORCE_UNIT_NONE) {
        who = force_command_implied_who(g);
    }
    if (who == FORCE_UNIT_NONE) {
        who = g->cmd_last_who;
    }
    if (who == FORCE_UNIT_NONE || who >= FORCE_LETTER_MAX) {
        flash(g);
        return;
    }

    if (g->cmd_verb == FORCE_VERB_HALT) {
        uint8_t lead = w->section_lead[who];
        if (lead != FORCE_UNIT_NONE) {
            x = w->unit_x[lead];
            y = w->unit_y[lead];
        } else {
            x = w->section_last_x[who];
            y = w->section_last_y[who];
        }
        force = 10u;
    }

    force_section_issue(w, who, g->cmd_verb, x, y, force);
    g->cmd_dot = 0;
    g->cmd_unit = FORCE_UNIT_NONE;
    g->cmd_last_who = who;
    show_ok(g, who, x, y, force);
}

static void cycle_list(force_game *g, uint8_t kind)
{
    uint8_t prev = (g->cycle_kind == kind) ? g->cycle_room : FORCE_UNIT_NONE;
    uint8_t r;

    if (kind == 1u) {
        r = force_intel_next_hot(g->world, prev);
    } else {
        r = force_intel_next_mark(g->world, prev);
    }
    if (r == FORCE_UNIT_NONE) {
        flash(g);
        return;
    }
    g->cycle_kind = kind;
    g->cycle_room = r;
}

static void cycle_snap(force_game *g)
{
    const force_world *w = g->world;
    uint8_t r = g->cycle_room;
    uint8_t x;
    uint8_t y;
    uint8_t who;

    if (g->cycle_kind == 0u || r >= w->room_count) {
        flash(g);
        return;
    }
    if ((w->room_flags[r] & FORCE_ROOM_MARK) != 0u) {
        x = w->last_x[r];
        y = w->last_y[r];
    } else {
        x = (uint8_t)(w->room_x0[r] + (uint8_t)(w->room_w[r] / 2u));
        y = (uint8_t)(w->room_y0[r] + (uint8_t)(w->room_h[r] / 2u));
    }
    force_game_camera_focus(g, x, y);
    who = force_intel_player_in_room(w, r);
    if (who < FORCE_LETTER_MAX) {
        g->cmd_last_who = who;
    }
    g->cycle_kind = 0;
    g->cycle_room = FORCE_UNIT_NONE;
}

static int accept_instant(force_game *g, uint8_t letter)
{
    if (letter == 1u) {
        if (!force_game_camera_back(g)) {
            flash(g);
        }
        return 1;
    }
    if (letter == 2u || letter == 23u) {
        cycle_list(g, 1u);
        return 1;
    }
    if (letter == 4u) {
        cycle_list(g, 2u);
        return 1;
    }
    return 0;
}

void force_command_feed(force_game *g, const force_input *in)
{
    uint8_t kind = in->cmd_kind;
    uint8_t val = in->cmd_value;
    uint8_t slot = g->cmd_slot;

    if (kind == FORCE_CMD_NONE) {
        return;
    }
    if (kind == FORCE_CMD_ESC) {
        draft_reset(g);
        g->cycle_kind = 0;
        g->cycle_room = FORCE_UNIT_NONE;
        return;
    }
    if (kind == FORCE_CMD_SPACE) {
        if (g->cycle_kind != 0u &&
            (slot == FORCE_SLOT_IDLE || slot == FORCE_SLOT_SHOW)) {
            cycle_snap(g);
            return;
        }
        kind = FORCE_CMD_COMMA;
    }

    switch (slot) {
    case FORCE_SLOT_IDLE:
        if (kind == FORCE_CMD_LETTER) {
            if (accept_instant(g, val)) {
                break;
            }
            accept_verb(g, val);
        } else if (kind == FORCE_CMD_RETURN || kind == FORCE_CMD_DEL) {
            /* nop */
        } else {
            flash(g);
        }
        break;
    case FORCE_SLOT_SHOW:
        if (kind == FORCE_CMD_LETTER) {
            if (accept_instant(g, val)) {
                break;
            }
            if (verb_from_letter(val) != FORCE_VERB_NONE) {
                draft_reset(g);
            }
            accept_verb(g, val);
        } else if (kind == FORCE_CMD_DEL) {
            draft_reset(g);
        } else if (kind == FORCE_CMD_RETURN || kind == FORCE_CMD_DIGIT ||
                   kind == FORCE_CMD_COMMA) {
            /* nop */
        } else {
            flash(g);
        }
        break;
    case FORCE_SLOT_WHO:
        if (kind == FORCE_CMD_LETTER) {
            accept_who(g, val);
        } else if (kind == FORCE_CMD_PERIOD) {
            accept_period(g);
        } else if (kind == FORCE_CMD_RETURN) {
            commit(g);
        } else if (kind == FORCE_CMD_DEL) {
            pop_slot(g);
        } else {
            flash(g);
        }
        break;
    case FORCE_SLOT_WHERE_X:
    case FORCE_SLOT_WHERE_Y:
    case FORCE_SLOT_FORCE:
        if (letter_where_verb(g->cmd_verb) && slot == FORCE_SLOT_WHERE_X &&
            kind == FORCE_CMD_LETTER) {
            if (val >= FORCE_LETTER_MAX) {
                flash(g);
                break;
            }
            g->cmd_x = val;
            g->cmd_digits = 0;
            if (g->cmd_verb == FORCE_VERB_SPLIT) {
                g->cmd_slot = FORCE_SLOT_FORCE;
                g->cmd_force = 0xFFu;
            }
            break;
        }
        if (kind == FORCE_CMD_DIGIT) {
            if (letter_where_verb(g->cmd_verb) && slot == FORCE_SLOT_WHERE_X) {
                flash(g);
                break;
            }
            accept_digit(g, val);
        } else if (kind == FORCE_CMD_COMMA) {
            accept_sep(g);
        } else if (kind == FORCE_CMD_RETURN) {
            commit(g);
        } else if (kind == FORCE_CMD_DEL) {
            pop_slot(g);
        } else {
            flash(g);
        }
        break;
    default:
        break;
    }
}

void force_command_paint(force_game *g)
{
    force_screen *s = &g->screen;
    static const char *const hole_name[4] = { "VERB", "WHO", "WHERE", "FORCE" };
    static const int hole_x[4] = { 1, 8, 14, 22 };
    uint8_t hole_now;
    uint8_t i;
    uint8_t fg;
    char line[FORCE_COLS + 1];
    const char *vn = verb_name(g->cmd_verb);
    uint8_t slot = g->cmd_slot;
    uint8_t who = g->cmd_who;
    char who_ch = (g->cmd_dot != 0u) ? '.' :
                  ((who < FORCE_LETTER_MAX) ? (char)('A' + who) : '?');

    if (g->cmd_nopath != 0u && g->cmd_flash > 0u) {
        hole_now = 2u;
    } else if (slot == FORCE_SLOT_SHOW && g->cmd_flash == 0u) {
        hole_now = 0xFFu;
    } else if (slot == FORCE_SLOT_IDLE || slot == FORCE_SLOT_SHOW) {
        hole_now = 0u;
    } else if (slot == FORCE_SLOT_WHO) {
        hole_now = 1u;
    } else if (slot == FORCE_SLOT_WHERE_X || slot == FORCE_SLOT_WHERE_Y) {
        hole_now = 2u;
    } else {
        hole_now = 3u;
    }

    for (i = 0u; i < 4u; ++i) {
        fg = FORCE_WHITE;
        if (i == hole_now) {
            fg = (g->cmd_flash > 0u) ? FORCE_LIGHT_RED : FORCE_YELLOW;
        }
        force_screen_puts(s, hole_x[i], 20, hole_name[i], fg, FORCE_BLACK);
    }

    if (g->world->script_outcome == FORCE_SCRIPT_WIN) {
        force_screen_puts(s, 1, 21, "SUCCESS", FORCE_YELLOW,
                          FORCE_BLACK);
        return;
    }
    if (g->world->script_outcome == FORCE_SCRIPT_LOSE) {
        force_screen_puts(s, 1, 21, "DEFEAT", FORCE_LIGHT_RED,
                          FORCE_BLACK);
        return;
    }

    line[0] = '\0';
    if (g->cmd_nopath != 0u && g->cmd_flash > 0u) {
        (void)snprintf(line, sizeof(line), "NO PATH");
        force_screen_puts(s, 1, 21, line, FORCE_LIGHT_RED, FORCE_BLACK);
        return;
    }
    if ((slot == FORCE_SLOT_IDLE || slot == FORCE_SLOT_SHOW) &&
        g->cycle_kind != 0u && g->cycle_room < g->world->room_count) {
        unsigned colour = (unsigned)g->world->room_colour[g->cycle_room];
        if (g->cycle_kind == 1u) {
            (void)snprintf(line, sizeof(line), "CONTACT %u", colour);
        } else {
            (void)snprintf(line, sizeof(line), "MARK %u", colour);
        }
        force_screen_puts(s, 1, 21, line, FORCE_YELLOW, FORCE_BLACK);
        return;
    }
    if (slot == FORCE_SLOT_IDLE) {
        (void)snprintf(line, sizeof(line), "READY");
    } else if (g->cmd_verb == FORCE_VERB_SPLIT) {
        if (slot == FORCE_SLOT_WHO && who == FORCE_UNIT_NONE) {
            (void)snprintf(line, sizeof(line), "%s", vn);
        } else if (slot == FORCE_SLOT_WHO ||
                   (slot == FORCE_SLOT_WHERE_X && g->cmd_x >= FORCE_LETTER_MAX)) {
            (void)snprintf(line, sizeof(line), "%s %c", vn, who_ch);
        } else if (slot == FORCE_SLOT_WHERE_X ||
                   (slot == FORCE_SLOT_FORCE && g->cmd_force == 0xFFu)) {
            (void)snprintf(line, sizeof(line), "%s %c %c", vn, who_ch,
                           (char)('A' + g->cmd_x));
        } else if (slot == FORCE_SLOT_FORCE) {
            (void)snprintf(line, sizeof(line), "%s %c %c %d", vn, who_ch,
                           (char)('A' + g->cmd_x), (int)g->cmd_force);
        } else if (g->cmd_x >= FORCE_LETTER_MAX) {
            (void)snprintf(line, sizeof(line), "SPLIT %c", who_ch);
        } else if (g->cmd_force > 1u) {
            (void)snprintf(line, sizeof(line), "SPLIT %c %c %d",
                           (char)('A' + g->cmd_x), who_ch, (int)g->cmd_force);
        } else {
            (void)snprintf(line, sizeof(line), "SPLIT %c %c",
                           (char)('A' + g->cmd_x), who_ch);
        }
    } else if (g->cmd_verb == FORCE_VERB_JOIN) {
        if (slot == FORCE_SLOT_WHO && who == FORCE_UNIT_NONE) {
            (void)snprintf(line, sizeof(line), "%s", vn);
        } else if (slot == FORCE_SLOT_WHO || g->cmd_x >= FORCE_LETTER_MAX) {
            (void)snprintf(line, sizeof(line), "%s %c", vn, who_ch);
        } else {
            (void)snprintf(line, sizeof(line), "JOIN %c %c", who_ch,
                           (char)('A' + g->cmd_x));
        }
    } else if (g->cmd_verb == FORCE_VERB_FOCUS) {
        if (slot == FORCE_SLOT_WHERE_X && g->cmd_digits == 0u) {
            (void)snprintf(line, sizeof(line), "%s", vn);
        } else if (slot == FORCE_SLOT_WHERE_X) {
            (void)snprintf(line, sizeof(line), "%s AT %d", vn, (int)g->cmd_x);
        } else if (slot == FORCE_SLOT_WHERE_Y && g->cmd_digits == 0u) {
            (void)snprintf(line, sizeof(line), "%s AT %d,", vn, (int)g->cmd_x);
        } else if (slot == FORCE_SLOT_WHERE_Y) {
            (void)snprintf(line, sizeof(line), "%s AT %d,%d", vn,
                           (int)g->cmd_x, (int)g->cmd_y);
        } else if (slot == FORCE_SLOT_FORCE && g->cmd_force == 0xFFu) {
            (void)snprintf(line, sizeof(line), "%s AT %d,%d FORCE", vn,
                           (int)g->cmd_x, (int)g->cmd_y);
        } else if (slot == FORCE_SLOT_FORCE) {
            (void)snprintf(line, sizeof(line), "%s AT %d,%d FORCE %d", vn,
                           (int)g->cmd_x, (int)g->cmd_y, (int)g->cmd_force);
        } else if (g->cmd_force > 0u) {
            (void)snprintf(line, sizeof(line), "FOCUS AT %d,%d FORCE %d",
                           (int)g->cmd_x, (int)g->cmd_y, (int)g->cmd_force);
        } else {
            (void)snprintf(line, sizeof(line), "FOCUS AT %d,%d",
                           (int)g->cmd_x, (int)g->cmd_y);
        }
    } else if (slot == FORCE_SLOT_WHO && who == FORCE_UNIT_NONE &&
               g->cmd_dot == 0u) {
        (void)snprintf(line, sizeof(line), "%s", vn);
    } else if (slot == FORCE_SLOT_WHO) {
        (void)snprintf(line, sizeof(line), "%s %c", vn, who_ch);
    } else if (slot == FORCE_SLOT_WHERE_X && g->cmd_digits == 0u) {
        (void)snprintf(line, sizeof(line), "%s %c", vn, who_ch);
    } else if (slot == FORCE_SLOT_WHERE_X) {
        (void)snprintf(line, sizeof(line), "%s %c AT %d", vn, who_ch,
                       (int)g->cmd_x);
    } else if (slot == FORCE_SLOT_WHERE_Y && g->cmd_digits == 0u) {
        (void)snprintf(line, sizeof(line), "%s %c AT %d,", vn, who_ch,
                       (int)g->cmd_x);
    } else if (slot == FORCE_SLOT_WHERE_Y) {
        (void)snprintf(line, sizeof(line), "%s %c AT %d,%d", vn, who_ch,
                       (int)g->cmd_x, (int)g->cmd_y);
    } else if (slot == FORCE_SLOT_FORCE && g->cmd_force == 0xFFu) {
        (void)snprintf(line, sizeof(line), "%s %c AT %d,%d FORCE", vn, who_ch,
                       (int)g->cmd_x, (int)g->cmd_y);
    } else if (slot == FORCE_SLOT_FORCE) {
        (void)snprintf(line, sizeof(line), "%s %c AT %d,%d FORCE %d", vn, who_ch,
                       (int)g->cmd_x, (int)g->cmd_y, (int)g->cmd_force);
    } else if (slot == FORCE_SLOT_SHOW && g->cmd_verb == FORCE_VERB_HALT) {
        (void)snprintf(line, sizeof(line), "HALT %c", who_ch);
    } else if (slot == FORCE_SLOT_SHOW && g->cmd_dot != 0u) {
        (void)snprintf(line, sizeof(line), "%s . AT %d,%d", vn,
                       (int)g->cmd_x, (int)g->cmd_y);
    } else if (slot == FORCE_SLOT_SHOW) {
        (void)snprintf(line, sizeof(line), "%s %c AT %d,%d FORCE %d", vn, who_ch,
                       (int)g->cmd_x, (int)g->cmd_y, (int)g->cmd_force);
    }

    fg = (slot == FORCE_SLOT_IDLE || slot == FORCE_SLOT_SHOW)
             ? FORCE_LIGHT_GREEN
             : FORCE_WHITE;
    force_screen_puts(s, 1, 21, line, fg, FORCE_BLACK);
}
