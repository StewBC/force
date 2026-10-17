#!/usr/bin/env python3
"""Validate every compiled glyph/paper combination and IIgs-only asset emission."""
from pathlib import Path
import re
import struct
import tempfile
import unittest
import assets
from sprites import words

ROOT=Path(__file__).resolve().parents[2]


class Assets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder=tempfile.TemporaryDirectory(prefix='force-iigs-assets-')
        cls.out=Path(cls.folder.name)
        c64_charset=ROOT/'src/c64/generated/charset.bin'
        cls.before=c64_charset.stat().st_mtime_ns if c64_charset.exists() else None
        cls.sources,cls.catalogue=assets.generate(ROOT,cls.out)
        cls.charset=(cls.out/'charset.bin').read_bytes()

    @classmethod
    def tearDownClass(cls):
        cls.folder.cleanup()

    def test_emission_is_independent_of_c64_generated_files(self):
        path=ROOT/'src/c64/generated/charset.bin'
        self.assertEqual(path.stat().st_mtime_ns if path.exists() else None,self.before)
        self.assertEqual({"mission%d.asm"%row["id"] for row in self.catalogue},
                         {path.name for path in self.sources if path.stem.startswith("mission")})
        self.assertIn("titledata.asm",[path.name for path in self.sources])
        contract=(self.out/'asset_contracts.s').read_text()
        size=int(re.search(r'ACTIVE_BYTES equ (\d+)',contract)[1])
        self.assertEqual(size%2,0)
        for row in self.catalogue:
            self.assertLess(row['bytes'],65536)
            self.assertGreaterEqual(row['routes'],1)

    def test_expanded_byte_lookup(self):
        source=(self.out/'celllookup.asm').read_text()
        data=bytes.fromhex(''.join(re.findall(r"dc h'([0-9A-F]+)'",source)))
        self.assertEqual(len(data),40960)
        for variant in range(40):
            for bits in range(256):
                offset=(variant*256+bits)*4
                actual=bytes(n for b in data[offset:offset+4] for n in (b>>4,b&15))
                if variant<8:
                    expected=bytes((2,11,14,variant)[(bits>>(6-(x//2)*2))&3] for x in range(8))
                else:
                    ink=(variant-8)%16;background=0 if variant<24 else 11
                    expected=bytes(ink if bits&(128>>x) else background for x in range(8))
                self.assertEqual(actual,expected,(variant,bits))

    def test_all_glyphs_all_papers_match_source_pixels(self):
        for tile in range(128):
            glyph=self.charset[tile*8:tile*8+8]
            stream=list(words(glyph))
            self.assertEqual(len(stream),16)
            for paper in range(8):
                pixels=bytearray(64)
                for n,(base,mask) in enumerate(stream):
                    value=base | ((paper*0x1111)&mask)
                    # Hardware PHA stores high byte first while S descends.
                    y=7-n//2
                    x=4 if n%2==0 else 0
                    packed=struct.pack('<H',value)
                    pixels[y*8+x:y*8+x+4]=bytes(v for byte in packed for v in (byte>>4,byte&15))
                reference=bytes(color for bits in glyph for shift in (6,4,2,0)
                                for color in [(2,11,14,paper)[(bits>>shift)&3]] for _ in range(2))
                self.assertEqual(bytes(pixels),reference,(tile,paper))


if __name__=='__main__':unittest.main()
