#!/usr/bin/env bash
# Boot the unlinked PRG and prove LOAD "FARM",8,1.
#
# The title waits for a key. This does not inject one: it NOPs the compare
# branch once the picture is up, then breakpoints world_load / load_fail.
#
#   tools/c64_map_load.sh

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE_ROOT="$(cd "${TOOLS_DIR}/.." && pwd)"

if [[ -n "${C64M_ROOT:-}" ]]; then
  MACHINES_ROOT="${C64M_ROOT}"
elif [[ -x "${FORCE_ROOT}/../machines/build/c64m" ]]; then
  MACHINES_ROOT="$(cd "${FORCE_ROOT}/../machines" && pwd)"
else
  echo "error: missing c64m (set C64M_ROOT)" >&2
  exit 1
fi

C64M_BIN="${MACHINES_ROOT}/build/c64m"
AM65="${MACHINES_ROOT}/build/am65"
CLIENT_DIR="${MACHINES_ROOT}/tools/c64"

TILES="70707070707070707070707070707070"
PAPER="05050505050505050505050505050505"

"${AM65}" -i "${FORCE_ROOT}/src/c64/force.asm" -o /tmp/force-pr5.prg --prg -s /tmp/force-pr5.sym

sym_addr() {
  local name="$1"
  local addr
  addr="$(awk -v n="${name}" '$2 == n { print $1; exit }' /tmp/force-pr5.sym)"
  if [[ -z "${addr}" ]]; then
    echo "error: ${name} missing from /tmp/force-pr5.sym" >&2
    exit 1
  fi
  printf '%s\n' "${addr}"
}

WORLD="$(sym_addr world_load)"
FAIL="$(sym_addr load_fail)"
DOWN="$(sym_addr show_title::down)"
echo "world_load: \$${WORLD}"
echo "load_fail: \$${FAIL}"
echo "show_title::down: \$${DOWN}"

python3 - <<'PY'
text = open("/tmp/force-pr5.sym").read().splitlines()
segs = {}
for line in text:
    line = line.strip()
    if not line.startswith(("CODE ", "SPARE ", "TITLE ")):
        # segment lines are indented "CODE [4000-8858)"
        pass
for line in text:
    if "CODE [" in line or "SPARE [" in line or "TITLE [" in line:
        print(line.strip())
PY

EMU_PID=""
cleanup() {
  if [[ -n "${EMU_PID}" ]] && kill -0 "${EMU_PID}" 2>/dev/null; then
    kill "${EMU_PID}" 2>/dev/null || true
    local _
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "${EMU_PID}" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "${EMU_PID}" 2>/dev/null; then
      kill -9 "${EMU_PID}" 2>/dev/null || true
    fi
    wait "${EMU_PID}" 2>/dev/null || true
  fi
  EMU_PID=""
}
trap cleanup EXIT

port_open() {
  python3 -c 'import socket, sys
s = socket.socket()
s.settimeout(0.2)
rc = s.connect_ex(("127.0.0.1", int(sys.argv[1])))
s.close()
raise SystemExit(0 if rc == 0 else 1)' "$1" 2>/dev/null
}

free_port() {
  python3 -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()'
}

launch_c64m() {
  local disk="$1"
  local log
  EMU_PORT="$(free_port)"
  log="$(mktemp "${TMPDIR:-/tmp}/c64_map_load.log.XXXXXX")"
  (
    cd "${MACHINES_ROOT}"
    exec "${C64M_BIN}" \
      --noini \
      --nosaveini \
      --headless \
      --control-port="${EMU_PORT}" \
      --pal \
      --turbo=2 \
      --prg /tmp/force-pr5.prg \
      --autorun \
      --disk "8=${disk}"
  ) >"${log}" 2>&1 &
  EMU_PID=$!
  local _
  for _ in $(seq 1 80); do
    if port_open "${EMU_PORT}"; then
      return 0
    fi
    if ! kill -0 "${EMU_PID}" 2>/dev/null; then
      echo "error: c64m exited before the control port opened" >&2
      cat "${log}" >&2 || true
      exit 1
    fi
    sleep 0.1
  done
  echo "error: control port ${EMU_PORT} did not open" >&2
  cat "${log}" >&2 || true
  exit 1
}

run_case() {
  local label="$1"
  local disk="$2"
  local want="$3"
  launch_c64m "${disk}"
  PYTHONPATH="${CLIENT_DIR}" python3 - \
    "${EMU_PORT}" "${WORLD}" "${FAIL}" "${DOWN}" \
    "${want}" "${TILES}" "${PAPER}" "${label}" <<'PY'
import sys
from c64_control_client import Ctl

port = int(sys.argv[1])
world = int(sys.argv[2], 16)
fail = int(sys.argv[3], 16)
down = int(sys.argv[4], 16)
want = sys.argv[5]
tiles = bytes.fromhex(sys.argv[6])
paper = bytes.fromhex(sys.argv[7])
label = sys.argv[8]

c = Ctl(host="127.0.0.1", port=port, timeout=60.0)

def parse_pc(text):
    for tok in text.split():
        if tok.lower().startswith("pc="):
            return int(tok.split("=", 1)[1], 16)
    raise SystemExit(f"{label}: no pc in {text!r}")

def accept(text):
    result = c.cmd(text)
    if result[0] not in ("ok", "data"):
        raise RuntimeError(f"{text!r} -> {result}")
    return result

def set_mem(addr, data):
    c.id += 1
    rid = c.id
    hdr = f"{rid} set-memory ${addr:04X} {len(data)} ram\n".encode("latin1")
    c.s.sendall(hdr + bytes(data) + b"\n")
    while True:
        line = c._readline()
        got, result = c._parse_response_header(line)
        if result[0] == "event":
            c._note_event(result[1])
            continue
        if got != rid or result[0] != "ok":
            raise RuntimeError(f"set-memory -> {result}")
        return

def wait_pc():
    state = c.ok("get-state")
    cpu = c.ok("get-cpu")
    pc = parse_pc(cpu)
    if "state=running" in state or pc not in (world, fail, down):
        if "state=paused" in state:
            c.ok("run")
        c.ok("wait-paused 30000")
        cpu = c.ok("get-cpu")
        pc = parse_pc(cpu)
    return pc

try:
    accept(f"break-exec ${down:04X}")
    accept(f"break-exec ${world:04X}")
    accept(f"break-exec ${fail:04X}")
    pc = wait_pc()
    if pc == down:
        gate = c.mem(down + 8, 4)
        if gate[:3] != bytes((0xC9, 0xFF, 0xF0)):
            raise SystemExit(
                f"{label}: title wait at ${down:04X} is {gate.hex()}, not cmp/beq")
        set_mem(down + 10, b"\xEA\xEA")
        c.ok("run")
        c.ok("wait-paused 30000")
        pc = parse_pc(c.ok("get-cpu"))
    status = c.mem(0x0819, 1)[0]
    got_tiles = c.mem(0xA000, 16)
    got_paper = c.mem(0xAC80, 16)
    play = c.mem(0xBC80, 4)
except Exception as exc:
    sys.exit(f"{label}: {exc}")

def hx(buf):
    return " ".join(f"{b:02X}" for b in buf)

print(f"{label}: pc=${pc:04X} status={status}")
print(f"{label}: tiles {hx(got_tiles)}")
print(f"{label}: paper {hx(got_paper)}")
print(f"{label}: play {hx(play)}")

if want == "ok":
    if pc != world or status != 0 or got_tiles != tiles or got_paper != paper:
        sys.exit(f"{label}: wanted world_load ${world:04X} status 0")
    if play != bytes((0x28, 0x00, 0x28, 0x14)):
        sys.exit(f"{label}: play rect {hx(play)}")
elif want == "miss":
    if pc != fail or status != 1 or pc == world:
        sys.exit(
            f"{label}: wanted load_fail ${fail:04X} status 1, "
            f"got pc=${pc:04X} status={status}")
else:
    sys.exit(f"{label}: bad want {want}")
PY
  cleanup
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/c64_map_load.XXXXXX")"
trap 'cleanup; rm -rf "${TMP_ROOT}"' EXIT

OK_DIR="${TMP_ROOT}/ok"
MISS_DIR="${TMP_ROOT}/miss"
mkdir -p "${OK_DIR}" "${MISS_DIR}"
cp "${FORCE_ROOT}/build/c64/farm.prg" "${OK_DIR}/farm.prg"
# No FARM directory entry. A different PRG must not alias onto that name.
cp /tmp/force-pr5.prg "${MISS_DIR}/other.prg"

run_case "farm" "${OK_DIR}" ok
run_case "missing" "${MISS_DIR}" miss
echo "ok"
