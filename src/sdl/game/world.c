#include "game/world.h"

#include <string.h>

force_world force_world_bss;

void force_copy_u8(uint8_t *dst, const uint8_t *src, uint16_t n)
{
    if (n == 0u) {
        return;
    }
    memcpy(dst, src, (size_t)n);
}

static void zero_u8(uint8_t *dst, uint16_t n)
{
    uint16_t i;
    for (i = 0; i < n; ++i) {
        dst[i] = 0u;
    }
}

static void copy_column(uint8_t *dst, const uint8_t *src,
                        uint8_t count, uint16_t cap)
{
    if (count > 0u) {
        force_copy_u8(dst, src, (uint16_t)count);
    }
    if ((uint16_t)count < cap) {
        zero_u8(dst + count, (uint16_t)(cap - (uint16_t)count));
    }
}

void force_world_load(force_world *world, const force_mission *mission)
{
    const force_map *map = mission->map;
    uint8_t width;
    uint8_t height;
    uint16_t y;
    uint16_t cells;

    world->width = (uint8_t)map->width;
    world->height = (uint8_t)map->height;
    world->win_x = (uint8_t)mission->x;
    world->win_y = (uint8_t)mission->y;
    world->win_w = (uint8_t)mission->w;
    world->win_h = (uint8_t)mission->h;

    width = world->width;
    height = world->height;

    for (y = 0u; y < (uint16_t)height; ++y) {
        world->row_off[y] = y * (uint16_t)width;
    }
    for (y = (uint16_t)height; y < (uint16_t)FORCE_MAP_H_MAX; ++y) {
        world->row_off[y] = 0u;
    }

    cells = (uint16_t)width * (uint16_t)height;
    force_copy_u8(world->tiles, map->tiles, cells);
    if (cells < (uint16_t)FORCE_MAP_CELLS_MAX) {
        zero_u8(world->tiles + cells,
                (uint16_t)FORCE_MAP_CELLS_MAX - cells);
    }
    force_copy_u8(world->color, map->color, cells);
    if (cells < (uint16_t)FORCE_MAP_CELLS_MAX) {
        zero_u8(world->color + cells,
                (uint16_t)FORCE_MAP_CELLS_MAX - cells);
    }

    world->room_count = map->room_count;
    copy_column(world->room_x0, map->room_x0, map->room_count, FORCE_ROOM_MAX);
    copy_column(world->room_y0, map->room_y0, map->room_count, FORCE_ROOM_MAX);
    copy_column(world->room_w, map->room_w, map->room_count, FORCE_ROOM_MAX);
    copy_column(world->room_h, map->room_h, map->room_count, FORCE_ROOM_MAX);
    copy_column(world->room_colour, map->room_colour, map->room_count,
                FORCE_ROOM_MAX);
    copy_column(world->room_cover_base, map->room_cover_base, map->room_count,
                FORCE_ROOM_MAX);
    copy_column(world->room_cover_count, map->room_cover_count, map->room_count,
                FORCE_ROOM_MAX);
    copy_column(world->room_scout_base, map->room_scout_base, map->room_count,
                FORCE_ROOM_MAX);
    copy_column(world->room_scout_count, map->room_scout_count, map->room_count,
                FORCE_ROOM_MAX);

    world->cover_count = map->cover_count;
    copy_column(world->cover_x, map->cover_x, map->cover_count, FORCE_COVER_MAX);
    copy_column(world->cover_y, map->cover_y, map->cover_count, FORCE_COVER_MAX);
    copy_column(world->cover_grade, map->cover_grade, map->cover_count,
                FORCE_COVER_MAX);
    copy_column(world->cover_facing, map->cover_facing, map->cover_count,
                FORCE_COVER_MAX);

    world->portal_count = map->portal_count;
    copy_column(world->portal_x, map->portal_x, map->portal_count,
                FORCE_PORTAL_MAX);
    copy_column(world->portal_y, map->portal_y, map->portal_count,
                FORCE_PORTAL_MAX);

    world->scout_count = map->scout_count;
    copy_column(world->scout_x, map->scout_x, map->scout_count, FORCE_SCOUT_MAX);
    copy_column(world->scout_y, map->scout_y, map->scout_count, FORCE_SCOUT_MAX);
    copy_column(world->scout_facing, map->scout_facing, map->scout_count,
                FORCE_SCOUT_MAX);

    world->spawn_count = map->spawn_count;
    copy_column(world->spawn_x, map->spawn_x, map->spawn_count, FORCE_SPAWN_MAX);
    copy_column(world->spawn_y, map->spawn_y, map->spawn_count, FORCE_SPAWN_MAX);
    copy_column(world->spawn_tile, map->spawn_tile, map->spawn_count,
                FORCE_SPAWN_MAX);

    world->objective_count = map->objective_count;
    copy_column(world->objective_x, map->objective_x, map->objective_count,
                FORCE_OBJECTIVE_MAX);
    copy_column(world->objective_y, map->objective_y, map->objective_count,
                FORCE_OBJECTIVE_MAX);

    world->mine_count = map->mine_count;
    copy_column(world->mine_x, map->mine_x, map->mine_count, FORCE_MINE_MAX);
    copy_column(world->mine_y, map->mine_y, map->mine_count, FORCE_MINE_MAX);
}
