.include "generated/layout.inc"
; Shared equates for the C64 vertical slice. 6502 only.

NONE            = $FF

UNIT_MAX        = 32
SECTION_MAX     = 16
LETTER_MAX      = 8
ROOM_MAX        = 16
COVER_MAX       = 128
PORTAL_MAX      = 24
SCOUT_MAX       = 32
; Same values as tools/gen_sdl.py. The loader rejects a body past these.
SPAWN_MAX       = 32
OP_MAX          = 64
BEAT_MAX        = 12
WATCH_MAX       = 8
PRED_MAX        = 32
WHERE_MAX       = 16
TMPL_MAX        = 8
CLAIM_BYTES     = (COVER_MAX + SCOUT_MAX) / 8   ; 20. One bit per chip or scout id.
COLS            = 40
FIELD_ROWS      = 20
SCREEN_ROWS     = 25
MAP_ROWS        = 40    ; row_lo / row_hi. Taller maps are rejected by gen_c64.py.
MAP_W           = 80    ; map_ptr and the portal bitset. gen_c64.py rejects any other width.
PORTAL_BYTES    = 400   ; MAP_W * MAP_ROWS / 8. One bit per cell.
SEAM_CAP        = 20    ; longest shared wall stored as a list. A longer span is walked.
DOOR_MAX        = 24    ; unordered walls with at least one open cell. The farm has 22.
DOOR_POOL       = 176   ; open mv_p bytes for those walls. The farm uses 167.
FORM_CELLS      = 9     ; bdx/bdy formation around an order cell.

VERB_NONE       = 0
VERB_MOVE       = 1
VERB_DEFEND     = 2
VERB_HALT       = 3
VERB_ATTACK     = 4
VERB_RETREAT    = 5
VERB_KILL       = 6
VERB_SPLIT      = 7
VERB_JOIN       = 8
VERB_FOCUS      = 9
VERB_BUILD      = 10    ; B. Section order only; not a script nibble.

KIND_INFANTRY   = 0
KIND_EMPLACEMENT = 2

CLASS_EMPTY     = 0
CLASS_WALLS     = 1
CLASS_ROOFS     = 2
CLASS_BARRIERS  = 3
CLASS_GOODGUYS  = 4
CLASS_ENEMIES   = 5
CLASS_COLORS    = 6
PAPER_WATER     = 6     ; colour tile 118, VIC blue. cell_open rejects it.
TILE_DECK_OPEN  = 80    ; unbuilt plank. Closed, even off the water.
TILE_DECK_BUILT = 81    ; finished plank. Open on blue paper.
DECK_MAX        = 16    ; SDL keeps 64. Normandy paints 6.
SLIDE_CAP       = 8     ; wall-gap search. A longer wall keeps the one-cell dodge.
; Deck brain and its RAM. The segment must end before GEO_IMAGE.
; Mission packs end before this. One more byte of brain means a lower
; origin and a smaller pack.

MOVE_WAIT       = 7
MOVE_SPRINT     = 4
HP_INFANTRY     = 16
FIRE_WAIT       = 8
RANGE_MAX       = 16    ; parked sight ray
RIFLE_FAR       = 10    ; dist >= 10 is not a rifle target
RIFLE_HALF      = 5     ; dist >= 5 halves the posture number
DMG_COVER3      = 1
DMG_COVER2      = 2
DMG_COVER1      = 3
DMG_SPRINT      = 5
DMG_WALK        = 7
DMG_OPEN        = 10
GRENADE_RANGE   = 5
GRENADE_MIN     = 2
GRENADE_BLAST   = 2
GRENADE_DMG     = 8
GRENADE_FX_TTL  = 4
FX_HURT         = 1

FLAG_NOPATH     = $01
FLAG_ASSIGN     = $02
FLAG_RELEASE    = $04
FLAG_BREAKING   = $08
FLAG_CONTACT    = $10

FACE_NONE       = 0
FACE_N          = 1
FACE_E          = 2
FACE_S          = 3
FACE_W          = 4
COVER_SOFT_N    = 5
COVER_HARD_N    = 9
AXIS_NONE       = 0
AXIS_EW         = 1
AXIS_NS         = 2
APPROACH_N      = $01
APPROACH_E      = $02
APPROACH_S      = $04
APPROACH_W      = $08
WHERE_ROOM      = 0
WHERE_CELL      = 1
WHERE_EXIT      = 3
SX_NEG          = $FF
STEP_FAR        = 16
STEP_CAP        = 8
GLYPH_ENEMY_E   = 10
OP_SET_SPAWN    = 3
OP_APPROACH     = 4
OP_GOTO         = 5
OP_WIN          = 7
OP_LOSE         = 8
OP_OBJECTIVE    = 10
WATCH_ONCE      = 1

PRED_NONE       = 0
PRED_STR_EQ     = 1
PRED_STR_LE     = 2
PRED_IN_GE      = 3
PRED_REACHED    = 4
PRED_AT_CELL    = 5
PRED_CLOCK_GE   = 6
PRED_REL_GE     = 7
PRED_STR_GE     = 8
PRED_JOB_IDLE   = 9

ROOM_SEEN       = $01
ROOM_LIVE       = $02
ROOM_HOME       = $04
ROOM_MARK       = $08
HEAT_START      = 8
FOCUS_TICKS     = 16

OUT_PLAYING     = 0
OUT_WIN         = 1
OUT_LOSE        = 2

SLOT_IDLE       = 0
SLOT_WHO        = 1
SLOT_WHERE_X    = 2
SLOT_WHERE_Y    = 3
SLOT_FORCE      = 4
SLOT_SHOW       = 5

CMD_NONE        = 0
CMD_LETTER      = 1
CMD_DIGIT       = 2
CMD_COMMA       = 3
CMD_SPACE       = 4
CMD_RETURN      = 5
CMD_DEL         = 6
CMD_PERIOD      = 7
CMD_ESC         = 8

; VIC colours. Playfield MC: %00 red, %01 grey, %10 light blue, %11 paper.
COL_BLACK       = 0
COL_WHITE       = 1
COL_RED         = 2
COL_CYAN        = 3
COL_GREEN       = 5
COL_BLUE        = 6
COL_YELLOW      = 7
COL_LIGHT_RED   = 10
COL_DARK_GREY   = 11
COL_GREY        = 12
COL_LIGHT_GREEN = 13
COL_LIGHT_BLUE  = 14
COL_LIGHT_GREY  = 15
MC_INK_RED      = 2
MC_INK_GREY     = 11
MC_INK_BLUE     = 14

; Always-RAM flags. Zero page, so a bank change cannot hide them.
; $A000–$BFFF is code space under BASIC; a KERNAL pass can flip $01.
; ui_edge is set by the line-210 split (map to normal text). The draw
; waits for a fresh edge. ui_count is how many of those edges have
; passed since the last draw, saturating at FRAME_RASTERS.
; screen_hold stays set until the line-251 split opens the display.
ui_edge         = $FB
ui_count        = $FC
screen_hold     = $FD

; Video frames from the start of world_tick to the draw. The draw
; runs at the line-210 edge that closes this count.
FRAME_RASTERS   = 3

; Raster compares. 210 is the last map line (switch to normal text).
; 242 is the last black UI line (grey paper for row 24). 251 is the
; first bottom-border line (restore multicolour). The map starts at 51.
RASTER_UI       = 210
RASTER_GREY     = 242
RASTER_MC       = 251
RASTER_MAP      = 51

COLORRAM        = $D800

; Bundle working storage. rom_* / sc_* homes are equates in homes.inc.
INDEX_HOME      = LOAD_STATUS + 1
SPRITE_PTR      = $07F8


