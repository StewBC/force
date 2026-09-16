#ifndef FORCE_TYPES_H
#define FORCE_TYPES_H

#include <stdbool.h>
#include <stdint.h>

/*
 * The machine is a 40x25 character screen. Each cell is 8x8 pixels.
 *
 * Rows 0-23 are the portable playfield + command strip (Atari / Apple II).
 * Row 24 is extra chrome on C64 and this SDL host.
 *
 * Native pixels: 320x200. SDL window is 4x nearest-neighbour: 1280x800.
 */
#define FORCE_COLS          40
#define FORCE_ROWS          25
#define FORCE_PLAY_ROWS     24
#define FORCE_FIELD_ROWS    20
#define FORCE_CELL_PX       8
#define FORCE_SCALE         4
#define FORCE_FB_W          (FORCE_COLS * FORCE_CELL_PX)
#define FORCE_FB_H          (FORCE_ROWS * FORCE_CELL_PX)
#define FORCE_WIN_W         (FORCE_FB_W * FORCE_SCALE)
#define FORCE_WIN_H         (FORCE_FB_H * FORCE_SCALE)

/* VIC-II colour indices. RGB lives in core/screen.c. */
enum force_color {
    FORCE_BLACK = 0,
    FORCE_WHITE,
    FORCE_RED,
    FORCE_CYAN,
    FORCE_PURPLE,
    FORCE_GREEN,
    FORCE_BLUE,
    FORCE_YELLOW,
    FORCE_ORANGE,
    FORCE_BROWN,
    FORCE_LIGHT_RED,
    FORCE_DARK_GREY,
    FORCE_GREY,
    FORCE_LIGHT_GREEN,
    FORCE_LIGHT_BLUE,
    FORCE_LIGHT_GREY,
    FORCE_COLOR_COUNT
};

typedef struct force_cell {
    uint8_t ch;
    uint8_t fg;
    uint8_t bg;
} force_cell;

typedef struct force_screen {
    force_cell cells[FORCE_ROWS][FORCE_COLS];
} force_screen;

enum force_cmd_kind {
    FORCE_CMD_NONE = 0,
    FORCE_CMD_LETTER,   /* cmd_value 0-25 = A-Z */
    FORCE_CMD_DIGIT,    /* cmd_value 0-9 */
    FORCE_CMD_COMMA,
    FORCE_CMD_SPACE,
    FORCE_CMD_RETURN,
    FORCE_CMD_DEL
};

typedef struct force_input {
    int cursor_dx;
    int cursor_dy;
    bool quit;
    bool toggle_fullscreen;
    bool restart;
    bool joy_present;
    bool stick_latched;
    uint8_t cmd_kind;
    uint8_t cmd_value;
} force_input;

#endif
