#include "game/menu.h"

#include "game/world.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/*
 * Campaign menu. The rules match src/c64/menu.asm.
 * Shown rows are the opening run of scored missions, plus one, plus any
 * session reveal from '+'. The progress file is build/c64/campaign.prg.
 * SDL repaints the character page every frame; the present is a full
 * buffer, so that redraw does not blank the display.
 */

#define MISS_MAX  16
#define ID_MAX    16
#define SAVE_HOLD 20

/* Production defaults; the self-test substitutes an isolated catalog. */
static const force_mission *catalog_missions = force_missions;
static unsigned catalog_count;

static char camp_path[PATH_MAX];
static int miss_count;
static uint8_t score[MISS_MAX];

static int ui_extra;
static int ui_miss;
static int ui_f8;
static int menu_played;
static int need_save;
static int save_failed;
static int save_frames;

static int frontier(void)
{
    int i;

    for (i = 0; i < miss_count; ++i) {
        if (score[i] == 0xFFu) {
            return i;
        }
    }
    return miss_count;
}

static int miss_shown(int index)
{
    int lim;

    if (index < 0 || index >= miss_count) {
        return 0;
    }
    lim = frontier() + 1 + ui_extra;
    return index < lim;
}

static void move_miss(int step)
{
    int index = ui_miss;

    for (;;) {
        index += step;
        if (index < 0 || index >= miss_count) {
            return;
        }
        if (miss_shown(index)) {
            ui_miss = index;
            return;
        }
    }
}

static void move_sel(int step)
{
    move_miss(step);
}

static void reveal_next(void)
{
    int front = frontier();

    if (front + 1 + ui_extra >= miss_count) {
        return;
    }
    ui_extra += 1;
    ui_miss = front + ui_extra;
}

static void clamp_cursor(void)
{
    int front;

    if (miss_shown(ui_miss)) {
        return;
    }
    front = frontier();
    if (front < miss_count) {
        ui_miss = front;
    } else if (miss_count > 0) {
        ui_miss = miss_count - 1;
    }
}

static void reset_scores(void)
{
    int i;

    for (i = 0; i < miss_count; ++i) {
        score[i] = 0xFFu;
    }
    ui_extra = 0;
    ui_miss = 0;
    ui_f8 = 0;
    need_save = 1;
}

static void begin_save(void)
{
    if (need_save) {
        save_frames = SAVE_HOLD;
    }
}

static int repo_has_missions(const char *dir)
{
    char path[PATH_MAX];
    FILE *file;

    if (snprintf(path, sizeof(path), "%s/assets/missions.txt", dir) >=
        (int)sizeof(path)) {
        return 0;
    }
    file = fopen(path, "rb");
    if (file == NULL) {
        return 0;
    }
    fclose(file);
    return 1;
}

static void set_camp_path(void)
{
    char dir[PATH_MAX];
    int up;

    if (getcwd(dir, sizeof(dir)) == NULL) {
        snprintf(camp_path, sizeof(camp_path), "build/c64/campaign.prg");
        return;
    }
    for (up = 0; up < 8; ++up) {
        char *slash;

        if (repo_has_missions(dir)) {
            if (snprintf(camp_path, sizeof(camp_path),
                         "%s/build/c64/campaign.prg", dir) >=
                (int)sizeof(camp_path)) {
                snprintf(camp_path, sizeof(camp_path),
                         "build/c64/campaign.prg");
            }
            return;
        }
        slash = strrchr(dir, '/');
        if (slash == NULL || slash == dir) {
            break;
        }
        *slash = '\0';
    }
    snprintf(camp_path, sizeof(camp_path), "build/c64/campaign.prg");
}

static int mkdir_parent(const char *file)
{
    char buf[PATH_MAX];
    size_t i;
    size_t n;

    if (snprintf(buf, sizeof(buf), "%s", file) >= (int)sizeof(buf)) {
        return -1;
    }
    n = strlen(buf);
    while (n > 0 && buf[n - 1] != '/') {
        n -= 1;
    }
    if (n == 0) {
        return 0;
    }
    buf[n - 1] = '\0';
    for (i = 1; buf[i] != '\0'; ++i) {
        if (buf[i] != '/') {
            continue;
        }
        buf[i] = '\0';
        if (mkdir(buf, 0755) != 0 && errno != EEXIST) {
            return -1;
        }
        buf[i] = '/';
    }
    if (mkdir(buf, 0755) != 0 && errno != EEXIST) {
        return -1;
    }
    return 0;
}

static int score_token(const char *tok, int *value)
{
    int i;
    int parsed = 0;

    if (strcmp(tok, "-") == 0) {
        *value = 0xFF;
        return 1;
    }
    *value = 0;
    for (i = 0; tok[i] != '\0'; ++i) {
        if (tok[i] < '0' || tok[i] > '9') {
            return 0;
        }
        *value = *value * 10 + (tok[i] - '0');
        if (*value > 99) {
            return 0;
        }
        parsed = 1;
    }
    return parsed;
}

static const char *legacy_stem(const char *ident)
{
    static const char *table[][2] = {
        {"hold_farm", "farm"},
        {"cross_river", "cross"},
        {"hold_river", "river"},
        {"take_base", "base"},
        {"take_ridge", "ridge"},
        {"hold_bastogne", "bastogne"},
    };
    int i;

    for (i = 0; i < 6; ++i) {
        if (strcmp(table[i][0], ident) == 0) {
            return table[i][1];
        }
    }
    return NULL;
}

/* Next token into buf. 1 on a token, 0 at end of line, -1 if it does not fit. */
static int next_tok(const char **pp, char *buf, size_t cap)
{
    const char *p = *pp;
    size_t n = 0;

    while (*p == ' ' || *p == '\t') {
        p += 1;
    }
    if (*p == '\0') {
        *pp = p;
        return 0;
    }
    while (*p != '\0' && *p != ' ' && *p != '\t') {
        if (n + 1 >= cap) {
            return -1;
        }
        buf[n] = *p;
        n += 1;
        p += 1;
    }
    buf[n] = '\0';
    *pp = p;
    return 1;
}

static void store_stem_score(const char *stem, int value)
{
    int i;

    for (i = 0; i < miss_count; ++i) {
        if (strcmp(catalog_missions[i].name, stem) == 0) {
            score[i] = (uint8_t)value;
            return;
        }
    }
}

static void apply_line(const char *line)
{
    char tok[4][ID_MAX + 1];
    const char *p = line;
    int ntok = 0;
    int value = 0;
    int index_value = 0;
    const char *stem;

    while (*p == ' ' || *p == '\t') {
        p += 1;
    }
    if (*p == '\0' || *p == '#') {
        return;
    }
    while (ntok < 4) {
        int got = next_tok(&p, tok[ntok], sizeof(tok[ntok]));

        if (got < 0) {
            return;
        }
        if (got == 0) {
            break;
        }
        ntok += 1;
    }
    /* Exactly two tokens: STEM SCORE. `farm 7` stays here. */
    if (ntok == 2) {
        if (!score_token(tok[1], &value)) {
            return;
        }
        store_stem_score(tok[0], value);
        return;
    }
    /* MAP INDEX SCORE OLD_ID, plus an optional title. Score is token 3. */
    if (ntok < 4) {
        return;
    }
    if (!score_token(tok[1], &index_value) || !score_token(tok[2], &value)) {
        return;
    }
    (void)index_value;
    stem = legacy_stem(tok[3]);
    if (stem == NULL) {
        return;
    }
    store_stem_score(stem, value);
}

static void parse_image(char *text)
{
    char *p = text;

    while (*p != '\0') {
        char *start = p;

        while (*p != '\0' && *p != '\n' && *p != '\r') {
            p += 1;
        }
        if (*p == '\r') {
            *p = '\0';
            p += 1;
            if (*p == '\n') {
                p += 1;
            }
        } else if (*p == '\n') {
            *p = '\0';
            p += 1;
        }
        apply_line(start);
    }
}

static void build_catalog(void)
{
    int i;

    miss_count = (int)catalog_count;
    if (miss_count > MISS_MAX) {
        miss_count = MISS_MAX;
    }
    for (i = 0; i < miss_count; ++i) {
        score[i] = 0xFFu;
    }
}

static int write_campaign(void)
{
    char tmp[PATH_MAX];
    FILE *file;
    int i;

    if (camp_path[0] == '\0' ||
        strlen(camp_path) + 4 >= sizeof(tmp)) {
        return 0;
    }
    if (mkdir_parent(camp_path) != 0) {
        return 0;
    }
    snprintf(tmp, sizeof(tmp), "%s.tmp", camp_path);
    file = fopen(tmp, "wb");
    if (file == NULL) {
        return 0;
    }
    if (fwrite("\x00\x10", 1, 2, file) != 2) {
        fclose(file);
        remove(tmp);
        return 0;
    }
    for (i = 0; i < miss_count; ++i) {
        int n;

        if (score[i] == 0xFFu) {
            n = fprintf(file, "%s -\n", catalog_missions[i].name);
        } else {
            n = fprintf(file, "%s %u\n", catalog_missions[i].name,
                        (unsigned)score[i]);
        }
        if (n < 0) {
            fclose(file);
            remove(tmp);
            return 0;
        }
    }
    if (fclose(file) != 0) {
        remove(tmp);
        return 0;
    }
    if (rename(tmp, camp_path) != 0) {
        remove(tmp);
        return 0;
    }
    return 1;
}

void force_campaign_load(void)
{
    FILE *file;
    char image[4096];
    size_t n;
    char *text;

    catalog_count = force_mission_count;
    build_catalog();
    ui_extra = 0;
    ui_miss = 0;
    ui_f8 = 0;
    menu_played = 0;
    need_save = 0;
    save_failed = 0;
    save_frames = 0;
    set_camp_path();

    file = fopen(camp_path, "rb");
    if (file == NULL) {
        return;
    }
    n = fread(image, 1, sizeof(image) - 1, file);
    fclose(file);
    image[n] = '\0';
    text = image;
    if (n >= 2 && (unsigned char)text[0] < 32u) {
        text += 2;
    }
    while (*text == '\0' && text < image + n) {
        text += 1;
    }
    parse_image(text);
}

void force_menu_open(void)
{
    begin_save();
}

const force_mission *force_menu_mission(void)
{
    if (menu_played < 0 || menu_played >= miss_count) {
        return &catalog_missions[0];
    }
    return &catalog_missions[menu_played];
}

void force_menu_commit(uint8_t outcome, uint8_t snap_flag, uint8_t snap_score)
{
    int played = menu_played;

    if (played < 0 || played >= miss_count) {
        return;
    }
    if (outcome == FORCE_SCRIPT_WIN) {
        if (snap_flag != 0u &&
            (score[played] == 0xFFu || snap_score > score[played])) {
            score[played] = snap_score;
            need_save = 1;
        }
        if (played + 1 < miss_count) {
            int next = played + 1;

            played = next;
            if (!miss_shown(played)) {
                int front = frontier();
                if (front < miss_count) {
                    played = front;
                }
            }
        }
    }
    menu_played = played;
    ui_miss = played;
    ui_f8 = 0;
}

static int do_return(void)
{
    if (!miss_shown(ui_miss)) {
        return 0;
    }
    menu_played = ui_miss;
    return 1;
}

static int key_down(const force_input *in)
{
    return in->cmd_kind != FORCE_CMD_NONE || in->f8 || in->nav_fire ||
           in->nav_plus || in->nav_minus || in->nav_star ||
           in->nav_dx != 0 || in->nav_dy != 0;
}

int force_menu_tick(const force_input *in)
{
    if (save_frames > 0) {
        /* The first of these frames is presented before the write. */
        if (save_frames == SAVE_HOLD - 1) {
            int ok = write_campaign();

            need_save = 0;
            save_failed = ok ? 0 : 1;
            if (!ok) {
                save_frames = 0;
                return 0;
            }
        }
        save_frames -= 1;
        return 0;
    }

    if (ui_f8) {
        if (in->f8) {
            reset_scores();
            begin_save();
        } else if (key_down(in)) {
            ui_f8 = 0;
        }
        return 0;
    }
    if (in->cmd_kind == FORCE_CMD_RETURN) {
        return do_return();
    }
    if (in->f8) {
        ui_f8 = 1;
        return 0;
    }
    if (in->nav_plus) {
        reveal_next();
        return 0;
    }
    if (in->nav_minus || in->nav_star) {
        ui_extra = 0;
        clamp_cursor();
        return 0;
    }
    if (in->cmd_kind == FORCE_CMD_ESC || in->cmd_kind == FORCE_CMD_DEL) {
        return 0;
    }
    if (in->nav_dy < 0) {
        move_sel(-1);
        return 0;
    }
    if (in->nav_dy > 0) {
        move_sel(1);
        return 0;
    }
    if (in->nav_dx != 0) {
        return 0;
    }
    if (in->nav_fire) {
        return do_return();
    }
    return 0;
}

static void cell(force_screen *s, int x, int y, char ch, int inv, uint8_t fg)
{
    if (inv) {
        force_screen_putc(s, x, y, (uint8_t)ch, FORCE_BLACK, FORCE_WHITE);
    } else {
        force_screen_putc(s, x, y, (uint8_t)ch, fg, FORCE_BLACK);
    }
}

static void draw_center(force_screen *s, int row, const char *text)
{
    int n = (int)strlen(text);
    int x = (FORCE_COLS - n) / 2;

    if (x < 0) {
        x = 0;
    }
    force_screen_puts(s, x, row, text, FORCE_WHITE, FORCE_BLACK);
}

static void draw_score(force_screen *s, int row, uint8_t value, int inv, uint8_t fg)
{
    char tens = ' ';
    char ones = '-';

    if (value != 0xFFu) {
        if (value >= 10u) {
            tens = (char)('0' + (value / 10u));
        }
        ones = (char)('0' + (value % 10u));
    }
    cell(s, 38, row, tens, inv, fg);
    cell(s, 39, row, ones, inv, fg);
}

static void draw_headers(force_screen *s)
{
    force_screen_puts(s, 0, 6, "Missions:", FORCE_WHITE, FORCE_BLACK);
    force_screen_puts(s, 30, 6, "Survivors:", FORCE_DARK_GREY, FORCE_BLACK);
}

static int window_skip(void)
{
    int skip = 0;
    int seen = 0;
    int i;

    for (i = 0; i < miss_count; ++i) {
        if (!miss_shown(i)) {
            continue;
        }
        if (i == ui_miss) {
            skip = seen;
        }
        seen += 1;
    }
    if (skip >= 10) {
        return skip - 9;
    }
    return 0;
}

static void draw_one_mission(force_screen *s, int index, int row)
{
    const char *title = catalog_missions[index].title;
    int inv = (index == ui_miss);
    uint8_t fg = (score[index] == 0xFFu) ? FORCE_WHITE : FORCE_LIGHT_GREEN;
    int n;
    int x;
    int t;

    if (title == NULL || title[0] == '\0') {
        title = catalog_missions[index].name;
    }
    n = (int)strlen(title);
    x = 0;
    for (t = 0; x < 37 && t < n; ++t, ++x) {
        cell(s, x, row, title[t], inv, fg);
    }
    while (x < 38) {
        cell(s, x, row, ' ', inv, fg);
        x += 1;
    }
    draw_score(s, row, score[index], inv, fg);
}

static void draw_missions(force_screen *s)
{
    int skip = window_skip();
    int passed = 0;
    int row = 8;
    int i;

    for (i = 0; i < miss_count && row < 18; ++i) {
        if (!miss_shown(i)) {
            continue;
        }
        if (passed < skip) {
            passed += 1;
            continue;
        }
        draw_one_mission(s, i, row);
        row += 1;
        passed += 1;
    }
}

static void draw_status(force_screen *s)
{
    if (save_frames > 0) {
        force_screen_puts(s, 0, 22, "SAVING", FORCE_WHITE, FORCE_BLACK);
        return;
    }
    if (ui_f8) {
        force_screen_puts(s, 0, 22, "F8 AGAIN TO RESET",
                          FORCE_WHITE, FORCE_BLACK);
        return;
    }
    if (save_failed) {
        force_screen_puts(s, 0, 22, "SAVE FAILED",
                          FORCE_LIGHT_RED, FORCE_BLACK);
    }
}

void force_menu_paint(force_screen *screen, uint32_t *pixels)
{
    force_screen_clear(screen, ' ', FORCE_WHITE, FORCE_BLACK);
    draw_center(screen, 0, "FORCE - WWII RTS");
    draw_center(screen, 24, "Stefan Wessels, 2026");
    draw_headers(screen);
    draw_missions(screen);
    draw_status(screen);
    force_screen_rasterize(screen, pixels);
}

static int id_of(const char *name)
{
    int i;

    for (i = 0; i < miss_count; ++i) {
        if (strcmp(catalog_missions[i].name, name) == 0) {
            return i;
        }
    }
    return -1;
}

static void blank_ui(void)
{
    int i;

    for (i = 0; i < miss_count; ++i) {
        score[i] = 0xFFu;
    }
    ui_extra = 0;
    ui_miss = 0;
    ui_f8 = 0;
    menu_played = 0;
    need_save = 0;
    save_failed = 0;
    save_frames = 0;
}

static int menu_fixture_selftest(void)
{
    char saved[PATH_MAX];
    char image[1024];
    force_input in;
    int farm;
    int ridge;
    int bast;

    memcpy(saved, camp_path, sizeof(saved));
    build_catalog();
    blank_ui();
    farm = id_of("test_first");
    ridge = id_of("test_second");
    bast = id_of("test_third");
    if (farm != 0 || ridge != 1 || bast != 2 || miss_count < 3) {
        return 0;
    }
    if (frontier() != 0 || !miss_shown(farm) || miss_shown(ridge) ||
        miss_shown(bast)) {
        return 0;
    }

    reveal_next();
    if (ui_extra != 1 || ui_miss != ridge || !miss_shown(ridge) ||
        miss_shown(bast)) {
        return 0;
    }
    reveal_next();
    if (ui_extra != 2 || ui_miss != bast || !miss_shown(bast)) {
        return 0;
    }
    if (miss_count == 3) {
        reveal_next();
        if (ui_extra != 2 || ui_miss != bast) {
            return 0;
        }
    }
    ui_extra = 0;
    clamp_cursor();
    if (ui_miss != farm || miss_shown(bast)) {
        return 0;
    }

    score[farm] = 7;
    if (frontier() != ridge || !miss_shown(ridge) || miss_shown(bast)) {
        return 0;
    }
    reveal_next();
    if (ui_extra != 1 || ui_miss != bast || !miss_shown(bast)) {
        return 0;
    }

    blank_ui();
    score[ridge] = 5;
    if (frontier() != farm || miss_shown(ridge) || miss_shown(bast)) {
        return 0;
    }
    menu_played = farm;
    force_menu_commit(FORCE_SCRIPT_WIN, 1u, 3u);
    if (score[farm] != 3 || score[ridge] != 5 || need_save != 1 ||
        ui_miss != ridge || !miss_shown(bast) ||
        !miss_shown(ridge)) {
        return 0;
    }

    menu_played = farm;
    need_save = 0;
    force_menu_commit(FORCE_SCRIPT_WIN, 1u, 1u);
    if (score[farm] != 3 || need_save != 0 || ui_miss != ridge) {
        return 0;
    }
    menu_played = bast;
    force_menu_commit(FORCE_SCRIPT_LOSE, 1u, 9u);
    if (menu_played != bast || ui_miss != bast || score[bast] != 0xFFu ||
        need_save != 0) {
        return 0;
    }

    memset(&in, 0, sizeof(in));
    blank_ui();
    in.f8 = true;
    if (force_menu_tick(&in) != 0 || ui_f8 != 1) {
        return 0;
    }
    memset(&in, 0, sizeof(in));
    in.nav_dy = 1;
    if (force_menu_tick(&in) != 0 || ui_f8 != 0 || ui_miss != 0) {
        return 0;
    }
    memset(&in, 0, sizeof(in));
    in.f8 = true;
    force_menu_tick(&in);
    force_menu_tick(&in);
    if (score[farm] != 0xFFu || ui_miss != 0 || ui_f8 != 0) {
        return 0;
    }
    save_frames = 0;
    need_save = 0;

    blank_ui();
    memset(&in, 0, sizeof(in));
    in.nav_dx = 1;
    if (force_menu_tick(&in) != 0 || ui_miss != farm) {
        return 0;
    }
    memset(&in, 0, sizeof(in));
    in.nav_dx = -1;
    if (force_menu_tick(&in) != 0 || ui_miss != farm) {
        return 0;
    }
    memset(&in, 0, sizeof(in));
    in.cmd_kind = FORCE_CMD_RETURN;
    if (force_menu_tick(&in) != 1 || menu_played != farm) {
        return 0;
    }

    {
        char *text;
        FILE *file;
        size_t n;
        int round = 1;

        /* The wrapper supplies a unique, isolated campaign path. */
        blank_ui();
        score[farm] = 4;
        score[bast] = 0;
        if (!write_campaign()) {
            round = 0;
        } else {
            blank_ui();
            file = fopen(camp_path, "rb");
            if (file == NULL) {
                round = 0;
            } else {
                n = fread(image, 1, sizeof(image) - 1, file);
                fclose(file);
                image[n] = '\0';
                text = image;
                if (n >= 2 && (unsigned char)text[0] < 32u) {
                    text += 2;
                }
                /* parse_image writes NULs over the line breaks. */
                if (strstr(text, "test_first 4") == NULL ||
                    strstr(text, "test_third 0") == NULL ||
                    strstr(text, "NORMANDY") != NULL) {
                    round = 0;
                } else {
                    parse_image(text);
                    if (score[farm] != 4 || score[ridge] != 0xFFu ||
                        score[bast] != 0) {
                        round = 0;
                    }
                }
            }
        }
        remove(camp_path);
        memcpy(camp_path, saved, sizeof(camp_path));
        if (!round) {
            return 0;
        }
    }

    {
        force_screen screen;
        uint32_t *pixels;
        int x;
        int y;

        pixels = calloc((size_t)FORCE_FB_W * (size_t)FORCE_FB_H,
                        sizeof(uint32_t));
        if (pixels == NULL) {
            return 0;
        }
        blank_ui();
        force_menu_paint(&screen, pixels);
        if (screen.cells[0][12].ch != 'F' ||
            screen.cells[6][0].ch != 'M' ||
            screen.cells[6][1].ch != 'i' ||
            screen.cells[6][0].fg != FORCE_WHITE ||
            screen.cells[6][30].ch != 'S' ||
            screen.cells[6][30].fg != FORCE_DARK_GREY ||
            screen.cells[8][0].ch != 'H' ||
            screen.cells[8][0].fg != FORCE_BLACK ||
            screen.cells[8][0].bg != FORCE_WHITE ||
            screen.cells[8][38].ch != ' ' ||
            screen.cells[8][38].bg != FORCE_WHITE ||
            screen.cells[8][39].ch != '-' ||
            screen.cells[8][39].bg != FORCE_WHITE ||
            screen.cells[9][0].ch != ' ' ||
            screen.cells[24][10].ch != 'S') {
            free(pixels);
            return 0;
        }
        for (y = 0; y < FORCE_ROWS; ++y) {
            for (x = 0; x < FORCE_COLS - 8; ++x) {
                if (screen.cells[y][x].ch == 'S' &&
                    screen.cells[y][x + 1].ch == 'o' &&
                    screen.cells[y][x + 2].ch == 'm' &&
                    screen.cells[y][x + 3].ch == 'e') {
                    free(pixels);
                    return 0;
                }
            }
        }
        free(pixels);
    }

    blank_ui();
    return 1;
}

/* `farm 7` is a stem score. The legacy id scores cross, then the save drops it. */
static int score_line_selftest(void)
{
    static const force_mission rows[] = {
        {.name = "farm", .title = "Hold the Farm", .biome = "normandy"},
        {.name = "cross", .title = "Cross the river", .biome = "normandy"},
    };
    const force_mission *saved_cat = catalog_missions;
    unsigned saved_n = catalog_count;
    char image[512];
    char mixed[] =
        "farm 7\n"
        "cross -\n"
        "NORMANDY 1 7 cross_river Cross the river\n";
    char farm_line[] = "farm 7\n";
    char cross_line[] = "cross -\n";
    char legacy_line[] = "NORMANDY 1 7 cross_river Cross the river\n";
    FILE *file;
    size_t n;
    int ok = 1;

    catalog_missions = rows;
    catalog_count = 2;
    build_catalog();
    blank_ui();
    parse_image(mixed);
    if (score[0] != 7 || score[1] != 7) {
        ok = 0;
    }
    if (ok && !write_campaign()) {
        ok = 0;
    } else if (ok) {
        file = fopen(camp_path, "rb");
        if (file == NULL) {
            ok = 0;
        } else {
            char *text;

            n = fread(image, 1, sizeof(image) - 1, file);
            fclose(file);
            image[n] = '\0';
            text = image;
            if (n >= 2 && (unsigned char)text[0] < 32u) {
                text += 2;
            }
            if (strstr(text, "farm 7") == NULL ||
                strstr(text, "cross 7") == NULL ||
                strstr(text, "hold_farm") != NULL ||
                strstr(text, "cross_river") != NULL ||
                strstr(text, "NORMANDY") != NULL) {
                ok = 0;
            }
        }
    }
    blank_ui();
    parse_image(farm_line);
    if (score[0] != 7 || score[1] != 0xFFu) {
        ok = 0;
    }
    blank_ui();
    parse_image(cross_line);
    if (score[0] != 0xFFu || score[1] != 0xFFu) {
        ok = 0;
    }
    blank_ui();
    parse_image(legacy_line);
    if (score[0] != 0xFFu || score[1] != 7) {
        ok = 0;
    }
    catalog_missions = saved_cat;
    catalog_count = saved_n;
    remove(camp_path);
    return ok;
}

/* No authored mission names, order, scores or files are test inputs. */
int force_menu_selftest(void)
{
    static const force_map maps[] = {
        {.name = "north"}, {.name = "south"}
    };
    static const force_mission missions[] = {
        {.name = "test_first", .title = "Hold the Farm", .biome = "north", .map = &maps[0]},
        {.name = "test_second", .title = "Take the Ridge", .biome = "north", .map = &maps[0]},
        {.name = "test_third", .title = "Something Else", .biome = "south", .map = &maps[1]}
    };
    char saved_path[PATH_MAX];
    char directory[] = "/tmp/force-menu-selftest-XXXXXX";
    const force_mission *saved_catalog = catalog_missions;
    unsigned saved_count = catalog_count;
    uint8_t saved_scores[MISS_MAX];
    int saved_ui[] = {miss_count, ui_extra, ui_miss, ui_f8, menu_played, need_save, save_failed, save_frames};
    int result;

    if (mkdtemp(directory) == NULL) {
        return 0;
    }
    memcpy(saved_path, camp_path, sizeof(saved_path));
    memcpy(saved_scores, score, sizeof(score));
    snprintf(camp_path, sizeof(camp_path), "%s/campaign.prg", directory);
    result = score_line_selftest();
    catalog_missions = missions;
    catalog_count = sizeof(missions) / sizeof(missions[0]);
    if (result) {
        result = menu_fixture_selftest();
    }
    remove(camp_path);
    rmdir(directory);
    memcpy(camp_path, saved_path, sizeof(camp_path));
    catalog_missions = saved_catalog;
    catalog_count = saved_count;
    memcpy(score, saved_scores, sizeof(score));
    miss_count = saved_ui[0];
    ui_extra = saved_ui[1];
    ui_miss = saved_ui[2];
    ui_f8 = saved_ui[3];
    menu_played = saved_ui[4];
    need_save = saved_ui[5];
    save_failed = saved_ui[6];
    save_frames = saved_ui[7];
    return result;
}
