# FORCE

## Maps, regions, and simulation

*Cells · rooms · portals · no A\**

### Two scales

| Scale | Size | Role |
| --- | --- | --- |
| Tactical / detail | ~40×20 playfield (training maps may be the whole mission) | Stacks, cover, weapons cells, cursor, combat |
| World | Training 40×25; standard ~80×50 (about 2×2 screens) | Several rooms live at once |
| Overview zoom | Same world painted onto ~40×24 | Ownership, heat, fog holes, contacts |

Do not add a third zoom that draws every private. Optional later. v1: cell stacks plus a count/health overlay.

### What a cell is

- Ground / cover / objective in the background character.
- Occupier class in the foreground (infantry, support, engineer, wreck).
- Overlay: count band (1 / few / many) and state (fresh / hurt / breaking).
- Fat weapon cells (nest, mortar, cannon): one cell, high HP, high suppress. Worth a K order.

Movement is one tactical cell per step. Blocked if impassable or packed. Crowding at a portal is a feature.

### Regions (rooms)

Cut each map into about 8 rooms on a one-screen fight and 12–16 on a 2×2 fight. Cap near 32. Sixteen ids fit in a nibble. A room is a named span — a rectangle: x0, y0, w, h. Rectangles do not overlap. A shared edge is a **front** if the tiles there are walkable.

Rooms are content: FARM, LANE, BANK, RIDGE. The overview can show those names. Pathfinding never searches the tactical grid.

### Portals / fronts

Two abutting rooms with open tiles on the shared edge are a **front**.
Do not paint that edge. Geometry (walls, hedges, barriers) is the
“can’t.” A long seam: each man aims at the nearest open cell, then
steps across. A 2-wide gap: keep-right (west → north, east → south,
y grows down) so opposite traffic pass. Packed: sidestep right, then
re-aim next think. A painted `portal` chip is only a door **through
a wall tile**. A bridge that starts closed is still that chip (or a
barrier tile) until engineers open it.

### Next-hop table

Baked at map load: `next[from][goal]` is the **first neighbour room**
on the walk, `$FF` if disconnected (`from == goal` targets the order
cell). 16×16 = 256 bytes. Rooms are linked if they share a walkable
seam or a painted door. Walk: while not in the dest room, aim at that
front (or door). In the dest room, target is the order cell (or the
cover slot). Do not plan a chain. Disconnected = fail the order on
the status line.

Retreat uses a stored rally room and the same table. Join uses the section’s last-order room, not a chase of the lead unit — see [`FORCE_08_Units_Sections_and_Tick.md`](FORCE_08_Units_Sections_and_Tick.md).

### In-room step

No A\*. One tactical cell per step. When both signs are set, step
**diagonally** if the dest cell is free and not both cardinals are
wall/barrier (occupancy does not block the cut; that is hedge-slip).
Same `move_wait` as a cardinal. Blocked: 4-connected zipper (other
axis, then one sidestep), else wait. Sidesteps stay 4-connected and
do not pop a room or a portal chip.

Do not run x until aligned, then y (an L). Do not spend a second 256-byte table on this — next-hop already used that page. 6502 divide is why a lookup is tempting; an additive **Bresenham error** on the unit needs neither divide nor ROM:

- When the target is set, keep the two signs and an error term from `|dx|`, `|dy|`.
- Each step: both signs → diagonal; else error says major axis → step x, else y.
- Far (beyond a 16-cell window) **and** one sign is 0: long run on the **major** axis, cap, look again. Both signs stay diagonal every think.
- Blocked: try the other axis, then one sidestep, else wait. Zero the run so the next think re-aims. Portal jams and packed cells are content. Do not slide forever along a wall.

Crowding at a portal is a feature.

**Authoring promise:** any two working cells in a room are connected by this stepper plus at most a sidestep, or they are not really the same room. A U-shaped wall that traps greedy is two rooms and a gate — or men piling on the wall is the correct picture (Hold the Farm). Houses are occupied roofs, not interiors you path through.

Who steps, how often, and dest vs target cache: FORCE_08.

### Fog and intel

Friendly stacks reveal around themselves. Overview shows stale red where enemy was last seen. Contact list is rooms with fire or a new sighting. Sighting list is rooms with a red mark. Both wrap. C and E are cheap indexes, not searches over 4000 cells every frame if you keep dirty flags on rooms.

### Engineers and specials

A bridge is a deck chip, not a class and not a portal timer. Any living soldier ordered to BUILD pours one point per logic tick into one adjacent unfinished deck of that bridge. The script header `build deck N` is the cost of every deck cell. Tile 80 is the unbuilt deck; tile 81 replaces it when the cell finishes and is walkable on water. Mines and portal jobs are not in this cut.

Special weapons are section modifiers (+baz, +flm) or a mortar fire-mission WHERE the section does not have to occupy. Keep the type line short.

### Time and length

Scenarios are 10–20 minutes. Clocks, reinforcement waves, and second axes of advance create urgency. Sitting still is a choice only when the doctrine and the clock allow it.

### What not to simulate in v1

- Per-soldier facing and peeking.
- Drag select and waypoint queues.
- Base building.
- Perfect path around every hedge. Rooms and doors are the path.
- A second 256-byte table for in-room steps. Next-hop already spent that page;
  the stepper is an error term on the unit.
