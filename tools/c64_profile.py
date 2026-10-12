#!/usr/bin/env python3
"""Time one C64 frame with an enemy in room 2, then the frame after it.

The bracket starts at input_poll. The pass runs world_tick, then
spins in wait_ui until the line-210 edge that closes the third
video frame, then draw_all. Work and that UI wait are separate.
IRQ time is lifted out of whichever stretch the raster hit.

Baseline notes: agents/c64-profile.md. Connects to a running c64m.
From the force repo root, with the PRG already loaded:

    python3 tools/c64_profile.py

Env: C64M_PORT (default 6510), C64M_ROOT (default ../machines).
The PRG's build/c64/game-image.sym and build/force.prg must match the image
in the emulator. The script presses F3, then D A 64,9, and stops on
the first input_poll where a living enemy has map x in 55..58.
That pass calls world_tick, then waits for the line-210 draw.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MACHINES = os.environ.get(
    "C64M_ROOT", os.path.join(os.path.dirname(ROOT), "machines"))
sys.path.insert(0, os.path.join(MACHINES, "tools", "c64"))
from c64_control_client import Ctl  # noqa: E402

PAL_FRAME = 985248 / 50
N = 32
PORT = int(os.environ.get("C64M_PORT", "6510"))
SYM = os.path.join(ROOT, "build", "c64", "game-image.sym")
PRG = os.path.join(ROOT, "build", "force.prg")

# Documented opcodes. A zero means "do not step this byte".
LEN = [
    1, 2, 0, 0, 0, 2, 2, 0, 1, 2, 1, 0, 0, 3, 3, 0,
    2, 2, 0, 0, 0, 2, 2, 0, 1, 3, 0, 0, 0, 3, 3, 0,
    3, 2, 0, 0, 2, 2, 2, 0, 1, 2, 1, 0, 3, 3, 3, 0,
    2, 2, 0, 0, 0, 2, 2, 0, 1, 3, 0, 0, 0, 3, 3, 0,
    1, 2, 0, 0, 0, 2, 2, 0, 1, 2, 1, 0, 3, 3, 3, 0,
    2, 2, 0, 0, 0, 2, 2, 0, 1, 3, 0, 0, 0, 3, 3, 0,
    1, 2, 0, 0, 0, 2, 2, 0, 1, 2, 1, 0, 3, 3, 3, 0,
    2, 2, 0, 0, 0, 2, 2, 0, 1, 3, 0, 0, 0, 3, 3, 0,
    0, 2, 0, 0, 2, 2, 2, 0, 1, 0, 1, 0, 3, 3, 3, 0,
    2, 2, 0, 0, 2, 2, 2, 0, 1, 3, 1, 0, 0, 3, 0, 0,
    2, 2, 2, 0, 2, 2, 2, 0, 1, 2, 1, 0, 3, 3, 3, 0,
    2, 2, 0, 0, 2, 2, 2, 0, 1, 3, 1, 0, 3, 3, 3, 0,
    2, 2, 0, 0, 2, 2, 2, 0, 1, 2, 1, 0, 3, 3, 3, 0,
    2, 2, 0, 0, 0, 2, 2, 0, 1, 3, 0, 0, 0, 3, 3, 0,
    2, 2, 0, 0, 2, 2, 2, 0, 1, 2, 1, 0, 3, 3, 3, 0,
    2, 2, 0, 0, 0, 2, 2, 0, 1, 3, 0, 0, 0, 3, 3, 0,
]

GROUPS = (
    ("Overhead", (
        ("Controls", ("controls",)),
        ("IRQ", ("irq",)),
        ("Wait for raster", ("wait",)),
        ("Cursor and command", ("cursor and command",)),
        ("Between calls", ("between calls",)),
    )),
    ("Draw", (
        ("Men", ("draw men",)),
        ("Command line", ("draw command",)),
        ("Grenade flash", ("draw grenade flash",)),
        ("Cursor", ("draw cursor",)),
        ("Full repaint", ("draw full",)),
    )),
    ("Simulation", (
        ("Movement", ("walking",)),
        ("Aim", ("targeting",)),
        ("Shot", ("shooting", "shoot bookkeeping", "shoot check")),
        ("Grenades", ("grenades",)),
        ("Cover", ("cover",)),
        ("Deaths", ("deaths",)),
        ("Hurt timers", ("hurt timers",)),
        ("Script and spawn", ("script", "spawn")),
        ("Grenade cooldown", ("grenade cooldown",)),
    )),
)


def load_sym(path):
    out = {}
    with open(path) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) != 2 or "::" in parts[1]:
                continue
            try:
                addr = int(parts[0], 16)
            except ValueError:
                continue
            out[parts[1]] = addr
    return out


def load_prg(path):
    raw = open(path, "rb").read()
    return raw[0] + raw[1] * 256, raw[2:]


def find_jsr(data, load, pc, target, limit=0x200):
    end = pc + limit
    while pc < end:
        op = data[pc - load]
        n = LEN[op]
        if n == 0:
            raise RuntimeError(f"unknown opcode ${op:02X} at ${pc:04X}")
        if op == 0x20:
            dest = data[pc - load + 1] + data[pc - load + 2] * 256
            if dest == target:
                return pc, pc + 3
        pc += n
    raise RuntimeError(f"jsr ${target:04X} not found after ${pc - limit:04X}")


def accept(c, text):
    kind, *_ = r = c.cmd(text)
    if kind == "error":
        raise RuntimeError(f"{text!r} -> {r}")
    return r


def cpu_fields(c):
    fields = {}
    for tok in c.ok("get-cpu").split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            fields[k] = v
    return fields


def cpu(c):
    fields = cpu_fields(c)
    return int(fields["pc"], 16), int(fields["cycles"])


def stack_byte(c, sp, offset):
    return c.mem(0x100 + ((sp + offset) & 0xFF), 1)[0]


def irq_resume(c):
    """PC the IRQ will RTI to. $FF48 has already pushed A, X, and Y."""
    sp = int(cpu_fields(c)["sp"], 16)
    lo = stack_byte(c, sp, 5)
    hi = stack_byte(c, sp, 6)
    return lo + hi * 256


def jsr_return(c):
    """Instruction after the jsr that entered the current routine."""
    sp = int(cpu_fields(c)["sp"], 16)
    lo = stack_byte(c, sp, 1)
    hi = stack_byte(c, sp, 2)
    return (lo + hi * 256 + 1) & 0xFFFF


def living(c, s):
    xs = c.mem(s["unit_x"], N)
    ys = c.mem(s["unit_y"], N)
    secs = c.mem(s["unit_section"], N)
    counts = c.mem(s["unit_count"], N)
    hps = c.mem(s["unit_hp"], N)
    friends, enemies = [], []
    for i in range(N):
        if counts[i] == 0 or hps[i] == 0:
            continue
        rec = (i, xs[i], ys[i], hps[i])
        (enemies if secs[i] >= 8 else friends).append(rec)
    return friends, enemies


def hold_until(c, key, pred, shift=False):
    if shift:
        c.ok("key-down left-shift")
    c.ok(f"key-down {key}")
    ok = False
    for _ in range(40):
        c.ok("wait-frame 2 8000")
        if pred():
            ok = True
            break
    c.ok(f"key-up {key}")
    if shift:
        c.ok("key-up left-shift")
    c.ok("wait-frame 2 8000")
    return ok


def run_to(c, addr):
    c.ok(f"run-to ${addr:04X}")
    c.ok("wait-paused 20000")
    pc, cyc = cpu(c)
    if pc != addr:
        raise RuntimeError(f"run-to ${addr:04X} stopped at ${pc:04X}")
    return cyc


def arm(c, addrs):
    accept(c, "break-clear-all")
    for a in addrs:
        accept(c, f"break-create exec ${a:04X}")


def hit_next(c):
    c.ok("run")
    c.ok("wait-paused 20000")
    return cpu(c)


def step_out(c):
    accept(c, "break-clear-all")
    c.ok("step-out")
    c.ok("wait-paused 20000")
    return cpu(c)


def add(buckets, name, n):
    buckets[name] = buckets.get(name, 0) + n


def stop_at(c, addrs):
    arm(c, list(dict.fromkeys(addrs)))
    pc, cyc = hit_next(c)
    if pc not in addrs:
        raise RuntimeError(
            f"stopped at ${pc:04X}, wanted "
            + ", ".join(f"${a:04X}" for a in addrs))
    return pc, cyc


def charge_irq(c, buckets, arrived):
    back = irq_resume(c)
    if not 0x0200 <= back <= 0xFFFF:
        sp = int(cpu_fields(c)["sp"], 16)
        raw = bytes(stack_byte(c, sp, i) for i in range(1, 9))
        raise RuntimeError(
            f"irq resume ${back:04X} sp=${sp:02X} stack {raw.hex()}")
    pc, cyc = stop_at(c, [back])
    add(buckets, "irq", cyc - arrived)
    buckets["irq_n"] = buckets.get("irq_n", 0) + 1
    return cyc, pc


def account_any(c, buckets, dests, name, irq, prev):
    """Run until one of dests. IRQ cycles land in the irq bucket."""
    while True:
        pc, cyc = stop_at(c, list(dests) + [irq])
        gap = cyc - prev
        if pc == irq and irq not in dests:
            add(buckets, name, gap)
            prev, landed = charge_irq(c, buckets, cyc)
            if landed in dests:
                return landed, prev
            continue
        add(buckets, name, gap)
        return pc, cyc


def account(c, buckets, dest, name, irq, prev):
    pc, cyc = account_any(c, buckets, [dest], name, irq, prev)
    if pc != dest:
        raise RuntimeError(f"expected ${dest:04X}, stopped at ${pc:04X}")
    return cyc


def profile_unit(c, buckets, calls, start, probes, unit_ret, irq):
    back = jsr_return(c)
    if back != unit_ret:
        raise RuntimeError(
            f"unit_shoot returns to ${back:04X}, expected ${unit_ret:04X}")
    prev = start
    while True:
        pc, cyc = account_any(
            c, buckets, list(probes) + [unit_ret], "shoot bookkeeping", irq, prev)
        if pc == unit_ret:
            return cyc
        if pc not in probes:
            raise RuntimeError(f"unexpected pc ${pc:04X} inside unit_shoot")
        before = buckets.get(probes[pc], 0)
        ret = jsr_return(c)
        prev = account(c, buckets, ret, probes[pc], irq, cyc)
        calls.setdefault(probes[pc], []).append(buckets[probes[pc]] - before)


def profile_shoot(c, buckets, calls, prev, shoot_at, unit_at, shoot_ret, probes, unit_ret, irq):
    prev = account(c, buckets, shoot_at, "shoot bookkeeping", irq, prev)
    while True:
        pc, cyc = account_any(
            c, buckets, [unit_at, shoot_ret], "shoot bookkeeping", irq, prev)
        if pc == shoot_ret:
            return cyc
        if pc != unit_at:
            raise RuntimeError(f"unexpected pc ${pc:04X} in shoot_all")
        prev = profile_unit(c, buckets, calls, cyc, probes, unit_ret, irq)


def order_defend(c, s):
    verb, who = s["cmd_verb"], s["cmd_who"]
    cx, cy, slot, digits = s["cmd_x"], s["cmd_y"], s["cmd_slot"], s["cmd_digits"]
    ov, ox, oy = s["section_order_verb"], s["section_order_x"], s["section_order_y"]
    steps = (
        ("d", True, lambda: c.mem(verb, 1)[0] == 2 and c.mem(slot, 1)[0] == 1),
        ("a", True, lambda: c.mem(who, 1)[0] == 0 and c.mem(slot, 1)[0] == 2),
        ("6", False, lambda: c.mem(cx, 1)[0] == 6 and c.mem(digits, 1)[0] == 1),
        ("4", False, lambda: c.mem(cx, 1)[0] == 64),
        ("comma", False, lambda: c.mem(slot, 1)[0] == 3),
        ("9", False, lambda: c.mem(cy, 1)[0] == 9),
        ("return", False, lambda: c.mem(ov, 1)[0] == 2
         and c.mem(ox, 1)[0] == 64 and c.mem(oy, 1)[0] == 9),
    )
    for key, shift, pred in steps:
        if not hold_until(c, key, pred, shift):
            raise RuntimeError(f"key {key} did not land")


def main():
    sym = load_sym(SYM)
    load, data = load_prg(PRG)
    need = (
        "input_poll", "game_tick", "world_tick", "draw_all", "decay_fx",
        "cover_jobs", "decay_grenade_wait", "shoot_all", "apply_deaths",
        "script_step", "spawn_pulse", "think_all", "refresh_units",
        "refresh_ui", "refresh_nades", "unit_shoot", "weapons_free",
        "try_grenade", "find_on_cell", "smear_closest", "posture_damage",
        "apply_hit_y", "note_contact", "unit_x", "unit_y", "unit_section",
        "unit_count", "unit_hp", "wait_ui", "drawn", "win_x", "win_y",
        "seen_win_x", "seen_win_y", "cmd_verb", "cmd_who", "cmd_x", "cmd_y",
        "cmd_slot", "cmd_digits", "section_order_verb", "section_order_x",
        "section_order_y", "irq",
    )
    missing = [n for n in need if n not in sym]
    if missing:
        raise SystemExit(f"missing symbols: {', '.join(missing)}")

    _, after_input = find_jsr(data, load, sym["main"], sym["input_poll"])
    _, after_tick = find_jsr(data, load, after_input, sym["game_tick"])
    _, after_draw = find_jsr(data, load, after_tick, sym["draw_all"])
    shoot_jsr, after_shoot = find_jsr(data, load, sym["world_tick"], sym["shoot_all"])
    _, unit_ret = find_jsr(data, load, sym["shoot_all"], sym["unit_shoot"])
    probes = {
        sym["weapons_free"]: "shoot check",
        sym["try_grenade"]: "grenades",
        sym["find_on_cell"]: "targeting",
        sym["smear_closest"]: "targeting",
        sym["posture_damage"]: "shooting",
        sym["apply_hit_y"]: "shooting",
        sym["note_contact"]: "shooting",
    }
    world_calls = (
        (sym["decay_fx"], "hurt timers"),
        (sym["cover_jobs"], "cover"),
        (sym["decay_grenade_wait"], "grenade cooldown"),
        (sym["apply_deaths"], "deaths"),
        (sym["script_step"], "script"),
        (sym["spawn_pulse"], "spawn"),
        (sym["cover_jobs"], "cover"),
        (sym["think_all"], "walking"),
    )

    c = Ctl(port=PORT, timeout=30.0)
    accept(c, "break-clear-all")
    c.ok("run")
    c.ok("set-turbo max")
    for key in ("f3", "left-shift", "d", "a"):
        c.ok(f"key-up {key}")
    c.ok("wait-frame 4 8000")
    c.ok("key-down f3")
    c.ok("wait-frame 25 8000")
    c.ok("key-up f3")
    c.ok("wait-frame 8 8000")
    ready = False
    for _ in range(40):
        friends, enemies = living(c, sym)
        if (len(friends) >= 6
                and all(hp == 16 and x >= 64 for _, x, y, hp in friends)
                and all(x <= 45 for _, x, y, hp in enemies)):
            ready = True
            break
        c.ok("wait-frame 2 8000")
    if not ready:
        raise SystemExit("restart did not show six fresh friendlies")
    order_defend(c, sym)

    c.ok("pause")
    c.ok("wait-paused 5000")
    arm(c, [sym["input_poll"]])
    found = None
    for _ in range(800):
        c.ok("run")
        c.ok("wait-paused 10000")
        pc, _cyc = cpu(c)
        if pc != sym["input_poll"]:
            raise SystemExit(f"hunt stopped at ${pc:04X}")
        friends, enemies = living(c, sym)
        room2 = [e for e in enemies if 55 <= e[1] <= 58]
        if room2:
            found = (friends, enemies, room2)
            break
    if not found:
        raise SystemExit("no enemy at map x 55..58 on a logic tick")
    friends, enemies, room2 = found
    print("friends", [(i, x, y, hp) for i, x, y, hp in friends])
    print("enemies", [(i, x, y, hp) for i, x, y, hp in enemies])
    print("in room 2", [(i, x, y, hp) for i, x, y, hp in room2])

    irq = sym["irq"]
    ctx = dict(
        data=data, load=load, sym=sym, irq=irq,
        after_input=after_input, after_tick=after_tick, after_draw=after_draw,
        shoot_jsr=shoot_jsr, after_shoot=after_shoot, unit_ret=unit_ret,
        probes=probes, world_calls=world_calls,
    )
    _, t0 = cpu(c)
    buckets, calls = profile_frame(c, ctx, t0)
    report("Logic frame", buckets, calls)
    return 0


def profile_world(c, ctx, prev):
    buckets_owner = ctx["buckets"]
    data, load, sym, irq = ctx["data"], ctx["load"], ctx["sym"], ctx["irq"]
    scan = sym["world_tick"]
    before_shoot = ctx["world_calls"][:3]
    after_shoot_calls = ctx["world_calls"][3:]
    for target, name in before_shoot:
        jsr_at, ret = find_jsr(data, load, scan, target)
        if prev_pc(c) != jsr_at:
            prev = account(c, buckets_owner, jsr_at, "between calls", irq, prev)
        prev = account(c, buckets_owner, ret, name, irq, prev)
        scan = ret
    jsr_at, _ret = find_jsr(data, load, scan, sym["shoot_all"])
    if prev_pc(c) != jsr_at:
        prev = account(c, buckets_owner, jsr_at, "between calls", irq, prev)
    if jsr_at != ctx["shoot_jsr"]:
        raise RuntimeError("shoot_all jsr moved")
    prev = profile_shoot(
        c, buckets_owner, ctx["calls"], prev, sym["shoot_all"], sym["unit_shoot"],
        ctx["after_shoot"], ctx["probes"], ctx["unit_ret"], irq)
    scan = ctx["after_shoot"]
    for target, name in after_shoot_calls:
        jsr_at, ret = find_jsr(data, load, scan, target)
        if prev_pc(c) != jsr_at:
            prev = account(c, buckets_owner, jsr_at, "between calls", irq, prev)
        prev = account(c, buckets_owner, ret, name, irq, prev)
        scan = ret
    return prev


def profile_frame(c, ctx, t0):
    """PC is input_poll. Returns buckets for work plus the following wait."""
    sym, irq = ctx["sym"], ctx["irq"]
    buckets, calls = {}, {}
    ctx["buckets"] = buckets
    ctx["calls"] = calls
    prev = account(c, buckets, ctx["after_input"], "controls", irq, t0)
    prev = account(c, buckets, sym["game_tick"], "between calls", irq, prev)
    pc, prev = account_any(
        c, buckets, [sym["world_tick"], ctx["after_tick"]],
        "cursor and command", irq, prev)
    if pc == sym["world_tick"]:
        prev = profile_world(c, ctx, prev)
        _, after_world = find_jsr(
            ctx["data"], ctx["load"], sym["game_tick"], sym["world_tick"])
        if prev_pc(c) != after_world:
            prev = account(c, buckets, after_world, "between calls", irq, prev)
        prev = account(c, buckets, ctx["after_tick"], "cursor and command", irq, prev)
    prev = account(c, buckets, sym["wait_ui"], "between calls", irq, prev)
    prev = account(c, buckets, sym["draw_all"], "wait", irq, prev)
    drawn = c.mem(sym["drawn"], 1)[0]
    same = (c.mem(sym["win_x"], 1)[0] == c.mem(sym["seen_win_x"], 1)[0]
            and c.mem(sym["win_y"], 1)[0] == c.mem(sym["seen_win_y"], 1)[0])
    buckets["drawn"] = drawn
    buckets["win_same"] = int(bool(same))
    if drawn and same:
        jsr_at, ret = find_jsr(
            ctx["data"], ctx["load"], sym["draw_all"], sym["refresh_units"])
        prev = account(c, buckets, jsr_at, "between calls", irq, prev)
        prev = account(c, buckets, ret, "draw men", irq, prev)
        _jsr, ret = find_jsr(ctx["data"], ctx["load"], ret, sym["refresh_ui"])
        prev = account(c, buckets, ret, "draw command", irq, prev)
        _jsr, ret = find_jsr(ctx["data"], ctx["load"], ret, sym["refresh_nades"])
        prev = account(c, buckets, ret, "draw grenade flash", irq, prev)
        prev = account(c, buckets, ctx["after_draw"], "draw cursor", irq, prev)
    else:
        prev = account(c, buckets, ctx["after_draw"], "draw full", irq, prev)
    prev = account(c, buckets, sym["input_poll"], "between calls", irq, prev)
    buckets["loop"] = prev - t0
    buckets["work"] = buckets["loop"] - buckets.get("wait", 0)
    total = sum(v for k, v in buckets.items() if isinstance(v, int) and k not in (
        "irq_n", "drawn", "win_same", "work", "loop"))
    if total != buckets["loop"]:
        raise RuntimeError(f"accounting {total} != {buckets['loop']} {buckets}")
    return buckets, calls


def report(title, buckets, calls):
    loop = buckets["loop"]
    work = buckets["work"]
    wait = buckets.get("wait", 0)
    print()
    print(title)
    print(
        f"work {work}  wait {wait}  loop {loop}  "
        f"irq {buckets.get('irq', 0)} x{buckets.get('irq_n', 0)}  "
        f"drawn={buckets.get('drawn')} win_same={buckets.get('win_same')}")
    print(f"{'Where the time went':22} {'Cycles':>8} {'Share':>7}")
    shown = 0
    for group, rows in GROUPS:
        grow = 0
        lines = []
        for label, keys in rows:
            n = sum(buckets.get(k, 0) for k in keys)
            if n == 0:
                continue
            grow += n
            lines.append((label, n))
        if grow == 0:
            continue
        print(f"{group:22} {grow:8} {100 * grow / loop:6.0f}%")
        for label, n in lines:
            shown += n
            print(f"  {label:20} {n:8} {100 * n / loop:6.0f}%")
    if shown != loop:
        print(f"{'Unbucketed':22} {loop - shown:8}")
    for name, ns in sorted(calls.items()):
        print(f"calls {name}: n={len(ns)} min={min(ns)} max={max(ns)} sum={sum(ns)}")


def prev_pc(c):
    pc, _cyc = cpu(c)
    return pc


if __name__ == "__main__":
    sys.exit(main())
