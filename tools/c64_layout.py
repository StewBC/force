"""Authoritative C64 placement contracts and deterministic generated includes."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
LAYOUT = json.loads((ROOT / 'assets/c64-layout.json').read_text())
REGIONS = {r['name']: r for r in LAYOUT['regions']}
_compat_hash = hashlib.sha256(json.dumps(LAYOUT, sort_keys=True, separators=(',', ':')).encode())
for _input in sorted({p for pattern in LAYOUT['compatibility_inputs'] for p in ROOT.glob(pattern)}):
    _compat_hash.update(str(_input.relative_to(ROOT)).encode() + b'\0' + _input.read_bytes())
COMPAT = int.from_bytes(_compat_hash.digest()[:2], 'little')

def start(name):
    return REGIONS[name]['start']

def capacity(name):
    r = REGIONS[name]
    return r['end'] - r['start']

def validate():
    for r in REGIONS.values():
        assert 0 <= r['start'] < r['end'] <= 65536, r
        assert r['start'] % r['alignment'] == 0, r
    for i, a in enumerate(REGIONS.values()):
        for b in list(REGIONS.values())[i+1:]:
            if max(a['start'], b['start']) < min(a['end'], b['end']):
                assert not set(a['phases']) & set(b['phases']), (a['name'], b['name'], 'live overlap')
                assert any(set((a['name'], b['name'])) <= set(o['regions']) for o in LAYOUT['overlays']), (a['name'], b['name'], 'undeclared overlay')

def generate():
    validate()
    out = ROOT / 'src/c64/generated'
    out.mkdir(exist_ok=True)
    lines = ['; Generated from assets/c64-layout.json. Do not edit.\n', f'LAYOUT_ID = ${COMPAT:04X}\n']
    for r in REGIONS.values():
        if r.get('equate'):
            lines += [f"{r['equate']} = ${r['start']:04X}\n", f"{r['equate']}_CAP = ${capacity(r['name']):04X}\n"]
    lines += [f'DIRECTORY_MAX = {(capacity("metadata")-1-26)//10}\n', f'MAP_SCHEMA_COUNT = {len(LAYOUT["schemas"])}\n', f'ROUTE_PORTALS_HOME = ${LAYOUT["routing_homes"]["portals"]:04X}\n', f'ROUTE_DOORS_HOME = ${LAYOUT["routing_homes"]["doors"]:04X}\n']
    (out / 'layout.inc').write_text(''.join(lines))
    lines = ['; Generated segment origins.\n']
    for r in REGIONS.values():
        if r.get('segment'):
            flags = ', noemit' if r.get('noemit') else ''
            flags += ', overlap_reclaimable' if r['name'] in ('bss', 'occupancy') else ''
            if r['name'] == 'bss':
                lines.append(f'.segdef "BSS", end=${r["end"]-1:04X}{flags}\n')
            else:
                lines.append(f'.segdef "{r["segment"]}", ${r["start"]:04X}{flags}\n')
    (out / 'segments.inc').write_text(''.join(lines))

if __name__ == '__main__':
    generate()
