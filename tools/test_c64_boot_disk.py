#!/usr/bin/env python3
"""Measure normal BASIC LOAD/RUN of FORCE on a real 1541 D64 mount."""
import argparse
import json
import re
import sys
from c64_layout import ROOT
from c64_package import symbols
sys.path.insert(0,str(ROOT.parent/'machines/tools/c64'))
from c64_control_client import Ctl

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--port',type=int,default=16512);a=ap.parse_args();c=Ctl(port=a.port,timeout=65);b=symbols(ROOT/'build/force.sym')
    def cmd(t):
        r=c.cmd(t)
        if r[0]=='error':raise RuntimeError((t,r))
        return r
    def cpu():
        t=cmd('get-cpu')[1];return int(re.search('pc=([0-9A-F]+)',t)[1],16),int(re.search('cycles=([0-9]+)',t)[1])
    def breaks(*addresses):
        cmd('break-clear-all')
        for addr in addresses:cmd(f'break-create exec ${addr:04x}')
    cmd('pause');cmd(f'mount-d64 8 {ROOT}/build/force.d64');breaks(0xa474);cmd('reset');cmd('run');cmd('wait-paused 60000');assert cpu()[0]==0xa474
    breaks(0xffd5);cmd('run-cycles 500000');cmd('paste-events LOAD"FORCE",8,1\\[RT]');cmd('run');cmd('wait-paused 60000');assert cpu()[0]==0xffd5;before=cpu()[1]
    breaks(0xa474);cmd('run');cmd('wait-paused 60000');assert cpu()[0]==0xa474;after=cpu()[1]
    image=(ROOT/'build/force.prg').read_bytes();base=int.from_bytes(image[:2],'little');assert c.mem(base,len(image)-2,'ram')==image[2:]
    breaks(b['boot_title_visible'],b['boot_fail']);cmd('paste-events RUN\\[RT]');cmd('run');cmd('wait-paused 10000');assert cpu()[0]==b['boot_title_visible']
    assert c.mem(0xe000,8000,'ram')==(ROOT/'src/c64/generated/title_bitmap.bin').read_bytes()
    report={'normal_LOAD_FORCE_8_1':True,'initial_prg_byte_comparison':True,'RUN_title_before_game_transfer':True,'bootstrap_bytes':len(image),'bootstrap_load_cycles':after-before,'bootstrap_load_seconds':(after-before)/985248}
    (ROOT/'build/c64/banked-evidence/pal-bootstrap-d64.json').write_text(json.dumps(report,indent=2)+'\n');print(report)

if __name__=='__main__':main()
