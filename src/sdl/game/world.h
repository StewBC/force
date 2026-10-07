#ifndef FORCE_WORLD_H
#define FORCE_WORLD_H

#include "generated/force_data.h"

#if (FORCE_MAP_W_MAX * FORCE_MAP_H_MAX) != FORCE_MAP_CELLS_MAX
#error "FORCE_MAP_CELLS_MAX must equal FORCE_MAP_W_MAX * FORCE_MAP_H_MAX"
#endif
#if FORCE_UNIT_MAX != FORCE_SPAWN_MAX
#error "FORCE_UNIT_MAX must equal FORCE_SPAWN_MAX"
#endif
#if FORCE_SECTION_MAX != (FORCE_LETTER_MAX * 2)
#error "FORCE_SECTION_MAX must be two banks of FORCE_LETTER_MAX"
#endif
#if FORCE_ROOM_MAX != 16
#error "next-hop is a 16x16 page; FORCE_ROOM_MAX must stay 16"
#endif

#define FORCE_UNIT_NONE            0xFFu
#define FORCE_COLOR_WATER          118u /* blue ground; C64 paper index 6 */
#define FORCE_TILE_DECK_OPEN        80u /* unbuilt deck; blocks, even off water */
#define FORCE_TILE_DECK_BUILT       81u /* finished deck; open on water */
#define FORCE_LOGIC_PERIOD         3u   /* 3 video frames per world_tick; only game.c. Vsync: 20 Hz at 60, ~16.7 at 50. No ms cap. */
#define FORCE_MOVE_WAIT_DEFAULT    7u
#define FORCE_MOVE_WAIT_SPRINT     4u
#define FORCE_HP_INFANTRY          16u
#define FORCE_FIRE_WAIT_RIFLE       8u
#define FORCE_RANGE_MAX            16u   /* parked sight ray; dist >= 16 blocked */
#define FORCE_RIFLE_FAR            10u   /* dist >= 10 is not a rifle target */
#define FORCE_RIFLE_HALF            5u   /* dist >= 5 halves the posture number */
#define FORCE_GRENADE_RANGE         5u   /* Chebyshev throw cap */
#define FORCE_GRENADE_MIN           2u   /* never adjacent */
#define FORCE_GRENADE_BLAST         2u   /* Chebyshev splash disk */
#define FORCE_GRENADE_DMG           8u
#define FORCE_GRENADE_FX_TTL        4u   /* logic ticks of colour flash */
#define FORCE_GRENADE_BANK          2u
#define FORCE_FX_HURT               1u   /* low nibble: 1 logic tick */
#define FORCE_FX_MUZZLE            16u   /* high nibble reserved */
#define FORCE_STEP_FAR             16u
#define FORCE_STEP_CAP             8u
#define FORCE_SECTION_FLAG_NOPATH         0x01u
#define FORCE_SECTION_FLAG_COVER_ASSIGN   0x02u
#define FORCE_SECTION_FLAG_COVER_RELEASE  0x04u
#define FORCE_SECTION_FLAG_BREAKING       0x08u
#define FORCE_SECTION_FLAG_CONTACT        0x10u
#define FORCE_GLYPH_ENEMY_E               10u

#ifndef FORCE_FOG
#define FORCE_FOG                  0   /* 1 = hide unseen rooms; intel still runs at 0 */
#endif
#define FORCE_ROOM_SEEN            0x01u
#define FORCE_ROOM_LIVE            0x02u
#define FORCE_ROOM_HOME            0x04u
#define FORCE_ROOM_MARK            0x08u
#define FORCE_HEAT_START           8u
#define FORCE_FOCUS_TICKS          16u /* logic ticks per F FORCE nibble */

#define FORCE_SCRIPT_WHO_PLAYER    0xFFu
#define FORCE_SCRIPT_PLAYING       0u
#define FORCE_SCRIPT_WIN           1u
#define FORCE_SCRIPT_LOSE          2u

#if (FORCE_COVER_MAX + FORCE_SCOUT_MAX) >= 0xFF
#error "unit_cover packs cover 0..COVER_MAX-1, scout COVER_MAX+i, $FF none"
#endif

#define FORCE_APPROACH_N  0x01u
#define FORCE_APPROACH_E  0x02u
#define FORCE_APPROACH_S  0x04u
#define FORCE_APPROACH_W  0x08u

#if FORCE_FACE_S == FORCE_APPROACH_S
#error "FORCE_FACE_S (enum 3) must not equal FORCE_APPROACH_S (bit 0x04)"
#endif

enum force_verb {
    FORCE_VERB_NONE    = 0,  /* never ordered this mission */
    FORCE_VERB_MOVE    = 1,  /* M */
    FORCE_VERB_DEFEND  = 2,  /* D */
    FORCE_VERB_HALT    = 3,  /* H */
    FORCE_VERB_ATTACK  = 4,  /* A */
    FORCE_VERB_RETREAT = 5,  /* R */
    FORCE_VERB_KILL    = 6,  /* K */
    FORCE_VERB_SPLIT   = 7,  /* S — wizard only */
    FORCE_VERB_JOIN    = 8,  /* J — wizard only */
    FORCE_VERB_FOCUS   = 9,  /* F — wizard, skip WHO */
    FORCE_VERB_BUILD   = 10  /* B — section order; not a script nibble */
};

enum force_unit_kind {
    FORCE_KIND_INFANTRY = 0,
    FORCE_KIND_VEHICLE,
    FORCE_KIND_EMPLACEMENT
};

typedef struct force_world {
    uint8_t  width;
    uint8_t  height;
    uint8_t  play_x; /* mission rect; scroll, F, and exit-* stay inside */
    uint8_t  play_y;
    uint8_t  play_w;
    uint8_t  play_h;
    uint8_t  win_x;
    uint8_t  win_y;
    uint8_t  win_w;
    uint8_t  win_h;

    uint16_t row_off[FORCE_MAP_H_MAX];

    uint8_t  tiles[FORCE_MAP_CELLS_MAX];
    uint8_t  color[FORCE_MAP_CELLS_MAX];   /* SDL; Phase 10 drops this 4K */

    uint8_t  room_count;
    uint8_t  room_x0[FORCE_ROOM_MAX];
    uint8_t  room_y0[FORCE_ROOM_MAX];
    uint8_t  room_w[FORCE_ROOM_MAX];
    uint8_t  room_h[FORCE_ROOM_MAX];
    uint8_t  room_colour[FORCE_ROOM_MAX];
    uint8_t  room_cover_base[FORCE_ROOM_MAX];
    uint8_t  room_cover_count[FORCE_ROOM_MAX];
    uint8_t  room_scout_base[FORCE_ROOM_MAX];
    uint8_t  room_scout_count[FORCE_ROOM_MAX];

    uint8_t  cover_count;
    uint8_t  cover_x[FORCE_COVER_MAX];
    uint8_t  cover_y[FORCE_COVER_MAX];
    uint8_t  cover_grade[FORCE_COVER_MAX];
    uint8_t  cover_facing[FORCE_COVER_MAX];  /* pole / soft / hard tag */

    uint8_t  portal_count;
    uint8_t  portal_x[FORCE_PORTAL_MAX];
    uint8_t  portal_y[FORCE_PORTAL_MAX];

    uint8_t  scout_count;
    uint8_t  scout_x[FORCE_SCOUT_MAX];
    uint8_t  scout_y[FORCE_SCOUT_MAX];
    uint8_t  scout_facing[FORCE_SCOUT_MAX];

    uint8_t  objective_count;
    uint8_t  objective_x[FORCE_OBJECTIVE_MAX];
    uint8_t  objective_y[FORCE_OBJECTIVE_MAX];

    uint8_t  mine_count;
    uint8_t  mine_x[FORCE_MINE_MAX];
    uint8_t  mine_y[FORCE_MINE_MAX];

    uint8_t  deck_count;
    uint8_t  deck_x[FORCE_DECK_MAX];
    uint8_t  deck_y[FORCE_DECK_MAX];
    uint8_t  deck_prog[FORCE_DECK_MAX]; /* 0xFF = that plank is finished */
    uint8_t  deck_cost;                  /* 0 = pour nothing and finish nothing */

    uint8_t  unit_x[FORCE_UNIT_MAX];
    uint8_t  unit_y[FORCE_UNIT_MAX];
    uint8_t  unit_section[FORCE_UNIT_MAX];
    uint8_t  unit_count[FORCE_UNIT_MAX];  /* stack size; 0 = free */
    uint8_t  unit_kind[FORCE_UNIT_MAX];
    uint8_t  unit_glyph[FORCE_UNIT_MAX];
    uint8_t  unit_region[FORCE_UNIT_MAX];
    uint8_t  unit_cover[FORCE_UNIT_MAX];
    uint8_t  unit_over_verb[FORCE_UNIT_MAX];  /* 0 = none */
    uint8_t  unit_over_x[FORCE_UNIT_MAX];
    uint8_t  unit_over_y[FORCE_UNIT_MAX];
    uint8_t  unit_built_x[FORCE_UNIT_MAX]; /* 0xFF = this man has poured nothing */
    uint8_t  unit_built_y[FORCE_UNIT_MAX];

    uint8_t  section_lead[FORCE_SECTION_MAX];
    uint8_t  section_last_x[FORCE_SECTION_MAX];
    uint8_t  section_last_y[FORCE_SECTION_MAX];
    uint8_t  section_strength[FORCE_SECTION_MAX];
    uint8_t  section_flags[FORCE_SECTION_MAX];
    uint8_t  section_order_verb[FORCE_SECTION_MAX];
    uint8_t  section_order_x[FORCE_SECTION_MAX];
    uint8_t  section_order_y[FORCE_SECTION_MAX];
    uint8_t  section_order_force[FORCE_SECTION_MAX];

    uint8_t  unit_tgt_x[FORCE_UNIT_MAX];
    uint8_t  unit_tgt_y[FORCE_UNIT_MAX];
    uint8_t  unit_step_sx[FORCE_UNIT_MAX];  /* 1, 0, or 0xFF = -1 */
    uint8_t  unit_step_sy[FORCE_UNIT_MAX];
    uint8_t  unit_step_ax[FORCE_UNIT_MAX];
    uint8_t  unit_step_ay[FORCE_UNIT_MAX];
    uint8_t  unit_step_err[FORCE_UNIT_MAX];
    uint8_t  unit_step_run[FORCE_UNIT_MAX];
    uint8_t  unit_move_wait[FORCE_UNIT_MAX];
    uint8_t  portal_from[FORCE_PORTAL_MAX];
    uint8_t  portal_to[FORCE_PORTAL_MAX];
    uint8_t  next_hop[FORCE_ROOM_MAX * FORCE_ROOM_MAX]; /* first neighbour room */
    uint8_t  path_fail_who;
    uint8_t  room_approach[FORCE_ROOM_MAX];
    uint8_t  room_axis[FORCE_ROOM_MAX];
    uint8_t  room_cover_lo[FORCE_ROOM_MAX];
    uint8_t  room_cover_none[FORCE_ROOM_MAX];
    uint8_t  room_cover_hi[FORCE_ROOM_MAX];
    uint8_t  room_flags[FORCE_ROOM_MAX]; /* SEEN LIVE HOME MARK */
    uint8_t  room_heat[FORCE_ROOM_MAX];
    uint8_t  last_x[FORCE_ROOM_MAX];
    uint8_t  last_y[FORCE_ROOM_MAX];

    uint8_t  unit_hp[FORCE_UNIT_MAX];
    uint8_t  unit_fire_wait[FORCE_UNIT_MAX];
    uint8_t  unit_fx[FORCE_UNIT_MAX];   /* lo: hurt; hi reserved */
    uint8_t  shot_this_tick;
    uint8_t  grenade_rem[FORCE_GRENADE_BANK];
    uint8_t  grenade_wait[FORCE_GRENADE_BANK];
    uint8_t  nade_fx_x[FORCE_GRENADE_BANK];
    uint8_t  nade_fx_y[FORCE_GRENADE_BANK];
    uint8_t  nade_fx_ttl[FORCE_GRENADE_BANK];
    uint8_t  section_order_str[FORCE_SECTION_MAX];

    const force_script *script;
    uint8_t  script_pc;
    uint8_t  script_waiting;
    uint8_t  script_wait_pred0;
    uint8_t  script_wait_pred1;
    uint8_t  script_wait_beat;
    uint8_t  spawn_room;
    uint8_t  spawn_job_rem;
    uint8_t  spawn_job_letter;
    uint8_t  spawn_job_room;
    uint8_t  spawn_job_batch;
    uint8_t  spawn_job_period;
    uint8_t  spawn_job_wait;
    uint8_t  script_fired;
    uint16_t script_clock;
    uint8_t  script_outcome;
} force_world;

extern force_world force_world_bss;

void force_copy_u8(uint8_t *dst, const uint8_t *src, uint16_t n);
void force_world_load(force_world *world, const force_mission *mission);
void force_world_clamp_play(const force_world *world, uint8_t *x, uint8_t *y);
uint8_t force_unit_spawn(force_world *world,
                         uint8_t x, uint8_t y,
                         uint8_t section, uint8_t kind,
                         uint8_t count, uint8_t glyph);
void force_section_recount(force_world *world);
void force_section_relead(force_world *world, uint8_t who);
void force_section_issue(force_world *world, uint8_t who,
                         uint8_t verb, uint8_t x, uint8_t y,
                         uint8_t force);
int force_cell_is_deck(const force_world *world, uint8_t x, uint8_t y);
int force_section_peel(force_world *world,
                       uint8_t src, uint8_t dst,
                       uint8_t first, uint8_t n);
int force_section_join(force_world *world, uint8_t src, uint8_t dst);
int force_unit_nudge(force_world *world, uint8_t i,
                     uint8_t verb, uint8_t x, uint8_t y);
void force_world_tick(force_world *world);
void force_cover_release(force_world *world, uint8_t who);
void force_cover_assign(force_world *world, uint8_t who);
int force_grenade_fx_at(const force_world *w, uint8_t x, uint8_t y);
int force_room_seen(const force_world *w, uint8_t r);
int force_room_enemy_visible(const force_world *w, uint8_t r);
uint8_t force_intel_next_hot(const force_world *w, uint8_t prev);
uint8_t force_intel_next_mark(const force_world *w, uint8_t prev);
uint8_t force_intel_player_in_room(const force_world *w, uint8_t r);

#endif
