#include "game/command.h"

#include "core/screen.h"

#include <stdio.h>

static void draft_reset(force_game *g)
{
    g->cmd_verb = FORCE_VERB_NONE;
    g->cmd_who = FORCE_UNIT_NONE;
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
    return "";
}

uint8_t force_command_implied_who(const force_game *g)
{
    const force_world *w = g->world;
    const int mx = (int)w->win_x + g->cursor_x;
    const int my = (int)w->win_y + g->cursor_y;
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
        return w->unit_section[i];
    }
    return FORCE_UNIT_NONE;
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
    g->cmd_slot = FORCE_SLOT_WHO;
    g->cmd_who = FORCE_UNIT_NONE;
    g->cmd_digits = 0;
}

static void accept_who(force_game *g, uint8_t letter)
{
    if (letter >= FORCE_LETTER_MAX) {
        flash(g);
        return;
    }
    g->cmd_who = letter;
    g->cmd_digits = 0;
    if (g->cmd_verb != FORCE_VERB_HALT) {
        g->cmd_slot = FORCE_SLOT_WHERE_X;
        g->cmd_x = 0;
    }
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
        g->cmd_slot = FORCE_SLOT_WHO;
        g->cmd_who = FORCE_UNIT_NONE;
        g->cmd_x = 0;
        g->cmd_digits = 0;
        return;
    }
    if (slot == FORCE_SLOT_WHO) {
        if (g->cmd_who == FORCE_UNIT_NONE) {
            draft_reset(g);
        } else {
            g->cmd_who = FORCE_UNIT_NONE;
        }
    }
}

static void commit(force_game *g)
{
    force_world *w = g->world;
    uint8_t who = g->cmd_who;
    uint8_t x;
    uint8_t y;
    uint8_t force;
    uint8_t map_x = (uint8_t)(w->win_x + (uint8_t)g->cursor_x);
    uint8_t map_y = (uint8_t)(w->win_y + (uint8_t)g->cursor_y);
    uint8_t slot = g->cmd_slot;
    uint8_t xmax;
    uint8_t ymax;

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
    } else {
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
    }

    xmax = (w->width > 0u) ? (uint8_t)(w->width - 1u) : 0u;
    ymax = (w->height > 0u) ? (uint8_t)(w->height - 1u) : 0u;
    if (x > xmax) {
        x = xmax;
    }
    if (y > ymax) {
        y = ymax;
    }

    w->section_order_verb[who] = g->cmd_verb;
    w->section_order_x[who] = x;
    w->section_order_y[who] = y;
    w->section_order_force[who] = force;
    {
        uint8_t f = w->section_flags[who];
        f = (uint8_t)(f & (uint8_t)~FORCE_SECTION_FLAG_NOPATH);
        if (g->cmd_verb == FORCE_VERB_DEFEND ||
            g->cmd_verb == FORCE_VERB_ATTACK) {
            f = (uint8_t)(f & (uint8_t)~FORCE_SECTION_FLAG_COVER_RELEASE);
            f = (uint8_t)(f | FORCE_SECTION_FLAG_COVER_ASSIGN);
        } else if (g->cmd_verb == FORCE_VERB_MOVE) {
            f = (uint8_t)(f & (uint8_t)~FORCE_SECTION_FLAG_COVER_ASSIGN);
            f = (uint8_t)(f | FORCE_SECTION_FLAG_COVER_RELEASE);
        }
        w->section_flags[who] = f;
    }
    w->section_order_str[who] = w->section_strength[who];
    g->cmd_nopath = 0;
    g->cmd_who = who;
    g->cmd_x = x;
    g->cmd_y = y;
    g->cmd_force = force;
    g->cmd_last_who = who;
    g->cmd_slot = FORCE_SLOT_SHOW;
    g->cmd_digits = 0;
}

void force_command_feed(force_game *g, const force_input *in)
{
    uint8_t kind = in->cmd_kind;
    uint8_t val = in->cmd_value;
    uint8_t slot = g->cmd_slot;

    if (kind == FORCE_CMD_NONE) {
        return;
    }
    if (kind == FORCE_CMD_SPACE) {
        kind = FORCE_CMD_COMMA;
    }

    switch (slot) {
    case FORCE_SLOT_IDLE:
        if (kind == FORCE_CMD_LETTER) {
            accept_verb(g, val);
        } else if (kind == FORCE_CMD_RETURN || kind == FORCE_CMD_DEL) {
            /* nop */
        } else {
            flash(g);
        }
        break;
    case FORCE_SLOT_SHOW:
        if (kind == FORCE_CMD_LETTER) {
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
        if (kind == FORCE_CMD_DIGIT) {
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
    char who_ch = (who < FORCE_LETTER_MAX) ? (char)('A' + who) : '?';

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

    line[0] = '\0';
    if (g->cmd_nopath != 0u && g->cmd_flash > 0u) {
        (void)snprintf(line, sizeof(line), "NO PATH");
        force_screen_puts(s, 1, 21, line, FORCE_LIGHT_RED, FORCE_BLACK);
        return;
    }
    if (slot == FORCE_SLOT_IDLE) {
        (void)snprintf(line, sizeof(line), "READY");
    } else if (slot == FORCE_SLOT_WHO && who == FORCE_UNIT_NONE) {
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
    } else if (slot == FORCE_SLOT_SHOW) {
        (void)snprintf(line, sizeof(line), "%s %c AT %d,%d FORCE %d", vn, who_ch,
                       (int)g->cmd_x, (int)g->cmd_y, (int)g->cmd_force);
    }

    fg = (slot == FORCE_SLOT_IDLE || slot == FORCE_SLOT_SHOW)
             ? FORCE_LIGHT_GREEN
             : FORCE_WHITE;
    force_screen_puts(s, 1, 21, line, fg, FORCE_BLACK);
}
