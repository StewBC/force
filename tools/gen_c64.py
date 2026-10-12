#!/usr/bin/env python3
"""Emit the C64 charset, tile class/force, home equates, and the farm bundle.

Playfield characters are multicolour: %00 red, %01 grey, %10 light blue,
%11 per-cell paper. The hires font sits at chars 128-223 (ASCII 32-127).
Chars 224-255 are scratch for soldier composites, filled at runtime.
"""

from __future__ import annotations

from collections import deque
import re
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import gen_sdl  # noqa: E402
import lzss  # noqa: E402
from c64_routes import bridge_variants, ROUTE_PORTALS_HOME, ROUTE_DOORS_HOME

INK_RED = 2
INK_GREY = 11
INK_BLUE = 14
FONT_BASE = 128


def bind_deck_components(
    width: int, height: int, tiles: list[int], paper: list[int],
    tile_class: list[int], blocked_classes: set[int],
    deck_x: list[int], deck_y: list[int],
) -> list[int]:
    """Bake dry banks into paper bits 4-7; water keeps id zero.

    Match deck.asm's via_stand and N/E/S/W seed order. Only components
    touching a deck are needed. Unlike the old 159-cell runtime ring,
    the build-time queue labels the entire bank without dropping cells.
    """
    result = [p & 0x0F for p in paper]
    decks = set(zip(deck_x, deck_y))
    directions = ((0, -1), (1, 0), (0, 1), (-1, 0))

    def dry(x: int, y: int) -> bool:
        if not (0 <= x < width and 0 <= y < height):
            return False
        i = y * width + x
        if result[i] & 0x0F == 6 or (x, y) in decks:
            return False
        tile = tiles[i]
        return tile == 81 or (tile != 80 and tile_class[tile] not in blocked_classes)

    component = 0
    for x, y in zip(deck_x, deck_y):
        for dx, dy in directions:
            sx, sy = x + dx, y + dy
            if not dry(sx, sy) or result[sy * width + sx] & 0xF0:
                continue
            component += 1
            if component > 15:
                raise gen_sdl.Error("deck banks exceed the 15 paper component IDs")
            result[sy * width + sx] |= component << 4
            queue = deque([(sx, sy)])
            while queue:
                cx, cy = queue.popleft()
                for nx, ny in ((cx + dx, cy + dy) for dx, dy in directions):
                    if dry(nx, ny) and not result[ny * width + nx] & 0xF0:
                        result[ny * width + nx] |= component << 4
                        queue.append((nx, ny))
    return result


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


def mc_row_deck(pair_row: list[int]) -> int:
    """Planks are grey. Clear pixels stay paper so the river colour shows.

    Cyan and brown are not shared multicolour inks, and the cell paper is
    the water. Left as paper, the whole glyph paints as more water.
    """
    byte = 0
    for px in range(0, 8, 2):
        bits = 0b11 if pair_row[px] == 0 else 0b01
        byte = ((byte << 2) | bits) & 255
    return byte


def check_playfield_pixels(tiles: list[list[list[int]]]) -> None:
    """2-wide pairs on playfield tiles. Editor ids skip this and the ink read."""
    for tid, tile in enumerate(tiles):
        if tid >= gen_sdl.RUNTIME_TILES:
            continue
        for ry, row in enumerate(tile):
            for px in range(0, 8, 2):
                if row[px] != row[px + 1]:
                    raise gen_sdl.Error(f"tile {tid} row {ry} is not 2-wide")


def force_colour(tile: list[list[int]]) -> int:
    """$FF means the cell paper comes from the colour layer.

    This is the ink read: clear, red, grey, and light blue are glyph ink,
    and any other index is paper. Editor tiles are not passed in.
    """
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


def stored_plane(raw: bytes) -> tuple[int, bytes]:
    """Flag bit 0 and the stored bytes. Set only when LZSS is shorter than the tight plane."""
    comp = lzss.encode(bytes(raw))
    if len(comp) < len(raw):
        return 1, comp
    return 0, bytes(raw)


# The selected record and banked collection have separate layout budgets.
from c64_layout import COMPAT, start, capacity, generate as generate_layout
import c64_missions
DECK_ORG = start("deck")
MISSION_SET_MAX = capacity("mission")


def pack_mission_body(
    px: int,
    py: int,
    pw: int,
    ph: int,
    cam_x: int,
    cam_y: int,
    spawn_x: list[int],
    spawn_y: list[int],
    spawn_tile: list[int],
    script: gen_sdl.CompiledScript,
) -> bytes:
    """Tight active-mission bytes. The scatter target is $BC80."""
    spawn_n = len(spawn_x)
    script_scalars = (
        script.op_count,
        script.beat_count,
        script.watch_count,
        script.pred_count,
        script.where_count,
        script.spawn_tmpl_count,
        script.start_spawn_room,
        script.start_beat,
        script.player_grenades,
        script.player_grenade_wait,
        script.enemy_grenades,
        script.enemy_grenade_wait,
        script.deck_cost,
    )
    script_groups = (
        (script.op_count, (
            script.op_code, script.op_a, script.op_b, script.op_c,
        )),
        (script.beat_count, (script.beat_pc,)),
        (script.watch_count, (
            script.watch_pred0, script.watch_pred1, script.watch_op,
            script.watch_arg, script.watch_flags,
        )),
        (script.pred_count, (
            script.pred_kind, script.pred_who, script.pred_a, script.pred_b,
        )),
        (script.where_count, (
            script.where_kind, script.where_a, script.where_b,
        )),
        (script.spawn_tmpl_count, (
            script.spawn_n, script.spawn_letter, script.spawn_room,
            script.spawn_batch, script.spawn_period,
        )),
    )
    body = bytearray((
        px & 255,
        py & 255,
        pw & 255,
        ph & 255,
        cam_x & 255,
        cam_y & 255,
        spawn_n & 255,
    ))
    body += _columns([spawn_x, spawn_y, spawn_tile], spawn_n)
    body += bytes(value & 255 for value in script_scalars)
    for count, cols in script_groups:
        body += _columns(list(cols), count)
    return bytes(body)


def pack_mission_set(parts: list[tuple[str, bytes]],
                     scripts: dict[str, gen_sdl.CompiledScript] | None = None) -> bytes:
    """Banked collection of independently encoded self-contained records."""
    try:
        return c64_missions.pack(parts, scripts)
    except ValueError as exc:
        raise gen_sdl.Error(str(exc)) from exc


def map_bundle(
    geo: bytes,
    missions: bytes,
    tiles: list[int],
    paper: list[int],
    routes: bytes | None = None,
    route_program: bytes | None = None,
) -> bytes:
    # Geometry and the independently encoded mission collection stay raw
    # in this container. A plane flag is set only when LZSS is strictly
    # smaller than the tight plane. The capacity field stays 3200.
    # Geometry's dest_len is the 870-byte home, not the tight source.
    plane_tiles = bytes(t & 255 for t in tiles)
    plane_paper = bytes(p & 255 for p in paper)
    tile_flag, tile_body = stored_plane(plane_tiles)
    paper_flag, paper_body = stored_plane(plane_paper)
    kind = lambda flag: "lzss" if flag else "raw"
    print(f"gen_c64: tiles {kind(tile_flag)} {len(tile_body)}")
    print(f"gen_c64: paper {kind(paper_flag)} {len(paper_body)}")
    chunks = (
        (1, 0, 0xB900, 870, geo),
        (2, 0, start("collection"), len(missions), missions),
        (3, tile_flag, 0xA000, 3200, tile_body),
        (4, paper_flag, 0xAC80, 3200, paper_body),
    )
    if routes is not None:
        if len(routes) != 818:
            raise gen_sdl.Error("initial routing image must be 818 bytes")
        chunks += ((5, 0, 0x1C00, 818, routes),)
    if route_program is not None:
        if routes is None or len(route_program) != 256:
            raise gen_sdl.Error("routing program requires initial tables and exactly 256 bytes")
        chunks += ((6, 0, 0xBF00, 256, route_program),)
    entries = bytearray()
    bodies = bytearray()
    offset = 26 + 10 * len(chunks)
    for cid, flags, dest, dest_len, body in chunks:
        entries += struct.pack(
            "<BBHHHH", cid, flags, offset, len(body), dest, dest_len
        )
        bodies += body
        offset += len(body)
    if routes is not None and 0xA000 + offset > 0xB900:
        raise gen_sdl.Error("routing bundle must end below geometry RAM at $B900")
    payload = bytearray(b"FMAP")
    # Byte 6 is mission_count. The set's first byte is the same count.
    payload += bytes((3 if route_program is not None else 1, 0x01, missions[0], 0))
    payload += struct.pack("<H", COMPAT) + bytes(14)
    payload += bytes((0, len(chunks)))
    payload += entries
    payload += bodies
    payload[12:14] = struct.pack("<H", len(payload))
    payload[10] = 0
    payload[10] = c64_missions.checksum(payload)
    return struct.pack("<H", 0xA000) + bytes(payload)


def homes_text() -> str:
    """Fixed rom_* / sc_* equates. Readers stay on these names."""
    lines = ["; Generated by tools/gen_c64.py — do not edit.\n"]

    def eq(name: str, addr: int) -> None:
        lines.append(f"{name} = ${addr:04X}\n")

    eq("rom_tiles", start("tiles"))
    eq("rom_paper", start("paper"))
    geo = start("geometry")
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
    act = start("active")
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
    eq("sc_deck_cost", act + 115)
    for i, name in enumerate(("sc_op_code", "sc_op_a", "sc_op_b", "sc_op_c")):
        eq(name, act + 116 + 64 * i)
    eq("sc_beat_pc", act + 372)
    for i, name in enumerate((
        "sc_watch_pred0", "sc_watch_pred1", "sc_watch_op",
        "sc_watch_arg", "sc_watch_flags",
    )):
        eq(name, act + 384 + 8 * i)
    for i, name in enumerate(("sc_pred_kind", "sc_pred_who", "sc_pred_a", "sc_pred_b")):
        eq(name, act + 424 + 32 * i)
    for i, name in enumerate(("sc_where_kind", "sc_where_a", "sc_where_b")):
        eq(name, act + 552 + 16 * i)
    for i, name in enumerate((
        "sc_spawn_n", "sc_spawn_letter", "sc_spawn_room",
        "sc_spawn_batch", "sc_spawn_period",
    )):
        eq(name, act + 600 + 8 * i)
    return "".join(lines)


def _compute(stem: str | None = None) -> dict:
    root = Path(__file__).resolve().parents[1]
    out = root / "src" / "c64" / "generated"
    out.mkdir(parents=True, exist_ok=True)

    name_per_id, classes, empty_tile = gen_sdl.load_tile_desc(root / "assets" / "tiles.txt")
    missions = gen_sdl.load_missions(root / "assets" / "missions.txt")
    chip_to_preset = gen_sdl.load_properties_txt(root / "assets" / "properties.txt")
    tile_w, tile_h, columns, count, png = gen_sdl.load_tsx(root / "assets" / "maps" / "tiles.tsx")
    if tile_w != 8 or tile_h != 8 or count < gen_sdl.RUNTIME_TILES:
        raise gen_sdl.Error(
            f"tileset must be at least {gen_sdl.RUNTIME_TILES} of 8x8, "
            f"got {count} {tile_w}x{tile_h}"
        )
    _w, _h, rows = load_indices(png)
    need_h = ((count + columns - 1) // columns) * 8
    if _h < need_h or _w < columns * 8:
        raise gen_sdl.Error(
            f"{png.name}: image {_w}x{_h} smaller than {count} tiles"
        )
    tiles = slice_index_tiles(rows, columns, count)
    check_playfield_pixels(tiles)

    class_table = [classes["empty"]] * count
    for tid in range(count):
        if tid < len(name_per_id) and name_per_id[tid] is not None:
            class_table[tid] = classes[name_per_id[tid]]
    # Chars 128–223 are the font and 224–255 are soldier composites.
    # Editor tiles never enter those slots or these two tables.
    play_tiles = tiles[: gen_sdl.RUNTIME_TILES]
    play_class = class_table[: gen_sdl.RUNTIME_TILES]

    # One cropped map per catalog stem. Play rect is the whole file.
    if stem is None:
        stem = missions[0][0]
    row = next((m for m in missions if m[0] == stem), None)
    if row is None:
        raise gen_sdl.Error(f"stem '{stem}' is not in the catalog")
    stem, biome, cam_x, cam_y, _title = row
    tmx_path = root / "assets" / "maps" / f"{stem}.tmx"
    if not tmx_path.is_file():
        raise gen_sdl.Error(f"{stem}: missing {tmx_path}")
    name, width, height, planes, firstgid = gen_sdl.load_tmx(
        tmx_path, count, empty_tile
    )
    if name != stem:
        raise gen_sdl.Error(
            f"{tmx_path}: file stem is '{name}', catalog stem is '{stem}'"
        )
    compiled = gen_sdl.compile_map(
        name, width, height, planes, firstgid, empty_tile,
        chip_to_preset, class_table, classes,
    )
    px, py, pw, ph, cam_x, cam_y = gen_sdl.play_bounds(
        compiled.width, compiled.height, cam_x, cam_y
    )
    # MAP_W is the portal-bitset stride, not the only legal width.
    if not 1 <= compiled.width <= 80:
        raise gen_sdl.Error(
            f"{compiled.name}: width {compiled.width} is outside 1..80"
        )
    if not 1 <= compiled.height <= 40:
        raise gen_sdl.Error(
            f"{compiled.name}: height {compiled.height} is outside 1..40"
        )
    if compiled.width * compiled.height > 3200:
        raise gen_sdl.Error(
            f"{compiled.name}: {compiled.width}x{compiled.height} exceeds 3200"
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
    # One record. The actors layer is already on the compiled map.
    script_path = root / "assets" / "scripts" / f"{stem}.txt"
    if not script_path.is_file():
        raise gen_sdl.Error(f"{stem}: missing {script_path}")
    script = gen_sdl.compile_script(script_path, compiled)
    body = pack_mission_body(
        px, py, pw, ph, cam_x, cam_y,
        list(compiled.spawn_x), list(compiled.spawn_y),
        list(compiled.spawn_tile), script,
    )
    parts = [(stem, body)]

    charset = bytearray(256 * 8)
    for tid, tile in enumerate(play_tiles):
        encode = mc_row_deck if tid in (80, 81) else mc_row
        for ry, row in enumerate(tile):
            charset[tid * 8 + ry] = encode(row)
    for gi, glyph in enumerate(load_font(root / "src" / "sdl" / "core" / "font.c")):
        base = (FONT_BASE + gi) * 8
        for ry, b in enumerate(glyph):
            charset[base + ry] = rev8(b)
    (out / "charset.bin").write_bytes(charset)

    paper = bind_deck_components(
        compiled.width, compiled.height, compiled.tiles,
        [paper_of(tiles[tid]) for tid in compiled.color], play_class,
        {classes["walls"], classes["barriers"]},
        compiled.deck_x, compiled.deck_y,
    )
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
        ("sc_deck_cost", script.deck_cost),
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
    force_bytes = [force_colour(t) for t in play_tiles]
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
        "rom_tile_class": [c & 255 for c in play_class],
        "rom_tile_force": [b & 255 for b in force_bytes],
    }
    for name, col in room_fields:
        labels[name] = pad(col, 16)
    for fields in (cover_fields, portal_fields, scout_fields, spawn_fields):
        for name, col in fields:
            labels[name] = [v & 255 for v in col] or [0]
    for name, value in script_scalars:
        labels[name] = [value & 255]
    labels["deck_count"] = [len(compiled.deck_x) & 255]
    labels["deck_x"] = [v & 255 for v in compiled.deck_x]
    labels["deck_y"] = [v & 255 for v in compiled.deck_y]
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
    deck_n = len(compiled.deck_x)
    if deck_n != len(compiled.deck_y):
        raise gen_sdl.Error(
            f"{compiled.name} deck axes are {deck_n} and {len(compiled.deck_y)}"
        )
    if deck_n > 16:
        raise gen_sdl.Error(
            f"{compiled.name} has {deck_n} deck cells; the C64 cap is 16"
        )
    geo += bytes((deck_n & 255,))
    geo += bytes(v & 255 for v in compiled.deck_x)
    geo += bytes(v & 255 for v in compiled.deck_y)
    if len(geo) > 870:
        raise gen_sdl.Error(
            f"{compiled.name} geometry is {len(geo)} bytes; the home is 870"
        )
    summary = (
        f"gen_c64: {compiled.name} {compiled.width}x{compiled.height} "
        f"rooms {len(rooms)} missions {len(parts)} "
        f"first {stem} {script.op_count} ops -> {out}"
    )
    try:
        initial_routes, route_program, route_variants, route_bytes = bridge_variants(
            rooms, compiled.tiles, paper, compiled.width, compiled.height,
            play_class, {classes["walls"], classes["barriers"]},
            list(zip(compiled.deck_x, compiled.deck_y)),
            list(zip(compiled.portal_x, compiled.portal_y)),
        )
    except ValueError as exc:
        raise gen_sdl.Error(f"{compiled.name}: {exc}") from exc
    print(f"gen_c64: {compiled.name} routing {len(route_variants)} states, {len(set(route_variants))} variants, {route_bytes} patch bytes")
    return {
        "root": root,
        "out": out,
        "class_table": play_class,
        "force": force_bytes,
        "labels": labels,
        "geo": geo,
        "body": body,
        "script": script,
        "width": compiled.width,
        "height": compiled.height,
        "biome": biome,
        "stem": stem,
        "tiles": compiled.tiles,
        "paper": paper,
        "routes": initial_routes,
        "route_program": route_program,
        "route_variants": route_variants,
        "summary": summary,
    }


def linked_labels() -> dict[str, list[int]]:
    """Padded tables the old farm.asm labels held. The bundle uses the tight form."""
    return _compute()["labels"]


def _campaign_text(path: Path) -> str | None:
    if not path.is_file():
        return None
    data = path.read_bytes()
    # A program image starts with the two-byte load address.
    if path.suffix == ".prg" and len(data) >= 2:
        data = data[2:]
    return data.decode("utf-8", errors="replace")


# Old campaign ids, translated once. The stem in a two-token line is not one of these.
LEGACY_IDS = {
    "hold_farm": "farm",
    "cross_river": "cross",
    "hold_river": "river",
    "take_base": "base",
    "take_ridge": "ridge",
    "hold_bastogne": "bastogne",
}

INDEX_ENTRY = 49
INDEX_HEADER = 14
BIOME_CAP = 4
MISS_CAP = 16
CONTAINER_CAP = 6650
FMSN_HEADER = 12
FMSN_ENTRY = 16
FMSN_CHUNKS = 6
FCTR_HEADER = 28
FCTR_ENTRY = 20
COLLECTION_LO = 0xE600
COLLECTION_HI = 0xFFFA
PACK_HOME = 0x0900
PACK_CAP = 597
GLYPH_HOME = 0x2000
GLYPH_BYTES = 1024


def apply_glyph_install(
    ram: bytearray, biome: str, files: dict[str, bytes], resident: str
) -> str:
    """Copy a 1024-byte biome file onto $2000. A missing file leaves both.

    resident is the biome already installed, or "" while the linked charset
    is still there. The same biome does not open the file. $2400 is not written.
    """
    if not isinstance(ram, bytearray):
        raise gen_sdl.Error("glyph ram")
    if biome == resident:
        return resident
    blob = files.get(biome.upper())
    if blob is None:
        return resident
    if len(blob) != GLYPH_BYTES:
        raise gen_sdl.Error(f"glyph file length {len(blob)}")
    ram[GLYPH_HOME:GLYPH_HOME + GLYPH_BYTES] = blob
    return biome


def _canon_score(token: str) -> str | None:
    """'-' or an integer 0..99. Anything else is not a score token."""
    if token == "-":
        return "-"
    if not token.isdigit():
        return None
    value = int(token)
    if value > 99:
        return None
    return str(value)


def _apply_score_line(raw: str, found: dict[str, str]) -> None:
    """Classify one campaign line by field count.

    Exactly two tokens, second a score: stem score. `farm 7` is this arm.
    Four or more tokens: MAP INDEX SCORE OLD_ID title.... The score is the
    third token and the legacy id is the fourth. Ignore the map and the index.
    Anything else is ignored, not fatal.
    """
    parts = raw.split()
    if not parts or parts[0].startswith("#"):
        return
    if len(parts) == 2:
        score = _canon_score(parts[1])
        if score is None:
            return
        found[parts[0]] = score
        return
    if len(parts) < 4:
        return
    if _canon_score(parts[1]) is None or _canon_score(parts[2]) is None:
        return
    stem = LEGACY_IDS.get(parts[3])
    if stem is None:
        return
    found[stem] = _canon_score(parts[2])


def scores_from_text(text: str) -> dict[str, str]:
    """Stem to score string. Later lines overwrite earlier ones."""
    found: dict[str, str] = {}
    for raw in text.splitlines():
        _apply_score_line(raw, found)
    return found


def _score_by_id(path: Path) -> dict[str, str]:
    """Keep a survivor count keyed by stem when the catalog is rewritten."""
    text = _campaign_text(path)
    if text is None:
        for legacy_name in ("campaign.seq", "campaign"):
            text = _campaign_text(path.with_name(legacy_name))
            if text is not None:
                break
    if text is None:
        return {}
    return scores_from_text(text)


def _xor_bytes(data: bytes) -> int:
    total = 0
    for byte in data:
        total ^= byte
    return total


def container_overhead(n: int) -> int:
    """FCTR header plus one 20-byte directory slot per mission."""
    return FCTR_HEADER + FCTR_ENTRY * n


def ranges_intersect(start_a: int, len_a: int, start_b: int, len_b: int) -> bool:
    if len_a <= 0 or len_b <= 0:
        return False
    return start_a < start_b + len_b and start_b < start_a + len_a


def assert_chunk_placement(source: int, source_len: int, dest: int, dest_len: int) -> None:
    """A chunk home must miss the collection, and miss its own source."""
    span = COLLECTION_HI - COLLECTION_LO
    if ranges_intersect(dest, dest_len, COLLECTION_LO, span):
        raise gen_sdl.Error(
            f"destination ${dest:04X} intersects ${COLLECTION_LO:04X}–${COLLECTION_HI:04X}"
        )
    if ranges_intersect(source, source_len, dest, dest_len):
        raise gen_sdl.Error(
            f"source ${source:04X}+{source_len} intersects destination ${dest:04X}+{dest_len}"
        )


def _name16(text: str, what: str) -> bytes:
    raw = text.encode("ascii")
    if not 1 <= len(raw) <= 15:
        raise gen_sdl.Error(f"{what} {text!r} is outside 1..15")
    return raw + bytes(16 - len(raw))


def encode_fmsn(data: dict, layout_id: int | None = None) -> tuple[bytes, dict[int, int]]:
    """One mission blob. Directory order is record, geometry, routes, program, tiles, paper."""
    layout_id = COMPAT if layout_id is None else layout_id
    body = data["body"]
    expanded = c64_missions.record(body, data["script"])
    if len(expanded) > PACK_CAP:
        raise gen_sdl.Error(
            f"{data['stem']}: expanded record {len(expanded)} exceeds {PACK_CAP}"
        )
    rec_codec, rec_bytes = stored_plane(expanded)
    geo = bytes(data["geo"])
    routes = bytes(data["routes"])
    program = bytes(data["route_program"])
    if len(routes) != 818:
        raise gen_sdl.Error(f"{data['stem']}: routes are {len(routes)} bytes, not 818")
    if len(program) != 256:
        raise gen_sdl.Error(f"{data['stem']}: routing program is {len(program)} bytes, not 256")
    tight = data["width"] * data["height"]
    tiles = bytes(t & 255 for t in data["tiles"])
    paper = bytes(p & 255 for p in data["paper"])
    if len(tiles) != tight or len(paper) != tight:
        raise gen_sdl.Error(
            f"{data['stem']}: planes are {len(tiles)} and {len(paper)}, geometry is {tight}"
        )
    tile_codec, tile_bytes = stored_plane(tiles)
    paper_codec, paper_bytes = stored_plane(paper)
    specs = (
        (8, rec_codec, c64_missions.checksum(expanded), PACK_HOME, PACK_CAP, len(expanded), len(body), rec_bytes),
        (1, 0, 0, 0xB900, 870, len(geo), 0, geo),
        (5, 0, 0, 0x1C00, 818, 818, 0, routes),
        (6, 0, 0, 0xBF00, 256, 256, 0, program),
        (3, tile_codec, 0, 0xA000, 3200, tight, 0, tile_bytes),
        (4, paper_codec, 0, 0xAC80, 3200, tight, 0, paper_bytes),
    )
    if len(specs) != FMSN_CHUNKS:
        raise gen_sdl.Error("FMSN directory is six chunks")
    offset = FMSN_HEADER + FMSN_ENTRY * FMSN_CHUNKS
    entries = bytearray()
    payloads = bytearray()
    codecs: dict[int, int] = {}
    for schema, codec, xor, dest, cap, decoded, body_len, payload in specs:
        assert_chunk_placement(COLLECTION_LO, COLLECTION_HI - COLLECTION_LO, dest, cap)
        assert_chunk_placement(COLLECTION_LO, COLLECTION_HI - COLLECTION_LO, dest, decoded)
        entries += struct.pack(
            "<BBBBHHHHHH",
            schema, codec, xor & 255, 0, offset, len(payload), dest, cap, decoded, body_len,
        )
        payloads += payload
        offset += len(payload)
        codecs[schema] = codec
    blob = bytearray(b"FMSN")
    blob += bytes((1, FMSN_CHUNKS))
    blob += struct.pack("<HHH", layout_id & 0xFFFF, offset, 0)
    blob += entries + payloads
    if len(blob) != offset:
        raise gen_sdl.Error(f"{data['stem']}: FMSN extent {len(blob)} != {offset}")
    return bytes(blob), codecs


def _size_with(current: dict, blob: bytes) -> int:
    n = len(current["missions"]) + 1
    payload = sum(len(m["blob"]) for m in current["missions"]) + len(blob)
    return container_overhead(n) + payload


def _seal_container(current: dict, layout_id: int, cid: int) -> dict:
    missions = current["missions"]
    n = len(missions)
    overhead = container_overhead(n)
    payloads = b"".join(m["blob"] for m in missions)
    extent = overhead + len(payloads)
    if extent > CONTAINER_CAP:
        raise gen_sdl.Error(f"c{cid}: container {extent} exceeds {CONTAINER_CAP}")
    image = bytearray(overhead) + bytearray(payloads)
    image[0:4] = b"FCTR"
    image[4] = 1
    image[5] = n
    struct.pack_into("<H", image, 6, layout_id & 0xFFFF)
    image[8] = 0
    biome = _name16(current["biome"], "biome")
    image[9] = len(current["biome"].encode("ascii"))
    image[10:26] = biome
    struct.pack_into("<H", image, 26, extent)
    offset = overhead
    placed = []
    for i, mission in enumerate(missions):
        slot = FCTR_HEADER + FCTR_ENTRY * i
        struct.pack_into("<HH", image, slot, offset, len(mission["blob"]))
        image[slot + 4:slot + 20] = _name16(mission["stem"], "stem")
        placed.append({
            "stem": mission["stem"],
            "offset": offset,
            "stored": len(mission["blob"]),
            "blob": mission["blob"],
            "codecs": mission.get("codecs", {}),
        })
        offset += len(mission["blob"])
    image[8] = 0
    image[8] = _xor_bytes(image)
    if _xor_bytes(image) != 0:
        raise gen_sdl.Error(f"c{cid}: container xor did not close")
    return {
        "id": cid,
        "biome": current["biome"],
        "payload": bytes(image),
        "missions": placed,
        "used": extent,
        "left": CONTAINER_CAP - extent,
    }


def pack_containers(items: list, layout_id: int) -> list:
    """Catalog order. Close on a biome change, and when the next blob would pass 6650."""
    containers: list = []
    current: dict | None = None

    def close() -> None:
        nonlocal current
        if current is None:
            return
        containers.append(_seal_container(current, layout_id, len(containers)))
        current = None

    for item in items:
        blob = item["blob"]
        room = CONTAINER_CAP - container_overhead(1)
        if len(blob) > room:
            raise gen_sdl.Error(
                f"{item['stem']}: blob {len(blob)} exceeds the one-mission cap {room}"
            )
        if current is not None and item["biome"] != current["biome"]:
            close()
        if current is not None and _size_with(current, blob) > CONTAINER_CAP:
            close()
        if current is None:
            current = {"biome": item["biome"], "missions": []}
        current["missions"].append(item)
    close()
    if not containers:
        raise gen_sdl.Error("container pack produced nothing")
    return containers


def parse_fctr(payload: bytes) -> dict:
    """Host view of one FCTR image. Extent is the payload, not the .seq length."""
    if len(payload) < FCTR_HEADER or payload[:4] != b"FCTR" or payload[4] != 1:
        raise gen_sdl.Error("container magic/version")
    if _xor_bytes(payload) != 0:
        raise gen_sdl.Error("container xor")
    n = payload[5]
    extent = int.from_bytes(payload[26:28], "little")
    if not 1 <= n <= 16 or extent != len(payload) or extent > CONTAINER_CAP:
        raise gen_sdl.Error(f"container extent {extent} count {n}")
    biome = payload[10:26].split(b"\0", 1)[0].decode("ascii")
    if payload[9] != len(biome):
        raise gen_sdl.Error("container biome length")
    missions = []
    overhead = container_overhead(n)
    if overhead > extent:
        raise gen_sdl.Error("container directory overruns the image")
    for i in range(n):
        slot = FCTR_HEADER + FCTR_ENTRY * i
        offset, stored = struct.unpack_from("<HH", payload, slot)
        stem = payload[slot + 4:slot + 20].split(b"\0", 1)[0].decode("ascii")
        if offset < overhead or stored == 0 or offset + stored > extent:
            raise gen_sdl.Error(f"{stem}: blob outside the container")
        blob = payload[offset:offset + stored]
        if blob[:4] != b"FMSN":
            raise gen_sdl.Error(f"{stem}: blob is not FMSN")
        missions.append({
            "stem": stem, "offset": offset, "stored": stored, "blob": blob,
        })
    return {
        "biome": biome,
        "payload": payload,
        "missions": missions,
        "used": extent,
        "left": CONTAINER_CAP - extent,
    }


def fmsn_directory(blob: bytes) -> list[tuple]:
    """Six directory tuples: schema, codec, xor, offset, stored, dest, capacity, decoded, body."""
    if len(blob) < FMSN_HEADER + FMSN_ENTRY * FMSN_CHUNKS or blob[:4] != b"FMSN" or blob[5] != FMSN_CHUNKS:
        raise gen_sdl.Error("FMSN header")
    extent = int.from_bytes(blob[8:10], "little")
    if extent != len(blob):
        raise gen_sdl.Error("FMSN extent")
    rows = []
    for i in range(FMSN_CHUNKS):
        schema, codec, xor, _reserved, offset, stored, dest, cap, decoded, body = struct.unpack_from(
            "<BBBBHHHHHH", blob, FMSN_HEADER + FMSN_ENTRY * i
        )
        rows.append((schema, codec, xor, offset, stored, dest, cap, decoded, body))
    return rows


def pack_index(missions: list, layout_id: int, containers: list | None = None) -> bytes:
    """FIDX version 1. container_count is byte 7. Each mission row is 49 bytes.

    Count checks run before containers are required, so a 17th mission or a
    fifth biome still fails when the caller has not built a container list.
    The row is stem, title, container id, offset, stored. There is no biome byte.
    """
    if not 1 <= len(missions) <= MISS_CAP:
        raise gen_sdl.Error(f"index mission count {len(missions)} is outside 1..{MISS_CAP}")
    biomes: list[str] = []
    for _stem, biome, _cx, _cy, _title in missions:
        if biome not in biomes:
            biomes.append(biome)
    if not 1 <= len(biomes) <= BIOME_CAP:
        raise gen_sdl.Error(f"index biome count {len(biomes)} is outside 1..{BIOME_CAP}")
    if containers is None:
        raise gen_sdl.Error("index requires containers")
    if not 1 <= len(containers) <= MISS_CAP:
        raise gen_sdl.Error(
            f"index container count {len(containers)} is outside 1..{MISS_CAP}"
        )
    bio_of = {name: index for index, name in enumerate(biomes)}
    located: dict[str, tuple[int, int, int]] = {}
    biome_bytes = bytearray()
    for cid, container in enumerate(containers):
        biome = container["biome"]
        if biome not in bio_of:
            raise gen_sdl.Error(f"container biome {biome!r} is not in the catalog")
        biome_bytes.append(bio_of[biome])
        for mission in container["missions"]:
            located[mission["stem"]] = (cid, mission["offset"], mission["stored"])
    size = INDEX_HEADER + 16 * len(biomes) + len(containers) + INDEX_ENTRY * len(missions)
    body = bytearray(size)
    body[0:4] = b"FIDX"
    body[4] = 1
    body[5] = len(missions)
    body[6] = len(biomes)
    body[7] = len(containers)
    struct.pack_into("<H", body, 8, layout_id & 0xFFFF)
    body[11] = 0
    struct.pack_into("<H", body, 12, size)
    offset = INDEX_HEADER
    for name in biomes:
        body[offset:offset + 16] = _name16(name, "biome")
        offset += 16
    body[offset:offset + len(biome_bytes)] = biome_bytes
    offset += len(biome_bytes)
    for stem, _biome, _cx, _cy, title in missions:
        if stem not in located:
            raise gen_sdl.Error(f"{stem}: missing from the container directory")
        cid, blob_off, stored = located[stem]
        stem_b = stem.encode("ascii")
        title_b = title.encode("ascii")
        if not 1 <= len(stem_b) <= 15:
            raise gen_sdl.Error(f"stem {stem!r} is outside 1..15")
        if not 1 <= len(title_b) <= 27:
            raise gen_sdl.Error(f"title {title!r} is outside 1..27")
        body[offset] = len(stem_b)
        body[offset + 1:offset + 1 + len(stem_b)] = stem_b
        body[offset + 16] = len(title_b)
        body[offset + 17:offset + 17 + len(title_b)] = title_b
        body[offset + 44] = cid
        struct.pack_into("<HH", body, offset + 45, blob_off, stored)
        offset += INDEX_ENTRY
    if offset != size:
        raise gen_sdl.Error(f"index extent {offset} != {size}")
    body[10] = 0
    body[10] = _xor_bytes(body)
    if _xor_bytes(body) != 0:
        raise gen_sdl.Error("index xor did not close")
    return bytes(body)


def write_index(missions: list, build_dir: Path | None = None, containers: list | None = None) -> Path:
    """Host file build/c64/index.seq. Load address is MENU_INDEX; read_file discards it."""
    root = Path(__file__).resolve().parents[1]
    path = (build_dir or root / "build") / "c64" / "index.seq"
    path.parent.mkdir(parents=True, exist_ok=True)
    blob = pack_index(missions, COMPAT, containers)
    path.write_bytes(struct.pack("<H", start("menu_index")) + blob)
    return path


def write_campaign(root: Path, missions: list, build_dir: Path | None = None) -> Path:
    """One `stem score` line per mission. Scores already on disk stay put."""
    path = (build_dir or root / "build") / "c64" / "campaign.prg"
    path.parent.mkdir(parents=True, exist_ok=True)
    old = _score_by_id(path)
    lines = [f"{stem} {old.get(stem, '-')}\n" for stem, _biome, _cx, _cy, _title in missions]
    # Load address is unused: the menu loads with secondary address 0.
    path.write_bytes(b"\x00\x10" + "".join(lines).encode("ascii"))
    for legacy_name in ("campaign", "campaign.seq"):
        legacy = path.with_name(legacy_name)
        if legacy.is_file():
            legacy.unlink()
    return path


def _codec_text(codecs: dict[int, int]) -> str:
    names = ((8, "record"), (1, "geometry"), (5, "routes"), (6, "program"), (3, "tiles"), (4, "paper"))
    return " ".join(f"{label} {codecs[schema]}" for schema, label in names)


def build(build_dir: Path | None = None) -> int:
    root = Path(__file__).resolve().parents[1]
    generate_layout()
    missions = gen_sdl.load_missions(root / "assets" / "missions.txt")
    stems = [row[0] for row in missions]
    out = root / "src" / "c64" / "generated"
    seq_dir = (build_dir or root / "build") / "c64"
    seq_dir.mkdir(parents=True, exist_ok=True)
    for stale in ("normandy.seq", "normandy.prg"):
        (seq_dir / stale).unlink(missing_ok=True)
    items = []
    first = True
    for stem in stems:
        data = _compute(stem)
        if first:
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
            first = False
        blob, codecs = encode_fmsn(data)
        items.append({
            "stem": stem,
            "biome": data["biome"],
            "blob": blob,
            "codecs": codecs,
        })
        print(data["summary"])
    containers = pack_containers(items, COMPAT)
    produced = set()
    for container in containers:
        path = seq_dir / f"c{container['id']}.seq"
        # The load address is discarded. TRANSFER is the pass-0 buffer.
        path.write_bytes(struct.pack("<H", start("transfer")) + container["payload"])
        produced.add(path.name)
        print(
            f"gen_c64: {path.name} biome {container['biome']} "
            f"used {container['used']} left {container['left']}"
        )
        for mission in container["missions"]:
            print(
                f"gen_c64: {mission['stem']} blob {mission['stored']} "
                f"{_codec_text(mission['codecs'])} "
                f"container {container['id']} offset {mission['offset']} "
                f"used {container['used']} left {container['left']} "
                f"biome {container['biome']}"
            )
    for stem in stems:
        (seq_dir / f"{stem}.seq").unlink(missing_ok=True)
        (seq_dir / f"{stem}.prg").unlink(missing_ok=True)
    for old in seq_dir.glob("c*.seq"):
        if old.name not in produced:
            old.unlink()
    index = write_index(missions, build_dir, containers)
    print(f"gen_c64: {index} {index.stat().st_size} bytes")
    campaign = write_campaign(root, missions, build_dir)
    print(f"gen_c64: {campaign}")
    return 0


if __name__ == "__main__":
    try:
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--build-dir", type=Path)
        raise SystemExit(build(parser.parse_args().build_dir))
    except gen_sdl.Error as exc:
        print(f"gen_c64: {exc}", file=sys.stderr)
        raise SystemExit(1)
