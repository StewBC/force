# Apple IIgs port

Status: Playable implementation in the working tree; reviewed and validated with the limits below. 2026-10-17.

## Goals and authority

Port the current game to native 65816 assembly, built with ORCA/M through
Golden Gate (`iix`). C64 is the lead platform. SDL provides readable comparison
material, not automatic authority when implementations disagree. Preserve the
existing missions, campaign, command language and 40×25 screen. Run continuously
through the phases after design review; user approval is not a phase gate.

Initial graphics remain the authored C64 artwork. Keep semantic tile IDs separate
from render frames so future single-pixel artwork and additional animation frames
do not require mission changes. New art, new gameplay, enlarged simulation limits,
SID emulation and broad tools reorganization are outside this implementation.

## Baseline and differences

Before changing behaviour, record differences in a ledger with reproduction,
observed C64/SDL results, intended IIgs behaviour, and disposition. C64 is the
starting reference, but a suspected bug is investigated rather than silently
copied or repaired in both ports. Correct stale handoff statements calling SDL
authoritative as relevant documentation is touched.

Baseline already executed by the implementation coordinator: `force_c64` builds.
`python3 tools/test_tactics.py` has a preexisting SDL failure at
`tools/test_tactics.c:175`, the Cross mission order-region assertion. Current
`cross.txt` orders enemy.E to room 5 while the test expects an adjacent approach.
Track this discrepancy; do not edit authored missions or claim it passes.

Parity means executed runtime states compared at matching logical ticks/events
with controlled inputs, initial state and any random source. Parser agreement,
source inspection and screenshots alone do not establish gameplay parity.
Normalize unit slot identity/cell/HP/order/cover, section state, director PC/waits,
resources, active route image and outcome. Use isolated campaign fixtures.

## Implementation boundaries

Put platform sources in `src/iigs`, new tooling in `tools/iigs`, generated outputs
and evidence in `build/iigs`. Keep existing tool entry points and build targets.
Import existing map/catalog/script compiler functions initially; extract shared
Python code only when necessary and keep its current regression checks passing.
Do not consume the C64 staged loader or its hardcoded memory destinations.

Reuse relevant Time Pilot startup, memory-manager, SHR and shutdown patterns.
Use the locally compiled `gssquared/build/GSSquared.app` and existing Python debug
client, with configurable emulator path and socket. MCP installation is optional;
working debugger control is sufficient. Copy the included `assets/iigs/disc/templat.2mg` to build outputs; never mutate
the source template, Time Pilot originals or user save data.

Adapt C64 game, command, world, movement, combat, deck and tactics logic. Replace
VIC/CIA/SID, banking, IRQ, KERNAL loading and storage with IIgs services. A narrow
build-time C64-to-ORCA syntax adapter is permitted for well-defined supported
forms; reject unsupported constructs and validate branch/symbol resolution. This
is generated assembly, not a runtime interpreter. Handwritten platform wrappers
remain explicit. Avoid a speculative whole-program translator before first boot.

### Memory and ABI invariants

Run in native mode. Initial simulation preserves 8-bit A/X/Y arithmetic, index
wrap, table layouts, sentinels and update ordering. Native platform and renderer
routines may use 16-bit registers through explicit wrappers. Public routines
state register widths, DP/DBR, arguments, results and clobbers.

Allocate the dedicated direct page in bank 0. A core `(dp),Y` pointer is a 16-bit
address interpreted against the core DBR data bank; core DBR is established on
entry and restored across platform calls. Allocate the core's addressable data
and mutable state within one bank; do not assume GS/OS provides a suitable bank.
Keep bank-local JSR/RTS code within a single code bank and use JSL/RTL wrappers
between banks. Emit linker size/extent checks and fail on overflow instead of
wrapping addresses. The initial core can retain compact C64-sized simulation
limits. Split immutable data or code through explicit long-address interfaces if
measured link size requires it; no arbitrary cross-bank short pointers.

Route patches use generated IIgs destinations or offsets into the allocated
route tables, never C64 physical addresses. Retain and validate the reserved
second doorway-header byte and the 818-byte route image contract. Banked C64
storage restrictions are not IIgs requirements.

Platform APIs: init/shutdown, mission_load(id), input_poll, render_frame,
campaign_load/save, frame_wait. Simulation has no Toolbox calls. Save/restore D,
DBR, register-width flags and normal stack at the boundaries. Frame pacing uses
IIgs VBL, initially one logic tick per three 60-Hz frames. Compare gameplay by
logic tick; document PAL versus NTSC timing instead of silently rescaling rules.

## Graphics

Use 320×200 SHR, a shared 16-colour palette, 40×20 map and five UI rows. Authored
PNG index transparency is explicit; black is not globally transparent. Ground,
unit, foreground masks, hurt tint, grenade effects and cursor retain C64 rules.
Terrain covers unit pixels except finished bridge tile 81, which is beneath the
unit. Redraw vacated and changed cells; repaint a viewport after scrolling first,
then optimize only if needed. Use an independent host compositor for pixel checks.

No Mr Sprite executable was found locally. Therefore implement a small Python
emitter for fixed, aligned 8×8 stack-drawing routines, following Time Pilot's
proven mechanism. This narrow generator avoids an external unavailable tool and
does not attempt Mr Sprite's general optimizer. Compare emitted results against
reference packed pixels. Keep a stable blitter interface so Mr Sprite can later
replace the generator if worthwhile. Do not generate the Cartesian product of
terrain, unit, paper and effects; opaque base drawing plus composition avoids
unbounded compiled code.

The wrapper saves interrupt state, stack, DP, width flags and shadow configuration,
then restores them before returning. Mask interrupts while the stack addresses
graphics memory; no Toolbox calls in that interval. Keep individual masked draws
bounded rather than masking one entire screen. Verify bank-$01 shadow writes and
SCBs/palette addressing explicitly.

## Phases and acceptance gates

### 0. Contracts and baseline

Check assembler, linker, packaging and emulator prerequisites. Inventory every
mission and existing regression result. Establish isolated C64 runtime fixtures
and normalized snapshots for farm, bridge, support weapons and campaign. Record
any unavailable baseline or preexisting failure honestly. Gates: current C64
build, asset parsing for all missions, documented memory/ABI and delta ledger.

### 1. Build, boot and display

Create the minimal ORCA/M GS/OS executable and reproducible build target. Initialize
SHR and palette, load mission terrain, initial units and font/UI. Generate aligned
compiled drawing routines. Gates: clean and incremental build; stock-speed emulator
launch; debugger register/memory read and screenshot; selected complete cell pixel
comparisons covering palette, transparency and layering; all mission extents render;
clean exit restores platform state. No gameplay-complete claim at this gate.

### 2. Interaction

Implement keyboard and repeat, cursor, command wizard, scroll/focus/previous camera,
intel UI and restart; add joystick after keyboard validation. Gates: injected input
sequences assert cursor/window/wizard/order state; bounds and scroll checks on wide
and tall maps; cursor erase; restart clears mutable state; visual UI confirmation.

### 3. Movement and construction

Adapt spawning, sections, cover, formation, doors/routing, stepper, split/join,
building and routing patches. Control combat/script advancement in fixtures.
Gates: executed C64/IIgs snapshot comparisons for failed sidesteps, all directions,
room crossings, blocked corners, cover, slot reuse, partial/completed bridges and
restart; route images match generated variants through relevant transitions.
Known offset-bank C64 routing oscillation remains a tracked issue, not a passing
crossing test. Preserve existing mission data.

### 4. Gameplay

Adapt rifles, grenades, hurt/death, nests, bazookas, reinforcement jobs, script
watches/waits, objectives and win/loss. Gates: logical-tick comparisons for target
ties, half range, posture, walls, friendly grenade avoidance, reload/ammunition,
death maintenance and director timing. Replay farm scripted flow and both outcomes;
load every mission and exercise representative script predicates.

### 5. Campaign, packaging and polish

Implement title/menu, reveal/reset, survivor persistence, error display and bootable
package. Gates: isolated writable/read-only fixtures; best score retained, loss
never writes, failed write preserves prior file, restart persistence; all missions
accessible and smoke-played; package boots independently. Profile representative
worst cases at 2.8 MHz and optimize measured misses. Existing gameplay is silent;
C64 title SID music needs an explicit IIgs equivalent or an honestly recorded
remaining audiovisual gap. Do not label missing required work complete.

Each gate leaves a runnable artifact and recorded evidence. Update `agents/iigs.md`
and build/run documentation once those behaviours actually land. Keep the design
status and remaining items accurate throughout implementation.


## Execution ledger — 2026-10-17

- Existing C64 package build: passed before implementation.
- Existing catalog parser: 5 tests passed; routing compiler: 6 tests passed.
- Existing SDL tactics: 6 tests run, one runtime fixture error at
  `test_tactics.c:175`. The final Cross defenders are authored to DEFEND room 5,
  while the fixture expects the adjacent approach room. No asset/gameplay edit.
- Executed NTSC C64 movement baseline: existing native harness passed; all seven
  farm soldiers defend their holes, then move into room 1 and settle at
  (14,8), (14,7), (14,9), (13,8), (15,8), (13,7), (15,9).
  Evidence: `build/iigs/evidence/c64-ntsc-movement.json`. This is an executed
  C64 baseline, not yet a C64/IIgs parity result.
- New debugger framebuffer decoder: four host checks passed, covering palette
  selection, fill semantics, PNG integrity and CPU snapshot offsets. Captured
  Time Pilot's 320-mode title directly from newer GSSquared video memory.
- Newer local GSSquared requires CMake installation to package its dylibs/resources.
  A complete bundle is staged under ignored `build/iigs/emulator/`; Applications
  and the emulator source remain unchanged (apart from CMake's install manifest).


## Additional graphics references

User supplied local `external/iigs-game-engine` (GTE) and
`external/iigs-sprite-compiler` on 2026-10-17. Inspected both read-only.
GTE `tools/mksprite.js` is an unfinished, GTE-specific clipping/compiler draft;
its Python `scanline-test.py` experiments with scanline decomposition, not sprite
code generation. The separate C# project targets .NET Framework 4.5.2 and uses
informed search for instruction sequences; its README describes limited short,
unmasked-sequence support. Keep both as references for later graphics work rather
than adding an unverified build dependency. No external source was copied.

## Execution ledger

The phased implementation is present in `src/iigs` and `tools/iigs`; generated
outputs and acceptance evidence remain under `build/iigs`. The lasting handoff is
`agents/iigs.md`. No mission or artwork source was changed.

| Phase | Demonstrated result |
| --- | --- |
| Baseline | C64/SDL builds and SDL smoke pass; catalogue 5 and routing 6 host tests pass. Existing SDL Cross tactics fixture conflict is recorded above. |
| Boot/assets/rendering | ORCA/M S16 and copied GS/OS startup image boot. All six actual framebuffers match; all 1,024 glyph/paper cases and 15 route images match independently decoded/generated data. |
| Interaction | Actual title/menu/mission keyboard flow, command entry, Escape, outcome Return, restart, idle input and all-six map bounds/scroll checks pass. |
| Movement/construction | Four complete normalized C64/IIgs checkpoints match after DEFEND128/MOVE512; native spawn backpressure and bridge redraw fixtures pass. Known C64 offset-bank oscillation remains outside this passing crossing evidence. |
| Gameplay | Eight normalized weapon checkpoints and nine controlled authored farm director transitions match executed C64 states. Win score capture and wipe loss pass. This is representative state parity, not an autonomous playthrough of every mission. |
| Campaign/package | Actual save/reload, best score/loss, create failure/retry, relaunch persistence and write-protected media pass. Caller registers/stack/video restore before QuitGS. |

Static terrain uses a narrow Python compiled-stack emitter. Dynamic cells/text
use a 40,960-byte expansion bank and the hardware scan compares two cells at a
time. Three host asset tests cover isolated generation, all glyph/paper words,
and every byte-expansion table entry; four debugger/PNG checks pass. The native
suite then checks actual emitted code and memory, rather than relying on those
host checks alone.

C64 baseline export adds optional `--state-trace` (movement or weapon states) and
`--director-state` to the existing isolated tactics harness. Fixtures explicitly
match fresh BSS/DATA initialization and preserve the C64's separately installed
initial route image. No mismatch is normalized away. Snapshot comparisons include
unit HP/ammunition/cover/orders, sections, director, resources, formations and the
full active route/doorway image.

### Remaining limits

Measured stock 2.8-MHz live cadence over 30 updates is farm17.8, cross18.9,
river17.1, base20.0, ridge16.2 and bastogne18.2 Hz. The 20-Hz target is not
sustained everywhere; full redraws and busy scenes remain performance work.
This is a demonstrated improvement over the earlier 11–12-Hz candidate, not a
claim that the stock-speed performance gate is fully closed. Real hardware
joystick calibration and exhaustive mission/balance playthrough remain open.
Title music is absent. These limitations prevent claiming complete performance
or audiovisual parity, although the playable implementation is available.

The user-supplied GTE and C# compiler references remain optional references.
Mr Sprite's original source at
`/Volumes/EXTERNAL/swessels/Develop/github/external/MrSprite_v1.0a/Src` is a small
C CLI with partial Unix support. A macOS port appears practical after fixing
Windows header/file enumeration dependencies, DWORD width and an `argc=4` typo.
No source was copied and no dependency installed; the current emitter remains
reproducible without those projects.
