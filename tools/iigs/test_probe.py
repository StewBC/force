#!/usr/bin/env python3
"""Check framebuffer decoding against independent palette/pixel examples."""
import struct
import tempfile
from pathlib import Path
import unittest
import zlib
from probe import decode_shr, png, registers


class Framebuffer(unittest.TestCase):
    def test_pixels_palette_selection_and_fill(self):
        pixels = bytearray(32000)
        pixels[0] = 0x12
        pixels[160] = 0x10
        palettes = bytearray(512)
        struct.pack_into('<H', palettes, 2, 0xf00)
        struct.pack_into('<H', palettes, 4, 0x0f0)
        struct.pack_into('<H', palettes, 32 + 2, 0x00f)
        controls = bytearray(200)
        controls[1] = 0x21  # Second palette, fill zero with previous colour.
        rgb = decode_shr(pixels, controls, palettes)
        self.assertEqual(rgb[:9], bytes((255, 0, 0, 0, 255, 0, 0, 0, 0)))
        self.assertEqual(rgb[960:969], bytes((0, 0, 255)) * 3)

    def test_rejects_640(self):
        with self.assertRaisesRegex(ValueError, '640 mode'):
            decode_shr(bytes(32000), bytes([128]) + bytes(199), bytes(512))

    def test_png_preserves_exact_rgb(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'screen.png'
            rgb = bytes((12, 34, 56, 78, 90, 123))
            png(path, rgb, 2, 1)
            data = path.read_bytes()
            self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
            at = 8
            chunks = {}
            while at < len(data):
                count = struct.unpack_from('>I', data, at)[0]
                kind = data[at+4:at+8]
                payload = data[at+8:at+8+count]
                checksum = struct.unpack_from('>I', data, at+8+count)[0]
                self.assertEqual(checksum, zlib.crc32(kind+payload) & 0xffffffff)
                chunks[kind] = payload
                at += count + 12
            self.assertEqual(zlib.decompress(chunks[b'IDAT']), b'\0' + rgb)

    def test_cpu_snapshot(self):
        raw = bytearray(40)
        raw[15] = 0x12
        struct.pack_into('<6H', raw, 16, 0x3456, 1, 2, 3, 0x1ff, 0x400)
        state = registers(raw)
        self.assertEqual((state['address'], state['d'], state['sp']), (0x123456, 0x400, 0x1ff))


if __name__ == '__main__':
    unittest.main()
