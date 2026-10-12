#!/usr/bin/env python3
"""Real first-frame, keyboard/stick, F3, routing and outcome/menu probes."""
import argparse
import contextlib
import io
import json
import re
import shutil
import sys
from c64_layout import ROOT
from c64_package import symbols
sys.path.insert(0,str(ROOT.parent/'machines/tools/c64'))
from c64_control_client import Ctl

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--port',type=int,default=16511);ap.add_argument('--label',default='pal');a=ap.parse_args();c=Ctl(port=a.port,timeout=65);s=symbols(ROOT/'build/c64/game-image.sym');b=symbols(ROOT/'build/force.sym');folder=ROOT/'build/c64'/f'{a.label}-play-fixture';folder.mkdir(exist_ok=True)
    for p in (ROOT/'build/c64').glob('*.seq'):shutil.copy2(p,folder/p.name)
    shutil.copy2(ROOT/'build/c64/campaign.prg',folder/'campaign.prg');catalog=(folder/'campaign.prg').read_bytes()
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
    def reach(addr):
        breaks(addr,s['load_fail'],b['boot_fail']);cmd('run');cmd('wait-paused 60000');assert cpu()['pc']==addr,cpu()
    def press_to(key,addr,forbid_disk=False,extra=()):
        stops=[addr,s['read_file'] if forbid_disk else s['load_fail'],*extra]
        breaks(*stops);cmd(f'key-down {key}');cmd('run');cmd('wait-paused 60000');cmd(f'key-up {key}');assert cpu()['pc']==addr,cpu()
    cmd('pause');cmd(f'mount-d64 8 {folder}');breaks(s['show_title::wait_ret'],b['boot_fail']);cmd(f'load-prg {ROOT}/build/force.prg');cmd('paste-events RUN\\[RT]');cmd('run');cmd('wait-paused 60000');assert cpu()['pc']==s['show_title::wait_ret']
    press_to('return',s['menu_loop']);cmd('break-clear-all');cmd('run-cycles 500000')
    poke(s['ui_extra'],b'\1');poke(s['ui_miss'],b'\1');press_to('return',s['loop'])
    assert c.mem(0xE600,4,'ram')==b'FCTR' and c.mem(0xA000,4,'ram')!=b'FCTR'
    def cue():return bytes((ch-96)&255 for ch in c.mem(0x400+960,40,'ram'))
    assert b'> Build a bridge' in cue(),cue()
    assert c.mem(0xd418,1)[0]&15==0 and c.mem(s['music_on'],1,'ram')==b'\0'
    assert c.mem(s['active_mission'],1,'ram')==b'\0'
    before=c.mem(s['cursor_x'],1,'ram')[0];cmd('break-clear-all');cmd('key-down d');cmd('run-cycles 500000');cmd('key-up d');after=c.mem(s['cursor_x'],1,'ram')[0];assert after>before,(before,after)
    before=after;cmd('joystick 2 8');cmd('run-cycles 500000');cmd('joystick 2 0');after=c.mem(s['cursor_x'],1,'ram')[0];assert after>before,(before,after)
    reach(s['loop'])
    import gen_c64
    with contextlib.redirect_stdout(io.StringIO()):reference=gen_c64._compute('cross')
    program=reference['route_program'];variants=reference['route_variants']
    addr=s['loop'];original=c.mem(addr,12,'ram')
    def route(state):
        routine=s['activate_routes'];end=addr+8
        poke(addr,bytes([0x08,0x78,0xa9,state,0x20,routine&255,routine>>8,0x28,0xea,0xea,0xea,0xea]));breaks(end)
        cmd('run');cmd('wait-paused 10000');assert cpu()['pc']==end
        actual=c.mem(s['portal_from'],304,'ram')+c.mem(s['door_n'],514,'ram');assert actual==variants[state]
        poke(end,bytes([0x4c,addr&255,addr>>8]));breaks(addr);cmd('run');cmd('wait-paused 10000');poke(addr,original)
    for mask in range(64):
        state=0
        for i in range(6):
            if mask>>i&1:state|=program[i]
        route(state)
    for source in range(4):
        for target in range(4):route(source);route(target)
    workspace=c.mem(0x900,89,'ram');press_to('f3',s['world_load'],True,extra=(s['clear_bss'],));assert c.mem(s['in_restart'],1,'ram')==b'\1';reach(s['loop']);assert c.mem(0x900,89,'ram')==workspace and b'Build a bridge' in cue()
    assert c.mem(s['portal_from'],304,'ram')+c.mem(s['door_n'],514,'ram')==reference['routes']
    # Return on a loss does not write. Same container (cross, then farm) does not read.
    poke(s['script_outcome'],b'\2');press_to('return',s['menu_loop']);assert (folder/'campaign.prg').read_bytes()==catalog
    cmd('break-clear-all');cmd('run-cycles 500000');poke(s['ui_extra'],b'\1');poke(s['ui_miss'],b'\1');press_to('return',s['loop'],True);assert b'Build a bridge' in cue()
    cmd('break-clear-all');cmd('run-cycles 500000');poke(s['ui_miss'],b'\0');press_to('return',s['loop'],True)
    # Base is the next container. The read lands in the transfer window.
    cmd('break-clear-all');cmd('run-cycles 500000');poke(s['ui_extra'],b'\3');poke(s['ui_miss'],b'\3');press_to('return',s['read_file'])
    assert int.from_bytes(c.mem(s['zDst'],2,'ram'),'little')==s['TRANSFER_HOME']
    reach(s['loop']);assert c.mem(0xE600,4,'ram')==b'FCTR' and c.mem(0xA000,4,'ram')!=b'FCTR'
    # A win commits a survivor score and returns to the menu. This fixture is
    # mounted read-only, so the attempted write must preserve the file.
    cmd('break-clear-all');cmd('run-cycles 500000')
    poke(s['script_outcome'],b'\1');poke(s['score_snap'],b'\1');poke(s['snap_score'],b'\7');press_to('return',s['menu_loop']);assert c.mem(s['miss_score']+3,1,'ram')==b'\7'
    assert c.mem(s['ui_save'],1,'ram')==b'\1' and (folder/'campaign.prg').read_bytes()==catalog
    report={'first_visible_frame_cross_cue':True,'objective_pointer_workspace':hex(int.from_bytes(c.mem(s['objective_ptr'],2,'ram'),'little')),'keyboard_cursor':True,'joystick_cursor':True,'all_64_physical_routing_masks':True,'all_16_routing_transitions':True,'F3_no_disk_workspace_and_bridge_reset':True,'loss_menu_no_write':True,'same_map_relaunch_no_disk':True,'win_menu_score_and_refused_write':True,'music_faded_before_game':True}
    (ROOT/f'build/c64/banked-evidence/{a.label}-play-flow.json').write_text(json.dumps(report,indent=2)+'\n');print(report)

if __name__=='__main__':main()
