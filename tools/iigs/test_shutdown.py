#!/usr/bin/env python3
"""Check native shutdown restores the caller ABI and video state before QuitGS.

This terminates the guest application; use only a private test emulator session.
"""
import argparse
import json
from pathlib import Path
from runtime import Runtime
from probe import DEFAULT_SOURCE,read,registers


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--socket',required=True)
    p.add_argument('--symbols',type=Path,required=True);p.add_argument('--evidence',type=Path,required=True)
    a=p.parse_args();g=Runtime(a.socket,a.symbols,DEFAULT_SOURCE)
    from gs2debug import BP_KIND_EXEC,REG_PC,REG_PB
    bp=None
    try:
        g.locate().freeze();before=registers(g.client.get_regs())
        saved=read(g.client,before['sp']+1,4)
        expected=dict(p=saved[0],d=int.from_bytes(saved[1:3],'little'),db=saved[3],sp=before['sp']+4)
        assert expected['d']==int.from_bytes(g.mem('old_dp',2),'little')
        video={addr:g.mem(name)[0] for addr,name in ((0xe0c029,'old_shr'),(0xe0c034,'old_border'),(0xe0c035,'old_shadow'))}
        start=g.address('shutdown');code=read(g.client,start,128)
        quit_call=code.index(bytes.fromhex('22a800e12920'))+start
        bp=g.client.bp_set(kind=BP_KIND_EXEC,address=quit_call)
        g.client.set_regs(REG_PC|REG_PB,pc=start&65535,pb=start>>16)
        g.client.continue_();event=g.client.wait_stopped(timeout=20);assert event.bp_id==bp
        after=registers(g.client.get_regs())
        for name,value in expected.items():assert after[name]==value,(name,value,after[name])
        for addr,value in video.items():assert read(g.client,addr,1)[0]==value,(hex(addr),value,read(g.client,addr,1))
        a.evidence.parent.mkdir(parents=True,exist_ok=True)
        a.evidence.write_text(json.dumps(dict(caller_registers_restored=expected,video_registers_restored=True,quitgs_reached=True),indent=2)+'\n')
        print('Native shutdown ABI/video restoration passed',flush=True)
        g.client.bp_clear(bp);bp=None;g.client.continue_()
    finally:
        if bp is not None:g.client.bp_clear(bp)
        g.close()

if __name__=='__main__':main()
