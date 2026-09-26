#!/usr/bin/env python3
"""Print C64 map-bundle sizes and fail if a home or a plane will not fit.

Uses the tables tools/gen_c64.py builds (the same bytes farm.asm used to
link) and checks build/c64/farm.prg. Plane chunks go through tools/lzss.py.
From the repo root:

    python3 tools/gen_c64.py && python3 tools/measure_c64_bundle.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import gen_c64  # noqa: E402
import gen_sdl  # noqa: E402
import lzss  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "build" / "c64" / "farm.prg"
BUNDLE_SHOWN = "build/c64/farm.prg"
GEN_SDL = ROOT / "tools" / "gen_sdl.py"
MISSIONS = ROOT / "assets" / "missions.txt"

LOAD = 0xA000
MISSION_HOME = 0x0900
MISSION_CEILING = 0x1C00
CHARSET = 0x2000
IO_PAGE = 0xD000
TILE_DEST_END = 0xAC80
SCRATCH = 4096
PLANE_BYTES = 3200
GEO_IMAGE_MAX = 870
MISSION_CHUNK_MAX = 3943

# One-shot file: geometry, missions, tiles, paper. Tileset id $05 is not emitted.
CHUNK_COUNT = 4
# Fixed header through chunk_count, then 10 bytes per entry.
INDEX_FIXED = 4 + 1 + 1 + 1 + 1 + 16 + 1 + 1
ENTRY_BYTES = 10
# Content target that sized the $0900 hole. Not a compiler cap.
CAP_MISSIONS = 6

_CAP_NAMES = (
    "FORCE_ROOM_MAX",
    "FORCE_PORTAL_MAX",
    "FORCE_COVER_MAX",
    "FORCE_SCOUT_MAX",
    "FORCE_SPAWN_MAX",
    "FORCE_SCRIPT_OPS_MAX",
    "FORCE_SCRIPT_WATCH_MAX",
    "FORCE_SCRIPT_BEAT_MAX",
    "FORCE_SCRIPT_PRED_MAX",
    "FORCE_SCRIPT_WHERE_MAX",
    "FORCE_SCRIPT_SPAWN_MAX",
    "FORCE_SCRIPT_NAME_MAX",
)

MAP_SCALARS = (
    "rom_map_w",
    "rom_map_h",
    "rom_room_count",
    "rom_cover_count",
    "rom_portal_count",
    "rom_scout_count",
)
PLAY_SCALARS = (
    "rom_play_x",
    "rom_play_y",
    "rom_play_w",
    "rom_play_h",
    "rom_cam_x",
    "rom_cam_y",
    "rom_spawn_count",
)
SCRIPT_SCALARS = (
    "sc_op_count",
    "sc_beat_count",
    "sc_watch_count",
    "sc_pred_count",
    "sc_where_count",
    "sc_spawn_count",
    "sc_start_spawn_room",
    "sc_start_beat",
    "sc_player_grenades",
    "sc_player_grenade_wait",
    "sc_enemy_grenades",
    "sc_enemy_grenade_wait",
)
ROOM_LABELS = (
    "rom_room_x0",
    "rom_room_y0",
    "rom_room_w",
    "rom_room_h",
    "rom_room_colour",
    "rom_room_cover_base",
    "rom_room_cover_count",
    "rom_room_scout_base",
    "rom_room_scout_count",
    "rom_room_axis",
    "rom_room_cover_lo",
    "rom_room_cover_none",
    "rom_room_cover_hi",
)
COVER_LABELS = (
    "rom_cover_x",
    "rom_cover_y",
    "rom_cover_grade",
    "rom_cover_facing",
)
PORTAL_LABELS = ("rom_portal_x", "rom_portal_y")
SCOUT_LABELS = ("rom_scout_x", "rom_scout_y", "rom_scout_facing")
SPAWN_LABELS = ("rom_spawn_x", "rom_spawn_y", "rom_spawn_tile")
OP_LABELS = ("sc_op_code", "sc_op_a", "sc_op_b", "sc_op_c")
BEAT_LABELS = ("sc_beat_pc",)
WATCH_LABELS = (
    "sc_watch_pred0",
    "sc_watch_pred1",
    "sc_watch_op",
    "sc_watch_arg",
    "sc_watch_flags",
)
PRED_LABELS = ("sc_pred_kind", "sc_pred_who", "sc_pred_a", "sc_pred_b")
WHERE_LABELS = ("sc_where_kind", "sc_where_a", "sc_where_b")
TMPL_LABELS = (
    "sc_spawn_n",
    "sc_spawn_letter",
    "sc_spawn_room",
    "sc_spawn_batch",
    "sc_spawn_period",
)

_CAP_RE = re.compile(r"^([A-Z][A-Z0-9_]*)\s*=\s*(\d+)\b")


def fail(msg: str) -> None:
    print(f"measure_c64_bundle: {msg}", file=sys.stderr)
    raise SystemExit(1)


def need(labels: dict[str, list[int]], name: str) -> list[int]:
    if name not in labels:
        fail(f"farm.asm has no {name}")
    return labels[name]


def scalar(labels: dict[str, list[int]], name: str) -> int:
    data = need(labels, name)
    if len(data) != 1:
        fail(f"{name} is {len(data)} bytes, expected 1")
    return data[0]


def check_counted(labels: dict[str, list[int]], names: tuple[str, ...], count: int) -> int:
    """Byte size as linked. count 0 is the one-byte placeholder, not a tight 0."""
    total = 0
    for name in names:
        data = need(labels, name)
        if count == 0:
            if len(data) != 1:
                fail(f"{name} placeholder is {len(data)} bytes, expected 1")
        elif len(data) != count:
            fail(f"{name} is {len(data)} bytes, count is {count}")
        total += len(data)
    return total


def load_caps(path: Path) -> dict[str, int]:
    if not path.is_file():
        fail(f"missing {path}")
    found: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = _CAP_RE.match(line.strip())
        if not match:
            continue
        name = match.group(1)
        if name in _CAP_NAMES and name not in found:
            found[name] = int(match.group(2))
    missing = [name for name in _CAP_NAMES if name not in found]
    if missing:
        fail(f"missing caps in {path}: {', '.join(missing)}")
    return found


def farm_stem(path: Path) -> str:
    """Script stem of the first farm row, the mission gen_c64.py emits."""
    if not path.is_file():
        fail(f"missing {path}")
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 3:
            fail(f"{path}:{lineno}: expected name map x,y,w,h [script]")
        if parts[1] != "farm":
            continue
        for tok in parts[3:]:
            if not tok.startswith("cam="):
                return tok
        fail(f"{path}:{lineno}: farm mission has no script stem")
    fail(f"{path}: no farm mission")
    return ""


def mission_chunk(count: int, stem_len: int, body: int) -> int:
    return 1 + count * (1 + stem_len + 2 + body)


def blocks_of(file_bytes: int) -> int:
    return (file_bytes + 253) // 254


def intersects_tile_dest(offset: int, src_len: int) -> bool:
    start = LOAD + offset
    end = start + src_len
    return start < TILE_DEST_END and end > LOAD


def _tight(labels: dict[str, list[int]], names: tuple[str, ...], count: int) -> bytes:
    """Logical columns. count 0 drops the linked one-byte placeholder."""
    out = bytearray()
    for name in names:
        out.extend(need(labels, name)[:count])
    return bytes(out)


def logical_geometry(labels: dict[str, list[int]]) -> bytes:
    out = bytearray(scalar(labels, name) for name in MAP_SCALARS)
    out.extend(_tight(labels, ROOM_LABELS, scalar(labels, "rom_room_count")))
    out.extend(_tight(labels, COVER_LABELS, scalar(labels, "rom_cover_count")))
    out.extend(_tight(labels, PORTAL_LABELS, scalar(labels, "rom_portal_count")))
    out.extend(_tight(labels, SCOUT_LABELS, scalar(labels, "rom_scout_count")))
    return bytes(out)


def logical_mission(labels: dict[str, list[int]], stem: str) -> bytes:
    body = bytearray(scalar(labels, name) for name in PLAY_SCALARS)
    body.extend(_tight(labels, SPAWN_LABELS, scalar(labels, "rom_spawn_count")))
    body.extend(scalar(labels, name) for name in SCRIPT_SCALARS)
    body.extend(_tight(labels, OP_LABELS, scalar(labels, "sc_op_count")))
    body.extend(_tight(labels, BEAT_LABELS, scalar(labels, "sc_beat_count")))
    body.extend(_tight(labels, WATCH_LABELS, scalar(labels, "sc_watch_count")))
    body.extend(_tight(labels, PRED_LABELS, scalar(labels, "sc_pred_count")))
    body.extend(_tight(labels, WHERE_LABELS, scalar(labels, "sc_where_count")))
    body.extend(_tight(labels, TMPL_LABELS, scalar(labels, "sc_spawn_count")))
    stem_b = stem.encode("ascii")
    return bytes((1, len(stem_b))) + stem_b + len(body).to_bytes(2, "little") + bytes(body)


def _diff_at(label: str, got: bytes, exp: bytes) -> str:
    n = min(len(got), len(exp))
    for i in range(n):
        if got[i] != exp[i]:
            return (
                f"{label} differs at {i}: ${got[i]:02X} != ${exp[i]:02X}"
                f" (lengths {len(got)} and {len(exp)})"
            )
    return f"{label} length {len(got)} != {len(exp)}"


def _u16(buf: bytes, i: int) -> int:
    return buf[i] | (buf[i + 1] << 8)


def check_farm_bundle(
    labels: dict[str, list[int]],
    stem: str,
    tiles: bytes,
    paper: bytes,
) -> tuple[int, list[str]]:
    """Match build/c64/farm.prg. Planes are LZSS when that form is under 3200."""
    if not BUNDLE.is_file():
        return 0, [f"missing {BUNDLE_SHOWN}; run python3 tools/gen_c64.py"]
    data = BUNDLE.read_bytes()
    index = INDEX_FIXED + ENTRY_BYTES * CHUNK_COUNT
    if len(data) < 2 + index:
        return 0, [f"{BUNDLE_SHOWN} is {len(data)} bytes, shorter than the index"]
    problems: list[str] = []
    load_at = _u16(data, 0)
    payload = data[2:]
    end = LOAD + len(payload)
    if load_at != LOAD:
        problems.append(f"{BUNDLE_SHOWN} load address ${load_at:04X} != $A000")
    if payload[:4] != b"FMAP":
        problems.append(f"{BUNDLE_SHOWN} magic is {payload[:4]!r}, expected FMAP")
    version, file_flags, mission_count, reserved = payload[4:8]
    if version != 1:
        problems.append(f"{BUNDLE_SHOWN} version {version} != 1")
    if file_flags != 0x01:
        problems.append(f"{BUNDLE_SHOWN} flags ${file_flags:02X} != $01")
    if mission_count != 1:
        problems.append(f"{BUNDLE_SHOWN} mission_count {mission_count} != 1")
    if reserved != 0:
        problems.append(f"{BUNDLE_SHOWN} reserved ${reserved:02X} != 0")
    if payload[8:24] != bytes([0xA0]) * 16:
        problems.append(f"{BUNDLE_SHOWN} continuation name is not $A0 pad")
    if payload[24] != 0:
        problems.append(f"{BUNDLE_SHOWN} continuation length {payload[24]} != 0")
    if payload[25] != CHUNK_COUNT:
        problems.append(f"{BUNDLE_SHOWN} chunk_count {payload[25]} != {CHUNK_COUNT}")

    geo = logical_geometry(labels)
    missions = logical_mission(labels, stem)
    tile_flag, tile_body = gen_c64.stored_plane(tiles)
    paper_flag, paper_body = gen_c64.stored_plane(paper)
    if (tile_flag, len(tile_body), paper_flag, len(paper_body)) != (1, 532, 1, 433):
        problems.append(
            f"stored planes flags {tile_flag}/{paper_flag} "
            f"lengths {len(tile_body)}/{len(paper_body)}, expected 1/1 and 532/433"
        )
    # Offset and src_len walk the rebuilt bodies. Homes stay fixed.
    chunks = (
        (1, 0, 0xB900, 870, geo),
        (2, 0, 0x0900, len(missions), missions),
        (3, tile_flag, 0xA000, PLANE_BYTES, tile_body),
        (4, paper_flag, 0xAC80, PLANE_BYTES, paper_body),
    )
    offset = INDEX_FIXED + ENTRY_BYTES * CHUNK_COUNT
    for i, (cid, flags, dest, dest_len, body) in enumerate(chunks):
        base = INDEX_FIXED + i * ENTRY_BYTES
        got_id = payload[base]
        got_flags = payload[base + 1]
        got_off = _u16(payload, base + 2)
        got_src = _u16(payload, base + 4)
        got_dest = _u16(payload, base + 6)
        got_dlen = _u16(payload, base + 8)
        src_len = len(body)
        if (got_id, got_flags, got_off, got_src, got_dest, got_dlen) != (
            cid, flags, offset, src_len, dest, dest_len,
        ):
            problems.append(
                f"chunk {cid} entry is "
                f"id {got_id} flags ${got_flags:02X} off {got_off} "
                f"src {got_src} dest ${got_dest:04X} dest_len {got_dlen}; "
                f"expected id {cid} flags ${flags:02X} off {offset} src {src_len} "
                f"dest ${dest:04X} dest_len {dest_len}"
            )
        end_at = offset + src_len
        if end_at > len(payload):
            problems.append(f"chunk {cid} extends past the payload")
        else:
            got_body = payload[offset:end_at]
            if got_body != body:
                problems.append(_diff_at(f"chunk {cid}", got_body, body))
        offset = end_at
    if offset != len(payload):
        problems.append(
            f"payload is {len(payload)} bytes; chunks end at {offset}"
        )
    if end != 0xA606:
        problems.append(f"bundle exclusive end ${end:04X} != $A606")
    return end, problems


def main() -> int:
    if len(sys.argv) != 1:
        fail("usage: python3 tools/measure_c64_bundle.py")

    try:
        labels = gen_c64.linked_labels()
    except gen_sdl.Error as exc:
        fail(str(exc))
    caps = load_caps(GEN_SDL)
    stem = farm_stem(MISSIONS)
    # FORCE_SCRIPT_NAME_MAX counts the C NUL. The directory stores the stem only.
    stem_max = caps["FORCE_SCRIPT_NAME_MAX"] - 1
    if stem_max < 1:
        fail(f"FORCE_SCRIPT_NAME_MAX {caps['FORCE_SCRIPT_NAME_MAX']} leaves no stem")
    if not 1 <= len(stem) <= stem_max:
        fail(f"script stem '{stem}' is {len(stem)} bytes, limit is {stem_max}")

    room_count = scalar(labels, "rom_room_count")
    cover_count = scalar(labels, "rom_cover_count")
    portal_count = scalar(labels, "rom_portal_count")
    scout_count = scalar(labels, "rom_scout_count")
    spawn_count = scalar(labels, "rom_spawn_count")
    op_count = scalar(labels, "sc_op_count")
    beat_count = scalar(labels, "sc_beat_count")
    watch_count = scalar(labels, "sc_watch_count")
    pred_count = scalar(labels, "sc_pred_count")
    where_count = scalar(labels, "sc_where_count")
    tmpl_count = scalar(labels, "sc_spawn_count")

    for name in MAP_SCALARS + PLAY_SCALARS + SCRIPT_SCALARS:
        scalar(labels, name)

    room_linked = 0
    room_width = len(need(labels, ROOM_LABELS[0]))
    for name in ROOM_LABELS:
        data = need(labels, name)
        if len(data) != room_width:
            fail(f"{name} is {len(data)} bytes, {ROOM_LABELS[0]} is {room_width}")
        if len(data) < room_count:
            fail(f"{name} is shorter than room_count {room_count}")
        room_linked += len(data)
    cover_linked = check_counted(labels, COVER_LABELS, cover_count)
    portal_linked = check_counted(labels, PORTAL_LABELS, portal_count)
    scout_linked = check_counted(labels, SCOUT_LABELS, scout_count)
    check_counted(labels, SPAWN_LABELS, spawn_count)
    check_counted(labels, OP_LABELS, op_count)
    check_counted(labels, BEAT_LABELS, beat_count)
    check_counted(labels, WATCH_LABELS, watch_count)
    check_counted(labels, PRED_LABELS, pred_count)
    check_counted(labels, WHERE_LABELS, where_count)
    check_counted(labels, TMPL_LABELS, tmpl_count)

    geo_logical = (
        len(MAP_SCALARS)
        + room_count * len(ROOM_LABELS)
        + cover_count * len(COVER_LABELS)
        + portal_count * len(PORTAL_LABELS)
        + scout_count * len(SCOUT_LABELS)
    )
    geo_linked = len(MAP_SCALARS) + room_linked + cover_linked + portal_linked + scout_linked
    mission_tight = (
        len(PLAY_SCALARS)
        + spawn_count * len(SPAWN_LABELS)
        + len(SCRIPT_SCALARS)
        + op_count * len(OP_LABELS)
        + beat_count * len(BEAT_LABELS)
        + watch_count * len(WATCH_LABELS)
        + pred_count * len(PRED_LABELS)
        + where_count * len(WHERE_LABELS)
        + tmpl_count * len(TMPL_LABELS)
    )
    farm_missions = mission_chunk(1, len(stem), mission_tight)

    geo_cap = (
        len(MAP_SCALARS)
        + caps["FORCE_ROOM_MAX"] * len(ROOM_LABELS)
        + caps["FORCE_COVER_MAX"] * len(COVER_LABELS)
        + caps["FORCE_PORTAL_MAX"] * len(PORTAL_LABELS)
        + caps["FORCE_SCOUT_MAX"] * len(SCOUT_LABELS)
    )
    mission_cap = (
        len(PLAY_SCALARS)
        + caps["FORCE_SPAWN_MAX"] * len(SPAWN_LABELS)
        + len(SCRIPT_SCALARS)
        + caps["FORCE_SCRIPT_OPS_MAX"] * len(OP_LABELS)
        + caps["FORCE_SCRIPT_BEAT_MAX"] * len(BEAT_LABELS)
        + caps["FORCE_SCRIPT_WATCH_MAX"] * len(WATCH_LABELS)
        + caps["FORCE_SCRIPT_PRED_MAX"] * len(PRED_LABELS)
        + caps["FORCE_SCRIPT_WHERE_MAX"] * len(WHERE_LABELS)
        + caps["FORCE_SCRIPT_SPAWN_MAX"] * len(TMPL_LABELS)
    )
    packed_bodies = CAP_MISSIONS * mission_cap
    directory = 1 + CAP_MISSIONS * (1 + stem_max + 2)
    cap_missions = packed_bodies + directory
    index = INDEX_FIXED + ENTRY_BYTES * CHUNK_COUNT

    tiles = bytes(need(labels, "rom_tiles"))
    paper = bytes(need(labels, "rom_paper"))
    tiles_lz = lzss.encode(tiles)
    paper_lz = lzss.encode(paper)
    _tile_flag, tiles_stored = gen_c64.stored_plane(tiles)
    _paper_flag, paper_stored = gen_c64.stored_plane(paper)

    raw_planes = len(tiles) + len(paper)
    raw_payload = index + geo_cap + cap_missions + raw_planes
    raw_end = LOAD + raw_payload
    farm_payload = index + geo_logical + farm_missions + len(tiles_stored) + len(paper_stored)
    farm_raw_payload = index + geo_logical + farm_missions + raw_planes
    cap_lz_payload = index + geo_cap + cap_missions + len(tiles_lz) + len(paper_lz)
    spare = MISSION_CEILING - (MISSION_HOME + cap_missions)

    tile_off = index + geo_logical + farm_missions
    paper_off = tile_off + len(tiles_stored)
    staged = 0
    if intersects_tile_dest(tile_off, len(tiles_stored)):
        staged += len(tiles_stored)
    if intersects_tile_dest(paper_off, len(paper_stored)):
        staged += len(paper_stored)

    def file_row(label: str, payload: int) -> str:
        end = LOAD + payload
        file_bytes = payload + 2
        margin = IO_PAGE - end
        return (
            f"  {label:<28} {payload:6d} {file_bytes:6d}  ${end:04X}"
            f"  {margin:6d}  {blocks_of(file_bytes):3d}"
        )

    lines = [
        "piece                          current     caps",
        f"  tiles plane                  {len(tiles):6d}   {PLANE_BYTES:6d}",
        f"  paper plane                  {len(paper):6d}   {PLANE_BYTES:6d}",
        f"  geometry logical             {geo_logical:6d}   {geo_cap:6d}",
        f"  geometry linked              {geo_linked:6d}",
        f"  mission tight                {mission_tight:6d}   {mission_cap:6d}",
        f"  mission home                          {mission_cap:6d}",
        f"  mission chunk (stem {stem})   {farm_missions:6d}   {cap_missions:6d}",
        "",
        "six missions at the caps",
        f"  packed bodies                {packed_bodies:6d}",
        f"  directory                    {directory:6d}",
        f"  mission chunk                {cap_missions:6d}",
        f"  geometry                     {geo_cap:6d}",
        f"  index                        {index:6d}",
        f"  raw planes                   {raw_planes:6d}",
        f"  one-shot payload raw         {raw_payload:6d}",
        f"  mission ceiling              ${MISSION_CEILING:04X}",
        f"  spare                        {spare:6d}",
        "",
        "lzss",
        f"  tiles                        {len(tiles_lz):6d}",
        f"  paper                        {len(paper_lz):6d}",
        f"  inside tile dest             {staged:6d}",
        "",
        "file                         payload  bytes     end  margin  blocks",
        file_row("farm raw logical", farm_raw_payload),
        file_row("farm lzss", farm_payload),
        file_row("six-mission cap raw", raw_payload),
        file_row("six-mission cap farm lzss", cap_lz_payload),
    ]
    print("\n".join(lines))

    failures: list[str] = []
    if raw_end >= IO_PAGE:
        failures.append(f"raw one-shot exclusive end ${raw_end:04X} >= $D000")
    if cap_missions > MISSION_CHUNK_MAX or MISSION_HOME + cap_missions > MISSION_CEILING:
        failures.append(
            f"mission chunk {cap_missions} exceeds {MISSION_CHUNK_MAX}"
            f" or ${MISSION_HOME:04X}+chunk exceeds ${MISSION_CEILING:04X}"
        )
    if geo_cap > GEO_IMAGE_MAX or MISSION_CEILING + GEO_IMAGE_MAX > CHARSET:
        failures.append(
            f"geometry image {geo_cap} exceeds {GEO_IMAGE_MAX}"
            f" or ${MISSION_CEILING:04X}+{GEO_IMAGE_MAX} exceeds ${CHARSET:04X}"
        )
    if len(tiles) != PLANE_BYTES or len(paper) != PLANE_BYTES:
        failures.append(f"raw planes are {len(tiles)} and {len(paper)}, expected {PLANE_BYTES}")
    if len(tiles_stored) > SCRATCH or len(paper_stored) > SCRATCH:
        failures.append(
            f"stored plane chunks {len(tiles_stored)} and {len(paper_stored)} exceed {SCRATCH}"
        )
    if staged > SCRATCH:
        failures.append(f"plane sources inside tile dest sum to {staged}, limit {SCRATCH}")
    for name, comp, raw in (("tiles", tiles_lz, tiles), ("paper", paper_lz, paper)):
        try:
            back = lzss.decode(comp, len(raw))
        except ValueError as exc:
            failures.append(f"{name} lzss: {exc}")
            continue
        if back != raw:
            failures.append(f"{name} lzss decode does not equal the raw plane")
    _end, bundle_problems = check_farm_bundle(labels, stem, tiles, paper)
    failures.extend(bundle_problems)
    if failures:
        for msg in failures:
            print(f"measure_c64_bundle: {msg}", file=sys.stderr)
        return 1
    print(f"bundle {BUNDLE_SHOWN} exclusive end ${_end:04X}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
