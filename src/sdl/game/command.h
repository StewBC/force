#ifndef FORCE_COMMAND_H
#define FORCE_COMMAND_H

#include "game/game.h"

void force_command_init(force_game *g);
void force_command_feed(force_game *g, const force_input *in);
void force_command_paint(force_game *g);
uint8_t force_command_implied_who(const force_game *g);

#endif
