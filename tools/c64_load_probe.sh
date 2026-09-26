#!/usr/bin/env bash
# Prove LOAD "PROBE",8,1 of a PRG-shaped file on HostFS and on a c1541 image.
#
#   tools/c64_load_probe.sh
#
# C64M_ROOT overrides the sibling ../machines checkout (same as tools/coop.sh).
# $C1541 is used when that variable is set and the command exists; otherwise
# c1541 on PATH. No third path is tried. emulate_1541 is not turned on.

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE_ROOT="$(cd "${TOOLS_DIR}/.." && pwd)"

if [[ -n "${C64M_ROOT:-}" ]]; then
  MACHINES_ROOT="${C64M_ROOT}"
elif [[ -x "${FORCE_ROOT}/../machines/build/c64m" ]]; then
  MACHINES_ROOT="$(cd "${FORCE_ROOT}/../machines" && pwd)"
else
  echo "error: missing ../machines/build/c64m (set C64M_ROOT)" >&2
  exit 1
fi

C64M_BIN="${MACHINES_ROOT}/build/c64m"
AM65="${MACHINES_ROOT}/build/am65"
CLIENT_DIR="${MACHINES_ROOT}/tools/c64"

if [[ ! -x "${C64M_BIN}" ]]; then
  echo "error: missing ${C64M_BIN}" >&2
  exit 1
fi
if [[ ! -x "${AM65}" ]]; then
  echo "error: missing ${AM65}" >&2
  exit 1
fi
if [[ ! -f "${CLIENT_DIR}/c64_control_client.py" ]]; then
  echo "error: missing ${CLIENT_DIR}/c64_control_client.py" >&2
  exit 1
fi

# Payload matches probe_expect in tools/c64_load_probe.asm. Load address $A000.
PAYLOAD_HEX="0102030405060708090A0B0C0D0E0F10"

C1541_BIN=""
C1541_RESOLVED=no
resolve_c1541() {
  local tried=""
  if [[ -n "${C1541+x}" && -n "${C1541}" ]]; then
    if command -v "${C1541}" >/dev/null 2>&1; then
      C1541_BIN="$(command -v "${C1541}")"
      C1541_RESOLVED=yes
      return 0
    fi
    tried="${C1541}"
  fi
  if command -v c1541 >/dev/null 2>&1; then
    C1541_BIN="$(command -v c1541)"
    C1541_RESOLVED=no
    return 0
  fi
  if [[ -n "${tried}" ]]; then
    echo "error: c1541 not found: tried ${tried} and c1541" >&2
  else
    echo "error: c1541 not found: tried c1541" >&2
  fi
  exit 1
}
resolve_c1541

echo "c64m: ${C64M_BIN}"
echo "c1541: ${C1541_BIN}"
echo "C1541 resolved: ${C1541_RESOLVED}"
echo "emulate_1541: off"

BUILD_DIR="${FORCE_ROOT}/build"
mkdir -p "${BUILD_DIR}"
PROBE_PRG="${BUILD_DIR}/c64_load_probe.prg"
PROBE_SYM="${BUILD_DIR}/c64_load_probe.sym"

"${AM65}" -i "${TOOLS_DIR}/c64_load_probe.asm" -o "${PROBE_PRG}" --prg -s "${PROBE_SYM}"

sym_addr() {
  local name="$1"
  local addr
  addr="$(awk -v n="${name}" '$2 == n { print $1; exit }' "${PROBE_SYM}")"
  if [[ -z "${addr}" ]]; then
    echo "error: ${name} missing from ${PROBE_SYM}" >&2
    exit 1
  fi
  printf '%s\n' "${addr}"
}

OK_ADDR="$(sym_addr probe_ok)"
FAIL_ADDR="$(sym_addr probe_fail)"
STATUS_ADDR="$(sym_addr probe_status)"
echo "probe_ok: \$${OK_ADDR}"
echo "probe_fail: \$${FAIL_ADDR}"
echo "probe_status: \$${STATUS_ADDR}"
echo "payload: ${PAYLOAD_HEX}"

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

write_probe_data() {
  local dest="$1"
  python3 -c 'import sys
payload = bytes.fromhex(sys.argv[1])
open(sys.argv[2], "wb").write(bytes([0x00, 0xA0]) + payload)' \
    "${PAYLOAD_HEX}" "${dest}"
}

# --noini leaves emulate_1541 at the zero default. --nosaveini so a breakpoint
# list cannot be written back. ROMs are discovered from the machines tree.
# Sets EMU_PID and EMU_PORT. Not called from a command substitution: the
# emulator has to stay in this shell so EXIT can kill it.
launch_c64m() {
  local disk="$1"
  local log
  EMU_PORT="$(free_port)"
  log="$(mktemp "${TMPDIR:-/tmp}/c64_load_probe.log.XXXXXX")"
  (
    cd "${MACHINES_ROOT}"
    exec "${C64M_BIN}" \
      --noini \
      --nosaveini \
      --headless \
      --control-port="${EMU_PORT}" \
      --pal \
      --turbo=2 \
      --prg "${PROBE_PRG}" \
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
    "${EMU_PORT}" "${OK_ADDR}" "${FAIL_ADDR}" "${STATUS_ADDR}" \
    "${want}" "${PAYLOAD_HEX}" "${label}" <<'PY'
import sys, time
from c64_control_client import Ctl

port = int(sys.argv[1])
ok_addr = int(sys.argv[2], 16)
fail_addr = int(sys.argv[3], 16)
status_addr = int(sys.argv[4], 16)
want = sys.argv[5]
payload = bytes.fromhex(sys.argv[6])
label = sys.argv[7]

last = None
c = None
for _ in range(50):
    try:
        c = Ctl(host="127.0.0.1", port=port, timeout=60.0)
        break
    except OSError as exc:
        last = exc
        time.sleep(0.1)
if c is None:
    sys.exit(f"{label}: connect failed: {last}")

def parse_pc(text):
    for tok in text.split():
        if tok.lower().startswith("pc="):
            return int(tok.split("=", 1)[1], 16)
    raise SystemExit(f"{label}: no pc in {text!r}")

def screen_text():
    raw = c.mem(0x0400, 200)
    chars = []
    for b in raw:
        b &= 0x7F
        if 1 <= b <= 26:
            chars.append(chr(ord("A") + b - 1))
        elif 48 <= b <= 57:
            chars.append(chr(b))
        elif b == 32:
            chars.append(" ")
        else:
            chars.append(".")
    return "".join(chars)

def accept(text):
    # break-exec answers with a data breakpoints frame, not ok.
    result = c.cmd(text)
    if result[0] not in ("ok", "data"):
        raise RuntimeError(f"{text!r} -> {result}")
    return result

try:
    accept("set-turbo 2")
    accept(f"break-exec ${ok_addr:04X}")
    accept(f"break-exec ${fail_addr:04X}")
    state = c.ok("get-state")
    cpu = c.ok("get-cpu")
    pc = parse_pc(cpu)
    paused = state
    if "state=running" in state or pc not in (ok_addr, fail_addr):
        if "state=paused" in state:
            c.ok("run")
        paused = c.ok("wait-paused 30000")
        cpu = c.ok("get-cpu")
        pc = parse_pc(cpu)
    mem = c.mem(0xA000, len(payload))
    status = c.mem(status_addr, 1)[0]
except Exception as exc:
    sys.exit(f"{label}: {exc}")

mem_hex = " ".join(f"{b:02X}" for b in mem)
print(f"{label}: pc=${pc:04X} memory={mem_hex} status={status}")
print(f"{label}: cpu={cpu}")
print(f"{label}: wait={paused}")

if want == "ok":
    if pc != ok_addr or mem != payload:
        print(f"{label}: screen={screen_text()!r}", file=sys.stderr)
        sys.exit(
            f"{label}: wanted probe_ok ${ok_addr:04X} and payload, "
            f"got pc=${pc:04X} status={status}")
elif want == "fail":
    if pc != fail_addr or status != 1:
        print(f"{label}: screen={screen_text()!r}", file=sys.stderr)
        sys.exit(
            f"{label}: wanted probe_fail ${fail_addr:04X} status 1, "
            f"got pc=${pc:04X} status={status}")
else:
    sys.exit(f"{label}: bad want {want}")
PY
  cleanup
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/c64_load_probe.XXXXXX")"
trap 'cleanup; rm -rf "${TMP_ROOT}"' EXIT

HOST_OK="${TMP_ROOT}/host-ok"
HOST_BAD="${TMP_ROOT}/host-bad"
mkdir -p "${HOST_OK}" "${HOST_BAD}"
write_probe_data "${HOST_OK}/probe.prg"
# Wrong CBM name. The success directory has only probe.prg.
write_probe_data "${HOST_BAD}/wrong.prg"

echo "hostfs dir: ${HOST_OK}"
run_case "hostfs-ok" "${HOST_OK}" ok
run_case "hostfs-miss" "${HOST_BAD}" fail

D64="${TMP_ROOT}/probe.d64"
set +e
C1541_OUT="$("${C1541_BIN}" -format "force,66" d64 "${D64}" -write "${HOST_OK}/probe.prg" probe 2>&1)"
C1541_RC=$?
set -e
printf '%s\n' "${C1541_OUT}"
if [[ "${C1541_RC}" -ne 0 ]]; then
  echo "error: ${C1541_BIN} -format/-write failed (${C1541_RC})" >&2
  exit 1
fi
set +e
C1541_DIR="$("${C1541_BIN}" -attach "${D64}" -dir 2>&1)"
C1541_DIR_RC=$?
set -e
printf '%s\n' "${C1541_DIR}"
if [[ "${C1541_DIR_RC}" -ne 0 ]]; then
  echo "error: ${C1541_BIN} -dir failed (${C1541_DIR_RC})" >&2
  exit 1
fi
# -dir prints the stored name in lowercase ("probe"). The write line above
# records it as PROBE; LOAD "PROBE" is what checks the CBM name.
if ! printf '%s\n' "${C1541_DIR}" | grep -E -q '"PROBE"|"probe"'; then
  echo "error: c1541 directory does not list PROBE" >&2
  exit 1
fi

echo "d64: ${D64}"
run_case "d64-ok" "${D64}" ok

echo "emulate_1541 left off"
echo "ok"
