# Section roster on the command strip

| Field | Value |
| --- | --- |
| Status | **active** (Draft) |
| Last worked on | 2026-09-12 |
| Source | `src/sdl/game/game.c` (`force_game_draw`) |
| Intent | [`../doc/FORCE_02_Command_Language_and_UI.md`](../doc/FORCE_02_Command_Language_and_UI.md), [`../doc/FORCE_08_Units_Sections_and_Tick.md`](../doc/FORCE_08_Units_Sections_and_Tick.md) |

Replace the motto on portable strip row 23 with an always-on A–H roster.
The thesis *Type the order. Spend the men.* stays in `doc/`; it does not
need a chrome line.

## As it is

`force_game_draw` paints rows 20–23 as:

| Row | Today (`game.c`) |
| --- | --- |
| 20 | `VERB   WHO   WHERE   FORCE` |
| 21 | `READY` |
| 22 | `CURSOR xx,yy` |
| 23 | `TYPE THE ORDER. SPEND THE MEN.` (light grey) |

Row 24 is host extra and does not move.

## Proposed

Row 23 becomes the section roster, always, not a menu `S`/`J` open.

```
A B C D E F G H
```

| Paint | Means |
| --- | --- |
| Light grey | Empty — legal peel *into* (`S`) |
| White | Has men |
| Yellow (or reverse) | Implied WHO: cursor stack’s letter, or the letter just typed |

Counts stay on the cell overlay. This field is occupancy of **letters**.

Until a section table exists, paint all eight letters light grey (every
name empty). Colour occupancy when `FORCE_08` records land. Do not invent
fake occupancy to preview white.

`S` / `J` do not swap in a different row. While the dest-letter slot is
live, illegal letters beep; grey vs white already says which names are
peel targets vs join dests.

Monochrome later: inverse or a mark under occupied. Out of scope here.

## What not to change in this landing

- Rows 20–22 stay slot legend / READY / cursor until the wizard exists.
- Row 24 stays host extra.
- `agents/game.md` still describes the motto until this paints.

## Done when

`--smoke` and an interactive frame show `A B C D E F G H` on row 23
instead of the motto, eight letters light grey, 40×25 geometry unchanged.
