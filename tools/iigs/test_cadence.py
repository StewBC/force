#!/usr/bin/env python3
"""Measure the real main loop against GS/OS's 60-Hz tick at stock IIgs speed."""
import argparse
import json
from pathlib import Path
from probe import DEFAULT_SOURCE,read,registers
from runtime import Runtime
from test_runtime import mission
from test_flow import frame


def measure(g,index,frames):
    mission(g,index);g.call('draw_all');g.call('render_frame')
    assert not registers(g.client.get_regs())['p']&4,'Live sample requires normal IRQs'
    g.client.write_mem(0,g.mailbox+17,b'\0');frame(g)
    start=int.from_bytes(g.mem('frame_now',2),'little')
    ticks=int.from_bytes(read(g.client,g.mailbox+18,4),'little')
    for _ in range(frames):frame(g)
    elapsed=(int.from_bytes(g.mem('frame_now',2),'little')-start)&65535
    logic=(int.from_bytes(read(g.client,g.mailbox+18,4),'little')-ticks)&0xffffffff
    speed=read(g.client,0xe0c036,1)[0]
    g.client.write_mem(0,g.mailbox+17,b'\1')
    assert speed&128,'IIgs fast CPU switch is disabled'
    return dict(system_ticks=elapsed,logic_ticks=logic,logic_hz=logic*60/elapsed,fast_switch=speed)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--socket',required=True)
    p.add_argument('--symbols',required=True,type=Path);p.add_argument('--evidence',required=True,type=Path)
    p.add_argument('--frames',type=int,default=30);a=p.parse_args()
    g=Runtime(a.socket,a.symbols,DEFAULT_SOURCE)
    try:
        g.locate().freeze();result={}
        for row in g.manifest['catalogue']:
            result[row['stem']]=measure(g,row['id'],a.frames)
            print(row['stem'],result[row['stem']],flush=True)
        a.evidence.parent.mkdir(parents=True,exist_ok=True);a.evidence.write_text(json.dumps(result,indent=2)+'\n')
        mission(g,0);g.call('draw_all');g.call('render_frame')
    finally:g.close(resume=True)

if __name__=='__main__':main()
