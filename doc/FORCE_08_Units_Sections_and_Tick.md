# FORCE

## Units, sections, and tick

*Move and/or shoot · letters own orders · no unassigned caste*

A unit on a logic tick asks two questions: **do I shoot**, **do I move**.
Strategy is everything that feeds those questions — section orders, cover
rosters, default ROE, wave scripts. The unit does not run a script.

This chapter is the mover. Rooms and next-hop are
[`FORCE_03_Maps_Regions_and_Sim.md`](FORCE_03_Maps_Regions_and_Sim.md).
Byte layout is
[`FORCE_06_Tiles_Memory_and_Sprites.md`](FORCE_06_Tiles_Memory_and_Sprites.md).
The typed line is
[`FORCE_02_Command_Language_and_UI.md`](FORCE_02_Command_Language_and_UI.md).

### Three names

| Word | Job |
| --- | --- |
| **Section** | Letter. Player types A–H (command-line cap 8). Sixteen rows in RAM: 0–7 player A–H, 8–15 enemy A–H. Section id is side. Owns the last order and a lead unit. |
| **Unit** | One mover in the pool: an infantry stack of 1–N, a vehicle, or an emplacement. |
| **Stack** | The occupancy picture — count on a cell. Infantry units *are* stacks. |

The player commands sections. A single private is addressable only after `S`
peels that stack into its own letter. There is no letter-less “unassigned”
pool; the command line speaks letters. Eight letters is the command-line
cap. `S` into a full roster beeps. Mission scripts name 8–15.

The TMX actors plane is spawn stamps. At load they become unit records. The
plane is not the live pool. Live occupancy is the 32-slot unit SoA.

### What is not a unit

Rooms, portals, cover slots, mines, objectives — they have positions; they
do not step. A nest or packed gun **is** a unit with `kind = emplacement`:
same shoot half, no stepper. Do not invent a base entity for “anything with
x, y, and an id.”

### Section record

Sixteen rows, two banks of A–H. `0–7` player, `8–15` enemy. Section id is
side; there is no extra owner byte. Player still types A–H. Scripts name
the high bank.

- Last order: verb, WHERE cell, force nibble 0–10 (`section_order_force`),
  and a strength snapshot at issue (`section_order_str`)
- Lead unit index (man in charge)
- Last lead cell (fallback when the letter is empty)
- Strength (sum of live `count` for that letter)
- In-contact / breaking flags as needed (`FLAG_BREAKING` on force-break)

On death after recount, if live `section_strength` is at or below the
threshold implied by the nibble versus that snapshot, rewrite verb to
`HALT` and set `FLAG_BREAKING`. Force 10 never breaks. Force 0–3 breaks
on the first death (`now < snap`). Force 4–6 breaks at half (`now <=
snap >> 1`). Force 7–9 breaks at `now <= 1`. A new player order clears
`FLAG_BREAKING`. Do not release cover on break. They stop walking and
keep shooting.

**Dest for `M` is a 3×3 rank around WHERE; dest for `D` is the
claimed hole on the unit.** Five stacks of C `M` to the same
house do not ram the cursor cell: lead takes WHERE, the rest
fill N, S, W, E, then corners, skip walls. `D` dest is
`unit_cover` (cover / scout cell, or `$FF` prone). The
section still holds one issued-cell WHERE. Walk facing is the
last cardinal step (tiles N clockwise: 0,2,4,6 / 8–14). Cover
facing overrides on arrival. A new `A` / `M` /
`D` / `H` / `K` / `R` overwrites last order for everyone
still in that letter. A scout peeled into E is untouched.
Do not copy WHERE onto every unit. Do not push five WHEREs
onto the section. Cover assigns on player `D`/`A` commit
flags, and on death reassign for player `A`/`D`/`H`/`K`.

`H` **writes** last order to hold here (WHERE = lead cell or current room).
It does not clear the field. Joiners arriving after a halt must not stand in
the lane with no job.

Doctrine (`D * 6`) is the last order of a section that never got one.

Empty letters persist for the mission: last order and last lead cell stay, so
`J I A` still has a hole to aim at. A letter that has never been used this
mission is a peel *target*, not a join dest.

### Lead unit

One byte on the section: index of the lead unit, plus last lead cell.

Join pathing does **not** chase the NCO. Joiners pile on him, then the cover
roster bounces them. Join dest is:

1. last order’s room (the WHERE cell’s region), else
2. lead’s current room, else
3. last lead cell

Same room is good enough. Enter that room, then run last order: `D` includes
the new man in the cover roster; `A` / `M` share the same dest; `H` stops in
the room.

The lead is identity: overview pip, succession, fallback rally, flavour.
When the lead dies or is peeled, pick another unit with that section id —
prefer one in the last-order room, else any, else the section is empty and
the last lead cell stands. Peel the lead on purpose: remaining men keep the
order, a new lead is anointed, the peeled unit is now its own letter.

### Unit record (fields, not packing)

Owned by the unit:

| Field | Why |
| --- | --- |
| `x, y` | Occupancy. Id is the pool index. |
| `region` | Current room. Flip on portal cross. |
| `section` | Whose last order you obey. |
| `kind` | Infantry / vehicle / emplacement. Classifies the mover. |
| `glyph` | Facing / variant chip. Sourced from the stamp tile at load. Draw uses this; do not treat the TMX actors plane as live occupancy. |
| `count` + HP | Infantry units in Phase 6 are unstacked privates: `count = 1`, `unit_hp` is a byte, spawn 16. A kill is `hp == 0` → `count = 0`, free the slot, lead succession, recount, cover reassign. Do not multiply damage by count. When stacks become real, either hp is the current man (`count--` then reload hp) or N men = N×16 — not this phase. Vehicles and nests may use a real HP nibble later. |
| `weapon` | Reloads `fire_wait`. Rifle, section MG, nest, … |
| `cover` | Slot index or `$FF`. |
| stepper cache | In-room line toward the current target (see FORCE_03). |
| `move_wait` | Frames until the next step. Countdown, not a stored speed. |
| `fire_wait` | Frames until the next shot. |

Target (portal cell or in-room goal) is a cache. Recompute when the order
changes, the unit enters a room, cover is reassigned, or the stepper gives
up (blocked). Do not store a tile id as state. Occupancy is not in the map
byte.

### Tick

Frame-counted. Present at display rate (50/60). Logic at a fixed cadence —
**15 Hz** is the working lie (every 3–4 frames). SDL and C64 use the same
counts.

Scan the pool. Thirty-two records, every logic tick: decrement waits, act on
zero. No timing wheel. No insert-by-next-tick queue. Off-screen rooms still
tick.

Logic tick is two passes of 32: all due shooters fire
(instant hits), then deaths / relead / recount / cover
reassign, then step. `fire_wait` reloads from weapon class
(`FORCE_FIRE_WAIT_RIFLE`). `H` does not step and does shoot.
`M` does not shoot.

`move_wait` reloads from **terrain class under the cell** (plus hurt / crawl
if you have it). Ballpark at 15 Hz: grass 7 (~2 steps/s), road 5, mud slower.
Until `tiles.txt` has a road class, every passable cell reloads
`move_wait = 7` **logic ticks** at 15 Hz (SDL: every 4 VSync
frames). Do not read terrain class for speed. A new order does
not reset wait. Fastest mover is `move_wait = 1`. Emplacements
do not step.

`fire_wait` reloads from **weapon class** (`FORCE_FIRE_WAIT_RIFLE`).
Independent of move, so a nest fires without walking and a rifle is not
locked to step rate.

| Cadence | Work |
| --- | --- |
| Display | Paint, cursor |
| Logic tick (~15 Hz) | Decrement waits; if zero, shoot and/or step |
| Event | New order, enter room, death, approach bits, cover roster |

On a due tick: if `fire_wait` is 0 and ROE gives a target, shoot; if
`move_wait` is 0 and a dest remains, step. And/or, not xor. Suppression and
prone are modifiers on those countdowns (or a skip flag). Emplacements only
get the shoot half.

Enemy “AI” is the same mover plus default ROE plus the mission script
(approach bits, waves). No per-unit behaviour tree.

### Split and join

No new verbs. The command line already has `S` and `J`. There is no eject
key and no letter-less scout.

**`S` from to [count]** — peel. Cursor names the stack. WHO is the source
letter, WHERE is the dest *letter* (not a cell). FORCE is how many men to
peel; default **1**, not 10. A size-1 stack changes letter. Out of letters,
or dest letter illegal, beep. Do not split a stack that is currently in the
`K` budget / mid-spray.

| Line | Means |
| --- | --- |
| `S A E` | Peel one man from A’s cursor stack into E (E was empty: scout) |
| `S A E` (E occupied) | Peel that one into existing E |
| `S A E 5` | Peel five (the whole cursor stack, if that is the count) |

E is now a section. Every existing verb works: `M E …`, `H E`, `R E`. A’s
next `D` does not move him. That is the scout.

**`J` who dest** — join. After `J`, WHO accepts a **type** or a **letter**.

| Line | Means |
| --- | --- |
| `J I A,C` | New infantry, round-robin into A and C (reinforcements) |
| `J E A` | Living section E joins A |

E’s units take A’s last order: walk to A’s room, then cover / attack / hold.
E goes empty (roster gray). A’s lead stays A’s lead unless A was empty, in
which case E’s lead becomes A’s.

Join dest must have men or a last order. A letter that has never existed
this mission is not a join dest (beep). An empty A that still holds last
order — everyone died, meat incoming — is legal; the campaign already
teaches that.

### Two scouts

They are different jobs. Keep both.

- **Room scout slots** — Defend assigns leftover men to authored holes.
  No command. “Eyes on the road.” See
  [`FORCE_07_Rooms_Cover_and_Farm.md`](FORCE_07_Rooms_Cover_and_Farm.md).
- **Player scout** — `S` then `M` on the new letter. He walks the map.
  Friendly stacks already punch fog; a size-1 unit is enough.

Default WHO stays the letter. The flourish is peel, then order that peel.

### Picture

`D A` — A takes cover. Roster may peel a slot scout to an authored gap.

`S A E` — one man becomes E. A’s next orders ignore him.

`M E 30,5` — E walks the ridge. Fog opens. Same stepper as everyone else.

`J E A` — E is A again. Dest = A’s last WHERE. He walks in; cover roster
runs; he fills a leftover hole.

That is the whole of unit “AI” for v1.

### What not to do

- Per-private click selection as the normal WHO
- An unassigned caste the line cannot name
- Dest copied onto every unit
- Path-to-NCO as the join magnet
- A 256-byte in-room move table (next-hop already spent that page)
- Priority queues for who thinks next
- Behaviour trees on the soldier
