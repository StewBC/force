# Apple IIgs port handoff

Native 65816 ORCA/M port in `src/iigs`, built using Golden Gate `iix`. C64 is
the behavioural lead; do not automatically treat a disagreement with SDL as an
IIgs or C64 bug. The approved phase plan and evidence ledger are in
`design/iigs-port.md`. This is a working port under verification, not a claim
that every phase acceptance gate has passed.

## Build and run

From the repository root:

```sh
cmake -B build -S . -DCMAKE_BUILD_TYPE=Debug
cmake --build build --target force_iigs
python3 tools/iigs/run.py
```

The optional target needs Python 3, `iix`, `cadius`, and a GS/OS template.
`python3 tools/iigs/build.py --help` exposes the template override and
`--no-disk`. The default template is included at
`assets/iigs/disc/templat.2mg`; it is copied, never modified. The build does not
require a separate Time Pilot checkout. Output is fixed at
`build/iigs` because ORCA COPY paths currently depend on that location.

Build products include `FORCE`, `force.2mg`, `force-800k.2mg`, `force-800k.po`,
listings, `link.map`, generated
assembly/assets and `symbols.json`. The copied disk's `System/Start` launches
FORCE directly. `run.py` prefers the prepared local GSSquared app under
`build/iigs/emulator`, then the external source build, then `/Applications`.
Override with `--emulator`. Every launch uses a new private disk copy and returns
a JSON session containing PID, disk, socket, log and private symbols path. Use
that session's symbols with that running binary, especially after rebuilding.

```sh
python3 tools/iigs/probe.py --socket /path/from/session/debug.sock status
python3 tools/iigs/probe.py --socket /path/from/session/debug.sock text m
python3 tools/iigs/probe.py --socket /path/from/session/debug.sock framebuffer /tmp/force.png
```

`probe.py` also provides pause, resume, step, memory, key and quit. It imports the
Python client from the local GSSquared source (`--gssquared-source` override).
`framebuffer` reads actual SHR pixels, scanline controls and palette. It does not
capture emulator chrome. The debugger socket is local; an MCP sidecar is not
required by these tools.

## Source and memory

`main.asm` owns GS/OS lifecycle, dedicated bank-0 direct page, hardware setup,
mission loading, frame scheduling, debug mailbox and native platform wrappers.
`input.asm`, `render.asm`, `title.asm` and `menu.asm` are included platform code.

`tools/iigs/core.py` strictly adapts the current C64 map/game/command/world/move/
combat/draw/deck/tactics assembly at build time, preserving native-mode 8-bit
A/X/Y semantics. Unsupported syntax fails generation. Hardware services and
routing activation are explicit IIgs replacements. Do not edit generated code.
The core is bank-local, DBR=PBR; runtime checks reject a bank-crossing core.
Short direct-page pointers address that data bank; their DP storage is in bank 0.
The manifest's link-time symbols require the runtime mailbox load base and DP;
`runtime.py` performs that relocation. Raw listing offsets are not guest addresses.

`assets.py` uses the existing semantic compilers for all six authored missions,
but creates padded IIgs mission tables and route destinations rather than using
C64 staged-loader addresses. `sprites.py` emits fixed aligned 8×8 compiled stack
routines. The renderer retains the composed-cell path for units, text and effects.
Compiled sprite wrappers preserve the normal stack, flags, DP/DBR and auxiliary
memory state; interrupts are masked while the stack addresses the screen.

New IIgs tooling lives in `tools/iigs`; existing root tools have not been moved.
`build.py` coordinates conversion, strict syntax adaptation, ORCA assembly/linking
and disk creation. `snapshot.py` defines normalized executed-state comparisons.

## Controls and campaign

The title/menu shows current mappings. The menu uses arrows and RETURN, `+` to
reveal, `-` to hide and `*` twice to reset scores. CTRL-Q returns to menu or quits;
CTRL-R restarts. CTRL-J in the menu toggles the visible JOYSTICK option.
It defaults off at startup, persists across missions/restarts, and is not saved.
When off, `input_joystick` returns before any game-port access. Menu CTRL-J is
distinguished from Down using the latched C025 Control bit; repeats are ignored.
Inspect `input.asm` for current gameplay keyboard mapping.

The IIgs uses its own GS/OS `FORCE.STATE`, with `FORCE.NEW` and `FORCE.BAK`
transaction files in the resolved launch directory. It does not write C64/SDL
campaign files. Absolute paths are resolved from GS/OS prefix 0; a raw assembly
entry does not inherit ORCA/C's prefix-8 initialization. Write failure retains
pending state and the menu offers R to retry. Persistence/reset tests must run
against private emulator disk copies, never a user's scores or template media.

## Verification and limits

Evidence lives in ignored `build/iigs/evidence/final-native`. Actual guest checks
cover all six 320×200 mission framebuffers, all 1,024 compiled glyph/paper cases,
and all 15 full 818-byte routing images. Executed C64/IIgs normalized snapshots
match at four movement checkpoints, eight weapon checkpoints, and nine authored
farm director transitions. The latter controls casualty/room predicates; it is
not an autonomous campaign playthrough. The snapshots include active units,
HP/ammunition/cover/orders, sections, director, resources, formations and routes.

Native checks also exercise keyboard title/menu/mission launch, released-arrow
behaviour with Shift held, wizard commit/Escape, restart, bounds/scrolling on all
six maps, spawn backpressure, incremental bridge redraw, and idle input. Campaign
checks exercise real GS/OS save/reload, best score/loss rules, failed-create retry,
actual emulator relaunch persistence, and write-protected 2MG error `$002B`.
Shutdown restores caller P/D/DBR/SP and video registers before QuitGS.

The public acceptance entry points are `test_runtime.py`, `test_flow.py`,
`test_interaction.py`, `test_campaign.py`, `test_cadence.py`, `test_shutdown.py`,
`test_input_idle.py`, and `test_joystick_option.py`. Run `--help` and pass the
private session's `--socket` and
`--symbols`. Shutdown terminates the guest; run it in a disposable session.
`test_assets.py` and `test_probe.py` are host checks. C64 baseline capture uses
`tools/test_c64_tactics.py --standard ntsc --movement-only --state-trace ...`,
without `--movement-only` for weapons, or `--director-state ...` for the shared
farm director. Those C64 tests launch their own isolated emulator/disk folder.

The 40,960-byte CELLLOOK bank expands source bytes for dynamic cells and text;
static terrain uses compiled stack sprites. Measured live cadence at stock
2.8 MHz over 30 updates ranges from 16.2 Hz (ridge) to 20 Hz (base), with farm
17.8 Hz. The deadline target is 20 Hz and overruns drop frames. Full redraws and
busy scenes still need tuning. Real hardware joystick calibration is unverified.
Title graphics exist; title music is absent. Full audiovisual parity and an
exhaustive campaign playthrough are not established.

A preexisting SDL `tools/test_tactics.c:175` Cross order-region assertion conflicts
with the current script. The preexisting C64 offset-bank routing oscillation also
remains; do not silently alter authored missions or lead-platform gameplay.

Mr Sprite is not a build dependency. Its source was inspected at
`/Volumes/EXTERNAL/swessels/Develop/github/external/MrSprite_v1.0a/Src`: a small C
CLI with partial Unix branches, Windows header/io/glob dependencies, an
`unsigned long` DWORD width issue on 64-bit hosts and an `argc=4` assignment typo.
A macOS port appears practical. No external source was copied. The bounded
Python emitter is the current reproducible path; semantic tile IDs are separate
from platform frames for later artwork/animation changes.

## Cursor drift correction — 2026-10-17

The original paddle sampler allowed interrupts between `$C070` and the final
`$C064/$C065` sample. Analog timers keep expiring while an IRQ handler runs, but
the loop counters do not advance. GSSquared's default centered virtual stick
normally measured 94; interrupted samples fell to 63, crossing the left/up
threshold of 64. A live Cross reproduction produced three unsolicited diagonal
inputs in 120 updates. This was missed by the earlier stopped-call idle fixture,
which runs with IRQs masked.

`input_joystick` now saves P, masks IRQs for the bounded sampling loop only, and
restores the caller interrupt state before interpreting the measurements.
`test_input_idle.py` exercises the actual live main loop with IRQs enabled on
private Farm/Cross sessions; do not substitute masked `Runtime.call` input
checks for this regression. Physical joystick calibration remains unverified.

The rebuilt fix passed 180 live updates on Farm and 180 on Cross with zero
unsolicited deltas and an unchanged lower-right cursor. Caller IRQ state is
checked both masked and enabled. Before/after samples are recorded under
`build/iigs/evidence/cursor-drift/`.

## Optional joystick control — 2026-10-17

Real hardware without a connected joystick can report a false up-left input even
with the IRQ timing correction. Joystick input is now explicitly opt-in. Startup
sets `joystick_enabled` to zero; the mission menu displays its state and CTRL-J
toggles it. The setting is outside the mission-cleared BSS, so restarting or
changing a mission preserves the user's choice, while relaunching resets it.

When disabled, `input_joystick` returns before the sampling strobe, paddle reads
or button read. CTRL-J is distinguished from Down (both produce `$0A`) using
C025 Control bit1 captured before acknowledging the keyboard strobe. C025 repeat
bit3 prevents firmware key-repeat from repeatedly toggling the setting.

`test_joystick_option.py` checks actual Ctrl-J/Down events, menu text, retained
state, keyboard arrows, and execution breakpoints around the hardware reader.
`test_input_idle.py` now defaults to joystick Off; pass `--joystick` with a neutral
controller to retain coverage of enabled, IRQ-protected analog sampling.

## Finder icon

`tools/iigs/icons.py` converts the editable grids in `assets/iigs/icons/` into
`build/iigs/icons/FORCE.ICON`, its Cadius `_FileInformation.txt`, and PNG previews.
The disk builder installs the icon in the volume's `Icons` directory with file
type `$CA` and aux `$0000`. Its association matches the `FORCE` application,
file type `$B3` and auxiliary type `$DB03`, as in Time Pilot's icon setup. It has
normal 48×24 and small 24×12 four-bit images with transparency masks. It matches
the application named FORCE, not the auto-start copy named System/Start.

## Hardware transfer images

A normal build produces a nonbootable 800K ProDOS transfer disk in both 2MG and
raw ProDOS-order forms: `force-800k.2mg` / `force-800k.po`. These have identical
1600-block contents: FORCE S16 `$B3/$DB03` and Icons/FORCE.ICON `$CA/$0000`.
No GS/OS system is included; boot an existing GS/OS installation, mount the
image, then copy using native Finder to preserve attributes. All mission/assets
are embedded in the application. `--no-disk` skips all disk packaging.
