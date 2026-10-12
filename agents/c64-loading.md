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

The game `transfer.inc` reader bounds every write, checks EOF/status, and
closes its channel on success or failure. It can skip a 16-bit payload count
after the two-byte load address, and a clip flag ends a read at the caller's
limit. `SETLFS` uses logical file 2. The KERNAL `OPEN` rejects file 0, and
the skip math leaves A clear when `read_extra` is under 256. Bootstrap keeps
the older one-byte skip in `transfer_boot.inc` and also leaves A at 2. No
KERNAL call occurs with ROM hidden. `bank_enter`/`bank_leave` preserve DDR,
processor port and interrupt flags; RAM vectors and the low-memory NMI
trampoline protect RESTORE while banked. CIA2 interrupt sources are masked
by their startup owner.

The runtime loads an FCTR container into `$E600` (at most 6650 bytes) and
unpacks one FMSN mission from it. A container longer than 6400 is a second
read that skips the first 6400 payload bytes. FMAP v3 remains a host fixture:
a 26-byte header, 10-byte directory entries, schemas 1–7, and a 6400-byte
file cap. `parse_map` still checks that fixture. Plane LZSS uses the FMSN
decoded length. Routing homes remain fixed.

The selected record expands into `$0900–$0B55`: exactly 597 bytes. Objective
text belongs to that record; validated relative offsets relocate into this
workspace. The record validator checks counts, lengths, coordinates, op
references, watches, templates and objective termination before scatter.
Scatter clears the 640-byte active home and publishes the mission identity
last. Restart unpacks the resident mission and does not read the disk or
clear BSS. A launch reads a container only when that mission's container is
not already resident. A plane's decoded length is width times height from
the geometry chunk. The directory capacity field stays 3200. After the
container XOR, a biome file on the disk replaces 1024 glyphs at `$2000` and
leaves `$2400`. A missing file does not read and the linked charset stays.
Startup errors show a load error and require restart; later errors restore
banking, quiesce mission references and support a fresh Return to the menu.

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
separate limits. A container may be 6650 bytes. The first read clips at
6400 and the tail is a second read.

## Current usage

Fresh assembly (`build/c64/memory-report.md`, layout `$B874`): DECK
3225/3243 (18 free; the bytes end at `$17EE`, and the region ends at
`MENU_INDEX` `$1800`), SPARE 6015/6016 (1 free), CODE 24489/24576 (87 free),
low validator 190/196 (6), banked validator 1123/1536 (413). SPARE still has
one byte free. The cold container walk (XOR, bank load, unpack, and glyph
install) sits in the deck gap. The cassette buffer hosts low validation
code; cassette device 1 is unsupported.

The selected workspace remains 597 bytes and DECK still starts at `$0B55`.
`menu_index` is `$1800–$1C00` (1024 bytes, equate `MENU_INDEX`) and is not
a startup chunk. Collection home is `$E600–$FFFA`, 6650 bytes, excluding
all six vector bytes. Containers: c0 5659/6650 normandy (farm, cross, river,
991 free), c1 4286/6650 normandy (base, ridge, 2364 free), c2 1924/6650
bastogne (bastogne, 4726 free). `build/c64/index.seq` is 345 bytes: a
`$1800` load address plus a 343-byte FIDX. `bank.seq` is 1123 bytes at
`$E000`, loaded once from `menu_open`. Campaign lines are `stem score`. A
legacy `hold_farm` id is translated onto `farm` once; the next save does
not keep the old id.

## Verification and measurements

The measurements below are from earlier banked-mission probes. They were
not re-run for containers. This assembly's host gate is catalog (5),
packages (13), components (4), routes (6), objectives (3), container (7),
biome (3), and `./build/src/sdl/force --smoke`. The control port was down
(`127.0.0.1:16511` refused), so campaign-io, play-flow, loading-failures,
and banked-runtime were not run.



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
