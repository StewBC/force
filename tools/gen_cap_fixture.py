#!/usr/bin/env python3
"""Write a raw bundle for the load-tail proof.

Not a game asset and not a missions.txt row. One empty mission, raw
planes, load address $A000. A capped mission body is 640 bytes and does
not fit in the pack: the deck segment owns $0B55–$1C00, so the mission
chunk must end by $0B55 (597 bytes). Six capped missions are 3949 bytes.

Plane prefixes (16 bytes), not the farm's $70 / $05:

    tiles at $A000: 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF 10
    paper at $AC80: 21 32 43 54 65 76 87 98 A9 BA CB DC ED FE 0F 1F

The paper source no longer reaches $C325. The written PRG is padded so a
load at $A000 leaves $FF at $C325 until clear_bss.

    python3 tools/gen_cap_fixture.py build/c64/cap-farm.prg

--direct-lzss writes the same shell with this farm's LZSS planes. The
532-byte tile source stays inside [$A000, $AC80).
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

LOAD = 0xA000
PLANE_BYTES = 3200
# $C325 is bss_start. PAPER_AT is filled once the mission chunk is known.
BSS_AT = 0xC325
TILE_PREFIX = bytes.fromhex("112233445566778899AABBCCDDEEFF10")
PAPER_PREFIX = bytes.fromhex("2132435465768798A9BACBDCEDFE0F1F")

# Caps from tools/gen_sdl.py / src/c64/equ.inc. A full body is 640 bytes
# once deck_cost is the 13th scalar.
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
# Packed into the cap-fixture chunk. A 640-byte body does not fit there.
MISSIONS = 1


def _mission_body() -> bytes:
    header = bytes((0, 0, 0, 0, 0, 0, SPAWN_MAX))
    spawns = bytes(SPAWN_MAX * 3)
    scalars = bytes((OP_MAX, BEAT_MAX, WATCH_MAX, PRED_MAX, WHERE_MAX, TMPL_MAX))
    scalars += bytes(7)
    arrays = bytes(
        OP_MAX * 4
        + BEAT_MAX * 1
        + WATCH_MAX * 5
        + PRED_MAX * 4
        + WHERE_MAX * 3
        + TMPL_MAX * 5
    )
    body = header + spawns + scalars + arrays
    if len(body) != 640:
        raise SystemExit(f"capped mission is {len(body)} bytes, expected 640")
    return body


def _missions() -> bytes:
    # 7 header bytes and 13 scalars, every count 0. _mission_body stays
    # the 640-byte contract; it is not stored in this chunk.
    _mission_body()
    body = bytes(20)
    stem = b"c"
    out = bytearray((MISSIONS, len(stem)))
    out += stem
    out += struct.pack("<H", len(body))
    out += body
    # 1 + (1 + 1 + 2 + 20) = 25.
    if len(out) != 25:
        raise SystemExit(f"mission chunk is {len(out)} bytes, expected 25")
    return bytes(out)


def _geometry() -> bytes:
    # The 870-byte home is full at 32 scouts. The deck count takes one byte,
    # so this image stops at 31 scouts and appends a zero count.
    # 6 + 16*13 + 128*4 + 24*2 + 31*3 + 1 = 868.
    scouts = SCOUT_MAX - 1
    out = bytearray((80, 40, ROOM_MAX, COVER_MAX, PORTAL_MAX, scouts))
    out += bytes(ROOM_MAX * 13 + COVER_MAX * 4 + PORTAL_MAX * 2 + scouts * 3)
    out.append(0)
    if len(out) != 868 or len(out) > 870:
        raise SystemExit(f"geometry is {len(out)} bytes, expected 868")
    return bytes(out)


def _paper_at(geo_len: int, mission_len: int) -> int:
    """Load address of the raw paper source."""
    return LOAD + 66 + geo_len + mission_len + PLANE_BYTES


def _planes(geo_len: int, mission_len: int) -> tuple[bytes, bytes]:
    tiles = bytearray(PLANE_BYTES)
    paper = bytearray(PLANE_BYTES)
    tiles[:16] = TILE_PREFIX
    paper[:16] = PAPER_PREFIX
    paper_at = _paper_at(geo_len, mission_len)
    index = BSS_AT - paper_at
    if 0 <= index < PLANE_BYTES:
        paper[index] = 0xFF
    return bytes(tiles), bytes(paper)


def _cover_bss(blob: bytes) -> bytes:
    """Pad a load at $A000 so address $C325 is $FF until clear_bss."""
    payload_end = LOAD + len(blob) - 2
    if payload_end > BSS_AT:
        raise SystemExit(
            f"payload already reaches ${payload_end:04X}, past bss ${BSS_AT:04X}"
        )
    pad = BSS_AT - payload_end
    return blob + bytes(pad) + bytes((0xFF,))


def _pack(chunks: tuple[tuple[int, int, int, int, bytes], ...]) -> bytes:
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
    return struct.pack("<H", LOAD) + bytes(payload)


def build() -> bytes:
    geo = _geometry()
    missions = _missions()
    import gen_c64

    if len(missions) > gen_c64.MISSION_SET_MAX:
        raise SystemExit(
            f"mission chunk {len(missions)} exceeds {gen_c64.MISSION_SET_MAX}"
        )
    tiles, paper = _planes(len(geo), len(missions))
    blob = _pack((
        (1, 0, 0xB900, 870, geo),
        (2, 0, 0x0900, len(missions), missions),
        (3, 0, LOAD, PLANE_BYTES, tiles),
        (4, 0, 0xAC80, PLANE_BYTES, paper),
    ))
    payload = len(blob) - 2
    # 66 + 868 + 25 + 3200 + 3200 = 7359. The pad then plants $FF at $C325.
    if payload != 7359:
        raise SystemExit(f"payload is {payload} bytes, expected 7359")
    blob = _cover_bss(blob)
    end = LOAD + len(blob) - 2
    if end != BSS_AT + 1 or blob[-1] != 0xFF:
        raise SystemExit(f"exclusive end ${end:04X}, last ${blob[-1]:02X}")
    return blob


def build_direct_lzss() -> tuple[bytes, bytes, bytes]:
    """Six-mission cap layout with this farm's LZSS planes.

    Tiles sit at $B30F (532 bytes, flag set) and miss [$A000, $AC80).
    Returns the PRG, the decoded tile prefix, and the compressed prefix.
    """
    import gen_c64

    labels = gen_c64.linked_labels()
    raw_tiles = bytes(labels["rom_tiles"])
    raw_paper = bytes(labels["rom_paper"])
    tile_flag, tile_body = gen_c64.stored_plane(raw_tiles)
    paper_flag, paper_body = gen_c64.stored_plane(raw_paper)
    if tile_flag != 1 or len(tile_body) != 532:
        raise SystemExit(
            f"farm tiles stored as flag {tile_flag} len {len(tile_body)}, expected flag 1 len 532"
        )
    if tile_body[:16] == raw_tiles[:16]:
        raise SystemExit("compressed tile prefix equals the raw prefix")
    geo = _geometry()
    missions = _missions()
    blob = _pack((
        (1, 0, 0xB900, 870, geo),
        (2, 0, 0x0900, len(missions), missions),
        (3, tile_flag, LOAD, PLANE_BYTES, tile_body),
        (4, paper_flag, 0xAC80, PLANE_BYTES, paper_body),
    ))
    payload = blob[2:]
    # Chunk 3 entry: id, flags, offset, src_len. The 532-byte source
    # must sit inside [$A000, $AC80).
    base = 26 + 2 * 10
    off = payload[base + 2] | (payload[base + 3] << 8)
    src = payload[base + 4] | (payload[base + 5] << 8)
    expect = 66 + len(geo) + len(missions)
    if payload[base] != 3 or payload[base + 1] != 1 or off != expect or src != 532:
        raise SystemExit(
            f"tile chunk id {payload[base]} flag {payload[base + 1]} off {off} len {src}"
        )
    if not (LOAD <= LOAD + off < 0xAC80):
        raise SystemExit(f"tile source ${LOAD + off:04X} misses the tile window")
    return blob, raw_tiles[:16], tile_body[:16]


def main() -> int:
    direct = False
    args = sys.argv[1:]
    if args and args[0] == "--direct-lzss":
        direct = True
        args = args[1:]
    if len(args) != 1:
        raise SystemExit(
            "usage: python3 tools/gen_cap_fixture.py [--direct-lzss] OUT.prg"
        )
    out = Path(args[0])
    out.parent.mkdir(parents=True, exist_ok=True)
    if direct:
        blob, decoded, compressed = build_direct_lzss()
        out.write_bytes(blob)
        end = LOAD + len(blob) - 2
        print(
            f"gen_cap_fixture: direct-lzss {out} {len(blob)} bytes end ${end:04X}",
            file=sys.stderr,
        )
        print("tiles " + decoded.hex())
        print("comp " + compressed.hex())
        return 0
    blob = build()
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
