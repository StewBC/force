# FORCE

## Command language and UI

*Four slots · guided line · cursor · overview*

The command line is a wizard, not a free editor. Tab (or a dedicated key) focuses the line. Each keystroke fills the current slot or backs up. DEL / BACKSPACE / RUN-STOP pops one slot. Illegal keys for the current slot are ignored, not buffered.

### Slot order

*VERB   WHO   WHERE   FORCE*

Talky form while learning, compact form once the hands know it. Example after A, C, 1, comma, 2, 0, comma, 5:

ATTACK C AT 10,20 FORCE 5

Compact status strip: ATK C @10,20 F5

The fourth portable line is the **section roster**, always on: `A B C D E F G H`. It replaces a motto on that row. Occupied letters are white; empty are light grey; implied WHO (cursor stack, or the letter just typed) is yellow. Counts stay on the cell overlay — this field answers which letters exist. Chrome for the SDL prototype: [`../design/section-roster-strip.md`](../design/section-roster-strip.md).

### Defaults on RETURN

| Slot | If RETURN early |
| --- | --- |
| WHO | Section under cursor, else last section used |
| WHERE | Cursor cell |
| FORCE | 10 (stand until dead or recalled). **`S` is 1** (peel one man). |

So in contact: A, C, RETURN means section C attacks the cursor cell at force 10. D, RETURN, RETURN, RETURN means the current section holds here at force 10. Camera verbs skip WHO and FORCE. `S A E` RETURN peels one.

### Verbs

| Key | Meaning | Slots used |
| --- | --- | --- |
| A | Attack / assault that cell | who, where, force |
| D | Defend / hold that cell | who, where, force |
| M | Move (no seek-and-destroy) | who, where, force optional |
| H | Halt / cancel current order | who |
| K | Kill / concentrate fire on that cell | who, where, force |
| J | Join: WHO is a **type** or a **letter**; then dest section(s) | who, dest letter(s) |
| S | Split / peel the cursor stack into another letter | from, to letter, count optional |
| R | Fall back one room toward last rally | who |
| F | Focus camera on cell or room | where, optional duration |
| Z | Zoom overview / detail | none |
| B | Back to previous camera | none |
| X or C | Next contact / firefight, then SPACE snaps detail and selects that section | none |
| E | Next last-known enemy sighting | none |
| CTRL hold or ? | Cheat sheet overlay | none |

Join examples: `J I A,C` — new infantry assign to A and C, alternating. `J E A` — living section E (the scout) joins A and takes A’s last order. After `J`, WHO accepts a type key (`I`, …) or A–H.

Split: cursor names the stack. `S A E` peels **one** man (FORCE defaults to 1, not 10) from A into E. WHERE on `S`/`J` dest is a **letter**, not a cell. E empty → a section of one; every combat verb then works on E. Out of letters, beep. Do not peel a stack that is in the `K` budget.

`S` and `J` do not open a different row. The roster is already there: grey letters are peel *targets*; white letters are join dests (or peel-into-existing). Illegal letters beep.

Camera and cycle verbs never change slot order of combat verbs.

Full peel/join and last-order rules:
[`FORCE_08_Units_Sections_and_Tick.md`](FORCE_08_Units_Sections_and_Tick.md).

### Force

One nibble. Evaluated against a snapshot of strength taken when the order was issued, not a running percent of theoretical TOE.

| Value | Meaning |
| --- | --- |
| 0 | Contact → break immediately |
| 1–3 | Probe. Peel off after first serious fire |
| 4–6 | Hold until roughly half strength or morale break |
| 7–9 | Hold until the position is actually lost |
| 10 or omitted | Stand until destroyed or recalled |

### Guided line behaviour

- After verb A the line asks for section.
- After who it asks for where. Digits build X, comma or space starts Y. RETURN with no digits uses the cursor cell.
- After where it asks for force. RETURN uses 10.
- After `J` the line asks for type *or* section, then dest letter(s).
- After `S` the line asks for from-section, then dest letter, then optional count (default 1).
- Comma is “next number” (or next dest letter on `J I A,C`), not a command.
- RUN-STOP on an empty first slot cancels the line.
- Optional SID tick on accept, buzz on illegal key.

### Cursor and popup (Tab out of the line)

WASD or joystick moves a cell cursor. The stack under the cursor is the implied WHO. A small popup can show context keys (attack, defend, halt, concentrate) but must not become a second language. Prefer the same letters as the line.

### Overview and cycles

Z flips detail and overview. Overview is a heat/ownership paint of rooms and stacks with relative coords coarse enough to type if needed. Joystick pick on overview dumps that cell into WHERE if a command is open, or focuses if not.

C / X cycles rooms with an active contact. E cycles last-known enemy marks. SPACE on a cycle item snaps the detail camera and arms WHO with that section. If the list is empty, beep and stay.

### Smart / doctrine

Smart mode is the last standing doctrine, not a genius. Example: `D * 6` — idle sections defend in place at force 6. Scenario default can be defend 4. When a section has no order and makes contact, doctrine applies. Predictable NCO.

### Micro

Default ROE when attacking a room with several threats: split fire. Nearest threat and anything shooting the section get a share. No scoring function.

Concentrate (K, or A issued on an enemy weapon cell) puts at least three quarters of the section fire budget on that cell. Leftovers only return fire at whoever is dropping them. When the cell is silent, ROE resumes. No waypoint queue in v1. Retarget by issuing K again.

Local overrides (halt, hold this cell, doctrine bump) expire unless re-issued as a standing line. Enemy never gets K.

### Implementation note

A command is a 4-byte object plus a 1-byte parser state. Cheat sheet is a static character overlay, not rebuilt every frame. The A–H roster is eight glyphs painted from the section table, not a menu.
