#!/usr/bin/env python3
"""Launch a windowed IIgs with a private disk copy and debugger socket."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = ROOT.parent.parent / 'external' / 'gssquared'


def emulator_path(explicit=None, source=DEFAULT_SOURCE):
    candidates = [Path(explicit).expanduser()] if explicit else [
        ROOT / 'build/iigs/emulator/GSSquared.app/Contents/MacOS/GSSquared',
        source / 'build/GSSquared.app/Contents/MacOS/GSSquared',
        source / 'build/GSSquared',
        Path('/Applications/GSSquared.app/Contents/MacOS/GSSquared'),
    ]
    for candidate in candidates:
        if '.app/Contents/MacOS/' in str(candidate) and not (candidate.parent.parent / 'Resources').is_dir():
            continue  # An uninstalled CMake app has neither resources nor bundled dylibs.
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate.resolve()
    raise FileNotFoundError('GSSquared not found; pass --emulator /path/to/GSSquared')


def launch(disk, emulator, folder=None, socket_path=None, timeout=15.0):
    disk = Path(disk).resolve()
    if not disk.is_file():
        raise FileNotFoundError(f'Disk not found: {disk}; build the IIgs disk first')
    if folder is None:
        folder = Path(tempfile.mkdtemp(prefix='force-iigs-'))
    else:
        folder = Path(folder).resolve()
        folder.mkdir(parents=True, exist_ok=False)
    socket_path = Path(socket_path) if socket_path else folder / 'debug.sock'
    if socket_path.exists():
        raise FileExistsError(f'Refusing to reuse debugger socket: {socket_path}')
    if len(os.fsencode(str(socket_path))) > 100:
        raise ValueError('Debugger socket path is too long; pass a short --socket under /tmp')
    private_disk = folder / ('force' + disk.suffix)
    shutil.copy2(disk, private_disk)
    command = [str(emulator), '-p', '5', '-ds7d1=' + str(private_disk),
               '--debug', str(socket_path), '--no-quit-confirm', '-s']
    with (folder / 'emulator.log').open('w') as log:
        proc = subprocess.Popen(command, cwd=folder, stdout=log,
                                stderr=subprocess.STDOUT, start_new_session=True)
    manifest = disk.parent / 'symbols.json'
    private_manifest = folder / 'symbols.json'
    if manifest.is_file():
        shutil.copy2(manifest, private_manifest)
    result = dict(pid=proc.pid, emulator=str(emulator), disk=str(private_disk),
                  socket=str(socket_path), log=str(folder / 'emulator.log'),
                  session=str(folder), symbols=str(private_manifest) if private_manifest.is_file() else None)
    (folder / 'session.json').write_text(json.dumps(result, indent=2) + '\n')
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f'GSSquared exited ({proc.returncode}); see {result["log"]}')
        if socket_path.exists():
            return result
        time.sleep(.1)
    # Leave an owned, visible process available for diagnosis; never kill other instances.
    raise TimeoutError(f'No debugger socket after {timeout:g}s; PID {proc.pid}; see {result["log"]}')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--disk', type=Path, default=ROOT / 'build/iigs/force.2mg')
    ap.add_argument('--emulator', type=Path)
    ap.add_argument('--gssquared-source', type=Path, default=DEFAULT_SOURCE)
    ap.add_argument('--session', type=Path, help='New private session directory (must not exist)')
    ap.add_argument('--socket', type=Path)
    ap.add_argument('--timeout', type=float, default=15)
    args = ap.parse_args()
    print(json.dumps(launch(args.disk, emulator_path(args.emulator, args.gssquared_source),
                            args.session, args.socket, args.timeout), indent=2))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError) as exc:
        raise SystemExit(str(exc))
