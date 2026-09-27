#!/usr/bin/env bash
# Write the program and its data files onto one .d64.
#
#   tools/c64_disk.sh build/force.d64 build/force.prg \
#       build/c64/normandy.prg normandy \
#       build/c64/bastogne.prg bastogne \
#       build/c64/campaign.prg campaign
#
# Each data file is a host path followed by its CBM name. A name ending
# in ,s is stored as a sequential file. $C1541, when set, is the c1541
# executable (path or command name). When it is unset, c1541 comes from PATH.

set -euo pipefail

if [[ $# -lt 2 || $(( ($# - 2) % 2 )) -ne 0 ]]; then
  echo "usage: c64_disk.sh dest.d64 force.prg [file cbmname]..." >&2
  exit 1
fi

d64=$1
prg=$2
shift 2

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

if [[ ! -f "$prg" ]]; then
  echo "error: missing $prg" >&2
  exit 1
fi

args=(-format "force,66" d64 "$d64" -write "$prg" force)
while [[ $# -gt 0 ]]; do
  src=$1
  name=$2
  shift 2
  if [[ ! -f "$src" ]]; then
    echo "error: missing $src" >&2
    exit 1
  fi
  args+=(-write "$src" "$name")
done

mkdir -p "$(dirname "$d64")"
"$bin" "${args[@]}"
echo "c64_disk: $d64"
