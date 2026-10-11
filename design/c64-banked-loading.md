# C64 staged loading, compressed chunks, and banked mission storage

Author: Codex, recording the user's accepted implementation scope.
Date: 2026-10-11.
Status: Accepted implementation brief; ready for an implementing agent.

## Assignment and scope

Implement this design in FORCE's C64 build. This document authorizes the
bootstrap/game split, compressed loading, RAM beneath KERNAL, and the loader
and build changes needed to complete the flow below. Do not wait for another
architecture approval. Resolve routine implementation choices using the
constraints and evidence here; report a genuine conflict with requirements.
SDL gameplay is the behavior reference and should remain unchanged.

Start with `agents/README.md`, then `agents/c64-port.md`,
`agents/c64-music.md`, `agents/testing.md`, and the source named below.
Source is authoritative for current behavior; this document defines the
requested replacement. Keep speculative design here until it lands.

The result must support further load/scatter operations as features grow.
A maintained memory map and checked placement contracts are core deliverables,
not optional documentation. Do not solve the immediate overflow by deleting
mission content, squeezing live code, or merely shifting the deck boundary.

## Required user-visible flow

1. Load a small bootstrap PRG containing the title bitmap and the minimum
   code/assets necessary to show it. Display the bitmap as soon as that PRG
   starts, before loading the main game. The entire game must no longer be
   part of the initial PRG. Brief setup/copy time is acceptable.
2. With the bitmap visible, load compressed game code and shared assets from
   device 8 and expand/install everything whose destination is available.
   Load the campaign catalog before offering the campaign UI. Preserve the
   existing title/menu music and RETURN-to-dismiss behavior: RETURN can
   dismiss the title only after loading is ready. Early input must not enter
   an incomplete game. Music may start once its required code/data are ready;
   document any unavoidable interruption during KERNAL disk operations.
3. Turn the bitmap off immediately before reclaiming its storage. Install
   any chunks that need that region as the final startup placement step,
   then show the campaign UI. The user explicitly accepts this transition:
   load such chunks as late as possible, or stage them earlier and unpack
   them last. Do not overwrite a visible bitmap or wait for an additional
   confirmation. If no startup chunk needs this region, reclaim it later
   when a map's mission collection is installed.
4. Selecting a mission loads the chosen map's bundle when that map is not
   resident. Transfer compressed chunks, install map/shared data at their
   declared destinations, and retain the map's mission collection in RAM
   beneath KERNAL. The mission collection may stay compressed there.
5. Prepare the selected mission by copying or decompressing its record into
   the 597-byte mission workspace, then activate/scatter it into the runtime
   tables and initialize the world. Same-map mission changes reuse the
   resident collection. F3 restores the selected mission without disk I/O.
   A different map replaces the previous collection and map data.

Compression is used when it makes a payload smaller; raw is a valid codec.
Measure stored sizes and loading times instead of assuming every compressed
file makes the full transition faster. Preserve mission outcomes, commands,
objectives, bridges, campaign scores, and writable/read-only save behavior.
Keep the existing visible `LOADING`/`SAVING` behavior where applicable.

## The failure this must resolve

The reported build error was:

```text
gen_c64: mission set is 620 bytes; cap is 597 and it must end before $0B55
```

Currently `tools/gen_c64.py::pack_mission_set` packs every mission on a map,
plus shared objective strings, into one resident image at `$0900`. Normandy
has five missions sharing the 597 bytes before the deck segment at `$0B55`.
This is a per-map collection cap, not a per-mission cap and not a cap for
the entire campaign. Adding useful script content to Cross the River exposed
it. The scripts must compile and remain intact under the replacement design.

The new invariant is:

- The collection's directory and stored mission payloads occupy a separately
  budgeted banked region. Their combined expanded size may exceed 597 bytes.
- Each selected mission's complete expanded record, including its objective
  text and relocation metadata, must fit `[ $0900, $0B55 )`: 597 bytes.
- Existing script/table caps still apply independently: do not silently
  truncate ops, predicates, spawn templates, objective text, or units.
- Reject an oversized individual mission with its identity, actual size,
  capacity, and the component-size breakdown. Reject collection overflow
  separately, with its map identity and stored-size breakdown.

Compression cannot make an expanded mission larger than the workspace fit.
Do not conflate stored size, expanded record size, and scatter destination
capacity. The active script tables at `$BC80` are a different allocation.

## Current source and memory constraints

Inspect these before implementing; refresh sizes from the assembler rather
than treating historic figures in handoff notes as current:

| Concern | Source |
|---------|--------|
| Segments, initial entry, BSS assertions | `src/c64/force.asm`, `equ.inc`, `bss.asm`, `zp.asm` |
| Bitmap, VIC bank transition | `src/c64/title.asm` |
| Disk load, codec, validation, scatter | `src/c64/load.asm`, `tools/lzss.py` |
| Campaign and map/mission selection | `src/c64/menu.asm`, `game.asm`, `world.asm` |
| KERNAL-dependent interrupt returns | `src/c64/irq.asm`, `music.asm` |
| Bundle format, homes, mission records | `tools/gen_c64.py`, `tools/gen_sdl.py` |
| Routing patch destinations | `tools/c64_routes.py`, `src/c64/deck.asm` |
| Build, disk packaging, debug launch | `src/c64/CMakeLists.txt`, `tools/c64_disk.sh`, `tools/coop.sh` |

Baseline allocations to account for explicitly:

| Allocation | Current home / constraint |
|------------|---------------------------|
| Zero page and stack | CPU/KERNAL, loader, music, and game all need tracked ownership |
| Gameplay screen | `$0400`; sprite pointers at `$07F8` |
| Boot/load metadata | `$0801` onward; current index at `$081A` |
| Selected mission workspace | `$0900`–`$0B54` inclusive (597 bytes) |
| Deck code and state | starts `$0B55`, must not overlap scratch at `$1C00` |
| Campaign/geometry/routing scratch | `$1C00`–`$1FFF`, phase-dependent reuse |
| Charset | `$2000`–`$27FF` |
| Loader/runtime SPARE code | starts `$2800`, below the sprite allocation |
| Cursor sprite / gap code | `$3F80`–`$3FBF` / code from `$3FC0` |
| Main code | starts `$4000`, current live code must end before map homes |
| Map tiles and paper | `$A000` and `$AC80`, 3200 bytes each |
| Geometry / active mission tables | `$B900` / `$BC80` (active tables: 640 bytes) |
| Routing patch program | `$BF00`–`$BFFF` |
| Occupancy / BSS | `$C000`–`$C31F` / end-anchored below `$D000` |
| Title screen matrix | `$CC00`, overlaps later BSS |
| I/O and color RAM | `$D000`–`$DFFF`, not ordinary RAM with I/O visible |
| Title bitmap | `$E000`–`$FF3F` (8000 bytes), replaced after dismissal |
| Hardware vectors with KERNAL hidden | `$FFFA`–`$FFFF`; never mission payload |

Addresses outside the selected mission workspace can be revised with a
checked placement plan. Preserve or regenerate every dependent routing patch
address and assertion when changing BSS. Never call `clear_bss` while the
visible title matrix occupies BSS. Do not assume `$1C00` or `$C000` is free
while catalog operations, decompression, occupancy, or menu tile stashing use it.

## One authoritative layout definition

Add a machine-readable layout definition, for example
`assets/c64-layout.json`, and a generator/validator. Choose the final paths
and schema, but satisfy all of these contracts:

- Define region names, address ranges with exclusive ends, alignment,
  ownership, permitted CPU mappings, lifetime phases, and intentional
  overlays. Define capacities and reserved vector/I/O/stack areas there.
- Generate assembly equates and packer constants from that definition;
  remove independently maintained numeric copies where practical. Where
  am65 requires literal segment origins, emit the required source/include
  or validate those literals against the layout. An unchecked duplicate
  does not meet this requirement.
- Combine declared regions with fresh assembler segment/symbol output to
  validate actual placement, emitted and noemit sizes, and routing homes.
  Produce a readable memory report showing address, size, capacity, free
  space, phase, and owner. Identify every intentional overlap and the
  transition that makes it legal.
- Validate simultaneously live allocations by phase, including transfer
  buffers, decoder workspace, directory metadata, installed code, title
  graphics/music, and destination tables. Source buffers stay live until
  all readers have finished. Validate VIC bank/alignment requirements too.
- Generate a build/format compatibility identifier from the relevant layout
  and schemas. The bootstrap, game package, map bundles, and mission
  records must reject incompatible combinations before activation.
- Report per-map collection storage and per-mission expanded sizes in the
  build output/report. The 597-byte workspace capacity is generated from
  its boundaries, not another hand-written constant.
- Changes to the layout, scripts, codec, scatter schema, or assembler inputs
  trigger the appropriate rebuilds. Support clean and incremental builds
  without stale generated products. Resolve any generation/assembly cycle
  explicitly: assemble to an intermediate image, validate/package it, then
  produce the bootstrap and disk artifacts.

Do not silently permit overlapping chunks by trusting the order of entries.
An overlay needs named lifetimes and an explicit release/install transition.

## Extensible package and placement contract

Use a versioned format shared by startup and map loading where practical.
The present FMAP v2 six-chunk allowlist and fixed scatter tables are starting
points, not limits for the new architecture. Bump incompatible formats.

A package header identifies its kind, version, layout compatibility, entry
count, and total stored extent. Each chunk entry declares:

- A typed chunk ID and placement/schema ID.
- Stored offset and length; exact decoded length.
- Codec ID (`raw` and the selected compression codec initially).
- Destination region and offset, or a validated scatter schema.
- Required alignment, placement phase/dependencies, and integrity value.

The directory must be accessible before destination writes begin. Bound its
size/count using generated capacities, not an unexplained `CHUNK_MAX = 6`.
Resolve placement through generated allowed regions/schemas; a file-supplied
absolute address alone must never authorize a write into arbitrary memory.
Reserved fields/flags and unsupported required entries fail clearly. Keep
optional-entry rules explicit if implemented.

Separate transfer, validation, decode/copy, placement/scatter, and activation.
Adding a feature should normally add a layout allocation, schema/handler, and
chunk producer, rather than another special-case disk loader. Document the
handler ABI: inputs, carry/status return, registers, zero-page scratch,
interrupt/mapping requirements, and lifetime of source/destination buffers.

Use the existing LZSS codec unless measurements justify another. Compare real
game/map/mission payloads, decoder footprint and scratch needs, and total
loading time. Do not add a dependency on a different codec solely because
this design mentions compression. Emit deterministically and store raw when
compression does not save bytes. Decoder reads and writes must be bounded,
including malformed backreferences, truncation, and output-length mismatch.

A large game package cannot safely be `LOAD`ed over executing game/loader
code or unread payload. Choose a proven staging or streamed chunk strategy;
check its maximum supported package/chunk sizes in the build. If streaming,
bound every read and validate completion before dispatching a chunk. If
staging, prove that each move/decode order preserves unread sources. Include
real transfer/header buffers in the memory report, not just final homes.

## Banked mission collection and activation

Keep the current map's directory and independently encoded mission records
in a region beneath KERNAL, preferably within `$E000`–`$FFF9` with explicit
reservations. This is shared physical capacity: subtract any code, loader
state, vector handlers, or other payload assigned there. No claim of a full
8 KB mission budget without that accounting. Do not retain all maps' mission
collections unless measured capacity supports it; only the current map is
required. Directory caching outside the bank is permitted if budgeted.

For each mission, the directory contains stable identity/catalog mapping,
stored offset/size, expanded size, codec, record version, and integrity
metadata. All text needed by a mission belongs to its expanded record. Prefer
self-contained text over cross-mission sharing; sharing may reduce disk bytes
but must not require live banked string pointers during gameplay.

Replace absolute text-pointer fixups into the old collective `$0900` pack.
Encode record-relative offsets or another documented relocation scheme.
After expansion, validate each objective offset, NUL termination, and its
1..38 printable-ASCII limit within the selected record, then resolve pointers
to the mission workspace. Workspace text remains valid until replacement.
Existing `init:`/beat objectives and the yellow/white `>` display must survive.

Activation has these steps:

1. Validate selection and directory entry, source bounds, codec, record
   compatibility, and expanded size before preparing the destination.
2. Quiesce gameplay/interrupt readers; clear previous objective references
   and invalidate the active mission. Copy/decode into the workspace.
3. Validate the full expanded record, including counts, op/beat/predicate/
   template references, spawn bounds, exact lengths, text and relocation
   bounds, and checksums. A corrupted record must not scatter unchecked data.
4. Clear/fill runtime tables under the declared scatter schemas. Preserve
   unrelated persistent map/campaign data. Initialize the selected mission,
   reset bridge/routing state, run init once, and publish the active identity
   only on success. The first visible frame must show the selected mission.

Keep `world_load` versus `mission_activate` responsibilities explicit. Audit
`menu_launch`, map-load's current implicit mission-0 activation, F3, win/loss
return, and same-map relaunch. No path may initialize the wrong mission or
reuse pointers into an overwritten workspace. F3 can either re-expand the
selected record or reuse the immutable workspace after resetting all runtime
state; choose one and prove it restores init and bridge state without disk.

## CPU banking and interrupt contract

Default gameplay can keep KERNAL and I/O visible (`$01` currently `$36`).
Mission bytes beneath KERNAL are storage, not directly readable text pointers.
Keep loader/decoder/banking entry points outside ROM-hidden address ranges
unless an explicitly verified resident-code mapping requires otherwise.

Provide central enter/leave-bank routines or an equally explicit API. Preserve
and restore the caller's processor-port configuration and interrupt state;
do not hard-code `cli` on return or discard unrelated port bits. Track `$00`
DDR assumptions as well as `$01`. Keep I/O visible for disk/VIC/CIA/SID access
unless a separate, checked operation needs otherwise. Restore the KERNAL-visible
mapping before every KERNAL call or return through KERNAL interrupt routines.

`SEI` does not mask NMI. Specify and implement hardware IRQ/NMI/reset vectors,
CIA/VIC source masking and acknowledgement, and safe handlers whenever KERNAL
is hidden. Reserve `$FFFA`–`$FFFF` and any low-RAM handler/trampoline storage.
Audit RESTORE-key NMI behavior and KERNAL LOAD/SAVE's own mapping changes.
The current battle IRQ enters via `$FF48` and returns through `$EA81`/`$EA31`;
it must never run with those ROM routines hidden. Either disable/quiesce it
for bounded banked operations or supply a complete compatible RAM handler.
Use the simplest proven approach; permanent KERNAL-hidden gameplay is not
required for banked mission storage.

Define whether decode reads banked bytes directly during a quiescent loading
phase or copies bounded slices through an always-visible buffer. Disk loading
must not simultaneously depend on hidden KERNAL routines. Account for how
writes beneath visible ROM reach RAM, and verify the chosen KERNAL LOAD path
instead of assuming its destination/mapping behavior. Loading errors must
restore a safe mapping, interrupt state, and visible display.

## Failure handling and publication

Validate arithmetic without 16-bit wraparound. Check file/entry bounds,
region capacities, destination alignment, duplicates and missing required
chunks, integrity, versions, scatter counts/strides, and source/destination
interference. Distinguish a scatter image's decoded length from its larger
zero-filled runtime capacity, as the current geometry path does.

Do not launch partially installed code or mark a partially loaded map as
resident. Load/decode/scatter errors leave a safe error display; startup may
require retry/restart, and map/mission errors should permit a safe return to
the menu when resident menu code remains intact. Old map data need not remain
playable after a failed replacement, but must be invalidated. Include a
concise error category/file or chunk identity; do not only spin silently.
Preserve the existing campaign save failure behavior and file format shared
with SDL. A banked buffer must never overwrite the campaign save image.

## Implementation sequence and deliverables

1. Record a fresh baseline: assembler segment/symbol map, current package and
   per-mission sizes, source bank/IRQ contracts, and reproduction of the
   620-versus-597 failure using the current Cross the River script. Preserve
   user script edits and campaign scores throughout generation/testing.
2. Add the authoritative layout/schema definitions, generated constants,
   memory report, compatibility IDs, and placement validators. Specify the
   complete chosen physical layout and phase transitions before moving code.
3. Add package builders, raw/compressed codec handling, bounded reader/decoder,
   and shared placement/scatter dispatch. Establish the banking/vector API
   and verify it independently. Include host-side format regressions.
4. Split bootstrap/title from the main game. Package code/shared assets and
   update the startup flow with late bitmap reclamation. Ensure menu/music
   code is installed before it runs and the bootstrap stays executable until
   handoff. It may be reclaimed afterward only under a declared lifetime.
5. Move per-map mission collections to banked storage, independently encode
   records, update activation/text relocation, and wire every launch/reset
   path. Remove the collective 597-byte cap while retaining the per-record cap.
6. Update CMake, D64 and folder-mount packaging, smoke/probe/co-op launch tools,
   and output-file dependencies. Keep `build/force.prg` as the launchable
   bootstrap where practical; supporting game files belong under `build/c64/`
   alongside map bundles and `campaign.prg`. Document actual CBM filenames.
   Normal device-8 loading must work on D64 as well as a host folder; an
   emulator-only direct injection is not a complete implementation.
7. Complete the verification below, update landed invariants and the generated
   memory report link in `agents/c64-port.md`/`agents/testing.md`, and mark this
   design landed in `design/README.md`. Keep current format and launch docs
   accurate in the same change. Report measurements, failures, and limitations.

## Required completion evidence

Use `agents/testing.md` for existing build gates and pipeline regressions.
C64 emulator checks should be windowed according to the project handoff.
Archive machine-readable snapshots/comparisons and timing results in build
artifacts. Do not claim success solely from assembly or a screenshot.

- Clean/incremental builds generate consistent bootstrap, game package, map
  bundles, disk image when tooling is available, and memory report. No
  simultaneously live overlaps or unsanctioned destination writes.
- For every installed code/data chunk, compare runtime bytes with the
  corresponding uncompressed build image, allowing only documented fixups.
  Independently decode every compressed payload on the host too.
- The reported 620-byte collection and a synthetic collection exceeding 597
  expanded bytes load successfully when each mission fits. Test raw and
  compressed missions, a 597-byte record, a 598-byte rejection, collection
  capacity/overflow, and a selection beyond mission 0.
- Corrupt/truncate headers and payloads; test bad versions/layout IDs, codecs,
  checksums, offsets, lengths, references, objective termination, duplicate
  chunks, and overlapping destinations. Fail safely without activation or
  out-of-bounds memory writes. Include guard-byte checks around working homes.
- Confirm objective text pointers always resolve within the active workspace;
  both farm cues and Cross the River's cue work after changes and restarts.
- Show the title before the main-game disk transfer; verify it remains intact
  during permitted installs, then is disabled before its RAM is reused.
  Early RETURN, RETURN after ready, missing game file, and corrupted game
  package must not jump into incomplete code. Title/menu music and fade still
  function on PAL and NTSC; measure permitted loading interruptions.
- Exercise title -> menu -> mission, another mission on the same map, another
  map, F3, win/loss return to menu, repeated map changes, campaign save/F8,
  and successful/refused writes. Confirm no disk load for same-map selection
  or F3 and no loss of stored scores from asset generation.
- Verify routing/bridge state and every scatter destination against generated
  reference images after initial load, restart, and map switch. Keep existing
  routing-home assertions or generated equivalents.
- Exercise keyboard/joystick, IRQ/raster behavior, and RESTORE/NMI handling
  across banking operations on PAL and NTSC. Confirm `$00`/`$01`, CPU interrupt
  state, vectors, and relevant VIC/CIA configuration are restored as specified.
- Compare bytes transferred and timings for initial bootstrap, game loading,
  map change, and mission preparation. Report both stored savings and elapsed
  time; if decompression offsets transfer savings, explain the measurement.

This work is complete when the requested staged flow and per-mission capacity
are implemented, exercised, and documented with a reproducible memory map.
