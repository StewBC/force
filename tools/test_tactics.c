/* Behavioral fixtures use the portable world as the reference simulation. */
#include <assert.h>
#include "../src/sdl/game/world.c"

static force_world board;
static void reset_board(void)
{
    unsigned i;
    memset(&board, 0, sizeof(board));
    board.width = board.height = board.play_w = board.play_h = 20;
    board.room_count = 1;
    board.room_w[0] = board.room_h[0] = 20;
    for (i = 0; i < 20; ++i) board.row_off[i] = (uint16_t)(20*i);
    memset(board.tiles, FORCE_TILE_EMPTY, sizeof(board.tiles));
    memset(board.section_lead, FORCE_UNIT_NONE, sizeof(board.section_lead));
    board.section_order_verb[0] = board.section_order_verb[8] = FORCE_VERB_HALT;
}
static void fire(uint8_t slot)
{
    uint8_t due[FORCE_SECTION_MAX] = {0};
    combat_stats stats = {0};
    unit_shoot(&board, slot, due, &stats);
}
static void weapons(void)
{
    uint8_t launcher, nest, target;
    reset_board();
    launcher = force_unit_spawn(&board, 4, 8, 0, FORCE_KIND_BAZOOKA, 1, 2);
    nest = force_unit_spawn(&board, 10, 8, 8, FORCE_KIND_EMPLACEMENT, 1, 14);
    assert(board.unit_hp[nest] == 48 && board.weapon_ammo[launcher] == 4);
    fire(launcher);
    assert(board.unit_hp[nest] == 16 && board.weapon_ammo[launcher] == 3);
    fire(launcher);
    assert(board.unit_hp[nest] == 16 && board.unit_fire_wait[launcher] == 19);
    board.unit_fire_wait[launcher] = 0;
    fire(launcher);
    assert(board.unit_hp[nest] == 0 && board.weapon_ammo[launcher] == 2);
    board.unit_count[launcher] = 0;
    assert(force_unit_spawn(&board, 4, 8, 0, FORCE_KIND_INFANTRY, 1, 2) == launcher);
    assert(board.weapon_ammo[launcher] == 0 && board.unit_hp[launcher] == 16);

    reset_board();
    nest = force_unit_spawn(&board, 10, 10, 0, FORCE_KIND_EMPLACEMENT, 1, 6);
    target = force_unit_spawn(&board, 14, 10, 8, FORCE_KIND_INFANTRY, 1, 10);
    fire(nest);                         /* rear of a west-facing nest */
    assert(board.unit_hp[target] == 16 && board.unit_fire_wait[nest] == 0);
    board.unit_x[target] = 6;
    board.tiles[board.row_off[10]+8] = 16;
    fire(nest);                         /* wall blocks the firing slit */
    assert(board.unit_hp[target] == 16);
    board.tiles[board.row_off[10]+8] = FORCE_TILE_EMPTY;
    fire(nest);
    assert(board.unit_hp[target] == 6 && board.unit_fire_wait[nest] == 3);
    assert(board.unit_x[nest] == 10 && board.unit_y[nest] == 10);

    reset_board();
    launcher = force_unit_spawn(&board, 5, 10, 0, FORCE_KIND_INFANTRY, 1, 2);
    nest = force_unit_spawn(&board, 9, 10, 8, FORCE_KIND_EMPLACEMENT, 1, 14);
    fire(launcher);
    assert(board.unit_hp[nest] == 47);  /* armored against rifle bullets */

    reset_board();
    launcher = force_unit_spawn(&board, 5, 10, 0, FORCE_KIND_BAZOOKA, 1, 2);
    target = force_unit_spawn(&board, 9, 10, 8, FORCE_KIND_INFANTRY, 1, 10);
    fire(launcher);                     /* crew uses rifles without a nest */
    assert(board.unit_hp[target] == 6 && board.weapon_ammo[launcher] == 4);
}
static void reinforcements(void)
{
    const uint8_t counts[] = {3, 1}, ids[] = {1, 8}, origins[] = {128, 128};
    const uint8_t batches[] = {3, 1}, periods[] = {1, 1};
    const uint8_t kinds[] = {1}, xs[] = {5}, ys[] = {5};
    const uint8_t ops[] = {1, 1}, args[] = {0, 1}, zeros[] = {0, 0};
    force_script sc = {0};
    reset_board();
    sc.spawn_tmpl_count = 2; sc.spawn_n = counts; sc.spawn_letter = ids;
    sc.spawn_room = origins; sc.spawn_batch = batches; sc.spawn_period = periods;
    sc.where_count = 1; sc.where_kind = kinds; sc.where_a = xs; sc.where_b = ys;
    sc.op_count = 2; sc.op_code = ops; sc.op_a = args; sc.op_b = sc.op_c = zeros;
    board.script = &sc;
    script_step(&board);
    assert(board.spawn_job_letter == 1 && board.script_pc == 1);
    spawn_job_pulse(&board);
    assert(board.unit_count[0] == 1 && board.unit_section[0] == 1);
    assert(board.unit_x[0] == 5 && board.unit_y[0] == 5 && board.unit_glyph[0] == 2);
    assert(board.spawn_job_rem == 2); /* exact point admits only one body */
    script_step(&board);
    spawn_job_pulse(&board);
    assert(board.spawn_job_rem == 2 && board.spawn_job_letter == 1);
    board.unit_x[0] = 6;
    spawn_job_pulse(&board);
    assert(board.spawn_job_rem == 1 && board.unit_section[1] == 1);
    board.spawn_job_rem = 0;
    script_step(&board);
    assert(board.spawn_job_letter == 8 && board.script_pc == 2);
}
/* Drive the authored director with controlled combat/progress outcomes. This
   checks cue sequencing and real spawn jobs without claiming balance testing. */
static void clear_section(uint8_t section)
{
    unsigned i;
    for (i = 0; i < FORCE_UNIT_MAX; ++i)
        if (board.unit_section[i] == section) board.unit_count[i] = 0;
    force_section_recount(&board);
}
static void director_pulse(void)
{
    unsigned i;
    spawn_job_pulse(&board);
    /* Leave each exact road entry free for the next scripted arrival. */
    for (i = 0; i < FORCE_UNIT_MAX; ++i) {
        if (!board.unit_count[i]) continue;
        if (board.unit_x[i] == 39 && board.unit_y[i] <= 3) board.unit_x[i] = 36;
        if (board.unit_x[i] == 0 && board.unit_y[i] <= 3) board.unit_x[i] = 2;
    }
    script_step(&board);
}
static void director_settle(void)
{
    unsigned n;
    for (n = 0; n < 160; ++n) director_pulse();
    assert(board.spawn_job_rem == 0);
}
static void cross_mission(void)
{
    const force_script *sc;
    unsigned i;
    uint8_t bridge_pred = 255, southwest = 255, approach = 255;
    force_world_load(&board, &force_missions[1]);
    sc = board.script;
    assert(strcmp(board.objective_text, "Defend, then build the bridge") == 0);
    assert(board.section_strength[9] == 1); /* Nest exists before contact. */
    for (i = 0; i < sc->pred_count; ++i)
        if (sc->pred_kind[i] == FORCE_PRED_BRIDGE_BUILT) bridge_pred = (uint8_t)i;
    assert(bridge_pred != 255 && !pred_true(&board, sc, bridge_pred));
    for (i = 0; i < board.room_count; ++i) {
        if (board.room_x0[i] == 0 && board.room_y0[i] == 11) southwest = (uint8_t)i;
        if (board.room_x0[i] == 9 && board.room_y0[i] == 11) approach = (uint8_t)i;
    }
    assert(southwest != 255 && approach != 255);
    script_step(&board);
    board.script_clock = 100;
    director_settle();
    assert(board.section_strength[8] == 6 && board.section_strength[1] == 0);
    for (i = 0; i + 1 < board.deck_count; ++i) board.deck_prog[i] = FORCE_UNIT_NONE;
    director_settle();
    assert(!pred_true(&board, sc, bridge_pred) && board.section_strength[1] == 0);
    board.deck_prog[board.deck_count-1] = FORCE_UNIT_NONE;
    assert(pred_true(&board, sc, bridge_pred));
    director_settle();
    assert(board.section_strength[1] == 4 && board.section_strength[2] == 1);
    assert(board.section_strength[10] == 4);
    assert(strcmp(board.objective_text, "Clear the road") == 0);
    assert(board.unit_kind[board.section_lead[2]] == FORCE_KIND_BAZOOKA);
    clear_section(9);
    director_settle();
    assert(board.section_strength[11] == 0); /* Road patrol must die too. */
    clear_section(10);
    director_settle();
    assert(board.section_strength[11] == 4 && board.section_strength[12] == 0);
    assert(strcmp(board.objective_text, "Clear the road") == 0);
    assert(board.section_order_verb[11] == FORCE_VERB_ATTACK);
    assert(board.section_order_x[11] == 20 && board.section_order_y[11] == 3);
    board.unit_region[board.section_lead[0]] = southwest;
    director_settle();
    assert(board.script_outcome == FORCE_SCRIPT_PLAYING); /* No scout shortcut. */
    /* The player can already be south of the river. Clearing the road
       wave must unlock defenders without asking them to return north. */
    clear_section(11);
    director_settle();
    assert(board.section_strength[12] == 5);
    assert(strcmp(board.objective_text, "Reach the southwest gap") == 0);
    assert(board.section_order_verb[12] == FORCE_VERB_DEFEND);
    assert(unit_region_at(&board, board.section_order_x[12],
                          board.section_order_y[12]) == approach);
    for (i = 0; i < FORCE_UNIT_MAX; ++i)
        if (board.unit_count[i] && board.unit_section[i] == 12)
            assert(board.unit_region[i] == southwest);
    assert(board.script_outcome == FORCE_SCRIPT_PLAYING);
    clear_section(12);
    director_settle();
    assert(board.script_outcome == FORCE_SCRIPT_WIN);
    force_world_load(&board, &force_missions[1]);
    assert(!pred_true(&board, board.script, bridge_pred)); /* Restart closes bridge. */
    for (i = 0; i < FORCE_LETTER_MAX; ++i) clear_section((uint8_t)i);
    script_step(&board);
    assert(board.script_outcome == FORCE_SCRIPT_LOSE);
    board.deck_count = 0;
    assert(!pred_true(&board, board.script, bridge_pred));
}
int main(void)
{
    weapons();
    reinforcements();
    cross_mission();
    puts("tactics behavior: armor, rockets, ammo, reload, arc, wall, fallback, slot reuse, point stream, job serialization, Cross the River director passed");
    return 0;
}
