#!/usr/bin/env python3
"""Real keyboard title/menu flow and authored director transitions on a private IIgs."""
import argparse
import json
from pathlib import Path
import time
from probe import DEFAULT_SOURCE,read,decode_shr,png
from runtime import Runtime
from test_runtime import mission
from snapshot import snapshot,differences


def frame(g):
    from gs2debug import BP_KIND_EXEC
    bp=g.client.bp_set(kind=BP_KIND_EXEC,address=g.address('main_loop'))
    try:
        g.client.continue_();event=g.client.wait_stopped(timeout=20)
        assert event.bp_id==bp
    finally:g.client.bp_clear(bp)


def tap(g,code,poll,mod=0):
    g.client.key_down(code,mod);time.sleep(.05);g.call(poll)
    g.client.key_up(code,mod);time.sleep(.05)


def flow(g,evidence):
    g.call('menu_open');g.call('show_title')
    png(evidence/'title.png',decode_shr(read(g.client,0xe12000,32000),read(g.client,0xe19d00,200),read(g.client,0xe19e00,512)))
    tap(g,40,'title_poll')
    assert g.mem('title_mode')==b'\0' and g.mem('menu_mode')==b'\1'
    tap(g,40,'menu_tick')
    assert g.mem('menu_mode')==b'\0'
    # Game is paused at its logic boundary by the debug flag, so poll manually.
    g.client.key_down(79);time.sleep(.05);g.call('input_poll')
    assert g.mem('in_dx')==b'\1'
    g.client.key_up(79);g.client.key_down(225);time.sleep(.05)
    g.call('input_poll',count=4)
    assert g.mem('in_dx')==b'\0','Arrow continued after release while Shift held'
    g.client.key_up(225)
    g.call('input_poll')
    tap(g,16,'input_poll')
    assert g.mem('in_kind')[0]==g.symbols['CMD_LETTER'] and g.mem('in_value')==b'\x0c'
    g.call('cmd_feed');assert g.mem('cmd_slot')[0]==g.symbols['SLOT_WHO']
    g.call('cmd_init')
    return dict(actual_keyboard_title_menu_mission=True,arrow_release_with_shift=True)


def director(g):
    state_snapshots=[]
    def step():
        g.call("script_step");state_snapshots.append(snapshot(g.mem))
    mission(g,0)
    # Run the authored patrol and cover waits with controlled casualty counts.
    step()
    assert g.mem('script_waiting')==b'\1'
    g.set('spawn_job_rem',0)
    g.client.write_mem(0,g.address('section_strength')+8,b'\x04')
    step()
    assert g.mem('script_waiting')==b'\1'
    g.client.write_mem(0,g.address('section_strength')+8,b'\0')
    step()
    assert g.mem('spawn_job_rem')==b'\x06'
    assert g.mem('spawn_job_batch')==b'\x02' and g.mem('spawn_job_period')==b'\x07'
    g.set('spawn_job_rem',0);step()
    g.client.write_mem(0,g.address('section_strength')+9,b'\x04');step()
    g.client.write_mem(0,g.address('section_strength')+9,b'\x02');step()
    g.client.write_mem(0,g.address('section_strength')+9,b'\0');step()
    assert g.mem('spawn_job_rem')==b'\x06'
    assert g.mem('spawn_job_batch')==b'\x03' and g.mem('spawn_job_period')==b'\x0e'
    g.set('spawn_job_rem',0)
    g.client.write_mem(0,g.address('section_strength')+10,b'\0')
    room_pred=g.mem('script_wait_pred1')[0]
    target_room=g.mem('sc_pred_a',room_pred+1)[room_pred]
    g.set('unit_region',target_room);step()
    assert g.mem('script_outcome')[0]==g.symbols['OUT_WIN']
    g.call('game_tick')
    assert g.mem('score_snap')==b'\1' and g.mem('snap_score')==b'\x07'
    mission(g,0);g.set('section_strength',bytes(16));step()
    assert g.mem('script_outcome')[0]==g.symbols['OUT_LOSE']
    return dict(authored_farm_director_controlled_predicates=True,batched_wave_templates=True,
                farm_win_score_snapshot=True,player_wipe_watch_loss=True,state_snapshots=state_snapshots)


def outcome_return(g):
    tap(g,40,'input_poll')
    assert g.mem('in_leave')==b'\1' and g.mem('in_kind')==b'\0'
    g.call('menu_open');assert g.mem('menu_mode')==b'\1'
    g.set('menu_mode',0);g.set('script_outcome',g.symbols['OUT_WIN'])
    g.set('score_snap',1);g.set('snap_score',7)
    g.set('debug_input',bytes([g.symbols['CMD_RETURN'],0,0,0]));g.call('input_poll')
    assert g.mem('in_leave')==b'\1' and g.mem('in_kind')==b'\0'
    g.call('menu_open');assert g.mem('menu_mode')==b'\1'
    assert g.mem('miss_score')[0]!=255
    return dict(loss_keyboard_return_to_menu=True,win_return_commits_campaign=True)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--socket',required=True)
    p.add_argument('--symbols',required=True,type=Path);p.add_argument('--evidence',required=True,type=Path)
    p.add_argument('--c64-director',type=Path)
    a=p.parse_args();a.evidence.mkdir(parents=True,exist_ok=True)
    g=Runtime(a.socket,a.symbols,DEFAULT_SOURCE)
    try:
        g.locate().freeze();result=flow(g,a.evidence);result.update(director(g));result.update(outcome_return(g))
        if a.c64_director:
            delta=differences(json.loads(a.c64_director.read_text()),result['state_snapshots'])
            assert not delta,delta[:20]
        (a.evidence/'flow.json').write_text(json.dumps(result,indent=2)+'\n');print('Native flow passed',flush=True)
        mission(g,0);g.call('draw_all');g.call('render_frame')
    finally:g.close(resume=True)

if __name__=='__main__':main()
