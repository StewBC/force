"""Objective syntax and C64 mission-pack pointer regressions."""
import unittest
from pathlib import Path

import gen_sdl
import gen_c64


class ObjectiveTests(unittest.TestCase):
    def compile(self, text):
        board = gen_sdl.CompiledMap('test', 1, 1, [112], [112])
        return gen_sdl._ScriptCompiler(Path('test.txt'), board).compile(text)

    def test_init_and_beat_text(self):
        sc = self.compile('init:\n objective "Hold #1: \\ farm" # comment\n'
                          'beat last:\n objective "Move -> west"\n win\n')
        self.assertEqual(sc.objective_text, ['Hold #1: \\ farm', 'Move -> west'])
        self.assertEqual(sc.beat_pc, [1])
        self.assertEqual(sc.op_code[:2], [10, 10])
        self.assertIn('\\\\', gen_sdl.emit_script_arrays('test', sc))

    def test_bounds_and_quotes(self):
        for text in ['', 'x' * 39, 'é', 'bad"quote']:
            with self.subTest(text=text), self.assertRaises(gen_sdl.Error):
                self.compile(f'beat last:\n objective "{text}"\n win\n')
        self.compile('beat last:\n objective "' + 'x' * 38 + '"\n win\n')
        with self.assertRaises(gen_sdl.Error):
            self.compile('beat last:\n objective unquoted\n win\n')

    def test_bundle_pointers_across_missions(self):
        scripts = {stem: self.compile(f'init:\n objective "{value}"\n'
                                     'beat last:\n objective "Shared"\n win\n')
                   for stem, value in [('first', 'Hold the farm'), ('second', 'Move west')]}
        parts = [(stem, gen_c64.pack_mission_body(0, 0, 1, 1, 0, 0, [], [], [], sc))
                 for stem, sc in scripts.items()]
        packed = gen_c64.pack_mission_set(parts, scripts)
        import c64_missions
        for index, (stem, body) in enumerate(parts):
            record, body_length = c64_missions.unpack(packed, index)
            self.assertEqual(body_length, len(body))
            sc = scripts[stem]
            for pc in (0, 1):
                lo = record[20 + sc.op_count + pc]
                hi = record[20 + 2 * sc.op_count + pc]
                offset = lo | hi << 8
                self.assertGreaterEqual(offset, body_length)
                value = record[offset:record.index(0, offset)].decode('ascii')
                self.assertEqual(value, sc.objective_text[sc.op_a[pc]])



if __name__ == '__main__':
    unittest.main()
