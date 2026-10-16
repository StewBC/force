"""Script ABI, malformed-record and portable tactics behavior regressions."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest
import gen_sdl
import gen_c64
import c64_missions
from c64_layout import ROOT


class Tactics(unittest.TestCase):
    def compile(self, body):
        board = gen_sdl.CompiledMap('fixture', 20, 20, [112]*400, [112]*400)
        board.rooms = [gen_sdl.Room(0, 0, 20, 20, 1)]
        return gen_sdl._ScriptCompiler(Path('fixture.txt'), board).compile(body)

    def test_existing_and_friendly_syntax(self):
        sc = self.compile('beat go:\n spawn 6 A in 1\n spawn 3 player.B at 5,5 kind bazooka batch 1 period 7\n order player.B A cell 10,5 force 10\n')
        self.assertEqual(sc.spawn_letter, [8, 0x31])
        self.assertEqual(sc.spawn_room, [0, 128])
        self.assertEqual(sc.where_kind[0], 1)
        self.assertEqual((sc.where_a[0], sc.where_b[0]), (5, 5))
        self.assertEqual(sc.op_a[-1], 1)

    def test_nest_facings_and_predicates(self):
        for i, face in enumerate(('n', 'e', 's', 'w')):
            sc = self.compile(f'init:\n spawn 1 A at 10,5 kind nest facing {face}\n order A H cell 10,5 force 10\nbeat go:\n wait player.A.strength >= 1 -> go\n')
            self.assertEqual(sc.spawn_letter, [8 | 0x20 | (i << 6)])
            self.assertEqual(sc.pred_who, [0])
            raw = gen_c64.pack_mission_body(0,0,20,20,0,0,[],[],[],sc)
            c64_missions.validate_record(raw, len(raw))

    def test_bridge_predicate(self):
        board = gen_sdl.CompiledMap('fixture', 20, 20, [112]*400, [112]*400)
        board.rooms = [gen_sdl.Room(0, 0, 20, 20, 1)]
        with self.assertRaises(gen_sdl.Error):
            gen_sdl._ScriptCompiler(Path('fixture.txt'), board).compile(
                'beat go:\n wait bridge built -> go\n')
        board.deck_x = [5, 6]
        board.deck_y = [5, 5]
        sc = gen_sdl._ScriptCompiler(Path('fixture.txt'), board).compile(
            'beat go:\n wait bridge built -> go\n')
        self.assertEqual(sc.pred_kind, [gen_sdl.FORCE_PRED_BRIDGE_BUILT])
        raw = gen_c64.pack_mission_body(0,0,20,20,0,0,[],[],[],sc)
        c64_missions.validate_record(raw, len(raw))
        bad = bytearray(raw)
        pred_at = 20 + 4*sc.op_count + sc.beat_count + 5*sc.watch_count
        bad[pred_at] = 11
        with self.assertRaises(ValueError):
            c64_missions.validate_record(bad, len(bad))
        with self.assertRaises(gen_sdl.Error):
            gen_sdl._ScriptCompiler(Path('fixture.txt'), board).compile(
                'beat go:\n wait bridge ready -> go\n')

    def test_invalid_spawns(self):
        for body in ('spawn 33 A in 1', 'spawn 1 player.Z at 2,2',
                     'spawn 1 A at 20,2', 'spawn 1 A kind nest',
                     'spawn 2 A at 2,2 kind nest', 'spawn 1 A facing n',
                     'spawn 1 A kind tank', 'spawn 1 A period 0'):
            with self.subTest(body=body), self.assertRaises(gen_sdl.Error):
                self.compile('beat go:\n '+body+'\n')
        with self.assertRaises(gen_sdl.Error):
            self.compile('init:\n spawn 2 player.A at 2,2\nbeat go:\n')

    def test_malformed_point_and_identity(self):
        sc = self.compile('beat go:\n spawn 1 A at 5,5 kind nest facing w\n')
        raw = bytearray(gen_c64.pack_mission_body(0,0,20,20,0,0,[],[],[],sc))
        template = len(raw)-5
        for offset, value in ((1, 0x18), (2, 0x8F), (3, 0), (4, 0), (0, 0)):
            bad = bytearray(raw); bad[template+offset] = value
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                c64_missions.validate_record(bad, len(bad))

    def test_runtime(self):
        with tempfile.TemporaryDirectory(prefix='force-tactics-') as folder:
            executable = str(Path(folder)/'tactics')
            subprocess.run([os.environ.get('CC','cc'), '-std=c11', '-Wall', '-Wextra', '-Werror',
                            '-I'+str(ROOT/'src/sdl'), str(ROOT/'tools/test_tactics.c'),
                            str(ROOT/'src/sdl/generated/force_data.c'), '-o', executable], check=True)
            subprocess.run([executable], check=True)


if __name__ == '__main__':
    unittest.main()
