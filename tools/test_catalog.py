"""Stem catalog grammar, play-bounds clamp, and cropped map geometry."""
import unittest

import c64_layout as layout
import gen_sdl

PRODUCTION = """
# biome stem [cam=x,y] "Title"
normandy farm "Hold the Farm"
normandy cross "Cross the river"
normandy river "Hold the river"
normandy base "Take the ridge base"
normandy ridge "Take the Ridge"
bastogne bastogne "Something Else"
"""

OLD_LINES = """
hold_farm normandy 40,0,40,20 farm "Hold the Farm"
cross_river normandy 0,0,40,20 cross "Cross the river"
hold_river normandy 0,0,40,20 river "Hold the river"
take_base normandy 0,0,40,40 base cam=0,0 "Take the ridge base"
take_ridge normandy 0,20,80,20 ridge cam=0,20 "Take the Ridge"
hold_bastogne bastogne 40,0,40,20 bastogne "Something Else"
"""


class StemCatalog(unittest.TestCase):
    def test_production_lines(self):
        rows = gen_sdl.load_stem_catalog(PRODUCTION)
        self.assertEqual(
            [row[0] for row in rows],
            ["farm", "cross", "river", "base", "ridge", "bastogne"],
        )
        self.assertEqual(
            [row[1] for row in rows],
            ["normandy", "normandy", "normandy", "normandy", "normandy", "bastogne"],
        )
        self.assertEqual(rows[0][2:], (0, 0, "Hold the Farm"))
        self.assertEqual(rows[3][4], "Take the ridge base")
        self.assertEqual(rows[5][4], "Something Else")

    def test_rejects_rect_title_repeat_and_long_names(self):
        with self.assertRaises(gen_sdl.Error):
            gen_sdl.load_stem_catalog(
                'hold_farm normandy 40,0,40,20 farm "Hold the Farm"\n'
            )
        with self.assertRaises(gen_sdl.Error):
            gen_sdl.load_stem_catalog('normandy farm "' + "x" * 28 + '"\n')
        with self.assertRaises(gen_sdl.Error):
            gen_sdl.load_stem_catalog(
                'normandy farm "Hold the Farm"\nnormandy farm "Again"\n'
            )
        long_name = "a" * 16
        self.assertRegex(long_name, gen_sdl.IDENT_RE.pattern)
        with self.assertRaises(gen_sdl.Error):
            gen_sdl.load_stem_catalog(f'{long_name} farm "Hold the Farm"\n')
        with self.assertRaises(gen_sdl.Error):
            gen_sdl.load_stem_catalog(f'normandy {long_name} "Hold the Farm"\n')

    def test_cam_clamp(self):
        rows = gen_sdl.load_stem_catalog('normandy farm cam=0,20 "Hold the Farm"\n')
        self.assertEqual(rows[0][2:4], (0, 20))
        self.assertEqual(gen_sdl.play_bounds(40, 20, 0, 20), (0, 0, 40, 20, 0, 0))
        self.assertEqual(gen_sdl.play_bounds(80, 40, 0, 20), (0, 0, 80, 40, 0, 20))
        with self.assertRaises(gen_sdl.Error):
            gen_sdl.load_stem_catalog('normandy farm cam=0,-1 "Hold the Farm"\n')

    def test_production_file_is_the_stem_catalog(self):
        path = layout.ROOT / "assets" / "missions.txt"
        rows = gen_sdl.load_missions(path)
        self.assertEqual(
            [row[0] for row in rows],
            ["farm", "cross", "river", "base", "ridge", "bastogne"],
        )
        self.assertEqual(rows[0][1], "normandy")
        self.assertEqual(rows[0][4], "Hold the Farm")
        with self.assertRaises(gen_sdl.Error):
            gen_sdl.load_stem_catalog(OLD_LINES)
        with self.assertRaises(gen_sdl.Error):
            gen_sdl.load_stem_catalog(
                'hold_farm normandy 40,0,40,20 farm "Hold the Farm"\n'
            )

    def _compiled(self, stem):
        root = layout.ROOT
        name_per_id, classes, empty_tile = gen_sdl.load_tile_desc(
            root / "assets" / "tiles.txt"
        )
        chip = gen_sdl.load_properties_txt(root / "assets" / "properties.txt")
        _tw, _th, _columns, count, _png = gen_sdl.load_tsx(
            root / "assets" / "maps" / "tiles.tsx"
        )
        class_table = [classes["empty"]] * count
        for tid in range(count):
            if tid < len(name_per_id) and name_per_id[tid] is not None:
                class_table[tid] = classes[name_per_id[tid]]
        path = root / "assets" / "maps" / f"{stem}.tmx"
        name, width, height, planes, firstgid = gen_sdl.load_tmx(
            path, count, empty_tile
        )
        return gen_sdl.compile_map(
            name, width, height, planes, firstgid, empty_tile,
            chip, class_table, classes,
        )

    def test_cropped_room_geometry(self):
        rows = {
            stem: (cx, cy)
            for stem, _biome, cx, cy, _title in gen_sdl.load_missions(
                layout.ROOT / "assets" / "missions.txt"
            )
        }
        farm = self._compiled("farm")
        self.assertEqual((farm.width, farm.height), (40, 20))
        colour4 = next(room for room in farm.rooms if room.colour == 4)
        self.assertEqual(colour4.x0, 0)
        self.assertEqual(
            gen_sdl.play_bounds(farm.width, farm.height, *rows["farm"])[:4],
            (0, 0, 40, 20),
        )
        base = self._compiled("base")
        colour12 = next(room for room in base.rooms if room.colour == 12)
        self.assertEqual(colour12.w, 10)
        ridge = self._compiled("ridge")
        self.assertEqual((ridge.width, ridge.height), (80, 20))
        ridge12 = next(room for room in ridge.rooms if room.colour == 12)
        self.assertEqual(ridge12.w, 12)


if __name__ == "__main__":
    unittest.main()
