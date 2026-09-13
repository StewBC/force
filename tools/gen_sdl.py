#!/usr/bin/env python3
"""Compile FORCE authoring files into src/sdl/generated/force_data.{h,c}."""

from __future__ import annotations

import argparse
import re
import struct
import sys
import zlib
import xml.etree.ElementTree as ET
from pathlib import Path

LAYER_NAMES = ("color", "tiles", "properties", "actors", "rooms")
META_LAYERS = frozenset(("properties", "actors", "rooms"))
TILED_FLIP = 0xE0000000
IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

FORCE_ROOM_MAX = 16
FORCE_PORTAL_MAX = 24
FORCE_COVER_MAX = 128
FORCE_COVER_PER_ROOM = 12
FORCE_SPAWN_MAX = 32
FORCE_SCOUT_MAX = 32
FORCE_SCOUT_PER_ROOM = 4
FORCE_OBJECTIVE_MAX = 8
FORCE_MINE_MAX = 32

FORCE_MAP_W_MAX = 80
FORCE_MAP_H_MAX = 50
FORCE_MAP_CELLS_MAX = 4000
assert FORCE_MAP_CELLS_MAX == FORCE_MAP_W_MAX * FORCE_MAP_H_MAX

FORCE_FACE_NONE = 0
FORCE_FACE_N = 1
FORCE_FACE_E = 2
FORCE_FACE_S = 3
FORCE_FACE_W = 4

FACE_BYTES = {
    "none": FORCE_FACE_NONE,
    "n": FORCE_FACE_N,
    "e": FORCE_FACE_E,
    "s": FORCE_FACE_S,
    "w": FORCE_FACE_W,
}


class Error(Exception):
    pass


class Preset:
    def __init__(self, kind: str, fields: dict[str, str]) -> None:
        self.kind = kind
        self.fields = fields


class Room:
    def __init__(self, x0: int, y0: int, w: int, h: int, colour: int) -> None:
        self.x0 = x0
        self.y0 = y0
        self.w = w
        self.h = h
        self.colour = colour


class CompiledMap:
    def __init__(
        self,
        name: str,
        width: int,
        height: int,
        color: list[int],
        tiles: list[int],
    ) -> None:
        self.name = name
        self.width = width
        self.height = height
        self.color = color
        self.tiles = tiles
        self.rooms: list[Room] = []
        self.room_cover_base: list[int] = []
        self.room_cover_count: list[int] = []
        self.room_scout_base: list[int] = []
        self.room_scout_count: list[int] = []
        self.cover_x: list[int] = []
        self.cover_y: list[int] = []
        self.cover_grade: list[int] = []
        self.cover_facing: list[int] = []
        self.portal_x: list[int] = []
        self.portal_y: list[int] = []
        self.scout_x: list[int] = []
        self.scout_y: list[int] = []
        self.scout_facing: list[int] = []
        self.spawn_x: list[int] = []
        self.spawn_y: list[int] = []
        self.spawn_tile: list[int] = []
        self.objective_x: list[int] = []
        self.objective_y: list[int] = []
        self.mine_x: list[int] = []
        self.mine_y: list[int] = []


def strip_comment(line: str) -> str:
    if "#" in line:
        line = line[: line.index("#")]
    return line.strip()


def parse_ranges(spec: str) -> list[int]:
    ids: list[int] = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            try:
                lo, hi = int(a.strip()), int(b.strip())
            except ValueError as exc:
                raise Error(f"bad range '{part}'") from exc
            if hi < lo:
                raise Error(f"bad range '{part}'")
            ids.extend(range(lo, hi + 1))
        else:
            try:
                ids.append(int(part))
            except ValueError as exc:
                raise Error(f"bad id '{part}'") from exc
    if not ids:
        raise Error("empty range")
    return ids


def load_tile_desc(path: Path) -> tuple[list[str | None], dict[str, int], int]:
    """Return (name_per_id, class_by_name, empty_tile_id)."""
    names: dict[int, str] = {}
    classes: dict[str, int] = {}
    text = path.read_text(encoding="utf-8")
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = strip_comment(raw)
        if not line:
            continue
        loc = f"{path}:{lineno}"
        if "=" in line and IDENT_RE.match(line.split("=", 1)[0].strip()):
            name, _, value = line.partition("=")
            name = name.strip()
            try:
                num = int(value.strip())
            except ValueError as exc:
                raise Error(f"{loc}: bad class id") from exc
            if not (0 <= num <= 255):
                raise Error(f"{loc}: class id out of range")
            if name in classes:
                raise Error(f"{loc}: class '{name}' repeated")
            if num in classes.values():
                raise Error(f"{loc}: class value {num} repeated")
            classes[name] = num
            continue
        parts = line.rsplit(None, 1)
        if len(parts) != 2:
            raise Error(f"{loc}: expected 'ranges name' or 'name=id'")
        spec, name = parts
        if not IDENT_RE.match(name):
            raise Error(f"{loc}: bad name '{name}'")
        try:
            ids = parse_ranges(spec)
        except Error as exc:
            raise Error(f"{loc}: {exc}") from exc
        for tid in ids:
            if tid < 0:
                raise Error(f"{loc}: negative tile id {tid}")
            if tid in names:
                raise Error(f"{loc}: tile {tid} already named '{names[tid]}'")
            names[tid] = name

    used = set(names.values())
    missing = used - set(classes)
    extra = set(classes) - used
    if missing:
        raise Error(f"{path}: no class id for {sorted(missing)}")
    if extra:
        raise Error(f"{path}: class id with no range: {sorted(extra)}")
    if "empty" not in classes:
        raise Error(f"{path}: missing empty= class")
    empty_ids = [tid for tid, n in names.items() if n == "empty"]
    if not empty_ids:
        raise Error(f"{path}: no tiles named empty")
    empty_tile = min(empty_ids)

    max_id = max(names) if names else -1
    name_per_id: list[str | None] = [None] * (max_id + 1)
    for tid, name in names.items():
        name_per_id[tid] = name
    return name_per_id, classes, empty_tile


def load_missions(path: Path) -> list[tuple[str, str, int, int, int, int]]:
    missions: list[tuple[str, str, int, int, int, int]] = []
    seen: set[str] = set()
    text = path.read_text(encoding="utf-8")
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = strip_comment(raw)
        if not line:
            continue
        loc = f"{path}:{lineno}"
        parts = line.split()
        if len(parts) != 3:
            raise Error(f"{loc}: expected 'name map x,y,w,h'")
        name, map_name, rect = parts
        if not IDENT_RE.match(name):
            raise Error(f"{loc}: bad mission name '{name}'")
        if not IDENT_RE.match(map_name):
            raise Error(f"{loc}: bad map name '{map_name}'")
        if name in seen:
            raise Error(f"{loc}: mission '{name}' repeated")
        nums = [p.strip() for p in rect.split(",")]
        if len(nums) != 4:
            raise Error(f"{loc}: rect must be x,y,w,h")
        try:
            x, y, w, h = (int(n) for n in nums)
        except ValueError as exc:
            raise Error(f"{loc}: bad rect") from exc
        if w <= 0 or h <= 0 or x < 0 or y < 0:
            raise Error(f"{loc}: rect must be non-negative origin and positive size")
        seen.add(name)
        missions.append((name, map_name, x, y, w, h))
    if not missions:
        raise Error(f"{path}: no missions")
    return missions


def _parse_int_token(tok: str) -> int | None:
    if re.fullmatch(r"-?\d+", tok) is None:
        return None
    return int(tok)


def _parse_preset_fields(loc: str, tokens: list[str]) -> dict[str, str]:
    fields: dict[str, str] = {}
    for tok in tokens:
        if tok.count("=") != 1:
            raise Error(f"{loc}: expected key=value, got '{tok}'")
        key, _, value = tok.partition("=")
        if not key or not value or not IDENT_RE.match(key):
            raise Error(f"{loc}: expected key=value, got '{tok}'")
        if key in fields:
            raise Error(f"{loc}: key '{key}' repeated")
        fields[key] = value
    return fields


def _validate_preset(loc: str, kind: str, fields: dict[str, str]) -> None:
    if kind == "cover":
        extra = set(fields) - {"grade", "facing"}
        if extra:
            raise Error(f"{loc}: unknown key '{sorted(extra)[0]}'")
        if "grade" not in fields:
            raise Error(f"{loc}: missing grade")
        if fields["grade"] not in {"1", "2", "3"}:
            raise Error(f"{loc}: bad grade '{fields['grade']}'")
        if "facing" not in fields:
            raise Error(f"{loc}: missing facing")
        if fields["facing"] not in {"n", "e", "s", "w", "none"}:
            raise Error(f"{loc}: bad facing '{fields['facing']}'")
        return
    if kind == "scout":
        extra = set(fields) - {"facing"}
        if extra:
            raise Error(f"{loc}: unknown key '{sorted(extra)[0]}'")
        if "facing" not in fields:
            raise Error(f"{loc}: missing facing")
        if fields["facing"] not in {"n", "e", "s", "w"}:
            raise Error(f"{loc}: bad facing '{fields['facing']}'")
        return
    if kind in ("portal", "objective", "mine"):
        if fields:
            raise Error(f"{loc}: extra key '{sorted(fields)[0]}'")
        return
    raise Error(f"{loc}: unknown kind '{kind}'")


def load_properties_txt(path: Path) -> dict[int, Preset]:
    """Return chip id → preset. File is required; empty vocabulary is allowed."""
    try:
        shown = path.resolve().relative_to(Path(__file__).resolve().parents[1]).as_posix()
    except ValueError:
        shown = str(path)
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise Error(f"{shown}: not found") from exc

    chips: dict[int, str] = {}
    chip_loc: dict[int, str] = {}
    presets: dict[str, Preset] = {}
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = strip_comment(raw)
        if not line:
            continue
        loc = f"{shown}:{lineno}"
        tokens = line.split()
        chip_id = _parse_int_token(tokens[0]) if "=" not in line else None
        if chip_id is not None:
            if len(tokens) != 2:
                raise Error(f"{loc}: expected chip '<id> <name>'")
            name = tokens[1]
            if not IDENT_RE.match(name):
                raise Error(f"{loc}: bad name '{name}'")
            if chip_id == 112:
                raise Error(f"{loc}: chip id 112 is knockout, never a chip")
            if chip_id < 113 or chip_id > 127:
                raise Error(f"{loc}: chip id {chip_id} out of range")
            if chip_id in chips:
                raise Error(f"{loc}: chip {chip_id} repeated")
            chips[chip_id] = name
            chip_loc[chip_id] = loc
            continue
        left, sep, right = line.partition("=")
        if sep and IDENT_RE.match(left.strip()):
            name = left.strip()
            rhs = right.split()
            if not rhs:
                raise Error(f"{loc}: expected kind")
            kind = rhs[0]
            fields = _parse_preset_fields(loc, rhs[1:])
            _validate_preset(loc, kind, fields)
            if name in presets:
                raise Error(f"{loc}: preset '{name}' repeated")
            presets[name] = Preset(kind, fields)
            continue
        raise Error(
            f"{loc}: expected chip '<id> <name>' or preset '<name>=<kind> …'"
        )

    chip_to_preset: dict[int, Preset] = {}
    for chip_id, name in chips.items():
        if name not in presets:
            raise Error(
                f"{chip_loc[chip_id]}: chip {chip_id} names undefined preset '{name}'"
            )
        chip_to_preset[chip_id] = presets[name]
    return chip_to_preset


def paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def load_png_rgba(path: Path) -> tuple[int, int, list[list[tuple[int, int, int, int]]]]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise Error(f"{path}: not a PNG")
    off = 8
    chunks: dict[bytes, bytes] = {}
    idats: list[bytes] = []
    while off + 12 <= len(data):
        length = struct.unpack(">I", data[off : off + 4])[0]
        ctype = data[off + 4 : off + 8]
        payload = data[off + 8 : off + 8 + length]
        off += 12 + length
        if ctype == b"IDAT":
            idats.append(payload)
        elif ctype == b"IEND":
            break
        elif ctype not in chunks:
            chunks[ctype] = payload
    if b"IHDR" not in chunks or not idats:
        raise Error(f"{path}: missing IHDR/IDAT")
    width, height, bit, color, comp, filt, inter = struct.unpack(">IIBBBBB", chunks[b"IHDR"])
    if bit != 8 or comp != 0 or filt != 0 or inter != 0:
        raise Error(f"{path}: need 8-bit non-interlaced PNG")
    raw = zlib.decompress(b"".join(idats))

    if color == 2:
        ch = 3
    elif color == 6:
        ch = 4
    elif color == 3:
        ch = 1
    else:
        raise Error(f"{path}: unsupported PNG color type {color}")

    stride = width * ch
    rows: list[bytes] = []
    prev = bytearray(stride)
    i = 0
    for _y in range(height):
        if i + 1 + stride > len(raw):
            raise Error(f"{path}: truncated PNG")
        ft = raw[i]
        src = raw[i + 1 : i + 1 + stride]
        i += 1 + stride
        out = bytearray(stride)
        for x in range(stride):
            left = out[x - ch] if x >= ch else 0
            up = prev[x]
            ul = prev[x - ch] if x >= ch else 0
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
                out[x] = (v + paeth(left, up, ul)) & 255
            else:
                raise Error(f"{path}: bad PNG filter {ft}")
        rows.append(bytes(out))
        prev = out

    pixels: list[list[tuple[int, int, int, int]]] = []
    if color == 3:
        pal = chunks.get(b"PLTE")
        if pal is None or len(pal) % 3:
            raise Error(f"{path}: bad PLTE")
        trns = chunks.get(b"tRNS", b"")
        table: list[tuple[int, int, int, int]] = []
        for pi in range(len(pal) // 3):
            r, g, b = pal[pi * 3 : pi * 3 + 3]
            a = trns[pi] if pi < len(trns) else 255
            table.append((r, g, b, a))
        for row in rows:
            pixels.append([table[p] if p < len(table) else (0, 0, 0, 0) for p in row])
    elif color == 2:
        for row in rows:
            line = []
            for x in range(0, stride, 3):
                line.append((row[x], row[x + 1], row[x + 2], 255))
            pixels.append(line)
    else:
        for row in rows:
            line = []
            for x in range(0, stride, 4):
                line.append((row[x], row[x + 1], row[x + 2], row[x + 3]))
            pixels.append(line)
    return width, height, pixels


def argb(px: tuple[int, int, int, int]) -> int:
    r, g, b, a = px
    return ((a & 255) << 24) | ((r & 255) << 16) | ((g & 255) << 8) | (b & 255)


def slice_tiles(
    pixels: list[list[tuple[int, int, int, int]]],
    tile_w: int,
    tile_h: int,
    columns: int,
    count: int,
) -> list[list[list[int]]]:
    img_h = len(pixels)
    img_w = len(pixels[0]) if img_h else 0
    rows = (count + columns - 1) // columns
    if img_w < columns * tile_w or img_h < rows * tile_h:
        raise Error("tileset image smaller than tilecount")
    tiles: list[list[list[int]]] = []
    for tid in range(count):
        tx = tid % columns
        ty = tid // columns
        tile = []
        for py in range(tile_h):
            row = []
            src = pixels[ty * tile_h + py]
            ox = tx * tile_w
            for px in range(tile_w):
                row.append(argb(src[ox + px]))
            tile.append(row)
        tiles.append(tile)
    return tiles


def verify_double_wide(tiles: list[list[list[int]]], path: Path) -> None:
    bad: list[str] = []
    for tid, tile in enumerate(tiles):
        for py, row in enumerate(tile):
            if len(row) % 2:
                raise Error(f"{path}: tile {tid} width is odd")
            for px in range(0, len(row), 2):
                if row[px] != row[px + 1]:
                    bad.append(f"tile {tid} row {py} x {px}/{px + 1}")
                    if len(bad) >= 8:
                        raise Error(
                            f"{path}: horizontal pixels are not 2-wide:\n  "
                            + "\n  ".join(bad)
                        )
    if bad:
        raise Error(f"{path}: horizontal pixels are not 2-wide:\n  " + "\n  ".join(bad))


def load_tsx(path: Path) -> tuple[int, int, int, int, Path]:
    root = ET.parse(path).getroot()
    tile_w = int(root.attrib["tilewidth"])
    tile_h = int(root.attrib["tileheight"])
    columns = int(root.attrib["columns"])
    count = int(root.attrib["tilecount"])
    image = root.find("image")
    if image is None or "source" not in image.attrib:
        raise Error(f"{path}: missing image")
    png = (path.parent / image.attrib["source"]).resolve()
    if not png.is_file():
        raise Error(f"{path}: image not found: {png}")
    return tile_w, tile_h, columns, count, png


def parse_csv_cells(text: str, width: int, height: int, loc: str) -> list[int]:
    nums = [int(tok) for tok in text.replace("\n", ",").split(",") if tok.strip()]
    if len(nums) != width * height:
        raise Error(f"{loc}: expected {width * height} cells, got {len(nums)}")
    return nums


def gid_to_tid(gid: int, firstgid: int, count: int, loc: str) -> int | None:
    if gid & TILED_FLIP:
        raise Error(f"{loc}: flipped tiles are not supported")
    if gid == 0:
        return None
    tid = gid - firstgid
    if tid < 0 or tid >= count:
        raise Error(f"{loc}: gid {gid} out of tileset")
    return tid


def load_tmx(
    path: Path, tile_count: int, empty_tile: int
) -> tuple[str, int, int, dict[str, list[int | None]], int]:
    root = ET.parse(path).getroot()
    width = int(root.attrib["width"])
    height = int(root.attrib["height"])
    ts = root.find("tileset")
    if ts is None:
        raise Error(f"{path}: no tileset")
    firstgid = int(ts.attrib["firstgid"])
    planes: dict[str, list[int | None]] = {}
    for layer in root.findall("layer"):
        name = layer.attrib.get("name", "")
        data = layer.find("data")
        if data is None or data.attrib.get("encoding") != "csv":
            raise Error(f"{path}: layer '{name}' is not CSV")
        loc = f"{path} layer '{name}'"
        gids = parse_csv_cells(data.text or "", width, height, loc)
        tids = [gid_to_tid(g, firstgid, tile_count, loc) for g in gids]
        if name in META_LAYERS:
            # Tile 0 is a legal spawn; Tiled GID 0 is absence, not tile 0.
            planes[name] = tids
        else:
            planes[name] = [empty_tile if t is None else t for t in tids]
    for name in LAYER_NAMES:
        if name not in planes:
            if name in META_LAYERS:
                planes[name] = [None] * (width * height)
            else:
                planes[name] = [empty_tile] * (width * height)
    unknown = set(planes) - set(LAYER_NAMES)
    if unknown:
        raise Error(f"{path}: unknown layer(s) {sorted(unknown)}")
    return path.stem, width, height, planes, firstgid


def painted_tile(tid: int, firstgid: int) -> str:
    return f"tile {tid} (Tiled GID {tid + firstgid})"


def absent(cell: int | None) -> bool:
    return cell is None


def knockout(cell: int | None, empty_tile: int) -> bool:
    return cell == empty_tile


def skip_meta(cell: int | None, empty_tile: int) -> bool:
    return absent(cell) or knockout(cell, empty_tile)


def rects_overlap_cells(a: Room, b: Room) -> bool:
    return (
        a.x0 < b.x0 + b.w
        and b.x0 < a.x0 + a.w
        and a.y0 < b.y0 + b.h
        and b.y0 < a.y0 + a.h
    )


def room_index_containing(rooms: list[Room], x: int, y: int) -> int | None:
    for i, room in enumerate(rooms):
        if room.x0 <= x < room.x0 + room.w and room.y0 <= y < room.y0 + room.h:
            return i
    return None


def extract_rooms(
    map_name: str,
    plane: list[int | None],
    width: int,
    height: int,
    firstgid: int,
    empty_tile: int,
) -> list[Room]:
    buckets: dict[int, list[tuple[int, int]]] = {c: [] for c in range(1, 16)}
    for y in range(height):
        for x in range(width):
            cell = plane[y * width + x]
            if skip_meta(cell, empty_tile):
                continue
            tid = cell
            if tid < 113 or tid > 127:
                raise Error(
                    f"{map_name} rooms ({x},{y}): {painted_tile(tid, firstgid)} "
                    "is not a colour chip"
                )
            buckets[tid - 112].append((x, y))
    rooms: list[Room] = []
    for colour in range(1, 16):
        cells = buckets[colour]
        if not cells:
            continue
        xs = [p[0] for p in cells]
        ys = [p[1] for p in cells]
        x0, y0 = min(xs), min(ys)
        x1, y1 = max(xs), max(ys)
        rw, rh = x1 - x0 + 1, y1 - y0 + 1
        if rw * rh != len(cells):
            raise Error(
                f"{map_name} rooms colour {colour}: not a filled rect "
                f"(bbox {x0},{y0},{rw},{rh} has {len(cells)} painted cells)"
            )
        rooms.append(Room(x0, y0, rw, rh, colour))
    if len(rooms) > FORCE_ROOM_MAX:
        raise Error(f"{map_name}: {len(rooms)} rooms > {FORCE_ROOM_MAX}")
    for i, a in enumerate(rooms):
        for b in rooms[i + 1 :]:
            if rects_overlap_cells(a, b):
                raise Error(
                    f"{map_name}: rooms colour {a.colour} and {b.colour} overlap"
                )
    return rooms


def _append_capped(
    map_name: str,
    kind: str,
    xs: list[int],
    ys: list[int],
    x: int,
    y: int,
    cap: int,
    extra: list[list[int]] | None = None,
    extra_vals: list[int] | None = None,
) -> None:
    if len(xs) >= cap:
        raise Error(f"{map_name} {kind} ({x},{y}): {len(xs) + 1} > {cap}")
    xs.append(x)
    ys.append(y)
    if extra is not None and extra_vals is not None:
        for col, val in zip(extra, extra_vals):
            col.append(val)


def extract_properties(
    compiled: CompiledMap,
    plane: list[int | None],
    firstgid: int,
    empty_tile: int,
    chip_to_preset: dict[int, Preset],
) -> None:
    map_name = compiled.name
    width, height = compiled.width, compiled.height
    rooms = compiled.rooms
    cover_by_room: list[list[tuple[int, int, int, int]]] = [[] for _ in rooms]
    scout_by_room: list[list[tuple[int, int, int]]] = [[] for _ in rooms]
    for y in range(height):
        for x in range(width):
            cell = plane[y * width + x]
            if skip_meta(cell, empty_tile):
                continue
            tid = cell
            if tid not in chip_to_preset:
                raise Error(
                    f"{map_name} properties ({x},{y}): unknown chip "
                    f"{painted_tile(tid, firstgid)}"
                )
            preset = chip_to_preset[tid]
            ri = room_index_containing(rooms, x, y)
            if ri is None:
                raise Error(f"{map_name} properties ({x},{y}): not in any room")
            if preset.kind == "cover":
                cover_by_room[ri].append(
                    (
                        x,
                        y,
                        int(preset.fields["grade"]),
                        FACE_BYTES[preset.fields["facing"]],
                    )
                )
            elif preset.kind == "scout":
                scout_by_room[ri].append(
                    (x, y, FACE_BYTES[preset.fields["facing"]])
                )
            elif preset.kind == "portal":
                _append_capped(
                    map_name,
                    "portal",
                    compiled.portal_x,
                    compiled.portal_y,
                    x,
                    y,
                    FORCE_PORTAL_MAX,
                )
            elif preset.kind == "objective":
                _append_capped(
                    map_name,
                    "objective",
                    compiled.objective_x,
                    compiled.objective_y,
                    x,
                    y,
                    FORCE_OBJECTIVE_MAX,
                )
            elif preset.kind == "mine":
                _append_capped(
                    map_name,
                    "mine",
                    compiled.mine_x,
                    compiled.mine_y,
                    x,
                    y,
                    FORCE_MINE_MAX,
                )
            else:
                raise Error(
                    f"{map_name} properties ({x},{y}): unknown kind "
                    f"'{preset.kind}'"
                )

    running_cover = 0
    running_scout = 0
    for i, room in enumerate(rooms):
        n_cover = len(cover_by_room[i])
        n_scout = len(scout_by_room[i])
        if n_cover > FORCE_COVER_PER_ROOM:
            ox, oy = cover_by_room[i][FORCE_COVER_PER_ROOM][0:2]
            raise Error(
                f"{map_name} cover ({ox},{oy}): {n_cover} in room colour "
                f"{room.colour} > {FORCE_COVER_PER_ROOM}"
            )
        if n_scout > FORCE_SCOUT_PER_ROOM:
            ox, oy = scout_by_room[i][FORCE_SCOUT_PER_ROOM][0:2]
            raise Error(
                f"{map_name} scout ({ox},{oy}): {n_scout} in room colour "
                f"{room.colour} > {FORCE_SCOUT_PER_ROOM}"
            )
        compiled.room_cover_base.append(running_cover)
        compiled.room_cover_count.append(n_cover)
        compiled.room_scout_base.append(running_scout)
        compiled.room_scout_count.append(n_scout)
        for x, y, grade, facing in cover_by_room[i]:
            _append_capped(
                map_name,
                "cover",
                compiled.cover_x,
                compiled.cover_y,
                x,
                y,
                FORCE_COVER_MAX,
                extra=[compiled.cover_grade, compiled.cover_facing],
                extra_vals=[grade, facing],
            )
        for x, y, facing in scout_by_room[i]:
            _append_capped(
                map_name,
                "scout",
                compiled.scout_x,
                compiled.scout_y,
                x,
                y,
                FORCE_SCOUT_MAX,
                extra=[compiled.scout_facing],
                extra_vals=[facing],
            )
        running_cover += n_cover
        running_scout += n_scout


def extract_spawns(
    compiled: CompiledMap,
    plane: list[int | None],
    firstgid: int,
    empty_tile: int,
    class_table: list[int],
    classes: dict[str, int],
) -> None:
    map_name = compiled.name
    width, height = compiled.width, compiled.height
    name_by_class = {num: name for name, num in classes.items()}
    allowed = {classes[n] for n in ("goodguys", "enemies") if n in classes}
    empty_class = classes["empty"]
    for y in range(height):
        for x in range(width):
            cell = plane[y * width + x]
            if skip_meta(cell, empty_tile):
                continue
            tid = cell
            cls = class_table[tid] if tid < len(class_table) else empty_class
            if cls not in allowed:
                cls_name = name_by_class.get(cls, str(cls))
                raise Error(
                    f"{map_name} actors ({x},{y}): {painted_tile(tid, firstgid)} "
                    f"class {cls_name} is not a spawn"
                )
            if room_index_containing(compiled.rooms, x, y) is None:
                raise Error(
                    f"{map_name} actors ({x},{y}): spawn outside any room"
                )
            if len(compiled.spawn_x) >= FORCE_SPAWN_MAX:
                raise Error(
                    f"{map_name}: {len(compiled.spawn_x) + 1} spawns > "
                    f"{FORCE_SPAWN_MAX}"
                )
            compiled.spawn_x.append(x)
            compiled.spawn_y.append(y)
            compiled.spawn_tile.append(tid)


def compile_map(
    name: str,
    width: int,
    height: int,
    planes: dict[str, list[int | None]],
    firstgid: int,
    empty_tile: int,
    chip_to_preset: dict[int, Preset],
    class_table: list[int],
    classes: dict[str, int],
) -> CompiledMap:
    if width > 255 or height > 255:
        raise Error(f"{name}: size {width}x{height} exceeds 255")
    if width > FORCE_MAP_W_MAX or height > FORCE_MAP_H_MAX:
        raise Error(
            f"{name}: size {width}x{height} exceeds "
            f"{FORCE_MAP_W_MAX}x{FORCE_MAP_H_MAX}"
        )
    if width * height > FORCE_MAP_CELLS_MAX:
        raise Error(
            f"{name}: {width}x{height} = {width * height} cells > "
            f"{FORCE_MAP_CELLS_MAX}"
        )
    color = [int(v) for v in planes["color"]]
    tiles = [int(v) for v in planes["tiles"]]
    compiled = CompiledMap(name, width, height, color, tiles)
    compiled.rooms = extract_rooms(
        name, planes["rooms"], width, height, firstgid, empty_tile
    )
    extract_properties(
        compiled, planes["properties"], firstgid, empty_tile, chip_to_preset
    )
    extract_spawns(
        compiled, planes["actors"], firstgid, empty_tile, class_table, classes
    )
    return compiled


def c_ident(name: str) -> str:
    return name


def emit_u32_tile(tile: list[list[int]]) -> str:
    lines = ["    {"]
    for row in tile:
        hexes = ", ".join(f"0x{p:08X}u" for p in row)
        lines.append(f"        {{{hexes}}},")
    lines.append("    },")
    return "\n".join(lines)


def emit_u8_plane(values: list[int], width: int) -> str:
    lines = []
    for y in range(0, len(values), width):
        row = values[y : y + width]
        lines.append("    " + ", ".join(f"{v:3d}" for v in row) + ",")
    return "\n".join(lines)


def emit_u8_array(sym: str, values: list[int]) -> str:
    body = ", ".join(str(v) for v in values)
    return f"static const uint8_t {sym}[{len(values)}] = {{ {body} }};\n\n"


def _c_ptr(sym: str, count: int) -> str:
    return sym if count else "NULL"


def emit_map_arrays(sym: str, compiled: CompiledMap) -> str:
    chunks: list[str] = []
    n = compiled.width * compiled.height
    chunks.append(f"static const uint8_t {sym}_color[{n}] = {{\n")
    chunks.append(emit_u8_plane(compiled.color, compiled.width))
    chunks.append("\n};\n\n")
    chunks.append(f"static const uint8_t {sym}_tiles[{n}] = {{\n")
    chunks.append(emit_u8_plane(compiled.tiles, compiled.width))
    chunks.append("\n};\n\n")

    room_count = len(compiled.rooms)
    if room_count:
        chunks.append(
            emit_u8_array(f"{sym}_room_x0", [r.x0 for r in compiled.rooms])
        )
        chunks.append(
            emit_u8_array(f"{sym}_room_y0", [r.y0 for r in compiled.rooms])
        )
        chunks.append(
            emit_u8_array(f"{sym}_room_w", [r.w for r in compiled.rooms])
        )
        chunks.append(
            emit_u8_array(f"{sym}_room_h", [r.h for r in compiled.rooms])
        )
        chunks.append(
            emit_u8_array(
                f"{sym}_room_colour", [r.colour for r in compiled.rooms]
            )
        )
        chunks.append(
            emit_u8_array(f"{sym}_room_cover_base", compiled.room_cover_base)
        )
        chunks.append(
            emit_u8_array(f"{sym}_room_cover_count", compiled.room_cover_count)
        )
        chunks.append(
            emit_u8_array(f"{sym}_room_scout_base", compiled.room_scout_base)
        )
        chunks.append(
            emit_u8_array(f"{sym}_room_scout_count", compiled.room_scout_count)
        )

    if compiled.cover_x:
        chunks.append(emit_u8_array(f"{sym}_cover_x", compiled.cover_x))
        chunks.append(emit_u8_array(f"{sym}_cover_y", compiled.cover_y))
        chunks.append(emit_u8_array(f"{sym}_cover_grade", compiled.cover_grade))
        chunks.append(
            emit_u8_array(f"{sym}_cover_facing", compiled.cover_facing)
        )
    if compiled.portal_x:
        chunks.append(emit_u8_array(f"{sym}_portal_x", compiled.portal_x))
        chunks.append(emit_u8_array(f"{sym}_portal_y", compiled.portal_y))
    if compiled.scout_x:
        chunks.append(emit_u8_array(f"{sym}_scout_x", compiled.scout_x))
        chunks.append(emit_u8_array(f"{sym}_scout_y", compiled.scout_y))
        chunks.append(
            emit_u8_array(f"{sym}_scout_facing", compiled.scout_facing)
        )
    if compiled.spawn_x:
        chunks.append(emit_u8_array(f"{sym}_spawn_x", compiled.spawn_x))
        chunks.append(emit_u8_array(f"{sym}_spawn_y", compiled.spawn_y))
        chunks.append(emit_u8_array(f"{sym}_spawn_tile", compiled.spawn_tile))
    if compiled.objective_x:
        chunks.append(
            emit_u8_array(f"{sym}_objective_x", compiled.objective_x)
        )
        chunks.append(
            emit_u8_array(f"{sym}_objective_y", compiled.objective_y)
        )
    if compiled.mine_x:
        chunks.append(emit_u8_array(f"{sym}_mine_x", compiled.mine_x))
        chunks.append(emit_u8_array(f"{sym}_mine_y", compiled.mine_y))
    return "".join(chunks)


def emit_map_init(sym: str, compiled: CompiledMap) -> str:
    room_count = len(compiled.rooms)
    cover_n = len(compiled.cover_x)
    portal_n = len(compiled.portal_x)
    scout_n = len(compiled.scout_x)
    spawn_n = len(compiled.spawn_x)
    objective_n = len(compiled.objective_x)
    mine_n = len(compiled.mine_x)
    return (
        f"const force_map {sym} = {{\n"
        f'    .name = "{compiled.name}",\n'
        f"    .width = {compiled.width},\n"
        f"    .height = {compiled.height},\n"
        f"    .color = {sym}_color,\n"
        f"    .tiles = {sym}_tiles,\n"
        f"    .room_count = {room_count},\n"
        f"    .room_x0 = {_c_ptr(f'{sym}_room_x0', room_count)},\n"
        f"    .room_y0 = {_c_ptr(f'{sym}_room_y0', room_count)},\n"
        f"    .room_w = {_c_ptr(f'{sym}_room_w', room_count)},\n"
        f"    .room_h = {_c_ptr(f'{sym}_room_h', room_count)},\n"
        f"    .room_colour = {_c_ptr(f'{sym}_room_colour', room_count)},\n"
        f"    .room_cover_base = {_c_ptr(f'{sym}_room_cover_base', room_count)},\n"
        f"    .room_cover_count = {_c_ptr(f'{sym}_room_cover_count', room_count)},\n"
        f"    .room_scout_base = {_c_ptr(f'{sym}_room_scout_base', room_count)},\n"
        f"    .room_scout_count = {_c_ptr(f'{sym}_room_scout_count', room_count)},\n"
        f"    .cover_count = {cover_n},\n"
        f"    .cover_x = {_c_ptr(f'{sym}_cover_x', cover_n)},\n"
        f"    .cover_y = {_c_ptr(f'{sym}_cover_y', cover_n)},\n"
        f"    .cover_grade = {_c_ptr(f'{sym}_cover_grade', cover_n)},\n"
        f"    .cover_facing = {_c_ptr(f'{sym}_cover_facing', cover_n)},\n"
        f"    .portal_count = {portal_n},\n"
        f"    .portal_x = {_c_ptr(f'{sym}_portal_x', portal_n)},\n"
        f"    .portal_y = {_c_ptr(f'{sym}_portal_y', portal_n)},\n"
        f"    .scout_count = {scout_n},\n"
        f"    .scout_x = {_c_ptr(f'{sym}_scout_x', scout_n)},\n"
        f"    .scout_y = {_c_ptr(f'{sym}_scout_y', scout_n)},\n"
        f"    .scout_facing = {_c_ptr(f'{sym}_scout_facing', scout_n)},\n"
        f"    .spawn_count = {spawn_n},\n"
        f"    .spawn_x = {_c_ptr(f'{sym}_spawn_x', spawn_n)},\n"
        f"    .spawn_y = {_c_ptr(f'{sym}_spawn_y', spawn_n)},\n"
        f"    .spawn_tile = {_c_ptr(f'{sym}_spawn_tile', spawn_n)},\n"
        f"    .objective_count = {objective_n},\n"
        f"    .objective_x = {_c_ptr(f'{sym}_objective_x', objective_n)},\n"
        f"    .objective_y = {_c_ptr(f'{sym}_objective_y', objective_n)},\n"
        f"    .mine_count = {mine_n},\n"
        f"    .mine_x = {_c_ptr(f'{sym}_mine_x', mine_n)},\n"
        f"    .mine_y = {_c_ptr(f'{sym}_mine_y', mine_n)},\n"
        "};\n\n"
    )


def write_generated(
    out_dir: Path,
    tiles: list[list[list[int]]],
    classes: dict[str, int],
    empty_tile: int,
    maps: list[CompiledMap],
    missions: list[tuple[str, str, int, int, int, int]],
    class_table: list[int],
) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    count = len(tiles)
    tile_w = len(tiles[0][0])

    class_enum = ",\n".join(
        f"    FORCE_CLASS_{name.upper()} = {num}"
        for name, num in sorted(classes.items(), key=lambda kv: kv[1])
    )

    h_path = out_dir / "force_data.h"
    c_path = out_dir / "force_data.c"

    h = f"""/* Generated by tools/gen_sdl.py — do not edit. */
#ifndef FORCE_DATA_H
#define FORCE_DATA_H

#include <stdint.h>
#include <stddef.h>

#define FORCE_TILESET_COUNT  {count}
#define FORCE_TILE_PX        {tile_w}
#define FORCE_TILE_EMPTY     {empty_tile}

#define FORCE_MAP_W_MAX          {FORCE_MAP_W_MAX}
#define FORCE_MAP_H_MAX          {FORCE_MAP_H_MAX}
#define FORCE_MAP_CELLS_MAX      {FORCE_MAP_CELLS_MAX}

#define FORCE_ROOM_MAX           {FORCE_ROOM_MAX}
#define FORCE_PORTAL_MAX         {FORCE_PORTAL_MAX}
#define FORCE_COVER_MAX          {FORCE_COVER_MAX}
#define FORCE_COVER_PER_ROOM     {FORCE_COVER_PER_ROOM}
#define FORCE_SPAWN_MAX          {FORCE_SPAWN_MAX}
#define FORCE_SCOUT_MAX          {FORCE_SCOUT_MAX}
#define FORCE_SCOUT_PER_ROOM     {FORCE_SCOUT_PER_ROOM}
#define FORCE_OBJECTIVE_MAX      {FORCE_OBJECTIVE_MAX}
#define FORCE_MINE_MAX           {FORCE_MINE_MAX}

#define FORCE_FACE_NONE  {FORCE_FACE_NONE}
#define FORCE_FACE_N     {FORCE_FACE_N}
#define FORCE_FACE_E     {FORCE_FACE_E}
#define FORCE_FACE_S     {FORCE_FACE_S}
#define FORCE_FACE_W     {FORCE_FACE_W}

enum force_tile_class {{
{class_enum}
}};

extern const uint32_t force_tileset[FORCE_TILESET_COUNT][FORCE_TILE_PX][FORCE_TILE_PX];
extern const uint8_t force_tile_class[FORCE_TILESET_COUNT];

typedef struct force_map {{
    const char *name;
    uint16_t width;
    uint16_t height;
    const uint8_t *color;
    const uint8_t *tiles;

    uint8_t room_count;
    const uint8_t *room_x0;
    const uint8_t *room_y0;
    const uint8_t *room_w;
    const uint8_t *room_h;
    const uint8_t *room_colour;
    const uint8_t *room_cover_base;
    const uint8_t *room_cover_count;
    const uint8_t *room_scout_base;
    const uint8_t *room_scout_count;

    uint8_t cover_count;
    const uint8_t *cover_x;
    const uint8_t *cover_y;
    const uint8_t *cover_grade;
    const uint8_t *cover_facing;

    uint8_t portal_count;
    const uint8_t *portal_x;
    const uint8_t *portal_y;

    uint8_t scout_count;
    const uint8_t *scout_x;
    const uint8_t *scout_y;
    const uint8_t *scout_facing;

    uint8_t spawn_count;
    const uint8_t *spawn_x;
    const uint8_t *spawn_y;
    const uint8_t *spawn_tile;

    uint8_t objective_count;
    const uint8_t *objective_x;
    const uint8_t *objective_y;

    uint8_t mine_count;
    const uint8_t *mine_x;
    const uint8_t *mine_y;
}} force_map;

"""
    for compiled in maps:
        h += f"extern const force_map force_map_{c_ident(compiled.name)};\n"
    h += """
extern const force_map *const force_maps[];
extern const unsigned force_map_count;

typedef struct force_mission {
    const char *name;
    const force_map *map;
    uint16_t x;
    uint16_t y;
    uint16_t w;
    uint16_t h;
} force_mission;

extern const force_mission force_missions[];
extern const unsigned force_mission_count;

#endif
"""
    h_path.write_text(h, encoding="utf-8")

    class_bytes = ", ".join(str(v) for v in class_table)
    tile_blocks = "\n".join(emit_u32_tile(t) for t in tiles)

    c = f"""/* Generated by tools/gen_sdl.py — do not edit. */
#include "generated/force_data.h"

const uint32_t force_tileset[FORCE_TILESET_COUNT][FORCE_TILE_PX][FORCE_TILE_PX] = {{
{tile_blocks}
}};

const uint8_t force_tile_class[FORCE_TILESET_COUNT] = {{
    {class_bytes}
}};

"""
    map_syms: dict[str, str] = {}
    for compiled in maps:
        sym = f"force_map_{c_ident(compiled.name)}"
        map_syms[compiled.name] = sym
        c += emit_map_arrays(sym, compiled)
        c += emit_map_init(sym, compiled)

    map_ptrs = ", ".join(f"&force_map_{c_ident(m.name)}" for m in maps)
    c += f"const force_map *const force_maps[] = {{ {map_ptrs} }};\n"
    c += f"const unsigned force_map_count = {len(maps)};\n\n"

    c += "const force_mission force_missions[] = {\n"
    for name, map_name, x, y, w, h in missions:
        c += (
            f'    {{ "{name}", &{map_syms[map_name]}, '
            f"{x}, {y}, {w}, {h} }},\n"
        )
    c += "};\n"
    c += f"const unsigned force_mission_count = {len(missions)};\n"
    c_path.write_text(c, encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", type=Path, help="force repo root")
    ap.add_argument("--out", type=Path, help="output directory for generated C")
    args = ap.parse_args(argv)

    root = (args.root or Path(__file__).resolve().parents[1]).resolve()
    out = (args.out or (root / "src" / "sdl" / "generated")).resolve()
    tiles_txt = root / "assets" / "tiles.txt"
    missions_txt = root / "assets" / "missions.txt"
    properties_txt = root / "assets" / "properties.txt"
    maps_dir = root / "assets" / "maps"
    tsx_path = maps_dir / "tiles.tsx"

    try:
        name_per_id, classes, empty_tile = load_tile_desc(tiles_txt)
        missions = load_missions(missions_txt)
        chip_to_preset = load_properties_txt(properties_txt)
        tile_w, tile_h, columns, count, png = load_tsx(tsx_path)
        if tile_w != 8 or tile_h != 8:
            raise Error(f"{tsx_path}: tiles must be 8x8 (got {tile_w}x{tile_h})")
        img_w, img_h, pixels = load_png_rgba(png)
        if img_w != columns * tile_w:
            raise Error(f"{png}: width {img_w} != {columns}*{tile_w}")
        tiles = slice_tiles(pixels, tile_w, tile_h, columns, count)
        verify_double_wide(tiles, png)
        if len(name_per_id) > count:
            extra = [i for i, n in enumerate(name_per_id) if n and i >= count]
            raise Error(f"{tiles_txt}: tile ids {extra} past tileset count {count}")

        class_table = [classes["empty"]] * count
        for tid in range(count):
            if tid < len(name_per_id) and name_per_id[tid] is not None:
                class_table[tid] = classes[name_per_id[tid]]  # type: ignore[index]

        tmx_files = sorted(maps_dir.glob("*.tmx"))
        if not tmx_files:
            raise Error(f"{maps_dir}: no .tmx files")
        loaded: list[tuple[str, int, int, dict[str, list[int | None]], int]] = []
        seen: set[str] = set()
        for tmx in tmx_files:
            name, width, height, planes, firstgid = load_tmx(
                tmx, count, empty_tile
            )
            if name in seen:
                raise Error(f"duplicate map name '{name}'")
            seen.add(name)
            loaded.append((name, width, height, planes, firstgid))

        for mname, map_name, x, y, w, h in missions:
            if map_name not in seen:
                raise Error(f"{missions_txt}: map '{map_name}' not found (mission {mname})")
            mw, mh = next(
                (mw, mh) for n, mw, mh, _planes, _fg in loaded if n == map_name
            )
            if x + w > mw or y + h > mh:
                raise Error(
                    f"{missions_txt}: {mname} rect {x},{y},{w},{h} "
                    f"outside {map_name} {mw}x{mh}"
                )

        maps = [
            compile_map(
                name,
                width,
                height,
                planes,
                firstgid,
                empty_tile,
                chip_to_preset,
                class_table,
                classes,
            )
            for name, width, height, planes, firstgid in loaded
        ]

        write_generated(
            out, tiles, classes, empty_tile, maps, missions, class_table
        )
    except Error as exc:
        print(f"gen_sdl: {exc}", file=sys.stderr)
        return 1

    per_map = ", ".join(
        f"{m.name} {len(m.rooms)} rooms {len(m.spawn_x)} spawns "
        f"{len(m.cover_x)} cover"
        for m in maps
    )
    print(
        f"gen_sdl: {count} tiles, {len(maps)} map(s), {len(missions)} mission(s), "
        f"{per_map} -> {out}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
