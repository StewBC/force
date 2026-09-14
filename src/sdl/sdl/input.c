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
    in->stick_latched = false;
    in->cmd_kind = FORCE_CMD_NONE;
    in->cmd_value = 0;
}

void force_input_poll(force_input *in, SDL_Gamepad *pad, SDL_Joystick *joy)
{
    const bool *key;
    int kdx = 0;
    int kdy = 0;
    int sdx = 0;
    int sdy = 0;
    int dx;
    int dy;
    bool fire;
    bool shift;
    uint32_t letters = 0u;
    uint16_t digits = 0u;
    uint8_t misc = 0u;
    int i;
    static int hold;
    static int last_dx;
    static int last_dy;
    static bool stick_latched;
    static SDL_Gamepad *prev_pad;
    static SDL_Joystick *prev_joy;
    static uint32_t prev_letters;
    static uint16_t prev_digits;
    static uint8_t prev_misc;

    key = SDL_GetKeyboardState(NULL);
    shift = (SDL_GetModState() & SDL_KMOD_SHIFT) != 0;

    if ((pad == NULL && joy == NULL) ||
        pad != prev_pad || joy != prev_joy) {
        stick_latched = false;
    }
    prev_pad = pad;
    prev_joy = joy;

    in->joy_present = (pad != NULL || joy != NULL);

    if (key[SDL_SCANCODE_LEFT]) {
        kdx -= 1;
    }
    if (key[SDL_SCANCODE_RIGHT]) {
        kdx += 1;
    }
    if (key[SDL_SCANCODE_UP]) {
        kdy -= 1;
    }
    if (key[SDL_SCANCODE_DOWN]) {
        kdy += 1;
    }
    if (!stick_latched && !shift) {
        if (key[SDL_SCANCODE_A]) {
            kdx -= 1;
        }
        if (key[SDL_SCANCODE_D]) {
            kdx += 1;
        }
        if (key[SDL_SCANCODE_W]) {
            kdy -= 1;
        }
        if (key[SDL_SCANCODE_S]) {
            kdy += 1;
        }
    }

    if (pad != NULL) {
        Sint16 ax = SDL_GetGamepadAxis(pad, SDL_GAMEPAD_AXIS_LEFTX);
        Sint16 ay = SDL_GetGamepadAxis(pad, SDL_GAMEPAD_AXIS_LEFTY);

        if (SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_DPAD_LEFT) ||
            ax < -STICK_DEAD) {
            sdx -= 1;
        }
        if (SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_DPAD_RIGHT) ||
            ax > STICK_DEAD) {
            sdx += 1;
        }
        if (SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_DPAD_UP) ||
            ay < -STICK_DEAD) {
            sdy -= 1;
        }
        if (SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_DPAD_DOWN) ||
            ay > STICK_DEAD) {
            sdy += 1;
        }
    } else if (joy != NULL) {
        Sint16 ax = SDL_GetJoystickAxis(joy, 0);
        Sint16 ay = SDL_GetJoystickAxis(joy, 1);
        Uint8 hat = 0;

        if (SDL_GetNumJoystickHats(joy) > 0) {
            hat = SDL_GetJoystickHat(joy, 0);
        }
        if ((hat & SDL_HAT_LEFT) || ax < -STICK_DEAD) {
            sdx -= 1;
        }
        if ((hat & SDL_HAT_RIGHT) || ax > STICK_DEAD) {
            sdx += 1;
        }
        if ((hat & SDL_HAT_UP) || ay < -STICK_DEAD) {
            sdy -= 1;
        }
        if ((hat & SDL_HAT_DOWN) || ay > STICK_DEAD) {
            sdy += 1;
        }
    }
    sdx = clamp_dir(sdx);
    sdy = clamp_dir(sdy);
    if (sdx != 0 || sdy != 0) {
        stick_latched = true;
    }

    dx = clamp_dir(kdx + sdx);
    dy = clamp_dir(kdy + sdy);

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
        if (hold >= REPEAT_DELAY &&
            ((hold - REPEAT_DELAY) % REPEAT_RATE) == 0) {
            fire = true;
        }
    }

    in->cursor_dx = fire ? dx : 0;
    in->cursor_dy = fire ? dy : 0;
    in->stick_latched = stick_latched;

    in->cmd_kind = FORCE_CMD_NONE;
    in->cmd_value = 0;

    if (key[SDL_SCANCODE_RETURN] || key[SDL_SCANCODE_KP_ENTER]) {
        misc |= 1u;
    }
    if (key[SDL_SCANCODE_BACKSPACE] || key[SDL_SCANCODE_DELETE]) {
        misc |= 2u;
    }
    if (key[SDL_SCANCODE_COMMA]) {
        misc |= 4u;
    }
    if (key[SDL_SCANCODE_SPACE]) {
        misc |= 8u;
    }
    {
        static const SDL_Scancode kp[10] = {
            SDL_SCANCODE_KP_0, SDL_SCANCODE_KP_1, SDL_SCANCODE_KP_2,
            SDL_SCANCODE_KP_3, SDL_SCANCODE_KP_4, SDL_SCANCODE_KP_5,
            SDL_SCANCODE_KP_6, SDL_SCANCODE_KP_7, SDL_SCANCODE_KP_8,
            SDL_SCANCODE_KP_9
        };
        for (i = 0; i < 10; ++i) {
            if (key[SDL_SCANCODE_0 + i] || key[kp[i]]) {
                digits = (uint16_t)(digits | (uint16_t)(1u << i));
            }
        }
    }
    for (i = 0; i < 26; ++i) {
        if (key[SDL_SCANCODE_A + i]) {
            letters |= (1u << i);
        }
    }

    if ((misc & 1u) != 0u && (prev_misc & 1u) == 0u) {
        in->cmd_kind = FORCE_CMD_RETURN;
    } else if ((misc & 2u) != 0u && (prev_misc & 2u) == 0u) {
        in->cmd_kind = FORCE_CMD_DEL;
    } else if ((misc & 4u) != 0u && (prev_misc & 4u) == 0u) {
        in->cmd_kind = FORCE_CMD_COMMA;
    } else if ((misc & 8u) != 0u && (prev_misc & 8u) == 0u) {
        in->cmd_kind = FORCE_CMD_SPACE;
    } else {
        for (i = 0; i < 10; ++i) {
            uint16_t bit = (uint16_t)(1u << i);
            if ((digits & bit) != 0u && (prev_digits & bit) == 0u) {
                in->cmd_kind = FORCE_CMD_DIGIT;
                in->cmd_value = (uint8_t)i;
                break;
            }
        }
        if (in->cmd_kind == FORCE_CMD_NONE) {
            for (i = 0; i < 26; ++i) {
                uint32_t bit = (1u << i);
                if ((letters & bit) != 0u && (prev_letters & bit) == 0u) {
                    if (stick_latched || shift) {
                        in->cmd_kind = FORCE_CMD_LETTER;
                        in->cmd_value = (uint8_t)i;
                    }
                    break;
                }
            }
        }
    }

    prev_letters = letters;
    prev_digits = digits;
    prev_misc = misc;
}
