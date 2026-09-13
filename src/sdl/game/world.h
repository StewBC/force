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

#define FORCE_UNIT_NONE  0xFFu

enum force_unit_kind {
    FORCE_KIND_INFANTRY = 0,
    FORCE_KIND_VEHICLE,
    FORCE_KIND_EMPLACEMENT
};

typedef struct force_world {
    uint8_t  width;
    uint8_t  height;
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
    uint8_t  cover_facing[FORCE_COVER_MAX];

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

    uint8_t  unit_x[FORCE_UNIT_MAX];
    uint8_t  unit_y[FORCE_UNIT_MAX];
    uint8_t  unit_section[FORCE_UNIT_MAX];
    uint8_t  unit_count[FORCE_UNIT_MAX];  /* stack size; 0 = free */
    uint8_t  unit_kind[FORCE_UNIT_MAX];
    uint8_t  unit_glyph[FORCE_UNIT_MAX];
    uint8_t  unit_region[FORCE_UNIT_MAX];
    uint8_t  unit_cover[FORCE_UNIT_MAX];

    uint8_t  section_lead[FORCE_SECTION_MAX];
    uint8_t  section_last_x[FORCE_SECTION_MAX];
    uint8_t  section_last_y[FORCE_SECTION_MAX];
    uint8_t  section_strength[FORCE_SECTION_MAX];
    uint8_t  section_flags[FORCE_SECTION_MAX];
    uint8_t  section_order_verb[FORCE_SECTION_MAX];
    uint8_t  section_order_x[FORCE_SECTION_MAX];
    uint8_t  section_order_y[FORCE_SECTION_MAX];
    uint8_t  section_order_force[FORCE_SECTION_MAX];
} force_world;

extern force_world force_world_bss;

void force_copy_u8(uint8_t *dst, const uint8_t *src, uint16_t n);
void force_world_load(force_world *world, const force_mission *mission);
uint8_t force_unit_spawn(force_world *world,
                         uint8_t x, uint8_t y,
                         uint8_t section, uint8_t kind,
                         uint8_t count, uint8_t glyph);
void force_section_recount(force_world *world);

#endif
