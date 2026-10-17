#!/usr/bin/env python3
"""Exercise real GS/OS campaign writes, reloads, best-score rules and retry."""
import argparse
import json
from pathlib import Path
from probe import DEFAULT_SOURCE
from runtime import Runtime

ROOT=Path(__file__).resolve().parents[2]


def campaign(game):
    path_length=int.from_bytes(game.mem('campaign_path',2),'little')
    path=game.mem('campaign_path',path_length+2)[2:].decode('ascii')
    assert path.endswith(':FORCE.STATE'),path
    count=len(game.manifest['catalogue'])
    game.set('miss_score',bytes([255])*count)
    game.set('miss_score',7)
    game.set('campaign_dirty',1)
    game.call('campaign_save')
    assert game.mem('campaign_error',2)==bytes(2),game.mem('campaign_error',2).hex()
    assert game.mem('campaign_dirty')==b'\0'
    game.set('miss_score',bytes([255])*count)
    game.call('campaign_load')
    assert game.mem('miss_score',count)==bytes([7]+[255]*(count-1))
    for n,v in [('mission_id',0),('score_snap',1),('snap_score',9),('script_outcome',1)]:game.set(n,v)
    game.call('campaign_commit')
    game.call('campaign_load')
    assert game.mem('miss_score')[0]==9
    for n,v in [('score_snap',1),('snap_score',4),('script_outcome',1)]:game.set(n,v)
    game.call('campaign_commit');game.call('campaign_load')
    assert game.mem('miss_score')[0]==9
    for n,v in [('score_snap',1),('snap_score',32),('script_outcome',2)]:game.set(n,v)
    game.call('campaign_commit');game.call('campaign_load')
    assert game.mem('miss_score')[0]==9
    # Force a genuine GS/OS create failure inside a nonexistent subdirectory,
    # keeping the mounted volume and original campaign path intact.
    original=game.mem('campaign_new_path',13)
    try:
        game.set('miss_score',11);game.set('campaign_dirty',1)
        game.set('campaign_new_path',b'\x0b\x00' + b'8:X:BAD.NEW')
        game.call('campaign_save')
        assert game.mem('campaign_error',2)!=bytes(2)
        assert game.mem('campaign_dirty')==b'\1'
        pending=game.mem('miss_score',count)
    finally:
        game.set('campaign_new_path',original)
    game.call('campaign_load')
    assert game.mem('miss_score')[0]==9,'Failed write replaced prior score'
    game.set('miss_score',pending);game.set('campaign_dirty',1)
    game.call('campaign_save');game.call('campaign_load')
    assert game.mem('miss_score')[0]==11 and game.mem('campaign_dirty')==b'\0'
    return dict(actual_gsos_save_reload=True,best_score_retained=True,loss_not_saved=True,
                create_failure_preserves_previous=True,pending_save_retry=True)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--socket',required=True)
    ap.add_argument('--symbols',type=Path,required=True)
    ap.add_argument('--gssquared-source',type=Path,default=DEFAULT_SOURCE)
    ap.add_argument('--evidence',type=Path,default=ROOT/'build/iigs/evidence/native/campaign.json')
    a=ap.parse_args()
    game=Runtime(a.socket,a.symbols,a.gssquared_source)
    try:
        game.locate().freeze()
        result=campaign(game)
        a.evidence.parent.mkdir(parents=True,exist_ok=True)
        a.evidence.write_text(json.dumps(result,indent=2)+'\n')
        print('Campaign passed:',a.evidence)
    finally:game.close(resume=True)


if __name__=='__main__':main()
