# Cover advancing (directional live sets)

| Field | Value |
| --- | --- |
| Author | FORCE design session |
| Date | 2026-09-14 |
| Status | **landed** |
| Last worked on | 2026-09-14 |
| Repo path | [`design/cover-advancing.md`](cover-advancing.md) |
| Plan | [`development-plan.md`](development-plan.md) (Phase 6 — first cut) |
| Source | `src/sdl/game/world.h`, `src/sdl/game/world.c`, `src/sdl/generated/force_data.h`, `tools/gen_sdl.py`, `assets/properties.txt` |
| Intent | [`../doc/FORCE_07_Rooms_Cover_and_Farm.md`](../doc/FORCE_07_Rooms_Cover_and_Farm.md) |
| Binary as it is | [`../agents/game.md`](../agents/game.md), [`../agents/known-gaps.md`](../agents/known-gaps.md) |
| Supercedes | Phase 5 `pick_best` membership (`facing_matches` vs `room_approach`, leftover grade-2 fills the wrong face) |

Index status is **landed**. Cover is directional, not army-owned. A
section’s order picks one advancing set in the dest room. The other
face of the furniture is not cover. One properties plane. Runtime
still walks **12**, not 24.

Farm paint is temporarily all `advancing=none` so the mixed-axis map
still compiles. Restamp is authoring, not a C special-case.

This is not the shoot half, not `K`, not waves, not a pressure
vector. Phase 6 combat **depends** on it: a meeting engagement in
one room is stupid under today’s fill.

---

## Overview

Phase 5 claims holes FCFS in the room of WHERE. Membership is “any
chip in that room.” Ranking prefers facing that opposes
`room_approach`, then **remaining grade-2**. Wrong-face walls still
fill. Four men and three chips on both sides of a wall put two men
on the unprotected side.

A rolling fight (leave the farm, push west, later reverse when
flanked from the houses) needs the other face of the same furniture
without faction tags and without a second TMX layer.

This change:

- Reinterprets cover `facing=` as **advancing=** (which way this
  force’s **rear** is).
- Gives each room an axis: E–W **or** N–S.
- Packs each room `[lo | none | hi]` so each live list is ≤ 12 and
  contiguous.
- Selects the live list from the **section’s order**, not from a
  single room mask shared by both sides.
- Derives look-facing on arrival. Neutrals look at the front.

`D` already assigns. `A` / `R` use the same assign when those verbs
land. Enemy uses the same fill. No `K` in this cut.

---

## Current runtime (Phase 5, landed)

Caps (`force_data.h` / `gen_sdl.py`):

| Symbol | Value |
| --- | ---: |
| `FORCE_COVER_MAX` | 128 |
| `FORCE_COVER_PER_ROOM` | 12 |
| `FORCE_SCOUT_PER_ROOM` | 4 |
| `FORCE_ROOM_MAX` | 16 |

World: `room_cover_base/count`, `cover_x/y/grade/facing`,
`room_approach[]` (SOUTH at load). `pick_best(w, i, room)` scans
`room_cover_count` (≤ 12) and uses `facing_matches` against
`room_approach`. Grade 2 that does not match is **tier 1, still
taken**. Grade 3 always taken. Grade 1 always taken.

`force_cover_assign` claims in the **room of WHERE**, not the room
the stack occupies now. Dest is `unit_cover`. Glyph: `face_slot`
uses authored `cover_facing` (look direction).

`properties.txt` cover presets: `grade` + `facing` in
`n/e/s/w/none`. One `properties` plane. One chip per cell.

Farm today: 3 rooms, **27** cover, all grade 2, counts `{11,8,8}`.
Room 0 (east) mixes W and N chips. That mix will **fail** the axis
check until restamp. Do not special-case it in C.

---

## Goals & Non-Goals

### In

- Cover chips tagged **advancing** (rear), not army, not look.
- Room axis E–W or N–S. Mixed directional chips in one room fail
  the compile.
- Live set = this letter’s advancing pole **plus neutrals**, ≤ 12.
  Wrong pole is not a candidate. Leftovers **prone**.
- Neutrals (`advancing=none`) sit in **both** live lists, one SoA
  row, one occupant. Budget: each none uses one of the 12 seats on
  **each** side.
- Paint cap 24 per room (12+12 exclusive). Compiler enforces the
  two list inequalities, not a magic 24 as the interesting number.
- Pack so `pick_best` iterates ≤ 12. Never a 24-loop with skips.
- Order selects the pole: `A` / `D` / `R` rules below. Recompute
  on assign; do not store a front byte on the section.
- Look-facing derived on arrival. Directional chip: look = opposite
  of advancing. Neutral: look = this letter’s front.
- One properties plane. Same cell, both ways = **neutral**, not two
  chips.
- Scout table unchanged (watch-direction). Live scout for this
  letter = scout facing equals this letter’s **front** (not
  `room_approach`).
- `room_approach` stays for D fallback / Phase 7 waves. It is not
  cover membership when the order gives an on-axis front.
- Farm restamp is authoring. Same assign code.
- `agents/game.md`, `known-gaps.md`, FORCE_07 on landing. No
  writer/reviewer loop required to implement from this file.

### Out

| Later / never | Why |
| --- | --- |
| Shoot, ROE, `K`, `fire_wait`, morale | Phase 6 remainder. Skip K-target holes when `K` exists. |
| Fire across a portal | Needed for a 2L/2R standoff; not this cut. |
| Pressure scalar, flocking, centroid | Forbidden. Script (Phase 7) issues `A`/`D`/`R`. |
| Second TMX layer / faction on the chip | Closed five layers. Side is order + room. |
| Two SoA rows on one cell | Occupancy jam. Neutral is the both-ways hole. |
| Cover stages / Advance verb | `A`/`D`/`R` + WHERE *are* the line moving. |
| Split every yard into 2L/2R | Optional authoring (greedy stepper / gate). Not required to hide lists. |
| Bump `FORCE_ROOM_MAX` | Next-hop is still a 16×16 page. |
| Bump `FORCE_COVER_MAX` | 128 holds the farm. Bump when a map runs out. |
| `malloc`, A*, occupancy bitmap, C64 | Unchanged. |

---

## Key Decisions

Locked in the Phase 6 conversation 2026-09-14.

1. **Cover is a direction of push, not an army.** Anyone may claim
   any free hole. Which subset is live is which way **this letter**
   is fighting.

2. **Advancing = rear.** Author `advancing=e` for the east-side
   force (pushing west, looking west). Attack left (WHERE west) →
   live **E**. Retreat toward the east → still **E** (front is still
   west). Attack right → live **W**. Same men, opposite order, the
   other set. Surround: fight west off the farm on E holes; enemy
   appears in the houses; `A` toward the farm lights the W holes
   they had been using.

3. **Wrong face is not leftover grade-2.** It is absent from the
   walk. Four men, one live hole → one covered, three prone.

4. **A room has two poles, not four.** Axis is E–W or N–S. Wave-3
   three-axis flank is two letters / two rooms, not one mask that
   lights every chip.

5. **Neutrals occupy one seat in each live list.** One cell, one
   man. `12 E + 12 W + 1 none` fails. `8 E + 8 W + 4 none` is 12+12
   live, 20 painted.

6. **One properties plane.** `A |wall| B` is two cells. Same cell
   both ways is `advancing=none`. Do not stamp twice.

7. **Selector is the section order, snapped to the dest room’s
   axis.** Not a live pressure field. `room_approach` is the D
   fallback when WHERE does not give an on-axis vector (Hold the
   Farm: `D` on the men, incoming SOUTH).

8. **Split rooms stay an authoring tool** (U-wall, portal as the
   front). They are not the cover model.

9. **No new verb.** Left is WHERE west of you, or the next room
   that way.

10. **`FORCE_COVER_PER_ROOM` becomes 24** (max paint). The 6502
    filter stays “scan 12 cover.” `FORCE_COVER_MAX` 128 until a
    board needs more (`unit_cover` packing still has headroom:
    cover + 32 scouts < `$FF`).

---

## Mapping: advancing ↔ look

| Advancing (paint, rear) | Front (fight) | Look (glyph) | Stand |
| --- | --- | --- | --- |
| E | W | W | east of the wall |
| W | E | E | west of the wall |
| N | S | S | north of the furniture |
| S | N | N | south of the furniture |
| none | (this letter’s front) | front | crater / interior |

```
west                         east
        B |wall| A
   adv=W         adv=E
   look E        look W
```

Attack + WHERE west → live **A**. Attack + WHERE east → live **B**.

---

## Worked example (the stupid fill)

Attack from the west, four men, `D` or `A` into this room:

```
   c1 |wall|          advancing=W
      |wall| c2       advancing=E
   c3 |wall|          advancing=W
```

| | Today (Phase 5) | This change |
| --- | --- | --- |
| Man 1 | c2 (opposes) | **c2** |
| Man 2 | c1 (leftover g2) | prone |
| Man 3 | c3 (leftover g2) | prone |
| Man 4 | prone | prone |

Reverse the order (front east): c1 and c3 live, c2 ignored.

---

## Compiler (`tools/gen_sdl.py`)

### Presets

Cover keys: `grade`, **`advancing`**. Values `n/e/s/w/none`.
**Reject `facing=` on cover** (one language). Scout still
`facing=` (watch).

`assets/properties.txt`: same tile ids, same names
(`cover_good_w`, …). Rewrite the preset body, e.g.

```text
cover_good_w=cover grade=2 advancing=w
cover_good_none=cover grade=2 advancing=none
```

That **inverts meaning** of today’s chips: old `facing=w` was look
west (= advancing **E**). Farm TMX must be restamped (or chips
swapped) in the same change. Do not invert in C to paper over it.

### Per-room pack

After grouping chips by containing rect, **sort** that room’s
cover into:

```text
[ lo exclusives | none | hi exclusives ]
```

| Axis | lo | hi |
| --- | --- | --- |
| E–W | `advancing=e` | `advancing=w` |
| N–S | `advancing=n` | `advancing=s` |

Infer axis: if any E/W exclusive and no N/S exclusive → E–W. If any
N/S and no E/W → N–S. If both → **error** (mixed axis). If only
none (or empty) → axis none; the “both lists” slice is the none
block.

Reject:

```text
lo + none > 12
hi + none > 12
```

(`FORCE_COVER_PER_ROOM` 24 is then implied; still `#define` it and
reject `lo+none+hi > 24` as a belt.) Same-cell two cover chips are
already impossible on one plane. Two cover rows with the same
`(x,y)` in one room (should not happen) → error.

Scout cap 4 unchanged. Off-axis scout in a 2-axis room is allowed
(a south scout in an E–W lane is just never live for these orders).

### Emitted columns (ROM `force_map`)

Keep `room_cover_base` / `room_cover_count` (count = lo+none+hi).
**Add:**

```c
const uint8_t *room_axis;         /* 0 none, 1 EW, 2 NS */
const uint8_t *room_cover_lo;     /* exclusive lo count */
const uint8_t *room_cover_none;   /* neutral count */
const uint8_t *room_cover_hi;     /* exclusive hi count */
```

`cover_facing[]` **stores advancing** (`FORCE_FACE_*` / `NONE`).
Do not emit a second look column. Rename in comments; a symbol
rename to `cover_advancing` is optional sugar (touch generated +
world + compiler together if you do it).

`#define FORCE_COVER_PER_ROOM 24`

```c
#define FORCE_AXIS_NONE  0u
#define FORCE_AXIS_EW    1u
#define FORCE_AXIS_NS    2u
```

---

## Runtime (`world.c` / `world.h`)

### BSS

Append after `room_approach` (new fields at the end):

```c
uint8_t room_axis[FORCE_ROOM_MAX];
uint8_t room_cover_lo[FORCE_ROOM_MAX];
uint8_t room_cover_none[FORCE_ROOM_MAX];
uint8_t room_cover_hi[FORCE_ROOM_MAX];
```

Load: `copy_column` from the map, tails 0. Unused rooms axis 0.

`room_approach` at load: **on-axis default**, not blindly SOUTH.

| `room_axis` | default `room_approach` |
| --- | --- |
| NS | `FORCE_APPROACH_S` |
| EW | `FORCE_APPROACH_W` |
| none | `FORCE_APPROACH_S` (neutrals match any live) |

Phase 7 still overwrites bits per wave. SOUTH on an EW room is
off-axis and must not leak the wrong pole into `D`.

### Front from the order

Recompute in `force_cover_assign`. Dest room = region of WHERE
(already). Axis = `room_axis[dest]`.

Cardinal from a vector, snapped to axis: take the component on the
axis (`dx` for EW, `dy` for NS). Sign picks the pole. Perpendicular
major component → no snap; treat as “no vector.”

**Front** = way this letter is fighting (look-at-the-enemy).
**Live advancing** = opposite of front (the rear). Axis none: live
slice is the none block; front still used for glyphs.

| Verb | Front |
| --- | --- |
| `A` | Toward WHERE. If lead’s room ≠ dest, center-to-center of lead room → dest (or next-hop portal’s 4-connected cross). If already in dest, lead → WHERE. No on-axis vector → `approach_front`. |
| `D` | Same as `A` when WHERE gives an on-axis vector (cursor on the far side of the yard, or another room). Else `approach_front`. Hold the Farm `D` on the men: SOUTH → front S → live advancing N. |
| `R` | Travel = toward rally via next-hop. **Front = opposite of travel** (backing up). Live advancing = travel direction (the rear). Until `R` exists, do not call this. |
| `M` / `H` / `NONE` | No assign (`M` still **releases**). |

`approach_front(axis, mask)`: the on-axis bit in the mask. NS +
`SOUTH` → S. NS + `SOUTH|WEST|EAST` → S (off-axis bits ignored for
this room). Both poles on the axis → first of lo then hi (N then S,
E then W). Mask 0 → no front, live list empty except we still allow
neutrals if axis is none.

Until `A` parses, only the `D` row runs. Write `section_front` as a
file-static helper used by assign so `A` is a verb enum + one
call site later, not a rewrite.

### Live slice (`pick_best`)

```text
base = room_cover_base[room]
lo   = room_cover_lo[room]
none = room_cover_none[room]
hi   = room_cover_hi[room]

live advancing E or N (rear = lo pole):
    start = base
    n     = lo + none

live advancing W or S (rear = hi pole):
    start = base + lo
    n     = none + hi

axis none (or no front):
    start = base + lo     /* lo is 0 */
    n     = none
```

`n` is ≤ 12 by compile. Loop `j in 0..n-1`, index `start+j`.
**Do not** call `facing_matches`. Tiers inside the live list:

| Tier | Slot |
| ---: | --- |
| 4 | grade 3 |
| 3 | live scout (front = scout facing; at most one per scout) |
| 2 | grade 2 |
| 0 | grade 1 |
| — | prone (`$FF`) |

No “remaining grade-2 other face.” Scouts: walk this room’s scout
slice (≤ 4), keep those with `scout_facing == front`. Dead scouts
are not candidates. Scout encoding unchanged (`FORCE_COVER_MAX+s`).

`cover_taken` unchanged (encoded index). Neutrals have one index;
first letter to claim the crater owns it.

`pick_best(w, i, room, front)` — pass front from assign. Grade 0 /
junk still skipped.

### Glyphs

On arrival (`unit_think` already calls `face_slot` with
`cover_facing`):

```c
/* cover_facing RAM = advancing. */
look = (adv == FORCE_FACE_NONE) ? front : opposite(adv);
face_slot(w, i, look);
```

Cache `front` on the unit? No. Recompute from the section order
(same helper). Neutral look follows a later re-assign if the
letter reverses.

Scout arrival: still `scout_facing` (watch = look).

### `force_cover_assign`

Unchanged outer shape: release letter, dest room of WHERE, FCFS
index order, emplacements skip, write `unit_cover` immediately.
Compute `front` once per assign, pass into `pick_best`. Empty live
list → `$FF`, march to WHERE and prone (already).

---

## Memory

| Add | Bytes |
| --- | ---: |
| `room_axis/lo/none/hi` × 16 | 64 |
| ROM same columns | 64 |
| Cover SoA | still ≤ 128 rows; rooms may hold 24 |

No taken-bit array. No second plane. Next-hop still 256.

---

## Farm

Must compile under the axis rule. East room today mixes W and N →
fail. Restamp in the same PR:

- Hold-the-farm yard is **N–S** (incoming field = south). Houses
  `advancing=none` (grade 3 when you paint them). South-face wall
  `advancing=n` (rear north, look south).
- Lane / west, if they keep cover, pick **E–W** and paint both
  poles only if a later mission fights there. Mid/west with zero
  live holes on `D` is still hit-the-dirt.

`--smoke`: verb NONE, stamps unmoved. Interactive: `D` in the east
room fills **south-facing** (advancing N) holes only; a man does
not sit west of a wall and call it cover against a south wave.

---

## Phase 6 remainder (not this file)

Shoot half, smear ROE, `K`, force nibble, morale. Fire **same room
or portal-adjacent** or a 2L/2R split never shoots. Enemy same
cover fill, no `K`. Pressure is a script input (alive vs theirs →
issue `A`/`D`/`R`), not a mover field.

---

## What not to do

- Scan 24 and `continue` the other pole.
- Duplicate a neutral into two SoA rows.
- `cover_side=player`.
- A sixth TMX layer.
- Fill opposite-face grade-2 as “better than dirt.”
- A live centroid / pressure nibble that slides men along a wall.
- Invert advancing↔look in `world.c` so the current farm TMX
  “just works.”

---

## Landing checklist

- [x] `FORCE_COVER_PER_ROOM` 24; compiler list inequalities; pack
      `[lo|none|hi]`; emit axis + three counts.
- [x] `properties.txt` `advancing=`; reject cover `facing=`.
- [x] World copy + `pick_best` slice + `section_front`.
- [x] `face_slot` via derived look.
- [x] Scout live = this letter’s front.
- [x] Load `room_approach` on-axis.
- [ ] Farm restamp (authoring). SDL farm is all `advancing=none`
      so mixed-axis paint still compiles.
- [x] Fold into `agents/game.md`, `known-gaps.md`, FORCE_07.
      This index → landed.
