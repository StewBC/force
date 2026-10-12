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

#define MAP_MAX   4
#define MISS_MAX  16
#define ID_MAX    16
#define SAVE_HOLD 20

/* Production defaults; the self-test substitutes an isolated catalog. */
static const force_mission *catalog_missions = force_missions;
static unsigned catalog_count;

static char camp_path[PATH_MAX];
static char map_stem[MAP_MAX][ID_MAX + 1];
static int map_count;
static int miss_count;
static int miss_map[MISS_MAX];
static uint8_t score[MISS_MAX];

static int ui_extra;
static int ui_col;
static int ui_map;
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

static int map_has_shown(int map)
{
    int i;

    for (i = 0; i < miss_count; ++i) {
        if (miss_map[i] == map && miss_shown(i)) {
            return 1;
        }
    }
    return 0;
}

static void focus_mission(void)
{
    int front = frontier();
    int i;

    if (front < miss_count && miss_map[front] == ui_map) {
        ui_miss = front;
        return;
    }
    for (i = 0; i < miss_count; ++i) {
        if (miss_map[i] == ui_map && miss_shown(i)) {
            ui_miss = i;
            return;
        }
    }
}

static void move_map(int step)
{
    int map = ui_map;

    for (;;) {
        map += step;
        if (map < 0 || map >= map_count) {
            return;
        }
        if (map_has_shown(map)) {
            ui_map = map;
            focus_mission();
            return;
        }
    }
}

static void move_miss(int step)
{
    int index = ui_miss;

    for (;;) {
        index += step;
        if (index < 0 || index >= miss_count) {
            return;
        }
        if (miss_map[index] == ui_map && miss_shown(index)) {
            ui_miss = index;
            return;
        }
    }
}

static void move_sel(int step)
{
    if (ui_col == 0) {
        move_map(step);
    } else {
        move_miss(step);
    }
}

static void enter_missions(void)
{
    if (ui_col != 0) {
        return;
    }
    if (!map_has_shown(ui_map)) {
        return;
    }
    ui_col = 1;
    focus_mission();
}

static void reveal_next(void)
{
    int front = frontier();

    if (front + 1 + ui_extra >= miss_count) {
        return;
    }
    ui_extra += 1;
    ui_miss = front + ui_extra;
    ui_map = miss_map[ui_miss];
    ui_col = 1;
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
    if (miss_count > 0) {
        ui_map = miss_map[ui_miss];
    }
}

static void reset_scores(void)
{
    int i;

    for (i = 0; i < miss_count; ++i) {
        score[i] = 0xFFu;
    }
    ui_extra = 0;
    ui_col = 0;
    ui_map = 0;
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

static void apply_line(const char *line)
{
    char map_name[ID_MAX + 1];
    char score_tok[8];
    char ident[ID_MAX + 1];
    const char *p = line;
    int ord = 0;
    int value = 0;
    int i;
    int neg = 0;

    while (*p == ' ' || *p == '\t') {
        p += 1;
    }
    if (*p == '\0' || *p == '#') {
        return;
    }
    if (sscanf(p, "%16s %d %7s %16s", map_name, &ord, score_tok, ident) != 4) {
        return;
    }
    (void)map_name;
    (void)ord;
    if (strcmp(score_tok, "-") == 0) {
        value = 0xFF;
    } else {
        for (i = 0; score_tok[i] != '\0'; ++i) {
            if (score_tok[i] < '0' || score_tok[i] > '9') {
                return;
            }
            value = value * 10 + (score_tok[i] - '0');
            if (value > 99) {
                return;
            }
            neg = 1;
        }
        if (!neg) {
            return;
        }
    }
    for (i = 0; i < miss_count; ++i) {
        if (strcmp(catalog_missions[i].name, ident) == 0) {
            score[i] = (uint8_t)value;
            return;
        }
    }
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

    map_count = 0;
    miss_count = (int)catalog_count;
    if (miss_count > MISS_MAX) {
        miss_count = MISS_MAX;
    }
    for (i = 0; i < miss_count; ++i) {
        const char *stem = catalog_missions[i].map->name;
        int map = 0;

        score[i] = 0xFFu;
        miss_map[i] = 0;
        while (map < map_count && strcmp(map_stem[map], stem) != 0) {
            map += 1;
        }
        if (map == map_count) {
            if (map_count >= MAP_MAX) {
                miss_count = i;
                break;
            }
            snprintf(map_stem[map_count], sizeof(map_stem[map_count]),
                     "%s", stem);
            map_count += 1;
        }
        miss_map[i] = map;
    }
}

static int write_campaign(void)
{
    char tmp[PATH_MAX];
    char upper[ID_MAX + 1];
    int ord_of[MAP_MAX];
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
    for (i = 0; i < MAP_MAX; ++i) {
        ord_of[i] = 0;
    }
    for (i = 0; i < miss_count; ++i) {
        const char *stem = map_stem[miss_map[i]];
        const char *title = catalog_missions[i].title;
        int map = miss_map[i];
        int ord = ord_of[map];
        int n;
        size_t c;

        ord_of[map] = ord + 1;
        if (title == NULL || title[0] == '\0') {
            title = catalog_missions[i].name;
        }
        for (c = 0; c < sizeof(upper) - 1 && stem[c] != '\0'; ++c) {
            char ch = stem[c];
            if (ch >= 'a' && ch <= 'z') {
                ch = (char)(ch - 32);
            }
            upper[c] = ch;
        }
        upper[c] = '\0';
        if (score[i] == 0xFFu) {
            n = fprintf(file, "%s %d - %s %s\n",
                        upper, ord, catalog_missions[i].name, title);
        } else {
            n = fprintf(file, "%s %d %u %s %s\n",
                        upper, ord, (unsigned)score[i],
                        catalog_missions[i].name, title);
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
    ui_col = 0;
    ui_map = 0;
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
    ui_map = miss_map[played];
    ui_col = 1;
    ui_f8 = 0;
}

static int do_return(void)
{
    if (miss_count <= 0) {
        return 0;
    }
    if (ui_col == 0) {
        enter_missions();
        return 0;
    }
    if (ui_miss < 0 || ui_miss >= miss_count) {
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
        ui_col = 0;
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
    if (in->nav_dx < 0) {
        ui_col = 0;
        return 0;
    }
    if (in->nav_dx > 0) {
        enter_missions();
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

static void draw_cased(force_screen *s, int row, const char *stem, int inv)
{
    int n = (int)strlen(stem);
    int x;

    for (x = 0; x < 9; ++x) {
        char ch = ' ';

        if (x < n) {
            ch = stem[x];
            if (x == 0) {
                if (ch >= 'a' && ch <= 'z') {
                    ch = (char)(ch - 32);
                }
            } else if (ch >= 'A' && ch <= 'Z') {
                ch = (char)(ch + 32);
            }
        }
        cell(s, x, row, ch, inv, FORCE_WHITE);
    }
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
    uint8_t map_fg = (ui_col == 0) ? FORCE_WHITE : FORCE_DARK_GREY;
    uint8_t mis_fg = (ui_col == 1) ? FORCE_WHITE : FORCE_DARK_GREY;

    force_screen_puts(s, 0, 6, "Map:", map_fg, FORCE_BLACK);
    force_screen_puts(s, 10, 6, "Missions:", mis_fg, FORCE_BLACK);
    force_screen_puts(s, 30, 6, "Survivors:", FORCE_DARK_GREY, FORCE_BLACK);
}

static void draw_maps(force_screen *s)
{
    int row = 8;
    int map;

    for (map = 0; map < map_count && row < 18; ++map) {
        if (!map_has_shown(map)) {
            continue;
        }
        draw_cased(s, row, map_stem[map], map == ui_map);
        row += 1;
    }
}

static int window_skip(void)
{
    int skip = 0;
    int seen = 0;
    int i;

    for (i = 0; i < miss_count; ++i) {
        if (miss_map[i] != ui_map || !miss_shown(i)) {
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
    int inv = (ui_col != 0 && index == ui_miss);
    uint8_t fg = (score[index] == 0xFFu) ? FORCE_WHITE : FORCE_LIGHT_GREEN;
    int n;
    int x;
    int t;

    if (title == NULL || title[0] == '\0') {
        title = catalog_missions[index].name;
    }
    n = (int)strlen(title);
    x = 10;
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
        if (miss_map[i] != ui_map || !miss_shown(i)) {
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
    draw_maps(screen);
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
    ui_col = 0;
    ui_map = 0;
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
    if (miss_map[farm] != miss_map[ridge] ||
        miss_map[farm] == miss_map[bast]) {
        return 0;
    }
    if (frontier() != 0 || !miss_shown(farm) || miss_shown(ridge) ||
        !map_has_shown(miss_map[farm]) || map_has_shown(miss_map[bast])) {
        return 0;
    }

    reveal_next();
    if (ui_extra != 1 || ui_miss != ridge || ui_col != 1 ||
        ui_map != miss_map[ridge] || !miss_shown(ridge) || miss_shown(bast)) {
        return 0;
    }
    reveal_next();
    if (ui_extra != 2 || ui_miss != bast || ui_map != miss_map[bast] ||
        !miss_shown(bast) || !map_has_shown(miss_map[bast])) {
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
    if (ui_miss != farm || ui_map != miss_map[farm] || miss_shown(bast)) {
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
        ui_miss != ridge || ui_col != 1 || !miss_shown(bast) ||
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
    if (score[farm] != 0xFFu || ui_miss != 0 || ui_col != 0 || ui_f8 != 0) {
        return 0;
    }
    save_frames = 0;
    need_save = 0;

    blank_ui();
    memset(&in, 0, sizeof(in));
    in.cmd_kind = FORCE_CMD_RETURN;
    if (force_menu_tick(&in) != 0 || ui_col != 1 || ui_miss != farm) {
        return 0;
    }
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
                parse_image(text);
                if (score[farm] != 4 || score[ridge] != 0xFFu ||
                    score[bast] != 0) {
                    round = 0;
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
            screen.cells[6][0].fg != FORCE_WHITE ||
            screen.cells[6][10].fg != FORCE_DARK_GREY ||
            screen.cells[6][30].fg != FORCE_DARK_GREY ||
            screen.cells[8][0].ch != 'N' ||
            screen.cells[8][0].fg != FORCE_BLACK ||
            screen.cells[8][0].bg != FORCE_WHITE ||
            screen.cells[8][8].ch != ' ' ||
            screen.cells[8][8].bg != FORCE_WHITE ||
            screen.cells[8][9].ch != ' ' ||
            screen.cells[8][9].bg != FORCE_BLACK ||
            screen.cells[8][10].ch != 'H' ||
            screen.cells[8][10].fg != FORCE_WHITE ||
            screen.cells[8][10].bg != FORCE_BLACK ||
            screen.cells[8][38].ch != ' ' ||
            screen.cells[8][39].ch != '-' ||
            screen.cells[9][0].ch != ' ' ||
            screen.cells[9][10].ch != ' ' ||
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
        ui_col = 1;
        ui_miss = farm;
        force_menu_paint(&screen, pixels);
        if (screen.cells[6][0].fg != FORCE_DARK_GREY ||
            screen.cells[6][10].fg != FORCE_WHITE ||
            screen.cells[8][10].fg != FORCE_BLACK ||
            screen.cells[8][10].bg != FORCE_WHITE ||
            screen.cells[8][39].ch != '-' ||
            screen.cells[8][39].bg != FORCE_WHITE ||
            screen.cells[8][0].bg != FORCE_WHITE) {
            free(pixels);
            return 0;
        }
        free(pixels);
    }

    blank_ui();
    return 1;
}

/* No authored mission names, order, scores or files are test inputs. */
int force_menu_selftest(void)
{
    static const force_map maps[] = {
        {.name = "north"}, {.name = "south"}
    };
    static const force_mission missions[] = {
        {.name = "test_first", .title = "Hold the Farm", .map = &maps[0]},
        {.name = "test_second", .title = "Take the Ridge", .map = &maps[0]},
        {.name = "test_third", .title = "Something Else", .map = &maps[1]}
    };
    char saved_path[PATH_MAX];
    char directory[] = "/tmp/force-menu-selftest-XXXXXX";
    const force_mission *saved_catalog = catalog_missions;
    unsigned saved_count = catalog_count;
    char saved_stems[sizeof(map_stem)];
    int saved_maps[MISS_MAX];
    uint8_t saved_scores[MISS_MAX];
    int saved_ui[] = {map_count, miss_count, ui_extra, ui_col, ui_map, ui_miss, ui_f8, menu_played, need_save, save_failed, save_frames};
    int result;

    if (mkdtemp(directory) == NULL) {
        return 0;
    }
    memcpy(saved_path, camp_path, sizeof(saved_path));
    memcpy(saved_stems, map_stem, sizeof(map_stem));
    memcpy(saved_maps, miss_map, sizeof(miss_map));
    memcpy(saved_scores, score, sizeof(score));
    snprintf(camp_path, sizeof(camp_path), "%s/campaign.prg", directory);
    catalog_missions = missions;
    catalog_count = sizeof(missions) / sizeof(missions[0]);
    result = menu_fixture_selftest();
    remove(camp_path);
    rmdir(directory);
    memcpy(camp_path, saved_path, sizeof(camp_path));
    catalog_missions = saved_catalog;
    catalog_count = saved_count;
    memcpy(map_stem, saved_stems, sizeof(map_stem));
    memcpy(miss_map, saved_maps, sizeof(miss_map));
    memcpy(score, saved_scores, sizeof(score));
    map_count = saved_ui[0];
    miss_count = saved_ui[1];
    ui_extra = saved_ui[2];
    ui_col = saved_ui[3];
    ui_map = saved_ui[4];
    ui_miss = saved_ui[5];
    ui_f8 = saved_ui[6];
    menu_played = saved_ui[7];
    need_save = saved_ui[8];
    save_failed = saved_ui[9];
    save_frames = saved_ui[10];
    return result;
}
