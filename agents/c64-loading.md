# C64 staged loading handoff — 2026-10-11

`assets/c64-layout.json` owns origins, capacities, phases, permitted overlays,
format schemas, and routing homes. `tools/c64_layout.py` generates assembly
constants and validates live overlaps. `tools/c64_package.py` checks actual
assembler segments and generates `build/c64/memory-report.{json,md}`. Treat
these checks as build requirements, not optional diagnostics.

## Loading and ownership

`build/force.prg` is a 16,145-byte bootstrap (previous linked PRG: 48,533).
It copies and displays the title before transferring game chunks. Each
`game00.seq` through `game0b.seq` is read through the bounded device-8 reader,
validated against the generated pinned manifest, consumed, then replaced by
the next chunk. Game entry occurs only after installation succeeds. Music
starts after installation. Return must be released and pressed again;
bitmap display is disabled before menu/BSS reuse and before banked map
payloads reclaim the title bitmap.

The shared `transfer.inc` reader bounds every write, checks EOF/status, and
closes its channel on success or failure. No KERNAL call occurs with ROM
hidden. `bank_enter`/`bank_leave` preserve DDR, processor port and interrupt
flags; RAM vectors and the low-memory NMI trampoline protect RESTORE while
banked. CIA2 interrupt sources are masked by their startup owner.

FMAP v3 has a 26-byte header and 10-byte typed directory entries. Required
schemas are geometry, collection, tiles, paper, routes, routing program,
and banked validator. Files are limited to the 6400-byte transfer buffer.
Header/version/compatibility, whole-file XOR, extent, directory uniqueness,
source overlap and destination allowlists are checked before placement.
Planes stage in released BSS while unread sources remain live. Routing homes
remain fixed; routing bytes survive map and mission resets.

MSET v1 has a six-byte header and ten-byte directory entries. Each mission
is independently raw or LZSS encoded, with stored/expanded/body lengths and
XOR integrity. Only the selected record expands into `$0900–$0B55`: exactly
597 bytes. Objective text belongs to that record; validated relative offsets
relocate into this workspace. The record validator checks counts, lengths,
coordinates, op references, watches, templates and objective termination
before scatter. Scatter clears the 640-byte active home and publishes the
mission identity last. Restart and same-map relaunch use resident data.
Map replacement invalidates the resident identity before transfer. Startup
errors show a load error and require restart; later errors restore banking,
quiesce mission references and support a fresh Return to the menu.

## Extension contract

Add allocations and phase ownership to the layout first. Add a schema and
producer, then a typed dispatch handler with explicit source bounds,
destination capacity and scratch lifetime. Reuse bounded transfer, exact
LZSS decoding, bank entry/exit, and mission preparation rather than adding
another disk path. Keep runtime references within the selected workspace;
new active fields need generated sizes and scatter/reset handling.

Compatibility hashes the canonical layout and resident source/producer ABI
inputs. Rebuild generated map records and game together after those inputs
change. FCHK headers are pinned by the bootstrap manifest. XOR8 and the
16-bit build identity detect ordinary corruption/mismatches; they are not
cryptographic signatures. Collection capacity and transfer capacity are
separate limits: a legal 6650-byte collection can still exceed a complete
map file's 6400-byte budget after other chunks are included.

## Current usage

Fresh assembly: DECK 4259/4267 (8 free), SPARE 6016/6016 (0), CODE
24573/24576 (3), low validator 190/196 (6), banked validator 1123/1536
(413). These tight resident budgets constrain future features. The cassette
buffer hosts low validation code; cassette device 1 is unsupported.

The selected workspace remains 597 bytes and DECK still starts at `$0B55`.
Collection home is `$E600–$FFFA`, 6650 bytes, excluding all six vector bytes.
Normandy stores 628 bytes for five records (581 expanded in total);
Bastogne stores 216 bytes (204 expanded). No mission content was removed;
the user's Cross script edit and existing campaign scores are preserved.

## Verification and measurements

Evidence is under `build/c64/banked-evidence/`. All 22 host tests passed:
packages (9), components (4), routes (6), objectives (3). PAL/NTSC runtime
probes compared installed bytes, title preservation, all missions, objective
relocation, scatter, map replacement and routing. A synthetic 16-mission map
expanded 9552 bytes in aggregate, accepted a 597-byte selected record and
rejected 598 bytes without workspace/deck/vector corruption. Seventeen
malformed-file cases passed guard checks; later failures also returned safely
to menu. RESTORE/NMI bank probes passed in both standards. Isolated writable
campaign tests passed save, read-only refusal and F8 reset. PAL/NTSC play-flow
checks passed first frame, keyboard/stick, 64 physical bridge masks, 16 routing
transitions, F3 without disk, loss, same-map relaunch and win/save refusal.

Measured emulated PAL time, excluding initial bootstrap transfer: folder
startup compressed 9.621 s versus raw 9.086 s; real 1541 D64 compressed
82.929 s versus raw 104.974 s. Compression saves roughly 22 seconds on disk
but costs 0.535 seconds on the fast folder path. NTSC folder startup is
9.269 s. PAL mission preparation is 37–74 ms for current records (Cross
43 ms), world reset approximately 18 ms, menu-to-session approximately
2.27 s including the music fade, and map replacement approximately 1.50 s.
Timing captures precede the final small error-recovery addition; final
play-flow and failure probes cover that addition.

Remaining verification limits: the supplementary probe typing normal BASIC
`LOAD"FORCE",8,1` timed out; staged real-1541 transfers and installed-byte
comparisons passed. Initial disk bootstrap transfer time is consequently
unmeasured. Music interruption during campaign KERNAL I/O was not measured
aurally; music/fade and banked NMI behavior were checked. SDL builds, but its
smoke bridge assertions and completion fixture were subsequently corrected.
The menu self-test subsequently received an isolated catalog and temporary
save fixture; the full SDL smoke gate now passes. Gameplay movement code
is unchanged.
