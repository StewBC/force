# FORCE — Tiles, memory, and sprites

Working notes. Complements the design docs (vision, command language, maps, campaign, command card).

## Projection

Straight top-down. No 3/4, no fake depth.

- A farmhouse is a **roof**.
- A yard wall is a wall because it reads as a ring from above.
- A road is dirt. Bushes are a bush glyph. Forest is canopy.
- Water is a flat fill. A bridge is plank across that fill, and that plank is the portal.

One projection for detail and overview. Overview is the same language, coarser: roof becomes a brown cell, canopy a green smear.

### Tile meaning palette

Not a palette of pretty — a palette of meaning:

- Ground: grass, dirt, mud, water
- Cover dress: wall, hedge, crater, sandbag
- Roof / solid building
- Canopy / orchard
- Road / path
- Portal dress: bridge, gate, ford

Stacks sit **on** cells. Do not draw men in doorways. The roof is occupied or it is not; the overlay says how many and how hurt.

---

## Map bytes

A mission map is `width × height` bytes. Each byte is a **tile id**.

The id names a character in the current charset and maps through a small property table:

- glyph
- terrain class (open, road, dirt, water, canopy, roof, wall, hedge, crater, portal-dress)
- flags: walkable, cover, blocks sight, portal-candidate

**The map byte is scenery. Occupancy is not in that byte.**

Do not store “section C, 7 men, hurt” in the tile. That changes every tick. Map is static until an engineer job or explosion patches a cell (road → crater, water+planks → bridge).

You do not need 256 behaviours. You need about a dozen classes. Many ids are visual variants of the same class (three canopy chars, two wall corners, dirt road N/S vs E/W).

### 256 is the charset, not the campaign

One charset = 256 defs. After letters, digits, punctuation, and UI chrome, plenty remain for terrain — and you will not need all of them.

- Shared core set for the whole game: grass, dirt, mud, water, road pieces, hedge, wall, roof, canopy, crater, bridge, mine mark, objective mark.
- Per-board swap of 16–32 slots is enough to make Farm look unlike Town.
- Color RAM does extra work so you need fewer unique glyphs (same hedge char, green vs brown).

---

## Sprites

VIC-II: eight hardware sprites on screen. Treat that as a **design rule** in v1, not something to multiplex away.

Sprites for things that must break the tile grid or read as a machine:

- trucks / halftracks
- tank
- towed gun / cannon
- optional mortar
- cursor (if a flashing cell is not enough)

Infantry stay characters plus a count/health overlay. A stack of twenty men is still one cell glyph.

Mission sprite budgets are content. Example: 2 player trucks, 1 cannon, 1 tank, cursor. The player cannot herd eight trucks onto one cell because the scenario does not give them eight trucks. Off-screen vehicles free a slot. Overview paints vehicles as coarse cells — no sprites required.

### Stack overlay (prefer characters)

1. **Preferred:** second character in a reserved id range in the same cell for 1 / few / many (and a coarse health tint via color RAM).
2. Optional later: one sprite on the selected stack or cursor cell.

v1 should leave all eight sprites to vehicles + cursor.

---

## Memory: one tile map, lists for the rest

Do not keep three parallel 4K maps.

### 1. Terrain — dense array

`tile[width * height]`

Always present. Engineer jobs and explosions patch this array. When a stack stands on grass you do **not** replace the grass. Paint time draws grass + occupier. The grass never left, so you do not need a “remember the tile underneath” copy.

- Training 40×25 → 1000 bytes
- Standard ~80×50 → 4000 bytes

### 2. Occupancy — short list

A section is a handful of units, not 4000 cells. Dest is **not** on the unit;
it lives on the section. Fields and tick rules:
[`FORCE_08_Units_Sections_and_Tick.md`](FORCE_08_Units_Sections_and_Tick.md).

```
unit:
  x, y
  section id
  count
  kind
  glyph
  weapon
  region id
  cover slot index (or $FF)
  stepper (error + signs)
  move_wait
  fire_wait

section[16]:
  last order (verb, where x, y, force)
  lead unit index
  last lead cell
  strength
  flags
```

Twenty units is already a large fight. Linear scan of 20–40 records is fine
at 1 MHz. Scan the whole pool every logic tick — off-screen rooms still move.

Optional: a **bitmap** of occupied cells for the greedy stepper (~80×50 bits ≈ 500 bytes). Set/clear when a unit moves. Not a second tile map.

The TMX `actors` plane is spawn stamps that become these records at load.
Do not keep a live people layer in the map.

### 3. Meta — lists and tiny tables

Doors, rooms, objectives, mines, fire, last-seen. Never a 4K array.

```
region[16]:
  x0, y0, w, h
  name id
  owner / heat / fog flags
  approach bits (mission script)
  pointer to cover roster
  pointer to scout slots

portal[24]:
  cell x, y
  from region, to region
  open / closed

next_hop[16][16]     ; 256 bytes

objective[]
mine[]
contact[]            ; rooms currently hot
last_seen[]          ; room + stale cell
```

Terrain may *look* like a door (bridge glyph). The portal list is the truth.

### What not to store

- A 4K people layer that duplicates the screen
- Door flags in the terrain byte
- Per-cell linked-list pointers

### Budget sketch (80×50)

| Piece | Size |
|--------|------|
| Terrain | 4000 |
| Occupied bitmap (optional) | ~500 |
| 32 unit records × ~8–12 bytes | ~256–384 |
| 16 section records × ~9 bytes | ~144 |
| 16 regions + ~24 portals | ~200 |
| Next-hop | 256 |
| Cover / scout rosters | see room-data note |
| Mines / objectives / contacts | a few hundred |

About **5–6K** for the world, not 12K of parallel maps.

### Draw order (detail window)

1. `tile[cell]` → background char + color
2. Stack in the list on this cell → occupier / overlay
3. Portal / mine / objective in short lists → mark
4. Sprites on top
