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
TILED_FLIP = 0xE0000000
IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


class Error(Exception):
    pass


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


def gid_to_tid(gid: int, firstgid: int, count: int, loc: str, empty_out: int) -> int:
    if gid & TILED_FLIP:
        raise Error(f"{loc}: flipped tiles are not supported")
    if gid == 0:
        return empty_out
    tid = gid - firstgid
    if tid < 0 or tid >= count:
        raise Error(f"{loc}: gid {gid} out of tileset")
    return tid


def load_tmx(
    path: Path, tile_count: int, empty_tile: int
) -> tuple[str, int, int, dict[str, list[int]]]:
    root = ET.parse(path).getroot()
    width = int(root.attrib["width"])
    height = int(root.attrib["height"])
    ts = root.find("tileset")
    if ts is None:
        raise Error(f"{path}: no tileset")
    firstgid = int(ts.attrib["firstgid"])
    planes: dict[str, list[int]] = {}
    for layer in root.findall("layer"):
        name = layer.attrib.get("name", "")
        data = layer.find("data")
        if data is None or data.attrib.get("encoding") != "csv":
            raise Error(f"{path}: layer '{name}' is not CSV")
        loc = f"{path} layer '{name}'"
        gids = parse_csv_cells(data.text or "", width, height, loc)
        none_is_zero = name in ("properties", "actors", "rooms")
        fill = 0 if none_is_zero else empty_tile
        planes[name] = [
            gid_to_tid(g, firstgid, tile_count, loc, fill) for g in gids
        ]
    for name in LAYER_NAMES:
        if name not in planes:
            fill = 0 if name in ("properties", "actors", "rooms") else empty_tile
            planes[name] = [fill] * (width * height)
    unknown = set(planes) - set(LAYER_NAMES)
    if unknown:
        raise Error(f"{path}: unknown layer(s) {sorted(unknown)}")
    return path.stem, width, height, planes


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


def write_generated(
    out_dir: Path,
    tiles: list[list[list[int]]],
    name_per_id: list[str | None],
    classes: dict[str, int],
    empty_tile: int,
    maps: list[tuple[str, int, int, dict[str, list[int]]]],
    missions: list[tuple[str, str, int, int, int, int]],
) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    count = len(tiles)
    tile_h = len(tiles[0])
    tile_w = len(tiles[0][0])
    class_table = [classes["empty"]] * count
    for tid in range(count):
        if tid < len(name_per_id) and name_per_id[tid] is not None:
            class_table[tid] = classes[name_per_id[tid]]  # type: ignore[index]

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

#define FORCE_TILESET_COUNT  {count}
#define FORCE_TILE_PX        {tile_w}
#define FORCE_TILE_EMPTY     {empty_tile}

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
    const uint8_t *properties;
    const uint8_t *actors;
    const uint8_t *rooms;
}} force_map;

"""
    for name, _w, _h, _planes in maps:
        h += f"extern const force_map force_map_{c_ident(name)};\n"
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
    for name, width, height, planes in maps:
        sym = f"force_map_{c_ident(name)}"
        map_syms[name] = sym
        for plane in LAYER_NAMES:
            arr = f"{sym}_{plane}"
            c += f"static const uint8_t {arr}[{width * height}] = {{\n"
            c += emit_u8_plane(planes[plane], width)
            c += "\n};\n\n"
        c += (
            f"const force_map {sym} = {{\n"
            f'    "{name}", {width}, {height},\n'
            f"    {sym}_color, {sym}_tiles, {sym}_properties,\n"
            f"    {sym}_actors, {sym}_rooms\n"
            f"}};\n\n"
        )

    map_ptrs = ", ".join(f"&force_map_{c_ident(name)}" for name, *_ in maps)
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
    maps_dir = root / "assets" / "maps"
    tsx_path = maps_dir / "tiles.tsx"

    try:
        name_per_id, classes, empty_tile = load_tile_desc(tiles_txt)
        missions = load_missions(missions_txt)
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

        tmx_files = sorted(maps_dir.glob("*.tmx"))
        if not tmx_files:
            raise Error(f"{maps_dir}: no .tmx files")
        maps: list[tuple[str, int, int, dict[str, list[int]]]] = []
        seen: set[str] = set()
        for tmx in tmx_files:
            name, width, height, planes = load_tmx(tmx, count, empty_tile)
            if name in seen:
                raise Error(f"duplicate map name '{name}'")
            seen.add(name)
            maps.append((name, width, height, planes))

        for mname, map_name, x, y, w, h in missions:
            if map_name not in seen:
                raise Error(f"{missions_txt}: map '{map_name}' not found (mission {mname})")
            mw, mh = next((mw, mh) for n, mw, mh, _ in maps if n == map_name)
            if x + w > mw or y + h > mh:
                raise Error(
                    f"{missions_txt}: {mname} rect {x},{y},{w},{h} "
                    f"outside {map_name} {mw}x{mh}"
                )

        write_generated(out, tiles, name_per_id, classes, empty_tile, maps, missions)
    except Error as exc:
        print(f"gen_sdl: {exc}", file=sys.stderr)
        return 1

    print(
        f"gen_sdl: {count} tiles, {len(maps)} map(s), {len(missions)} mission(s) -> {out}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
