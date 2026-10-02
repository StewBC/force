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

# Reserved map layers. Any other name is a mission script stem.
LAYER_NAMES = ("color", "tiles", "properties", "rooms")
META_LAYERS = frozenset(("properties", "rooms"))
TILED_FLIP = 0xE0000000
IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
# Display titles peeled off mission lines, keyed by mission name.
MISSION_TITLE: dict[str, str] = {}

FORCE_ROOM_MAX = 16
FORCE_PORTAL_MAX = 24
FORCE_COVER_MAX = 128
FORCE_COVER_PER_ROOM = 24
FORCE_COVER_LIVE_MAX = 12
FORCE_SPAWN_MAX = 32
FORCE_UNIT_MAX = 32
FORCE_SECTION_MAX = 16
FORCE_LETTER_MAX = 8
assert FORCE_UNIT_MAX == FORCE_SPAWN_MAX
assert FORCE_SECTION_MAX == FORCE_LETTER_MAX * 2
FORCE_SCOUT_MAX = 32
FORCE_SCOUT_PER_ROOM = 4
FORCE_OBJECTIVE_MAX = 8
FORCE_MINE_MAX = 32

FORCE_SCRIPT_OPS_MAX = 64
FORCE_SCRIPT_WATCH_MAX = 8
FORCE_SCRIPT_BEAT_MAX = 12
FORCE_SCRIPT_PRED_MAX = 32
FORCE_SCRIPT_WHERE_MAX = 16
FORCE_SCRIPT_SPAWN_MAX = 8
FORCE_SCRIPT_NAME_MAX = 16  # 15 + NUL

FORCE_OP_NOP = 0
FORCE_OP_SPAWN = 1
FORCE_OP_ORDER = 2
FORCE_OP_SET_SPAWN = 3
FORCE_OP_APPROACH = 4
FORCE_OP_GOTO = 5
FORCE_OP_WAIT = 6
FORCE_OP_WIN = 7
FORCE_OP_LOSE = 8
FORCE_OP_RADIO = 9

FORCE_PRED_NONE = 0
FORCE_PRED_STR_EQ = 1
FORCE_PRED_STR_LE = 2
FORCE_PRED_IN_GE = 3
FORCE_PRED_REACHED = 4
FORCE_PRED_AT_CELL = 5
FORCE_PRED_CLOCK_GE = 6
FORCE_PRED_REL_GE = 7
FORCE_PRED_STR_GE = 8
FORCE_PRED_JOB_IDLE = 9

FORCE_WHERE_ROOM = 0
FORCE_WHERE_CELL = 1
FORCE_WHERE_PLAYER = 2
FORCE_WHERE_EXIT = 3

FORCE_SCRIPT_WHO_PLAYER = 0xFF
FORCE_SCRIPT_WATCH_ONCE = 0x01

FORCE_VERB_MOVE = 1
FORCE_VERB_DEFEND = 2
FORCE_VERB_HALT = 3
FORCE_VERB_ATTACK = 4
FORCE_VERB_RETREAT = 5

FORCE_APPROACH_N = 0x01
FORCE_APPROACH_E = 0x02
FORCE_APPROACH_S = 0x04
FORCE_APPROACH_W = 0x08

SCRIPT_VERBS = {
    "A": FORCE_VERB_ATTACK,
    "D": FORCE_VERB_DEFEND,
    "M": FORCE_VERB_MOVE,
    "H": FORCE_VERB_HALT,
    "R": FORCE_VERB_RETREAT,
}

APPROACH_BITS = {
    "N": FORCE_APPROACH_N,
    "E": FORCE_APPROACH_E,
    "S": FORCE_APPROACH_S,
    "W": FORCE_APPROACH_W,
}

PRED_STR_OPS = {
    "==": FORCE_PRED_STR_EQ,
    "<=": FORCE_PRED_STR_LE,
    ">=": FORCE_PRED_STR_GE,
}

FORCE_MAP_W_MAX = 80
FORCE_MAP_H_MAX = 50
FORCE_MAP_CELLS_MAX = 4000
assert FORCE_MAP_CELLS_MAX == FORCE_MAP_W_MAX * FORCE_MAP_H_MAX

# Tiles 0–127 are the playfield sheet (linked tileset and C64 charset).
# Tiles 128–159 are editor glyphs. Rooms use 128–142; 143–159 are illegal
# there. Properties may bind 128–159. The same id is a different mark on
# each layer. A map uses one room scheme, legacy 113–127 or editor 128–142.
RUNTIME_TILES = 128
EDITOR_ROOM_LAST = 142
EDITOR_PROP_LAST = 159
RESERVED_PROP_FIRST = 147

FORCE_FACE_NONE = 0
FORCE_FACE_N = 1
FORCE_FACE_E = 2
FORCE_FACE_S = 3
FORCE_FACE_W = 4

EXIT_FACES = {
    "exit-north": FORCE_FACE_N,
    "exit-east": FORCE_FACE_E,
    "exit-south": FORCE_FACE_S,
    "exit-west": FORCE_FACE_W,
}

FORCE_COVER_SOFT_N = 5
FORCE_COVER_SOFT_E = 6
FORCE_COVER_SOFT_S = 7
FORCE_COVER_SOFT_W = 8
FORCE_COVER_HARD_N = 9
FORCE_COVER_HARD_E = 10
FORCE_COVER_HARD_S = 11
FORCE_COVER_HARD_W = 12

FORCE_AXIS_NONE = 0
FORCE_AXIS_EW = 1
FORCE_AXIS_NS = 2

FACE_BYTES = {
    "none": FORCE_FACE_NONE,
    "n": FORCE_FACE_N,
    "e": FORCE_FACE_E,
    "s": FORCE_FACE_S,
    "w": FORCE_FACE_W,
}

COVER_SOFT_BYTES = {
    "n": FORCE_COVER_SOFT_N,
    "e": FORCE_COVER_SOFT_E,
    "s": FORCE_COVER_SOFT_S,
    "w": FORCE_COVER_SOFT_W,
}
COVER_HARD_BYTES = {
    "n": FORCE_COVER_HARD_N,
    "e": FORCE_COVER_HARD_E,
    "s": FORCE_COVER_HARD_S,
    "w": FORCE_COVER_HARD_W,
}


def cover_tag(fields: dict[str, str]) -> int:
    if "advancing" in fields:
        return FACE_BYTES[fields["advancing"]]
    if "soft" in fields:
        return COVER_SOFT_BYTES[fields["soft"]]
    return COVER_HARD_BYTES[fields["hard"]]


def cover_dir(tag: int) -> int:
    if tag >= FORCE_COVER_HARD_N:
        return tag - FORCE_COVER_HARD_N + FORCE_FACE_N
    if tag >= FORCE_COVER_SOFT_N:
        return tag - FORCE_COVER_SOFT_N + FORCE_FACE_N
    return tag


def cover_is_ew_dir(d: int) -> bool:
    return d in (FORCE_FACE_E, FORCE_FACE_W)


def cover_is_ns_dir(d: int) -> bool:
    return d in (FORCE_FACE_N, FORCE_FACE_S)


def cover_is_neutral(tag: int) -> bool:
    return tag >= FORCE_COVER_SOFT_N


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
        self.room_axis: list[int] = []
        self.room_cover_lo: list[int] = []
        self.room_cover_none: list[int] = []
        self.room_cover_hi: list[int] = []
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


# Mission row: name, map, x, y, w, h, script, cam_x, cam_y.
# cam is the opening window top-left. Omitted, it is the rect origin.


def _parse_cam(token: str, loc: str) -> tuple[int, int]:
    body = token[4:]
    nums = [p.strip() for p in body.split(",")]
    if len(nums) != 2 or nums[0] == "" or nums[1] == "":
        raise Error(f"{loc}: cam= must be x,y")
    try:
        cx, cy = (int(n) for n in nums)
    except ValueError as exc:
        raise Error(f"{loc}: bad cam=") from exc
    if cx < 0 or cy < 0:
        raise Error(f"{loc}: cam= must be non-negative")
    return cx, cy


def peel_title(line: str, loc: str) -> tuple[str, str | None]:
    """Take a trailing "title" off a mission line. The title may contain spaces."""
    if '"' not in line:
        return line, None
    first = line.find('"')
    second = line.find('"', first + 1)
    if second < 0:
        raise Error(f"{loc}: unterminated title")
    if line[second + 1 :].strip():
        raise Error(f"{loc}: title must be the last field")
    title = line[first + 1 : second]
    if not title or len(title) > 27:
        raise Error(f"{loc}: title must be 1..27 characters")
    if any(ord(ch) < 32 or ord(ch) > 126 for ch in title):
        raise Error(f"{loc}: title must be plain text")
    return line[:first].strip(), title


def load_missions(path: Path) -> list[tuple[str, str, int, int, int, int, str | None, int, int]]:
    missions: list[tuple[str, str, int, int, int, int, str | None, int, int]] = []
    seen: set[str] = set()
    MISSION_TITLE.clear()
    text = path.read_text(encoding="utf-8")
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = strip_comment(raw)
        if not line:
            continue
        loc = f"{path}:{lineno}"
        line, title = peel_title(line, loc)
        parts = line.split()
        if len(parts) < 3:
            raise Error(f"{loc}: expected 'name map x,y,w,h [script] [cam=x,y]'")
        name, map_name, rect = parts[0], parts[1], parts[2]
        script: str | None = None
        cam: tuple[int, int] | None = None
        for tok in parts[3:]:
            if tok.startswith("cam="):
                if cam is not None:
                    raise Error(f"{loc}: cam= repeated")
                cam = _parse_cam(tok, loc)
            else:
                if script is not None:
                    raise Error(f"{loc}: unexpected '{tok}'")
                script = tok
        if not IDENT_RE.match(name):
            raise Error(f"{loc}: bad mission name '{name}'")
        if not IDENT_RE.match(map_name):
            raise Error(f"{loc}: bad map name '{map_name}'")
        if script is not None and not IDENT_RE.match(script):
            raise Error(f"{loc}: bad script name '{script}'")
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
        if cam is None:
            cam = (x, y)
        seen.add(name)
        if title is None:
            title = name.replace("_", " ")
            if len(title) > 27:
                title = title[:27]
        MISSION_TITLE[name] = title
        missions.append((name, map_name, x, y, w, h, script, cam[0], cam[1]))
    if not missions:
        raise Error(f"{path}: no missions")
    return missions


class CompiledScript:
    def __init__(self, name: str, map_name: str) -> None:
        self.name = name
        self.map_name = map_name
        self.op_code: list[int] = []
        self.op_a: list[int] = []
        self.op_b: list[int] = []
        self.op_c: list[int] = []
        self.beat_pc: list[int] = []
        self.beat_name: list[str] = []
        self.watch_name: list[str] = []
        self.watch_pred0: list[int] = []
        self.watch_pred1: list[int] = []
        self.watch_op: list[int] = []
        self.watch_arg: list[int] = []
        self.watch_flags: list[int] = []
        self.pred_kind: list[int] = []
        self.pred_who: list[int] = []
        self.pred_a: list[int] = []
        self.pred_b: list[int] = []
        self.where_kind: list[int] = []
        self.where_a: list[int] = []
        self.where_b: list[int] = []
        self.spawn_n: list[int] = []
        self.spawn_letter: list[int] = []
        self.spawn_room: list[int] = []
        self.spawn_batch: list[int] = []
        self.spawn_period: list[int] = []
        self.start_spawn_room = 0
        self.start_beat = 0
        self.player_grenades = 0
        self.player_grenade_wait = 0
        self.enemy_grenades = 0
        self.enemy_grenade_wait = 0

    @property
    def op_count(self) -> int:
        return len(self.op_code)

    @property
    def beat_count(self) -> int:
        return len(self.beat_pc)

    @property
    def watch_count(self) -> int:
        return len(self.watch_op)

    @property
    def pred_count(self) -> int:
        return len(self.pred_kind)

    @property
    def where_count(self) -> int:
        return len(self.where_kind)

    @property
    def spawn_tmpl_count(self) -> int:
        return len(self.spawn_n)


def load_script(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise Error(f"{path.name}: not found") from exc


def compile_script(path: Path, compiled_map: CompiledMap) -> CompiledScript:
    return _ScriptCompiler(path, compiled_map).compile(load_script(path))


def _script_tokenize(line: str) -> list[str]:
    line = line.replace("->", " -> ")
    out: list[str] = []
    for tok in line.split():
        if tok != ":" and tok.endswith(":"):
            out.append(tok[:-1])
            out.append(":")
        else:
            out.append(tok)
    return out


def _is_room_name(tok: str) -> bool:
    if IDENT_RE.match(tok):
        return True
    return _parse_int_token(tok) is not None and not tok.startswith("-")


class _ScriptCompiler:
    def __init__(self, path: Path, compiled_map: CompiledMap) -> None:
        self.path = path
        self.map = compiled_map
        self.shown = path.name
        self.colour_index: dict[int, int] = {}
        for i, room in enumerate(compiled_map.rooms):
            self.colour_index[room.colour] = i
        self.aliases: dict[str, int] = {}
        self.out = CompiledScript(path.stem, compiled_map.name)
        self.beat_names: dict[str, int] = {}
        self.watch_names: set[str] = set()
        self.start_spawn_name: str | None = None
        self.start_spawn_loc: str | None = None
        self.grenade_seen: set[str] = set()

    def compile(self, text: str) -> CompiledScript:
        rooms_lines: list[tuple[str, list[str]]] = []
        spawn_lines: list[tuple[str, list[str]]] = []
        watch_lines: list[tuple[str, list[str]]] = []
        beats: list[tuple[str, str, list[tuple[str, list[str]]]]] = []
        cur_beat: tuple[str, str, list[tuple[str, list[str]]]] | None = None

        for lineno, raw in enumerate(text.splitlines(), 1):
            line = strip_comment(raw)
            if not line:
                continue
            loc = f"{self.shown}:{lineno}"
            tokens = _script_tokenize(line)
            if not tokens:
                continue
            head = tokens[0]
            if head == "wave":
                raise Error(f"{loc}: wave = is rejected")
            if head == "if_sometimes":
                raise Error(f"{loc}: if_sometimes is rejected")
            if head == "radio":
                raise Error(f"{loc}: radio is parked")
            if head == "room":
                rooms_lines.append((loc, tokens))
                continue
            if head == "spawn_room":
                spawn_lines.append((loc, tokens))
                continue
            if head in (
                "player_grenades",
                "player_grenade_wait",
                "enemy_grenades",
                "enemy_grenade_wait",
            ):
                if cur_beat is not None:
                    raise Error(f"{loc}: {head} belongs in the header")
                self._top_grenade(loc, tokens, head)
                continue
            if head == "watch":
                watch_lines.append((loc, tokens))
                continue
            if head == "beat":
                name = self._beat_header(loc, tokens)
                if name in self.beat_names:
                    raise Error(f"{loc}: beat '{name}' repeated")
                self._check_name(loc, name)
                self.beat_names[name] = len(beats)
                cur_beat = (loc, name, [])
                beats.append(cur_beat)
                continue
            if cur_beat is None:
                raise Error(
                    f"{loc}: expected room, spawn_room, grenade header, "
                    "watch, or beat"
                )
            cur_beat[2].append((loc, tokens))

        for loc, tokens in rooms_lines:
            self._define_room(loc, tokens)
        if len(spawn_lines) > 1:
            raise Error(f"{spawn_lines[1][0]}: spawn_room repeated")
        if spawn_lines:
            self._top_spawn_room(*spawn_lines[0])
        if not beats:
            raise Error(f"{self.shown}: zero beats")
        if len(beats) > FORCE_SCRIPT_BEAT_MAX:
            raise Error(
                f"{self.shown}: {len(beats)} beats > {FORCE_SCRIPT_BEAT_MAX}"
            )

        for loc, tokens in watch_lines:
            self._compile_watch(loc, tokens)
        for _bloc, bname, body in beats:
            self.out.beat_pc.append(self.out.op_count)
            self.out.beat_name.append(bname)
            for loc, tokens in body:
                self._compile_beat_line(loc, tokens)
        if self.out.op_count > FORCE_SCRIPT_OPS_MAX:
            raise Error(
                f"{self.shown}: {self.out.op_count} ops > {FORCE_SCRIPT_OPS_MAX}"
            )

        if self.start_spawn_name is not None:
            assert self.start_spawn_loc is not None
            self.out.start_spawn_room = self._room(
                self.start_spawn_loc, self.start_spawn_name
            )
        self.out.start_beat = 0
        return self.out

    def _check_name(self, loc: str, name: str) -> None:
        if len(name) > FORCE_SCRIPT_NAME_MAX - 1:
            raise Error(f"{loc}: name '{name}' longer than 15")

    def _need_int(self, loc: str, tok: str, lo: int, hi: int) -> int:
        n = _parse_int_token(tok)
        if n is None:
            raise Error(f"{loc}: expected integer, got '{tok}'")
        if n < lo or n > hi:
            raise Error(f"{loc}: {n} out of range {lo}..{hi}")
        return n

    def _u8(self, loc: str, tok: str) -> int:
        return self._need_int(loc, tok, 0, 255)

    def _u8_nz(self, loc: str, tok: str) -> int:
        n = self._u8(loc, tok)
        if n == 0:
            raise Error(f"{loc}: expected non-zero")
        return n

    def _letter(self, loc: str, tok: str) -> int:
        if len(tok) != 1 or tok < "A" or tok > "H":
            raise Error(f"{loc}: letter '{tok}' is not A-H")
        return ord(tok) - ord("A") + FORCE_LETTER_MAX

    def _room(self, loc: str, name: str) -> int:
        if name in self.aliases:
            return self.aliases[name]
        n = _parse_int_token(name)
        if n is None or name.startswith("-"):
            raise Error(f"{loc}: unknown room '{name}'")
        if n not in self.colour_index:
            raise Error(
                f"{loc}: room {name}: colour {n} not on {self.map.name}"
            )
        return self.colour_index[n]

    def _define_room(self, loc: str, tokens: list[str]) -> None:
        if (
            len(tokens) != 5
            or tokens[2] != "="
            or tokens[3] != "colour"
        ):
            raise Error(f"{loc}: expected 'room <name> = colour <1-15>'")
        name = tokens[1]
        if not _is_room_name(name):
            raise Error(f"{loc}: bad room name '{name}'")
        self._check_name(loc, name)
        if name in self.aliases:
            raise Error(f"{loc}: room '{name}' repeated")
        colour = self._need_int(loc, tokens[4], 1, 15)
        if colour not in self.colour_index:
            raise Error(
                f"{loc}: room {name}: colour {colour} not on {self.map.name}"
            )
        self.aliases[name] = self.colour_index[colour]

    def _top_spawn_room(self, loc: str, tokens: list[str]) -> None:
        if len(tokens) != 2:
            raise Error(f"{loc}: expected 'spawn_room <name>'")
        self.start_spawn_name = tokens[1]
        self.start_spawn_loc = loc

    def _top_grenade(self, loc: str, tokens: list[str], field: str) -> None:
        if len(tokens) != 2:
            raise Error(f"{loc}: expected '{field} <0-255>'")
        if field in self.grenade_seen:
            raise Error(f"{loc}: {field} repeated")
        self.grenade_seen.add(field)
        setattr(self.out, field, self._u8(loc, tokens[1]))

    def _beat_header(self, loc: str, tokens: list[str]) -> str:
        if len(tokens) != 3 or tokens[2] != ":":
            raise Error(f"{loc}: expected 'beat <name>:'")
        name = tokens[1]
        if not IDENT_RE.match(name):
            raise Error(f"{loc}: bad beat name '{name}'")
        return name

    def _emit_pred(self, kind: int, who: int, a: int, b: int) -> int:
        if len(self.out.pred_kind) >= FORCE_SCRIPT_PRED_MAX:
            raise Error(
                f"{self.shown}: {len(self.out.pred_kind) + 1} preds > "
                f"{FORCE_SCRIPT_PRED_MAX}"
            )
        self.out.pred_kind.append(kind)
        self.out.pred_who.append(who)
        self.out.pred_a.append(a)
        self.out.pred_b.append(b)
        return len(self.out.pred_kind) - 1

    def _emit_where(self, kind: int, a: int, b: int) -> int:
        if len(self.out.where_kind) >= FORCE_SCRIPT_WHERE_MAX:
            raise Error(
                f"{self.shown}: {len(self.out.where_kind) + 1} wheres > "
                f"{FORCE_SCRIPT_WHERE_MAX}"
            )
        self.out.where_kind.append(kind)
        self.out.where_a.append(a)
        self.out.where_b.append(b)
        return len(self.out.where_kind) - 1

    def _emit_spawn(
        self, n: int, letter: int, room: int, batch: int, period: int
    ) -> int:
        if len(self.out.spawn_n) >= FORCE_SCRIPT_SPAWN_MAX:
            raise Error(
                f"{self.shown}: {len(self.out.spawn_n) + 1} spawn templates > "
                f"{FORCE_SCRIPT_SPAWN_MAX}"
            )
        self.out.spawn_n.append(n)
        self.out.spawn_letter.append(letter)
        self.out.spawn_room.append(room)
        self.out.spawn_batch.append(batch)
        self.out.spawn_period.append(period)
        return len(self.out.spawn_n) - 1

    def _emit_op(self, code: int, a: int, b: int, c: int) -> None:
        if len(self.out.op_code) >= FORCE_SCRIPT_OPS_MAX:
            raise Error(
                f"{self.shown}: {len(self.out.op_code) + 1} ops > "
                f"{FORCE_SCRIPT_OPS_MAX}"
            )
        self.out.op_code.append(code)
        self.out.op_a.append(a)
        self.out.op_b.append(b)
        self.out.op_c.append(c)

    def _parse_xy(self, loc: str, tokens: list[str], i: int) -> tuple[int, int, int]:
        if i >= len(tokens):
            raise Error(f"{loc}: expected x,y")
        t = tokens[i]
        if "," not in t:
            raise Error(f"{loc}: expected x,y, got '{t}'")
        left, right = t.split(",", 1)
        if left == "" or right == "":
            raise Error(f"{loc}: expected x,y, got '{t}'")
        x = self._need_int(loc, left, 0, 255)
        y = self._need_int(loc, right, 0, 255)
        return x, y, i + 1

    def _check_cell(self, loc: str, x: int, y: int) -> None:
        if x >= self.map.width or y >= self.map.height:
            raise Error(
                f"{loc}: cell {x},{y} outside {self.map.name} "
                f"{self.map.width}x{self.map.height}"
            )

    def _parse_bits(self, loc: str, tok: str) -> int:
        bits = 0
        for part in tok.split("|"):
            if part not in APPROACH_BITS:
                raise Error(f"{loc}: bad approach '{tok}'")
            bits |= APPROACH_BITS[part]
        if bits == 0:
            raise Error(f"{loc}: bad approach '{tok}'")
        return bits

    def _parse_pred(
        self, loc: str, tokens: list[str], i: int, *, allow_job: bool
    ) -> tuple[int, int]:
        if i >= len(tokens):
            raise Error(f"{loc}: expected predicate")
        t = tokens[i]
        if t == "job":
            if i + 1 >= len(tokens) or tokens[i + 1] != "idle":
                raise Error(f"{loc}: expected 'job idle'")
            if not allow_job:
                raise Error(f"{loc}: job idle is illegal on a watcher")
            idx = self._emit_pred(FORCE_PRED_JOB_IDLE, 0, 0, 0)
            return idx, i + 2
        if t == "clock":
            if i + 2 >= len(tokens) or tokens[i + 1] != ">=":
                raise Error(f"{loc}: expected 'clock >= <n>'")
            n = self._need_int(loc, tokens[i + 2], 0, 65535)
            idx = self._emit_pred(
                FORCE_PRED_CLOCK_GE, 0, n & 0xFF, (n >> 8) & 0xFF
            )
            return idx, i + 3
        if t == "player.strength":
            if i + 2 >= len(tokens) or tokens[i + 1] not in PRED_STR_OPS:
                raise Error(f"{loc}: expected player.strength ==/<=/>= <n>")
            n = self._u8(loc, tokens[i + 2])
            idx = self._emit_pred(
                PRED_STR_OPS[tokens[i + 1]], FORCE_SCRIPT_WHO_PLAYER, n, 0
            )
            return idx, i + 3
        if t == "player.in":
            if i + 3 >= len(tokens) or tokens[i + 2] != ">=":
                raise Error(f"{loc}: expected 'player.in <room> >= ...'")
            room = self._room(loc, tokens[i + 1])
            if tokens[i + 3] == "enemy.in":
                if i + 4 >= len(tokens):
                    raise Error(f"{loc}: expected room after enemy.in")
                room2 = self._room(loc, tokens[i + 4])
                if room2 != room:
                    raise Error(f"{loc}: player.in / enemy.in rooms differ")
                idx = self._emit_pred(FORCE_PRED_REL_GE, 0, room, 0)
                return idx, i + 5
            n = self._u8(loc, tokens[i + 3])
            idx = self._emit_pred(
                FORCE_PRED_IN_GE, FORCE_SCRIPT_WHO_PLAYER, room, n
            )
            return idx, i + 4
        if t.endswith(".strength") and t != ".strength":
            letter = self._letter(loc, t[: -len(".strength")])
            if i + 2 >= len(tokens) or tokens[i + 1] not in PRED_STR_OPS:
                raise Error(f"{loc}: expected <letter>.strength ==/<=/>= <n>")
            n = self._u8(loc, tokens[i + 2])
            idx = self._emit_pred(PRED_STR_OPS[tokens[i + 1]], letter, n, 0)
            return idx, i + 3
        if t.endswith(".in") and t != ".in":
            letter = self._letter(loc, t[: -len(".in")])
            if i + 3 >= len(tokens) or tokens[i + 2] != ">=":
                raise Error(f"{loc}: expected <letter>.in <room> >= <n>")
            room = self._room(loc, tokens[i + 1])
            n = self._u8(loc, tokens[i + 3])
            idx = self._emit_pred(FORCE_PRED_IN_GE, letter, room, n)
            return idx, i + 4
        if len(t) == 1 and "A" <= t <= "H":
            if i + 1 < len(tokens) and tokens[i + 1] == "in":
                if i + 2 >= len(tokens):
                    raise Error(f"{loc}: expected room")
                letter = self._letter(loc, t)
                room = self._room(loc, tokens[i + 2])
                idx = self._emit_pred(FORCE_PRED_REACHED, letter, room, 0)
                return idx, i + 3
            if i + 1 < len(tokens) and tokens[i + 1] == "at":
                letter = self._letter(loc, t)
                x, y, ni = self._parse_xy(loc, tokens, i + 2)
                self._check_cell(loc, x, y)
                idx = self._emit_pred(FORCE_PRED_AT_CELL, letter, x, y)
                return idx, ni
        raise Error(f"{loc}: bad predicate '{t}'")

    def _parse_pred_pair(
        self, loc: str, tokens: list[str], i: int, *, allow_job: bool
    ) -> tuple[int, int, int]:
        p0, i = self._parse_pred(loc, tokens, i, allow_job=allow_job)
        p1 = 0xFF
        if i < len(tokens) and tokens[i] == "and":
            p1, i = self._parse_pred(loc, tokens, i + 1, allow_job=allow_job)
            if i < len(tokens) and tokens[i] == "and":
                raise Error(f"{loc}: third and")
        return p0, p1, i

    def _parse_where(
        self, loc: str, tokens: list[str], i: int
    ) -> tuple[int, int]:
        if i >= len(tokens):
            raise Error(f"{loc}: expected where")
        t = tokens[i]
        if t == "room":
            if i + 1 >= len(tokens):
                raise Error(f"{loc}: expected room name")
            room = self._room(loc, tokens[i + 1])
            return self._emit_where(FORCE_WHERE_ROOM, room, 0), i + 2
        if t == "cell":
            x, y, ni = self._parse_xy(loc, tokens, i + 1)
            self._check_cell(loc, x, y)
            return self._emit_where(FORCE_WHERE_CELL, x, y), ni
        if t == "player":
            return self._emit_where(FORCE_WHERE_PLAYER, 0, 0), i + 1
        if t in EXIT_FACES:
            return self._emit_where(FORCE_WHERE_EXIT, EXIT_FACES[t], 0), i + 1
        raise Error(f"{loc}: bad where '{t}'")

    def _parse_verb(self, loc: str, tok: str) -> int:
        if tok == "K":
            raise Error(f"{loc}: K is the human edge")
        if tok not in SCRIPT_VERBS:
            raise Error(f"{loc}: unknown verb '{tok}'")
        return SCRIPT_VERBS[tok]

    def _parse_spawn(self, loc: str, tokens: list[str], i: int) -> tuple[int, int]:
        if i + 1 >= len(tokens):
            raise Error(f"{loc}: expected 'spawn <n> <letter>'")
        n = self._u8_nz(loc, tokens[i])
        letter = self._letter(loc, tokens[i + 1])
        i = i + 2
        room = 0xFF
        batch = n
        period = 1
        while i < len(tokens):
            t = tokens[i]
            if t == "in":
                if i + 1 >= len(tokens):
                    raise Error(f"{loc}: expected room after in")
                if tokens[i + 1] == "spawn_room":
                    room = 0xFF
                else:
                    room = self._room(loc, tokens[i + 1])
                i += 2
            elif t == "batch":
                if i + 1 >= len(tokens):
                    raise Error(f"{loc}: expected batch")
                batch = self._u8_nz(loc, tokens[i + 1])
                i += 2
            elif t == "period":
                if i + 1 >= len(tokens):
                    raise Error(f"{loc}: expected period")
                period = self._u8_nz(loc, tokens[i + 1])
                i += 2
            else:
                break
        return self._emit_spawn(n, letter, room, batch, period), i

    def _parse_order(self, loc: str, tokens: list[str], i: int) -> tuple[int, int]:
        if i + 1 >= len(tokens):
            raise Error(f"{loc}: expected 'order <letter> <verb> <where> force <0-10>'")
        letter = self._letter(loc, tokens[i])
        verb = self._parse_verb(loc, tokens[i + 1])
        where, i = self._parse_where(loc, tokens, i + 2)
        if i >= len(tokens) or tokens[i] != "force":
            raise Error(f"{loc}: order requires force <0-10>")
        if i + 1 >= len(tokens):
            raise Error(f"{loc}: order requires force <0-10>")
        force = self._need_int(loc, tokens[i + 1], 0, 10)
        packed = verb | (force << 4)
        self._emit_op(FORCE_OP_ORDER, letter, packed, where)
        return 0, i + 2

    def _parse_watch_action(
        self, loc: str, tokens: list[str]
    ) -> tuple[int, int]:
        if not tokens:
            raise Error(f"{loc}: expected watcher action")
        t = tokens[0]
        if t == "order":
            raise Error(f"{loc}: watchers may not order")
        if t == "spawn":
            raise Error(f"{loc}: watchers may not spawn")
        if t == "wait":
            raise Error(f"{loc}: wait is a beat action")
        if t == "win":
            if len(tokens) != 1:
                raise Error(f"{loc}: extra tokens after win")
            return FORCE_OP_WIN, 0
        if t == "lose":
            if len(tokens) != 1:
                raise Error(f"{loc}: extra tokens after lose")
            return FORCE_OP_LOSE, 0
        if t == "set":
            if len(tokens) != 3 or tokens[1] != "spawn_room":
                raise Error(f"{loc}: expected 'set spawn_room <room>'")
            return FORCE_OP_SET_SPAWN, self._room(loc, tokens[2])
        if t == "approach":
            if len(tokens) != 3:
                raise Error(f"{loc}: expected 'approach <room> <bits>'")
            room = self._room(loc, tokens[1])
            bits = self._parse_bits(loc, tokens[2])
            if room > 15 or bits > 15:
                raise Error(f"{loc}: approach packing overflow")
            return FORCE_OP_APPROACH, (bits << 4) | room
        if t == "goto":
            if len(tokens) != 2:
                raise Error(f"{loc}: expected 'goto <beat>'")
            beat = tokens[1]
            if beat not in self.beat_names:
                raise Error(f"{loc}: unknown beat '{beat}'")
            return FORCE_OP_GOTO, self.beat_names[beat]
        if t == "radio":
            raise Error(f"{loc}: radio is parked")
        raise Error(f"{loc}: unknown watcher action '{t}'")

    def _compile_watch(self, loc: str, tokens: list[str]) -> None:
        if len(tokens) < 5 or tokens[2] != ":":
            raise Error(f"{loc}: expected 'watch <name>: <pred> -> <action>'")
        name = tokens[1]
        if not IDENT_RE.match(name):
            raise Error(f"{loc}: bad watch name '{name}'")
        self._check_name(loc, name)
        if name in self.watch_names:
            raise Error(f"{loc}: watch '{name}' repeated")
        self.watch_names.add(name)
        if "->" not in tokens:
            raise Error(f"{loc}: expected ->")
        arrow = tokens.index("->")
        p0, p1, ni = self._parse_pred_pair(
            loc, tokens, 3, allow_job=False
        )
        if ni != arrow:
            raise Error(f"{loc}: extra tokens in predicate")
        action_toks = tokens[arrow + 1 :]
        once = False
        if action_toks and action_toks[-1] == "once":
            once = True
            action_toks = action_toks[:-1]
        op, arg = self._parse_watch_action(loc, action_toks)
        flags = 0
        if op not in (FORCE_OP_WIN, FORCE_OP_LOSE) or once:
            flags = FORCE_SCRIPT_WATCH_ONCE
        if len(self.out.watch_op) >= FORCE_SCRIPT_WATCH_MAX:
            raise Error(
                f"{self.shown}: {len(self.out.watch_op) + 1} watchers > "
                f"{FORCE_SCRIPT_WATCH_MAX}"
            )
        self.out.watch_name.append(name)
        self.out.watch_pred0.append(p0)
        self.out.watch_pred1.append(p1)
        self.out.watch_op.append(op)
        self.out.watch_arg.append(arg)
        self.out.watch_flags.append(flags)

    def _compile_beat_line(self, loc: str, tokens: list[str]) -> None:
        head = tokens[0]
        if head == "wait":
            if "->" not in tokens:
                raise Error(f"{loc}: expected ->")
            arrow = tokens.index("->")
            p0, p1, ni = self._parse_pred_pair(
                loc, tokens, 1, allow_job=True
            )
            if ni != arrow:
                raise Error(f"{loc}: extra tokens in predicate")
            if arrow + 1 >= len(tokens) or arrow + 2 != len(tokens):
                raise Error(f"{loc}: wait names one beat")
            dest = tokens[arrow + 1]
            if dest not in self.beat_names:
                raise Error(f"{loc}: unknown beat '{dest}'")
            self._emit_op(
                FORCE_OP_WAIT, p0, p1, self.beat_names[dest]
            )
            return
        if head == "spawn":
            tmpl, i = self._parse_spawn(loc, tokens, 1)
            if i != len(tokens):
                raise Error(f"{loc}: extra tokens after spawn")
            self._emit_op(FORCE_OP_SPAWN, tmpl, 0, 0)
            return
        if head == "order":
            _, i = self._parse_order(loc, tokens, 1)
            if i != len(tokens):
                raise Error(f"{loc}: extra tokens after order")
            return
        if head == "set":
            if len(tokens) != 3 or tokens[1] != "spawn_room":
                raise Error(f"{loc}: expected 'set spawn_room <room>'")
            room = self._room(loc, tokens[2])
            self._emit_op(FORCE_OP_SET_SPAWN, room, 0, 0)
            return
        if head == "approach":
            if len(tokens) != 3:
                raise Error(f"{loc}: expected 'approach <room> <bits>'")
            room = self._room(loc, tokens[1])
            bits = self._parse_bits(loc, tokens[2])
            self._emit_op(FORCE_OP_APPROACH, room, bits, 0)
            return
        if head == "goto":
            if len(tokens) != 2:
                raise Error(f"{loc}: expected 'goto <beat>'")
            dest = tokens[1]
            if dest not in self.beat_names:
                raise Error(f"{loc}: unknown beat '{dest}'")
            self._emit_op(FORCE_OP_GOTO, self.beat_names[dest], 0, 0)
            return
        if head == "win":
            if len(tokens) != 1:
                raise Error(f"{loc}: extra tokens after win")
            self._emit_op(FORCE_OP_WIN, 0, 0, 0)
            return
        if head == "lose":
            if len(tokens) != 1:
                raise Error(f"{loc}: extra tokens after lose")
            self._emit_op(FORCE_OP_LOSE, 0, 0, 0)
            return
        if head == "radio":
            raise Error(f"{loc}: radio is parked")
        if head == "if_sometimes":
            raise Error(f"{loc}: if_sometimes is rejected")
        raise Error(f"{loc}: unknown action '{head}'")


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
        extra = set(fields) - {"grade", "advancing", "soft", "hard"}
        if extra:
            raise Error(f"{loc}: unknown key '{sorted(extra)[0]}'")
        if "grade" not in fields:
            raise Error(f"{loc}: missing grade")
        if fields["grade"] not in {"1", "2", "3"}:
            raise Error(f"{loc}: bad grade '{fields['grade']}'")
        roles = [k for k in ("advancing", "soft", "hard") if k in fields]
        if len(roles) != 1:
            raise Error(f"{loc}: cover needs exactly one of advancing=/soft=/hard=")
        role = roles[0]
        if fields[role] not in {"n", "e", "s", "w"}:
            raise Error(f"{loc}: bad {role} '{fields[role]}'")
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
            legacy = 113 <= chip_id <= 127
            editor = 128 <= chip_id <= EDITOR_PROP_LAST
            if not legacy and not editor:
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
        # Editor glyphs are not playfield art and are not 2-wide.
        if tid >= RUNTIME_TILES:
            continue
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


def spawn_layers_for_map(
    missions: list[tuple[str, str, int, int, int, int, str | None, int, int]],
    map_name: str,
) -> tuple[list[str], str | None]:
    # Catalog order. The display name is not a layer; the script stem is.
    # The first row's stem is the plane compiled into the map spawn SoA.
    stems: list[str] = []
    seen: set[str] = set()
    first: str | None = None
    saw = False
    for _name, mname, _x, _y, _w, _h, stem, _cx, _cy in missions:
        if mname != map_name:
            continue
        if not saw:
            first = stem
            saw = True
        if stem is None or stem in seen:
            continue
        seen.add(stem)
        stems.append(stem)
    return stems, first


def load_tmx(
    path: Path,
    tile_count: int,
    empty_tile: int,
    spawn_stems: list[str],
) -> tuple[str, int, int, dict[str, list[int | None]], int]:
    root = ET.parse(path).getroot()
    width = int(root.attrib["width"])
    height = int(root.attrib["height"])
    ts = root.find("tileset")
    if ts is None:
        raise Error(f"{path}: no tileset")
    firstgid = int(ts.attrib["firstgid"])
    spawn_set = set(spawn_stems)
    planes: dict[str, list[int | None]] = {}
    for layer in root.findall("layer"):
        name = layer.attrib.get("name", "")
        if name in planes:
            raise Error(f"{path}: duplicate layer '{name}'")
        data = layer.find("data")
        if data is None or data.attrib.get("encoding") != "csv":
            raise Error(f"{path}: layer '{name}' is not CSV")
        loc = f"{path} layer '{name}'"
        gids = parse_csv_cells(data.text or "", width, height, loc)
        tids = [gid_to_tid(g, firstgid, tile_count, loc) for g in gids]
        if name in META_LAYERS or name in spawn_set:
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
    unknown = set(planes) - set(LAYER_NAMES) - spawn_set
    if unknown:
        raise Error(f"{path}: unknown layer(s) {sorted(unknown)}")
    missing = [name for name in spawn_stems if name not in planes]
    if missing:
        raise Error(f"{path}: missing layer(s) {sorted(set(missing))}")
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


def room_chip(tid: int) -> tuple[int, str] | None:
    """Colour 1–15 and which chip row it came from. None if not a room chip."""
    if 113 <= tid <= 127:
        return tid - 112, "legacy"
    if 128 <= tid <= EDITOR_ROOM_LAST:
        return tid - 127, "editor"
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
    scheme: str | None = None
    for y in range(height):
        for x in range(width):
            cell = plane[y * width + x]
            if skip_meta(cell, empty_tile):
                continue
            tid = cell
            parsed = room_chip(tid)
            if parsed is None:
                if EDITOR_ROOM_LAST < tid <= EDITOR_PROP_LAST:
                    raise Error(
                        f"{map_name} rooms ({x},{y}): {painted_tile(tid, firstgid)} "
                        "is not a room colour (143-159 are illegal on rooms)"
                    )
                raise Error(
                    f"{map_name} rooms ({x},{y}): {painted_tile(tid, firstgid)} "
                    "is not a colour chip"
                )
            colour, kind = parsed
            if scheme is None:
                scheme = kind
            elif scheme != kind:
                raise Error(
                    f"{map_name} rooms ({x},{y}): mixed legacy colour chips "
                    "(113-127) and editor colour chips (128-142)"
                )
            buckets[colour].append((x, y))
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
                if RESERVED_PROP_FIRST <= tid <= EDITOR_PROP_LAST:
                    raise Error(
                        f"{map_name} properties ({x},{y}): "
                        f"{painted_tile(tid, firstgid)} is reserved "
                        "(147-159 are unbound)"
                    )
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
                        cover_tag(preset.fields),
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
        chips = cover_by_room[i]
        seen: set[tuple[int, int]] = set()
        for x, y, _grade, _adv in chips:
            if (x, y) in seen:
                raise Error(
                    f"{map_name} cover ({x},{y}): two chips in room colour "
                    f"{room.colour}"
                )
            seen.add((x, y))

        dirs = [cover_dir(a) for *_, a in chips]
        has_ew = any(cover_is_ew_dir(d) for d in dirs)
        has_ns = any(cover_is_ns_dir(d) for d in dirs)
        if has_ew and has_ns:
            raise Error(
                f"{map_name} room colour {room.colour}: "
                f"mixed E-W and N-S cover"
            )
        if has_ew:
            axis = FORCE_AXIS_EW
            lo_face, hi_face = FORCE_FACE_E, FORCE_FACE_W
        elif has_ns:
            axis = FORCE_AXIS_NS
            lo_face, hi_face = FORCE_FACE_N, FORCE_FACE_S
        else:
            axis = FORCE_AXIS_NONE
            lo_face, hi_face = -1, -1

        lo = [
            c
            for c in chips
            if not cover_is_neutral(c[3]) and cover_dir(c[3]) == lo_face
        ]
        none = [c for c in chips if cover_is_neutral(c[3])]
        hi = [
            c
            for c in chips
            if not cover_is_neutral(c[3]) and cover_dir(c[3]) == hi_face
        ]
        n_lo, n_none, n_hi = len(lo), len(none), len(hi)
        if n_lo + n_none > FORCE_COVER_LIVE_MAX:
            ox, oy = (lo + none)[FORCE_COVER_LIVE_MAX][0:2]
            raise Error(
                f"{map_name} cover ({ox},{oy}): {n_lo + n_none} live "
                f"(lo+none) in room colour {room.colour} "
                f"> {FORCE_COVER_LIVE_MAX}"
            )
        if n_hi + n_none > FORCE_COVER_LIVE_MAX:
            ox, oy = (hi + none)[FORCE_COVER_LIVE_MAX][0:2]
            raise Error(
                f"{map_name} cover ({ox},{oy}): {n_hi + n_none} live "
                f"(hi+none) in room colour {room.colour} "
                f"> {FORCE_COVER_LIVE_MAX}"
            )
        packed = lo + none + hi
        n_cover = len(packed)
        n_scout = len(scout_by_room[i])
        if n_cover > FORCE_COVER_PER_ROOM:
            ox, oy = packed[FORCE_COVER_PER_ROOM][0:2]
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
        compiled.room_axis.append(axis)
        compiled.room_cover_lo.append(n_lo)
        compiled.room_cover_none.append(n_none)
        compiled.room_cover_hi.append(n_hi)
        compiled.room_scout_base.append(running_scout)
        compiled.room_scout_count.append(n_scout)
        for x, y, grade, advancing in packed:
            _append_capped(
                map_name,
                "cover",
                compiled.cover_x,
                compiled.cover_y,
                x,
                y,
                FORCE_COVER_MAX,
                extra=[compiled.cover_grade, compiled.cover_facing],
                extra_vals=[grade, advancing],
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
    layer: str,
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
                    f"{map_name} {layer} ({x},{y}): {painted_tile(tid, firstgid)} "
                    f"class {cls_name} is not a spawn"
                )
            if room_index_containing(compiled.rooms, x, y) is None:
                raise Error(
                    f"{map_name} {layer} ({x},{y}): spawn outside any room"
                )
            if len(compiled.spawn_x) >= FORCE_SPAWN_MAX:
                raise Error(
                    f"{map_name}: {len(compiled.spawn_x) + 1} spawns > "
                    f"{FORCE_SPAWN_MAX}"
                )
            compiled.spawn_x.append(x)
            compiled.spawn_y.append(y)
            compiled.spawn_tile.append(tid)


def reject_editor_paint(
    map_name: str,
    layer: str,
    plane: list[int | None],
    width: int,
) -> None:
    """Tiles 128+ belong on rooms and properties, not on a drawn or spawn layer."""
    for i, cell in enumerate(plane):
        if cell is None or cell < RUNTIME_TILES:
            continue
        x, y = i % width, i // width
        raise Error(
            f"{map_name} {layer} ({x},{y}): tile {cell} is editor-only"
        )


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
    spawn_layer: str | None = None,
) -> CompiledMap:
    for layer, plane in planes.items():
        if layer in ("rooms", "properties"):
            continue
        reject_editor_paint(name, layer, plane, width)
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
    # First catalog row only. No stem means no opening stamps, even if a
    # later mission on this map has its own layer.
    if spawn_layer is not None:
        extract_spawns(
            compiled,
            planes[spawn_layer],
            firstgid,
            empty_tile,
            class_table,
            classes,
            spawn_layer,
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


def emit_str_ptr_array(sym: str, values: list[str]) -> str:
    body = ", ".join(f'"{v}"' for v in values)
    return (
        f"static const char *const {sym}[{len(values)}] = {{ {body} }};\n\n"
    )


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
        chunks.append(emit_u8_array(f"{sym}_room_axis", compiled.room_axis))
        chunks.append(
            emit_u8_array(f"{sym}_room_cover_lo", compiled.room_cover_lo)
        )
        chunks.append(
            emit_u8_array(f"{sym}_room_cover_none", compiled.room_cover_none)
        )
        chunks.append(
            emit_u8_array(f"{sym}_room_cover_hi", compiled.room_cover_hi)
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
        f"    .room_axis = {_c_ptr(f'{sym}_room_axis', room_count)},\n"
        f"    .room_cover_lo = {_c_ptr(f'{sym}_room_cover_lo', room_count)},\n"
        f"    .room_cover_none = {_c_ptr(f'{sym}_room_cover_none', room_count)},\n"
        f"    .room_cover_hi = {_c_ptr(f'{sym}_room_cover_hi', room_count)},\n"
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


def emit_script_arrays(sym: str, sc: CompiledScript) -> str:
    chunks: list[str] = []
    if sc.op_count:
        chunks.append(emit_u8_array(f"{sym}_op_code", sc.op_code))
        chunks.append(emit_u8_array(f"{sym}_op_a", sc.op_a))
        chunks.append(emit_u8_array(f"{sym}_op_b", sc.op_b))
        chunks.append(emit_u8_array(f"{sym}_op_c", sc.op_c))
    if sc.beat_count:
        chunks.append(emit_u8_array(f"{sym}_beat_pc", sc.beat_pc))
        chunks.append(emit_str_ptr_array(f"{sym}_beat_name", sc.beat_name))
    if sc.watch_count:
        chunks.append(emit_str_ptr_array(f"{sym}_watch_name", sc.watch_name))
        chunks.append(emit_u8_array(f"{sym}_watch_pred0", sc.watch_pred0))
        chunks.append(emit_u8_array(f"{sym}_watch_pred1", sc.watch_pred1))
        chunks.append(emit_u8_array(f"{sym}_watch_op", sc.watch_op))
        chunks.append(emit_u8_array(f"{sym}_watch_arg", sc.watch_arg))
        chunks.append(emit_u8_array(f"{sym}_watch_flags", sc.watch_flags))
    if sc.pred_count:
        chunks.append(emit_u8_array(f"{sym}_pred_kind", sc.pred_kind))
        chunks.append(emit_u8_array(f"{sym}_pred_who", sc.pred_who))
        chunks.append(emit_u8_array(f"{sym}_pred_a", sc.pred_a))
        chunks.append(emit_u8_array(f"{sym}_pred_b", sc.pred_b))
    if sc.where_count:
        chunks.append(emit_u8_array(f"{sym}_where_kind", sc.where_kind))
        chunks.append(emit_u8_array(f"{sym}_where_a", sc.where_a))
        chunks.append(emit_u8_array(f"{sym}_where_b", sc.where_b))
    if sc.spawn_tmpl_count:
        chunks.append(emit_u8_array(f"{sym}_spawn_n", sc.spawn_n))
        chunks.append(emit_u8_array(f"{sym}_spawn_letter", sc.spawn_letter))
        chunks.append(emit_u8_array(f"{sym}_spawn_room", sc.spawn_room))
        chunks.append(emit_u8_array(f"{sym}_spawn_batch", sc.spawn_batch))
        chunks.append(emit_u8_array(f"{sym}_spawn_period", sc.spawn_period))
    return "".join(chunks)


def emit_script_init(sym: str, sc: CompiledScript) -> str:
    return (
        f"const force_script {sym} = {{\n"
        f'    .name = "{sc.name}",\n'
        f"    .op_count = {sc.op_count},\n"
        f"    .op_code = {_c_ptr(f'{sym}_op_code', sc.op_count)},\n"
        f"    .op_a = {_c_ptr(f'{sym}_op_a', sc.op_count)},\n"
        f"    .op_b = {_c_ptr(f'{sym}_op_b', sc.op_count)},\n"
        f"    .op_c = {_c_ptr(f'{sym}_op_c', sc.op_count)},\n"
        f"    .beat_count = {sc.beat_count},\n"
        f"    .beat_pc = {_c_ptr(f'{sym}_beat_pc', sc.beat_count)},\n"
        f"    .beat_name = {_c_ptr(f'{sym}_beat_name', sc.beat_count)},\n"
        f"    .watch_count = {sc.watch_count},\n"
        f"    .watch_name = {_c_ptr(f'{sym}_watch_name', sc.watch_count)},\n"
        f"    .watch_pred0 = {_c_ptr(f'{sym}_watch_pred0', sc.watch_count)},\n"
        f"    .watch_pred1 = {_c_ptr(f'{sym}_watch_pred1', sc.watch_count)},\n"
        f"    .watch_op = {_c_ptr(f'{sym}_watch_op', sc.watch_count)},\n"
        f"    .watch_arg = {_c_ptr(f'{sym}_watch_arg', sc.watch_count)},\n"
        f"    .watch_flags = {_c_ptr(f'{sym}_watch_flags', sc.watch_count)},\n"
        f"    .pred_count = {sc.pred_count},\n"
        f"    .pred_kind = {_c_ptr(f'{sym}_pred_kind', sc.pred_count)},\n"
        f"    .pred_who = {_c_ptr(f'{sym}_pred_who', sc.pred_count)},\n"
        f"    .pred_a = {_c_ptr(f'{sym}_pred_a', sc.pred_count)},\n"
        f"    .pred_b = {_c_ptr(f'{sym}_pred_b', sc.pred_count)},\n"
        f"    .where_count = {sc.where_count},\n"
        f"    .where_kind = {_c_ptr(f'{sym}_where_kind', sc.where_count)},\n"
        f"    .where_a = {_c_ptr(f'{sym}_where_a', sc.where_count)},\n"
        f"    .where_b = {_c_ptr(f'{sym}_where_b', sc.where_count)},\n"
        f"    .spawn_tmpl_count = {sc.spawn_tmpl_count},\n"
        f"    .spawn_n = {_c_ptr(f'{sym}_spawn_n', sc.spawn_tmpl_count)},\n"
        f"    .spawn_letter = {_c_ptr(f'{sym}_spawn_letter', sc.spawn_tmpl_count)},\n"
        f"    .spawn_room = {_c_ptr(f'{sym}_spawn_room', sc.spawn_tmpl_count)},\n"
        f"    .spawn_batch = {_c_ptr(f'{sym}_spawn_batch', sc.spawn_tmpl_count)},\n"
        f"    .spawn_period = {_c_ptr(f'{sym}_spawn_period', sc.spawn_tmpl_count)},\n"
        f"    .start_spawn_room = {sc.start_spawn_room},\n"
        f"    .start_beat = {sc.start_beat},\n"
        f"    .player_grenades = {sc.player_grenades},\n"
        f"    .player_grenade_wait = {sc.player_grenade_wait},\n"
        f"    .enemy_grenades = {sc.enemy_grenades},\n"
        f"    .enemy_grenade_wait = {sc.enemy_grenade_wait},\n"
        "};\n\n"
    )


def write_generated(
    out_dir: Path,
    tiles: list[list[list[int]]],
    classes: dict[str, int],
    empty_tile: int,
    maps: list[CompiledMap],
    missions: list[tuple[str, str, int, int, int, int, str | None, int, int]],
    class_table: list[int],
    scripts: dict[str, CompiledScript],
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
#define FORCE_COVER_LIVE_MAX     {FORCE_COVER_LIVE_MAX}
#define FORCE_SPAWN_MAX          {FORCE_SPAWN_MAX}
#define FORCE_UNIT_MAX           {FORCE_UNIT_MAX}
#define FORCE_SECTION_MAX        {FORCE_SECTION_MAX}
#define FORCE_LETTER_MAX         {FORCE_LETTER_MAX}
#define FORCE_SCOUT_MAX          {FORCE_SCOUT_MAX}
#define FORCE_SCOUT_PER_ROOM     {FORCE_SCOUT_PER_ROOM}
#define FORCE_OBJECTIVE_MAX      {FORCE_OBJECTIVE_MAX}
#define FORCE_MINE_MAX           {FORCE_MINE_MAX}

#define FORCE_SCRIPT_OPS_MAX      {FORCE_SCRIPT_OPS_MAX}u
#define FORCE_SCRIPT_WATCH_MAX     {FORCE_SCRIPT_WATCH_MAX}u
#define FORCE_SCRIPT_BEAT_MAX     {FORCE_SCRIPT_BEAT_MAX}u
#define FORCE_SCRIPT_PRED_MAX     {FORCE_SCRIPT_PRED_MAX}u
#define FORCE_SCRIPT_WHERE_MAX    {FORCE_SCRIPT_WHERE_MAX}u
#define FORCE_SCRIPT_SPAWN_MAX     {FORCE_SCRIPT_SPAWN_MAX}u
#define FORCE_SCRIPT_NAME_MAX     {FORCE_SCRIPT_NAME_MAX}u
#define FORCE_SCRIPT_WATCH_ONCE   {FORCE_SCRIPT_WATCH_ONCE}u

#define FORCE_FACE_NONE  {FORCE_FACE_NONE}
#define FORCE_FACE_N     {FORCE_FACE_N}
#define FORCE_FACE_E     {FORCE_FACE_E}
#define FORCE_FACE_S     {FORCE_FACE_S}
#define FORCE_FACE_W     {FORCE_FACE_W}

#define FORCE_COVER_SOFT_N  {FORCE_COVER_SOFT_N}
#define FORCE_COVER_SOFT_E  {FORCE_COVER_SOFT_E}
#define FORCE_COVER_SOFT_S  {FORCE_COVER_SOFT_S}
#define FORCE_COVER_SOFT_W  {FORCE_COVER_SOFT_W}
#define FORCE_COVER_HARD_N  {FORCE_COVER_HARD_N}
#define FORCE_COVER_HARD_E  {FORCE_COVER_HARD_E}
#define FORCE_COVER_HARD_S  {FORCE_COVER_HARD_S}
#define FORCE_COVER_HARD_W  {FORCE_COVER_HARD_W}

#define FORCE_AXIS_NONE  {FORCE_AXIS_NONE}
#define FORCE_AXIS_EW    {FORCE_AXIS_EW}
#define FORCE_AXIS_NS    {FORCE_AXIS_NS}

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
    const uint8_t *room_axis;
    const uint8_t *room_cover_lo;
    const uint8_t *room_cover_none;
    const uint8_t *room_cover_hi;
    const uint8_t *room_scout_base;
    const uint8_t *room_scout_count;

    uint8_t cover_count;
    const uint8_t *cover_x;
    const uint8_t *cover_y;
    const uint8_t *cover_grade;
    const uint8_t *cover_facing;   /* pole 1-4, soft 5-8, hard 9-12 */

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

enum force_script_op {{
    FORCE_OP_NOP        = 0,
    FORCE_OP_SPAWN      = 1,
    FORCE_OP_ORDER      = 2,
    FORCE_OP_SET_SPAWN  = 3,
    FORCE_OP_APPROACH   = 4,
    FORCE_OP_GOTO       = 5,
    FORCE_OP_WAIT       = 6,
    FORCE_OP_WIN        = 7,
    FORCE_OP_LOSE       = 8,
    FORCE_OP_RADIO      = 9
}};

enum force_pred_kind {{
    FORCE_PRED_NONE      = 0,
    FORCE_PRED_STR_EQ    = 1,
    FORCE_PRED_STR_LE    = 2,
    FORCE_PRED_IN_GE     = 3,
    FORCE_PRED_REACHED   = 4,
    FORCE_PRED_AT_CELL   = 5,
    FORCE_PRED_CLOCK_GE  = 6,
    FORCE_PRED_REL_GE    = 7,
    FORCE_PRED_STR_GE    = 8,
    FORCE_PRED_JOB_IDLE  = 9
}};

enum force_where_kind {{
    FORCE_WHERE_ROOM     = 0,
    FORCE_WHERE_CELL     = 1,
    FORCE_WHERE_PLAYER   = 2,
    FORCE_WHERE_EXIT     = 3
}};

typedef struct force_script {{
    const char *name;
    uint8_t op_count;
    const uint8_t *op_code;
    const uint8_t *op_a;
    const uint8_t *op_b;
    const uint8_t *op_c;
    uint8_t beat_count;
    const uint8_t *beat_pc;
    const char *const *beat_name;
    uint8_t watch_count;
    const char *const *watch_name;
    const uint8_t *watch_pred0;
    const uint8_t *watch_pred1;
    const uint8_t *watch_op;
    const uint8_t *watch_arg;
    const uint8_t *watch_flags;
    uint8_t pred_count;
    const uint8_t *pred_kind;
    const uint8_t *pred_who;
    const uint8_t *pred_a;
    const uint8_t *pred_b;
    uint8_t where_count;
    const uint8_t *where_kind;
    const uint8_t *where_a;
    const uint8_t *where_b;
    uint8_t spawn_tmpl_count;
    const uint8_t *spawn_n;
    const uint8_t *spawn_letter;
    const uint8_t *spawn_room;
    const uint8_t *spawn_batch;
    const uint8_t *spawn_period;
    uint8_t start_spawn_room;
    uint8_t start_beat;
    uint8_t player_grenades;
    uint8_t player_grenade_wait;
    uint8_t enemy_grenades;
    uint8_t enemy_grenade_wait;
}} force_script;

"""
    for compiled in maps:
        h += f"extern const force_map force_map_{c_ident(compiled.name)};\n"
    for stem in scripts:
        h += f"extern const force_script force_script_{c_ident(stem)};\n"
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
    const force_script *script;
    uint16_t cam_x; /* opening window top-left; clamped inside the rect */
    uint16_t cam_y;
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

    script_syms: dict[str, str] = {}
    for stem, sc in scripts.items():
        sym = f"force_script_{c_ident(stem)}"
        script_syms[stem] = sym
        c += emit_script_arrays(sym, sc)
        c += emit_script_init(sym, sc)

    c += "const force_mission force_missions[] = {\n"
    for name, map_name, x, y, w, h, stem, cam_x, cam_y in missions:
        script_ptr = (
            f"&{script_syms[stem]}" if stem is not None else "NULL"
        )
        c += (
            f'    {{ "{name}", &{map_syms[map_name]}, '
            f"{x}, {y}, {w}, {h}, {script_ptr}, {cam_x}, {cam_y} }},\n"
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
        if count < RUNTIME_TILES:
            raise Error(
                f"{tsx_path}: tileset has {count} tiles; "
                f"need at least {RUNTIME_TILES}"
            )
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
        spawn_of: dict[str, str | None] = {}
        seen: set[str] = set()
        for tmx in tmx_files:
            stems, spawn_layer = spawn_layers_for_map(missions, tmx.stem)
            name, width, height, planes, firstgid = load_tmx(
                tmx, count, empty_tile, stems
            )
            if name in seen:
                raise Error(f"duplicate map name '{name}'")
            seen.add(name)
            spawn_of[name] = spawn_layer
            loaded.append((name, width, height, planes, firstgid))

        for mname, map_name, x, y, w, h, _stem, cam_x, cam_y in missions:
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
            if cam_x >= mw or cam_y >= mh:
                raise Error(
                    f"{missions_txt}: {mname} cam={cam_x},{cam_y} "
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
                spawn_of[name],
            )
            for name, width, height, planes, firstgid in loaded
        ]
        maps_by_name = {m.name: m for m in maps}

        scripts: dict[str, CompiledScript] = {}
        scripts_dir = root / "assets" / "scripts"
        for mname, map_name, _x, _y, _w, _h, stem, _cx, _cy in missions:
            if stem is None:
                continue
            cmap = maps_by_name[map_name]
            path = scripts_dir / f"{stem}.txt"
            if stem in scripts:
                if scripts[stem].map_name != map_name:
                    raise Error(
                        f"{missions_txt}: script '{stem}' already bound to "
                        f"{scripts[stem].map_name} (mission {mname})"
                    )
                continue
            if not path.is_file():
                raise Error(
                    f"{missions_txt}: script '{stem}' not found "
                    f"(mission {mname})"
                )
            scripts[stem] = compile_script(path, cmap)

        # Editor glyphs stay in the sheet for Tiled. The linked tileset is
        # playfield tiles 0–127, so normandy and bastogne keep their bytes.
        runtime_n = RUNTIME_TILES
        runtime_tiles = tiles[:runtime_n]
        runtime_class = class_table[:runtime_n]
        used_names = {
            name_per_id[tid]
            for tid in range(min(runtime_n, len(name_per_id)))
            if name_per_id[tid] is not None
        }
        runtime_classes = {
            name: num for name, num in classes.items() if name in used_names
        }
        write_generated(
            out, runtime_tiles, runtime_classes, empty_tile, maps, missions,
            runtime_class, scripts,
        )
    except Error as exc:
        print(f"gen_sdl: {exc}", file=sys.stderr)
        return 1

    per_map = ", ".join(
        f"{m.name} {len(m.rooms)} rooms {len(m.spawn_x)} spawns "
        f"{len(m.cover_x)} cover"
        for m in maps
    )
    per_script = "".join(
        f", {stem}.txt {sc.op_count} ops {sc.watch_count} watchers"
        for stem, sc in scripts.items()
    )
    print(
        f"gen_sdl: {count} tiles ({RUNTIME_TILES} runtime), "
        f"{len(maps)} map(s), {len(missions)} mission(s), "
        f"{per_map}{per_script} -> {out}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
