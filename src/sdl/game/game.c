#include "game/game.h"

#include "core/screen.h"

#include <stdio.h>

void force_game_init(force_game *g)
{
    g->cursor_x = FORCE_COLS / 2;
    g->cursor_y = FORCE_FIELD_ROWS / 2;
    g->frames = 0;
    g->joy_present = false;
}

void force_game_tick(force_game *g, const force_input *in)
{
    g->cursor_x += in->cursor_dx;
    g->cursor_y += in->cursor_dy;
    if (g->cursor_x < 0) {
        g->cursor_x = 0;
    }
    if (g->cursor_x >= FORCE_COLS) {
        g->cursor_x = FORCE_COLS - 1;
    }
    if (g->cursor_y < 0) {
        g->cursor_y = 0;
    }
    if (g->cursor_y >= FORCE_FIELD_ROWS) {
        g->cursor_y = FORCE_FIELD_ROWS - 1;
    }
    g->joy_present = in->joy_present;
    g->frames += 1;
}

void force_game_draw(force_game *g)
{
    force_screen *s = &g->screen;
    char line[FORCE_COLS + 1];
    const bool blink = ((g->frames / 30u) & 1u) != 0u;
    int x, y;

    /* Playfield: rows 0-19, C64 blue / light-blue. */
    force_screen_fill(s, 0, 0, FORCE_COLS, FORCE_FIELD_ROWS,
                      ' ', FORCE_LIGHT_BLUE, FORCE_BLUE);
    for (y = 0; y < FORCE_FIELD_ROWS; y += 2) {
        for (x = 0; x < FORCE_COLS; x += 2) {
            force_screen_putc(s, x, y, '.', FORCE_DARK_GREY, FORCE_BLUE);
        }
    }

    force_screen_puts(s, 2, 1, "FORCE", FORCE_YELLOW, FORCE_BLUE);
    force_screen_puts(s, 2, 3, "WASD / arrows / stick move the cursor",
                      FORCE_LIGHT_BLUE, FORCE_BLUE);
    force_screen_puts(s, 2, 4, "ESC or Q quits    F11 fullscreen",
                      FORCE_CYAN, FORCE_BLUE);

    if (blink) {
        force_screen_putc(s, g->cursor_x, g->cursor_y, ' ', FORCE_BLACK, FORCE_YELLOW);
    } else {
        force_screen_putc(s, g->cursor_x, g->cursor_y, '+', FORCE_YELLOW, FORCE_BLUE);
    }

    /* Command strip: rows 20-23 — the portable 4-line UI. */
    force_screen_fill(s, 0, FORCE_FIELD_ROWS, FORCE_COLS, 4,
                      ' ', FORCE_WHITE, FORCE_BLACK);
    force_screen_puts(s, 1, 20, "VERB   WHO   WHERE   FORCE", FORCE_YELLOW, FORCE_BLACK);
    force_screen_puts(s, 1, 21, "READY", FORCE_LIGHT_GREEN, FORCE_BLACK);
    (void)snprintf(line, sizeof(line), "CURSOR %02d,%02d", g->cursor_x, g->cursor_y);
    force_screen_puts(s, 1, 22, line, FORCE_WHITE, FORCE_BLACK);
    force_screen_puts(s, 1, 23, "TYPE THE ORDER. SPEND THE MEN.", FORCE_LIGHT_GREY, FORCE_BLACK);

    /* Row 24: C64 / SDL extra. Atari and Apple II will not have this. */
    force_screen_fill(s, 0, FORCE_PLAY_ROWS, FORCE_COLS, 1,
                      ' ', FORCE_WHITE, FORCE_DARK_GREY);
    (void)snprintf(line, sizeof(line), "SDL  40x25  4X  1280x800   JOY %s",
                   g->joy_present ? "YES" : "NO");
    force_screen_puts(s, 1, 24, line, FORCE_CYAN, FORCE_DARK_GREY);
}
