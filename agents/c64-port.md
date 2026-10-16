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
internal phases. Staged compressed loading and banked mission storage landed on 2026-10-11.

## Memory and support weapons — 2026-10-16

`tactics.asm` owns compact spawn identity, support-weapon rules, ammunition,
last-drawn kind and the status-formatting cache. Nests have 48 HP, fixed
cardinal 90-degree firing arcs, wall-clear range below 10 and reload 3.
Landed rifle bullets do at most 1 damage to nests; grenades retain damage 8.
Bazooka crews have 16 HP and four rounds, prioritize nests with a wall-clear
ray below range 10, deal 32 direct damage and reload 20. Without a reachable
nest or ammunition they use the existing rifle rules. Kind 1 is reserved.
Both ports draw a grey tripod/base or launcher tube over the unit glyph.

Stepper state is shared scratch for one `think_i`, never per-unit persistent
state. Formation caches hold offset IDs, decoded relative to the order cell.
`apply_deaths` skips recount/section maintenance when neither death mask is
set. Row-to-screen addressing shares lookup tables. Status formatting runs
only when command fields or outcome change. Plank completion uses a small
dirty list and preserves the incremental soldier renderer.

The generated doorway image is **514 bytes**, including its reserved second
header byte. `door_lo-door_n == 2` and its total extent are assembly assertions.
Reference-count cleanup must preserve packed-image padding. Routing home
addresses come from `assets/c64-layout.json`; tests must not hardcode them.

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
composites: terrain wins where it is not paper, then the glyph, except
finished bridge tile 81, where the soldier covers the deck. Hurt tint
changes the soldier’s blue pixels to red before composition.

Rows 20–24 are normal text, switched by a raster IRQ before the badline.
Rows 20–23 background black. Row 24 background dark grey. Font is the SDL
8×8 font, bits reversed, at chars 128–223 (screen code = ASCII + 96).
The cursor is sprite 0, a yellow 8×8 box at `$3F80` (pointer `$FE`).

Fog stays off. `Z` stays unbound. The C64 title has an original SID score;
gameplay is otherwise silent. See [`c64-music.md`](c64-music.md). Farm tile
and paper planes in `c0` use LZSS.

## Build

Use `cmake --build build --target force_c64`; direct assembly of `force.asm`
produces an intermediate image, not a launchable game. `build/force.prg` is
now the bootstrap. Mount `build/c64` as device 8, then autorun that PRG.
`tools/coop.sh` builds and launches this configuration. `cmake --build build
--target disk` creates `build/force.d64` including all startup SEQ chunks,
`index.seq` (CBM name `INDEX`), `c0.seq` `c1.seq` `c2.seq` (CBM names `C0`
`C1` `C2`), `bank.seq` (CBM name `BANK`), and campaign data. c1541 must be
on PATH or set with C1541.
Runtime symbols are `build/c64/game-image.sym`; `build/force.sym` describes
only the bootstrap. Generated files must not be edited. Generation preserves
existing `build/c64/campaign.prg` scores, matched by stem. A legacy id such
as `hold_farm` is copied onto `farm` once.

See [C64 loading](c64-loading.md) for the current format, banking, memory
ownership, extension contract, and verification results.

## Map source

Each catalog stem is its own map: `farm`, `cross`, `river`, `base`, `ridge`,
`bastogne`. The C64 packs them into containers. `c0` holds farm, cross, and
river. `c1` holds base and ridge. `c2` holds bastogne. `bastogne.tmx` is the
old north-east 40×20. `assets/scripts/bastogne.txt` is still a copy of
`farm.txt`. The cropped map has four rooms (colours 1–4) and no deck. Use
those files. Do not fall back to `HEAD`.

`farm` is 40×20. Colours 1–4 are still room indexes 0–3, in the same
place, so the farm script’s room numbers do not move. The `actors` layer
still starts seven player units. Cover and portals are unchanged (35
cover, 5 portals). Colour 4 starts at x=0. Exit west is the west edge.

`cross` and `river` are the old north-west 40×20 (colours 6–9, 16, and
18). Colour 16 is the 9×9 at (0,11). Colour 18 is the 6×9 at (26,11).
`base` is the old west 40×40; colour 12 there is 10 wide. `ridge` is the
old south strip, 80×20, local rows 0–19; colour 12 there is 12 wide.
Hold the Farm walks colours 1–4 only.

## Memory

The authoritative layout is `assets/c64-layout.json`. Assembly origins,
capacities, routing homes, producer destinations, and compatibility identity
are generated from it. `build/c64/memory-report.json` and `.md` are generated
from fresh assembly and packaged files, with phase overlap and capacity
checks. [C64 loading](c64-loading.md) records the ownership transitions.

The selected immutable mission occupies exactly `$0900–$0B55` (597 bytes);
DECK still begins at `$0B55`. The resident container lives at `$E600–$FFFA`
(6650 bytes) after bitmap shutdown. The banked validator occupies
`$E000–$E600` and is loaded from `bank.seq`. RAM vectors are reserved at
`$FFFA–$10000`.

## What is actually coded

| File | State |
|------|--------|
| `irq.asm` | Raster split at lines 210, 242, 251. No extra pushes: `$FF48` already saved A/X/Y. 210 is normal text and the draw edge. 242 is the grey bar. 251 restores multicolour in the bottom border and is the one `jmp $EA31`. The other two `jmp $EA81`. Ack is `lda $D019` / `sta $D019`. CIA IRQs masked. The display stays blank until 251 has opened it. |
| `draw.asm` | Occupancy at `$C000`. The first paint writes the farm. A window move copies the overlap and paints the new edge; a jump with no overlap writes the farm. After that `refresh_units` clears the cell a man left, writes his index on the cell he entered, and composites charset `224+index` when his picture changes. A quiet pass does not touch the page. Sprite cursor. |
| `input.asm` | Matrix scan, port 2 stick. Cursor hold steps on the first logic poll, waits four, then steps every poll. RUN/STOP cancels the draft, and so does left-arrow. F3 restarts. |
| `command.asm` | Wizard port of `src/sdl/game/command.c`. Paint is a shortened line, not every SDL branch. `B` is BUILD. On IDLE and SHOW, `G` restores the previous camera. In the WHO slot `G` is still section index 6. |
| `game.asm` | Tick, cursor scroll, `F`/`G` camera. The cursor past a screen edge steps the window one cell. `F` centres the window on the cell. `G` restores the previous window. |
| `world.asm` | Load, spawn, orders, tick. Movement is in `move.asm`. Rifles, deaths, and grenades are in `combat.asm`. |
| `deck.asm` | Engineer pour, local plank movement, and the wall-gap slide. Segment `DECK` at `$0B55`. |

`world.asm` loads the play rect, spawns the player stamps, recounts,
and clamps. Each FMSN record carries a raw routing chunk (818 bytes):
24 portal-from ids, 24 portal-to ids, 256 next hops, and the 514-byte
fixed doorway image. The loader stages it at `$1C00` after expanding
geometry, then `install_routes` scatters it into BSS. The routing patch
program is 256 bytes at `$BF00`–`$BFFF`, immediately after active mission
data. Container bytes live at `$E600` and must not overlap those homes.
A mismatched layout id fails the load and must be regenerated with the game.

The pipeline computes every combination of relevant bridge boundary cells.
Doorway slots and crossing-pool capacities remain fixed across variants;
a zero crossing count closes a reserved slot, which `door_find` ignores.
The program contains 16 deck-cell state masks, a state-to-list index,
shared reversible page patches, and shared lists of those patches.
Activation restores the current state's changed bytes to their initial
values, then applies the selected state's changes. Startup builds only the
small portal bitset; restart closes the deck and activates state zero.
There is no runtime routing calculator. Campaign scratch at `$1C00` can
be reused without damaging the persistent program. The pipeline rejects
variants exceeding the 256-byte program, 24 doorway slots, or 176 crossing
positions; assembly assertions protect the patch destination addresses.
Normandy has four routing states in 232 bytes, while Bastogne has one in
18 bytes. Both programs are padded to 256 bytes. This replaces the former
256-byte initial-hop backup, so persistent RAM does not grow. The program
adds a 256-byte chunk and 10-byte directory entry to each bundle; current
Normandy and Bastogne PRGs are 3376 and 2644 bytes. Rebuild and relaunch
`build/force.prg` with `build/c64/{normandy,bastogne}.prg` together (or rebuild
the disk target when using a D64).

`unit_spawn` puts the caller's X back and records the
man's room. His `unit_move_wait` is the slot modulo 7: phase 0 stores
0, phases 1–6 store 2–7, because a stored 1 is already due. A step
reloads 7 (sprint 4) and keeps that phase. A think that does not step
leaves the wait at 0, so the gate soldiers are back in step before the
first order. An enemy wave is ordered before its first think. SDL
`force_unit_spawn` uses the same store.

`move.asm` is the movement port of `world.c`: script
orders, enemy spawn pulses, cover assignment, `next_hop`, and the
Bresenham step with sidestep and door crossing.

`deck.asm` matches the SDL pour and local stepping. A living
non-emplacement soldier ordered onto a deck cell pours that connected
run: one point per man per tick into the adjacent unfinished plank
(most progress, then north, then west). Two men on one cell finish it
in half the time. The point does not spill. Cost 0 never finishes.
Load stamps tile 80. A finished cell is tile 81, which stays open on
blue paper. Each completion ORs its generated state mask into
`route_pending`. Interior cells have mask zero and cause no routing change.
After all pours, `build_pulse` activates the combined state once if changed.
Normandy's six planks yield 64 physical completion combinations but only
four routing states. Activation takes at most 5.9 ms in the PAL emulator;
a whole pulse with two simultaneous boundary completions takes 22.1 ms.
Tile 80 stays closed.
Plank completion clears `drawn`, requesting a full repaint at the next
scheduled draw. This also refreshes finished planks that no soldier visits;
construction itself does not write screen RAM. Multiple completions before
that draw share one repaint.
The plank pixels are grey: cyan and brown are not shared multicolour
inks, and the cell paper is the water, so a paper-coloured glyph would
paint as more water. Clear pixels stay paper and show the river. The
soldier's non-paper pixels cover the deck, and his paper pixels show the
plank beneath. This ground rule is specific to finished tile 81; walls
and other terrain retain their foreground masking. Hurt tint is applied
to the soldier before composition.
Movement over finished planks uses the ordinary stepper, without bridge
steering, a completed-crossing latch, or a special diagonal exception.
A diagonal needs at least one open cardinal neighbour, just like any other
terrain. Unfinished planks remain impassable.
When the preferred cardinal is terrain, the other axis is taken only if
that step opens the preferred direction; otherwise he steps toward the
nearer gap, at most 8 cells, and a tie goes right. A longer wall keeps the
one-cell right-then-left dodge. Room routing still uses baked doorway patches.
The soldier composite is still drawn over the cell, so tile 81 stays
under him. Geometry stores the deck cells after the scout columns
(count, then x, then y, at most 16). `deck_cost` is the 13th script
scalar, `sc_deck_cost`. Paper bits 4–7 hold a dry-component id baked
by the map generator. `cell_open` tests the low nibble.
Arming runs in `world_load`, before the first picture, and resets deck
progress and stamps tile 80. `tools/gen_c64.py` precomputes the dry banks
that touch deck cells and packs their component ids into paper bits 4–7.
Those labels are retained for bundle compatibility but movement no longer
reads them. There is no runtime bridge-connectivity or dry-bank flood.
The only construction flood marks the connected deck run named by BUILD.


`section_issue` stores the order. Defend, attack, and retreat set
the assign flag; move and build set the release flag. The tick spends that
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
`contact_start`, cover, `build_pulse`, think, `despawn_exits`,
`intel_pulse`.
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
Standing on the edge cell does not. On `farm` the west edge is x=0,
so exit-west steps off that side.

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
