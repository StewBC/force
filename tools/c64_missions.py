"""Self-contained independently encoded mission records (MSET v1).

Header: count, version, layout-id u16, extent u16. Directory entries:
offset, stored, expanded, scatter-body length (all u16), codec, XOR8.
Catalog ordinal is stable identity within the map. Objective operands are
record-relative offsets, relocated only after validating the entire record.
"""
import struct
import lzss
from c64_layout import COMPAT, capacity

HEADER = 6
ENTRY = 10

def checksum(data):
    value = 0
    for b in data:
        value ^= b
    return value

def record(body, script):
    out = bytearray(body)
    homes = {}
    ops = 20 + 3 * body[6]
    for pc in range(script.op_count):
        if script.op_code[pc] == 10:
            text = script.objective_text[script.op_a[pc]]
            if text not in homes:
                homes[text] = len(out)
                out += text.encode('ascii') + b'\0'
            offset = homes[text]
            out[ops + script.op_count + pc] = offset & 255
            out[ops + 2 * script.op_count + pc] = offset >> 8
    return bytes(out)

def pack(parts, scripts):
    if not 1 <= len(parts) <= 16:
        raise ValueError('mission collection count must be 1..16')
    directory = bytearray()
    payload = bytearray()
    offset = HEADER + ENTRY * len(parts)
    for stem, body in parts:
        raw = record(body, scripts[stem]) if scripts else body
        if len(raw) > capacity('mission'):
            raise ValueError(f'{stem}: expanded mission {len(raw)} bytes; capacity {capacity("mission")}; body {len(body)}, text/relocations {len(raw)-len(body)}')
        comp = lzss.encode(raw)
        codec, stored = (1, comp) if len(comp) < len(raw) else (0, raw)
        directory += struct.pack('<HHHHBB', offset, len(stored), len(raw), len(body), codec, checksum(raw))
        payload += stored
        offset += len(stored)
        print(f'gen_c64: mission {stem}: body {len(body)}, text {len(raw)-len(body)}, expanded {len(raw)}/{capacity("mission")}, stored {len(stored)} codec {codec}')
    if offset > capacity('collection'):
        raise ValueError(f'collection stored {offset}/{capacity("collection")}; header {HEADER}, directory {len(directory)}, records {len(payload)}')
    return struct.pack('<BBHH', len(parts), 1, COMPAT, offset) + directory + payload

def unpack(collection, index):
    if len(collection) < HEADER:
        raise ValueError('truncated collection header')
    count, version, compat, extent = struct.unpack_from('<BBHH', collection)
    if not 1 <= count <= 16 or version != 1 or compat != COMPAT or extent != len(collection) or extent > capacity('collection'):
        raise ValueError('incompatible/invalid collection')
    if not 0 <= index < count or HEADER + count * ENTRY > extent:
        raise ValueError('invalid mission selection/directory')
    intervals=[]
    selected=None
    for i in range(count):
        off, stored, expanded, body, codec, check = struct.unpack_from('<HHHHBB', collection, HEADER + ENTRY * i)
        if off < HEADER + ENTRY * count or not stored or off + stored > extent or not 20 <= body <= expanded <= capacity('mission') or codec not in (0,1):
            raise ValueError('invalid mission entry')
        if any(max(off,a) < min(off+stored,b) for a,b in intervals):
            raise ValueError('overlapping mission records')
        intervals.append((off,off+stored))
        src=collection[off:off+stored]
        raw=lzss.decode(src,expanded) if codec else src
        if len(raw)!=expanded or checksum(raw)!=check:
            raise ValueError('mission checksum/length')
        validate_record(raw,body)
        if i==index:
            selected=(raw,body)
    return selected

def validate_record(raw,body):
    if len(raw)<20 or raw[6]>32 or raw[2]==0 or raw[3]==0 or raw[0]+raw[2]>80 or raw[1]+raw[3]>40:
        raise ValueError('mission rectangle/spawns')
    scalar=7+3*raw[6]
    if scalar+13>body:
        raise ValueError('mission scalar extent')
    counts=raw[scalar:scalar+6]
    if any(n>cap for n,cap in zip(counts,(64,12,8,32,16,8))):
        raise ValueError('mission counts')
    n,beats,watches,preds,wheres,templates=counts
    if scalar+13+sum(n*s for n,s in zip(counts,(4,1,5,4,3,5)))!=body:
        raise ValueError('mission body length')
    ops=scalar+13
    for pc in range(n):
        code=raw[ops+pc]; a=raw[ops+n+pc]; b=raw[ops+2*n+pc]
        if code>10:
            raise ValueError('unknown opcode')
        if code==10:
            offset=a|(b<<8)
            if not body<=offset<len(raw):
                raise ValueError('objective offset')
            end=raw.find(b'\0',offset)
            if not offset<end<=offset+38 or any(c<32 or c>126 for c in raw[offset:end]):
                raise ValueError('objective text')
    beat_at=ops+4*n
    if any(pc>n for pc in raw[beat_at:beat_at+beats]):
        raise ValueError('beat PC')
