#!/usr/bin/env bash
# Attach to a windowed c64m running the matching bootstrap/device-8 files.
# tools/coop.sh launches that configuration. Port defaults to 6510.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cmake --build "$root/build" --target force_c64
exec python3 "$root/tools/test_c64_banked_runtime.py" --port "${C64M_PORT:-6510}"
