# FORCE content guide

This folder is the mission kit. You paint maps in Tiled, stamp cover and
rooms with named chips, list the mission, and (optionally) write a
director script that spawns enemies, issues orders, and trips win or
lose.

The game does **not** load these files at runtime. A build compiles
them. If something is illegal, the build fails with a line you can fix.
That is the intended loop: paint, bind, script, build.

This guide talks in **names** (`cover_hard_w`, `walls`, colour 1), not
sheet slots. Chip ids move. Names do not. Current id → name maps live in
`tiles.txt` and `properties.txt`; look there when you need to know which
cell on the sheet is which name.

---

## What a mission is

A playable mission is three things bound together:

1. A **map** — a Tiled `.tmx` under `maps/`.
2. A **catalog row** in `missions.txt` (name, map, window, optional script).
3. An optional **director script** under `scripts/`.

Player soldiers start where you stamp them on the map. Enemy entry is
owned by the script when the mission has one. Unscripted missions stamp
whatever is on the spawn layer and give enemies no standing order.

Hold the Farm is the shipping example: `maps/normandy.tmx`, script
`scripts/farm.txt`, catalog row `hold_farm`. The spawn layer is `farm`.
Bastogne is `maps/bastogne.tmx`, script `bastogne`, catalog row
`hold_bastogne`.

---

## Folder layout

```text
assets/
  maps/
    tiles.tsx              Tiled tileset (geometry + pointer at the PNG)
    force.tiled-project    Open this in Tiled
    normandy.tmx           Hold the Farm map; stem is the map name
    bastogne.tmx           Second map; stem is the map name
  png/
    tiles.png              The 8×8 sheet the tileset draws (160 tiles)
  tiles.txt                Tile-id ranges → class names (walls, roofs, …)
  properties.txt           Colour-row chips → named presets (cover, portal, …)
  missions.txt             Mission catalog
  scripts/
    farm.txt               One director cue sheet per file; stem is the script name
  aseprite/                Art source. Not compiled. Not required to author a mission.
```

| File | What you do with it |
|------|---------------------|
| `maps/tiles.tsx` | The tileset every map uses. Do not duplicate it per mission. |
| `png/tiles.png` | The picture. Classes and cover names are **not** stored in the PNG. |
| `tiles.txt` | Which ids are scenery, soldiers, colour chips, or knockout. |
| `properties.txt` | Which colour-row chips mean `cover_hard_w`, `portal`, `mine`, … |
| `maps/<stem>.tmx` | The board: four shared layers plus one spawn layer. |
| `missions.txt` | Registers a mission: which map, which window, which script. |
| `scripts/<stem>.txt` | The director. Optional. Bound from the catalog’s fourth field. |

Map stem and script stem do not have to match. Hold the Farm uses map
`normandy` and script `farm`. Bastogne uses `bastogne` for both.

---

## Tileset

Open `maps/force.tiled-project` in [Tiled](https://www.mapeditor.org/).
Maps reference `tiles.tsx`, which points at `../png/tiles.png`.

The sheet is 8×8 cells, 16 columns by 10 rows (160 tiles), orthogonal,
top-down. Tiles 0–127 are playfield art and must be 2 pixels wide.
Tiles 128–159 are editor glyphs (an arrow, a letter, or a red X on a
solid fill). They are painted only on `rooms` and `properties`. They
are exempt from the 2-wide rule and from the C64 ink rules, and they
never enter the charset. `assets/aseprite/tiles.aseprite` is still the
old 64×64 file and was not extended with those two rows.

Do not flip or rotate tiles in Tiled — flip bits fail the compile. Do
not add object layers or image layers. The compiler accepts the four
shared layer names below, plus a spawn layer named with the script
stem, encoded as CSV.

### Classes (`tiles.txt`)

Every tile id belongs to a class. Unlisted ids are `empty`. Range lines
name a span; class lines give the number the compiler uses. You paint by
eye; the class is what the game believes.

| Class | Layer it belongs on | Role |
|-------|---------------------|------|
| `empty` | any, as knockout | No scenery, no room, no property, no spawn. |
| `colors` | `color`, `rooms` | Ground tint, and room-colour paint. |
| `walls` | `tiles` | Solid. Blocks walking. |
| `barriers` | `tiles` | Solid. Blocks walking (fences, wrecks, the farm barrier line). |
| `roofs` | `tiles` | Building tops. Units can occupy the cell; the roof is drawn over them. |
| `goodguys` | spawn layer | Player spawn stamp. |
| `enemies` | spawn layer | Enemy spawn stamp (ignored if the mission has a script). |
| `editor` | `rooms`, `properties` | Pipeline marks for tiles 128–159. Not scenery. |

Scenery variants (wall corners, roof pieces, dirt vs grass colour) are
different pictures of the same class. The class is the behaviour; the
picture is the dress.

If you rearrange the sheet, update `tiles.txt` so the ranges still name
the right pictures. This guide will still be valid because it uses class
names.

---

## Maps

Create a map in the same folder as `tiles.tsx`, attach that tileset, set
tile size 8×8, and add these layers, named in lowercase:

| Layer | Visible in Tiled? | What it is |
|-------|-------------------|------------|
| `color` | often hidden | Ground tint under everything. |
| `tiles` | yes | Scenery: walls, roofs, barriers, open ground. |
| `rooms` | often hidden | Room paint. One colour = one rectangle. |
| `properties` | yes while stamping | Cover holes, portals, scouts, objectives, mines. |
| script stem | often hidden | Spawn stamps. `farm` on `normandy.tmx`, `bastogne` on `bastogne.tmx`. |

Layer **names** matter, not XML order and not Tiled’s stack order. A
missing meta layer (`rooms`, `properties`, the spawn layer) is treated
as empty. A missing `color` or `tiles` layer is treated as a plane of
knockout. An unknown name fails the compile.

Size limits: width ≤ 80, height ≤ 50, width × height ≤ 4000.
`normandy.tmx` is 80×40 (2×2 playfields); Hold the Farm is limited to
the NE 40×20.

### Knockout, absence, and tile 0

Three different “nothing”s. Mixing them up is the usual authoring bug.

| What you paint | On `color` / `tiles` | On `rooms` / `properties` / the spawn layer |
|----------------|----------------------|--------------------------------------|
| Tiled’s empty cell (GID 0) | Knockout fill / knockout scenery | **Absence** — no room, no chip, no spawn |
| The `empty` chip | Same knockout | Knockout — also not a room / chip / spawn |
| A `goodguys` tile (the first soldier on the sheet) | Legal scenery (do not) | Legal **spawn**. This is not empty. |

On meta layers, unpainted and `empty` both mean “nothing here.” The first
player soldier tile is a real stamp. Do not treat “the sheet starts at
zero” as “zero means empty” on the spawn layer.

### `color`

Playfield fill. Each cell takes its background from the colour-layer
chip (the chip’s top-left pixel). Knockout becomes opaque black.

Paint `colors` chips for dirt, grass, road, water tints. This layer is
dress. It does not block, hide, or define rooms.

### `tiles`

Scenery. This is what the player reads as the farm, the wall, the
houses.

- Open ground: knockout / `empty`.
- `walls` and `barriers` block walking. Two bodies cannot share a cell.
- `roofs` are occupied from above. Men sit **on** the house cell; the
  roof is redrawn over them. Do not try to path through a building
  interior.
- Do not put soldiers on this layer. Soldiers go on the spawn layer.
- Do not paint tiles 128–159 here. They are editor-only.

Authoring promise the stepper relies on: any two working cells in a
room are connected by greedy steps plus at most a sidestep, or they are
not really the same room. A U-shaped wall that traps men is two rooms
and a gate — or the pile-up is the picture you wanted.

### `rooms`

Rooms are the pathfinding graph. Units walk **room to room**, then
greedy-step inside the dest room. There is no A\*.

Paint with colour chips. Each distinct colour is one room:

- Colour 1, colour 2, … colour 15. Legacy chips 113–127 use
  colour = id − 112. Editor chips 128–142 use colour = id − 127.
  A map uses one of those schemes. Mixing them fails. Chips 143–159
  are illegal on `rooms`. The same id is a property mark on the
  `properties` layer, not a room colour.
- One colour = **one filled axis-aligned rectangle**. Shared edges
  between different colours are allowed. Shared cells are not.
- Doughnuts, L-shapes, and two blobs of the same colour fail.
- Every property chip and every spawn must sit inside some room.

Leave a cell unpainted (or `empty`) for “not a room.” Do not leave a
cover hole or a soldier outside every rectangle.

Scripts never store Tiled ids. They bind names to these colour numbers:

```text
room houses = colour 1
room lane   = colour 2
```

Integer tokens without an alias are colours, not “first room in the
file.” `room 1 = colour 1` on Farm is documentation: the alias `1` is
colour 1. If you restamp colours, you change the alias lines, not the
engine.

A room is **E–W or N–S**, never both. The axis comes from the cover you
stamp (see Cover). Mixed cover directions in one rectangle fail.

### `properties`

Meta stamps. Nothing here is scenery. The picture of a house is on
`tiles`; the hole a man claims inside that house is a cover chip here.

Paint the **named** chip from `properties.txt`. The colour-row cell that
currently carries `cover_hard_w` may move; the name does not.

| Preset name | Kind | What it marks |
|-------------|------|----------------|
| `cover_good_n` `cover_good_e` `cover_good_s` `cover_good_w` | cover | Grade-2 **advancing** pole. Rear = that cardinal. |
| `cover_soft_n` `cover_soft_e` `cover_soft_s` `cover_soft_w` | cover | Grade-2 **soft** neutral. Axis = that cardinal. |
| `cover_hard_n` `cover_hard_e` `cover_hard_s` `cover_hard_w` | cover | Grade-3 **hard** neutral. Always look that cardinal. |
| `portal` | portal | A door **through a wall tile**. |
| `objective` | objective | An objective cell. |
| `mine` | mine | A mine cell. |
| `scout_north` `scout_east` `scout_south` `scout_west` | scout | Eyes-on slot. Editor chips 143–146. |

Two cover chips on the same cell in one room fail. A chip outside every
room fails. Unknown chips fail. Painting a reserved chip 147–159 fails.
The legacy row 113–127 still names the same cover, portal, objective,
and mine presets, so older maps keep building.

Open fronts (walkable seams between two rooms) are **inferred**. Do not
paint `portal` on an open gap. Paint `portal` only where a wall would
otherwise block — a gate, a door, a closed bridge.

Objectives and mines compile. Engineer jobs that arm or clear them are
not in the current binary; stamp them anyway if the board needs the
marks.

### Spawn layer

The layer is named with the script stem (`farm`, `bastogne`).
`goodguys` become the player roster (section A and on).
`enemies` become the enemy bank — **unless** the mission lists a script,
in which case enemy stamps are skipped and the director owns entry.

Each stamp is one infantry stack, count 1. Place them on walkable cells
inside a room. Do not stamp `walls` / `roofs` / colour chips / editor
tiles here.

Hold the Farm paints seven player men on the `farm` layer in the houses
and leaves the west field empty. Wave 1 walks in from the script.

---

## Cover

Cover is authored meta, like doors. The game never searches the screen
for “a good wall.” It claims numbered holes you painted and walks to
them.

The smart-looking moment — contact starts, stacks leave the dirt and
lock to houses, walls, wrecks — only works if the list already exists.

### Grades

Three grades. Two flatten; four is fuss. Default fill order is **3, then
2, then 1**. Leftovers go prone in the open. That is readable: too many
men for the furniture.

| Grade | Meaning | Typical stamp |
|-------|---------|----------------|
| 3 | Inside, roof over you | House interiors (`cover_hard_*`) |
| 2 | Stops fire from one side | Yard wall, hay, tank face (`cover_good_*` / `cover_soft_*`) |
| 1 | Better than the lane | Crater, hedge end, lone tree (add a preset if you need it) |

Grade is on the preset line in `properties.txt` (`grade=3`), not in the
picture.

### Three roles: advancing, soft, hard

Every cover chip has **exactly one** of `advancing=`, `soft=`, or
`hard=`, plus a cardinal `n` / `e` / `s` / `w`. That is the whole
vocabulary. There is no bare “anyone, no facing.”

| Role | Preset family | Who may occupy | Facing |
|------|---------------|----------------|--------|
| **Advancing** (exclusive pole) | `cover_good_*` | Only the force whose **rear** matches that cardinal | Look the opposite way (incoming). |
| **Soft** (neutral) | `cover_soft_*` | Anyone | Look from motion, snapped to that axis. An E/W chip makes an E–W room. NE, SE, and E all face east. |
| **Hard** (neutral) | `cover_hard_*` | Anyone | Always that cardinal, regardless of motion. Farm houses: `cover_hard_w` — occupants look west. |

**Advancing is the force’s rear**, not the threat. A wave coming from
the west has rear = west and uses `cover_good_w` (look east). The other
pole (`cover_good_e`) is live if they reverse.

**Soft and hard are “anyone,” not an army.** Neutrals sit in **both**
live lists. One occupant. Same cell both ways is one chip, not two.

The word `good` in `cover_good_w` is the old grade name (grade 2). It is
not a fourth role. Role = advancing. Grade = 2.

### Axis and live lists

A room is E–W **or** N–S, taken from any pole / soft / hard direction
you stamped. Mixing northish chips with eastish chips in one rectangle
fails the compile.

When a section takes cover in a room, its **live list** is:

- the advancing pole that matches its rear, **plus**
- every soft and hard (neutral) chip in that room.

The other pole is not cover for them. Live list ≤ 12. Paint cap 24 per
room (both poles + neutrals). Global cap 128.

Fill is greedy: grade 3, then a live scout (if you bound scout chips),
then grade 2, then grade 1. Within a tier, nearer Manhattan, then lower
slot index. Rest: prone.

Reassignment happens when a section first goes in contact in a room, a
stack dies, a slot is destroyed, or the room’s **approach bits** change
(a new wave). Not when an enemy takes one step.

### How to stamp a room

Think of the fight’s axis first, then the furniture.

**E–W yard** (threat along the road, Farm’s four rooms):

- Houses / interiors that should always look west: `cover_hard_w`.
- A wreck or wall with two faces: `cover_good_w` on the west side
  (rear west, look east) and `cover_good_e` on the east side (live if
  the letter reverses).
- Scrap anyone can use, facing from motion: `cover_soft_w` or
  `cover_soft_e` (either one sets the E–W axis).

**N–S yard** (threat from the south):

- Advancing north (rear north, look south): `cover_good_n`.
- The opposite pole: `cover_good_s`.
- Neutrals: `cover_hard_s` / `cover_soft_s`, etc.

A wreck is **not** a circle to flock around. It is two poles on this
room’s axis, plus optional neutrals. The E/W faces of a wreck that sits
on a gate belong in the adjacent E–W room. One room cannot mix axes.

Do not paint 20 holes in a room you will never `D`. Thin cover in a
transit field is correct: leftovers prone, the wave does not hunker
there.

### Approach bits

The director sets which way a wave is coming with `approach`. That mask
is the **D fallback** when the order’s WHERE does not already give an
on-axis vector, and it is how a new wave reshuffles enemy holes.

Load default is on-axis: E–W rooms start WEST, N–S rooms start SOUTH.
The script still writes the bit when a wave starts — the wave script
*is* the vector. Do not compute a moving pressure arrow every tick.

---

## Missions catalog

`missions.txt` is the index. `#` starts a comment. One mission per line:

```text
name  map  x,y,w,h  [script]  [cam=x,y]
```

| Field | Meaning |
|-------|---------|
| `name` | Identifier for the mission (`hold_farm`). |
| `map` | Stem of `maps/<map>.tmx`. |
| `x,y,w,h` | Allowed play rect, in cells. Must sit inside the map. The 40×20 view scrolls inside it and no farther. |
| `script` | Optional. Stem of `scripts/<script>.txt`. |
| `cam=x,y` | Optional. Map cell where the window's top-left opens. Omitted, that cell is `x,y`. A value that would hang the window outside the rect is pulled back inside. |

```text
hold_farm normandy 40,0,40,20 farm "Hold the Farm"
```

That is: mission `hold_farm`, map `normandy`, play rect the NE 40×20 of
the 80×40 map, script `farm`, menu title `Hold the Farm`. The rect is
already one screen, so the camera does not scroll. `cam=40,0` on a
whole-map rect `0,0,80,40` opens on that same farm and can scroll.
NW / SW / SE are grass and are outside a NE-only rect.

A mission rect may be one quadrant, a row, a column, or the whole
board. The script still names rooms on the **map**, not on the view.

A missing script file, an unknown stem, or a script that names a room
colour the map does not have fails the **build**.

Identifiers: letter or underscore, then letters, digits, underscores.

---

## Director scripts

A script is a **company commander**, not a brain. Soldiers already
walk, take cover, shoot, and halt on the force nibble. You spawn a
group, give them the same four-slot order the player types, watch the
board, and issue the next order when a condition trips.

Units do not run the script. There is no per-unit behaviour tree, no
`wave = 2` variable, no `if_sometimes`. Letters **are** the tags.

Authoring is `scripts/<stem>.txt`. Keywords are lowercase and
case-sensitive. `#` to end of line is a comment. Names (rooms, beats,
watches) are identifiers or, for rooms, decimal colour numbers. Names
are at most 15 characters.

### File shape

```text
room <name> = colour <1-15>     # aliases, then the map’s room of that colour
spawn_room <name>               # load default for `in spawn_room`

init:
  <setup>                         # once at load, before any watch

watch <name>: <pred> [and <pred>] -> <action> [once]

beat <name>:
  <action>
  wait <pred> [and <pred>] -> <next_beat>
```

Top of file: room aliases, optional `spawn_room`, optional `init`,
watchers, then beats. Beats run in source order. The first `beat` is
where the mission starts. A file with zero beats fails.

`init` runs once, at load, after the player stamps and before the first
tick. Watches are not scanned yet, so a predicate that is true of an
empty letter (`A.strength <= 1`, `A.strength == 0`) does not see the
board before the nests exist. Setup is `spawn`, `order`, `set
spawn_room`, and `approach`. `wait`, `goto`, `win`, and `lose` belong
on a beat. A spawn in `init` places its whole group before the next
line, so three opening groups do not share one job. `batch` and
`period` do not stagger init. One `init` block, and it comes before
any beat.

`and` joins **exactly two** predicates. A third `and` fails. Need `or`?
Write two watchers.

### Beat structure

The **spine** is one beat at a time. A beat is a short cue: spawn,
order, set approach, then `wait` until the board looks right, then
jump to another beat.

```text
beat patrol:
  spawn 6 A in spawn_room
  order A A room 1 force 10
  approach 1 W
  wait A.strength == 4 -> cover
```

Read that as: put six men on letter A, assault room 1 at force 10,
tell that room the wave is coming from the west, sit until two have
fallen, then go to `cover`. That is the opening beat of
`scripts/farm.txt`.

Rules of the spine:

- Actions in a beat run in order, immediately, then the `wait` parks.
- `wait` always names a **beat**. Never `wait … -> win`. Put `win` /
  `lose` on a beat (or a watcher) of their own.
- `wait` is **level-triggered**. It does not evaluate on the tick it
  is decoded (that tick parks). It fires the first later tick both
  predicates are true.
- Orders are **events**, not levels. Issuing `D` once snapshots force
  and assigns holes. Re-issuing `D` every tick would reset the snapshot
  and they would never break. The spine leaves after `wait` fires; it
  does not hold the order down.
- `goto <beat>` jumps without waiting. Rare; Farm does not need it.

Typical 3-act shape:

1. **Patrol** — spawn, assault, wait until that letter has taken losses, then the next order.
2. **Contact** — staggered spawn, hunker, fall back, run off the map.
   Split “they are all out” (`job idle`) from “they have taken losses”
   (`strength <= n`) into **two beats**. A single `wait B.strength <= 4`
   on the spawn tick would fire with two men and skip the hunker.
3. **Last stand** — spawn, die in place (`D` at force 10), win when
   they are gone **and** a living player body is in the room you care
   about.

Losing the starting houses is not an automatic fail unless you write
that watcher. Farm’s win is “clear room 3 with someone standing in it,”
not “still holding room 1.”

### Watchers

Watchers are an always-scanned table. They stay armed for the whole
mission (or until `once` consumes them). Wipe and overrun belong here,
not on the spine.

```text
watch wipe:    player.strength == 0            -> lose
watch overrun: player.in 4 >= 5                -> set spawn_room 2   once
```

- Scanned every logic tick (one per three display frames) while the mission is still playing. Not during `init`, and not before the first tick.
- Default for non-win/lose actions is **once** (edge-triggered). You
  can write `once` explicitly. Win/lose latch the outcome and freeze
  the board; they do not need `once`, but it is legal.
- Watchers may `win`, `lose`, `set spawn_room`, `approach`, `goto`.
  They may **not** `order` or `spawn`. An order is a beat.
- `job idle` is illegal on a watcher (true at load and between waves).
  Use it on a spine `wait` only.
- Watcher `goto` jumps the spine and clears a parked wait.

Debounce with a count (`player.in 4 >= 5`), not a slower poll.

### Letters

`A`–`H` in a script are the **enemy** bank. Player letters are not
script handles. `player` in a predicate is the whole player bank.

- Fresh letter when two groups must be alive at once.
- Reuse `A` when the previous group is gone.
- `A.strength == 0` means “this letter is dead” (or was never spawned). Put the opening groups in `init` when a watch must not treat that empty start as a loss.

There is no mutable `wave` byte. The beat name *is* the act.

### Orders and force

```text
order <letter> <verb> <where> force <0-10>
```

`force` is required. There is no default (the player’s RETURN defaults
to 10; the cue sheet does not).

| Verb | Meaning | Cover |
|------|---------|--------|
| `A` | Attack / assault. Walk toward WHERE and hunt. | Assigns when a living man first enters the dest room (contact-start). Does **not** steal houses at spawn. |
| `D` | Defend / hunker. Walk to the WHERE room and fill holes. Front is travel toward WHERE. | Assigns **immediately**. |
| `R` | Retreat. Like `D`, but walk **backwards**: front stays the threat, not the dest. | Assigns **immediately**. Farm fallback: `order B R room 3 force 4`. |
| `M` | Move. Transit, no hunt. | Releases cover. Arrival near an `exit-*` WHERE despawns enemy men. |
| `H` | Halt. Stay and fight. | — |

`K` (concentrate) is the human edge. The compiler rejects script `K`.
`radio` is parked.

Force is a nibble, 0–10. When living strength drops to half of the
**issued** n, the section **HALTs** (keeps holes, keeps shooting, stops
walking). Force-break is not retreat (it HALTs). You then issue the next
`D`, `R`, or `M`. Force 10 means they never break — last stand, or a run
off the map you do not want interrupted.

A spawn-job that is still pulsing snapshots **issued n** (live + remaining),
not the empty count, so `order B D … force 5` on eight staggered men
is half of 8, not half of 0. Deaths during the stagger do not HALT
against that snapshot until `job idle`.

WHERE is resolved **at issue time**, not chased every step. If the
player moves, a watcher or a later beat re-issues; the dest is not a
homing missile.

| WHERE | Form | Meaning |
|-------|------|---------|
| Room | `room <name>` | Dest room. `D` fills holes there; `A` assaults it. |
| Cell | `cell x,y` | A specific cell on the map (not the window). |
| Player | `player` | Sticky dest, resolved when the order is issued. |
| Exit | `exit-west` `exit-east` `exit-north` `exit-south` | Mission-edge despawn for enemy `M` near that edge. |

### Spawn jobs

```text
spawn <n> <letter> [in <room>|in spawn_room] [batch <b>] [period <p>]
```

- `n` ≥ 1. Letter `A`–`H`.
- Default room is the live `spawn_room` (top-level, or last `set spawn_room`).
- `batch` and `period` stagger the pulses. Period is **logic ticks**,
  not display frames. First pulse is this tick; later pulses every
  `period`. `batch 2 period 7` with n = 8 is four pulses.
- `spawn` does **not** wait the spine. The next line (`order`) runs
  immediately. Wait `job idle` in a following beat if you need all
  bodies out before you judge casualties.
- One spawn-job at a time. Pool full → skip this pulse, keep remaining,
  retry after `period`. The spine does not stall.
- Same-beat `spawn` then `order M exit-west` will not land a man on
  the dest and vanish him this tick; spawn skips the exit cluster.

`set spawn_room <room>` retargets later `in spawn_room` spawns. Farm
uses a watcher: if the player overruns the west field, the next wave
appears in the inner lane instead.

### Win and lose

`win` and `lose` freeze the board. The clock stops, spawn stops, men
finish their last hurt flash and hold. The cursor still moves; it
cannot unfreeze. Window chrome quits. Esc cancels a typed order.

Farm paints the outcome on the talky line. Global lose is usually
`player.strength == 0` on a watcher, armed the whole session — even if
a later beat was scheduled.

The clock (`clock >= n`, n in logic ticks from load) exists as a
predicate for “hold until…” skins. Farm’s win is event-driven, not
clock-end.

### Command reference

#### Top-level

| Command | Form | Notes |
|---------|------|-------|
| Room alias | `room <name> = colour <1-15>` | Binds a name (or integer) to that map colour. Required documentation even when name and colour coincide. |
| Default spawn | `spawn_room <name>` | Load default. At most one. |
| Watcher | `watch <name>: <pred> [and <pred>] -> <action> [once]` | Always scanned. See Watchers. |
| Beat | `beat <name>:` | Spine label. First beat is the start. Body is the following action lines. |

#### Beat actions

| Command | Form | Notes |
|---------|------|-------|
| `spawn` | `spawn <n> <letter> [in <room>\|in spawn_room] [batch <b>] [period <p>]` | Background job. Does not park the spine. |
| `order` | `order <letter> <verb> <where> force <0-10>` | Verb is `A` `D` `M` `H` `R`. Force required. `K` rejected. |
| `set` | `set spawn_room <room>` | Next `in spawn_room` uses this room. |
| `approach` | `approach <room> <bits>` | Bits: `N` `E` `S` `W`, or OR’d (`W\|E`). |
| `wait` | `wait <pred> [and <pred>] -> <beat>` | Parks. Target is a beat name, never `win`/`lose`. |
| `goto` | `goto <beat>` | Jump now. |
| `win` | `win` | Latch win, freeze. |
| `lose` | `lose` | Latch lose, freeze. |

Watcher actions are the same list **minus** `spawn`, `order`, and
`wait`.

#### Predicates

| Predicate | Meaning |
|-----------|---------|
| `<letter>.strength == <n>` | That enemy letter’s living count equals n. |
| `<letter>.strength <= <n>` | Living count ≤ n. |
| `<letter>.strength >= <n>` | Living count ≥ n. |
| `player.strength == <n>` | Whole player bank equals n. (`<=` / `>=` also.) |
| `player.in <room> >= <n>` | Living player stacks in that room ≥ n. |
| `<letter>.in <room> >= <n>` | Living stacks of that letter in that room ≥ n. |
| `<letter> in <room>` | At least one living man of that letter is in the room. |
| `<letter> at <x>,<y>` | A living man of that letter stands on that cell. |
| `player.in <room> >= enemy.in <room>` | Player count in the room ≥ enemy count in the **same** room. |
| `clock >= <n>` | Logic ticks since load ≥ n. |
| `job idle` | Spawn-job remaining is 0 (including “no job”). Spine `wait` only. |

`<letter>` is `A`–`H`. `player` is the friendly bank.

#### WHERE (for `order`)

| Token | Meaning |
|-------|---------|
| `room <name>` | Named room (alias or colour). |
| `cell <x>,<y>` | Map cell. Must sit on the map. |
| `player` | Player lead, resolved at issue. |
| `exit-west` `exit-east` `exit-north` `exit-south` | Edge for enemy `M` despawn. |

### Caps (fail the compile)

| Thing | Cap |
|-------|-----|
| Ops (spawn/order/wait/…) | 64 |
| Beats | 12 |
| Watchers | 8 |
| Predicates | 32 |
| WHEREs | 16 |
| Spawn templates | 8 |
| Cover painted per room | 24 |
| Cover live per pole+neutrals | 12 |
| Cover global | 128 |
| Rooms | 16 |
| Portals | 24 |
| Scouts per room | 4 |
| Spawns on the spawn layer | 32 |
| Objectives | 8 |
| Mines | 32 |
| Name length | 15 |

Also rejected: `radio`, `if_sometimes`, `wave =`, script `K`,
player-bank letters, `job idle` on a watcher, watcher `order`/`spawn`,
`wait … -> win`, missing `force`, force > 10, n/batch/period = 0,
cell outside the map, mixed-axis cover, non-rect rooms.

### Worked example — Hold the Farm

`scripts/farm.txt` on `maps/normandy.tmx`. The fight is four E–W rooms,
west → east **4 – 3 – 2 – 1**. Colour 1 is the houses (east), colour 4
is the west field. Seven player stamps sit in the houses. No enemy
stamps; the director owns entry. Player grenades are 8 with wait 50.
Enemy grenades are 0 with wait 200.

```text
room 1 = colour 1
room 2 = colour 2
room 3 = colour 3
room 4 = colour 4

spawn_room 4

player_grenades 8
player_grenade_wait 50
enemy_grenades 0
enemy_grenade_wait 200

watch wipe:    player.strength == 0            -> lose
watch overrun: player.in 4 >= 5                -> set spawn_room 2   once

beat patrol:
  spawn 6 A in spawn_room
  order A A room 1 force 10
  approach 1 W
  wait A.strength == 4 -> cover

beat cover:
  order A D room 2 force 10
  wait A.strength == 0 -> contact

beat contact:
  spawn 6 B in spawn_room batch 2 period 7
  order B D room 2 force 5
  wait job idle -> contact_fight

beat contact_fight:
  wait B.strength <= 4 -> contact_back

beat contact_back:
  order B R room 3 force 4
  wait B.strength <= 2 -> contact_run

beat contact_run:
  order B M exit-west force 10
  wait B.strength == 0 -> last

beat last:
  spawn 6 C in spawn_room batch 3 period 14
  order C D room 3 force 10
  wait C.strength == 0 and player.in 3 >= 1 -> held

beat held:
  win
```

What that play does:

| Beat | Picture |
|------|---------|
| `patrol` | Six men walk in from the west field and assault the houses. Approach WEST so room 1’s live pole is the west-rear holes plus house neutrals. The beat ends when two have fallen (`A.strength == 4`). |
| `cover` | The survivors `D` room 2 at force 10 until letter A is gone. |
| `contact` | Six more, two at a time. They `D` room 2 at force 5 (hunker, will HALT at half). Spine waits until the stagger is finished. |
| `contact_fight` | Once they exist as a group of six, wait until four are down. |
| `contact_back` | Fall back, `R` room 3 at force 4 (walk west, still looking east). |
| `contact_run` | `M` off the west edge at force 10 (never break; despawn or die). |
| `last` | Six more, three at a time every 14 ticks, `D` room 3 at force 10 (die in place). Win when they are gone **and** a player stack is in room 3. Sitting in the houses forever is a failed mission. |
| `wipe` | Player bank empty → lose, any time. |
| `overrun` | Five player stacks in the west field → later waves spawn in room 2. |

Counts, force nibbles, and beat names are tunables in this file. The
engine does not know “Hold the Farm.”

### Authoring advice

- Name rooms after the place (`houses`, `lane`, `field`), then alias
  them to colours. Integers work; they are harder to restamp.
- One threat axis per room. Flanks are other rooms / other letters, not
  E+W chips in an N–S yard.
- Stamp cover for the fight you will `D`, not for every bush.
- Split “they have arrived” from “they have broken.” `job idle`, then
  a casualty wait, then the fallback order.
- Force 10 = last stand or a guaranteed run. Force 5 then a later `D`
  is “stop pushing and hug dirt,” then the director walks them back.
- Reuse a letter when the previous group is gone. A second live group
  needs a new letter.
- Keep watchers for session rules (wipe, overrun, clock). Keep the
  spine for the act.

---

## Checking your work

From the repo root:

```bash
cmake --build build -j
./build/src/sdl/force
```

The compiler reruns when maps, scripts, `missions.txt`, `tiles.txt`, or
`properties.txt` change. A bad stamp or a bad cue is a build error with
a file and line, not a runtime surprise.

`--smoke` opens a window, paints one frame, and exits 0. It does not
play the 3-act fight. Interactive run is the check for “does this
mission read.”

### Common failures

| Symptom | Likely cause |
|---------|----------------|
| unknown layer | Layer name is not `color`, `tiles`, `rooms`, `properties`, or the mission script stem. |
| editor-only | Painted a tile 128+ on `color`, `tiles`, or the spawn layer. The message names the layer and the cell. |
| mixed colour chips | One map uses both legacy room chips 113–127 and editor room chips 128–142. |
| illegal on rooms | Painted 143–159 on `rooms`. |
| reserved | Painted an unbound property chip 147–159. |
| not a colour chip | Painted scenery or a cover preset on `rooms`. Use a colour chip. |
| not a filled rect | L-shape, doughnut, or two blobs of the same colour. |
| mixed E-W and N-S cover | A northish chip and an eastish chip in one room. |
| properties … not in any room | Cover / portal / spawn sits on unpainted `rooms`. |
| two chips in room | Two cover stamps on one cell. |
| live (lo+none) > 12 | Too many holes on one pole including neutrals. Drop stamps or split the room. |
| unknown chip | Painted a colour-row tile that `properties.txt` does not name. |
| flip bits | Tiled H/V/D flip. Stamp the facing chip instead. |
| letter is not A-H | Script tried to order a player letter. |
| order requires force | Forgot `force <0-10>`. |
| wait names one beat | Wrote `wait … -> win`. Make a `beat held: win`. |
| job idle is illegal on a watcher | Move that wait onto the spine. |
| watchers may not order | Put the `order` in a beat; `goto` that beat from the watcher if you must. |
| colour N not on this map | Alias points at a colour you never painted, or the catalog bound this script to the wrong map. |

---

## Adding a mission (checklist)

1. Duplicate a map (or File → New in the Tiled project). Save as
   `maps/<stem>.tmx`. Keep the four shared layer names and add a spawn
   layer named with the script stem. Attach `tiles.tsx`.
2. Paint `color` (tints) and `tiles` (scenery) with tiles 0–127. Knock
   out open ground with `empty` / unpainted.
3. Paint `rooms` in filled rectangles, one colour chip per room. Use
   either the legacy row or editor chips 128–142, not both.
4. Stamp cover on `properties` with the **named** chips
   (`cover_hard_w`, `cover_good_e`, …). Editor chips 128–146 are the
   row to use for new paint, including `scout_north` and the other
   three scouts. Stamp `portal` only through walls. Keep one axis per
   room. Stay under 12 live / 24 painted. Leave 147–159 unpainted.
5. Stamp player `goodguys` on the spawn layer inside a room. Leave
   enemies off if you will write a script. Do not stamp tiles 128–159
   there.
6. Add a row to `missions.txt`. Window must sit inside the map.
7. If the mission is a fight, write `scripts/<stem>.txt`: aliases,
   `spawn_room`, wipe watcher, beats. Bind the stem as the fourth
   catalog field.
8. Build. Fix the first compiler error. Run the binary. Play the
   spine once without cheating the force numbers — if they never
   break, you wanted force 10; if they never fall back, you waited
   on the wrong predicate.
