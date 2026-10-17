#!/usr/bin/env python3
"""Exercise the IIgs joystick menu option with real keyboard events."""
import argparse
import json
from pathlib import Path
import time
from probe import DEFAULT_SOURCE,decode_shr,png,read
from runtime import Runtime
from test_flow import tap
from test_runtime import mission


def menu_text(g):
    return ''.join(chr((v-96)&255) for v in g.mem('SCREEN',1000)[800:840])


def ctrl_j(g):
    g.client.key_down(224,0x40);time.sleep(.05)
    try:tap(g,13,'menu_tick',mod=0x40)
    finally:g.client.key_up(224);time.sleep(.05)


def check(g,evidence):
    from gs2debug import BP_KIND_EXEC
    assert g.mem('joystick_enabled')==b'\0','Must use a fresh boot'
    g.call('menu_open');assert 'JOYSTICK: OFF' in menu_text(g)
    # Even stale/hostile paddle values cannot enter the hardware reader while off.
    g.set('paddle_x',0);g.set('paddle_y',0);g.set('paddle_last_button',128)
    bp=g.client.bp_set(kind=BP_KIND_EXEC,address=g.address('joystick_read'))
    try:
        g.call('input_poll',count=32)
        assert g.mem('in_dx',2)==bytes(2) and g.mem('in_kind')==b'\0'
        assert g.mem('paddle_last_button')==b'\x80'
        tap(g,79,'input_poll');assert g.mem('in_dx')==b'\1'
    finally:g.client.bp_clear(bp)
    # Down is the same character as Ctrl-J, but must remain menu navigation.
    g.set('ui_extra',1);g.set('ui_miss',0);tap(g,81,'menu_tick')
    assert g.mem('ui_miss')==b'\1' and g.mem('joystick_enabled')==b'\0'
    ctrl_j(g)
    assert g.mem('joystick_enabled')==b'\1' and g.mem('ui_miss')==b'\1'
    assert 'JOYSTICK: ON ' in menu_text(g)
    # Enabled input must actually enter the reader; use its body as an exec probe.
    bp=g.client.bp_set(kind=BP_KIND_EXEC,address=g.address('joystick_read'))
    try:
        try:g.call('input_joystick')
        except AssertionError as exc:
            assert str(exc)==f"input_joystick stopped at unexpected address {g.address('joystick_read'):06x}",str(exc)
        else:raise AssertionError('Enabled joystick did not reach hardware reader')
    finally:g.client.bp_clear(bp)
    mission(g,1);assert g.mem('joystick_enabled')==b'\1'
    mission(g,1);assert g.mem('joystick_enabled')==b'\1'
    g.call('menu_open');assert 'JOYSTICK: ON ' in menu_text(g)
    ctrl_j(g);assert g.mem('joystick_enabled')==b'\0'
    assert 'JOYSTICK: OFF' in menu_text(g)
    g.call('render_frame')
    png(evidence.parent/'joystick-menu.png',decode_shr(read(g.client,0xe12000,32000),read(g.client,0xe19d00,200),read(g.client,0xe19e00,512)))
    return dict(default_off=True,off_skips_hardware_and_button=True,keyboard_arrows_when_off=True,
                down_arrow_still_navigates=True,ctrl_j_toggles_visible_status=True,
                enabled_reader_reachable=True,retained_across_missions_and_restarts=True)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--socket',required=True)
    p.add_argument('--symbols',required=True,type=Path);p.add_argument('--evidence',required=True,type=Path)
    a=p.parse_args();g=Runtime(a.socket,a.symbols,DEFAULT_SOURCE)
    try:
        g.locate().freeze();a.evidence.parent.mkdir(parents=True,exist_ok=True)
        result=check(g,a.evidence);a.evidence.write_text(json.dumps(result,indent=2)+'\n')
        print('Joystick option passed:',a.evidence,flush=True)
    finally:g.close(resume=True)

if __name__=='__main__':main()
