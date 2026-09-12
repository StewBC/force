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
- facing: N / E / S / W / none  
  (`none` = interior, good from all sides)

Facing is how you get “far side of the wreck” without a live pressure field.

---

## Approach bits (the cheap pressure vector)

Do not compute a moving pressure vector every tick. Do not flock around the tank.

The scenario owns a **bitmask of live attack angles** on the room:

```
approaches: SOUTH | EAST | WEST   ; bits flipped by wave script
```

Hold the Farm:

- Wave 1: `SOUTH`
- Wave 2: `SOUTH` (harder, same axis)
- Wave 3: `SOUTH | WEST | EAST`

A cover slot is preferred if its facing **opposes a live approach**, or facing is `none`.

- Attack from south → north face of wall and north slot of the tank come first.
- Wave 3 lights west → west-facing house wall / west end of yard wall / east slot of the tank (far side from west) come into play.
- If you did not author west-facing slots, men stay in south-cover and die from the flank. That is the lesson.

The wave script *is* the vector. Update bits when a wave starts or when a later roaming threat **crosses a region line** (FIELD_WEST vs FIELD_SOUTH), not every step.

---

## Scout slots

Room / mission flag, not extra AI.

After hard cover is filled, if a live approach has an empty scout slot, peel **one** stack onto it before packing more grade-2. “Eyes on the road,” only if you can spare the man.

Houses still win: grade 3 first. Scouts are leftover attention.

Script scouts per mission. Patrol the Loop would have four scout slots and almost no grade 3.

---

## The tank ring — four slots, not an orbit

A wreck is not a circle to flock around. It is four slots, grade 2, one per compass point:

```
tank at 18,12
  N  18,11  face S
  E  19,12  face W
  S  18,13  face N
  W  17,12  face E
```

If approach = SOUTH, offer the N slot first. Skip the S slot unless everything else is full.

When approach bits change, stacks get a new slot index and take a few greedy steps. It reads as “they shifted around the wreck.” No circling math.

Houses do not need rings. A house is 1–3 interior slots, grade 3, facing none (or one “window” slot facing an approach if you want a designated firing slit).

---

## Assignment algorithm

Once per trigger (contact start / death / slot gone / approach bits changed):

1. Collect living stacks of this section in this room.
2. Fill all free grade-3 slots (nearest stack to slot, Manhattan).
3. Place at most one stack on each **live** scout slot, if a stack remains.
4. Fill grade-2 whose facing opposes a live approach.
5. Fill remaining grade-2.
6. Fill grade-1.
7. Rest: prone in place (`cover index = $FF`, state = exposed).

Skip a slot if it *is* the enemy cell you are concentrating on (`K` target).

`D`efend this room: take cover, hold.  
`K`ill: you may leave cover to spend fire on the named cell; if force breaks, assign from the roster again.

Enemy sections use the same roster and default fill. They do not get `K`.

---

## Memory

Per slot: x, y, grade, facing → a few bytes.  
8–12 slots per room × 16 rooms is well under 1K. Pack if you want.

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

  cover[]
    house-A interior     g3  face none
    house-B interior     g3  face none
    house-C interior     g3  face none
    wall inner           g2  face S     ; packed against field
    wall inner           g2  face S
    wall west end        g2  face W     ; used when W3 lights WEST
    wall east end        g2  face E
    wagon                g2  face E     ; or face S if the wagon sits on the south edge
    tank N               g2  face S
    tank W               g2  face E
    tank E               g2  face W
    tree / scrap         g1  face none

  scout[]
    SOUTH   wall-gap toward the field
    WEST    west fence
    EAST    east fence
```

### What you should see

- Order: `D a` (or `D a` on the farm cell) at force 6–10.
- Wave 1: houses fill, then wall facing south, one scout in the south gap, maybe a man on the north side of the tank.
- Wave 2: same geometry, worse incoming. Force number starts to matter.
- Wave 3: approach bits add west+east. Assignment runs again. Spare men peel to west/east wall ends and side scouts. If you never authored those slots, the yard is flanked on purpose.

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
- [ ] Cover slots numbered, grade + facing
- [ ] Scout slots per plausible approach
- [ ] Mission script for which approach bits turn on, and when
- [ ] Finger test: can you assign 5 stacks for a south attack without standing in the lane?
- [ ] Finger test: does a side attack make the roster look wrong in a way the player can read?
