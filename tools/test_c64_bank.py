#!/usr/bin/env python3
"""Probe CPU port, interrupt flags, RAM vectors and RESTORE while banked."""
import argparse
import json
import re
import sys
from c64_layout import ROOT
from c64_package import symbols
sys.path.insert(0,str(ROOT.parent/'machines/tools/c64'))
from c64_control_client import Ctl

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--port',type=int,default=16511);ap.add_argument('--label',default='pal');a=ap.parse_args();c=Ctl(port=a.port,timeout=65);s=symbols(ROOT/'build/c64/game-image.sym');b=symbols(ROOT/'build/force.sym')
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
    cmd('pause');cmd(f'mount-d64 8 {ROOT}/build/c64');breaks(s['show_title::wait_ret'],b['boot_fail']);cmd(f'load-prg {ROOT}/build/force.prg');cmd('paste-events RUN\\[RT]');cmd('run');cmd('wait-paused 60000');assert cpu()['pc']==s['show_title::wait_ret']
    addr=cpu()['pc'];original=c.mem(addr,12,'ram');ports=c.mem(0,2);flags=cpu()['p'];vector=c.mem(0xfffa,6,'ram');before_music=c.mem(s['music_on'],1,'ram');assert before_music==b'\1'
    assert int.from_bytes(vector[:2],'little')==s['bank_nmi']
    enter=s['bank_enter'];leave=s['bank_leave'];loop=addr+3;done=addr+9
    stub=bytes([0x20,enter&255,enter>>8,0x4c,loop&255,loop>>8,0x20,leave&255,leave>>8,0x4c,done&255,done>>8]);poke(addr,stub);breaks(loop);cmd('run');cmd('wait-paused 10000');assert cpu()['pc']==loop
    bank_ports=c.mem(0,2);assert bank_ports[1]&7==5 and cpu()['p']&4
    bank_sp=cpu()['sp'];breaks(s['bank_nmi']);cmd('restore');cmd('run');cmd('wait-paused 10000');assert cpu()['pc']==s['bank_nmi'] and cpu()['sp']==bank_sp-3
    cmd('break-clear-all');cmd('run-cycles 4000')
    assert c.mem(0,2)==bank_ports and cpu()['sp']==bank_sp and c.mem(s['bank_active'],1,'ram')==b'\1'
    poke(loop,bytes([0x4c,(addr+6)&255,(addr+6)>>8]));breaks(done);cmd('run');cmd('wait-paused 10000');assert cpu()['pc']==done
    assert c.mem(0,2)==ports and cpu()['p']&5==flags&5 and c.mem(s['bank_active'],1,'ram')==b'\0'
    assert c.mem(0xfffa,6,'ram')==vector
    poke(addr,original)
    report={'ports_before':ports.hex(),'ports_banked':bank_ports.hex(),'ports_after':c.mem(0,2).hex(),'flags_before':flags,'flags_after':cpu()['p'],'restore_nmi_handler_entered':True,'restore_nmi_stack_preserved':True,'vectors':vector.hex(),'title_music_on':True,'sid_volume':c.mem(0xd418,1)[0]&15}
    (ROOT/f'build/c64/banked-evidence/{a.label}-bank.json').write_text(json.dumps(report,indent=2)+'\n');print(report)

if __name__=='__main__':main()
