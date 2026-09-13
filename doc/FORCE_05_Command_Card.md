# FORCE

## Command card

*Keep this beside the keyboard*

Slot order never changes: VERB WHO WHERE FORCE

RETURN uses the default for the current hole. DEL pops one hole. Cursor cell fills WHERE if you type no digits. Strip row 4 is always `A B C D E F G H` (white = men, grey = empty, yellow = WHO).

### Combat

| Type | Means |
| --- | --- |
| A c 10,20 5 | Section C attack 10,20, leave if about half gone |
| A c RETURN | C attack cursor cell, force 10 |
| D c 12,08 7 | C hold that cell, hard |
| D RETURN RETURN RETURN | Current section hold here, force 10 |
| M c 04,18 | C move, do not hunt |
| H c | C halt |
| K c RETURN 8 | C concentrate on cursor cell (the nest), force 8 |
| R c | C fall back one room toward rally |

### Admin and camera

| Type | Means |
| --- | --- |
| J i a,c | New infantry join A and C, round-robin |
| J e a | Section E (the scout) joins A, takes A’s last order |
| S a e | Peel one man from A’s cursor stack into E |
| S a e 5 | Peel five |
| `D * 6` | Doctrine: idle sections defend at force 6 |
| F 20,10 3 | Focus there, then snap back |
| F RETURN | Focus cursor |
| Z | Overview / detail |
| B | Previous camera |
| C then SPACE | Next contact, snap and select |
| E | Next enemy mark |
| CTRL hold | Cheat sheet |

### Force

0 run. 1–3 probe. 4–6 half. 7–9 almost last man. 10 stand. On `S`, the nibble is peel count (default 1).

### ROE

Default: split fire. K: spend the section on that cell until it is quiet, then default again. Enemy never concentrates.

### Box line

*Type the order. Spend the men.*
