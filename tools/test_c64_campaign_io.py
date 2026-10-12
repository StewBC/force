#!/usr/bin/env python3
"""Campaign save/refusal/F8 probes on an isolated copy, never live scores."""
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
    ap=argparse.ArgumentParser();ap.add_argument('--port',type=int,default=16514);a=ap.parse_args();c=Ctl(port=a.port,timeout=65);s=symbols(ROOT/'build/c64/game-image.sym');b=symbols(ROOT/'build/force.sym');folder=ROOT/'build/c64/campaign-fixture';folder.mkdir(exist_ok=True)
    for p in (ROOT/'build/c64').glob('*.seq'):shutil.copy2(p,folder/p.name)
    shutil.copy2(ROOT/'build/c64/campaign.prg',folder/'campaign.prg');live=(ROOT/'build/c64/campaign.prg').read_bytes()
    def cmd(t):
        r=c.cmd(t)
        if r[0]=='error':raise RuntimeError(r)
        return r
    def cpu():return {k:int(v,16) for k,v in re.findall(r'(pc|p|sp)=([0-9A-F]+)',cmd('get-cpu')[1])}
    def poke(addr,data):
        c.id+=1;rid=c.id;c.s.sendall(f'{rid} set-memory ${addr:04x} {len(data)} ram\n'.encode()+data+b'\n')
        while True:
            n,r=c._parse_response_header(c._readline())
            if n==rid:
                if r[0]=='error':raise RuntimeError(r)
                return
    def breaks(*addresses):
        cmd('break-clear-all')
        for addr in addresses:cmd(f'break-create exec ${addr:04x}')
    cmd('pause');breaks(s['show_title::wait_ret'],b['boot_fail']);cmd(f'load-prg {ROOT}/build/force.prg');cmd('paste-events RUN\\[RT]');cmd('run');cmd('wait-paused 60000');assert cpu()['pc']==s['show_title::wait_ret']
    breaks(s['menu_loop']);cmd('key-down return');cmd('run');cmd('wait-paused 10000');cmd('key-up return')
    def call(name,value=0,saving=False):
        addr=cpu()['pc'];original=c.mem(addr,12,'ram');routine=s[name];end=addr+6
        poke(addr,bytes([0x78,0xa9,value,0x20,routine&255,routine>>8,0xea,0xea,0xea,0xea,0xea,0xea]))
        breaks(end,s['note_save']) if saving else breaks(end)
        cmd('run');cmd('wait-paused 10000')
        if saving:
            assert cpu()['pc']==s['note_save']
            assert c.mem(0x400+22*40,6,'ram')==bytes([ord(ch)+96 for ch in 'SAVING'])
            breaks(end);cmd('run');cmd('wait-paused 10000')
        assert cpu()['pc']==end
        poke(end,bytes([0x4c,addr&255,addr>>8]));breaks(addr);cmd('run');cmd('wait-paused 10000');poke(addr,original)
    poke(s['miss_score']+1,b'\7');call('menu_save_now',saving=True)
    assert c.mem(s['ui_save'],1,'ram')==b'\0'
    saved=(folder/'campaign.prg').read_bytes();assert b'NORMANDY 1 7 cross_river' in saved
    poke(s['miss_score']+1,b'\10')
    try:
        (folder/'campaign.prg').chmod(0o444);folder.chmod(0o555);call('menu_save_now',saving=True)
        assert c.mem(s['ui_save'],1,'ram')==b'\1'
        assert (folder/'campaign.prg').read_bytes()==saved
        assert c.mem(0x400+22*40,11,'ram')==bytes([ord(ch)+96 for ch in 'SAVE FAILED'])
    finally:
        folder.chmod(0o755);(folder/'campaign.prg').chmod(0o644)
    call('menu_handle',9);assert c.mem(s['ui_f8'],1,'ram')==b'\1';call('menu_handle',9,saving=True)
    assert c.mem(s['ui_save'],1,'ram')==b'\0'
    cleared=(folder/'campaign.prg').read_bytes()[2:].decode('ascii');assert all(line.split()[2]=='-' for line in cleared.splitlines())
    assert (ROOT/'build/c64/campaign.prg').read_bytes()==live
    report={'successful_write':True,'saving_visible':True,'refused_write_unchanged':True,'save_failed_visible':True,'F8_two_press_reset_saved':True,'live_campaign_unchanged':True}
    (ROOT/'build/c64/banked-evidence/campaign-io.json').write_text(json.dumps(report,indent=2)+'\n');print(report)

if __name__=='__main__':main()
