"""Compile authored FORCE catalogue to bank-local IIgs mission images.

Uses the lead platform's semantic compiler, but no C64 loader destinations.
"""
from pathlib import Path
import json
import re
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
import gen_c64
import gen_sdl
import gen_title


def dc_bytes(label, data):
    data=bytes(data)
    lines=[label+' anop']
    lines += [" dc h'"+data[i:i+32].hex().upper()+"'" for i in range(0,len(data),32)]
    return '\n'.join(lines)+'\n'


def capacity(name, values):
    if name in ('rom_tiles','rom_paper'): return 3200
    if name.startswith('rom_room_') and name!='rom_room_count': return 16
    if name.startswith('rom_cover_') and name!='rom_cover_count': return 128
    if name.startswith('rom_portal_') and name!='rom_portal_count': return 24
    if name.startswith(('rom_scout_','rom_spawn_')) and not name.endswith('count'): return 32
    for prefix,n in [('sc_op_',64),('sc_beat_pc',12),('sc_watch_',8),('sc_pred_',32),('sc_where_',16),('sc_spawn_',8)]:
        if name.startswith(prefix) and not name.endswith('count'): return n
    return len(values)


def generate(root, out):
    catalogue=gen_sdl.load_missions(root/'assets/missions.txt')
    compiled=[gen_c64._compute(row[0],out_dir=out/'compiler') for row in catalogue]
    # Stable padded structure permits original core short pointers with any mission.
    names=[n for n in compiled[0]['labels'] if n not in ('rom_tile_class','rom_tile_force','deck_count','deck_x','deck_y')]
    names += ['asset_deck_count','asset_deck_x','asset_deck_y','route_components','objective_text']
    caps={n:capacity(n,compiled[0]['labels'][n]) for n in names if n in compiled[0]['labels']}
    caps.update(asset_deck_count=1,asset_deck_x=16,asset_deck_y=16,route_components=16,objective_text=512)
    offsets={}; size=0
    for name in names: offsets[name]=size;size+=caps[name]
    size=(size+1)&~1
    assert size<16384
    layout='; Generated bank-local offsets; no C64 addresses.\n'
    layout+='\n'.join(f'{n} equ active_mission+{offsets[n]}' for n in names)+'\n'
    layout+=f'ACTIVE_BYTES equ {size}\nMISSION_COUNT equ {len(compiled)}\n'
    layout+=dc_bytes('rom_tile_class',compiled[0]['class_table'])+dc_bytes('rom_tile_force',compiled[0]['force'])
    # Compile directly; force_iigs does not require a preexisting C64 build.
    _tw,_th,columns,count,png=gen_sdl.load_tsx(root/'assets/maps/tiles.tsx')
    _w,_h,rows=gen_c64.load_indices(png)
    tiles=gen_c64.slice_index_tiles(rows,columns,count)
    charset=bytearray(2048)
    for tid,tile in enumerate(tiles[:gen_sdl.RUNTIME_TILES]):
        encode=gen_c64.mc_row_deck if tid in (80,81) else gen_c64.mc_row
        for y,row in enumerate(tile): charset[tid*8+y]=encode(row)
    for gi,glyph in enumerate(gen_c64.load_font(root/'src/sdl/core/font.c')):
        for y,b in enumerate(glyph): charset[(128+gi)*8+y]=gen_c64.rev8(b)
    title_rows=gen_title.read_png(root/'assets/png/force_title_c64.png')
    title_pixels=bytes(gen_title.index_of(row[x:x+3])*17 for row in title_rows for x in range(0,len(row),3))
    assert len(title_pixels)==32000
    (out/'title.bin').write_bytes(title_pixels)
    palette_words=[]
    for rgb in gen_title.PALETTE:
        r,g,b=[min(15,(c+8)//17) for c in rgb]
        palette_words.append((r<<8)|(g<<4)|b)
    layout+="title_palette dc i2'"+','.join(str(c) for c in palette_words)+"'\n"
    title_source=out/'titledata.asm'
    title_source.write_text(' case on\nTITLEIMG DATA TITLEIMG\ntitle_image ENTRY\n'+dc_bytes('title_data',title_pixels)+' END\n')
    # Mission glyph IDs stay semantic; IIgs render frames can evolve independently.
    layout+='tile_frames anop\n'
    for first in range(0,128,16): layout+=" dc i2'"+','.join(str(i*2) for i in range(first,first+16))+"'\n"
    layout+=dc_bytes('initial_charset',charset)
    (out/'charset.bin').write_bytes(charset)
    layout+='CAMPAIGN_HEADER_BYTES equ '+str(5+16*len(catalogue))+'\n'
    layout+='CAMPAIGN_BYTES equ '+str(6+17*len(catalogue))+'\n'
    identity=b'FRC1'+bytes([len(catalogue)])+b''.join(row[0].encode('ascii').ljust(16,b'\0') for row in catalogue)
    layout+=dc_bytes('campaign_template',identity)
    layout+="mission_titles dc a2'"+','.join('mission_title'+str(i) for i in range(len(catalogue)))+"'\n"
    for i,row in enumerate(catalogue): layout+=dc_bytes('mission_title'+str(i),row[4].encode('ascii')+b'\0')
    contracts=[];body=[]
    for line in layout.splitlines():
        if re.match(r'(ACTIVE_BYTES|MISSION_COUNT|CAMPAIGN_HEADER_BYTES|CAMPAIGN_BYTES) equ ',line): contracts.append(line)
        else: body.append(line)
    (out/'asset_contracts.s').write_text('\n'.join(contracts)+'\n')
    (out/'assets.s').write_text('\n'.join(body)+'\n')
    # Expand one glyph byte into four packed SHR bytes. The generic compositor
    # keeps source masks/font IDs intact; native packing is a table lookup.
    lookup=bytearray()
    for paper in range(8):
        for bits in range(256):
            lookup.extend((2,11,14,paper)[(bits>>shift)&3]*17 for shift in (6,4,2,0))
    for background in (0,11):
        for ink in range(16):
            for bits in range(256):
                pixels=[ink if bits&(128>>x) else background for x in range(8)]
                lookup.extend((pixels[x]<<4)|pixels[x+1] for x in (0,2,4,6))
    assert len(lookup)==40960
    lookup_source=out/'celllookup.asm'
    lookup_source.write_text(' case on\nCELLLOOK DATA CELLLOOK\ncell_lookup ENTRY\n'+dc_bytes('lookup_data',lookup)+' END\n')
    sources=[title_source,lookup_source]; metadata=[]
    for mid,(row,data) in enumerate(zip(catalogue,compiled)):
        payload=bytearray(size)
        labels=dict(data['labels'])
        labels.update(asset_deck_count=labels['deck_count'],asset_deck_x=labels['deck_x'],asset_deck_y=labels['deck_y'],route_components=list(data['route_program'][:16]))
        # Objective operands are relocated to actual linked core pointers at load.
        text=bytearray()
        for pc,opcode in enumerate(data['script'].op_code):
            if opcode==10:
                message=data['script'].objective_text[data['script'].op_a[pc]].encode('ascii')+b'\0'
                rel=offsets['objective_text']+len(text)
                labels['sc_op_a'][pc]=rel&255;labels['sc_op_b'][pc]=rel>>8
                text+=message
        labels['objective_text']=list(text)
        for name in names:
            values=bytes(labels[name]); assert len(values)<=caps[name],(name,len(values),caps[name])
            payload[offsets[name]:offsets[name]+len(values)]=values
        variants=data['route_variants']
        routeblob=b''.join(bytes(v) for v in variants)
        assert len(payload)+len(routeblob)<=65536, 'mission route bank overflow'
        assert len(routeblob)==818*len(variants)
        source=f' case on\n ALIGN 256\nMIS{mid} DATA MIS{mid}\nmission{mid} entry\n'+dc_bytes('mission_image'+str(mid),payload)+f'route{mid} entry\n'+dc_bytes('route_image'+str(mid),routeblob)+' END\n'
        path=out/f'mission{mid}.asm';path.write_text(source);sources.append(path)
        metadata.append(dict(id=mid,stem=data['stem'],title=row[4],width=data['width'],height=data['height'],routes=len(variants),bytes=len(payload)+len(routeblob)))
    tables='\n'.join(f' using MIS{i}' for i in range(len(compiled)))+'\n'
    tables+='mission_ptrs dc a4\''+','.join('mission'+str(i) for i in range(len(compiled)))+"'\n"
    tables+='route_ptrs dc a4\''+','.join('route'+str(i) for i in range(len(compiled)))+"'\n"
    (out/'pointers.s').write_text(tables)
    (out/'catalogue.json').write_text(json.dumps(metadata,indent=2)+'\n')
    return sources,metadata
