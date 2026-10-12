"""Staged startup chunks: each transfers to the same checked buffer.

FCHK v3 is a 16-byte typed placement contract. The bootstrap's generated
manifest pins every header byte and authorized destination. No disk-supplied
absolute address authorizes a write. New allocations add manifest producers.
"""
from pathlib import Path
import struct
import json
import subprocess
import argparse
import hashlib
import lzss
from c64_layout import ROOT, COMPAT, REGIONS, LAYOUT, capacity, start, generate
from c64_missions import checksum

def symbols(path):
    return {name:int(addr,16) for addr,name in (line.split()[:2] for line in Path(path).read_text().splitlines() if len(line.split())>=2 and all(c in '0123456789ABCDEFabcdef' for c in line.split()[0]))}

def segments(path):
    import re
    result={}
    for name,lo,hi,flags in re.findall(r'^\s*(\w+) \[([0-9A-F]+)-([0-9A-F]+)\)(.*)$',Path(path).read_text(),re.M):
        result[name]={'start':int(lo,16),'end':int(hi,16),'noemit':'noemit' in flags}
    return result

def check_segments(path, bootstrap=False):
    actual=segments(path)
    aliases={'BOOT':'bootstrap','MANIFEST':'scratch','ASSETS':'boot_assets','ZP':'zeropage'}
    for name,s in actual.items():
        region=aliases.get(name) or next((n for n,r in REGIONS.items() if r.get('segment')==name),None)
        if region is None:raise ValueError(f'undeclared assembler segment {name}')
        r=REGIONS[region]
        if not r['start']<=s['start']<=s['end']<=r['end'] or s['noemit']!=r['noemit']:
            raise ValueError(f'{name}: actual {s} outside layout {r}')
        if region!='bss' and s['start']!=r['start']:
            raise ValueError(f'{name}: unchecked/moved origin')
    return actual

def chunk(raw, region, compress=True):
    comp=lzss.encode(raw)
    codec,payload=(1,comp) if compress and len(comp)<len(raw) else (0,raw)
    header=struct.pack('<4sBBHBBHHBB', b'FCHK',3,1,COMPAT,codec,region,len(raw),len(payload),checksum(raw),1)
    return header,payload

def _geometry_span(data, entries):
    """Decoded plane length from schema 1, whatever its directory slot."""
    geo = next(e for e in entries if e[0] == 1)
    codec, off, stored = geo[1], geo[2], geo[3]
    if codec or stored < 2 or off + 2 > len(data):
        raise ValueError('plane extent')
    w, h = data[off], data[off + 1]
    span = w * h
    if not 1 <= w <= 80 or not 1 <= h <= 40 or span > 3200:
        raise ValueError('plane extent')
    return span


def _check_plane_body(data, entry, tight):
    """Capacity stays 3200. Raw stored is the tight size. LZSS must beat it."""
    codec, off, stored = entry[1], entry[2], entry[3]
    body = data[off:off + stored]
    if codec:
        if stored >= tight:
            raise ValueError('plane decoded length')
        decoded = lzss.decode(body, tight)
    else:
        if stored != tight:
            raise ValueError('plane decoded length')
        decoded = body
    if len(decoded) != tight:
        raise ValueError('plane decoded length')


def parse_map(data):
    """Validate the complete map container before accepting any placement."""
    from c64_layout import LAYOUT
    if len(data)<26 or len(data)>capacity('transfer') or data[:4]!=b'FMAP' or data[4]!=3 or data[5]!=1:
        raise ValueError('map magic/version/kind/transfer extent')
    if int.from_bytes(data[8:10],'little')!=COMPAT or checksum(data)!=0:
        raise ValueError('map compatibility/integrity')
    if not 1<=data[6]<=16 or data[7] or data[11] or any(data[14:25]) or int.from_bytes(data[12:14],'little')!=len(data):
        raise ValueError('map count/reserved/extent')
    count=data[25];directory_end=26+count*10
    if not count or directory_end>len(data) or count>(capacity('metadata')-1-26)//10:
        raise ValueError('map directory capacity')
    regions={1:'geometry',2:'collection',3:'tiles',4:'paper',5:'scratch',6:'routing_program',7:'bank_validation'}
    entries=[];seen=set();previous=directory_end
    for i in range(count):
        e=struct.unpack_from('<BBHHHH',data,26+10*i);cid,codec,off,stored,dest,expanded=e
        if cid not in regions or cid in seen or codec not in (0,1) or codec and cid not in (3,4):
            raise ValueError('map schema/duplicate/codec')
        seen.add(cid);name=regions[cid]
        if off<previous or not stored or off+stored>len(data) or dest!=start(name) or expanded>capacity(name):
            raise ValueError('map source/destination overlap or capacity')
        if cid in (3,4):
            if expanded!=3200:raise ValueError('plane extent')
        elif cid in (2,6,7) and stored!=expanded:
            raise ValueError('raw extent')
        previous=off+stored;entries.append(e)
    if 1 in seen:
        tight=_geometry_span(data, entries)
        for e in entries:
            if e[0] in (3,4):
                _check_plane_body(data, e, tight)
    # FMAP v3 is the fixture format. Schema 8 belongs to FMSN, not this set.
    if seen!={1,2,3,4,5,6,7} or previous!=len(data):
        raise ValueError('missing schema/trailing extent')
    return entries

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--check-output',action='store_true');ap.add_argument('--raw',action='store_true');ap.add_argument('--am65',default=str(ROOT.parent/'machines/build/am65'));ap.add_argument('--build',default=str(ROOT/'build'));args=ap.parse_args()
    build=Path(args.build);out=build/'c64';out.mkdir(parents=True,exist_ok=True)
    if args.check_output:
        try:
            report=json.loads((out/'memory-report.json').read_text())
            chunks_ok=all(hashlib.sha256((out/c['file']).read_bytes()).hexdigest()==c['sha256'] for c in report['chunks'])
            boxes=report.get('containers',{})
            boxes_ok=all(hashlib.sha256((out/(name+'.seq')).read_bytes()).hexdigest()==c['sha256'] for name,c in boxes.items())
            bank=report.get('bank')
            bank_ok=bank is not None and hashlib.sha256((out/'bank.seq').read_bytes()).hexdigest()==bank['sha256']
            if (out/'memory-report.md').exists() and chunks_ok and boxes_ok and bank_ok and boxes:
                return
        except (OSError,ValueError,KeyError):
            pass
    generate()
    subprocess.run([args.am65,'-i',str(ROOT/'src/c64/force.asm'),'-o',str(out/'game-image.prg'),'--prg','-s',str(out/'game-image.sym')],check=True)
    sym=symbols(out/'game-image.sym');blob=(out/'game-image.prg').read_bytes();origin=int.from_bytes(blob[:2],'little');image=blob[2:]
    actual=check_segments(out/'game-image.sym')
    ends={name:actual[REGIONS[name]['segment']]['end'] for name in LAYOUT['startup_regions']}
    for old in out.glob('game??.prg'):
        old.unlink()
    chunks=[];manifest=['; Generated startup manifest, source buffer never overlaps installed code.\nstartup_entries:\n']
    for region_id,(name,end) in enumerate(ends.items(),1):
        r=REGIONS[name]
        if end>r['end']:
            raise ValueError(f'{name} assembled end ${end:04x} exceeds ${r["end"]:04x}')
        for dest in range(r['start'],end,6000):
            raw=image[dest-origin:min(dest+6000,end)-origin]
            header,stored=chunk(raw,region_id,not args.raw)
            if len(header)+len(stored)>capacity('transfer'):
                raise ValueError('startup transfer overflow')
            i=len(chunks)
            if i>=16:
                raise ValueError('startup filename capacity exceeded')
            filename=f'game{i:02x}.seq'
            (out/filename).write_bytes(struct.pack('<H',start('transfer'))+header+stored)
            # Host independently decodes every produced chunk.
            decoded=lzss.decode(stored,len(raw)) if header[8] else stored
            assert decoded==raw
            manifest.append('    .byte '+','.join(f'${b:02X}' for b in header)+'\n')
            manifest.append(f'    .word ${dest:04X}\n')
            chunks.append(dict(file=filename,region=name,destination=dest,expanded=len(raw),stored=len(stored),codec=header[8],checksum=checksum(raw),sha256=hashlib.sha256((out/filename).read_bytes()).hexdigest()))
    produced={c['file'] for c in chunks}
    for old in out.glob('game??.seq'):
        if old.name not in produced:old.unlink()
    manifest.append(f'STARTUP_COUNT = {len(chunks)}\n')
    (ROOT/'src/c64/generated/startup.inc').write_text(''.join(manifest))
    subprocess.run([args.am65,'-i',str(ROOT/'src/c64/bootstrap.asm'),'-o',str(build/'force.prg'),'--prg','-s',str(build/'force.sym')],check=True)
    # The validator is one file. It used to be appended to every map.
    bank=image[start('bank_validation')-origin:sym['bank_validation_end']-origin]
    if len(bank)!=sym['bank_validation_end']-start('bank_validation'):
        raise ValueError('bank image length')
    (out/'bank.seq').write_bytes(struct.pack('<H',start('bank_validation'))+bank)
    boot_segments=check_segments(build/'force.sym',True)
    bootsym=symbols(build/'force.sym')
    report=dict(layout_id=COMPAT,chunks=chunks,bootstrap_bytes=(build/'force.prg').stat().st_size,segments={name:dict(start=REGIONS[name]['start'],end=end,size=end-REGIONS[name]['start'],capacity=capacity(name),free=REGIONS[name]['end']-end) for name,end in ends.items()})
    for name,actual_start,actual_end in [('bss',sym['bss_start'],sym['bss_end']),('occupancy',start('occupancy'),start('occupancy')+capacity('occupancy'))]:
        assert REGIONS[name]['start']<=actual_start<=actual_end<=REGIONS[name]['end']
        report['segments'][name]=dict(start=actual_start,end=actual_end,size=actual_end-actual_start,capacity=capacity(name),free=capacity(name)-(actual_end-actual_start))
    report['assembler_segments']=actual
    report['bootstrap_segments']=boot_segments
    report['transfer_capacity']=capacity('transfer')
    report['routing_homes']=LAYOUT['routing_homes']
    report['segments']['zeropage']=dict(start=actual['ZEROPAGE']['start'],end=actual['ZEROPAGE']['end'],size=actual['ZEROPAGE']['end']-actual['ZEROPAGE']['start'],capacity=capacity('zeropage'),free=REGIONS['zeropage']['end']-actual['ZEROPAGE']['end'])
    report['segments']['bootstrap']=dict(start=start('bootstrap'),end=bootsym['boot_end'],size=bootsym['boot_end']-start('bootstrap'),capacity=capacity('bootstrap'),free=REGIONS['bootstrap']['end']-bootsym['boot_end'])
    report['collections']={}
    report['segments']['bank_validation']=dict(start=start('bank_validation'),end=sym['bank_validation_end'],size=len(bank),capacity=capacity('bank_validation'),free=capacity('bank_validation')-len(bank))
    report['bank']=dict(file='bank.seq',stored=len(bank),sha256=hashlib.sha256((out/'bank.seq').read_bytes()).hexdigest())
    import gen_c64
    report['containers']={}
    for path in sorted(out.glob('c*.seq')):
        data=path.read_bytes()[2:]
        if data[:4]!=b'FCTR':
            continue
        parsed=gen_c64.parse_fctr(data)
        stems=[]
        for mission in parsed['missions']:
            stems.append(mission['stem'])
            for row in gen_c64.fmsn_directory(mission['blob']):
                _schema,_codec,_xor,_off,_stored,dest,cap,decoded,_body=row
                gen_c64.assert_chunk_placement(0xE600, _stored, dest, decoded)
                gen_c64.assert_chunk_placement(0xE600, cap, dest, cap)
        report['containers'][path.stem]=dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(),stored=parsed['used'],cap=gen_c64.CONTAINER_CAP,biome=parsed['biome'],stems=stems,free=parsed['left'])
    (out/'memory-report.json').write_text(json.dumps(report,indent=2)+'\n')
    lines=['# C64 generated memory report\n',f'Layout compatibility: `${COMPAT:04X}`. Fresh assembly: game-image.sym.\n','| Region | Address (exclusive end) | Actual | Capacity | Free | Phases | Owner |\n','|---|---|---:|---:|---:|---|---|\n']
    for name,r in REGIONS.items():
        actual=report['segments'].get(name,{}).get('size',capacity(name))
        lines.append(f'| {name} | ${r["start"]:04X}–${r["end"]:04X} | {actual} | {capacity(name)} | {capacity(name)-actual} | {", ".join(r["phases"])} | {r["owner"]} |\n')
    lines.append('\nIntentional overlays and release transitions:\n\n')
    for o in __import__('c64_layout').LAYOUT['overlays']:
        lines.append(f'- {", ".join(o["regions"])}: {o["transition"]}.\n')
    lines.append('\nStartup chunks (each loaded and consumed before next transfer):\n\n')
    for c in chunks:lines.append(f'- {c["file"]}: ${c["destination"]:04X}, {c["expanded"]} expanded, {c["stored"]} stored, codec {c["codec"]}.\n')
    lines.append('\nContainers (one biome, whole image at `$E600`):\n\n')
    for name,c in report['containers'].items():lines.append(f'- {name}.seq: {c["stored"]}/{c["cap"]} bytes, biome {c["biome"]}, stems {", ".join(c["stems"])}, free {c["free"]}.\n')
    lines.append(f'\nbank.seq: {report["bank"]["stored"]} bytes at `$E000`.\n')
    (out/'memory-report.md').write_text(''.join(lines))

if __name__=='__main__':main()
