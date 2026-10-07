#include "game/game.h"
#include "game/menu.h"
#include "game/title.h"
#include "sdl/host.h"

#include <stdio.h>
#include <string.h>

/* Cross the river stamps six unbuilt decks. Two men on the west bank
   pour the north plank together, then step onto the south plank.
   The man on that plank must still show over the deck.
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

static int fb_has(const uint32_t *px, int cx, int cy, uint32_t color)
{
    int ox = cx * (int)FORCE_CELL_PX;
    int oy = cy * (int)FORCE_CELL_PX;
    int y, x;

    for (y = 0; y < (int)FORCE_CELL_PX; ++y) {
        const uint32_t *row = px + (oy + y) * FORCE_FB_W + ox;
        for (x = 0; x < (int)FORCE_CELL_PX; ++x) {
            if (row[x] == color) {
                return 1;
            }
        }
    }
    return 0;
}

static uint32_t glyph_ink(uint8_t tid)
{
    int y, x;

    if (tid >= FORCE_TILESET_COUNT) {
        return 0u;
    }
    for (y = 0; y < (int)FORCE_TILE_PX; ++y) {
        for (x = 0; x < (int)FORCE_TILE_PX; ++x) {
            uint32_t p = force_tileset[tid][y][x];
            if ((p >> 24) != 0u) {
                return p;
            }
        }
    }
    return 0u;
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
    {
        uint32_t ink = glyph_ink(w->unit_glyph[a]);
        uint32_t deck = force_tileset[FORCE_TILE_DECK_BUILT][0][0];
        int ax = (int)w->unit_x[a] - (int)w->win_x;
        int ay = (int)w->unit_y[a] - (int)w->win_y;
        int ex = 32 - (int)w->win_x;
        int ey = 2 - (int)w->win_y;

        force_game_draw(game);
        if (ink == 0u || ink == deck ||
            !fb_has(game->pixels, ax, ay, ink) ||
            fb_has(game->pixels, ex, ey, ink) ||
            !fb_has(game->pixels, ex, ey, deck)) {
            return bridge_fail(game, "man under deck");
        }
    }
    force_game_begin(game, &force_missions[0]);
    return 1;
}

static int via_fail(force_game *game, const char *why)
{
    fprintf(stderr, "FORCE: bridge via failed: %s\n", why);
    force_game_begin(game, &force_missions[0]);
    return 0;
}

static void bridge_finish(force_world *w, int west_only)
{
    uint8_t i;

    for (i = 0u; i < w->deck_count; ++i) {
        int idx;

        if (west_only && w->deck_x[i] != 32u) {
            continue;
        }
        w->deck_prog[i] = FORCE_UNIT_NONE;
        idx = (int)w->row_off[w->deck_y[i]] + (int)w->deck_x[i];
        w->tiles[idx] = FORCE_TILE_DECK_BUILT;
    }
}

/* (30,8) to (36,8) crosses the river south of the planks. A closed
   bridge keeps that straight step. An open one pulls him onto the
   planks and across. Restore mission 0 before the frame. */
static int bridge_via(force_game *game)
{
    const force_mission *cross = NULL;
    force_world *w;
    uint8_t m;
    unsigned i;
    int crossed = 0;

    for (i = 0u; i < force_mission_count; ++i) {
        if (strcmp(force_missions[i].name, "cross_river") == 0) {
            cross = &force_missions[i];
            break;
        }
    }
    if (cross == NULL || game->world == NULL) {
        fprintf(stderr, "FORCE: bridge via failed: no cross_river\n");
        return 0;
    }
    force_game_begin(game, cross);
    w = game->world;
    m = force_unit_spawn(w, 30u, 8u, 2u, FORCE_KIND_INFANTRY, 1u, 6u);
    if (m == FORCE_UNIT_NONE) {
        return via_fail(game, "spawn");
    }
    force_section_recount(w);
    w->unit_move_wait[m] = 0u;
    force_section_issue(w, 2u, FORCE_VERB_MOVE, 36u, 8u, 10u);
    force_world_tick(w);
    if (w->unit_x[m] != 31u || w->unit_y[m] != 8u) {
        return via_fail(game, "closed bridge pulled");
    }
    bridge_finish(w, 1);
    w->unit_x[m] = 30u;
    w->unit_y[m] = 8u;
    w->unit_move_wait[m] = 0u;
    force_section_issue(w, 2u, FORCE_VERB_MOVE, 36u, 8u, 10u);
    force_world_tick(w);
    if (w->unit_x[m] != 31u || w->unit_y[m] != 8u) {
        return via_fail(game, "partial bridge pulled");
    }
    bridge_finish(w, 0);
    w->unit_x[m] = 30u;
    w->unit_y[m] = 8u;
    w->unit_move_wait[m] = 0u;
    force_section_issue(w, 2u, FORCE_VERB_MOVE, 36u, 8u, 10u);
    force_world_tick(w);
    if (w->unit_y[m] >= 8u) {
        return via_fail(game, "open bridge ignored");
    }
    for (i = 0u; i < 80u; ++i) {
        w->unit_move_wait[m] = 0u;
        force_world_tick(w);
        if (w->unit_x[m] >= 35u) {
            crossed = 1;
            break;
        }
    }
    if (!crossed) {
        return via_fail(game, "did not cross");
    }
    for (i = 0u; i < 8u; ++i) {
        w->unit_move_wait[m] = 0u;
        force_world_tick(w);
        if (w->unit_x[m] < 35u) {
            return via_fail(game, "sent back");
        }
    }
    force_game_begin(game, &force_missions[0]);
    return 1;
}

/* One man on the bottom plank, order on the far side of the south door.
   The river is south of him. He has to step east to the gap. The old
   dodge stepped back west and stayed there. */
static int bridge_leave(force_game *game)
{
    const force_mission *cross = NULL;
    force_world *w;
    uint8_t m;
    unsigned i;

    for (i = 0u; i < force_mission_count; ++i) {
        if (strcmp(force_missions[i].name, "cross_river") == 0) {
            cross = &force_missions[i];
            break;
        }
    }
    if (cross == NULL || game->world == NULL) {
        fprintf(stderr, "FORCE: bridge leave failed: no cross_river\n");
        return 0;
    }
    force_game_begin(game, cross);
    w = game->world;
    bridge_finish(w, 0);
    m = force_unit_spawn(w, 32u, 3u, 3u, FORCE_KIND_INFANTRY, 1u, 6u);
    if (m == FORCE_UNIT_NONE) {
        fprintf(stderr, "FORCE: bridge leave failed: spawn\n");
        force_game_begin(game, &force_missions[0]);
        return 0;
    }
    force_section_recount(w);
    w->unit_move_wait[m] = 0u;
    force_section_issue(w, 3u, FORCE_VERB_MOVE, 0u, 18u, 10u);
    for (i = 0u; i < 40u; ++i) {
        w->unit_move_wait[m] = 0u;
        force_world_tick(w);
        if (w->unit_y[m] > 3u && w->unit_x[m] >= 35u) {
            force_game_begin(game, &force_missions[0]);
            return 1;
        }
    }
    fprintf(stderr, "FORCE: bridge leave failed: stuck at %u,%u\n",
            (unsigned)w->unit_x[m], (unsigned)w->unit_y[m]);
    force_game_begin(game, &force_missions[0]);
    return 0;
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
        if (!bridge_leave(&game)) {
            force_host_shutdown(host);
            return 1;
        }
        if (!bridge_via(&game)) {
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
