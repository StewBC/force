# FORCE — game design

Working design for **FORCE**, a single-player campaign RTS for 8-bit machines
(Commodore 64 first, Apple II in the same family of constraints). There is no
mouse. The player commands named sections with a four-slot typed order line, a
cell cursor, and a coarse overview map. Individual soldiers are numbers on
cells, not objects to click.

These files are the **product intent**. They are not a description of the SDL
prototype as it exists in source. For the binary as it is, start at
[`agents/README.md`](../agents/README.md). Speculative code architecture lives
in [`design/`](../design/); see [`design/README.md`](../design/README.md).

## Thesis

*Type the order. Spend the men.*

The player is an NCO with a radio, not a god with a drag box. Default rules of
engagement smear fire across every visible gun. Skill is attention, force
values, and when to override the NCO with a concentrate order.

A scenario should take ten to twenty minutes, feel like a decision, and be
worth replaying. Character graphics, user-defined tiles, movement on an 8-pixel
grid. Fun as strategy, not as animation.

## Non-negotiables

- The unit of play is the section (letters A–H). A single stack is a letter
  only after `S` peels it (the scout flourish).
- Every order uses the same slot order: **verb, who, where, force**. Unused
  slots are skipped, never rearranged.
- No A\*. Movement is region portals plus a 4-connected zig-zag inside a room.
- Enemy AI uses only default ROE. Focus fire is the human edge.
- One teaching idea per mission. Recycle boards; change the plan and the clock.

## Read in this order

| # | File | What it settles |
|---|------|-----------------|
| 1 | [`FORCE_01_Vision_and_Principles.md`](FORCE_01_Vision_and_Principles.md) | Thesis, platform shape, success criteria |
| 2 | [`FORCE_02_Command_Language_and_UI.md`](FORCE_02_Command_Language_and_UI.md) | Four-slot wizard, verbs, force, cursor, overview, ROE |
| 3 | [`FORCE_05_Command_Card.md`](FORCE_05_Command_Card.md) | Keyboard-side cheat sheet of (2) |
| 4 | [`FORCE_03_Maps_Regions_and_Sim.md`](FORCE_03_Maps_Regions_and_Sim.md) | Cells, rooms, portals, next-hop, in-room step, fog |
| 5 | [`FORCE_08_Units_Sections_and_Tick.md`](FORCE_08_Units_Sections_and_Tick.md) | Section vs unit, last order, lead, move/shoot tick, `S`/`J` |
| 6 | [`FORCE_06_Tiles_Memory_and_Sprites.md`](FORCE_06_Tiles_Memory_and_Sprites.md) | Top-down tiles, map bytes vs occupancy lists, sprite budget |
| 7 | [`FORCE_07_Rooms_Cover_and_Farm.md`](FORCE_07_Rooms_Cover_and_Farm.md) | Cover grades, approach bits, Hold the Farm room record |
| 8 | [`FORCE_04_Campaign_Twenty_Scenarios.md`](FORCE_04_Campaign_Twenty_Scenarios.md) | Twenty missions, three recycled boards, one idea each |

(3) is a card, not a chapter. Read it after (2). (6) and (7) are working notes
that complement (1)–(5); they do not replace them.

## Shape in one screen

Detail view is one screen of character cells: about **40×20** playfield plus a
**4-line** command/status strip (40×25 if the machine allows). The fourth
portable line is the A–H section roster (not the motto). Units move cell
to cell. Occupied cells show a unit glyph; stack size and a coarse
health/morale tint ride a second character or a sprite.

Overview compresses a larger tactical map (about **80×50** on standard
missions) back to one 40×24 summary: ownership, heat, last-known contacts,
friendly stacks. Training maps can be a single screen. Standard campaign maps
are about four times that area so the player cannot watch every room.

## What the files do not cover

- **How the SDL prototype is built or layered.** That is [`agents/`](../agents/).
- **Code designs that have not landed.** That is [`design/`](../design/).
- **How Tiled / PNG become linked C.** That is [`agents/assets.md`](../agents/assets.md).
