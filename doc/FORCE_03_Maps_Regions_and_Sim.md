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

Cut each map into about 8 rooms on a one-screen fight and 12–16 on a 2×2 fight. Cap near 32. Sixteen ids fit in a nibble. A room is a named span — a rectangle: x0, y0, w, h — plus portals. Rectangles do not overlap.

Rooms are content: FARM, LANE, BANK, RIDGE. The overview can show those names. Pathfinding never searches the tactical grid.

### Portals

Each shared edge has one or two anchors: a tactical cell (or short span) a unit must step on to change room. Crossing flips the unit’s region id. A bridge is a portal that starts closed. Engineers open it. A demolished culvert writes the next-hop entry back to empty.

### Next-hop table

Baked at map load or shipped in scenario data: next[from][goal] = portal or next room. 16×16 = 256 bytes. Walk: while not in goal room, walk toward next portal. In the last room, greedy to the order cell. Disconnected = fail the order on the status line.

Local tick: sign-step toward the current portal or goal cell; if blocked try the other axis, then a sidestep; else wait. Retreat uses a stored rally room and the same table.

### Fog and intel

Friendly stacks reveal around themselves. Overview shows stale red where enemy was last seen. Contact list is rooms with fire or a new sighting. Sighting list is rooms with a red mark. Both wrap. C and E are cheap indexes, not searches over 4000 cells every frame if you keep dirty flags on rooms.

### Engineers and specials

Engineers are cell jobs, not inventories: lay mines, clear mines, build portal, destroy portal. A section walks to the cell; a timer changes cell and portal state.

Special weapons are section modifiers (+baz, +flm) or a mortar fire-mission WHERE the section does not have to occupy. Keep the type line short.

### Time and length

Scenarios are 10–20 minutes. Clocks, reinforcement waves, and second axes of advance create urgency. Sitting still is a choice only when the doctrine and the clock allow it.

### What not to simulate in v1

- Per-soldier facing and peeking.
- Drag select and waypoint queues.
- Base building.
- Perfect path around every hedge. Rooms and doors are the path.
