#include "game/game.h"
#include "game/menu.h"
#include "game/title.h"
#include "sdl/host.h"

#include <stdio.h>
#include <string.h>

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
