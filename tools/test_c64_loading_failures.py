#!/usr/bin/env python3
"""Device-8 malformed-file/guard probes on an isolated folder fixture."""
import argparse
import json
import re
import shutil
import sys
from pathlib import Path
from c64_layout import ROOT
from c64_package import symbols
sys.path.insert(0,str(ROOT.parent/'machines/tools/c64'))
from c64_control_client import Ctl

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--port',type=int,default=16514);a=ap.parse_args();c=Ctl(port=a.port,timeout=65)
    b=symbols(ROOT/'build/force.sym');s=symbols(ROOT/'build/c64/game-image.sym');folder=ROOT/'build/c64/failure-fixture';folder.mkdir(exist_ok=True)
    for p in (ROOT/'build/c64').glob('*.seq'):shutil.copy2(p,folder/p.name)
    shutil.copy2(ROOT/'build/c64/campaign.prg',folder/'campaign.prg')
    def cmd(text):
        result=c.cmd(text)
        if result[0]=='error':raise RuntimeError((text,result))
        return result
    def cpu():
        text=cmd('get-cpu')[1];return {k:int(v,16 if k in ('pc','p') else 10) for k,v in re.findall(r'(pc|p|cycles)=([0-9A-F]+)',text)}
    def breaks(*addresses):
        cmd('break-clear-all')
        for addr in addresses:cmd(f'break-create exec ${addr:04x}')
    def poke(addr,data):
        c.id+=1;rid=c.id;c.s.sendall(f'{rid} set-memory ${addr:04x} {len(data)} ram\n'.encode()+data+b'\n')
        while True:
            n,result=c._parse_response_header(c._readline())
            if n==rid:
                if result[0]=='error':raise RuntimeError(result)
                return
    cmd('pause');cmd(f'mount-d64 8 {folder}')
    original=(folder/'game00.seq').read_bytes();results=[]
    for case in ('missing','magic','version','layout','codec','checksum','truncated','oversized'):
        file=folder/'game00.seq';file.write_bytes(original)
        if case=='missing':file.unlink()
        elif case=='truncated':file.write_bytes(original[:-1])
        elif case=='oversized':file.write_bytes(original+bytes(6401))
        else:
            data=bytearray(original);position={'magic':2,'version':6,'layout':8,'codec':10,'checksum':len(data)-1}[case];data[position]^=0x80;file.write_bytes(data)
        breaks(b['boot_title_visible'],b['boot_fail']);cmd(f'load-prg {ROOT}/build/force.prg');cmd('paste-events RUN\\[RT]');cmd('run');cmd('wait-paused 60000');assert cpu()['pc']==b['boot_title_visible']
        guards={addr:c.mem(addr,n,'ram') for addr,n in ((0xb54,1),(s['deck_end'],8),(0xb900,8),(0xfffa,6))}
        breaks(b['boot_fail'],b['boot_ready'],s['main']);cmd('run');cmd('wait-paused 60000');state=cpu();assert state['pc']==b['boot_fail'],(case,state)
        assert all(c.mem(addr,len(raw),'ram')==raw for addr,raw in guards.items()),case
        assert c.mem(1,1)[0]&7==6
        breaks(b['boot_error::halt']);cmd('run');cmd('wait-paused 10000');assert c.mem(0xd011,1)[0]&0x20==0
        results.append({'case':case,'guard_bytes_unchanged':True,'game_not_entered':True,'visible_error':True,'kernal_io_restored':True})
        print(case,'passed',flush=True)
    file.write_bytes(original)
    # Map cases run the actual bounded reader and directory/placement checks.
    map_original=(folder/'normandy.seq').read_bytes()
    import c64_missions
    for case in ('version','layout','checksum','duplicate','overlap','destination','reserved','truncated','oversized'):
        bad=bytearray(map_original)
        if case=='truncated':bad=bad[:-1]
        elif case=='oversized':bad+=bytes(6401)
        elif case=='checksum':bad[-1]^=1
        else:
            p=2
            if case=='version':bad[p+4]^=1
            elif case=='layout':bad[p+8]^=1
            elif case=='duplicate':bad[p+36]=bad[p+26]
            elif case=='overlap':bad[p+38:p+40]=bad[p+28:p+30]
            elif case=='destination':bad[p+32:p+34]=b'\0\0'
            else:bad[p+14]=1
            bad[p+10]=0;bad[p+10]=c64_missions.checksum(bad[p:])
        (folder/'normandy.seq').write_bytes(bad)
        breaks(s['show_title::wait_ret'],b['boot_fail']);cmd(f'load-prg {ROOT}/build/force.prg');cmd('paste-events RUN\\[RT]');cmd('run');cmd('wait-paused 60000');assert cpu()['pc']==s['show_title::wait_ret']
        # Disable the title through the real RETURN path before map replacement.
        breaks(s['menu_loop']);cmd('key-down return');cmd('run');cmd('wait-paused 10000');cmd('key-up return')
        addr=s['menu_loop'];poke(s['cat_load_name'],b'NORMANDY'+bytes(8));poke(s['map_len'],b'\x08')
        guards={a:c.mem(a,n,'ram') for a,n in ((0x8ff,1),(0x900,597),(0xb55,8),(0xb900,8),(0xbc80,640),(0xfffa,6))}
        routine=s['map_load'];original_code=c.mem(addr,8,'ram');poke(addr,bytes([0x78,0x20,routine&255,routine>>8,0xea,0xea,0xea,0xea]))
        breaks(s['load_fail'],addr+4);cmd('run');cmd('wait-paused 60000');state=cpu();assert state['pc']==s['load_fail'],(case,state)
        assert all(c.mem(a,len(raw),'ram')==raw for a,raw in guards.items()),case
        assert c.mem(1,1)[0]&7==6 and c.mem(s['bank_active'],1,'ram')==b'\0'
        poke(addr,original_code)
        breaks(s['error_wait_return']);cmd('run');cmd('wait-paused 10000');assert cpu()['pc']==s['error_wait_return']
        breaks(s['menu_loop']);cmd('key-down return');cmd('run');cmd('wait-paused 10000');cmd('key-up return');assert cpu()['pc']==s['menu_loop']
        assert c.mem(s['resident'],1,'ram')==b'\xff' and c.mem(s['active_mission'],1,'ram')==b'\xff'
        results.append({'case':'map '+case,'menu_recovery':True,'status':c.mem(0x819,1,'ram')[0],'guard_bytes_unchanged':True,'mission_not_activated':True,'kernal_io_restored':True})
        print('map',case,'passed',flush=True)
    (folder/'normandy.seq').write_bytes(map_original)
    (ROOT/'build/c64/banked-evidence/failure-guards.json').write_text(json.dumps(results,indent=2)+'\n')
    print('All',len(results),'device-8 failure cases passed')

if __name__=='__main__':main()
