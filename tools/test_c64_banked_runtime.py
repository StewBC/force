#!/usr/bin/env python3
"""Windowed c64m staged-loading probe.

Launch c64m with build/force.prg, autorun, control port and build/c64 mounted
on device 8, then run this script. Device transfers use the real game path.
After the menu launches Cross the river, the banked validator and the
resident c0 container are compared to the packaged bytes.
"""
import argparse
import json
import re
import sys
import time
from pathlib import Path
from c64_layout import ROOT, start
from c64_package import symbols

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
        poke(s['ui_extra'],b'\1');poke(s['ui_miss'],b'\1')
        breaks(s['session_init'],s['load_fail']);before=cpu()['cycles'];key('return');command('wait-paused 60000');state=cpu();assert state['pc']==s['session_init'],state
        report['timings']['menu_to_session_cycles']=state['cycles']-before
        compare('validator late install',c.mem(start('bank_validation'),s['bank_validation_end']-start('bank_validation'),'ram'),image[start('bank_validation')-base:s['bank_validation_end']-base])
        payload=(build/'c64/c0.seq').read_bytes()[2:]
        assert payload[:4]==b'FCTR'
        compare('resident container',c.mem(start('collection'),len(payload),'ram'),payload)
        (out/f'{label}-runtime-snapshot.bin').write_bytes(c.mem(0,65536,'ram'))
    freq=985248 if a.standard=='pal' else 1022727
    report['timings_seconds']={k:v/freq for k,v in report['timings'].items()}
    (out/f'{label}-runtime.json').write_text(json.dumps(report,indent=2)+'\n')
    command('break-clear-all')
    print(json.dumps(report))

if __name__=='__main__':main()
