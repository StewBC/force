# Section roster on the command strip

| Field | Value |
| --- | --- |
| Status | **landed** |
| Last worked on | 2026-09-12 |
| Source | `src/sdl/game/game.c` (`force_game_draw`) |
| Intent | [`../doc/FORCE_02_Command_Language_and_UI.md`](../doc/FORCE_02_Command_Language_and_UI.md), [`../doc/FORCE_08_Units_Sections_and_Tick.md`](../doc/FORCE_08_Units_Sections_and_Tick.md) |

Replace the motto on portable strip row 23 with an always-on A–H roster.
The thesis *Type the order. Spend the men.* stays in `doc/`; it does not
need a chrome line.

## Landed

Row 23 paints eight letters, one cell each with a space between:

```
A B C D E F G H
```

All light grey (every name empty). Occupancy colours wait on a section
table. Letters are `putc`'d in a loop so later white/yellow is per glyph,
not a new string.

| Row | Now |
| --- | --- |
| 20 | `VERB   WHO   WHERE   FORCE` |
| 21 | `READY` |
| 22 | `CURSOR xx,yy` |
| 23 | A–H roster, light grey |
| 24 | Host extra (unchanged) |

Handoff: [`../agents/game.md`](../agents/game.md). Follow-on occupancy:
[`../agents/known-gaps.md`](../agents/known-gaps.md).

## Paint (when sections exist)

| Paint | Means |
| --- | --- |
| Light grey | Empty — legal peel *into* (`S`) |
| White | Has men |
| Yellow (or reverse) | Implied WHO: cursor stack’s letter, or the letter just typed |

Counts stay on the cell overlay. This field is occupancy of **letters**.

`S` / `J` do not swap in a different row. While the dest-letter slot is
live, illegal letters beep; grey vs white already says which names are
peel targets vs join dests.

Monochrome later: inverse or a mark under occupied. Out of scope here.
