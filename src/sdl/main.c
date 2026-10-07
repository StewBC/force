#include "game/game.h"
#include "game/menu.h"
#include "game/title.h"
#include "sdl/host.h"

#include <stdio.h>
#include <string.h>

/* Cross the river stamps six unbuilt decks. Two men on the west bank
   pour the north plank together, then step onto the south plank.
   Restore mission 0 before the frame. */
static int bridge_fail(force_game *game, const char *why)
{
    fprintf(stderr, "FORCE: bridge build failed: %s\n", why);
    force_game_begin(game, &force_missions[0]);
    return 0;
}

static uint8_t bridge_tile(const force_world *w, uint8_t x, uint8_t y)
{
    return w->tiles[(unsigned)w->row_off[y] + x];
}

static int bridge_prog(const force_world *w, uint8_t x, uint8_t y,
                       uint8_t *prog)
{
    uint8_t i;

    for (i = 0u; i < w->deck_count; ++i) {
        if (w->deck_x[i] == x && w->deck_y[i] == y) {
            *prog = w->deck_prog[i];
            return 1;
        }
    }
    return 0;
}

static int bridge_build(force_game *game)
{
    const force_mission *cross = NULL;
    force_world *w;
    uint8_t a;
    uint8_t b;
    uint8_t prog;
    unsigned i;

    for (i = 0u; i < force_mission_count; ++i) {
        if (strcmp(force_missions[i].name, "cross_river") == 0) {
            cross = &force_missions[i];
            break;
        }
    }
    if (cross == NULL || game->world == NULL) {
        fprintf(stderr, "FORCE: bridge build failed: no cross_river\n");
        return 0;
    }
    force_game_begin(game, cross);
    w = game->world;
    if (w->deck_count != 6u || w->deck_cost != 40u) {
        return bridge_fail(game, "deck list or cost");
    }
    for (i = 0u; i < w->deck_count; ++i) {
        uint8_t x = w->deck_x[i];
        uint8_t y = w->deck_y[i];

        if (y < 2u || y > 3u || x < 32u || x > 34u) {
            return bridge_fail(game, "deck cell");
        }
        if (bridge_tile(w, x, y) != FORCE_TILE_DECK_OPEN) {
            return bridge_fail(game, "unbuilt glyph");
        }
        if (w->color[(unsigned)w->row_off[y] + x] != FORCE_COLOR_WATER) {
            return bridge_fail(game, "deck not on water");
        }
    }
    a = force_unit_spawn(w, 31u, 2u, 1u, FORCE_KIND_INFANTRY, 1u, 6u);
    b = force_unit_spawn(w, 31u, 3u, 1u, FORCE_KIND_INFANTRY, 1u, 6u);
    if (a == FORCE_UNIT_NONE || b == FORCE_UNIT_NONE) {
        return bridge_fail(game, "spawn");
    }
    force_section_recount(w);
    w->unit_move_wait[a] = 0u;
    w->unit_move_wait[b] = 0u;
    w->deck_cost = 2u;
    force_section_issue(w, 1u, FORCE_VERB_BUILD, 32u, 2u, 10u);
    force_world_tick(w);
    if (bridge_tile(w, 32u, 2u) != FORCE_TILE_DECK_BUILT ||
        bridge_tile(w, 32u, 3u) != FORCE_TILE_DECK_OPEN) {
        return bridge_fail(game, "gang-up plank");
    }
    if (!bridge_prog(w, 32u, 2u, &prog) || prog != FORCE_UNIT_NONE ||
        !bridge_prog(w, 32u, 3u, &prog) || prog != 0u) {
        return bridge_fail(game, "gang-up progress");
    }
    if (w->unit_x[a] != 31u || w->unit_y[a] != 2u ||
        w->unit_x[b] != 31u || w->unit_y[b] != 3u ||
        w->unit_built_x[a] != 32u || w->unit_built_y[a] != 2u ||
        w->unit_built_x[b] != 32u || w->unit_built_y[b] != 2u) {
        return bridge_fail(game, "men left the bank early");
    }
    force_world_tick(w);
    if (bridge_tile(w, 32u, 3u) != FORCE_TILE_DECK_BUILT ||
        bridge_tile(w, 33u, 2u) != FORCE_TILE_DECK_OPEN ||
        w->color[(unsigned)w->row_off[3] + 32u] != FORCE_COLOR_WATER) {
        return bridge_fail(game, "second plank");
    }
    if (w->unit_x[a] != 32u || w->unit_y[a] != 3u ||
        w->unit_x[b] != 31u || w->unit_y[b] != 2u) {
        return bridge_fail(game, "step onto last plank");
    }
    force_game_begin(game, &force_missions[0]);
    return 1;
}

/* Take the Ridge shares normandy with Hold the Farm. Its friendlies live
   on the ridge layer (south strip). Restore mission 0 before the frame. */
static int ridge_friendlies(force_game *game)
{
    const force_mission *ridge = NULL;
    unsigned i;
    int n = 0;

    for (i = 0u; i < force_mission_count; ++i) {
        if (strcmp(force_missions[i].name, "take_ridge") == 0) {
            ridge = &force_missions[i];
            break;
        }
    }
    if (ridge == NULL || game->world == NULL) {
        return 0;
    }
    force_game_begin(game, ridge);
    for (i = 0u; i < FORCE_UNIT_MAX; ++i) {
        if (game->world->unit_count[i] == 0u) {
            continue;
        }
        if (game->world->unit_section[i] >= FORCE_LETTER_MAX) {
            continue;
        }
        if (game->world->unit_y[i] < 20u) {
            n = -1;
            break;
        }
        n++;
    }
    force_game_begin(game, &force_missions[0]);
    return n == 7;
}

int main(int argc, char **argv)
{
    const int smoke = (argc > 1 && strcmp(argv[1], "--smoke") == 0);
    force_host *host = NULL;
    force_game game;
    force_input input;
    int in_menu = 0;

    if (!force_host_init(&host)) {
        fprintf(stderr, "FORCE: failed to open an SDL window\n");
        return 1;
    }

    /* Splash. Comment out this call to boot straight into the menu. */
    if (!smoke && !force_title_show(host, game.pixels)) {
        force_host_shutdown(host);
        return 0;
    }

    if (smoke) {
        /* One frame of mission 0. No title, no menu. */
        force_game_init(&game);
        if (!bridge_build(&game)) {
            force_host_shutdown(host);
            return 1;
        }
        if (!force_menu_selftest()) {
            fprintf(stderr, "FORCE: menu self-test failed\n");
            force_host_shutdown(host);
            return 1;
        }
        if (!ridge_friendlies(&game)) {
            fprintf(stderr, "FORCE: ridge friendlies missing\n");
            force_host_shutdown(host);
            return 1;
        }
    } else {
        game.world = &force_world_bss;
        game.joy_present = false;
        game.stick_latched = false;
        game.leave = 0;
        force_campaign_load();
        force_host_sync_input(host);
        force_menu_open();
        in_menu = 1;
    }

    while (force_host_pump(host, &input)) {
        if (in_menu) {
            if (force_menu_tick(&input)) {
                force_input step = input;

                /* The selecting edge must not confirm an order. */
                step.cmd_kind = FORCE_CMD_NONE;
                step.cmd_value = 0;
                step.cursor_dx = 0;
                step.cursor_dy = 0;
                step.nav_dx = 0;
                step.nav_dy = 0;
                step.restart = false;
                force_game_begin(&game, force_menu_mission());
                in_menu = 0;
                force_game_tick(&game, &step);
                force_game_draw(&game);
            } else {
                force_menu_paint(&game.screen, game.pixels);
            }
        } else {
            force_game_tick(&game, &input);
            if (game.leave) {
                force_menu_commit(game.world->script_outcome,
                                  game.score_snap, game.snap_score);
                game.leave = 0;
                force_menu_open();
                in_menu = 1;
                force_menu_paint(&game.screen, game.pixels);
            } else {
                force_game_draw(&game);
            }
        }
        force_host_present(host, game.pixels);
        if (smoke) {
            break;
        }
    }

    force_host_shutdown(host);
    return 0;
}
