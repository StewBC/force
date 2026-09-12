#ifndef FORCE_INPUT_H
#define FORCE_INPUT_H

#include "core/types.h"

struct SDL_Gamepad;
struct SDL_Joystick;

void force_input_reset(force_input *in);
void force_input_poll(force_input *in, struct SDL_Gamepad *pad, struct SDL_Joystick *joy);

#endif
