#!/usr/bin/env python3
"""Emit the C64 charset and farm tables from the same assets as the SDL build.

Playfield characters are multicolour: %00 red, %01 grey, %10 light blue,
%11 per-cell paper. The hires font sits at chars 128-223 (ASCII 32-127).
Chars 224-255 are scratch for soldier composites, filled at runtime.
"""

from __future__ import annotations

import re
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import gen_sdl  # noqa: E402

INK_RED = 2
INK_GREY = 11
INK_BLUE = 14
TILES = 128
FONT_BASE = 128


def load_indices(path: Path) -> tuple[int, int, list[list[int]]]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise gen_sdl.Error(f"{path}: not a png")
    pos = 8
    idat = b""
    ihdr = b""
    while pos + 8 <= len(data):
        ln = struct.unpack(">I", data[pos : pos + 4])[0]
        typ = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + ln]
        if typ == b"IHDR":
            ihdr = chunk
        elif typ == b"IDAT":
            idat += chunk
        elif typ == b"IEND":
            break
        pos += 12 + ln
    width, height, bit, color, comp, filt, inter = struct.unpack(">IIBBBBB", ihdr)
    if bit != 8 or color != 3 or comp != 0 or filt != 0 or inter != 0:
        raise gen_sdl.Error(f"{path}: need indexed 8-bit png")
    raw = zlib.decompress(idat)
    rows: list[list[int]] = []
    i = 0
    prev = bytearray(width)
    for _y in range(height):
        ft = raw[i]
        src = raw[i + 1 : i + 1 + width]
        i += 1 + width
        out = bytearray(width)
        for x in range(width):
            left = out[x - 1] if x else 0
            up = prev[x]
            ul = prev[x - 1] if x else 0
            v = src[x]
            if ft == 0:
                out[x] = v
            elif ft == 1:
                out[x] = (v + left) & 255
            elif ft == 2:
                out[x] = (v + up) & 255
            elif ft == 3:
                out[x] = (v + (left + up) // 2) & 255
            elif ft == 4:
                out[x] = (v + gen_sdl.paeth(left, up, ul)) & 255
            else:
                raise gen_sdl.Error(f"{path}: bad filter")
        rows.append(list(out))
        prev = out
    return width, height, rows


def slice_index_tiles(
    rows: list[list[int]], columns: int, count: int
) -> list[list[list[int]]]:
    tiles: list[list[list[int]]] = []
    for tid in range(count):
        tx = tid % columns
        ty = tid // columns
        tile: list[list[int]] = []
        for py in range(8):
            row = rows[ty * 8 + py]
            tile.append(row[tx * 8 : tx * 8 + 8])
        tiles.append(tile)
    return tiles


def mc_bits(index: int) -> int:
    if index == INK_GREY:
        return 0b01
    if index == INK_BLUE:
        return 0b10
    if index == INK_RED:
        return 0b00
    return 0b11


def mc_row(pair_row: list[int]) -> int:
    byte = 0
    for px in range(0, 8, 2):
        byte = ((byte << 2) | mc_bits(pair_row[px])) & 255
    return byte


def force_colour(tile: list[list[int]]) -> int:
    """$FF means the cell paper comes from the colour layer."""
    saw_ink = False
    saw_clear = False
    solids: set[int] = set()
    for row in tile:
        for c in row:
            if c == 0:
                saw_clear = True
            elif c in (INK_RED, INK_GREY, INK_BLUE):
                saw_ink = True
            else:
                solids.add(c)
    if saw_ink or saw_clear or len(solids) != 1:
        return 0xFF
    return next(iter(solids))


def paper_of(tile: list[list[int]]) -> int:
    c = tile[0][0]
    return 0 if c == 0 else c


def rev8(b: int) -> int:
    r = 0
    for i in range(8):
        if b & (1 << i):
            r |= 1 << (7 - i)
    return r


def load_font(path: Path) -> list[list[int]]:
    text = path.read_text(encoding="utf-8")
    rows = re.findall(r"\{([^}]*)\}", text.split("font_ascii", 1)[1])
    glyphs: list[list[int]] = []
    for row in rows:
        nums = [int(n, 16) for n in re.findall(r"0x[0-9A-Fa-f]+", row)]
        if len(nums) == 8:
            glyphs.append(nums)
    if len(glyphs) != 96:
        raise gen_sdl.Error(f"{path}: expected 96 glyphs, got {len(glyphs)}")
    return glyphs


def emit_bytes(label: str, data: list[int]) -> str:
    lines = [f"{label}:"]
    if not data:
        lines.append("    .byte 0")
        return "\n".join(lines) + "\n"
    for i in range(0, len(data), 16):
        chunk = data[i : i + 16]
        lines.append("    .byte " + ",".join(f"${b & 255:02X}" for b in chunk))
    return "\n".join(lines) + "\n"


def pad(values: list[int], n: int) -> list[int]:
    out = list(values[:n])
    if len(out) < n:
        out.extend([0] * (n - len(out)))
    return out


def build() -> int:
    root = Path(__file__).resolve().parents[1]
    out = root / "src" / "c64" / "generated"
    out.mkdir(parents=True, exist_ok=True)

    name_per_id, classes, empty_tile = gen_sdl.load_tile_desc(root / "assets" / "tiles.txt")
    missions = gen_sdl.load_missions(root / "assets" / "missions.txt")
    chip_to_preset = gen_sdl.load_properties_txt(root / "assets" / "properties.txt")
    tile_w, tile_h, columns, count, png = gen_sdl.load_tsx(root / "assets" / "maps" / "tiles.tsx")
    if (tile_w, tile_h, count) != (8, 8, TILES):
        raise gen_sdl.Error(f"tileset must be 128 of 8x8, got {count} {tile_w}x{tile_h}")
    _w, _h, rows = load_indices(png)
    tiles = slice_index_tiles(rows, columns, count)
    for tid, tile in enumerate(tiles):
        for ry, row in enumerate(tile):
            for px in range(0, 8, 2):
                if row[px] != row[px + 1]:
                    raise gen_sdl.Error(f"tile {tid} row {ry} is not 2-wide")

    class_table = [classes["empty"]] * count
    for tid in range(count):
        if tid < len(name_per_id) and name_per_id[tid] is not None:
            class_table[tid] = classes[name_per_id[tid]]

    tmx_files = sorted((root / "assets" / "maps").glob("*.tmx"))
    maps = []
    for tmx in tmx_files:
        name, width, height, planes, firstgid = gen_sdl.load_tmx(tmx, count, empty_tile)
        maps.append(
            gen_sdl.compile_map(
                name, width, height, planes, firstgid, empty_tile,
                chip_to_preset, class_table, classes,
            )
        )
    by_name = {m.name: m for m in maps}
    mission = next(m for m in missions if m[0] == "farm_mission" or m[2] == 40)
    # missions are (name, map, x, y, w, h, script). Prefer the farm window.
    farm_m = None
    for m in missions:
        if m[1] == "farm":
            farm_m = m
            break
    if farm_m is None:
        raise gen_sdl.Error("no farm mission")
    _mname, map_name, px, py, pw, ph, stem = farm_m
    compiled = by_name[map_name]
    if compiled.width != 80:
        raise gen_sdl.Error(f"map_ptr assumes width 80, got {compiled.width}")
    # Caps match src/c64/equ.inc. pad() used to drop extra rooms quietly.
    if compiled.height > 40:
        raise gen_sdl.Error(
            f"row tables hold 40 rows, got height {compiled.height}"
        )
    if len(compiled.rooms) > 16:
        raise gen_sdl.Error(
            f"ROOM_MAX is 16, got {len(compiled.rooms)} rooms"
        )
    for room in compiled.rooms:
        if room.w > 40 or room.h > 40:
            raise gen_sdl.Error(
                f"room colour {room.colour} is {room.w}x{room.h}; "
                "room edges are capped at 40"
            )
    if len(compiled.portal_x) > 24:
        raise gen_sdl.Error(
            f"PORTAL_MAX is 24, got {len(compiled.portal_x)} portals"
        )
    if len(compiled.cover_x) > 128:
        raise gen_sdl.Error(
            f"COVER_MAX is 128, got {len(compiled.cover_x)} cover chips"
        )
    if len(compiled.scout_x) > 127:
        raise gen_sdl.Error(
            f"scout ids share the cover byte, got {len(compiled.scout_x)}"
        )
    script = gen_sdl.compile_script(root / "assets" / "scripts" / f"{stem}.txt", compiled)

    charset = bytearray(256 * 8)
    for tid, tile in enumerate(tiles):
        for ry, row in enumerate(tile):
            charset[tid * 8 + ry] = mc_row(row)
    for gi, glyph in enumerate(load_font(root / "src" / "sdl" / "core" / "font.c")):
        base = (FONT_BASE + gi) * 8
        for ry, b in enumerate(glyph):
            charset[base + ry] = rev8(b)
    (out / "charset.bin").write_bytes(charset)

    paper = [paper_of(tiles[tid]) for tid in compiled.color]
    rooms = compiled.rooms
    parts: list[str] = [
        "; Generated by tools/gen_c64.py — do not edit.\n",
        f"rom_map_w: .byte {compiled.width}\n",
        f"rom_map_h: .byte {compiled.height}\n",
        f"rom_play_x: .byte {px}\n",
        f"rom_play_y: .byte {py}\n",
        f"rom_play_w: .byte {pw}\n",
        f"rom_play_h: .byte {ph}\n",
        f"rom_room_count: .byte {len(rooms)}\n",
        f"rom_cover_count: .byte {len(compiled.cover_x)}\n",
        f"rom_portal_count: .byte {len(compiled.portal_x)}\n",
        f"rom_scout_count: .byte {len(compiled.scout_x)}\n",
        f"rom_spawn_count: .byte {len(compiled.spawn_x)}\n",
        emit_bytes("rom_tiles", compiled.tiles),
        emit_bytes("rom_paper", paper),
        emit_bytes("rom_tile_class", class_table),
        emit_bytes("rom_tile_force", [force_colour(t) for t in tiles]),
        emit_bytes("rom_room_x0", pad([r.x0 for r in rooms], 16)),
        emit_bytes("rom_room_y0", pad([r.y0 for r in rooms], 16)),
        emit_bytes("rom_room_w", pad([r.w for r in rooms], 16)),
        emit_bytes("rom_room_h", pad([r.h for r in rooms], 16)),
        emit_bytes("rom_room_colour", pad([r.colour for r in rooms], 16)),
        emit_bytes("rom_room_cover_base", pad(compiled.room_cover_base, 16)),
        emit_bytes("rom_room_cover_count", pad(compiled.room_cover_count, 16)),
        emit_bytes("rom_room_scout_base", pad(compiled.room_scout_base, 16)),
        emit_bytes("rom_room_scout_count", pad(compiled.room_scout_count, 16)),
        emit_bytes("rom_room_axis", pad(compiled.room_axis, 16)),
        emit_bytes("rom_room_cover_lo", pad(compiled.room_cover_lo, 16)),
        emit_bytes("rom_room_cover_none", pad(compiled.room_cover_none, 16)),
        emit_bytes("rom_room_cover_hi", pad(compiled.room_cover_hi, 16)),
        emit_bytes("rom_cover_x", compiled.cover_x or [0]),
        emit_bytes("rom_cover_y", compiled.cover_y or [0]),
        emit_bytes("rom_cover_grade", compiled.cover_grade or [0]),
        emit_bytes("rom_cover_facing", compiled.cover_facing or [0]),
        emit_bytes("rom_portal_x", compiled.portal_x or [0]),
        emit_bytes("rom_portal_y", compiled.portal_y or [0]),
        emit_bytes("rom_scout_x", compiled.scout_x or [0]),
        emit_bytes("rom_scout_y", compiled.scout_y or [0]),
        emit_bytes("rom_scout_facing", compiled.scout_facing or [0]),
        emit_bytes("rom_spawn_x", compiled.spawn_x or [0]),
        emit_bytes("rom_spawn_y", compiled.spawn_y or [0]),
        emit_bytes("rom_spawn_tile", compiled.spawn_tile or [0]),
        f"sc_op_count: .byte {script.op_count}\n",
        f"sc_beat_count: .byte {script.beat_count}\n",
        f"sc_watch_count: .byte {script.watch_count}\n",
        f"sc_pred_count: .byte {script.pred_count}\n",
        f"sc_where_count: .byte {script.where_count}\n",
        f"sc_spawn_count: .byte {script.spawn_tmpl_count}\n",
        f"sc_start_spawn_room: .byte {script.start_spawn_room}\n",
        f"sc_start_beat: .byte {script.start_beat}\n",
        f"sc_player_grenades: .byte {script.player_grenades}\n",
        f"sc_player_grenade_wait: .byte {script.player_grenade_wait}\n",
        f"sc_enemy_grenades: .byte {script.enemy_grenades}\n",
        f"sc_enemy_grenade_wait: .byte {script.enemy_grenade_wait}\n",
        emit_bytes("sc_op_code", script.op_code or [0]),
        emit_bytes("sc_op_a", script.op_a or [0]),
        emit_bytes("sc_op_b", script.op_b or [0]),
        emit_bytes("sc_op_c", script.op_c or [0]),
        emit_bytes("sc_beat_pc", script.beat_pc or [0]),
        emit_bytes("sc_watch_pred0", script.watch_pred0 or [0]),
        emit_bytes("sc_watch_pred1", script.watch_pred1 or [0]),
        emit_bytes("sc_watch_op", script.watch_op or [0]),
        emit_bytes("sc_watch_arg", script.watch_arg or [0]),
        emit_bytes("sc_watch_flags", script.watch_flags or [0]),
        emit_bytes("sc_pred_kind", script.pred_kind or [0]),
        emit_bytes("sc_pred_who", script.pred_who or [0]),
        emit_bytes("sc_pred_a", script.pred_a or [0]),
        emit_bytes("sc_pred_b", script.pred_b or [0]),
        emit_bytes("sc_where_kind", script.where_kind or [0]),
        emit_bytes("sc_where_a", script.where_a or [0]),
        emit_bytes("sc_where_b", script.where_b or [0]),
        emit_bytes("sc_spawn_n", script.spawn_n or [0]),
        emit_bytes("sc_spawn_letter", script.spawn_letter or [0]),
        emit_bytes("sc_spawn_room", script.spawn_room or [0]),
        emit_bytes("sc_spawn_batch", script.spawn_batch or [0]),
        emit_bytes("sc_spawn_period", script.spawn_period or [0]),
    ]
    (out / "farm.asm").write_text("".join(parts), encoding="utf-8")
    print(
        f"gen_c64: {compiled.name} {compiled.width}x{compiled.height} "
        f"play {px},{py},{pw},{ph} rooms {len(rooms)} "
        f"script {script.op_count} ops -> {out}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(build())
    except gen_sdl.Error as exc:
        print(f"gen_c64: {exc}", file=sys.stderr)
        raise SystemExit(1)
