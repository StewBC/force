#ifndef FORCE_GAME_H
#define FORCE_GAME_H

#include "core/types.h"
#include "generated/force_data.h"

typedef struct force_game {
    force_screen screen;
    uint32_t pixels[FORCE_FB_W * FORCE_FB_H];
    const force_mission *mission;
    int cursor_x;
    int cursor_y;
    uint32_t frames;
    bool joy_present;
} force_game;

void force_game_init(force_game *g);
void force_game_tick(force_game *g, const force_input *in);
void force_game_draw(force_game *g);

#endif
