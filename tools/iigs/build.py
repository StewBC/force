#!/usr/bin/env python3
"""Build the native ORCA/M executable, GS/OS boot disk and 800K transfer images."""
from pathlib import Path
import argparse
import json
import re
import shutil
import struct
import subprocess
import sys
import assets
import core
import sprites
import icons

ROOT=Path(__file__).resolve().parents[2]

def run(args, logfile=None):
    result=subprocess.run([str(x) for x in args],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    if logfile: logfile.write_text(result.stdout)
    if result.returncode:
        print(result.stdout[-18000:]);raise SystemExit(f'{args[0]} exited {result.returncode}')
    return result.stdout

def transfer_disk(out,icon_path):
    """Distribution disk for mounting/copying under an existing GS/OS system."""
    image=out/'force-800k.2mg'
    image.unlink(missing_ok=True)
    run(['cadius','CREATEVOLUME',image,'FORCE','800KB'])
    run(['cadius','ADDFILE',image,'/FORCE',out/'FORCE'])
    run(['cadius','CREATEFOLDER',image,'/FORCE/Icons'])
    run(['cadius','ADDFILE',image,'/FORCE/Icons',icon_path])
    run(['cadius','CHECKVOLUME',image],out/'transfer-disk-check.txt')
    # Also provide a raw ProDOS-order image for mounters that do not accept 2MG.
    data=image.read_bytes()
    if data[:4]!=b'2IMG':raise ValueError('Expected a 2MG transfer disk')
    fmt,flags,blocks,offset,length=struct.unpack_from('<5I',data,12)
    if fmt!=1 or blocks!=1600 or length!=800*1024 or offset+length>len(data):
        raise ValueError('Transfer disk is not an 800K ProDOS image')
    (out/'force-800k.po').write_bytes(data[offset:offset+length])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'build/iigs')
    parser.add_argument('--template',type=Path,default=ROOT/'assets/iigs/disc/templat.2mg')
    parser.add_argument('--no-disk',action='store_true')
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    if out!=ROOT/'build/iigs': parser.error('ORCA COPY paths currently require --out build/iigs')
    icon_path=icons.generate(ROOT,out/'icons')
    sources,catalogue=assets.generate(ROOT,out)
    # Expand all conditional branches, retaining the exact condition/flags.
    expands=set()
    for module in core.MODULES:
        for n,line in enumerate((ROOT/f'src/c64/{module}.asm').read_text().splitlines(),1):
            if line.strip().split(' ')[0] in core.BRANCHES: expands.add(f'{module}:{n}')
    core.generate(ROOT,out,expands)
    pushes=[]
    for row in range(7,-1,-1):
        for offset in (2,0): pushes += [f' lda render_buffer+{row*4+offset}',' pha']
        if row: pushes += [' tsc',' sec',' sbc #156',' tcs']
    (out/'stack.s').write_text('\n'.join(pushes)+'\n')
    packing=[]
    for row in range(8):
        packing += [' lda CHARSET,y',' and #255',' asl a',' asl a',
                    ' ora render_lookup_offset',' tax',' lda >cell_lookup,x',
                    f' sta render_buffer+{row*4}',' lda >cell_lookup+2,x',
                    f' sta render_buffer+{row*4+2}',' iny']
    (out/'cellpack.s').write_text('\n'.join(packing)+'\n')
    sprite_source=out/'sprites.asm'
    sprites.compile_sprites((out/'charset.bin').read_bytes(),sprite_source)
    objects=[]
    for source in [ROOT/'src/iigs/main.asm',*sources,sprite_source]:
        stem=out/source.stem
        log=run(['iix','assemble','+L','+S',source.relative_to(ROOT),'keep='+str(stem.relative_to(ROOT))],out/(source.stem+'.listing'))
        objects.append(stem)
    script=out/'link.script'
    script.write_text('+S +L\n'+'\n'.join(str(x.relative_to(ROOT)) for x in objects)+'\n')
    run(['iix','chtyp','-l','LINKER',script.relative_to(ROOT)])
    log=run(['iix','assemble',script.relative_to(ROOT),'keep=build/iigs/FORCE'],out/'link.map')
    symbols={}
    for listing in [out/'main.listing',out/'link.map']:
        for line in listing.read_text().splitlines():
            for address,name in re.findall(r'\b([0-9A-F]{6})\s+([A-Za-z_]\w*)',line):
                symbols[name]=int(address,16)
    for name,offset in re.findall(r'^(\w+) equ active_mission\+(\d+)$',(out/'assets.s').read_text(),re.M):
        symbols[name]=symbols['active_mission']+int(offset)
    symbols['CORE']=0
    if symbols['core_end']>65536: raise SystemExit('CORE exceeds 64KiB bank')
    (out/'symbols.json').write_text(json.dumps({'symbols':symbols,'mailbox':{'signature':'FORCEIIGS','version':1,'base':10,'dp':14,'ready':16,'pause':17,'ticks':18,'mission':22,'action':23,'input':24},'catalogue':catalogue},indent=2)+'\n')
    if not args.no_disk:
        if not args.template.exists(): parser.error(f'missing GS/OS template {args.template}')
        disk=out/'force.2mg';shutil.copyfile(args.template,disk)
        # Template retains its existing volume and GS/OS desktop.
        catalog=run(['cadius','CATALOG',disk])
        match=re.search(r'^/([^/]+)/\s*$',catalog,re.M)
        volume=match[1] if match else 'TIMEPILOT'
        (out/'_FileInformation.txt').write_text('FORCE=Type(B3),AuxType(DB03),VersionCreate(00),MinVersion(80),Access(E3),FolderInfo1(000000000000000000000000000000000000),FolderInfo2(000000000000000000000000000000000000)\n')
        run(['cadius','ADDFILE',disk,'/'+volume,out/'FORCE'])
        # Finder matches this icon to FORCE's S16 type and DB03 auxiliary type.
        run(['cadius','ADDFILE',disk,'/'+volume+'/Icons',icon_path])
        # Modify startup only inside this newly copied workspace output image.
        assert (ROOT/'build/iigs').resolve() in disk.resolve().parents
        assert disk.resolve()!=args.template.resolve()
        startup=out/'startup';startup.mkdir(exist_ok=True)
        shutil.copy2(out/'FORCE',startup/'Start')
        (startup/'_FileInformation.txt').write_text('Start=Type(B3),AuxType(DB03),VersionCreate(00),MinVersion(80),Access(E3),FolderInfo1(000000000000000000000000000000000000),FolderInfo2(000000000000000000000000000000000000)\n')
        run(['cadius','DELETEFILE',disk,'/'+volume+'/System/Start'])
        run(['cadius','ADDFILE',disk,'/'+volume+'/System',startup/'Start'])
        transfer_disk(out,icon_path)
        print('Disk images: force.2mg (boot), force-800k.2mg / force-800k.po (transfer)')
    print(f'Built {out / "FORCE"}; {len(catalogue)} missions')

if __name__=='__main__':main()
