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
    uint8_t cmd_dot;       /* 1 = WHO is period */
    uint8_t cmd_unit;      /* 0-31 snapshot, or FORCE_UNIT_NONE */
    uint8_t cmd_x;
    uint8_t cmd_y;
    uint8_t cmd_force;     /* 0-10; 0xFF unset */
    uint8_t cmd_slot;      /* enum force_cmd_slot */
    uint8_t cmd_digits;    /* 0-2 in the current number */
    uint8_t cmd_last_who;  /* 0-7 or FORCE_UNIT_NONE */
    uint8_t cmd_flash;     /* 0 = off */
    uint8_t cmd_nopath;    /* 1 → row 21 paints NO PATH while flash > 0 */
    uint8_t cam_prev_ok;
    uint8_t cam_prev_x;
    uint8_t cam_prev_y;
    uint8_t cam_prev_cx;
    uint8_t cam_prev_cy;
    uint8_t cam_ttl;       /* logic ticks; 0 = stay */
    uint8_t cycle_kind;    /* 0 none, 1 contact, 2 mark */
    uint8_t cycle_room;    /* 0..15 or 0xFF */
    uint8_t score_snap;    /* 1 once the win tick stored snap_score */
    uint8_t snap_score;    /* living player strength, 0..99 */
    uint8_t leave;         /* 1 = RETURN on the outcome banner */
} force_game;

void force_game_init(force_game *g);
void force_game_begin(force_game *g, const force_mission *mission);
void force_game_tick(force_game *g, const force_input *in);
void force_game_draw(force_game *g);
void force_game_cursor_cell(const force_game *g, uint8_t *mx, uint8_t *my);
void force_game_cursor_span(const force_game *g,
                            uint8_t *x0, uint8_t *y0,
                            uint8_t *x1, uint8_t *y1);
void force_game_camera_focus(force_game *g, uint8_t mx, uint8_t my);
int force_game_camera_back(force_game *g);

#endif
