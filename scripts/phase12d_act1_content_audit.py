#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CAMPAIGN=ROOT/'content/campaign'
REGISTRY=ROOT/'content/registry.json'

def canon(v): return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False)
def fail(m): raise SystemExit(f'PHASE12D ACT1 FAIL: {m}')

def main():
    if not REGISTRY.exists(): fail('production registry missing')
    reg=json.loads(REGISTRY.read_text())
    payload=dict(reg); declared=payload.pop('registry_hash','')
    if hashlib.sha256(canon(payload).encode()).hexdigest()!=declared: fail('registry_hash mismatch')
    ids=[f'D{i:02d}' for i in range(1,9)]
    entries=reg.get('campaign',[])
    if [e.get('dossier_id') for e in entries[:8]]!=ids: fail('registry campaign must retain D01-D08 as the exact Act-I prefix')
    prior=set(); taught=set()
    expected={
      'D01':['road'],'D02':['road'],'D03':['bridge'],'D04':['road','bridge'],
      'D05':['border'],'D06':['border'],'D07':['restricted_zone'],'D08':['road','border','restricted_zone']}
    for did in ids:
        path=CAMPAIGN/f'{did}.json'
        if not path.exists(): fail(f'{did} missing')
        d=json.loads(path.read_text())
        body=dict(d); content_hash=body.pop('content_hash','')
        if hashlib.sha256(canon(body).encode()).hexdigest()!=content_hash: fail(f'{did} content_hash mismatch')
        if d.get('editable_primitive_permissions')!=expected[did]: fail(f'{did} teaching permissions changed')
        if d.get('act_index')!=1 or len(d.get('map_layers',[]))!=1: fail(f'{did} Act-I placement invalid')
        if len(d.get('agents',[]))>3 or d.get('reaction_beats_after_edit',99)>2 or d.get('stability_required_cycles',99)>1: fail(f'{did} Act-I ceiling exceeded')
        for p in d.get('prerequisite_dossier_ids',[]):
            if p not in prior: fail(f'{did} prerequisite not earlier: {p}')
        for tag in d.get('required_tutorial_tags',[]):
            if tag not in taught: fail(f'{did} requires untaught tag: {tag}')
        sol=d.get('validation_metadata',{}).get('known_solution_envelope',{})
        if not sol.get('solution_commands'): fail(f'{did} solution command regression missing')
        prior.add(did); taught.update(d.get('tutorial_tags',[]))
    d08=json.loads((CAMPAIGN/'D08.json').read_text())
    if 'bridge' in d08.get('editable_primitive_permissions',[]): fail('D08 bridge must be authored/immutable to preserve Act-I <=3 editable ceiling')
    if 'D08_B_EXISTING' not in d08['map_layers'][0].get('initial_primitives',{}).get('active_bridge_ids',[]): fail('D08 immutable bridge system missing')
    if d08.get('validation_metadata',{}).get('baseline_requires_mastery',True): fail('D08 baseline must not be mastery gated')
    service=(ROOT/'src/application/content_registry.gd').read_text()
    test=(ROOT/'tests/test_act1_content_runner.gd').read_text()
    runtime=(ROOT/'scripts/run_phase12a_runtime.sh').read_text()
    for marker in ['available_campaign_ids','content_progression_tutorial_tag_not_previously_taught','known_solution_candidate_family_mismatch','Baseline progression never consumes mastery/remix state']:
        if marker not in service: fail(f'content registry service missing marker: {marker}')
    for marker in ['Fresh profile must expose D01 only','D08 synthesis must include the bridge system as authored immutable state','nothing mastery-gated']:
        if marker not in test: fail(f'Act-I headless test missing marker: {marker}')
    if 'phase12d-act1-content-contract' not in runtime or 'test_act1_content_runner.gd' not in runtime: fail('runtime wrapper not wired for 12D Act-I')
    print('Phase 12D Act-I content audit: PASS (D01-D08 prefix/progression/hashes/teaching order)')
if __name__=='__main__': main()
