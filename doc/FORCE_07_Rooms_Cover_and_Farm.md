# FORCE — Rooms, cover, and Hold the Farm

Working notes. Cover is authored meta, like doors. Stacks do not search the screen at 1 MHz.

---

## Principle

The smart-looking moment is: contact starts, stacks leave the dirt and lock to walls, houses, wrecks.

That only works if hiding spots already exist as a short list. Searching a 40×25 window for “best cover” every tick will look drunk and eat the frame.

**Discoverability is for the editor. Runtime only claims numbered holes and walks.** Same greedy stepper as portals.

Recompute assignment when:

- a section first goes in contact in a room, or
- a stack dies, or
- a cover slot is destroyed, or
- the room’s **approach bits** change (a new wave)

Not when an enemy stack steps one cell.

---

## Three cover grades

Worth having. Two grades flatten; four is fuss.

| Grade | Meaning | Farm examples |
|-------|---------|----------------|
| 3 hard | Inside, roof over you | The three houses |
| 2 good | Stops fire from one side | Yard wall, hay wagon, shot-out tank |
| 1 scrap | Better than the lane | Crater, hedge end, lone tree |

Default fill order: **3, then 2, then 1**. Houses pack first, then the wall, then the hay. Leftovers go prone in the open. That is readable: too many men for the furniture.

Each cover slot stores:

- cell x, y
- grade (1–3)
- **advancing**: N / E / S / W / none  
  (`none` = interior / crater, live for either pole)

Advancing is the force’s **rear**, not look and not an army. `advancing=e`
is the east-side force (pushing west, looking west). Look-facing is
derived at arrival. Same cell both ways is `none`, not two chips.

A room has one axis: E–W **or** N–S. Paint both poles if the yard will
be fought both ways. Live list = this letter’s pole plus neutrals, ≤ 12.
The other pole is not cover. Leftovers prone.

---

## Approach bits (D fallback / waves)

Do not compute a moving pressure vector every tick. Do not flock around the tank.

Cover membership is the **section’s order** snapped to the room axis
(`A`/`D`/`R` + WHERE), not the room mask. `room_approach` is the D
fallback when WHERE does not give an on-axis vector, and the Phase 7
wave script. Load default is on-axis: NS/none → SOUTH, EW → WEST.

```
approaches: SOUTH | EAST | WEST   ; bits flipped by wave script
```

Hold the Farm (N–S room):

- Wave 1: `SOUTH` → front S → live advancing N
- Wave 2: `SOUTH` (harder, same axis)
- Wave 3: flanks are other rooms / other letters, not lighting E+W chips
  in this NS room (mixed axis fails the compile)

The wave script *is* the vector. Update bits when a wave starts or when a later roaming threat **crosses a region line** (FIELD_WEST vs FIELD_SOUTH), not every step.

---

## Scout slots

Room / mission flag, not extra AI.

After hard cover is filled, if a live approach has an empty scout slot, peel **one** stack onto it before packing more grade-2. “Eyes on the road,” only if you can spare the man.

Houses still win: grade 3 first. Scouts are leftover attention.

Script scouts per mission. Patrol the Loop would have four scout slots and almost no grade 3.

This is not the player scout. `S` then `M` on a new letter walks the map and
lifts fog; that unit is out of this roster until `J` brings it back. See
[`FORCE_08_Units_Sections_and_Tick.md`](FORCE_08_Units_Sections_and_Tick.md).

---

## The tank ring — four slots, not an orbit

A wreck is not a circle to flock around. It is two poles on this room’s
axis (plus optional `none`), grade 2:

```
tank at 18,12  (N–S room)
  N  18,11  advancing=n   ; rear north, look south
  S  18,13  advancing=s   ; rear south, look north
```

The E/W faces of the same wreck belong in the adjacent E–W room if the
wreck is a gate. One room cannot mix axes.

When the letter reverses (`A` the other way), assignment walks the other
pole. Men take a few greedy steps. No circling math.

Houses do not need rings. A house is 1–3 interior slots, grade 3,
`advancing=none`.

---

## Assignment algorithm

Once per trigger (this phase: Defend commit; later:
contact start / death / slot gone / the letter’s front changes):
walk the 32-slot pool in index order. Each living stack of
this section takes the **best remaining free slot in the live
list** of the WHERE room: grade 3, then live scout (scout
facing equals this letter’s **front**; at most one stack per
live scout), then grade 2, then grade 1. Wrong-pole chips are
not in the walk. Within a tier, nearer Manhattan, then lower
slot index. Rest: prone (`cover index = $FF`). Skip a slot if
it is the `K` target (no `K` until combat). Who goes where
is not important; this is greedy FCFS, not a scripted pairing.

Live list = advancing pole matching this letter’s rear, plus
`advancing=none`. Rear is the opposite of front. Front comes
from the order (`A`/`D` toward WHERE, `R` backing toward
rally) snapped to the room axis; `D` on the men falls back to
`room_approach`. Scout facing **names the front it watches**:
`scout_south` is live when this letter’s front is south.
Compiler rejects scout `facing=none` and mixed-axis cover.

`D`efend: take cover in the room of WHERE. If the section is
elsewhere, they walk there (portals) then fill holes. No holes
in that room: march to WHERE and prone. Cursor on the men is
defend-here; cursor in another yard is defend-there.  
`K`ill: you may leave cover to spend fire on the named cell; if force breaks, assign from the roster again.

Enemy sections use the same roster and default fill. They do not get `K`.

---

## Memory

Per slot: x, y, grade, advancing → a few bytes.  
Up to 24 painted per room (12+12), 12 live. 128 global.

Per stack: one byte cover-slot index, or `$FF`.

No second map. No flood fill. No A*.

---

## Room record — mission 1, Hold the Farm

Board: Farm. One screen. One section. Three buildings, a yard wall between the houses and a field, a hay wagon, a shot-out tank on the road.

```
room FARM
  bounds          ; houses + yard + wall + near field / road
  approaches      ; script: W1 SOUTH, W2 SOUTH, W3 SOUTH|WEST|EAST
  portals         ; to LANE / ORCHARD / FIELD as needed (may be unused in m1)

  cover[]   ; N–S axis. SDL farm is currently all advancing=none pending restamp.
    house-A interior     g3  advancing none
    house-B interior     g3  advancing none
    house-C interior     g3  advancing none
    wall inner           g2  advancing n   ; rear north, look south
    wall inner           g2  advancing n
    tank N               g2  advancing n
    tank S               g2  advancing s   ; live if the letter reverses
    tree / scrap         g1  advancing none

  scout[]
    SOUTH   wall-gap toward the field
    WEST    west fence
    EAST    east fence
```

### What you should see

- Order: `D a` (or `D a` on the farm cell) at force 6–10.
- Wave 1: houses fill, then advancing-N wall, one scout in the south gap, maybe a man on the north side of the tank.
- Wave 2: same geometry, worse incoming. Force number starts to matter.
- Wave 3: west/east flanks are other rooms (or a second letter with WHERE
  that way), not E+W chips in this N–S yard.

Win: farm still yours when the clock ends. Optional retrieval truck (sprite) at the end; `M` to it.

---

## What not to do on this board

- Continuous pressure vector from enemy centroid
- Circling / orbiting the wreck each tick
- Per-soldier search for “best bush”
- A third zoom that draws walls in 3/4

If a later mission has a roaming gun, flip approach bits when it **enters** FIELD_WEST or FIELD_SOUTH. Same data path as a scripted wave.

---

## Authoring checklist (any room)

- [ ] Bounds and name
- [ ] Portals
- [ ] Cover slots numbered, grade + advancing; one axis per room
- [ ] Scout slots per plausible approach
- [ ] Mission script for which approach bits turn on, and when
- [ ] Finger test: can you assign 5 stacks for a south attack without standing in the lane?
- [ ] Finger test: does a side attack make the roster look wrong in a way the player can read?
