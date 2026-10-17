#!/usr/bin/env python3
"""Executed native input, scrolling, restart and representative timing checks."""
import argparse
import json
import tempfile
import assets
from pathlib import Path
from probe import DEFAULT_SOURCE, registers
from runtime import Runtime
from test_runtime import mission,framebuffer


def interaction(g):
    results={}
    for row in g.manifest['catalogue']:
        mission(g,row['id'])
        for axis,window,cursor,play,size,delta in (
            ('x','win_x','cursor_x','play_x','play_w','in_dx'),
            ('y','win_y','cursor_y','play_y','play_h','in_dy')):
            other='in_dy' if delta=='in_dx' else 'in_dx'
            g.set(other,0);g.set(delta,1);g.call('move_cursor',count=255)
            span=g.mem('win_w' if axis=='x' else 'win_h')[0]
            assert g.mem(window)[0]==g.mem(play)[0]+max(0,g.mem(size)[0]-span)
            assert g.mem(cursor)[0]==span-1
            g.set(delta,255);g.call('move_cursor',count=255)
            assert g.mem(window)[0]==g.mem(play)[0] and g.mem(cursor)[0]==0
        results[row['stem']]='four_bounds_and_scroll_passed'
    mission(g,0)
    # Exercise the native input mailbox and the actual four-slot command parser.
    def token(name,value=0,dx=0,dy=0):
        g.set('debug_input',bytes([g.symbols[name],value,dx,dy]))
        g.call('input_poll');g.call('cmd_feed')
        assert g.mem('debug_input',4)==bytes(4)
    token('CMD_LETTER',ord('M')-65)
    assert g.mem('cmd_slot')[0]==g.symbols['SLOT_WHO']
    token('CMD_LETTER',0)
    assert g.mem('cmd_slot')[0]==g.symbols['SLOT_WHERE_X']
    token('CMD_DIGIT',1);token('CMD_DIGIT',4);token('CMD_COMMA')
    token('CMD_DIGIT',8);token('CMD_RETURN')
    assert g.mem('cmd_slot')[0]==g.symbols['SLOT_SHOW']
    assert g.mem('section_order_verb')[0]==g.symbols['VERB_MOVE']
    assert g.mem('section_order_x')[0]==14 and g.mem('section_order_y')[0]==8
    token('CMD_ESC');assert g.mem('cmd_slot')[0]==g.symbols['SLOT_IDLE']
    g.call('input_poll',count=32)
    assert g.mem('in_dx')==b'\0' and g.mem('in_dy')==b'\0',('idle drift',g.mem('paddle_x'),g.mem('paddle_y'))
    g.set('unit_hp',1);mission(g,0)
    assert g.mem('cmd_slot')[0]==g.symbols['SLOT_IDLE'] and g.mem('frame_lo')==b'\0'
    return dict(mission_bounds=results,input_mailbox_command_commit=True,escape_cancels=True,
                idle_paddles_no_drift=True,restart_resets_session=True)


def routes(g):
    result={}
    with tempfile.TemporaryDirectory(prefix='force-iigs-routecheck-') as folder:
        for row in g.manifest['catalogue']:
            data=assets.gen_c64._compute(row['stem'],out_dir=Path(folder))
            mission(g,row['id'])
            for state,expected in enumerate(data['route_variants']):
                g.call('activate_routes',a=state)
                actual=g.mem('portal_from',304)+g.mem('door_n',514)
                assert actual==bytes(expected),(row['stem'],state)
            g.call('activate_routes',a=0)
            result[row['stem']]=len(data['route_variants'])
    return result


def exhaustive_tiles(g,evidence):
    mission(g,0);g.set('cursor_x',255);g.set('cursor_y',255)
    for page,start in enumerate((0,800)):
        values=[min(1023,start+i) for i in range(800)]
        g.set('SCREEN',bytes(v%128 for v in values))
        g.set('COLORRAM',bytes(v//128 for v in values))
        g.set('cached_glyph',bytes([255])*1024);g.call('render_frame')
        framebuffer(g,evidence.parent/f'tile-papers-{page}.png')
    return 1024


def profile(g):
    result={}
    for row in g.manifest['catalogue']:
        mission(g,row['id'])
        def timed(name,count=1):
            before=registers(g.client.get_regs())['cycle']
            after=g.call(name,count=count)
            return (after['cycle']-before)/count
        # Counts are the debugger's raw cycle domain; record without assuming MHz.
        g.set('cached_glyph',bytes([255])*1024)
        full=timed('render_frame')
        steady=timed('render_frame',count=8)
        world=timed('world_tick',count=32)
        draw=timed('draw_all',count=8)
        poll=timed('input_poll',count=8)
        result[row['stem']]=dict(full_render_counter=full,steady_render_counter=steady,world_tick_counter=world,draw_all_counter=draw,input_poll_counter=poll,
                                 estimated_warm_total_cycles=steady+world+draw+poll,
                                 target_cycles_per_20hz_tick=143052)
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--socket',required=True);p.add_argument('--symbols',required=True,type=Path)
    p.add_argument('--evidence',required=True,type=Path)
    a=p.parse_args();g=Runtime(a.socket,a.symbols,DEFAULT_SOURCE)
    try:
        g.locate().freeze();result=interaction(g);result['route_images']=routes(g);result['native_glyph_paper_cases']=exhaustive_tiles(g,a.evidence);result['raw_timing']=profile(g)
        a.evidence.parent.mkdir(parents=True,exist_ok=True);a.evidence.write_text(json.dumps(result,indent=2)+'\n')
        print('Interaction/timing passed:',a.evidence)
        mission(g,0);g.call('draw_all');g.call('render_frame')
    finally:g.close(resume=True)

if __name__=='__main__':main()
