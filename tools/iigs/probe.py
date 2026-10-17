#!/usr/bin/env python3
"""Inspect/control GSSquared through its bundled, documented Python client."""
from __future__ import annotations
import argparse
from contextlib import contextmanager
import json
from pathlib import Path
import struct
import sys
import zlib

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = ROOT.parent.parent / 'external/gssquared'


def client_class(source=DEFAULT_SOURCE):
    client_dir = Path(source) / 'clients/python/src'
    if not client_dir.is_dir():
        raise FileNotFoundError(f'gs2debug client missing: {client_dir}; pass --gssquared-source')
    sys.path.insert(0, str(client_dir))
    from gs2debug import Client
    class BoundedClient(Client):
        def request(self, msg_type, payload=b'', *, timeout=10):
            return super().request(msg_type, payload, timeout=timeout)
    return BoundedClient


def registers(raw):
    if len(raw) != 40:
        raise ValueError(f'Expected 40-byte CPU snapshot, got {len(raw)}')
    result = {'cycle': struct.unpack_from('<Q', raw)[0], 'p': raw[13],
              'db': raw[14], 'pb': raw[15]}
    result.update(zip(('pc', 'a', 'x', 'y', 'sp', 'd'), struct.unpack_from('<6H', raw, 16)))
    result['address'] = result['pb'] * 65536 + result['pc']
    return result


@contextmanager
def stopped(client):
    running = client.get_status().execution_mode == 0
    if running:
        client.pause()
        client.wait_stopped(timeout=5)
    try:
        yield
    finally:
        if running:
            client.continue_()


def read(client, address, length, domain=0):
    if not 0 <= address < 0x1000000 or not 0 <= length <= 0x1000000 - address:
        raise ValueError('Invalid 24-bit memory range')
    return b''.join(client.read_mem(domain, address + offset, min(4096, length - offset))
                    for offset in range(0, length, 4096))


def decode_shr(pixels, controls, palettes):
    """Decode actual 320-mode SHR pixels, including per-line palette/fill."""
    if len(pixels) != 32000 or len(controls) != 200 or len(palettes) != 512:
        raise ValueError('Invalid SHR buffer lengths')
    rgb = bytearray()
    for y, control in enumerate(controls):
        if control & 128:
            raise ValueError(f'Scanline {y} uses 640 mode; this probe expects 320-mode FORCE')
        palette = (control & 15) * 32
        previous = 0
        for byte in pixels[y * 160:(y + 1) * 160]:
            for index in (byte >> 4, byte & 15):
                if control & 32:
                    if index == 0:
                        index = previous
                    previous = index
                color = struct.unpack_from('<H', palettes, palette + index * 2)[0]
                rgb.extend((((color >> 8) & 15) * 17, ((color >> 4) & 15) * 17, (color & 15) * 17))
    return bytes(rgb)


def png(path, rgb, width=320, height=200):
    if len(rgb) != width * height * 3:
        raise ValueError('RGB byte length does not match image geometry')
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    rows = b''.join(b'\0' + rgb[y * width * 3:(y + 1) * width * 3] for y in range(height))
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--socket', required=True)
    ap.add_argument('--gssquared-source', type=Path, default=DEFAULT_SOURCE)
    sub = ap.add_subparsers(dest='command', required=True)
    for name in ('status', 'pause', 'resume', 'quit'):
        sub.add_parser(name)
    step = sub.add_parser('step'); step.add_argument('count', nargs='?', type=int, default=1)
    text = sub.add_parser('text'); text.add_argument('text')
    key = sub.add_parser('key'); key.add_argument('scancode', type=lambda x: int(x, 0))
    mem = sub.add_parser('memory'); mem.add_argument('address', type=lambda x: int(x, 0)); mem.add_argument('length', type=lambda x: int(x, 0))
    capture = sub.add_parser('framebuffer'); capture.add_argument('output', type=Path)
    args = ap.parse_args()
    with client_class(args.gssquared_source)() as client:
        client.connect(args.socket)
        client.hello()
        if args.command == 'status':
            state = client.get_status()
            with stopped(client):
                print(json.dumps(dict(platform=state.platform_id, execution_mode=state.execution_mode,
                                      registers=registers(client.get_regs())), indent=2))
        elif args.command == 'pause':
            if client.get_status().execution_mode == 0:
                client.pause(); client.wait_stopped(timeout=5)
        elif args.command == 'resume':
            client.continue_()
        elif args.command == 'quit':
            client.quit()
        elif args.command == 'step':
            if args.count < 1:
                raise ValueError('Step count must be positive')
            if client.get_status().execution_mode == 0:
                client.pause(); client.wait_stopped(timeout=5)
            client.step_into(args.count)
            event = client.wait_stopped(timeout=10)
            print(json.dumps(dict(reason=event.reason, registers=registers(client.get_regs())), indent=2))
        elif args.command == 'text':
            client.type_text(args.text)
        elif args.command == 'key':
            client.tap_key(args.scancode)
        elif args.command == 'memory':
            with stopped(client):
                print(read(client, args.address, args.length).hex())
        elif args.command == 'framebuffer':
            with stopped(client):
                pixels = read(client, 0xe12000, 32000)
                controls = read(client, 0xe19d00, 200)
                palettes = read(client, 0xe19e00, 512)
            png(args.output, decode_shr(pixels, controls, palettes))
            print(str(args.output.resolve()))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, TimeoutError) as exc:
        raise SystemExit(str(exc))
