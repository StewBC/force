# FORCE

*Type the order. Spend the men.*

FORCE is a single-player RTS in an 8-bit frame (Commodore 64 first). There is no mouse. You command named sections with a four-slot typed order line and a cell cursor. Individual soldiers are numbers on cells, not objects to click.

You are an NCO with a radio, not a god with a drag box. Default fire smears across every visible gun. Skill is attention, the force number, and when to override the NCO with a concentrate order.

A finished scenario should take ten to twenty minutes, feel like a decision, and be worth replaying. Character graphics, movement on an 8-pixel grid. Fun as strategy, not as animation.

**Version 0.1.0.** The current binary is an SDL3 prototype of **Hold the Farm**: one screen, one friendly section, west-field enemies walking in. Combat is live. There is not yet a campaign clock, waves, or win/lose.

---

## Build and run

Needs CMake 3.20+, a C11 compiler, SDL3, and Python 3 (stdlib only; used to compile the map).

```bash
cmake -B build -S . -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j
./build/src/sdl/force
```

`--smoke` opens a window, paints one frame, and exits 0. Close the game with the window chrome. Esc cancels a typed order. F11 toggles fullscreen. F3 restarts the current mission.

On Apple Silicon, Homebrew’s SDL3 (`/opt/homebrew`) is picked up automatically.

---

## How to play

The unit of play is a **section**, letters A–H. Farm starts with section **A** (white on the roster). Empty letters are grey. The letter under the cursor, or the one you just typed, is yellow.

Orders use a four-slot wizard. Slot order never changes:

**VERB &nbsp; WHO &nbsp; WHERE &nbsp; FORCE**

One RETURN fills remaining holes with defaults: WHO is the section under the cursor (else the last letter you used), WHERE is the cursor cell, FORCE is 10.

There is no command-mode / cursor-mode toggle. The cursor is always live.

| Hands | Cursor | Talk to the line |
| --- | --- | --- |
| Keyboard | Unshifted WASD and arrows | SHIFT+letter (SHIFT+A is Attack, not left) |
| Stick (after the first real move) | Stick and arrows | Unshifted letters |

Digits, comma, space, RETURN, and DEL are unshifted. DEL pops one slot (or a digit inside the current number). Esc cancels the whole line from any slot. Illegal keys for the current hole are ignored.

WHERE is `X,Y`. Type digits for X, comma or space, then Y. RETURN with no digits uses the cursor.

The strip:

- Row 20 — the four holes (`VERB WHO WHERE FORCE`); the current hole is yellow
- Row 21 — talky line, e.g. `ATTACK A AT 10,20 FORCE 5`
- Row 22 — cursor cell (map coordinates)
- Row 23 — roster `A B C D E F G H`

---

## Commands

**In** is in this binary. **Planned** is on the command card, not bound yet.

### Combat

| Key | Order | Status | What it does |
| --- | --- | --- | --- |
| **A** | Attack | **In** | Walk to cover in the room of WHERE (else a 3×3 around the cell) and hunt. Weapons free. |
| **D** | Defend | **In** | Take cover in the room of WHERE and hold. Weapons free. Leftovers go prone in the open. |
| **M** | Move | **In** | Sprint to a 3×3 rank around WHERE. Silent while walking; fight at dest. If the dest cell is a cover chip, claim it. |
| **H** | Halt | **In** | Stop walking. Stay and fight (weapons free). |
| **K** | Kill / concentrate | **In** | Hold and dump fire on that cell. First 3 of every 4 due rifles take it if a living enemy is there with line of sight; the 4th smears. When the cell is quiet, smear resumes. Does not leave cover. Enemy never gets `K`. |
| **R** | Retreat | **In** | Like Defend: take cover in the room of WHERE. Front is **opposite** of travel (walk backwards, keep facing the threat). Auto “one room toward last rally” is not bound. |

Examples (SHIFT+letter, then digits, RETURN):

| You type | Means |
| --- | --- |
| `D` RETURN | Section under the cursor defends here, force 10 |
| `A C` RETURN | C attacks the cursor cell, force 10 |
| `M A 4,18` RETURN | A sprints to 4,18; silent on the way, fights on arrival |
| `K` RETURN `8` | Current section concentrates on the cursor cell, force 8 |
| `H A` RETURN | A halt |
| `S B` RETURN | Cursor man becomes section B |
| `J B A` RETURN | B joins A and takes A's last order |
| `M .` RETURN | Tagged man sprints to the cursor cell |

### Force

The fourth slot is a nibble, snapshotted when you issue the order, not a running percent of a paper TOE. On death, if live strength is at or below the threshold, the letter **halts** (stops walking, still shoots). A new order clears the break.

| Value | Meaning | Status |
| --- | --- | --- |
| 0 | Break immediately on a loss | **In** (same as 1–3 until a contact bit exists) |
| 1–3 | Probe. Break after first death | **In** |
| 4–6 | Hold until about half gone | **In** |
| 7–9 | Hold until almost the last man | **In** |
| 10 or omitted | Stand until destroyed or recalled | **In** |

On planned `S`, this nibble is peel count (default 1), not force.

### Admin and camera

| Key | Order | Status | What it does |
| --- | --- | --- | --- |
| **S** | Split / peel | **In** | Peel the cursor man into another letter (`S B` = that man becomes B). Count optional. |
| **J** | Join | **In** | Letter join only (`J B A`). Type-join `J I` is not bound. |
| **.** | This stack | **In** | WHO is period: that man stays in his letter. `M .` / `D .` / `H .` / `K .` after tagging him. |
| **F** | Focus | **In** | Snap camera to a cell. FORCE is optional duration, then `B`. |
| **Z** | Zoom | Planned | Overview / detail. Room-blob paint, not a scaled tilemap. |
| **B** | Back | **In** | Previous camera. |
| **C** / **X** | Contact | **In** | Cycle rooms with fire; SPACE snaps and selects. |
| **E** | Enemy mark | **In** | Cycle last-known enemy sightings. |
| **?** / CTRL | Cheat sheet | Planned | Overlay of this card. |
| `D * 6` | Doctrine | Planned | Idle sections defend in place at force 6. |

### Host keys (not orders)

| Key | Status | What it does |
| --- | --- | --- |
| Esc | **In** | Cancel the typed order |
| F3 | **In** | Restart the current mission |
| F11 | **In** | Fullscreen |
| DEL / BACKSPACE | **In** | Pop one wizard slot |
| RETURN | **In** | Commit remaining defaults |

---

## Combat, as it plays

Rifles are instant: a shot this tick hits this tick. No tracers. Default ROE is **smear** — closest enemy in range with line of sight. Houses and walls block shots through them; a man *on* a wall can still fight. Cover cuts damage (a roof lasts longer than dirt). Walking men are harder to hit. `M` is silent **while sprinting**; arrived movers fight. Type `A`, `D`, `H`, or `K` to shoot on the way.

Farm: eight friendlies at the east yard, seven enemies in the west field with a standing attack. `D` the farm, they lock to houses and the wall. Point at a misplaced man, `M .` onto a wall chip. `K` a man who is dropping you. `M` to cross a lane without lighting up on the way.

There is no campaign clock yet, no waves, no win line. When the yard is quiet, that is the fight.

---

## Design notes

Product intent lives in [`doc/`](doc/README.md). The command card you can keep beside the keyboard is [`doc/FORCE_05_Command_Card.md`](doc/FORCE_05_Command_Card.md).
