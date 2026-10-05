#include "sdl/host.h"

#include "sdl/input.h"

#include <SDL3/SDL.h>
#include <stdlib.h>

struct force_host {
    SDL_Window *window;
    SDL_Renderer *renderer;
    SDL_Texture *fb;
    SDL_Gamepad *pad;
    SDL_Joystick *joy;
    bool fullscreen;
};

static void close_sticks(force_host *host)
{
    if (host->pad != NULL) {
        SDL_CloseGamepad(host->pad);
        host->pad = NULL;
    }
    if (host->joy != NULL) {
        SDL_CloseJoystick(host->joy);
        host->joy = NULL;
    }
}

static void open_first_stick(force_host *host)
{
    int count = 0;
    SDL_JoystickID *ids;

    if (host->pad != NULL || host->joy != NULL) {
        return;
    }

    ids = SDL_GetGamepads(&count);
    if (ids != NULL && count > 0) {
        host->pad = SDL_OpenGamepad(ids[0]);
        if (host->pad == NULL) {
            SDL_Log("OpenGamepad: %s", SDL_GetError());
        }
    }
    SDL_free(ids);
    if (host->pad != NULL) {
        return;
    }

    ids = SDL_GetJoysticks(&count);
    if (ids != NULL && count > 0) {
        host->joy = SDL_OpenJoystick(ids[0]);
        if (host->joy == NULL) {
            SDL_Log("OpenJoystick: %s", SDL_GetError());
        }
    }
    SDL_free(ids);
}

bool force_host_init(force_host **out)
{
    force_host *host;

    *out = NULL;
    host = calloc(1, sizeof(*host));
    if (host == NULL) {
        SDL_Log("out of memory");
        return false;
    }

    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK | SDL_INIT_GAMEPAD)) {
        SDL_Log("SDL_Init: %s", SDL_GetError());
        free(host);
        return false;
    }

    if (!SDL_CreateWindowAndRenderer(
            "FORCE",
            FORCE_WIN_W,
            FORCE_WIN_H,
            SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY,
            &host->window,
            &host->renderer)) {
        SDL_Log("CreateWindowAndRenderer: %s", SDL_GetError());
        SDL_Quit();
        free(host);
        return false;
    }

    SDL_SetWindowMinimumSize(host->window, FORCE_FB_W, FORCE_FB_H);
    SDL_SetRenderVSync(host->renderer, 1);
    SDL_SetRenderLogicalPresentation(
        host->renderer,
        FORCE_FB_W,
        FORCE_FB_H,
        SDL_LOGICAL_PRESENTATION_INTEGER_SCALE);

    host->fb = SDL_CreateTexture(
        host->renderer,
        SDL_PIXELFORMAT_XRGB8888,
        SDL_TEXTUREACCESS_STREAMING,
        FORCE_FB_W,
        FORCE_FB_H);
    if (host->fb == NULL) {
        SDL_Log("CreateTexture: %s", SDL_GetError());
        SDL_DestroyRenderer(host->renderer);
        SDL_DestroyWindow(host->window);
        SDL_Quit();
        free(host);
        return false;
    }
    SDL_SetTextureScaleMode(host->fb, SDL_SCALEMODE_NEAREST);

    open_first_stick(host);
    *out = host;
    return true;
}

void force_host_shutdown(force_host *host)
{
    if (host == NULL) {
        return;
    }
    close_sticks(host);
    if (host->fb != NULL) {
        SDL_DestroyTexture(host->fb);
    }
    if (host->renderer != NULL) {
        SDL_DestroyRenderer(host->renderer);
    }
    if (host->window != NULL) {
        SDL_DestroyWindow(host->window);
    }
    SDL_Quit();
    free(host);
}

bool force_host_pump(force_host *host, force_input *in)
{
    SDL_Event e;

    force_input_reset(in);

    while (SDL_PollEvent(&e)) {
        switch (e.type) {
        case SDL_EVENT_QUIT:
            in->quit = true;
            break;
        case SDL_EVENT_KEY_DOWN:
            if (e.key.repeat) {
                break;
            }
            if (e.key.key == SDLK_F11) {
                in->toggle_fullscreen = true;
            } else if (e.key.key == SDLK_F3) {
                in->restart = true;
            } else if (e.key.key == SDLK_F8) {
                in->f8 = true;
            }
            break;
        case SDL_EVENT_GAMEPAD_ADDED:
            if (host->pad == NULL) {
                if (host->joy != NULL) {
                    SDL_CloseJoystick(host->joy);
                    host->joy = NULL;
                }
                host->pad = SDL_OpenGamepad(e.gdevice.which);
            }
            break;
        case SDL_EVENT_GAMEPAD_REMOVED:
            if (host->pad != NULL && e.gdevice.which == SDL_GetGamepadID(host->pad)) {
                close_sticks(host);
                open_first_stick(host);
            }
            break;
        case SDL_EVENT_JOYSTICK_ADDED:
            open_first_stick(host);
            break;
        case SDL_EVENT_JOYSTICK_REMOVED:
            if (host->joy != NULL && e.jdevice.which == SDL_GetJoystickID(host->joy)) {
                close_sticks(host);
                open_first_stick(host);
            }
            break;
        default:
            break;
        }
    }

    if (in->toggle_fullscreen) {
        host->fullscreen = !host->fullscreen;
        SDL_SetWindowFullscreen(host->window, host->fullscreen);
    }

    if (in->quit) {
        return false;
    }

    force_input_poll(in, host->pad, host->joy);
    return true;
}

void force_host_sync_input(force_host *host)
{
    force_input ignored;

    if (host == NULL) {
        return;
    }
    force_input_poll(&ignored, host->pad, host->joy);
}

bool force_host_wait_key(force_host *host, const uint32_t *pixels)
{
    SDL_Event e;

    force_host_present(host, pixels);
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_EVENT_QUIT) {
            return false;
        }
    }

    for (;;) {
        force_host_present(host, pixels);
        if (!SDL_WaitEventTimeout(&e, 16)) {
            continue;
        }
        do {
            if (e.type == SDL_EVENT_QUIT) {
                return false;
            }
            if (e.type == SDL_EVENT_KEY_DOWN && !e.key.repeat) {
                return true;
            }
        } while (SDL_PollEvent(&e));
    }
}

void force_host_present(force_host *host, const uint32_t *pixels)
{
    SDL_UpdateTexture(host->fb, NULL, pixels, FORCE_FB_W * (int)sizeof(uint32_t));
    SDL_SetRenderDrawColor(host->renderer, 0, 0, 0, 255);
    SDL_RenderClear(host->renderer);
    SDL_RenderTexture(host->renderer, host->fb, NULL, NULL);
    SDL_RenderPresent(host->renderer);
}
