# C64 port handoff

Session handoff, 2026-09-24. Wave 1 fights under the SDL rifle
rule: closest man inside 9, no sight ray, posture then distance.
The soldier redraw is in: a quiet pass does not touch occupancy
or screen RAM. The frame schedule is in: one `world_tick` every
three video rasters. `pred_ok` evaluates a wait, and a wait is not
tested on the tick it is armed. `despawn_exits` removes an enemy only after his own cell is outside
the playfield. Wave 3 can spawn. Contact-on-arrival, the intel pulse and cyclers, and peel/join are
in the PRG and matched the SDL game in play. Script watches run.
Player strength 0 shows DEFEAT. A win shows SUCCESS.
The SDL binary in `src/sdl/` is the spec. This note is the unfinished
C64 work.

Goal the user set: play Hold the Farm (the vertical slice) in c64m as a
PRG, with parity to the SDL game. Layout under `src/c64/`, am65, every
routine a `.proc` / `.endproc`. Do not stop for design review between
internal phases. Phase 10's LZSS pass is not required for this one board.

## Working agreement

`src/sdl/` is what the game does. `src/c64/` is the port. This note follows
those sources. When the PRG disagrees with the SDL game, find the
difference and fix the port.

Logic ticks once per three video frames. SDL tests
`frames % FORCE_LOGIC_PERIOD` with the period at 3. The PRG runs
`world_tick`, then waits for the line-210 edge that closes those
three frames (the map-to-UI split), then `draw_all`, then starts
the next `world_tick`. The draw begins when the beam leaves the map
and is meant to finish before the beam returns to the top. The old
15-of-50 accumulator was a floor, not this rate. Rows 0–19 stay
multicolour, and a raster IRQ switches rows 20–24 to normal text for
the UI.

c64m checks are windowed unless a task says otherwise, so the picture is
on screen while the control port is used. `tools/coop.sh` assembles the
PRG, starts windowed `../machines/build/c64m`, and runs
`../machines/tools/c64/coop_watch.py`.

## Graphics the user locked

Rows 0–19 are multicolour text. Four colours per cell:

| Bits | Source | VIC |
|------|--------|-----|
| `%00` | red (enemy ink) | `$D021` = 2 |
| `%01` | grey | `$D022` = 11 |
| `%10` | light blue (player ink) | `$D023` = 14 |
| `%11` | that cell's ground colour | colour RAM \| `$08` |

Playfield tiles 0–127 are 8×8 and 2-wide, so each one is one multicolour
character. Index 0 in the PNG is transparent and becomes `%11` (ground
shows through). The authoring sheet is 160 tiles (128×80). Tiles 128–159
are editor glyphs for `rooms` and `properties`. `gen_c64.py` packs only
ids 0–127 into `charset.bin` and into `rom_tile_class` and `rom_tile_force`
(128 bytes each). Those editor tiles skip the 2-wide check and the ink
read. Chars 128–223 stay the UI font. Chars 224–255 stay soldier
composites: terrain wins where it is not paper, then the glyph. Hurt
tints blue pixels to red.

Rows 20–24 are normal text, switched by a raster IRQ before the badline.
Rows 20–23 background black. Row 24 background dark grey. Font is the SDL
8×8 font, bits reversed, at chars 128–223 (screen code = ASCII + 96).
The cursor is sprite 0, a yellow 8×8 box at `$3F80` (pointer `$FE`).

Fog stays off. `Z` stays unbound. The C64 title has an original SID score;
gameplay is otherwise silent. See [`c64-music.md`](c64-music.md). Map planes
in the farm bundle use LZSS.

## Build

From the repo root, then from `src/c64`:

```bash
python3 tools/gen_title.py
python3 tools/gen_c64.py
../machines/build/am65 -i src/c64/force.asm -o /tmp/force.prg --prg
```

CMake target `force_c64` writes `build/force.prg`.
`cmake --build build --target disk` writes `build/force.d64` with
`force.prg`, `normandy.prg`, `bastogne.prg`, and the `campaign` file.
That target is not part of
`cmake --build`. `$C1541` is the c1541 executable when set; otherwise
`c1541` comes from `PATH`. am65 is
`../machines/build/am65`. c64m is `../machines/build/c64m`.
Control port: `../machines/agents/c64/using-c64m.md`. One client.
`load-prg` injects and does not start. `-a` / `--autorun` types `RUN`.
`paste-text-data` with the four bytes `RUN\r` is the reliable start.
`wait-paused` times out if the machine is wedged in the BASIC editor.

Normal windowed play from the repo root uses the PRG directly and mounts the
generated bundle directory as device 8:

```bash
../machines/build/c64m -P -a -p build/force.prg --disk 8=build/c64
```

This path does not use `build/force.d64`; only rebuild the disk target when
testing the disk image itself.

Windowed launch (the usual check; leave `--headless` off unless asked):

```bash
tools/coop.sh
```

That is also the coop session. Pause in the c64m window writes
`build/debug/snap-NNN.txt`. Steer the watcher with
`build/debug/coop_inbox` (`resume`, `arm`, `scrub`, `quit`). Port
defaults to 6510 (`C64M_PORT`). `FORCE_SKIP_BUILD=1` skips the assemble.

Generated output (do not edit): `src/c64/generated/charset.bin`,
`build/c64/normandy.prg`, `build/c64/bastogne.prg`, and
`build/c64/campaign.prg`. `gen_c64.py` deletes a leftover `farm.asm`.

## Map source

`assets/maps/normandy.tmx` is the renamed farm. `assets/maps/bastogne.tmx`
is a copy of it, with the spawn layer named `bastogne` and
`assets/scripts/bastogne.txt` a copy of `farm.txt`. Use those files.
Do not fall back to `HEAD`. A bundle packs every mission that names
the map, in catalog order. Normandy carries `hold_farm` at index 0 and
`take_ridge` at index 1.

The Hold the Farm play rect is still `40,0,40,20`. Colours 1–4 are
still room indexes 0–3, in the same place, so the farm script’s room
numbers do not move. The `farm` layer still starts seven player units.
Cover and portals inside that window are unchanged (35 cover, 5 portals).

The west half is colours 6–9. Rows 20–39 are Take the Ridge: colours
10–15, west to east start, hedges, road, foot, slope, crest. Those
rooms sit outside the farm play rect. The map has fourteen rooms.
Hold the Farm does not walk them. Exit west is still the play edge at x=40.

## Memory

| Region | Address | Role |
|--------|---------|------|
| BASIC stub | `$0801` | `10 SYS 2061` |
| Boot | `$080D` | `sei`, `$01=$36`, `txs`, `jmp main` |
| Packed mission | `$0900` | `map_load` copies the mission chunk here. The SID player does not live here |
| Charset | `$2000`–`$27FF` | locked. `$D018=$18`, screen `$0400`. The menu inverts chars 0–95 and stashes those tiles at `$C000` |
| Sprite | `$3F80` | locked |
| Code | `$4000`–`$9F2B` | `main` is `$4000`; exclusive end `$9F2C`. Class/force tables and the SID player are in this block. They must stay below `$A000`: `map_load` writes the bundle there and a table that has slid into that window is replaced by map bytes |
| Title | `$9F2C`–`$C63B` | `.segdef "TITLE", after="CODE", reclaimable`; exclusive end `$C63C`. 8000 bitmap, 1000 screen, 1000 colour |
| SPARE code | `$2800`–below `$3F80` | Loader and runtime code in the charset-to-sprite gap. The load-name bytes moved into CODE |
| Occupancy | `$C000`–`$C31F` | locked, noemit, `overlap_reclaimable`. `build_occ` fills the 40×20 table. The menu borrows the low 768 bytes as a tile stash |
| BSS | `$C322`–`$CFFF` | noemit, end-anchored at `$CFFF`, `overlap_reclaimable`. `cover_claim` is the low 20 bytes |
| `ui_edge` | `$FB` | not in BSS. Line 210 sets it. |
| `ui_count` | `$FC` | not in BSS. Line 210 increments it, saturating at 3. |
| `screen_hold` | `$FD` | not in BSS. Set at boot. Line 251 clears it and opens the display. |

Boot calls `show_title` (`src/c64/title.asm`). Comment out that `jsr` to open the menu without the picture or the song. The title blanks, copies the picture under the KERNAL, unblanks, starts the music, and `LOAD`s the program `CAMPAIGN` (`build/c64/campaign.prg`) from device 8 while the picture stays up. RETURN dismisses the picture only after that load succeeds. A missing file turns the border red and does not return. The music keeps playing into the menu. F3 does not show the title. The copy runs before `clear_bss`, which is what makes the overlap with occupancy and BSS legal.

The shared menu behavior is in [`game.md`](game.md) under Campaign menu. SDL implements it in `src/sdl/game/menu.c` and shares `build/c64/campaign.prg`. `src/c64/menu.asm` remains the disk, font, and music copy. C64 bindings: cursor left/right and joystick left/right switch columns; cursor up/down and joystick up/down move the bar; fire is RETURN. RETURN on a map enters its missions. RETURN on a mission loads that map's bundle only when it is not resident, then starts it. Right does not launch. RUN/STOP, DEL, or cursor left returns to the map column. A choice repaints rows 8–17 in place and leaves the display on.

`LOADING` is drawn on the menu during the music fade. The page is blanked and cleared before the stashed tiles are copied back, so the inverse bar is gone before those characters become map glyphs. The menu inverts charset chars 0–95 and stashes the real tiles at `$C000`.

While the outcome banner is up, RETURN leaves the battle for the menu. F3 still restarts the mission in place and does not write. During play, RETURN still confirms orders. The in-mission banner is `SUCCESS` or `DEFEAT`.

A win records the count in memory, draws the menu (so the new score is already on the row), then row 22 says `SAVING` and the catalog is written. The raster IRQ stays masked for that write, so the battle splits cannot turn the text page multicolour. F8's second press uses the same `SAVING` write after the lists show the cleared campaign. A loss does not write. HostFS and a disk image accept the save only when the volume is writable; a read-only mount leaves the file untouched and row 22 shows `SAVE FAILED` in light red. The line writer must keep its index: `buf_putc` clears Y, and a lost index repeats one character until `$1C00`–`$1FFF` is full. The title and the menu share the line-250 music IRQ. A mission installs the battle raster handler after the 45-frame fade and `music_stop`. `$D01A` is clear while `CAMPAIGN` is loaded or saved so that IRQ cannot run inside the KERNAL call. The file is a program, the same kind of `LOAD` as a map bundle, so a folder mount, a disk image, and VICE all take it. Saving uses `@:CAMPAIGN`. The image sits at `$1C00` (`camp_limit` `$2000`), which is the map loader's geometry scratch only while a bundle is being placed. The catalog load finishes before that, and a save runs after it is dead.

`$01` stays `$36` so code placed in `$A000`–`$BFFF` executes from RAM. BASIC is banked out; KERNAL and I/O stay. BSS itself sits in the unbanked block under the I/O registers, so the BASIC bit does not hide the variables. A read of `$01` with the high bits set (`$E7`) still means bank bits `$07` when the low 3 bits are 7: BASIC is visible, and any code under it reads as ROM.

`map_ptr` (`src/c64/map.asm`) turns `zA0=x`, `zA1=y` into `zPtr` at
`rom_tiles` and `zPtr2` at `rom_paper`. It uses the row bases built by `build_rows` and the fixed paper-table delta.
It preserves X and `zT0`–`zT3`; Y returns zero and A returns the tile byte.

Zero page for world code: `zPtr`, `zPtr2`, `zA0`–`zA4`, `zR0`, `zT0`–`zT7`.
Draw also uses `zSrc` and `zDst`. World procs must not touch those two.
Carry set means success on peel/join/nudge. `grenade_fx_at` sets carry
when the cell should flash.

## What is actually coded

| File | State |
|------|--------|
| `irq.asm` | Raster split at lines 210, 242, 251. No extra pushes: `$FF48` already saved A/X/Y. 210 is normal text and the draw edge. 242 is the grey bar. 251 restores multicolour in the bottom border and is the one `jmp $EA31`. The other two `jmp $EA81`. Ack is `lda $D019` / `sta $D019`. CIA IRQs masked. The display stays blank until 251 has opened it. |
| `draw.asm` | Occupancy at `$C000`. The first paint writes the farm. A window move copies the overlap and paints the new edge; a jump with no overlap writes the farm. After that `refresh_units` clears the cell a man left, writes his index on the cell he entered, and composites charset `224+index` when his picture changes. A quiet pass does not touch the page. Sprite cursor. |
| `input.asm` | Matrix scan, port 2 stick. Cursor hold steps on the first logic poll, waits four, then steps every poll. RUN/STOP cancels the draft, and so does left-arrow. F3 restarts. |
| `command.asm` | Wizard port of `src/sdl/game/command.c`. Paint is a shortened line, not every SDL branch. |
| `game.asm` | Tick, cursor scroll, F/B camera. The cursor past a screen edge steps the window one cell. `F` centres the window on the cell. |
| `world.asm` | Load, spawn, orders, tick. Movement is in `move.asm`. Rifles, deaths, and grenades are in `combat.asm`. |

`world.asm` loads the play rect, spawns the player stamps, recounts,
and clamps. `unit_spawn` puts the caller's X back and records the
man's room. His `unit_move_wait` is the slot modulo 7: phase 0 stores
0, phases 1–6 store 2–7, because a stored 1 is already due. A step
reloads 7 (sprint 4) and keeps that phase. A think that does not step
leaves the wait at 0, so the gate soldiers are back in step before the
first order. An enemy wave is ordered before its first think. SDL
`force_unit_spawn` uses the same store.

`move.asm` is the movement port of `world.c`: script
orders, enemy spawn pulses, cover assignment, `next_hop`, and the
Bresenham step with sidestep and door crossing.

`section_issue` stores the order. Defend, attack, and retreat set
the assign flag; move sets the release flag. The tick spends that
flag, so each man gets his own cover chip in the order cell's room
and walks to it. A room where-cell is that room's first cover chip,
or `x0+w/2`, `y0+h/2` when the room has none. Script `op_a` is the
letter (enemy A is 8, not 16) and `op_b` is `force<<4|verb`. An
attack order clears the assign flag, so that squad walks a rank
toward the where-cell until contact. Spawn pulses use an open cell
in the spawn room and glyph 10 (east-facing enemy).

The seam walker has to test the cell it is standing on. Using the
next-room id as that row made the door out of room 3 look shut, so
the squad stopped there and the section took the no-path flag.
`world_tick` clears `path_fail_who` each tick, the same as SDL, so
the red NO PATH line only appears on a new failure.

`world_tick` follows the SDL order: decay hurt and grenade ttl,
cover, grenade cooldown, `shoot_all`, `apply_deaths`, script, spawn,
`contact_start`, cover, think, `despawn_exits`, `intel_pulse`.
Combat trace lines are not printed.

`combat.asm` follows the SDL rifle and grenade rule. A rifle picks
the closest living other-bank man at Chebyshev under 10 and does not
call `ray_clear`. The walk stays in the file so it can be turned
back on. Grenade splash still uses it: walls block the disk, and the
landing cell always hits. Damage is the posture number, then halved
from dist 5. A shot that lands starts the 8-tick reload. A halved 0
does not. A grenade throws only when the nearest other-bank man is
standing on his assigned chip at Chebyshev 2–5. A man in the open
does not draw one, and a friendly in the blast disk aborts that
target. Blast damage stays 8 with no posture cut. `shoot_all` packs
living players and living enemies (`side_pl`, `side_en`) in slot
order, and the rifle and grenade scans walk the other list. An axis
that already reaches the best distance loses, and the larger axis is
the distance. Distance 10 still misses. A tie keeps the earlier slot.
A man dropped earlier in the volley is skipped on `unit_hp` 0.
`find_on_cell` and the grenade friendly check still walk every slot.
Deaths clear the man, relead, and may reassign cover or halt a broken
section.
`section_relead` trashes Y, so the death walk has to keep its
section index itself.

The steady draw repaints a 5×5 disk when that bank's ttl or origin
changes, and once more when the ttl hits 0. `grenade_fx_at` sets
carry for a walkable cell inside a live disk. Walls and roofs stay
unlit.

Confirmed in the window, 2026-09-23, after `D A 64,9`. The six
friendlies take room-1 cover: five on the grade-3 chips at x=62 and
one at x=66. Wave 1 crosses room 3 (x ≤ 52) at 16 hp. The first
drops are at x=53, the west edge of room 2. The houses stay at 16
through that band. Player grenade stock stays 8, because wave 1 is
in the open. `script_waiting` stays set, so wave 2 does not spawn.

## Redraw

`refresh_units` does not call `build_occ`. Every vacated cell is
cleared before any man is stamped, so one man can step onto a
cell another man left in the same tick, including a man who died.
The cell he left gets the map character and occupancy `$FF`. The
cell he entered gets his index and screen code `224+index`.
Colour RAM stays the cell's paper colour. Grenade disks still
repaint through `draw_cell`. `build_occ` remains the full-field
paint, used when `drawn` is clear or the window moved.

`mix_byte` mixes one character byte. Terrain wins where the pixel
is not paper (`%11`). A hurt player's blue glyph pixels (`%10`)
become red (`%00`); a hurt enemy's red pixels become blue. Paper
terrain copies the glyph.

Checked on 2026-09-23. Enemy 11 stepped from (55, 8) to (56, 8).
The cell he left is tile `$70` with occupancy `$FF`. The cell he
entered is char `$EB` (224+11). Both cells keep paper colour
`$0F`, the same as the grass he had not stood on. His hurt
composite matches the mixer, and a friendly hurt tint matches
then clears. Numbers are in [`c64-profile.md`](c64-profile.md).

## Schedule

One game frame is one `world_tick`, then the draw. `world_tick` runs
as soon as the previous draw returns. `wait_ui` then spins until
line 210 has fired three times since that draw. Line 210 is the
split that switches the UI rows to normal text, which is the bottom
of the map. The draw starts on that edge, while the beam is in the
UI and the border, and it is supposed to finish before line 51
brings the beam back to the top of the map. Line 251 restores
multicolour in the bottom border and does not gate the draw. The next `world_tick`
starts immediately after the draw. An edge that was already set when
the logic returned is dropped, and the draw waits for the next
line 210, so a late logic pass does not paint the map under the
beam. The line-251 IRQ latches the matrix and the stick on every video
frame. `input_poll` consumes that latch once per logic frame, before
`world_tick`. A press between logic frames stays set. RUN/STOP and
left-arrow drop latched command edges.
`FRAME_RASTERS` is 3. The port does not read `$02A6`. A PAL room-2
shot on 2026-09-24 spent about 23,300 cycles in the logic, spun
25,403 cycles, then drew for 5,244. `draw_all` was entered at
raster 213. Two video frames would hold that fight. It stays at
three: a scroll still repaints an edge (and copies the rest), and the
spare is kept for that and for whatever else shows up. Write-up:
[`../design/frame-schedule.md`](../design/frame-schedule.md).

## Source review follow-ups

[`c64-issues.md`](c64-issues.md) records the 2026-09-24 handwritten-source review,
small fixes, deferred correctness findings, and measured code-space headroom.

## Next

Played and matching SDL: an enemy attack holes up on entering the
destination room, Shift+C and Shift+E cycle heat and marks, and
`S A B` / `J B A` move men between letters. Script watches run
before the beat, including while a wait is armed. Farm: player
strength 0 loses; five friendlies in room 4 move the spawn room
to 2, once.

`pred_ok` is in. Carry set means the armed pair is true. A second
index of `$FF` means there is no second predicate. Who `$FF` is the
player bank. The predicate is not tested on the tick the wait is
armed: the arm stores `sc_op_c` as `script_wait_beat` and returns.
The next tick, on success, sets `script_pc` from `sc_beat_pc`. That
is what keeps wave C from being born at strength 0 and winning in
the same step when a friendly is already in room 3.

An exit order's cell is one step outside the playfield, on whichever
face was named. The man walks to that edge and then takes the step
off. `despawn_exits` clears him only once his own cell is outside.
Standing on the edge cell does not. Confirmed on the running PRG:
the first clear stopped with section 9 still alive at (39, 13), move
order (39, 10). The playfield starts at x=40, so he had already
stepped off the west side.

Predicate kinds, matching `src/sdl/generated/force_data.h`:

| Kind | Value | True when |
|------|-------|-----------|
| `NONE` | 0 | always |
| `STR_EQ` | 1 | `bank_strength(who) == a` |
| `STR_LE` | 2 | `bank_strength(who) <= a` |
| `IN_GE` | 3 | `count_in_room(who, a) >= b` |
| `REACHED` | 4 | `count_in_room(who, a) >= 1` |
| `AT_CELL` | 5 | a living man of `who` is on `(a, b)` |
| `CLOCK_GE` | 6 | `script_clock >= a \| (b << 8)` |
| `REL_GE` | 7 | friendlies in room `a` >= enemies there |
| `STR_GE` | 8 | `bank_strength(who) >= a` |
| `JOB_IDLE` | 9 | `spawn_job_rem == 0` |

Who `$FF` is the player bank (sections 0–7 summed, or any
friendly in the room). Any other who is one section.
`bank_strength` and `count_in_room` are `force_world_tick`'s
helpers in `src/sdl/game/world.c`. Tables are `sc_pred_kind`,
`sc_pred_who`, `sc_pred_a`, `sc_pred_b`.

Still open:

| Routine | State |
|---------|--------|
| script watches | in. Checked before the beat. Farm: player strength 0 loses; five friendlies in room 4 move the spawn room to 2, once |
| `contact_start` | in. Called after the spawn and before the second cover pass. An attacking enemy section sets CONTACT and ASSIGN once any of its men is in the order cell's room |
| `intel_pulse`, `intel_next_hot`, `intel_next_mark`, `intel_player_in_room` | in. The pulse runs at the end of the tick. Fog is off, so an enemy marks his room. Hot cycles heat, mark cycles ROOM_MARK, and the room pick returns the first player letter there |
| `section_peel`, `section_join` | in. Carry set on success. Peel keeps the wizard's zT4/zT5. Join keeps zA0 and zA1. A KILL order rejects peel |
| `unit_nudge` | in. `.` plus a cell gives that man his own MOVE, HALT, KILL, DEFEND, ATTACK, or RETREAT |

SDL sources for the real port, in this order after the crash is gone:

1. `src/sdl/game/world.c` and `world.h` (tick order is at the bottom of `world.c`)
2. `src/sdl/game/command.c` (the asm paint is lossy)
3. `src/sdl/game/game.c` (camera, draw order)
4. `src/sdl/sdl/input.c` (edge priority: ESC, RETURN, DEL, comma, space, period, digits, letters)

## IRQ and the first painted frame

Verified with `c64m --pal -a -p /tmp/force.prg` and a control port. The PRG stays in the program. `$01` stays `$36`. `$0314` stays `irq`. Screen row 0 is the NE farm (mostly `$70`, not `$20`). The UI rows are normal-text char 128. A grabbed frame shows the farm, the A–H roster, and the VERB/WHO/WHERE/FORCE line.

The install was already right: `lda #<irq` / `sta $0314` is the first byte of `.proc irq`. `$FF48` pushes A, X, and Y, then `JMP ($0314)`. The handler was pushing those again and then pulling three bytes and `RTI`. That `RTI` took the KERNAL-saved Y as flags and the saved X and A as the PC. In `wait_frame` A is 0, so the CPU ran into page zero, hit `BRK`, and `$FE66` (still the BASIC break vector) restored `$0314` to `$EA31` and opened the editor.

`$EA31` is the KERNAL IRQ body (clock, cursor blink, `SCNKEY`). It ends at `$EA81` with the pop and `RTI`. It is not a substitute for a balanced stack. Jumping there from all three splits would tick the clock three times a frame and run the keyboard scan across the next badline. The handler does not push. The line-210 and line-242 splits `jmp $EA81`. The line-251 split is the first bottom-border line, so it `jmp $EA31` once per frame. `irq_init` sets `$CC` to 1 so the blink path does not write screen RAM. The line-251 handler scans `$DC00` before `jmp $EA31`, so the latch and the KERNAL keyboard scan do not share the port. `input_poll` does not touch `$DC00`. The three IRQs land on rasters 210, 242, and 251, and `$D016` is `$D8` on the field and `$C8` on the UI. Boot leaves the display blank until line 251 has run, so the first colour fill is not visible. F3 does not blank.

The picture that stayed garbage after the IRQ stopped crashing was the first `input_poll`. `key_edge` / `key_down` put the key's row in X. The digit walk then did `inx` / `cpx #10` on that row. A row is 0–7, so X never became 10, the walk never returned, and `draw_all` never ran. Both routines now save X and Y. The letter walk had the same shape.

`txs` in the boot stub still throws away the SYS return. A normal `rts` from `main` is not how this goes back to BASIC.

The screen is persistent. `draw_all` paints the whole field and the text once (before `cli`, and again after a restart or a window move). Later passes store a cell only when that man's count, position, hp, effect, or glyph differs from what is already there, and a command cell only when its glyph or colour differs. The UI is not cleared on those passes. Those later passes run after `wait_ui`, at the line-210 split, not on every video frame. `input_poll` runs once per logic frame, at the top of the loop.

## Out of scope until the slice runs

Apple II. LZSS. Pageant truck and radio. Engineers, type-join, Town/Loop.
The rest of Phase 9. Scaled overview and fog (already cut on SDL).
