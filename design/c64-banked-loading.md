# C64 compressed loading and banked RAM

Author: Codex, recording the user's agreed direction.
Date: 2026-10-11.
Status: Accepted direction; deferred implementation.

## Intent and implementation trigger

Keep the current loader until a requested C64 feature no longer fits the
resident layout. At that point, implement compressed chunk loading and use
RAM beneath the KERNAL as part of that feature's work. The user has authorized
this future direction: an agent should recognize the capacity problem and
proceed without asking again whether to adopt this system. This is not an
instruction to implement it now.

Confirm the shortage against a fresh assembler segment/symbol listing and
the generated bundle sizes. Remove genuinely dead code or use a small existing
gap when that solves the problem cleanly. Do not repeatedly squeeze live code,
reduce features, or move boundaries into loader destinations to postpone a
needed memory architecture change.

## Basic architecture

- Keep a small bootstrap, loader, decompressor, and bank-switching entry points
  at addresses accessible in all required CPU memory configurations.
- Package main code, supporting code modules, and game data as chunks with
  explicit destinations, stored and expanded sizes, and codec identification.
  Load and decompress them into their assigned homes before use.
- Use `$E000–$FFFF` underlying RAM for resident code, data, or both. It currently
  holds the copied title bitmap after the title is dismissed. Reserve and
  manage the CPU vectors at `$FFFA–$FFFF` when KERNAL ROM is hidden.
- Bank KERNAL ROM out to execute/read that RAM. Bank it back in for KERNAL
  services. Specify the IRQ/NMI/vector and banking contract before moving code;
  the current battle IRQ relies on KERNAL entry/exit routines.
- Graphics can also occupy underlying RAM because VIC-II visibility differs
  from CPU ROM mapping. Respect VIC bank, alignment, and character-ROM rules
  when choosing screen, charset, sprite, or bitmap destinations.
- Preserve campaign load/save, map switching, mission restart, and writable
  device-8 behavior. Staging/decompression must never overwrite unread source,
  executing code, live state, or a still-needed loader.

Compression reduces the stored image, not the expanded resident footprint.
Banking makes almost 8 KB more physical RAM useful; overlays can additionally
share addresses between mutually exclusive title/menu/loading/gameplay phases.
Overlay design and RAM beneath I/O are optional follow-ons, not prerequisites.
Once resident requirements exhaust physical RAM, compression alone cannot help.

## Current constraints and codec choice

Source of truth: `src/c64/force.asm`, `src/c64/equ.inc`,
`src/c64/generated/homes.inc`, `src/c64/load.asm`, `src/c64/title.asm`,
`src/c64/irq.asm`, and `tools/gen_c64.py`.

At this date CODE ends at `$9E6B` exclusive, leaving 405 bytes before the map
planes at `$A000`. Normandy's five packed missions use 544 of the 597 bytes
at `$0900`; DECK begins at `$0B55`. `$1C00–$1FFF` is loading/campaign scratch,
not permanent free storage. These figures must be regenerated when work starts.

The current `lzss_decode` plus `lz_take` and its error jump occupies 172 bytes
in SPARE. Upstream forward 6502 LZSA decoders measured on this date: LZSA1
small 172 bytes, LZSA1 fast 306, LZSA2 small 241, LZSA2 fast 252; LZSA2 also
needs one zero-page scratch byte. These exclude FORCE integration and additional
validation. Reference: https://github.com/emmanuel-marty/lzsa/tree/master/asm/6502.
Choose a codec by measuring real game chunks, decoder footprint, load time,
and staging requirements. LZSA is a candidate, not a mandatory dependency.

## Completion evidence

Verify the emitted layout and every decompressed chunk against its original
bytes. Exercise title → menu → mission, a different map load, F3 restart,
return to menu, campaign save, and both successful/refused disk writes.
Verify interrupts, keyboard/joystick input, and graphics under each banking
configuration used. Update `agents/c64-port.md` with the landed memory map and
banking contract, and mark this design landed in `design/README.md`.
