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
int main(void)
{
    weapons();
    reinforcements();
    puts("tactics behavior: armor, rockets, ammo, reload, arc, wall, fallback, slot reuse, point stream, job serialization passed");
    return 0;
}
