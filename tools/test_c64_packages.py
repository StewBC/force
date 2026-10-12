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

    def test_real_collections_and_codecs(self):
        import gen_sdl
        maps={m[1] for m in gen_sdl.load_missions(layout.ROOT/'assets/missions.txt')}
        used=set()
        for path in (layout.ROOT/'build/c64').glob('*.seq'):
            data=path.read_bytes()[2:]
            if data[:4]!=b'FMAP' or path.stem not in maps:continue
            self.assertEqual(missions.checksum(data),0)
            entries=[struct.unpack_from('<BBHHHH',data,26+10*i) for i in range(data[25])]
            e=next(e for e in entries if e[0]==2)
            collection=data[e[2]:e[2]+e[3]]
            for i in range(collection[0]):
                raw,body=missions.unpack(collection,i)
                self.assertLessEqual(len(raw),597)
                used.add(collection[6+10*i+8])
            if path.stem=='normandy':self.assertGreater(len(collection),597)
        self.assertEqual(used,{0,1})

    @staticmethod
    def boundary(beats):
        # Full valid scatter body: 32 stamps, 64 NOPs, 32 predicates,
        # 16 wheres, 8 templates; nine beats makes exactly 597 bytes.
        return bytes([0,0,80,40,0,0,32])+bytes(96)+bytes([64,beats,0,32,16,8,0,0,0,0,0,0,0])+bytes(256+beats+128+48+40)

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
        data=(layout.ROOT/'build/c64/normandy.seq').read_bytes()[2:]
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

if __name__=='__main__':unittest.main()
