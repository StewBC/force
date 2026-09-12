#include "game/game.h"
#include "sdl/host.h"

#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
    const int smoke = (argc > 1 && strcmp(argv[1], "--smoke") == 0);
    force_host *host = NULL;
    force_game game;
    force_input input;

    if (!force_host_init(&host)) {
        fprintf(stderr, "FORCE: failed to open an SDL window\n");
        return 1;
    }

    force_game_init(&game);

    while (force_host_pump(host, &input)) {
        force_game_tick(&game, &input);
        force_game_draw(&game);
        force_host_present(host, &game.screen);
        if (smoke) {
            break;
        }
    }

    force_host_shutdown(host);
    return 0;
}
