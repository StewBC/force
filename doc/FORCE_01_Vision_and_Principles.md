# FORCE

## Vision and principles

*Working design · 8-bit RTS · no mouse*

FORCE is a single-player campaign RTS for 8-bit machines (Commodore 64 first, Apple II in the same family of constraints). There is no mouse. The player commands named sections with a four-slot typed order line, a cell cursor, and a coarse overview map. Individual soldiers are numbers on cells, not objects to click.

The product goal is not spectacle. A scenario should take ten to twenty minutes, feel like a decision, and be worth replaying. Character graphics, user-defined tiles, movement on an 8-pixel grid. Fun as strategy, not as animation.

### Thesis

*Type the order. Spend the men.*

The player is an NCO with a radio, not a god with a drag box. Default rules of engagement will smear fire across every visible gun. Skill is attention, force values, and when to override the NCO with a concentrate order.

### Non-negotiables

- The unit of play is the section (letters A–H). A single stack is addressable after `S` peels it into its own letter (the scout flourish), or with `.` WHO (this stack, stay in letter; expires on the next letter-wide order). Default WHO stays the letter. There is no click-the-private as the normal WHO.
- Every order uses the same slot order: verb, who, where, force. Verbs that do not need a slot skip it; they do not rearrange it.
- Micro is target priority and short local overrides. It expires unless committed as a standing order.
- No A\*. Movement is region portals plus a 4-connected zig-zag inside a room.
- Enemy AI uses only default ROE. Focus fire is the human edge.
- One teaching idea per mission. Recycle boards; change the plan and the clock.

### Platform shape

Detail view is one screen of character cells (about 40×20 playfield plus a 4-line command/status strip, or 40×25 if the machine allows). Units move cell to cell, not pixel-perfect. Occupied cells show a unit glyph; a sprite or second character carries stack size and a coarse health/morale tint.

Overview (zoom) compresses a larger tactical map (about 80×50 on standard missions) back to one 40×24 summary: ownership, heat, last-known contacts, friendly stacks. Own units punch holes in fog of war.

Smaller training maps can be a single screen. Standard campaign maps are about four times that area so the player cannot watch every room. Tension comes from two or three live problems at once, not from empty walking.

### What the game is about

Territory. Rooms and named ground (farm, ridge, bank, lane). Production and replacements, when they exist, come from held ground and standing join orders — not from clicking a barracks.

WWII toolkit used sparingly: infantry as the meat, then bazooka, flamethrower, mortar, and engineers (bridge, lay mines, clear mines, demolish). Specials are section modifiers or cell jobs, not extra micro classes.

Tone: invented battles in a WWII frame is easier and more honest than simulating a whole historical front. If history is used, compress one battle into a few boards.

### Success

A player finishes Hold the Farm understanding defend, force, and the contact key. By mission 20 they are flipping overview to detail, concentrating a section on a nest, and still losing a room they neglected. They say it was tense, not that it needed a mouse.
