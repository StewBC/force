#!/usr/bin/env python3
"""Turn assets/png/force_title_c64.png into the C64 multicolour splash.

The PNG is 160x200, one VIC colour per pixel (Colodore RGB). Each 4x8 cell
uses black plus at most three other colours, so black is the shared background
and is not stored.

Outputs, all under the repo:
  src/c64/generated/title_bitmap.bin   8000 bytes, cell-major, 2 bits per pixel
  src/c64/generated/title_colour.bin   2000 bytes, 1000 screen then 1000 colour
  src/sdl/generated/title_data.c/.h    the same bytes for the SDL splash
"""

import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PNG = ROOT / "assets" / "png" / "force_title_c64.png"
BITMAP_PATH = ROOT / "src" / "c64" / "generated" / "title_bitmap.bin"
COLOUR_PATH = ROOT / "src" / "c64" / "generated" / "title_colour.bin"
SDL_C = ROOT / "src" / "sdl" / "generated" / "title_data.c"
SDL_H = ROOT / "src" / "sdl" / "generated" / "title_data.h"

# Colodore, index order. Exact match against the title PNG.
PALETTE = [
    bytes.fromhex("000000"),
    bytes.fromhex("FFFFFF"),
    bytes.fromhex("813338"),
    bytes.fromhex("75CEC8"),
    bytes.fromhex("8E3C97"),
    bytes.fromhex("56AC4D"),
    bytes.fromhex("2E2C9B"),
    bytes.fromhex("EDF171"),
    bytes.fromhex("8E5029"),
    bytes.fromhex("553800"),
    bytes.fromhex("C46C71"),
    bytes.fromhex("4A4A4A"),
    bytes.fromhex("7B7B7B"),
    bytes.fromhex("A9FF9F"),
    bytes.fromhex("706DEB"),
    bytes.fromhex("B2B2B2"),
]
BACKGROUND = 0
W = 160
H = 200
CELLS_X = 40
CELLS_Y = 25


def fail(msg):
    print("gen_title: " + msg, file=sys.stderr)
    sys.exit(1)


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def read_png(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        fail(f"{path} is not a PNG")
    i = 8
    w = h = 0
    color = None
    idat = b""
    while i < len(data):
        ln = struct.unpack(">I", data[i : i + 4])[0]
        typ = data[i + 4 : i + 8]
        chunk = data[i + 8 : i + 8 + ln]
        if typ == b"IHDR":
            w, h, bit, color, comp, filt, inter = struct.unpack(">IIBBBBB", chunk)
            if bit != 8 or color != 2 or comp != 0 or filt != 0 or inter != 0:
                fail("title PNG must be 8-bit RGB, non-interlaced")
        elif typ == b"IDAT":
            idat += chunk
        i += 12 + ln
        if typ == b"IEND":
            break
    if (w, h) != (W, H):
        fail(f"title PNG is {w}x{h}, expected {W}x{H}")
    raw = zlib.decompress(idat)
    rows = []
    pos = 0
    stride = w * 3
    prev = bytearray(stride)
    for _y in range(h):
        f = raw[pos]
        pos += 1
        row = bytearray(raw[pos : pos + stride])
        pos += stride
        if f == 1:
            for x in range(stride):
                left = row[x - 3] if x >= 3 else 0
                row[x] = (row[x] + left) & 255
        elif f == 2:
            for x in range(stride):
                row[x] = (row[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                left = row[x - 3] if x >= 3 else 0
                row[x] = (row[x] + ((left + prev[x]) // 2)) & 255
        elif f == 4:
            for x in range(stride):
                a = row[x - 3] if x >= 3 else 0
                b = prev[x]
                c = prev[x - 3] if x >= 3 else 0
                row[x] = (row[x] + paeth(a, b, c)) & 255
        elif f != 0:
            fail(f"unknown PNG filter {f}")
        rows.append(row)
        prev = row
    return rows


def index_of(rgb):
    try:
        return PALETTE.index(rgb)
    except ValueError:
        fail(f"pixel {rgb.hex()} is not a Colodore VIC colour")
        return 0


def encode(rows):
    bitmap = bytearray(8000)
    screen = bytearray(1000)
    colour = bytearray(1000)
    for cy in range(CELLS_Y):
        for cx in range(CELLS_X):
            pixels = []
            extras = []
            for py in range(8):
                row_i = []
                src = rows[cy * 8 + py]
                for px in range(4):
                    x = (cx * 4 + px) * 3
                    idx = index_of(bytes(src[x : x + 3]))
                    row_i.append(idx)
                    if idx != BACKGROUND and idx not in extras:
                        extras.append(idx)
                pixels.append(row_i)
            if len(extras) > 3:
                fail(f"cell {cx},{cy} needs more than three colours besides black")
            cell = cy * CELLS_X + cx
            screen[cell] = ((extras[0] if len(extras) > 0 else 0) << 4) | (
                extras[1] if len(extras) > 1 else 0
            )
            colour[cell] = extras[2] if len(extras) > 2 else 0
            base = cell * 8
            for py in range(8):
                byte = 0
                for px in range(4):
                    idx = pixels[py][px]
                    if idx == BACKGROUND:
                        bits = 0
                    else:
                        bits = extras.index(idx) + 1
                    byte = (byte << 2) | bits
                bitmap[base + py] = byte
    return bitmap, screen, colour


def roundtrip(rows, bitmap, screen, colour):
    for cy in range(CELLS_Y):
        for cx in range(CELLS_X):
            cell = cy * CELLS_X + cx
            hi = screen[cell] >> 4
            lo = screen[cell] & 0x0F
            cr = colour[cell] & 0x0F
            slots = (BACKGROUND, hi, lo, cr)
            base = cell * 8
            for py in range(8):
                byte = bitmap[base + py]
                src = rows[cy * 8 + py]
                for px in range(4):
                    bits = (byte >> (6 - 2 * px)) & 3
                    got = PALETTE[slots[bits]]
                    x = (cx * 4 + px) * 3
                    if bytes(src[x : x + 3]) != got:
                        fail(f"roundtrip mismatch at {cx * 4 + px},{cy * 8 + py}")


def c_array(name, data):
    lines = [f"const uint8_t {name}[{len(data)}] = {{"]
    for i in range(0, len(data), 16):
        chunk = ", ".join(f"0x{b:02X}" for b in data[i : i + 16])
        lines.append(f"    {chunk},")
    lines.append("};")
    lines.append("")
    return "\n".join(lines)


def write_sdl(bitmap, screen, colour):
    SDL_C.parent.mkdir(parents=True, exist_ok=True)
    SDL_H.write_text(
        "/* Generated by tools/gen_title.py — do not edit. */\n"
        "#ifndef FORCE_TITLE_DATA_H\n"
        "#define FORCE_TITLE_DATA_H\n"
        "\n"
        "#include <stdint.h>\n"
        "\n"
        "#define FORCE_TITLE_BITMAP_BYTES 8000\n"
        "#define FORCE_TITLE_SCREEN_BYTES 1000\n"
        "#define FORCE_TITLE_COLOUR_BYTES 1000\n"
        "\n"
        "extern const uint8_t force_title_bitmap[FORCE_TITLE_BITMAP_BYTES];\n"
        "extern const uint8_t force_title_screen[FORCE_TITLE_SCREEN_BYTES];\n"
        "extern const uint8_t force_title_colour[FORCE_TITLE_COLOUR_BYTES];\n"
        "\n"
        "#endif\n"
    )
    SDL_C.write_text(
        "/* Generated by tools/gen_title.py — do not edit. */\n"
        '#include "title_data.h"\n'
        "\n"
        + c_array("force_title_bitmap", bitmap)
        + c_array("force_title_screen", screen)
        + c_array("force_title_colour", colour)
    )


def main():
    rows = read_png(PNG)
    bitmap, screen, colour = encode(rows)
    roundtrip(rows, bitmap, screen, colour)
    BITMAP_PATH.parent.mkdir(parents=True, exist_ok=True)
    BITMAP_PATH.write_bytes(bitmap)
    COLOUR_PATH.write_bytes(screen + colour)
    write_sdl(bitmap, screen, colour)


if __name__ == "__main__":
    main()
