"""Biome glyph install. The fixture is not committed art and is not in a container."""
import unittest

import gen_c64
import gen_sdl
from c64_layout import ROOT


class BiomeTests(unittest.TestCase):
    def test_fixture_copies_1024_and_leaves_the_tail(self):
        ram = bytearray(b"\xA5" * 0x2800)
        tail = bytes(ram[0x2400:0x2800])
        fixture = bytes((index * 3 + 1) & 255 for index in range(1024))
        resident = gen_c64.apply_glyph_install(ram, "normandy", {"NORMANDY": fixture}, "")
        self.assertEqual(resident, "normandy")
        self.assertEqual(bytes(ram[0x2000:0x2400]), fixture)
        self.assertEqual(bytes(ram[0x2400:0x2800]), tail)
        ram[0x2000] = 0
        again = gen_c64.apply_glyph_install(ram, "normandy", {}, resident)
        self.assertEqual(again, "normandy")
        self.assertEqual(ram[0x2000], 0)
        missed = gen_c64.apply_glyph_install(ram, "bastogne", {}, again)
        self.assertEqual(missed, "normandy")
        self.assertEqual(ram[0x2000], 0)
        c0 = (ROOT / "build/c64/c0.seq").read_bytes()
        self.assertNotIn(fixture, c0)
        self.assertFalse((ROOT / "assets/tilesets/normandy.bin").exists())
        self.assertFalse((ROOT / "assets/tilesets/bastogne.bin").exists())
        src = (ROOT / "src/c64/load.asm").read_text()
        proc = src.split(".proc glyph_install", 1)[1].split(".endproc", 1)[0]
        self.assertLess(proc.index("jsr open_named"), proc.index("jsr copy_got"))
        self.assertIn("#<CHARSET", proc)
        self.assertIn("cmp #4", proc)
        self.assertIn("bcs missing", proc)
        load = src.split(".proc container_load", 1)[1].split(".endproc", 1)[0]
        self.assertLess(load.index("jsr xor_container"), load.index("jsr glyph_install"))
        self.assertLess(load.index("jsr glyph_install"), load.rindex("sta resident"))

    def test_biome_change_closes_with_room(self):
        items = [
            {"stem": "a", "biome": "normandy", "blob": b"A" * 50},
            {"stem": "b", "biome": "bastogne", "blob": b"B" * 50},
        ]
        packed = gen_c64.pack_containers(items, 1)
        self.assertEqual(len(packed), 2)
        self.assertGreater(packed[0]["left"], 1000)
        self.assertEqual(packed[0]["biome"], "normandy")
        self.assertEqual(packed[1]["biome"], "bastogne")

    def test_short_glyph_file_is_rejected(self):
        ram = bytearray(b"\xA5" * 0x2800)
        with self.assertRaises(gen_sdl.Error):
            gen_c64.apply_glyph_install(ram, "normandy", {"NORMANDY": b"x" * 100}, "")
        self.assertEqual(ram[0x2000], 0xA5)


if __name__ == "__main__":
    unittest.main()
