"""Container fit, the 6500-byte second pass, and the loader's refuse path."""
import unittest

import gen_c64
import gen_sdl
from c64_layout import ROOT


def model_read(image: bytes, extra: int, limit: int, clip: bool) -> bytes:
    """PRG file is a 2-byte address plus the payload. Skip 2+extra, then store.

    clip means the byte that would land on the exclusive limit is dropped and
    the read succeeds. A short skip is an error, matching read_file.
    """
    skip = 2 + extra
    if skip > len(image):
        raise AssertionError("eof during skip")
    out = bytearray()
    index = skip
    while index < len(image):
        if len(out) >= limit:
            if clip:
                return bytes(out)
            raise AssertionError("write past limit")
        out.append(image[index])
        index += 1
    return bytes(out)


class ContainerTests(unittest.TestCase):
    def test_three_share_a_container(self):
        items = [
            {"stem": "a", "biome": "normandy", "blob": b"A" * 100},
            {"stem": "b", "biome": "normandy", "blob": b"B" * 100},
            {"stem": "c", "biome": "normandy", "blob": b"C" * 100},
        ]
        packed = gen_c64.pack_containers(items, 1)
        self.assertEqual(len(packed), 1)
        self.assertEqual([m["stem"] for m in packed[0]["missions"]], ["a", "b", "c"])
        self.assertGreater(packed[0]["left"], 0)
        self.assertLessEqual(packed[0]["used"], gen_c64.CONTAINER_CAP)

    def test_size_split_at_6650(self):
        blob = b"Z" * 2000
        items = [
            {"stem": f"m{i}", "biome": "normandy", "blob": blob} for i in range(4)
        ]
        three = gen_c64.container_overhead(3) + 3 * 2000
        four = gen_c64.container_overhead(4) + 4 * 2000
        self.assertLessEqual(three, gen_c64.CONTAINER_CAP)
        self.assertGreater(four, gen_c64.CONTAINER_CAP)
        packed = gen_c64.pack_containers(items, 1)
        self.assertEqual([len(c["missions"]) for c in packed], [3, 1])
        self.assertLessEqual(packed[0]["used"], gen_c64.CONTAINER_CAP)
        self.assertGreater(packed[0]["left"], 0)

    def test_one_blob_over_the_cap_fails(self):
        room = gen_c64.CONTAINER_CAP - gen_c64.container_overhead(1)
        blob = b"Q" * (room + 1)
        with self.assertRaises(gen_sdl.Error):
            gen_c64.pack_containers(
                [{"stem": "big", "biome": "normandy", "blob": blob}], 1
            )

    def test_biome_closes_with_room_to_spare(self):
        items = [
            {"stem": "a", "biome": "normandy", "blob": b"A" * 50},
            {"stem": "b", "biome": "bastogne", "blob": b"B" * 50},
        ]
        packed = gen_c64.pack_containers(items, 1)
        self.assertEqual(len(packed), 2)
        self.assertGreater(packed[0]["left"], 1000)
        self.assertEqual(packed[0]["biome"], "normandy")
        self.assertEqual(packed[1]["biome"], "bastogne")
        self.assertEqual(packed[0]["payload"][9], len(b"normandy"))

    def test_real_missions_and_bastogne_split(self):
        missions = gen_sdl.load_missions(ROOT / "assets" / "missions.txt")
        items = []
        for stem, biome, _cx, _cy, _title in missions:
            data = gen_c64._compute(stem)
            blob, codecs = gen_c64.encode_fmsn(data)
            self.assertLessEqual(len(blob), gen_c64.CONTAINER_CAP - gen_c64.container_overhead(1))
            self.assertEqual(blob[:4], b"FMSN")
            self.assertEqual(blob[5], 6)
            rows = gen_c64.fmsn_directory(blob)
            self.assertEqual([row[0] for row in rows], [8, 1, 5, 6, 3, 4])
            for _schema, _codec, _xor, off, stored, dest, cap, decoded, _body in rows:
                gen_c64.assert_chunk_placement(0xE600, stored, dest, decoded)
                self.assertFalse(0xE600 <= dest < 0xFFFA)
                self.assertLess(dest + cap, 0xE600)
                self.assertGreaterEqual(off, 108)
                self.assertLessEqual(off + stored, len(blob))
            items.append({"stem": stem, "biome": biome, "blob": blob, "codecs": codecs})
        packed = gen_c64.pack_containers(items, gen_c64.COMPAT)
        home = {}
        for container in packed:
            self.assertLessEqual(container["used"], gen_c64.CONTAINER_CAP)
            biomes = {container["biome"]}
            self.assertEqual(len(biomes), 1)
            for mission in container["missions"]:
                home[mission["stem"]] = container["id"]
        self.assertEqual(set(home), {row[0] for row in missions})
        self.assertNotEqual(home["ridge"], home["bastogne"])
        self.assertEqual(home["farm"], home["cross"])
        self.assertEqual(home["cross"], home["river"])
        record_codecs = {item["codecs"][8] for item in items}
        self.assertEqual(record_codecs, {0, 1})

    def test_pass1_stores_the_tail(self):
        payload = bytes((index + index // 256) & 255 for index in range(6500))
        self.assertNotEqual(payload[6400:6500], payload[0:100])
        image = b"\x00\xa0" + payload
        first = model_read(image, extra=0, limit=6400, clip=True)
        second = model_read(image, extra=6400, limit=100, clip=True)
        self.assertEqual(first, payload[:6400])
        self.assertEqual(second, payload[6400:6500])
        self.assertNotEqual(second, payload[:100])
        self.assertEqual(b"\x00\xa0" + payload[:6400] + second, image[:2] + payload)

    def test_measure_got_inverts_sbc_carry(self):
        load = (ROOT / "src/c64/load.asm").read_text()
        proc = load.split(".proc measure_got", 1)[1].split(".endproc", 1)[0]
        lines = [ln.split(";")[0].strip() for ln in proc.splitlines()]
        lines = [ln for ln in lines if ln]
        tail = lines[lines.index("sta ctr_got+1") + 1:]
        self.assertEqual(tail, ["bcc below", "clc", "rts", "below:", "sec", "rts"])

    def test_reader_opens_logical_file_two(self):
        text = (ROOT / "src/c64/transfer.inc").read_text()
        proc = text.split(".proc read_file", 1)[1].split(".endproc", 1)[0]
        window = proc.split("jsr $FFBA", 1)[0]
        lines = [ln.split(";")[0].strip() for ln in window.splitlines()]
        lines = [ln for ln in lines if ln]
        self.assertEqual(lines[-3:], ["lda #2", "ldx #8", "ldy #2"])

    def test_source_refuses_while_planes_are_live(self):
        load = (ROOT / "src/c64/load.asm").read_text()
        proc = load.split(".proc container_load", 1)[1].split(".endproc", 1)[0]
        self.assertLess(proc.index("planes_live"), proc.index("jsr open_named"))
        self.assertNotIn("jsr read_file", proc)
        named = load.split(".proc open_named", 1)[1].split(".endproc", 1)[0]
        self.assertIn("jsr read_file", named)
        self.assertNotIn("in_restart", proc)
        self.assertNotIn("unpack_resident", proc)
        self.assertLess(proc.index("jsr xor_container"), proc.index("jsr glyph_install"))
        menu = (ROOT / "src/c64/menu.asm").read_text()
        campaign = menu.split(".proc campaign_load", 1)[1].split(".endproc", 1)[0]
        self.assertNotIn("container_load", campaign)
        self.assertNotIn("BANK", campaign)
        launch = menu.split(".proc menu_launch", 1)[1].split(".endproc", 1)[0]
        self.assertIn("jsr container_load", launch)
        self.assertNotIn("jsr map_load", launch)
        game = (ROOT / "src/c64/game.asm").read_text()
        tick = game.split(".proc game_tick", 1)[1].split(".endproc", 1)[0]
        restart = tick.split("beq live", 1)[1].split("\nlive:", 1)[0]
        self.assertIn("jsr unpack_resident", restart)
        self.assertNotIn("jsr clear_bss", restart)
        self.assertNotIn("jsr read_file", restart)
        self.assertNotIn("jsr container_load", restart)


if __name__ == "__main__":
    unittest.main()
