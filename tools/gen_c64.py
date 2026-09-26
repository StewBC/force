#!/usr/bin/env python3
"""Emit the C64 charset, tile class/force, home equates, and the raw farm bundle.

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


def _columns(cols: list[list[int]], count: int) -> bytes:
    # count 0 is empty. The asm one-byte placeholder is not a bundle byte.
    out = bytearray()
    for col in cols:
        out.extend((v & 255) for v in col[:count])
    return bytes(out)


def map_bundle(
    geo: bytes,
    missions: bytes,
    tiles: list[int],
    paper: list[int],
) -> bytes:
    # Chunk flag bit0 would mean LZSS. Planes stay raw, so every flag is 0.
    # Geometry's dest_len is the 870-byte home, not the tight source.
    plane_tiles = bytes(t & 255 for t in tiles)
    plane_paper = bytes(p & 255 for p in paper)
    chunks = (
        (1, 0, 0xB900, 870, geo),
        (2, 0, 0x0900, len(missions), missions),
        (3, 0, 0xA000, 3200, plane_tiles),
        (4, 0, 0xAC80, 3200, plane_paper),
    )
    entries = bytearray()
    bodies = bytearray()
    offset = 26 + 10 * len(chunks)
    for cid, flags, dest, dest_len, body in chunks:
        entries += struct.pack(
            "<BBHHHH", cid, flags, offset, len(body), dest, dest_len
        )
        bodies += body
        offset += len(body)
    payload = bytearray(b"FMAP")
    payload += bytes((1, 0x01, 1, 0))
    payload += bytes([0xA0]) * 16
    payload += bytes((0, len(chunks)))
    payload += entries
    payload += bodies
    return struct.pack("<H", 0xA000) + bytes(payload)


def homes_text() -> str:
    """Fixed rom_* / sc_* equates. Readers stay on these names."""
    lines = ["; Generated by tools/gen_c64.py — do not edit.\n"]

    def eq(name: str, addr: int) -> None:
        lines.append(f"{name} = ${addr:04X}\n")

    eq("rom_tiles", 0xA000)
    eq("rom_paper", 0xAC80)
    geo = 0xB900
    for i, name in enumerate((
        "rom_map_w", "rom_map_h", "rom_room_count", "rom_cover_count",
        "rom_portal_count", "rom_scout_count",
    )):
        eq(name, geo + i)
    rooms = (
        "rom_room_x0", "rom_room_y0", "rom_room_w", "rom_room_h",
        "rom_room_colour", "rom_room_cover_base", "rom_room_cover_count",
        "rom_room_scout_base", "rom_room_scout_count", "rom_room_axis",
        "rom_room_cover_lo", "rom_room_cover_none", "rom_room_cover_hi",
    )
    base = geo + 6
    for i, name in enumerate(rooms):
        eq(name, base + 16 * i)
    base += 13 * 16
    for i, name in enumerate((
        "rom_cover_x", "rom_cover_y", "rom_cover_grade", "rom_cover_facing",
    )):
        eq(name, base + 128 * i)
    base += 4 * 128
    for i, name in enumerate(("rom_portal_x", "rom_portal_y")):
        eq(name, base + 24 * i)
    base += 2 * 24
    for i, name in enumerate(("rom_scout_x", "rom_scout_y", "rom_scout_facing")):
        eq(name, base + 32 * i)
    act = 0xBC80
    for i, name in enumerate(("rom_play_x", "rom_play_y", "rom_play_w", "rom_play_h")):
        eq(name, act + i)
    eq("rom_cam_x", act + 4)
    eq("rom_cam_y", act + 5)
    eq("rom_spawn_count", act + 6)
    for i, name in enumerate(("rom_spawn_x", "rom_spawn_y", "rom_spawn_tile")):
        eq(name, act + 7 + 32 * i)
    for i, name in enumerate((
        "sc_op_count", "sc_beat_count", "sc_watch_count",
        "sc_pred_count", "sc_where_count", "sc_spawn_count",
    )):
        eq(name, act + 103 + i)
    eq("sc_start_spawn_room", act + 109)
    eq("sc_start_beat", act + 110)
    for i, name in enumerate((
        "sc_player_grenades", "sc_player_grenade_wait",
        "sc_enemy_grenades", "sc_enemy_grenade_wait",
    )):
        eq(name, act + 111 + i)
    for i, name in enumerate(("sc_op_code", "sc_op_a", "sc_op_b", "sc_op_c")):
        eq(name, act + 115 + 64 * i)
    eq("sc_beat_pc", act + 371)
    for i, name in enumerate((
        "sc_watch_pred0", "sc_watch_pred1", "sc_watch_op",
        "sc_watch_arg", "sc_watch_flags",
    )):
        eq(name, act + 383 + 8 * i)
    for i, name in enumerate(("sc_pred_kind", "sc_pred_who", "sc_pred_a", "sc_pred_b")):
        eq(name, act + 423 + 32 * i)
    for i, name in enumerate(("sc_where_kind", "sc_where_a", "sc_where_b")):
        eq(name, act + 551 + 16 * i)
    for i, name in enumerate((
        "sc_spawn_n", "sc_spawn_letter", "sc_spawn_room",
        "sc_spawn_batch", "sc_spawn_period",
    )):
        eq(name, act + 599 + 8 * i)
    return "".join(lines)


def _compute() -> dict:
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
        stems, spawn_layer = gen_sdl.spawn_layers_for_map(missions, tmx.stem)
        name, width, height, planes, firstgid = gen_sdl.load_tmx(
            tmx, count, empty_tile, stems
        )
        maps.append(
            gen_sdl.compile_map(
                name, width, height, planes, firstgid, empty_tile,
                chip_to_preset, class_table, classes, spawn_layer,
            )
        )
    by_name = {m.name: m for m in maps}
    mission = next(m for m in missions if m[0] == "farm_mission" or m[2] == 40)
    # missions are (name, map, x, y, w, h, script, cam_x, cam_y).
    farm_m = None
    for m in missions:
        if m[1] == "farm":
            farm_m = m
            break
    if farm_m is None:
        raise gen_sdl.Error("no farm mission")
    _mname, map_name, px, py, pw, ph, stem, cam_x, cam_y = farm_m
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
    if len(compiled.scout_x) > 32:
        raise gen_sdl.Error(
            f"SCOUT_MAX is 32, got {len(compiled.scout_x)} scouts"
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
    room_n = len(rooms)
    cover_n = len(compiled.cover_x)
    portal_n = len(compiled.portal_x)
    scout_n = len(compiled.scout_x)
    spawn_n = len(compiled.spawn_x)
    # One column list. farm.asm gets the pad or the empty placeholder;
    # the bundle gets the tight prefix of the same list.
    room_fields = (
        ("rom_room_x0", [r.x0 for r in rooms]),
        ("rom_room_y0", [r.y0 for r in rooms]),
        ("rom_room_w", [r.w for r in rooms]),
        ("rom_room_h", [r.h for r in rooms]),
        ("rom_room_colour", [r.colour for r in rooms]),
        ("rom_room_cover_base", compiled.room_cover_base),
        ("rom_room_cover_count", compiled.room_cover_count),
        ("rom_room_scout_base", compiled.room_scout_base),
        ("rom_room_scout_count", compiled.room_scout_count),
        ("rom_room_axis", compiled.room_axis),
        ("rom_room_cover_lo", compiled.room_cover_lo),
        ("rom_room_cover_none", compiled.room_cover_none),
        ("rom_room_cover_hi", compiled.room_cover_hi),
    )
    cover_fields = (
        ("rom_cover_x", compiled.cover_x),
        ("rom_cover_y", compiled.cover_y),
        ("rom_cover_grade", compiled.cover_grade),
        ("rom_cover_facing", compiled.cover_facing),
    )
    portal_fields = (
        ("rom_portal_x", compiled.portal_x),
        ("rom_portal_y", compiled.portal_y),
    )
    scout_fields = (
        ("rom_scout_x", compiled.scout_x),
        ("rom_scout_y", compiled.scout_y),
        ("rom_scout_facing", compiled.scout_facing),
    )
    spawn_fields = (
        ("rom_spawn_x", compiled.spawn_x),
        ("rom_spawn_y", compiled.spawn_y),
        ("rom_spawn_tile", compiled.spawn_tile),
    )
    script_scalars = (
        ("sc_op_count", script.op_count),
        ("sc_beat_count", script.beat_count),
        ("sc_watch_count", script.watch_count),
        ("sc_pred_count", script.pred_count),
        ("sc_where_count", script.where_count),
        ("sc_spawn_count", script.spawn_tmpl_count),
        ("sc_start_spawn_room", script.start_spawn_room),
        ("sc_start_beat", script.start_beat),
        ("sc_player_grenades", script.player_grenades),
        ("sc_player_grenade_wait", script.player_grenade_wait),
        ("sc_enemy_grenades", script.enemy_grenades),
        ("sc_enemy_grenade_wait", script.enemy_grenade_wait),
    )
    script_groups = (
        (script.op_count, (
            ("sc_op_code", script.op_code),
            ("sc_op_a", script.op_a),
            ("sc_op_b", script.op_b),
            ("sc_op_c", script.op_c),
        )),
        (script.beat_count, (
            ("sc_beat_pc", script.beat_pc),
        )),
        (script.watch_count, (
            ("sc_watch_pred0", script.watch_pred0),
            ("sc_watch_pred1", script.watch_pred1),
            ("sc_watch_op", script.watch_op),
            ("sc_watch_arg", script.watch_arg),
            ("sc_watch_flags", script.watch_flags),
        )),
        (script.pred_count, (
            ("sc_pred_kind", script.pred_kind),
            ("sc_pred_who", script.pred_who),
            ("sc_pred_a", script.pred_a),
            ("sc_pred_b", script.pred_b),
        )),
        (script.where_count, (
            ("sc_where_kind", script.where_kind),
            ("sc_where_a", script.where_a),
            ("sc_where_b", script.where_b),
        )),
        (script.spawn_tmpl_count, (
            ("sc_spawn_n", script.spawn_n),
            ("sc_spawn_letter", script.spawn_letter),
            ("sc_spawn_room", script.spawn_room),
            ("sc_spawn_batch", script.spawn_batch),
            ("sc_spawn_period", script.spawn_period),
        )),
    )
    force_bytes = [force_colour(t) for t in tiles]
    labels: dict[str, list[int]] = {
        "rom_map_w": [compiled.width & 255],
        "rom_map_h": [compiled.height & 255],
        "rom_play_x": [px & 255],
        "rom_play_y": [py & 255],
        "rom_play_w": [pw & 255],
        "rom_play_h": [ph & 255],
        "rom_cam_x": [cam_x & 255],
        "rom_cam_y": [cam_y & 255],
        "rom_room_count": [room_n & 255],
        "rom_cover_count": [cover_n & 255],
        "rom_portal_count": [portal_n & 255],
        "rom_scout_count": [scout_n & 255],
        "rom_spawn_count": [spawn_n & 255],
        "rom_tiles": [t & 255 for t in compiled.tiles],
        "rom_paper": [p & 255 for p in paper],
        "rom_tile_class": [c & 255 for c in class_table],
        "rom_tile_force": [b & 255 for b in force_bytes],
    }
    for name, col in room_fields:
        labels[name] = pad(col, 16)
    for fields in (cover_fields, portal_fields, scout_fields, spawn_fields):
        for name, col in fields:
            labels[name] = [v & 255 for v in col] or [0]
    for name, value in script_scalars:
        labels[name] = [value & 255]
    for _count, fields in script_groups:
        for name, col in fields:
            labels[name] = [v & 255 for v in col] or [0]
    geo = bytes((
        compiled.width & 255,
        compiled.height & 255,
        room_n & 255,
        cover_n & 255,
        portal_n & 255,
        scout_n & 255,
    ))
    geo += _columns([col for _, col in room_fields], room_n)
    geo += _columns([col for _, col in cover_fields], cover_n)
    geo += _columns([col for _, col in portal_fields], portal_n)
    geo += _columns([col for _, col in scout_fields], scout_n)
    body = bytearray((
        px & 255,
        py & 255,
        pw & 255,
        ph & 255,
        cam_x & 255,
        cam_y & 255,
        spawn_n & 255,
    ))
    body += _columns([col for _, col in spawn_fields], spawn_n)
    body += bytes(value & 255 for _, value in script_scalars)
    for count, fields in script_groups:
        body += _columns([col for _, col in fields], count)
    try:
        stem_b = stem.encode("ascii")
    except UnicodeEncodeError as exc:
        raise gen_sdl.Error(f"script stem {stem!r} is not ASCII") from exc
    if not 1 <= len(stem_b) <= 15:
        raise gen_sdl.Error(
            f"script stem {stem!r} is {len(stem_b)} bytes; bundle stems are 1..15"
        )
    missions_chunk = (
        bytes((1, len(stem_b)))
        + stem_b
        + struct.pack("<H", len(body))
        + bytes(body)
    )
    summary = (
        f"gen_c64: {compiled.name} {compiled.width}x{compiled.height} "
        f"play {px},{py},{pw},{ph} rooms {len(rooms)} "
        f"script {script.op_count} ops -> {out}"
    )
    return {
        "root": root,
        "out": out,
        "class_table": class_table,
        "force": force_bytes,
        "labels": labels,
        "geo": geo,
        "missions": missions_chunk,
        "tiles": compiled.tiles,
        "paper": paper,
        "summary": summary,
    }


def linked_labels() -> dict[str, list[int]]:
    """Padded tables the old farm.asm labels held. The bundle uses the tight form."""
    return _compute()["labels"]


def build() -> int:
    data = _compute()
    root = data["root"]
    out = data["out"]
    tileset = (
        "; Generated by tools/gen_c64.py — do not edit.\n"
        + emit_bytes("rom_tile_class", data["class_table"])
        + emit_bytes("rom_tile_force", data["force"])
    )
    (out / "tileset.asm").write_text(tileset, encoding="utf-8")
    (out / "homes.inc").write_text(homes_text(), encoding="utf-8")
    farm_asm = out / "farm.asm"
    if farm_asm.exists():
        farm_asm.unlink()
    bundle_path = root / "build" / "c64" / "farm.prg"
    bundle_path.parent.mkdir(parents=True, exist_ok=True)
    blob = map_bundle(data["geo"], data["missions"], data["tiles"], data["paper"])
    bundle_path.write_bytes(blob)
    print(data["summary"])
    print(f"gen_c64: {bundle_path.relative_to(root)} {len(blob)} bytes")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(build())
    except gen_sdl.Error as exc:
        print(f"gen_c64: {exc}", file=sys.stderr)
        raise SystemExit(1)
