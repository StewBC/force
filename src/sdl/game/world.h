#ifndef FORCE_WORLD_H
#define FORCE_WORLD_H

#include "generated/force_data.h"

#if (FORCE_MAP_W_MAX * FORCE_MAP_H_MAX) != FORCE_MAP_CELLS_MAX
#error "FORCE_MAP_CELLS_MAX must equal FORCE_MAP_W_MAX * FORCE_MAP_H_MAX"
#endif

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

    uint8_t  spawn_count;
    uint8_t  spawn_x[FORCE_SPAWN_MAX];
    uint8_t  spawn_y[FORCE_SPAWN_MAX];
    uint8_t  spawn_tile[FORCE_SPAWN_MAX];

    uint8_t  objective_count;
    uint8_t  objective_x[FORCE_OBJECTIVE_MAX];
    uint8_t  objective_y[FORCE_OBJECTIVE_MAX];

    uint8_t  mine_count;
    uint8_t  mine_x[FORCE_MINE_MAX];
    uint8_t  mine_y[FORCE_MINE_MAX];
} force_world;

extern force_world force_world_bss;

void force_copy_u8(uint8_t *dst, const uint8_t *src, uint16_t n);
void force_world_load(force_world *world, const force_mission *mission);

#endif
