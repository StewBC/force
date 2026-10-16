#!/usr/bin/env python3
"""Launch an isolated windowed PAL/NTSC game and check C64 tactics/drawing.

Uses the normal -a/-p launch, Inspector, and a private disk folder. The
user's campaign and any existing emulator are never modified. Build first.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from c64_layout import ROOT
from c64_package import symbols

MACHINES = ROOT.parent/'machines'
sys.path.insert(0,str(MACHINES/'tools/c64'))
from c64_control_client import Ctl


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--port',type=int,default=16528)
    ap.add_argument('--standard',choices=('pal','ntsc'),default='pal')
    ap.add_argument('--build',type=Path,default=ROOT/'build')
    ap.add_argument('--movement-only',action='store_true')
    ap.add_argument('--mission',type=int,default=0,choices=range(6))
    a=ap.parse_args()
    with socket.socket() as sock:
        if sock.connect_ex(('127.0.0.1',a.port))==0:
            raise SystemExit(f'Port {a.port} is occupied; choose another --port')
    folder=Path(tempfile.mkdtemp(prefix='force-c64-tactics-'))
    disk=folder/'build/c64';disk.mkdir(parents=True)
    for path in (a.build/'c64').glob('*.seq'):shutil.copy2(path,disk/path.name)
    shutil.copy2(a.build/'c64/campaign.prg',disk/'campaign.prg')
    shutil.copy2(a.build/'force.prg',folder/'build/force.prg')
    s=symbols(a.build/'c64/game-image.sym');b=symbols(a.build/'force.sym')
    log=open(folder/'emulator.log','w')
    proc=subprocess.Popen([str(MACHINES/'build/c64m'),'-P' if a.standard=='pal' else '-N',
        '-a','-p','build/force.prg','--disk','8=./build/c64','--inspector',
        '--control-port',str(a.port),'--inifile='+str(MACHINES/'c64m.ini'),'--nosaveini'],
        cwd=folder,stdout=log,stderr=log)
    c=None
    try:
        for _ in range(100):
            try:c=Ctl(port=a.port,timeout=35);break
            except OSError:
                if proc.poll() is not None:raise RuntimeError('emulator exited: '+(folder/'emulator.log').read_text())
                time.sleep(.1)
        if c is None:raise RuntimeError('emulator control port unavailable')
        def cmd(t):
            r=c.cmd(t)
            if r[0]=='error':raise RuntimeError((t,r))
            return r
        def cpu():
            return {k:int(v,16) if k!='cycles' else int(v) for k,v in
                    re.findall(r'(pc|sp|cycles)=([0-9A-Fa-f]+)',cmd('get-cpu')[1])}
        def poke(addr,data):
            if isinstance(data,int):data=bytes([data])
            c.id+=1;rid=c.id
            c.s.sendall(f'{rid} set-memory ${addr:04x} {len(data)} ram\n'.encode()+data+b'\n')
            while True:
                n,r=c._parse_response_header(c._readline())
                if n==rid:
                    if r[0]=='error':raise RuntimeError(r)
                    return
        def mem(name,n=1):return c.mem(s[name],n,'ram')
        def setv(name,value):poke(s[name],value)
        def breaks(*addresses):
            cmd('break-clear-all')
            for addr in addresses:cmd(f'break-create exec ${addr:04x}')
        def wait_at(addr):
            cmd('wait-paused 30000')
            state=cpu()
            if state['pc']!=addr:raise AssertionError((hex(addr),state,mem('LOAD_STATUS').hex()))
        def reach(name):
            addr=s[name];breaks(addr,s['load_fail'],b['boot_fail'],s['bank_reset'])
            cmd('run');wait_at(addr)
        def press(key,name):
            addr=s[name];breaks(addr,s['load_fail'],b['boot_fail'],s['bank_reset'])
            cmd(f'key-down {key}');cmd('run');wait_at(addr);cmd(f'key-up {key}')
        cmd('pause');breaks(s['show_title::wait_ret'],b['boot_fail']);cmd('run');wait_at(s['show_title::wait_ret'])
        print('automatic RUN/title passed',flush=True)
        press('return','menu_loop')
        cmd('break-clear-all');cmd('run-cycles 300000');cmd('wait-paused 30000')
        setv('ui_extra',15);setv('ui_miss',a.mission)
        press('return','menu_launch')
        for name in ('container_load','unpack_resident','clear_bss','install_routes',
                     'mission_activate','irq_init','world_load','session_init','draw_all','build_occ','draw_field','draw_ui',
                     'remember_units','refresh_deck','place_cursor','loop'):
            if name not in s:continue
            reach(name)
            print('launch',name,flush=True)
        addr=s['loop'];original=c.mem(addr,10,'ram')
        timings={}
        def call(name):
            # An isolated callable bracket. No disk, input, or raster wait.
            target=s[name]
            poke(addr,bytes([0x08,0x78,0x20,target&255,target>>8,0x28,0xea,0x4c,addr&255,addr>>8]))
            breaks(addr+7,s['load_fail']);start=cpu()['cycles'];cmd('run');wait_at(addr+7)
            elapsed=cpu()['cycles']-start;timings.setdefault(name,[]).append(elapsed)
            breaks(addr);cmd('run');wait_at(addr)
            return elapsed
        if a.movement_only:
            setv('sc_op_count',0);setv('sc_watch_count',0)
            frames=[]
            def batch(n):
                target=s['world_tick'];scratch=0x1c00
                program=bytes([0x08,0x78,0xa9,n,0x8d,0,0x1c,
                    0x20,target&255,target>>8,0xce,0,0x1c,0xd0,0xf8,0x28,0xea,
                    0x4c,addr&255,addr>>8])
                poke(addr,program);breaks(addr+17,s['load_fail']);cmd('run');wait_at(addr+17)
                breaks(addr);cmd('run');wait_at(addr)
            for name,v in [('zA0',0),('zA1',2),('zA2',22),('zA3',9),('zA4',10)]:setv(name,v)
            call('section_issue');batch(128)
            print('defended',list(zip(mem('unit_x',7),mem('unit_y',7))),flush=True)
            for name,v in [('zA0',0),('zA1',1),('zA2',14),('zA3',8),('zA4',10)]:setv(name,v)
            call('section_issue')
            for tick in range(4):
                batch(128)
                xs=mem('unit_x',32);ys=mem('unit_y',32);counts=mem('unit_count',32);rs=mem('unit_region',32)
                positions=[(i,xs[i],ys[i],rs[i]) for i in range(32) if counts[i]]
                frames.append(positions)
                print('movement',128*(tick+1),positions,flush=True)
            (folder/'movement.json').write_text(json.dumps(frames,indent=2))
            assert len(frames[-1])==7 and all(rec[3]==1 for rec in frames[-1]), frames[-1]
            assert {(rec[1],rec[2]) for rec in frames[-1]} == {(14,8),(14,7),(14,9),(13,8),(15,8),(13,7),(15,9)}
            print('Movement passed; evidence:',folder/'movement.json',flush=True)
            return
        def reset():
            call('clear_bss')
            for name,value in [('map_w',20),('map_h',20),('play_w',20),('play_h',20),
                               ('win_w',20),('win_h',20),('room_count',1),('rom_room_count',1),
                               ('rom_room_w',20),('rom_room_h',20),('rom_room_x0',0),('rom_room_y0',0)]:setv(name,value)
            setv('rom_tiles',bytes([112])*400);setv('rom_paper',bytes([5])*400)
            setv('section_lead',bytes([255])*16);setv('rom_cover_count',0);setv('rom_scout_count',0)
            setv('section_order_verb',bytes([3])*16);setv('sc_watch_count',0);setv('sc_op_count',0)
            setv('grenade_rem',bytes(2));setv('deck_count',0);call('build_rows')
        def spawn(x,y,section,kind,glyph):
            for name,v in [('zA0',x),('zA1',y),('zA2',section),('zA3',kind),('zA4',1),('zT7',glyph)]:setv(name,v)
            call('unit_spawn')
        def fire(slot):
            call('pack_sides');setv('cb_i',slot);call('unit_shoot')
        if a.mission==2:
            assert 2 in mem('unit_kind',6) and 3 in mem('unit_kind',6)
            assert mem('section_strength',2)==bytes([4,1])
        press('f3','world_load');reach('loop')
        assert mem('in_restart')[0]==1
        reset();spawn(4,8,0,3,2);spawn(10,8,8,2,14)
        assert mem('unit_hp',2)==bytes([16,48]) and mem('weapon_ammo',2)==bytes([4,0])
        fire(0);assert mem('unit_hp',2)[1]==16 and mem('weapon_ammo')[0]==3
        fire(0);assert mem('unit_hp',2)[1]==16 and mem('unit_fire_wait')[0]==19
        setv('unit_fire_wait',0);fire(0);assert mem('unit_hp',2)[1]==0 and mem('weapon_ammo')[0]==2
        reset();spawn(10,10,0,2,6);spawn(14,10,8,0,10)
        fire(0);assert mem('unit_hp',2)[1]==16
        poke(s['unit_x']+1,6);poke(s['rom_tiles']+208,16)
        fire(0);assert mem('unit_hp',2)[1]==16
        poke(s['rom_tiles']+208,112);fire(0)
        assert mem('unit_hp',2)[1]==6 and mem('unit_fire_wait')[0]==3
        reset();spawn(5,10,0,0,2);spawn(9,10,8,2,14);fire(0)
        assert mem('unit_hp',2)[1]==47
        reset();spawn(5,10,0,3,2);spawn(9,10,8,0,10);fire(0)
        assert mem('unit_hp',2)[1]==6 and mem('weapon_ammo')[0]==4
        reset()
        for name,v in [('spawn_job_type',1),('spawn_job_letter',1),('spawn_job_room',128),
                       ('spawn_job_rem',3),('spawn_job_batch',3),('spawn_job_period',1),
                       ('sc_where_kind',1),('sc_where_a',5),('sc_where_b',5)]:setv(name,v)
        call('spawn_pulse')
        assert mem('spawn_job_rem')[0]==2 and mem('unit_section')[0]==1 and mem('unit_glyph')[0]==2
        call('spawn_pulse');assert mem('spawn_job_rem')[0]==2
        setv('unit_x',6);call('spawn_pulse');assert mem('spawn_job_rem')[0]==1
        # Screen address helper must preserve index registers indirectly through
        # the real full draw. Complete an unoccupied plank without invalidation.
        reset();setv('deck_count',1);setv('deck_x',8);setv('deck_y',8);setv('deck_cost',1)
        poke(s['rom_tiles']+168,80);call('draw_all');setv('drawn',1);setv('think_i',0)
        # deck_pour receives the index in A; a one-instruction prefix loads it.
        target=s['deck_pour'];poke(addr,bytes([0xa9,0,0x20,target&255,target>>8,0x4c,(addr+5)&255,(addr+5)>>8]))
        breaks(addr+5);cmd('run');wait_at(addr+5)
        assert mem('drawn')[0]==1 and mem('deck_dirty')[0]==1
        poke(addr+5,bytes([0x4c,addr&255,addr>>8]));breaks(addr);cmd('run');wait_at(addr)
        before=cpu()['cycles'];call('draw_all');bridge_cycles=cpu()['cycles']-before
        assert c.mem(0x400+8*40+8,1,'ram')==bytes([81]) and mem('deck_dirty')[0]==0
        poke(addr,original)
        result={'standard':a.standard,'auto_run_title_menu_and_mission':True,'rocket_damage_ammo_reload':True,
                'nest_arc_wall_armor':True,'rifle_fallback':True,'point_stream_backpressure':True,
                'incremental_bridge_redraw':True,'cycles':timings,'bridge_draw_bracket':bridge_cycles}
        (folder/'results.json').write_text(json.dumps(result,indent=2)+'\n')
        print('C64 tactics passed; evidence:',folder/'results.json',flush=True)
    except Exception:
        if c:
            try:
                c.cmd('pause');print('Failure CPU:',c.cmd('get-cpu'),'fixture:',folder,flush=True);(folder/'failure-ram.bin').write_bytes(c.mem(0,65536,'ram'))
            except Exception:pass
        raise
    finally:
        if c:c.s.close()
        proc.terminate()
        try:proc.wait(timeout=5)
        except subprocess.TimeoutExpired:proc.kill();proc.wait()
        log.close()


if __name__=='__main__':main()
