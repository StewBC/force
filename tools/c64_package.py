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
            decoded=lzss.decode(data[off:off+stored],expanded) if codec else data[off:off+stored]
            if len(decoded)!=expanded:raise ValueError('plane decoded length')
        elif cid in (2,6,7) and stored!=expanded:
            raise ValueError('raw extent')
        previous=off+stored;entries.append(e)
    if seen!=set(LAYOUT['schemas'].values()) or previous!=len(data):
        raise ValueError('missing schema/trailing extent')
    return entries

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--check-output',action='store_true');ap.add_argument('--raw',action='store_true');ap.add_argument('--am65',default=str(ROOT.parent/'machines/build/am65'));ap.add_argument('--build',default=str(ROOT/'build'));args=ap.parse_args()
    build=Path(args.build);out=build/'c64';out.mkdir(parents=True,exist_ok=True)
    if args.check_output:
        try:
            report=json.loads((out/'memory-report.json').read_text())
            if (out/'memory-report.md').exists() and all(hashlib.sha256((out/c['file']).read_bytes()).hexdigest()==c['sha256'] for c in report['chunks']) and all(hashlib.sha256((out/(name+'.seq')).read_bytes()).hexdigest()==c['sha256'] for name,c in report['collections'].items()):
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
    # Map records and bank validator are packaged after fresh assembly. This
    # resolves the assembly/generation cycle without stale code in map bundles.
    import gen_sdl
    map_names={m[1] for m in gen_sdl.load_missions(ROOT/'assets/missions.txt')}
    bank=image[start('bank_validation')-origin:sym['bank_validation_end']-origin]
    for path in sorted(out.glob('*.seq')):
        data=path.read_bytes()[2:]
        if data[:4]!=b'FMAP' or path.stem not in map_names:
            continue
        count=data[25]
        entries=[list(struct.unpack_from('<BBHHHH',data,26+10*i)) for i in range(count)]
        if count==7:
            # Regeneration is preferred; recover existing producer payloads
            # during an assembly-only incremental build.
            entries=entries[:6]
        bodies=[data[e[2]:e[2]+e[3]] for e in entries]
        offset=26+10*len(LAYOUT["schemas"])
        directory=bytearray()
        for entry,body in zip(entries,bodies):
            entry[2]=offset
            directory+=struct.pack('<BBHHHH',*entry)
            offset+=len(body)
        directory+=struct.pack('<BBHHHH',7,0,offset,len(bank),start('bank_validation'),len(bank))
        header=bytearray(data[:26]);header[25]=len(LAYOUT['schemas']);header[10]=0
        payload=header+directory+b''.join(bodies)+bank
        if len(payload)>capacity('transfer'):
            raise ValueError(f'{path.stem}: map transfer {len(payload)}/{capacity("transfer")}')
        payload[12:14]=struct.pack("<H",len(payload))
        payload[10]=checksum(payload)
        parse_map(payload)
        path.write_bytes(struct.pack('<H',start('transfer'))+payload)
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
    import c64_missions
    for path in sorted(out.glob('*.seq')):
        data=path.read_bytes()[2:]
        if data[:4]!=b'FMAP' or path.stem not in map_names:continue
        entries=[struct.unpack_from('<BBHHHH',data,26+10*i) for i in range(data[25])]
        e=next(e for e in entries if e[0]==2);collection=data[e[2]:e[2]+e[3]]
        records=[c64_missions.unpack(collection,i)[0] for i in range(collection[0])]
        report['collections'][path.stem]=dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(),stored=len(collection),capacity=capacity('collection'),expanded=[len(r) for r in records],expanded_sum=sum(map(len,records)))
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
    lines.append('\nResident mission collections:\n\n')
    for name,c in report['collections'].items():lines.append(f'- {name}: {c["stored"]}/{c["capacity"]} stored; expanded missions {c["expanded"]}; total {c["expanded_sum"]}.\n')
    (out/'memory-report.md').write_text(''.join(lines))
    print(json.dumps(report))

if __name__=='__main__':main()
