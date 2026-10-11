"""Bank-label compiler regressions. Run: python3 tools/test_c64_components.py."""
import unittest

import gen_c64


class BankComponents(unittest.TestCase):
    def bake(self, w, h, tiles, paper, decks):
        classes = [0] * 128
        classes[16] = 1  # wall
        classes[64] = classes[80] = 3  # barrier / unfinished deck
        return gen_c64.bind_deck_components(
            w, h, tiles, paper, classes, {1, 3},
            [x for x, y in decks], [y for x, y in decks],
        )

    def test_separate_banks_and_terrain(self):
        w, h = 7, 5
        paper = [5] * (w * h)
        tiles = [112] * (w * h)
        for y in range(h):
            paper[y * w + 3] = 6
        tiles[0] = 16
        tiles[1] = 64
        tiles[2] = 48  # roof is dry walkable ground
        result = self.bake(w, h, tiles, paper, [(3, 2)])
        self.assertEqual([p & 15 for p in result], paper)
        self.assertEqual(result[0] >> 4, 0)
        self.assertEqual(result[1] >> 4, 0)
        self.assertEqual(result[2] >> 4, 2)
        self.assertEqual(result[2 * w + 2] >> 4, 2)
        self.assertEqual(result[2 * w + 4] >> 4, 1)
        self.assertTrue(all(result[y * w + 3] == 6 for y in range(h)))

    def test_large_bank_and_deck_on_dry_ground(self):
        w = h = 40
        result = self.bake(w, h, [112] * (w * h), [5] * (w * h), [(20, 20)])
        self.assertEqual(sum(p >> 4 == 1 for p in result), w * h - 1)
        self.assertEqual(result[20 * w + 20], 5)

    def test_no_deck_and_unconnected_ground(self):
        self.assertEqual(self.bake(2, 2, [112] * 4, [5] * 4, []), [5] * 4)
        # A dry island that does not touch the deck stays unlabelled.
        result = self.bake(5, 1, [112] * 5, [5, 6, 6, 6, 5], [(1, 0)])
        self.assertEqual(result, [21, 6, 6, 6, 5])

    def test_component_overflow_fails_build(self):
        # Each water deck has isolated dry ground on both sides.
        w, h = 33, 3
        paper = [6] * (w * h)
        decks = [(x, 1) for x in range(1, w, 2)]
        for x, y in decks:
            paper[x] = paper[2 * w + x] = 5
        with self.assertRaisesRegex(gen_c64.gen_sdl.Error, '15 paper component'):
            self.bake(w, h, [112] * (w * h), paper, decks)


if __name__ == '__main__':
    unittest.main()
