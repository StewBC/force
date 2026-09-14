#ifndef FORCE_GAME_H
#define FORCE_GAME_H

#include "core/types.h"
#include "game/world.h"

enum force_cmd_slot {
    FORCE_SLOT_IDLE = 0,   /* waiting for verb; READY */
    FORCE_SLOT_WHO,
    FORCE_SLOT_WHERE_X,
    FORCE_SLOT_WHERE_Y,
    FORCE_SLOT_FORCE,
    FORCE_SLOT_SHOW        /* committed line on row 21 */
};

typedef struct force_game {
    force_screen screen;
    uint32_t pixels[FORCE_FB_W * FORCE_FB_H];
    const force_mission *mission;   /* name / identity only after load */
    force_world *world;             /* &force_world_bss */
    int cursor_x;
    int cursor_y;
    uint32_t frames;
    bool joy_present;
    bool stick_latched;
    uint8_t cmd_verb;
    uint8_t cmd_who;       /* 0-7 or FORCE_UNIT_NONE */
    uint8_t cmd_x;
    uint8_t cmd_y;
    uint8_t cmd_force;     /* 0-10; 0xFF unset */
    uint8_t cmd_slot;      /* enum force_cmd_slot */
    uint8_t cmd_digits;    /* 0-2 in the current number */
    uint8_t cmd_last_who;  /* 0-7 or FORCE_UNIT_NONE */
    uint8_t cmd_flash;     /* 0 = off */
    uint8_t cmd_nopath;    /* 1 → row 21 paints NO PATH while flash > 0 */
} force_game;

void force_game_init(force_game *g);
void force_game_tick(force_game *g, const force_input *in);
void force_game_draw(force_game *g);

#endif
