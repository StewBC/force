#include "sdl/input.h"

#include <SDL3/SDL.h>

#define REPEAT_DELAY 14
#define REPEAT_RATE  4
#define STICK_DEAD   16000

static int clamp_dir(int v)
{
    if (v < -1) {
        return -1;
    }
    if (v > 1) {
        return 1;
    }
    return v;
}

void force_input_reset(force_input *in)
{
    in->cursor_dx = 0;
    in->cursor_dy = 0;
    in->quit = false;
    in->toggle_fullscreen = false;
    in->joy_present = false;
}

void force_input_poll(force_input *in, SDL_Gamepad *pad, SDL_Joystick *joy)
{
    const bool *key;
    int dx = 0;
    int dy = 0;
    static int hold;
    static int last_dx;
    static int last_dy;
    bool fire;

    key = SDL_GetKeyboardState(NULL);

    if (key[SDL_SCANCODE_LEFT] || key[SDL_SCANCODE_A]) {
        dx -= 1;
    }
    if (key[SDL_SCANCODE_RIGHT] || key[SDL_SCANCODE_D]) {
        dx += 1;
    }
    if (key[SDL_SCANCODE_UP] || key[SDL_SCANCODE_W]) {
        dy -= 1;
    }
    if (key[SDL_SCANCODE_DOWN] || key[SDL_SCANCODE_S]) {
        dy += 1;
    }

    in->joy_present = (pad != NULL || joy != NULL);
    if (pad != NULL) {
        Sint16 ax = SDL_GetGamepadAxis(pad, SDL_GAMEPAD_AXIS_LEFTX);
        Sint16 ay = SDL_GetGamepadAxis(pad, SDL_GAMEPAD_AXIS_LEFTY);

        if (SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_DPAD_LEFT) || ax < -STICK_DEAD) {
            dx -= 1;
        }
        if (SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_DPAD_RIGHT) || ax > STICK_DEAD) {
            dx += 1;
        }
        if (SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_DPAD_UP) || ay < -STICK_DEAD) {
            dy -= 1;
        }
        if (SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_DPAD_DOWN) || ay > STICK_DEAD) {
            dy += 1;
        }
    } else if (joy != NULL) {
        Sint16 ax = SDL_GetJoystickAxis(joy, 0);
        Sint16 ay = SDL_GetJoystickAxis(joy, 1);
        Uint8 hat = 0;

        if (SDL_GetNumJoystickHats(joy) > 0) {
            hat = SDL_GetJoystickHat(joy, 0);
        }
        if ((hat & SDL_HAT_LEFT) || ax < -STICK_DEAD) {
            dx -= 1;
        }
        if ((hat & SDL_HAT_RIGHT) || ax > STICK_DEAD) {
            dx += 1;
        }
        if ((hat & SDL_HAT_UP) || ay < -STICK_DEAD) {
            dy -= 1;
        }
        if ((hat & SDL_HAT_DOWN) || ay > STICK_DEAD) {
            dy += 1;
        }
    }

    dx = clamp_dir(dx);
    dy = clamp_dir(dy);

    fire = false;
    if (dx == 0 && dy == 0) {
        hold = 0;
    } else if (hold == 0 || dx != last_dx || dy != last_dy) {
        fire = true;
        hold = 1;
        last_dx = dx;
        last_dy = dy;
    } else {
        hold += 1;
        if (hold >= REPEAT_DELAY && ((hold - REPEAT_DELAY) % REPEAT_RATE) == 0) {
            fire = true;
        }
    }

    in->cursor_dx = fire ? dx : 0;
    in->cursor_dy = fire ? dy : 0;
}
