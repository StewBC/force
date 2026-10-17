#!/usr/bin/env python3
"""Check for unsolicited cursor input during live gameplay with IRQs enabled.

Use a private session and a neutral controller/mouse-as-joystick. Unlike stopped
routine-call fixtures, this runs the real main loop and its system interrupts.
"""
import argparse
import json
from pathlib import Path
from probe import DEFAULT_SOURCE, registers
from runtime import Runtime
from test_runtime import mission


def sample(game,index,frames):
    from gs2debug import BP_KIND_EXEC
    mission(game,index)
    x=game.mem('win_w')[0]-1;y=game.mem('win_h')[0]-1
    game.set('cursor_x',x);game.set('cursor_y',y)
    game.client.write_mem(0,game.mailbox+17,b'\0')
    bp=game.client.bp_set(kind=BP_KIND_EXEC,address=game.address('do_tick'))
    rows=[]
    try:
        for _ in range(frames):
            game.client.continue_();event=game.client.wait_stopped(timeout=20)
            assert event.bp_id==bp
            assert registers(game.client.get_regs())['p']&4==0,'Test must run with IRQs enabled'
            axes=list(game.mem('paddle_x',2));delta=list(game.mem('in_dx',2))
            cursor=list(game.mem('cursor_x',2))
            rows.append(dict(paddles=axes,delta=delta,cursor=cursor))
    finally:
        game.client.write_mem(0,game.mailbox+17,b'\1');game.client.bp_clear(bp)
    return rows,[r for r in rows if r['delta']!=[0,0] or r['cursor']!=[x,y]]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--socket',required=True);p.add_argument('--symbols',required=True,type=Path)
    p.add_argument('--frames',type=int,default=180);p.add_argument('--evidence',required=True,type=Path)
    p.add_argument('--joystick',action='store_true',help='Also exercise enabled analog sampling; use a neutral controller')
    a=p.parse_args();game=Runtime(a.socket,a.symbols,DEFAULT_SOURCE);results={};bad=[]
    try:
        game.locate().freeze()
        game.set('joystick_enabled',int(a.joystick))
        # Verify sampling also retains an already masked caller's IRQ state.
        assert game.call('input_joystick')['p']&4
        for index in (0,1):
            rows,failures=sample(game,index,a.frames)
            name=game.manifest['catalogue'][index]['stem']
            results[name]=dict(frames=a.frames,unsolicited=len(failures),samples=rows)
            bad.extend(failures)
            print(name,':',len(failures),'unsolicited inputs in',a.frames,'live updates',flush=True)
        a.evidence.parent.mkdir(parents=True,exist_ok=True)
        a.evidence.write_text(json.dumps(results,indent=2)+'\n')
        assert not bad,bad[:8]
        mission(game,0);game.call('draw_all');game.call('render_frame')
    finally:game.close(resume=True)

if __name__=='__main__':main()
