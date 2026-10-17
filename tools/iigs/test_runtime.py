#!/usr/bin/env python3
"""Exercise real IIgs missions, rendering, movement and weapons on a private disk."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
from probe import DEFAULT_SOURCE, decode_shr, png, read
from runtime import Runtime
from snapshot import snapshot, differences

ROOT = Path(__file__).resolve().parents[2]


def positions(game):
    counts = game.mem('unit_count', 32)
    xs, ys, rs = (game.mem(n, 32) for n in ('unit_x', 'unit_y', 'unit_region'))
    return [[i, xs[i], ys[i], rs[i]] for i in range(32) if counts[i]]


def framebuffer(game, path):
    # Reference implementation decodes software cells independently of 65816 code.
    screen = game.mem('SCREEN', 1000)
    colors = game.mem('COLORRAM', 1000)
    charset = game.mem('CHARSET', 2048)
    cx, cy, blink = (game.mem(n)[0] for n in ('cursor_x', 'cursor_y', 'frame_lo'))
    expected = bytearray(64000)
    for cell, char in enumerate(screen):
        x, y = cell % 40, cell // 40
        for row in range(8):
            bits = charset[char * 8 + row]
            if y < 20:
                line = []
                for shift in (6, 4, 2, 0):
                    ink = (2, 11, 14, colors[cell] & 7)[(bits >> shift) & 3]
                    line.extend((ink, ink))
            else:
                paper = 11 if y == 24 else 0
                line = [colors[cell] & 15 if bits & (128 >> col) else paper for col in range(8)]
            if x == cx and y == cy and y < 20:
                for col in range(8):
                    if blink & 8 or row in (0, 7) or col in (0, 7):
                        line[col] = 3
            start = (y * 8 + row) * 320 + x * 8
            expected[start:start+8] = bytes(line)
    raw = read(game.client, 0xe12000, 32000)
    actual = bytes(nibble for value in raw for nibble in (value >> 4, value & 15))
    png(path, decode_shr(raw, read(game.client, 0xe19d00, 200), read(game.client, 0xe19e00, 512)))
    mismatch = [i for i, (a, b) in enumerate(zip(expected, actual)) if a != b]
    if mismatch:
        sample = [(i % 320, i // 320, expected[i], actual[i]) for i in mismatch[:12]]
        raise AssertionError(f'{len(mismatch)} framebuffer pixels differ (x,y,expected,actual): {sample}')


def mission(game, index):
    game.set('mission_id', index)
    game.call('mission_load')


def movement(game, evidence, baseline=None, state_baseline=None):
    game.set('bss_start',bytes(game.symbols['bss_end']-game.symbols['bss_start']))
    mission(game, 0)
    game.set('sc_op_count', 0)
    game.set('sc_watch_count', 0)
    # This separately initialized DATA byte starts at zero on the fresh C64 boot.
    game.set('spawn_job_type',0)
    # Farm has no init spawns; restoring removes any prior running-game wave.
    game.call('world_load')
    game.call('session_init')
    for name, value in [('zA0', 0), ('zA1', 2), ('zA2', 22), ('zA3', 9), ('zA4', 10)]:
        game.set(name, value)
    game.call('section_issue')
    game.call('world_tick', count=128)
    defended = positions(game)
    assert len(defended) == 7, defended
    for name, value in [('zA0', 0), ('zA1', 1), ('zA2', 14), ('zA3', 8), ('zA4', 10)]:
        game.set(name, value)
    game.call('section_issue')
    frames, snapshots = [], []
    for _ in range(4):
        game.call('world_tick', count=128)
        frames.append(positions(game))
        snapshots.append(snapshot(game.mem))
    expected = [[i, x, y, 1] for i, (x, y) in enumerate(((14,8), (14,7), (14,9), (13,8), (15,8), (13,7), (15,9))) ]
    assert frames[-1] == expected, frames[-1]
    if baseline:
        assert frames == json.loads(Path(baseline).read_text()), 'Executed C64 movement baseline differs'
    (evidence / 'movement.json').write_text(json.dumps(dict(defended=defended, frames=frames, snapshots=snapshots), indent=2)+'\n')
    if state_baseline:
        delta=differences(json.loads(Path(state_baseline).read_text()),snapshots)
        assert not delta,delta[:20]


def tactics(game):
    shot_snapshots=[]
    def reset():
        game.set('spawn_job_type',0)
        game.set('bss_start', bytes(game.symbols['bss_end'] - game.symbols['bss_start']))
        for name, value in [('map_w',20),('map_h',20),('play_w',20),('play_h',20),
                            ('win_w',20),('win_h',20),('room_count',1),('rom_room_count',1),
                            ('rom_room_w',20),('rom_room_h',20),('rom_room_x0',0),('rom_room_y0',0)]:
            game.set(name, value)
        game.set('rom_tiles', bytes([112])*400)
        game.set('rom_paper', bytes([5])*400)
        game.set('section_lead', bytes([255])*16)
        for name in ('rom_cover_count', 'rom_scout_count', 'sc_watch_count', 'sc_op_count', 'deck_count'):
            game.set(name, 0)
        game.set('section_order_verb', bytes([3])*16)
        game.set('grenade_rem', bytes(2))
        game.call('build_rows')
    def spawn(x, y, section, kind, glyph):
        for name, value in [('zA0',x),('zA1',y),('zA2',section),('zA3',kind),('zA4',1),('zT7',glyph)]:
            game.set(name,value)
        game.call('unit_spawn')
    def fire(slot):
        game.call('pack_sides'); game.set('cb_i',slot); game.call('unit_shoot')
        shot_snapshots.append(snapshot(game.mem))
    reset(); spawn(4,8,0,3,2); spawn(10,8,8,2,14)
    assert game.mem('unit_hp',2)==bytes([16,48])
    fire(0)
    assert game.mem('unit_hp',2)[1]==16 and game.mem('weapon_ammo')[0]==3
    fire(0)
    assert game.mem('unit_hp',2)[1]==16 and game.mem('unit_fire_wait')[0]==19
    game.set('unit_fire_wait',0); fire(0)
    assert game.mem('unit_hp',2)[1]==0 and game.mem('weapon_ammo')[0]==2
    reset(); spawn(10,10,0,2,6); spawn(14,10,8,0,10); fire(0)
    assert game.mem('unit_hp',2)[1]==16
    game.set('unit_x',bytes([10,6])); game.client.write_mem(0,game.address('rom_tiles')+208,b'\x10'); fire(0)
    assert game.mem('unit_hp',2)[1]==16
    game.client.write_mem(0,game.address('rom_tiles')+208,b'\x70'); fire(0)
    assert game.mem('unit_hp',2)[1]==6 and game.mem('unit_fire_wait')[0]==3
    reset(); spawn(5,10,0,0,2); spawn(9,10,8,2,14); fire(0)
    assert game.mem('unit_hp',2)[1]==47
    reset(); spawn(5,10,0,3,2); spawn(9,10,8,0,10); fire(0)
    assert game.mem('unit_hp',2)[1]==6 and game.mem('weapon_ammo')[0]==4
    reset()
    for name,value in [('spawn_job_type',1),('spawn_job_letter',1),('spawn_job_room',128),
                       ('spawn_job_rem',3),('spawn_job_batch',3),('spawn_job_period',1),
                       ('sc_where_kind',1),('sc_where_a',5),('sc_where_b',5)]:game.set(name,value)
    game.call('spawn_pulse')
    assert game.mem('spawn_job_rem')[0]==2 and game.mem('unit_section')[0]==1 and game.mem('unit_glyph')[0]==2
    game.call('spawn_pulse');assert game.mem('spawn_job_rem')[0]==2
    game.set('unit_x',6);game.call('spawn_pulse');assert game.mem('spawn_job_rem')[0]==1
    reset()
    for name,value in [('deck_count',1),('deck_x',8),('deck_y',8),('deck_cost',1)]:game.set(name,value)
    game.client.write_mem(0,game.address('rom_tiles')+168,bytes([80]))
    game.call('draw_all');game.set('drawn',1);game.set('think_i',0)
    game.call('deck_pour',a=0)
    assert game.mem('drawn')[0]==1 and game.mem('deck_dirty')[0]==1
    game.call('draw_all')
    assert game.mem('SCREEN',1000)[8*40+8]==81 and game.mem('deck_dirty')[0]==0
    return dict(rocket_damage_ammo_reload=True,nest_arc_wall_armor=True,rifle_fallback=True,
                point_stream_backpressure=True,incremental_bridge_redraw=True,shot_snapshots=shot_snapshots)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--socket',required=True)
    ap.add_argument('--symbols',type=Path,default=ROOT/'build/iigs/symbols.json')
    ap.add_argument('--gssquared-source',type=Path,default=DEFAULT_SOURCE)
    ap.add_argument('--evidence',type=Path,default=ROOT/'build/iigs/evidence/native')
    ap.add_argument('--c64-movement',type=Path)
    ap.add_argument('--c64-state',type=Path)
    ap.add_argument('--c64-weapons',type=Path)
    ap.add_argument('--mode',choices=('catalogue','movement','tactics','all'),default='all')
    args=ap.parse_args();args.evidence.mkdir(parents=True,exist_ok=True)
    game=Runtime(args.socket,args.symbols,args.gssquared_source)
    try:
        game.locate().freeze()
        if args.mode in ('catalogue','all'):
            for row in game.manifest['catalogue']:
                mission(game,row['id'])
                game.call('draw_all');game.call('render_frame')
                assert (game.mem('map_w')[0],game.mem('map_h')[0])==(row['width'],row['height'])
                framebuffer(game,args.evidence/(row['stem']+'.png'))
                print('Mission/framebuffer passed:',row['stem'],flush=True)
        if args.mode in ('movement','all'):
            movement(game,args.evidence,args.c64_movement,args.c64_state)
            print('Movement passed',flush=True)
        if args.mode in ('tactics','all'):
            result=tactics(game)
            if args.c64_weapons:
                delta=differences(json.loads(args.c64_weapons.read_text()),result['shot_snapshots'])
                assert not delta,delta[:20]
            (args.evidence/'tactics.json').write_text(json.dumps(result,indent=2)+'\n')
            print('Tactics passed',flush=True)
        mission(game,0);game.call('draw_all');game.call('render_frame')
    finally:
        game.close(resume=True)


if __name__=='__main__':main()
