; Shared equates for the C64 vertical slice. 6502 only.

NONE            = $FF

UNIT_MAX        = 32
SECTION_MAX     = 16
LETTER_MAX      = 8
ROOM_MAX        = 16
COVER_MAX       = 128
PORTAL_MAX      = 24
SCOUT_MAX       = 32
COLS            = 40
FIELD_ROWS      = 20
SCREEN_ROWS     = 25

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

KIND_INFANTRY   = 0
KIND_EMPLACEMENT = 2

CLASS_EMPTY     = 0
CLASS_WALLS     = 1
CLASS_ROOFS     = 2
CLASS_BARRIERS  = 3
CLASS_GOODGUYS  = 4
CLASS_ENEMIES   = 5
CLASS_COLORS    = 6

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

; Always-RAM flags. BSS sits under the BASIC ROM, so the IRQ must not
; keep these there: a KERNAL pass can flip $01 and hide $A000.
; ui_edge is set by the line-210 split (map to text UI). The draw
; waits for a fresh edge. ui_count is how many of those edges have
; passed since the last draw, saturating at FRAME_RASTERS.
ui_edge         = $FB
ui_count        = $FC

; Video frames from the start of world_tick to the draw. The draw
; runs at the line-210 edge that closes this count.
FRAME_RASTERS   = 3

SCREEN          = $0400
COLORRAM        = $D800
CHARSET         = $2000
SPRITE_PTR      = $07F8
SPRITE_DATA     = $3F80
OCC             = $C000          ; 40*20 unit index, $FF empty. Rebuilt on a full paint.


