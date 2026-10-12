#!/usr/bin/env bash
# Cooperative live-debug session for FORCE.
#
#   tools/coop.sh
#
# 1. Generate farm tables and assemble the PRG (unless FORCE_SKIP_BUILD=1)
# 2. If the control port is free: start windowed c64m from ../machines
# 3. Run ../machines/tools/c64/coop_watch.py in the foreground
#
# Windowed on purpose. Do not pass --headless.
# You play; pause on a glitch → build/debug/snap-NNN.txt
# Agent steers: echo resume >> build/debug/coop_inbox
# Watcher protocol: machines/tools/c64/coop_watch.py
#
# Env:
#   C64M_PORT         default 6510
#   C64M_ROOT         default ../machines
#   FORCE_SKIP_BUILD  1 = skip generate + assemble

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE_ROOT="$(cd "${TOOLS_DIR}/.." && pwd)"
MACHINES_ROOT="${C64M_ROOT:-$(cd "${FORCE_ROOT}/../machines" && pwd)}"
C64M_BIN="${MACHINES_ROOT}/build/c64m"
AM65="${MACHINES_ROOT}/build/am65"
WATCHER="${MACHINES_ROOT}/tools/c64/coop_watch.py"
PRG="${FORCE_ROOT}/build/force.prg"
PORT="${C64M_PORT:-6510}"

if [[ ! -x "${C64M_BIN}" ]]; then
  echo "error: missing ${C64M_BIN}" >&2
  exit 1
fi
if [[ ! -x "${AM65}" ]]; then
  echo "error: missing ${AM65}" >&2
  exit 1
fi
if [[ ! -f "${WATCHER}" ]]; then
  echo "error: missing ${WATCHER}" >&2
  exit 1
fi

port_open() {
  python3 -c 'import socket, sys
s = socket.socket()
s.settimeout(0.25)
rc = s.connect_ex(("127.0.0.1", int(sys.argv[1])))
s.close()
sys.exit(0 if rc == 0 else 1)' "$1" 2>/dev/null
}

if [[ "${FORCE_SKIP_BUILD:-0}" != "1" ]]; then
  cmake --build "${FORCE_ROOT}/build" --target force_c64
fi

if [[ ! -f "${PRG}" ]]; then
  echo "error: missing ${PRG}" >&2
  exit 1
fi

mkdir -p "${FORCE_ROOT}/build/debug"

if port_open "${PORT}"; then
  echo "coop: control port ${PORT} already open — attaching watcher only"
  echo "      (another client must not hold the socket)"
else
  echo "coop: starting windowed c64m --pal --control-port=${PORT} --prg ${PRG} --autorun"
  echo "      cwd=${MACHINES_ROOT}"
  (
    cd "${MACHINES_ROOT}"
    exec "${C64M_BIN}" --pal --control-port="${PORT}" --prg "${PRG}" --autorun --disk "8=${FORCE_ROOT}/build/c64"
  ) &
  EMU_PID=$!
  disown "${EMU_PID}" 2>/dev/null || true
  for _ in $(seq 1 80); do
    if port_open "${PORT}"; then
      sleep 0.4
      break
    fi
    sleep 0.15
  done
  if ! port_open "${PORT}"; then
    kill "${EMU_PID}" 2>/dev/null || true
    echo "error: control port ${PORT} did not open" >&2
    exit 1
  fi
  echo "coop: emulator up on port ${PORT}"
fi

echo "coop: watcher → build/debug/snap-*.txt  inbox → build/debug/coop_inbox"
echo "coop: play, pause on glitch; Ctrl-C stops the watcher (emu keeps running if we started it)"
echo ""

cd "${FORCE_ROOT}"
exec python3 "${WATCHER}" --port "${PORT}" --out-dir "${FORCE_ROOT}/build/debug"
