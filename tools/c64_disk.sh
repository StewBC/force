#!/usr/bin/env bash
# Write force.prg and farm.prg onto one .d64.
#
#   tools/c64_disk.sh build/force.prg build/c64/farm.prg build/force.d64
#
# $C1541, when set, is the c1541 executable (path and file name).
# When it is unset, c1541 is taken from PATH.

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: c64_disk.sh force.prg farm.prg force.d64" >&2
  exit 1
fi

prg=$1
farm=$2
d64=$3

# A value with no slash is a command name (PATH). A path must exist.
if [[ -n "${C1541:-}" ]]; then
  bin=$C1541
  if [[ "$bin" == */* && ! -x "$bin" ]]; then
    echo "error: c1541 is not executable: $bin" >&2
    exit 1
  fi
elif command -v c1541 >/dev/null 2>&1; then
  bin=$(command -v c1541)
else
  echo "error: c1541 not found on PATH (C1541 is unset)" >&2
  exit 1
fi

for src in "$prg" "$farm"; do
  if [[ ! -f "$src" ]]; then
    echo "error: missing $src" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$d64")"
"$bin" -format "force,66" d64 "$d64" \
  -write "$prg" force \
  -write "$farm" farm
echo "c64_disk: $d64"
