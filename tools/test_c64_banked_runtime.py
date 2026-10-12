#!/usr/bin/env python3
"""Windowed c64m staged-loading byte, scatter, banking and reset probe.

Launch c64m with build/force.prg, autorun, control port and build/c64 mounted
on device 8, then run this script. Device transfers use the real game path.
Routine probes use a temporary JSR at a paused safe point, restore all patched
bytes, and archive snapshots. They do not replace disk installation.
"""
import argparse
import json
import re
import sys
import time
from pathlib import Path
from c64_layout import ROOT, start
from c64_package import symbols
import c64_missions

sys.path.insert(0,str(ROOT.parent/'machines/tools/c64'))
from c64_control_client import Ctl

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--build',type=Path,default=ROOT/'build');ap.add_argument('--label');ap.add_argument('--port',type=int,default=16511);ap.add_argument('--standard',choices=['pal','ntsc'],default='pal');ap.add_argument('--startup-only',action='store_true');a=ap.parse_args()
    c=Ctl(port=a.port,timeout=65);build=a.build.resolve();s=symbols(build/'c64/game-image.sym');b=symbols(build/'force.sym');out=ROOT/'build/c64/banked-evidence';label=a.label or a.standard;out.mkdir(exist_ok=True)
    report={'standard':a.standard,'comparisons':[],'timings':{},'timing_events':[]}
    def command(text):
        result=c.cmd(text)
        if result[0]=='error':raise RuntimeError(f'{text}: {result}')
        return result
    def poke(addr,data):
        c.id+=1;rid=c.id;c.s.sendall(f'{rid} set-memory ${addr:04x} {len(data)} ram\n'.encode()+data+b'\n')
        while True:
            r,res=c._parse_response_header(c._readline())
            if r==rid:
                if res[0]=='error':raise RuntimeError(res)
                return
    def cpu():
        text=command('get-cpu')[1]
        return {k:int(v,16 if k in ('pc','a','x','y','sp','p') else 10) for k,v in re.findall(r'(pc|a|x|y|sp|p|cycles)=([0-9A-F]+)',text)}
    def breaks(*addresses):
        command('break-clear-all')
        for addr in addresses:command(f'break-create exec ${addr:04x}')
    def reach(addr,seconds=60000):
        breaks(addr,b['boot_fail'],s['load_fail'])
        command('run');command(f'wait-paused {seconds}')
        state=cpu()
        if state['pc']!=addr:raise AssertionError(f'expected ${addr:04x}; got {state}; loader status {c.mem(0x819,1,"ram").hex()}')
        return state
    def compare(name,actual,expected):
        equal=actual==expected
        report['comparisons'].append({'name':name,'bytes':len(actual),'equal':equal,'first_difference':next((i for i,(x,y) in enumerate(zip(actual,expected)) if x!=y),None)})
        if not equal:raise AssertionError(report['comparisons'][-1])
    def key(name):
        command(f'key-down {name}');command('run');time.sleep(.12);command(f'key-up {name}');time.sleep(.15);command('pause')
    command('pause');breaks(b['boot_title_visible'],b['boot_fail'])
    command(f'load-prg {build}/force.prg');command('paste-events RUN\\[RT]');command('run');command('wait-paused 60000');visible=cpu();assert visible['pc']==b['boot_title_visible']
    compare('title before first disk transfer',c.mem(0xe000,8000,'ram'),(ROOT/'src/c64/generated/title_bitmap.bin').read_bytes())
    # RETURN held during loading must not leave the title.
    command('key-down return');ready=reach(b['boot_ready']);assert c.mem(0xd011,1)[0]&0x7f==0x3b
    report['timings']['game_cycles']=ready['cycles']-visible['cycles']
    image=(build/'c64/game-image.prg').read_bytes();base=int.from_bytes(image[:2],'little');image=image[2:]
    package=json.loads((build/'c64/memory-report.json').read_text())
    for chunk in package['chunks']:
        addr,n=chunk['destination'],chunk['expanded'];compare(chunk['file'],c.mem(addr,n,'ram'),image[addr-base:addr-base+n])
    compare('title after game placement',c.mem(0xe000,8000,'ram'),(ROOT/'src/c64/generated/title_bitmap.bin').read_bytes())
    command('key-up return');reach(s['show_title::wait_ret']);breaks(s['menu_loop'],s['load_fail']);key('return');command('wait-paused 60000');assert cpu()['pc']==s['menu_loop']
    assert c.mem(0xd011,1)[0]&0x20==0
    command('run-cycles 50000')
    if not a.startup_only:
        poke(s['ui_col'],b'\1');poke(s['ui_miss'],b'\1')
        breaks(s['session_init'],s['load_fail']);before=cpu()['cycles'];key('return');command('wait-paused 60000');state=cpu();assert state['pc']==s['session_init'],state
        report['timings']['menu_to_session_cycles']=state['cycles']-before
        compare('validator late install',c.mem(start('bank_validation'),s['bank_validation_end']-start('bank_validation'),'ram'),image[start('bank_validation')-base:s['bank_validation_end']-base])
        payload=(build/'c64/normandy.seq').read_bytes()[2:]
        import struct
        e=struct.unpack_from('<BBHHHH',payload,36);collection=payload[e[2]:e[2]+e[3]]
        compare('banked collection',c.mem(start('collection'),len(collection),'ram'),collection)
        def call(name,index=0,expect_error=False):
            print('probe',name,index,flush=True)
            addr=cpu()['pc'];original=c.mem(addr,8,'ram');routine=s[name]
            stub=bytes([0xa2,index,0x20,routine&255,routine>>8,0xea,0xea,0xea]);poke(addr,stub)
            breaks(addr+5,s['load_fail']);
            before_ports=c.mem(0,2);before=cpu();command('run');command('wait-paused 60000');after=cpu();assert after['pc']==(s['load_fail'] if expect_error else addr+5),(name,after)
            elapsed=after['cycles']-before['cycles']
            report['timing_events'].append({'routine':name,'index':index,'rejected':expect_error,'cycles':elapsed})
            report['timings'][f'{name}_{index}'+('_rejected' if expect_error else '')+'_cycles']=elapsed
            assert c.mem(0,2)==before_ports,(before_ports.hex(),c.mem(0,2).hex())
            assert c.mem(s['bank_active'],1,'ram')==b'\0'
            if expect_error:
                poke(addr,original)
                return
            poke(addr+5,bytes([0x4c,addr&255,addr>>8]));breaks(addr);command('run');command('wait-paused 10000');poke(addr,original)
        def active_reference(index):
            raw,body=c64_missions.unpack(collection,index);raw=bytearray(raw);spawn=raw[6];scalar=7+3*spawn;counts=raw[scalar:scalar+6];ops=scalar+13;n=counts[0]
            for pc in range(n):
                if raw[ops+pc]==10:
                    lo=ops+n+pc;hi=ops+2*n+pc;ptr=(raw[lo]|raw[hi]<<8)+0x900;raw[lo]=ptr&255;raw[hi]=ptr>>8
            dest=bytearray(640);dest[:7]=raw[:7];cursor=7
            def scatter(at,count,stride,fields):
                nonlocal cursor
                for field in range(fields):dest[at+field*stride:at+field*stride+count]=raw[cursor:cursor+count];cursor+=count
            scatter(7,spawn,32,3);dest[103:116]=raw[cursor:cursor+13];cursor+=13
            for at,count,stride,fields in zip((116,372,384,424,552,600),counts,(64,12,8,32,16,8),(4,1,5,4,3,5)):scatter(at,count,stride,fields)
            return bytes(raw),bytes(dest)
        for index in (1,0,2,3,4,1):
            call('mission_activate',index);raw,active=active_reference(index)
            compare(f'mission {index} workspace',c.mem(0x900,len(raw),'ram'),raw)
            compare(f'mission {index} scatter',c.mem(start('active'),640,'ram'),active)
            call('world_load');compare(f'mission {index} F3 immutable workspace',c.mem(0x900,len(raw),'ram'),raw)
        import gen_c64
        for map_name in ('bastogne','normandy'):
            name=map_name.upper().encode('ascii')
            poke(s['cat_load_name'],name+b'\0'*(16-len(name)));poke(s['map_len'],bytes([len(name)]))
            call('map_load')
            with __import__('contextlib').redirect_stdout(__import__('io').StringIO()):
                reference=gen_c64._compute(map_name)
            compare(map_name+' tiles',c.mem(start('tiles'),3200,'ram'),bytes(reference['tiles']))
            compare(map_name+' paper',c.mem(start('paper'),3200,'ram'),bytes(reference['paper']))
            compare(map_name+' routing program',c.mem(start('routing_program'),256,'ram'),reference['route_program'])
            call('mission_activate',0);call('world_load')
            routes=c.mem(s['portal_from'],304,'ram')+c.mem(s['door_n'],514,'ram')
            compare(map_name+' initial routing scatter/reset',routes,reference['routes'])
        # A real device-8 synthetic map transfer exceeds the old collective
        # limit and exercises directory ordinal 15 and the exact 597-byte home.
        from test_c64_packages import Packages
        with __import__('contextlib').redirect_stdout(__import__('io').StringIO()):
            large=c64_missions.pack([(str(i),Packages.boundary(9)) for i in range(16)],None)
        payload=(build/'c64/normandy.seq').read_bytes()[2:]
        entries=[list(struct.unpack_from('<BBHHHH',payload,26+10*i)) for i in range(payload[25])]
        bodies=[payload[e[2]:e[2]+e[3]] for e in entries]
        bodies[1]=large;entries[1][3]=len(large);entries[1][5]=len(large)
        offset=26+10*len(entries);directory=bytearray()
        for e,body in zip(entries,bodies):
            e[2]=offset;directory+=struct.pack('<BBHHHH',*e);offset+=len(body)
        header=bytearray(payload[:26]);header[6]=16;header[10]=0
        synthetic=header+directory+b''.join(bodies);synthetic[12:14]=struct.pack('<H',len(synthetic));synthetic[10]=c64_missions.checksum(synthetic)
        from c64_package import parse_map
        parse_map(synthetic)
        (build/'c64/synthetic.seq').write_bytes(b'\0\xa0'+synthetic)
        poke(s['cat_load_name'],b'SYNTHETIC'+bytes(7));poke(s['map_len'],b'\x09');call('map_load')
        guard_before=c.mem(0x8ff,1,'ram');guard_after=c.mem(0xb55,8,'ram');vectors=c.mem(0xfffa,6,'ram')
        call('mission_activate',15)
        compare('597-byte record',c.mem(0x900,597,'ram'),Packages.boundary(9))
        compare('597-byte lower guard',c.mem(0x8ff,1,'ram'),guard_before)
        compare('597-byte deck guard',c.mem(0xb55,8,'ram'),guard_after)
        compare('hardware vector reservation',c.mem(0xfffa,6,'ram'),vectors)
        # Oversize rejection occurs before writing or invalidating the workspace.
        before_workspace=c.mem(0x900,597,'ram');before_active=c.mem(start('active'),640,'ram')
        poke(start('collection')+6+15*10+4,(598).to_bytes(2,'little'))
        call('mission_activate',15,expect_error=True)
        compare('598-byte rejection workspace guard',c.mem(0x900,597,'ram'),before_workspace)
        compare('598-byte rejection scatter guard',c.mem(start('active'),640,'ram'),before_active)
        compare('598-byte rejection deck guard',c.mem(0xb55,8,'ram'),guard_after)
        (out/f'{label}-runtime-snapshot.bin').write_bytes(c.mem(0,65536,'ram'))
    freq=985248 if a.standard=='pal' else 1022727
    report['timings_seconds']={k:v/freq for k,v in report['timings'].items()}
    (out/f'{label}-runtime.json').write_text(json.dumps(report,indent=2)+'\n')
    command('break-clear-all')
    print(json.dumps(report))

if __name__=='__main__':main()
