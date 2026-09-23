# C64 port handoff

Session handoff, 2026-09-23. Wave 1 fights under the SDL rifle
rule: closest man inside 9, no sight ray, posture then distance.
The next task is the soldier redraw. `refresh_units` still wipes
the occupancy page on every pass. The mission still stops on the
first script wait, so the PRG is not a finished Hold the Farm.
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

SDL locks logic at 15 Hz on purpose. The C64 should complete those same 15
ticks each second while the CPU runs flat out. The 15/50 accumulator is
that rate. Rows 0–19 stay multicolour, and a raster IRQ switches rows
20–24 to hires text for the UI.

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

Tiles are already 8×8 and 2-wide, so each tile is one multicolour character.
Index 0 in the PNG is transparent and becomes `%11` (ground shows through).
A soldier is composited into charset slots 224–255: terrain wins where it
is not paper, then the glyph. Hurt tints blue pixels to red.

Rows 20–24 are hires text, switched by a raster IRQ before the badline.
Rows 20–23 background black. Row 24 background dark grey. Font is the SDL
8×8 font, bits reversed, at chars 128–223 (screen code = ASCII + 96).
The cursor is sprite 0, a yellow 8×8 box at `$3F80` (pointer `$FE`).

Fog stays off. `Z` stays unbound. No SID. No LZSS.

## Build

From the repo root, then from `src/c64`:

```bash
python3 tools/gen_c64.py
../machines/build/am65 -i src/c64/force.asm -o /tmp/force.prg --prg
```

CMake target `force_c64` writes `build/force.prg`. am65 is
`../machines/build/am65`. c64m is `../machines/build/c64m`.
Control port: `../machines/agents/c64/using-c64m.md`. One client.
`load-prg` injects and does not start. `-a` / `--autorun` types `RUN`.
`paste-text-data` with the four bytes `RUN\r` is the reliable start.
`wait-paused` times out if the machine is wedged in the BASIC editor.

Windowed launch (the usual check; leave `--headless` off unless asked):

```bash
tools/coop.sh
```

That is also the coop session. Pause in the c64m window writes
`build/debug/snap-NNN.txt`. Steer the watcher with
`build/debug/coop_inbox` (`resume`, `arm`, `scrub`, `quit`). Port
defaults to 6510 (`C64M_PORT`). `FORCE_SKIP_BUILD=1` skips the assemble.

Generated output (do not edit): `src/c64/generated/farm.asm`,
`src/c64/generated/charset.bin`.

## Map source

`assets/maps/farm.tmx` compiles. Use that file. Do not fall back to
`HEAD`.

The play rect is still `40,0,40,20`. Colours 1–4 are still room indexes
0–3, in the same place, so the farm script’s room numbers do not move.
The eight player spawns are unchanged. Cover and portals inside the
window match the previous committed map (35 cover, 5 portals). One
terrain cell and six colour cells inside the window differ.

The grass quadrants are no longer three big rooms. The fixed map has
ten rooms: colours 6–11 sit outside the play rect. `next_hop` for the
whole board changes. Hold the Farm does not walk those rooms. Exit west
is still the play edge at x=40.

## Memory

| Region | Address | Role |
|--------|---------|------|
| BASIC stub | `$0801` | `10 SYS 2061` |
| Boot | `$080D` | `sei`, `$01=$36`, `txs`, `jmp main` |
| Charset | `$2000`–`$27FF` | locked. `$D018=$18`, screen `$0400` |
| Sprite | `$3F80` | locked |
| Code + farm tables | `$4000` up (~`$75D4`) | `main` is `$4000` |
| BSS | `$A000` | noemit. Needs `$01=$36` (RAM under BASIC, KERNAL and I/O stay) |
| `frame_flag` | `$FB` | not in BSS |

`$36` is required because world RAM is under the BASIC ROM. A read of
`$01` with the high bits set (`$E7`) still means bank bits `$07` when
the low 3 bits are 7: BASIC is visible and BSS reads are ROM.

`map_ptr` (`src/c64/map.asm`) turns `zA0=x`, `zA1=y` into `zPtr` at
`rom_tiles` and `zPtr2` at `rom_paper`. Width is 80 (`y*64+y*16+x`).
It trashes X and `zT0`–`zT3`.

Zero page for world code: `zPtr`, `zPtr2`, `zA0`–`zA4`, `zR0`, `zT0`–`zT7`.
Draw also uses `zSrc` and `zDst`. World procs must not touch those two.
Carry set means success on peel/join/nudge. `grenade_fx_at` sets carry
when the cell should flash.

## What is actually coded

| File | State |
|------|--------|
| `irq.asm` | Raster split at lines 50, 210, 242. No extra pushes: `$FF48` already saved A/X/Y. Field splits `jmp $EA81`; the border split `jmp $EA31` once a frame. Ack is `lda $D019` / `sta $D019`. CIA IRQs masked. |
| `draw.asm` | Occupancy at `$C000`. The first paint writes the farm and the text. After that a screen store is a changed man-cell, a changed command glyph/colour, or a grenade disk whose ttl or origin changed. `refresh_units` still calls `build_occ` first and clears 800 bytes on every pass. Sprite cursor. |
| `input.asm` | Matrix scan, port 2 stick, SDL repeat (delay 14, rate 4). Left-arrow is ESC. F3 restarts. |
| `command.asm` | Wizard port of `src/sdl/game/command.c`. Paint is a shortened line, not every SDL branch. |
| `game.asm` | Tick, cursor clamp, F/B camera. Farm does not scroll. |
| `world.asm` | Load, spawn, orders, tick. Movement is in `move.asm`. Rifles, deaths, and grenades are in `combat.asm`. |

`world.asm` loads the play rect, spawns the player stamps, recounts,
and clamps. `unit_spawn` puts the caller's X back and records the
man's room. `move.asm` is the movement port of `world.c`: script
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

`world_tick` now follows the SDL order through the second cover
pass and `think_all`: decay hurt and grenade ttl, cover, grenade
cooldown, `shoot_all`, `apply_deaths`, script, spawn, cover, think.
It still does not call `contact_start`, `despawn_exits`, or
`intel_pulse`. Combat trace lines are not printed.

`combat.asm` follows the SDL rifle and grenade rule. A rifle picks
the closest living other-bank man at Chebyshev under 10 and does not
call `ray_clear`. The walk stays in the file so it can be turned
back on. Grenade splash still uses it: walls block the disk, and the
landing cell always hits. Damage is the posture number, then halved
from dist 5. A shot that lands starts the 8-tick reload. A halved 0
does not. A grenade throws only when the nearest other-bank man is
standing on his assigned chip at Chebyshev 2–5. A man in the open
does not draw one, and a friendly in the blast disk aborts that
target. Blast damage stays 8 with no posture cut. Deaths clear the
man, relead, and may reassign cover or halt a broken section.
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

## Next, before anything else

Stop `refresh_units` from rebuilding occupancy on every pass.
The screen is already sticky, and the farm does not scroll, so a
quiet pass must not touch screen RAM or the occupancy page. The
baseline is [`c64-profile.md`](c64-profile.md). Repeat it with
[`../tools/c64_profile.py`](../tools/c64_profile.py).

`build_occ` fills `$C000`–`$C31F` with `$FF` and then stamps every
living man. The fill is 5,444 cycles. `refresh_units` calls it
before the compare, including on a pass where no man changed.
Screen RAM is not written by that wipe. The page exists so
`draw_cell` can ask who stands on a cell.

On the baseline pass one enemy moved and the six friendlies did
not. The compare already skips a man whose count, position, hp,
effect, and glyph match. The stores were the cell he left and the
cell he entered. Those two cells do not need an 800-byte clear.

For a man who moved: write `$FF` in the occupancy byte he left,
write his index on the cell he entered, store the map character
in the old screen cell, and rebuild charset slot `224+index` for
the new cell. Men do not share a cell, so the vacated byte is
empty. `build_occ` stays the full-field paint, used when `drawn`
is clear or the window moved.

The new character is real work. Terrain wins where it is not
paper, then the glyph, and a hurt man tints blue pixels to red.
`mix_byte` does that one pixel-pair at a time across eight bytes.
That mixer is the rest of the "Drawing men" row after the wipe.
Eight bytes should cost a fraction of what it costs now. The
picture of a man on a cell does not change.

A pass where nobody moved does no composite and no occupancy
clear. Do not redraw the farm, the command line, or an unchanged
man as part of this.

Check with the profile script. The hunt is the same: `D A 64,9`,
then one logic pass with a living enemy at map x 55–58. Drawing
men was 10,080 cycles inside a 35,778-cycle pass. After this it
is the two cell stores plus one composite. In the window the man
stands on his cell, the cell he left shows the map, and a hurt
tint still shows.

## After the redraw

`pred_ok`. It is `clc` / `rts`, so a `wait` never succeeds.
`script_step` stores `sc_op_a` / `sc_op_b` as the predicate pair
and calls `pred_ok` while `script_waiting` is set. Carry set means
the pair is true. A second index of `$FF` means there is no second
predicate.

Regenerate from `assets/scripts/farm.txt` and read the pred tables.
Do not trust an old index. The first wait is `A.strength == 4`
(letter A is who 8). When that is true, beat `cover` orders A to
defend room 2 at force 10. The next wait is `A.strength == 0`, and
beat `contact` spawns letter B and orders it to defend room 2.
Wave C defends room 3 at force 10, so it does not halt at half
strength. Check the first wait in the window after the same
`D A 64,9` hold. Do not start contact-on-arrival or the west-edge
despawn in this change.

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

Still open after that, not this task:

| Routine | State |
|---------|--------|
| script watches | `script_step` does not run them. Farm: player strength 0 loses; five friendlies in room 4 move the spawn room to 2, once |
| `contact_start` | not called. An enemy attack does not take cover on entering the dest room |
| `despawn_exits` | not called. A move onto the play edge does not remove the man |
| `intel_pulse`, `intel_next_hot`, `intel_next_mark`, `intel_player_in_room` | pulse is not called. The cyclers return `NONE` |
| `section_peel`, `section_join`, `unit_nudge` | `clc` / `rts` |

SDL sources for the real port, in this order after the crash is gone:

1. `src/sdl/game/world.c` and `world.h` (tick order is at the bottom of `world.c`)
2. `src/sdl/game/command.c` (the asm paint is lossy)
3. `src/sdl/game/game.c` (camera, draw order)
4. `src/sdl/sdl/input.c` (edge priority: ESC, RETURN, DEL, comma, space, period, digits, letters)

## IRQ and the first painted frame

Verified with `c64m --pal -a -p /tmp/force.prg` and a control port. The PRG stays in the program. `$01` stays `$36`. `$0314` stays `irq`. Screen row 0 is the NE farm (mostly `$70`, not `$20`). The UI rows are hires char 128. A grabbed frame shows the farm, the A–H roster, and the VERB/WHO/WHERE/FORCE line.

The install was already right: `lda #<irq` / `sta $0314` is the first byte of `.proc irq`. `$FF48` pushes A, X, and Y, then `JMP ($0314)`. The handler was pushing those again and then pulling three bytes and `RTI`. That `RTI` took the KERNAL-saved Y as flags and the saved X and A as the PC. In `wait_frame` A is 0, so the CPU ran into page zero, hit `BRK`, and `$FE66` (still the BASIC break vector) restored `$0314` to `$EA31` and opened the editor.

`$EA31` is the KERNAL IRQ body (clock, cursor blink, `SCNKEY`). It ends at `$EA81` with the pop and `RTI`. It is not a substitute for a balanced stack. Jumping there from all three splits would tick the clock three times a frame and run the keyboard scan across the next badline. The handler does not push. The line-50 and line-210 splits `jmp $EA81`. The line-242 split is in the border, so it `jmp $EA31` once per frame. `irq_init` sets `$CC` to 1 so the blink path does not write screen RAM. `input_poll` holds `SEI` across `$DC00` because that bottom split's `SCNKEY` uses the same port. On c64m the three IRQs land on rasters 50, 210, and 242, and `$D016` is `$D8` on the field and `$C8` on the UI.

The picture that stayed garbage after the IRQ stopped crashing was the first `input_poll`. `key_edge` / `key_down` put the key's row in X. The digit walk then did `inx` / `cpx #10` on that row. A row is 0–7, so X never became 10, the walk never returned, and `draw_all` never ran. Both routines now save X and Y. The letter walk had the same shape.

`txs` in the boot stub still throws away the SYS return. A normal `rts` from `main` is not how this goes back to BASIC.

The screen is persistent. `draw_all` paints the whole field and the text once (before `cli`, and again after a restart or a window move). Later passes store a cell only when that man's count, position, hp, effect, or glyph differs from what is already there, and a command cell only when its glyph or colour differs. The UI is not cleared on those passes. Logic is 15 ticks per 50 video frames, the SDL rate. Input and the sprite cursor still run every video frame.

## Out of scope until the slice runs

Apple II. LZSS. Pageant truck and radio. Engineers, type-join, Town/Loop.
The rest of Phase 9. Scaled overview and fog (already cut on SDL).
