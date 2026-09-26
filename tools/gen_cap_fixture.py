#!/usr/bin/env python3
"""Write a cap-sized raw bundle for the load-tail proof.

Not a game asset and not a missions.txt row. Six dummy missions at the
script caps, raw planes, load address $A000, exclusive end $CC0F.

Plane prefixes (16 bytes), not the farm's $70 / $05:

    tiles at $A000: 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF 10
    paper at $AC80: 21 32 43 54 65 76 87 98 A9 BA CB DC ED FE 0F 1F

Paper byte $0396 is $FF, so a load at $A000 leaves $FF at $C325 until
clear_bss. The rest of each plane is 0.

    python3 tools/gen_cap_fixture.py build/c64/cap-farm.prg
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

LOAD = 0xA000
PLANE_BYTES = 3200
# Paper source starts at $BF8F. $C325 is bss_start.
BSS_AT = 0xC325
PAPER_AT = 0xBF8F
TILE_PREFIX = bytes.fromhex("112233445566778899AABBCCDDEEFF10")
PAPER_PREFIX = bytes.fromhex("2132435465768798A9BACBDCEDFE0F1F")

# Caps from tools/gen_sdl.py / src/c64/equ.inc. A full body is 639 bytes.
SPAWN_MAX = 32
OP_MAX = 64
BEAT_MAX = 12
WATCH_MAX = 8
PRED_MAX = 32
WHERE_MAX = 16
TMPL_MAX = 8
ROOM_MAX = 16
COVER_MAX = 128
PORTAL_MAX = 24
SCOUT_MAX = 32
STEM_LEN = 15
MISSIONS = 6


def _mission_body() -> bytes:
    header = bytes((0, 0, 0, 0, 0, 0, SPAWN_MAX))
    spawns = bytes(SPAWN_MAX * 3)
    scalars = bytes((OP_MAX, BEAT_MAX, WATCH_MAX, PRED_MAX, WHERE_MAX, TMPL_MAX))
    scalars += bytes(6)
    arrays = bytes(
        OP_MAX * 4
        + BEAT_MAX * 1
        + WATCH_MAX * 5
        + PRED_MAX * 4
        + WHERE_MAX * 3
        + TMPL_MAX * 5
    )
    body = header + spawns + scalars + arrays
    if len(body) != 639:
        raise SystemExit(f"capped mission is {len(body)} bytes, expected 639")
    return body


def _missions() -> bytes:
    body = _mission_body()
    out = bytearray((MISSIONS,))
    for i in range(MISSIONS):
        stem = f"cap{i:012d}".encode("ascii")
        if len(stem) != STEM_LEN:
            raise SystemExit(f"stem {stem!r} is not {STEM_LEN} bytes")
        out.append(STEM_LEN)
        out += stem
        out += struct.pack("<H", len(body))
        out += body
    if len(out) != 3943:
        raise SystemExit(f"mission chunk is {len(out)} bytes, expected 3943")
    return bytes(out)


def _geometry() -> bytes:
    # 6 + 16*13 + 128*4 + 24*2 + 32*3 = 870. Counts at the caps, rest zero.
    out = bytearray(870)
    out[0] = 80
    out[1] = 40
    out[2] = ROOM_MAX
    out[3] = COVER_MAX
    out[4] = PORTAL_MAX
    out[5] = SCOUT_MAX
    return bytes(out)


def _planes() -> tuple[bytes, bytes]:
    tiles = bytearray(PLANE_BYTES)
    paper = bytearray(PLANE_BYTES)
    tiles[:16] = TILE_PREFIX
    paper[:16] = PAPER_PREFIX
    paper[BSS_AT - PAPER_AT] = 0xFF
    return bytes(tiles), bytes(paper)


def build() -> bytes:
    geo = _geometry()
    missions = _missions()
    tiles, paper = _planes()
    chunks = (
        (1, 0, 0xB900, 870, geo),
        (2, 0, 0x0900, len(missions), missions),
        (3, 0, LOAD, PLANE_BYTES, tiles),
        (4, 0, 0xAC80, PLANE_BYTES, paper),
    )
    entries = bytearray()
    bodies = bytearray()
    offset = 26 + 10 * len(chunks)
    for cid, flags, dest, dest_len, body in chunks:
        entries += struct.pack("<BBHHHH", cid, flags, offset, len(body), dest, dest_len)
        bodies += body
        offset += len(body)
    payload = bytearray(b"FMAP")
    payload += bytes((1, 0x01, MISSIONS, 0))
    payload += bytes([0xA0]) * 16
    payload += bytes((0, len(chunks)))
    payload += entries
    payload += bodies
    if len(payload) != 11279:
        raise SystemExit(f"payload is {len(payload)} bytes, expected 11279")
    end = LOAD + len(payload)
    if end != 0xCC0F:
        raise SystemExit(f"exclusive end ${end:04X} != $CC0F")
    return struct.pack("<H", LOAD) + bytes(payload)


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: python3 tools/gen_cap_fixture.py OUT.prg")
    out = Path(sys.argv[1])
    blob = build()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(blob)
    end = LOAD + len(blob) - 2
    print(
        f"gen_cap_fixture: {out} {len(blob)} bytes end ${end:04X}",
        file=sys.stderr,
    )
    print("tiles " + TILE_PREFIX.hex())
    print("paper " + PAPER_PREFIX.hex())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
