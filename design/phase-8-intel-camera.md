# Phase 8 — Intel and camera

| Field | Value |
| --- | --- |
| Author | FORCE design session |
| Date | 2026-09-21 |
| Status | **Accepted** (landed, then cut) |
| Last worked on | 2026-09-21 |
| Repo path | [`design/phase-8-intel-camera.md`](phase-8-intel-camera.md) |
| Plan | [`development-plan.md`](development-plan.md) (Phase 8 frozen) |
| Source | `src/sdl/game/world.{h,c}`, `src/sdl/game/game.{h,c}`, `src/sdl/game/command.c`, `src/sdl/game/command.h` |
| Intent | [`../doc/FORCE_02_Command_Language_and_UI.md`](../doc/FORCE_02_Command_Language_and_UI.md), [`../doc/FORCE_03_Maps_Regions_and_Sim.md`](../doc/FORCE_03_Maps_Regions_and_Sim.md), [`../doc/FORCE_06_Tiles_Memory_and_Sprites.md`](../doc/FORCE_06_Tiles_Memory_and_Sprites.md) |
| Binary as it is | [`../agents/game.md`](../agents/game.md), [`../agents/known-gaps.md`](../agents/known-gaps.md) |
| Depends on | Phase 7 (script, `exit-*`), Phase 9 slice (`S`/`J`/`M`/`.`) |

The camera is a view. Men, rooms, and next-hop live on the
full map. Focus `F`, back `B`, and `C`/`E` lists are the
intel surface.

**As built:** the mission `x,y,w,h` is the play rect (`play_*`).
The view is 40×20 (`win_w` / `win_h`). Edge-pan, `F`, and `B`
keep that view inside the rect. A rect the size of the view
does not scroll. Farm is NE `40,0,40,20`, so the grass
quadrants stay off screen. `exit-*` and despawn use the
play-rect edge (farm west = x=40). A typed WHERE clamps into
the rect. Scaled `Z` is unbound. `FORCE_FOG` is 0; draw never
hides. Room heat / `MARK` still feed `C`/`E`.

Sections below that describe full-map pan, a scaled `Z`, or an
exit on the TMX edge are the earlier plan. They are not the
binary.

---

## Overview

Farm is already an 80×40 board. `farm_mission` windows the
NE quadrant `40,0,40,20`. NW / SW / SE are grass rooms
(colours 5–7). `win_*` is copied from the mission at load
and never moves. Cursor clamp and playfield blit treat that
rect as the world. `exit-west` and despawn test the window
face, so wave 2 vanishes at x=40 (the farm/NW seam) and a
player cannot walk into NW.

Phase 8 makes `win_x` / `win_y` a camera origin. `win_w` /
`win_h` stay the view size (40×20). Edge-pan, `F`, and `B`
move the origin. `Z` paints the whole map onto the 40×20
playfield. `C` / `X` / `E` walk 16 room bytes, not 4000
cells. SPACE snaps the detail camera.

Fog is room flags, scanned from 32 units. Unseen rooms
paint black. The mission window is `HOME`: Hold the Farm
still shows the NE fight. Off-window grass starts unseen.
A scout walking in sets `SEEN`. Compile `-DFORCE_FOG=0`
(or `#define FORCE_FOG 0` in `world.h`) leaves camera,
overview, and `C`/`E` in place.

`--smoke` is still one frame, exit 0, PLAYING, player
unmoved. Interactive: pan west into NW, `Z` shows four
quadrants, unseen grass is black, `F` snaps, `B` restores.

This is not engineers, not type-join, not a cheat-sheet
overlay, not a C64 emitter.

---

## Data

On `force_world` (with the other 16-row room columns):

```c
uint8_t room_flags[FORCE_ROOM_MAX]; /* SEEN 0x01 LIVE 0x02 HOME 0x04 MARK 0x08 */
uint8_t room_heat[FORCE_ROOM_MAX];  /* 8 on fire / new sighting; -- each logic tick */
uint8_t last_x[FORCE_ROOM_MAX];
uint8_t last_y[FORCE_ROOM_MAX];
```

On `force_game` (view + cycle chrome, not sim):

```c
uint8_t overview;     /* 1 = whole-map paint */
uint8_t cam_prev_ok;
uint8_t cam_prev_x, cam_prev_y, cam_prev_cx, cam_prev_cy, cam_prev_ov;
uint8_t cam_ttl;      /* logic ticks; 0 = stay */
uint8_t cycle_kind;   /* 0 none, 1 contact, 2 mark */
uint8_t cycle_room;   /* 0..15 or 0xFF */
```

No 4K fog plane. No malloc.

`FORCE_FOG` defaults to 1 in `world.h`. Hide paths are
`#if FORCE_FOG`. Intel pulse always runs.

---

## Camera

Display only. `world_tick` does not read `win_*` after this
phase.

**Edge pan.** Detail view: cursor past a screen edge slides
`win_x` / `win_y`, clamped so the 40×20 stays inside the
map. Overview does not pan; the 40×20 *is* the map.

**`F`.** Wizard verb. Skip WHO. WHERE is a cell (RETURN =
cursor, overview-aware). FORCE is optional duration; omit
= stay. Commit saves the current view onto the one-slot
prev stack, leaves overview, centres the window on WHERE
when the map is large enough, and places the cursor on
that cell. `cam_ttl = force * 16` logic ticks (~1 s per
nibble at 15 Hz). `ttl` hitting 0 restores prev.

**`B`.** Instant. Restore prev. Empty stack flashes.

**`Z`.** Instant toggle. Does not write prev. Entering
overview keeps `win_*` for the return trip.

Map cell under the cursor:

- detail: `win_x + cursor_x`
- overview: `cursor_x * sx`, `sx = ceil(width / 40)` (farm 2)

WHERE defaults and implied WHO use that cell (overview:
the 2×2 block).

---

## Exit and despawn

`exit-*` and `where_on_edge` use the **map** face
(`width` / `height`), not `win_*`. Camera pan must not
retarget an already-issued `M exit-west`.

Farm west face is NW (room colour 5, `x0 == 0`). Wave 2
`M exit-west` walks through NW to x=0, then despawns.
Next-hop already links the farm west field to NW on the
open seam at x=39/40. Player `M` into NW is a normal walk.

`spawn_cell_ok` still refuses Chebyshev ≤ 1 of a live MOVE
dest so a same-tick spawn does not vanish. Farm spawn_room
is still colour 4 (x=40–45); dest x=0 is far.

---

## Fog (removable)

Pulse after step + despawn (and once at load after stamps).
Scan 32 units:

1. Clear `LIVE` (keep `SEEN` / `HOME` / `MARK`).
2. Living player: `LIVE | SEEN` on `unit_region`.
3. Living enemy in a room that is currently enemy-visible
   (`LIVE` or `HOME`, or `FORCE_FOG == 0`): set `MARK` and
   `last_x/y`. If `MARK` was clear, this is a new sighting
   → `room_heat = 8`.
4. `LIVE` room with no living enemy: clear `MARK`.
5. Decrement `room_heat` (floor 0).

Load seeds `HOME | SEEN` on every room that **intersects**
the mission window (the load-time `win_*`, before the
player pans). Farm NE rooms 1–4 are home. NW/SW/SE are
not.

Draw (only if `FORCE_FOG`):

| Room | Terrain | Enemy bodies |
|------|---------|--------------|
| not `SEEN` | black | hidden |
| `HOME` or `LIVE` | full | shown |
| `SEEN` only | full | hidden; last-seen pip at `last_*` |

Friendlies always draw. Sim (step, shoot, script) ignores
the flags. Grenade flash follows terrain visibility.

Why HOME: room-level vision without it would hide wave 1
in the west field while the player holds the houses. The
trainer would go blind. HOME keeps the given fight
readable. Fog is the other quadrants and rooms you have
not entered after leaving HOME.

To remove fog: `#define FORCE_FOG 0`. Camera, `Z`, `C`/`E`
stay. `HOME`/`SEEN`/`LIVE` still update; draw stops hiding.

---

## `C` / `E`

Cheap indexes over 16 rooms.

- `C` / `X` (IDLE or SHOW): next room with `room_heat > 0`.
  Wrap. Empty → flash.
- `E` (IDLE or SHOW): next room with `MARK`.
- Mid-order, `C`/`E` are WHO letters (section C / E). `X`
  is never a letter.
- SPACE while a cycle is armed: leave overview, `F`-snap
  to `last_*` (mark) or the room canonical cell (contact),
  arm `cmd_last_who` with a player section in that room
  when one exists, clear the cycle.
- Rifle hit and grenade blast set `room_heat = 8` on the
  shooter and target rooms.

Row 21 while idle/show and a cycle is armed: `CONTACT n` /
`MARK n` with `room_colour`.

`Z`/`B`/`C`/`E`/`X` in IDLE/SHOW do not reset a SHOW line
except `F`, which is a verb and starts a new draft.

---

## Overview paint

`sx = ceil(width/40)`, `sy = ceil(height/20)`. Farm 2×2.
Each playfield cell samples map `(cx*sx, cy*sy)` colour +
tile. Then units at `(unit_x/sx, unit_y/sy)`. Unseen rooms
black. Stale `MARK` fills the last-seen overview cell red.
Cursor is the same yellow border, now a 2×2 of map.

No third zoom. No room-name overlay this phase.

---

## Out

- `F` `Z` `B` `C` `X` `E` bound as specified.
- Camera pan on the 80×40 farm; walking west from NE enters
  NW.
- `exit-west` is the map west face.
- Fog on unseen rooms; `FORCE_FOG 0` compiles it out of
  draw.
- `--smoke` unchanged in outcome.

Not this phase: `?` cheat sheet, doctrine `D *`, type-join
`J I`, engineers, Town/Loop.

---

## Verification

1. `--smoke` exit 0, PLAYING, player unmoved, NE farm
   visible, row 21 `READY`.
2. Interactive: cursor off the left edge of the farm stays
   on the farm. NW grass does not appear. `F` RETURN centres
   inside the play rect. `B` restores. `C` during fire, SPACE
   snaps. Wave 2 `M` exit-west despawns at x=40.
3. `-DFORCE_FOG=0`: NW terrain is visible without a scout;
   `Z`/`F`/`C` still work.
