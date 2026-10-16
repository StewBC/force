"""Format/capacity/codec regressions for staged loading and banked missions."""
import contextlib
import io
import random
import struct
import unittest
from pathlib import Path
import c64_layout as layout
import c64_missions as missions
import c64_package as packages
import lzss

class Packages(unittest.TestCase):
    def pack(self, parts):
        with contextlib.redirect_stdout(io.StringIO()):
            return missions.pack(parts,None)

    def test_layout(self):
        layout.validate()
        self.assertEqual(layout.capacity('mission'),597)
        self.assertEqual(layout.REGIONS['collection']['end'],0xfffa)
        self.assertGreater(layout.capacity('collection'),597)
        self.assertEqual(layout.REGIONS['deck']['end'],6144)
        index=layout.REGIONS['menu_index']
        self.assertEqual(index['start'],6144)
        self.assertEqual(index['end'],7168)
        self.assertEqual(index['equate'],'MENU_INDEX')
        self.assertEqual(layout.capacity('menu_index'),1024)

    def test_real_collections_and_codecs(self):
        import gen_sdl
        import gen_c64
        stems={m[0] for m in gen_sdl.load_missions(layout.ROOT/'assets/missions.txt')}
        used=set()
        seen=set()
        for path in sorted((layout.ROOT/'build/c64').glob('c*.seq')):
            data=path.read_bytes()[2:]
            self.assertEqual(data[:4], b'FCTR')
            parsed=gen_c64.parse_fctr(data)
            for mission in parsed['missions']:
                seen.add(mission['stem'])
                rows=gen_c64.fmsn_directory(mission['blob'])
                record=next(row for row in rows if row[0]==8)
                used.add(record[1])
        self.assertEqual(seen, stems)
        self.assertEqual(used, {0, 1})

    @staticmethod
    def boundary(beats):
        # Full valid scatter body: 32 stamps, 64 NOPs, 32 predicates,
        # 16 wheres, 8 templates; nine beats makes exactly 597 bytes.
        return bytes([0,0,80,40,0,0,32])+bytes(96)+bytes([64,beats,0,32,16,8,0,0,0,0,0,0,0])+bytes(256+beats+128+48)+bytes([1]*8)+bytes([8]*8)+bytes(8)+bytes([1]*16)

    def test_workspace_boundary(self):
        body=self.boundary(9)
        self.assertEqual(len(body),597)
        collection=self.pack([('exact',body)])
        self.assertEqual(missions.unpack(collection,0)[0],body)
        with self.assertRaisesRegex(ValueError,'598.*597'):
            self.pack([('oversize',self.boundary(10))])

    def test_large_collection(self):
        body=self.boundary(9)
        collection=self.pack([(str(i),body) for i in range(16)])
        self.assertEqual(sum(len(missions.unpack(collection,i)[0]) for i in range(16)),9552)
        self.assertLess(len(collection),layout.capacity('collection'))

    def test_collection_overflow_separate(self):
        rng=random.Random(123)
        with self.assertRaisesRegex(ValueError,'collection stored'):
            self.pack([(str(i),rng.randbytes(597)) for i in range(16)])

    def test_bad_collection(self):
        original=self.pack([('ok',self.boundary(9))])
        for position in (0,1,2,4,6,8,10,12,14,15,len(original)-1):
            corrupted=bytearray(original);corrupted[position]^=0x80
            with self.subTest(position=position),self.assertRaises(ValueError):
                missions.unpack(bytes(corrupted),0)
        for n in (0,5,15,len(original)-1):
            with self.assertRaises(ValueError):missions.unpack(original[:n],0)

    def test_map_corruption(self):
        data=self._fmap(40, 20, 0, bytes(800), 0, bytes(800))
        packages.parse_map(data)
        for position in (0,4,5,6,8,10,12,25,26,27,28,30,32):
            bad=bytearray(data);bad[position]^=0x80
            with self.subTest(position=position),self.assertRaises(ValueError):packages.parse_map(bad)
        # Repair integrity so directory and placement checks must catch these.
        for edit in ('duplicate','overlap','destination','reserved','codec'):
            bad=bytearray(data)
            if edit=='duplicate':bad[36]=bad[26]
            elif edit=='overlap':bad[38:40]=bad[28:30]
            elif edit=='destination':bad[32:34]=b'\0\0'
            elif edit=='reserved':bad[14]=1
            else:bad[27]=1
            bad[10]=0;bad[10]=missions.checksum(bad)
            with self.subTest(edit=edit),self.assertRaises(ValueError):packages.parse_map(bad)
        with self.assertRaises(ValueError):packages.parse_map(data[:-1])

    def test_lzss_strict(self):
        for raw in (b'',b'a',bytes(range(256)),b'abc'*200):
            encoded=lzss.encode(raw)
            self.assertEqual(lzss.decode(encoded,len(raw)),raw)
            with self.assertRaises(ValueError):lzss.decode(encoded+b'!',len(raw))
        for src,size in [(b'\0\0\0',3),(b'\1',1),(b'\1a\1\0',2),(b'\1a\1\x0f',2)]:
            with self.assertRaises(ValueError):lzss.decode(src,size)

    def test_objective_corruption(self):
        from test_objectives import ObjectiveTests
        import gen_c64
        sc=ObjectiveTests().compile('init:\n objective "Cue"\nbeat next:\n win\n')
        body=gen_c64.pack_mission_body(0,0,1,1,0,0,[],[],[],sc)
        raw=missions.record(body,sc)
        missions.validate_record(raw,len(body))
        for off in (0,len(raw),len(body)-1):
            bad=bytearray(raw);bad[20+sc.op_count]=off&255;bad[20+2*sc.op_count]=off>>8
            with self.assertRaises(ValueError):missions.validate_record(bad,len(body))
        bad=raw[:-1]+b'!'
        with self.assertRaises(ValueError):missions.validate_record(bad,len(body))

    def _fmap(self, width, height, tile_codec, tile_body, paper_codec, paper_body, tile_cap=3200, paper_cap=3200):
        from c64_layout import COMPAT, start
        geo=bytes((width, height, 0, 0, 0, 0, 0))
        collection=b'\x01\x01\x00\x00'
        chunks=(
            (1, 0, start('geometry'), 870, geo),
            (2, 0, start('collection'), len(collection), collection),
            (3, tile_codec, start('tiles'), tile_cap, tile_body),
            (4, paper_codec, start('paper'), paper_cap, paper_body),
            (5, 0, start('scratch'), 818, bytes(818)),
            (6, 0, start('routing_program'), 256, bytes(256)),
            (7, 0, start('bank_validation'), 1, b'\x00'),
        )
        entries=bytearray();bodies=bytearray();offset=26+10*len(chunks)
        for cid, flags, dest, dest_len, body in chunks:
            entries+=struct.pack('<BBHHHH', cid, flags, offset, len(body), dest, dest_len)
            bodies+=body
            offset+=len(body)
        payload=bytearray(b'FMAP')
        payload+=bytes((3, 1, 1, 0))
        payload+=struct.pack('<H', COMPAT)+bytes(14)
        payload+=bytes((0, len(chunks)))
        payload+=entries
        payload+=bodies
        payload[12:14]=struct.pack('<H', len(payload))
        payload[10]=0
        payload[10]=missions.checksum(payload)
        return payload

    def test_tight_planes(self):
        raw=bytes((i * 17 + 3) & 255 for i in range(800))
        payload=self._fmap(40, 20, 0, raw, 0, raw)
        packages.parse_map(payload)
        patched=bytearray(payload)
        for i in range(patched[25]):
            slot=26+10*i
            if patched[slot]==3:
                struct.pack_into('<H', patched, slot+8, 800)
        patched[10]=0
        patched[10]=missions.checksum(patched)
        with self.assertRaisesRegex(ValueError, 'plane extent'):
            packages.parse_map(patched)
        zeros=bytes(800)
        comp=lzss.encode(zeros)
        self.assertLess(len(comp), 800)
        packages.parse_map(self._fmap(40, 20, 1, comp, 1, comp))
        self.assertEqual(lzss.decode(comp, 800), zeros)
        with self.assertRaises(ValueError):
            lzss.decode(comp, 3200)

    def test_farm_tiles_are_tight_lzss(self):
        import gen_c64
        data=(layout.ROOT/'build/c64/c0.seq').read_bytes()[2:]
        farm=next(row for row in gen_c64.parse_fctr(data)['missions'] if row['stem']=='farm')
        rows=gen_c64.fmsn_directory(farm['blob'])
        geo=next(row for row in rows if row[0]==1)
        self.assertEqual(farm['blob'][geo[3]:geo[3]+2], bytes((40, 20)))
        tiles=next(row for row in rows if row[0]==3)
        self.assertEqual(tiles[1], 1)
        self.assertEqual(tiles[6], 3200)
        self.assertLess(tiles[4], 800)
        decoded=lzss.decode(farm['blob'][tiles[3]:tiles[3]+tiles[4]], tiles[7])
        self.assertEqual(len(decoded), 800)

    def test_campaign_scores_and_index(self):
        import tempfile
        import gen_c64
        import gen_sdl
        missions=gen_sdl.load_missions(layout.ROOT/'assets/missions.txt')
        stems=[row[0] for row in missions]
        titles=[row[4] for row in missions]
        text=(layout.ROOT/'build/c64/campaign.prg').read_bytes()[2:].decode('ascii')
        lines=[ln for ln in text.splitlines() if ln and not ln.startswith('#')]
        self.assertEqual([line.split()[0] for line in lines], stems)
        self.assertTrue(all(line.split()[1] == '-' or 0 <= int(line.split()[1]) <= 99 for line in lines))
        scored=gen_c64.scores_from_text(
            'farm 7\ncross -\nNORMANDY 1 7 cross_river Cross the river\n'
        )
        self.assertEqual(scored['farm'], '7')
        self.assertEqual(scored['cross'], '7')
        self.assertEqual(gen_c64.scores_from_text('farm 7\n'), {'farm': '7'})
        self.assertEqual(gen_c64.scores_from_text('cross -\n'), {'cross': '-'})
        self.assertEqual(
            gen_c64.scores_from_text('NORMANDY 1 7 cross Cross the river\n'),
            {},
        )
        with tempfile.TemporaryDirectory() as tmp:
            parent=Path(tmp)
            c64=parent/'c64'
            c64.mkdir()
            (c64/'campaign.prg').write_bytes(
                b'\x00\x10NORMANDY 0 7 hold_farm Hold the Farm\n'
            )
            # write_campaign joins build_dir/c64 and reads that file for old scores.
            written=gen_c64.write_campaign(layout.ROOT, missions, parent)
            saved=written.read_bytes()[2:].decode('ascii')
        self.assertIn('farm 7\n', saved)
        self.assertNotIn('hold_farm', saved)
        self.assertNotIn('NORMANDY', saved)
        self.assertIn('cross -\n', saved)
        built=(layout.ROOT/'build/c64/campaign.prg').read_bytes()[2:].decode('ascii')
        self.assertEqual(
            [ln for ln in built.splitlines() if ln and not ln.startswith('#')],
            lines,
        )
        containers=[
            gen_c64.parse_fctr((layout.ROOT/'build/c64'/name).read_bytes()[2:])
            for name in ('c0.seq', 'c1.seq', 'c2.seq')
        ]
        blob=gen_c64.pack_index(missions, layout.COMPAT, containers)
        self.assertEqual(blob[:4], b'FIDX')
        self.assertEqual(blob[4], 1)
        self.assertEqual(blob[5], 6)
        self.assertEqual(blob[6], 2)
        self.assertEqual(blob[7], 3)
        self.assertEqual(int.from_bytes(blob[8:10], 'little'), layout.COMPAT & 0xFFFF)
        self.assertEqual(int.from_bytes(blob[12:14], 'little'), len(blob))
        self.assertEqual(gen_c64._xor_bytes(blob), 0)
        self.assertEqual(blob[14+32:14+32+3], bytes((0, 0, 1)))
        origin=14+2*16+3
        self.assertEqual(len(blob), origin+6*gen_c64.INDEX_ENTRY)
        self.assertEqual(len(blob), 343)
        self.assertEqual(gen_c64.INDEX_ENTRY, 49)
        home={'farm': 0, 'cross': 0, 'river': 0, 'base': 1, 'ridge': 1, 'bastogne': 2}
        for i, stem in enumerate(stems):
            ent=blob[origin+i*49:origin+(i+1)*49]
            self.assertEqual(ent[0], len(stem))
            self.assertEqual(bytes(ent[1:1+len(stem)]), stem.encode())
            self.assertEqual(ent[16], len(titles[i]))
            self.assertEqual(bytes(ent[17:17+len(titles[i])]), titles[i].encode())
            self.assertEqual(ent[44], home[stem])
            if i+1 < len(stems):
                self.assertEqual(blob[origin+(i+1)*49], len(stems[i+1]))
        on_disk=(layout.ROOT/'build/c64/index.seq').read_bytes()[2:]
        self.assertEqual(on_disk, gen_c64.pack_index(missions, layout.COMPAT, containers))
        with self.assertRaises(gen_sdl.Error):
            gen_c64.pack_index(
                [('m%02d'%i, 'normandy', 0, 0, 'Title') for i in range(17)], 1
            )
        with self.assertRaises(gen_sdl.Error):
            gen_c64.pack_index(
                [('m%d'%i, 'b%d'%i, 0, 0, 'Title') for i in range(5)], 1
            )
        menu=(layout.ROOT/'src/c64/menu.asm').read_text()
        load=menu.split('.proc campaign_load',1)[1].split('.endproc',1)[0]
        self.assertIn('MENU_INDEX', load)
        self.assertNotIn('TRANSFER_HOME', load)
        self.assertLess(load.index('jsr read_file'), load.index('jsr parse_image'))
        self.assertIn('.byte "INDEX"', menu)
        self.assertNotIn('ui_col', menu)
        self.assertNotIn('container_load', load)
        self.assertNotIn('BANK', load)
        launch=menu.split('.proc menu_launch',1)[1].split('.endproc',1)[0]
        self.assertIn('jsr container_load', launch)
        self.assertNotIn('jsr map_load', launch)
        self.assertNotIn('jsr set_load_name', launch)
        self.assertLess(launch.index('sta $D011'), launch.index('jsr container_load'))
        opened=menu.split('.proc menu_open',1)[1].split('.endproc',1)[0]
        self.assertLess(opened.index('jsr menu_vic'), opened.index('jsr load_bank'))
        title=(layout.ROOT/'src/c64/title.asm').read_text()
        show=title.split('.proc show_title',1)[1]
        self.assertLess(show.index('jsr campaign_load'), show.index('$D011'))
        force=(layout.ROOT/'src/c64/force.asm').read_text()
        self.assertIn('endof("DECK") .le MENU_INDEX', force)
        cmake=(layout.ROOT/'src/c64/CMakeLists.txt').read_text()
        self.assertIn('index.seq', cmake)
        self.assertIn('index,s', cmake)
        self.assertIn('c0.seq', cmake)
        self.assertIn('c1.seq', cmake)
        self.assertIn('c2.seq', cmake)
        self.assertIn('bank.seq', cmake)
        self.assertIn('c0,s', cmake)
        self.assertIn('c1,s', cmake)
        self.assertIn('c2,s', cmake)
        self.assertIn('bank,s', cmake)
        self.assertTrue((layout.ROOT/'build/c64/bank.seq').exists())
        self.assertFalse((layout.ROOT/'build/c64/farm.seq').exists())

    def test_no_unresolved_scoped_symbols(self):
        # am65 can leave a forward alias local to a proc at FFFF even when
        # the global alias resolves. That turns a valid build into a BASIC crash.
        sym = packages.symbols(layout.ROOT/'build/c64/game-image.sym')
        self.assertEqual([name for name,value in sym.items() if value == 0xFFFF and '::' in name], [])
        self.assertEqual(sym['fill_status::line_str'], sym['line_str'])

    def test_legacy_loader_is_not_resident(self):
        # Host FMAP fixtures remain supported; the shipping runtime uses FCTR.
        sym = packages.symbols(layout.ROOT/'build/c64/game-image.sym')
        self.assertNotIn('map_load', sym)
        self.assertNotIn('prepare_mission', sym)
        self.assertIn('unpack_resident', sym)
        self.assertIn('lzss_sized', sym)

if __name__=='__main__':unittest.main()
