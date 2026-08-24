#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
CAMPAIGN=ROOT/'content/campaign'
REGISTRY=ROOT/'content/registry.json'
TRANSFORMS={
    'D13':'permission_asymmetry',
    'D14':'cross_network_dependency',
    'D15':'topology_restructuring',
    'D16':'temporal_stability_dependency',
}

def canon(v): return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False)
def fail(m): raise SystemExit(f'PHASE12D ACT2 FAIL: {m}')
def load(did):
    p=CAMPAIGN/f'{did}.json'
    if not p.exists(): fail(f'{did} missing')
    d=json.loads(p.read_text())
    body=dict(d); declared=body.pop('content_hash','')
    if hashlib.sha256(canon(body).encode()).hexdigest()!=declared: fail(f'{did} content_hash mismatch')
    return d

def families(d):
    return {r.get('family_id') for k in ('objectives','protected_invariants') for r in d.get(k,[])}

def main():
    reg=json.loads(REGISTRY.read_text())
    payload=dict(reg); declared=payload.pop('registry_hash','')
    if hashlib.sha256(canon(payload).encode()).hexdigest()!=declared: fail('registry_hash mismatch')
    prefix=[f'D{i:02d}' for i in range(1,17)]
    if [e.get('dossier_id') for e in reg.get('campaign',[])[:16]]!=prefix: fail('registry must retain exact D01-D16 production prefix')

    all_content={did:load(did) for did in prefix}
    taught=set(); prior=set()
    for did in prefix:
        d=all_content[did]
        for prerequisite in d.get('prerequisite_dossier_ids',[]):
            if prerequisite not in prior: fail(f'{did} prerequisite not earlier: {prerequisite}')
        for tag in d.get('required_tutorial_tags',[]):
            if tag not in taught: fail(f'{did} requires untaught tutorial tag: {tag}')
        prior.add(did); taught.update(d.get('tutorial_tags',[]))

    for i in range(9,17):
        did=f'D{i:02d}'; d=all_content[did]
        if d.get('act_index')!=2 or len(d.get('map_layers',[]))!=1: fail(f'{did} Act-II placement invalid')
        if not 2 <= len(d.get('agents',[])) <= 5: fail(f'{did} must stay inside Act-II 2-5 agent envelope')
        if len(d.get('editable_primitive_permissions',[]))>5: fail(f'{did} primitive ceiling exceeded')
        if d.get('reaction_beats_after_edit',99)>3 or d.get('stability_required_cycles',99)>2: fail(f'{did} Act-II reaction/Stability ceiling exceeded')
        if any(str(a.get('archetype_id','')).startswith(('A8_','A10_')) for a in d.get('agents',[])): fail(f'{did} introduces a specialist before its frozen act')
        sol=d.get('validation_metadata',{}).get('known_solution_envelope',{})
        if not sol.get('solution_commands'): fail(f'{did} known solution commands missing')

    for did in ('D09','D10'):
        d=all_content[did]
        if 'landmark' not in d.get('editable_primitive_permissions',[]): fail(f'{did} must teach editable landmark semantics')
        probe=d.get('validation_metadata',{}).get('semantic_non_dominance',{})
        for key in ('all_initial_single_relabels_tested','relabel_plus_cheapest_intervention_tested'):
            if not probe.get(key): fail(f'{did} P10-R2 evidence missing: {key}')
        if probe.get('bypasses_central_causal_lesson',True): fail(f'{did} relabel probe bypasses central lesson')
        if not probe.get('cheapest_additional_candidate_id'): fail(f'{did} cheapest additional intervention witness missing')
    if not all_content['D10'].get('allow_duplicate_landmark_labels'): fail('D10 must allow competing duplicate semantic targets')

    d11=all_content['D11']
    if d11.get('editable_primitive_permissions')!=['waterway'] or 'O6_WATER_CONNECTIVITY' not in families(d11): fail('D11 must introduce waterway + Ferry connectivity cleanly')
    if not any(a.get('archetype_id')=='A7_FERRY_WATER_CARRIER' for a in d11.get('agents',[])): fail('D11 Ferry missing')

    d12=all_content['D12']; cmds=d12['validation_metadata']['known_solution_envelope']['solution_commands']
    if d12.get('editable_primitive_permissions')!=['waterway','bridge']: fail('D12 must combine waterway + bridge')
    if [c.get('primitive_family') for c in cmds]!=['waterway','bridge']: fail('D12 solution must establish water then supported bridge crossing')

    for did,expected in TRANSFORMS.items():
        if all_content[did].get('validation_metadata',{}).get('dominant_reasoning_transformation')!=expected: fail(f'{did} P10-R1 transform changed')
    if len({TRANSFORMS[d] for d in ('D13','D14','D15')})<2 or len({TRANSFORMS[d] for d in ('D14','D15','D16')})<2: fail('D13-D16 P10-R1 three-window diversity failed')

    d13=all_content['D13']
    emergency=next((a for a in d13.get('agents',[]) if a.get('agent_id')=='D13_AG_EMERGENCY'),{})
    if 'D13_ZP_QUIET' not in emergency.get('ignored_restricted_zone_policy_ids',[]): fail('D13 Emergency override evidence missing')
    if not {'O2_NON_REACHABILITY','O5_PERMISSION_COMPLIANCE'} <= families(d13): fail('D13 permission contrast families missing')

    d14=all_content['D14']
    if not any(a.get('archetype_id')=='A6_COMMERCIAL_CARRIER' for a in d14.get('agents',[])): fail('D14 Commercial Carrier missing')
    if not {'O5_PERMISSION_COMPLIANCE','O7_SEMANTIC_DESTINATION'} <= families(d14): fail('D14 route/permission/service requirement mix missing')

    d15=all_content['D15']
    if 'O9_PROTECTED_ADJACENCY' not in families(d15): fail('D15 protected adjacency missing')
    unsafe=set(d15.get('validation_metadata',{}).get('alternative_solution_search',{}).get('unsafe_candidate_ids',[]))
    solution_ids={cid for c in d15['validation_metadata']['known_solution_envelope']['solution_commands'] for cid in c.get('candidate_ids',[])}
    if 'D15_R_WETLAND_TARGET' not in unsafe or 'D15_R_WETLAND_TARGET' in solution_ids: fail('D15 max-connectivity trap regression')

    d16=all_content['D16']; sol=d16['validation_metadata']['known_solution_envelope']; evidence=sol.get('stability_transition_evidence',[])
    if d16.get('stability_required_cycles')!=2 or d16.get('stability_reason_tag')!='agent_progression_arrival': fail('D16 first two-cycle Stability contract changed')
    if not sol.get('relevant_temporal_transition_observed') or not evidence: fail('D16 non-idle Stability evidence incomplete')
    known_agents={a.get('agent_id') for a in d16.get('agents',[])}
    known_nodes={n.get('node_id') for n in d16['map_layers'][0].get('nodes',[])}
    seen_cycles=set()
    for event in evidence:
        cycle=int(event.get('cycle',0))
        if cycle<1 or cycle>d16.get('stability_required_cycles',0) or cycle in seen_cycles or event.get('agent_id') not in known_agents: fail('D16 Stability evidence cycle/agent invalid')
        seen_cycles.add(cycle)
        if event.get('from_node_id') not in known_nodes or event.get('to_node_id') not in known_nodes or event.get('from_node_id')==event.get('to_node_id'): fail('D16 Stability evidence must be a real non-idle canonical node transition')
        if event.get('transition_kind')!=d16.get('stability_reason_tag'): fail('D16 Stability evidence reason mismatch')

    production=(ROOT/'src/application/production_content_validator.gd').read_text()
    test=(ROOT/'tests/test_act2_content_runner.gd').read_text()
    runtime=(ROOT/'scripts/run_phase12a_runtime.sh').read_text()
    for marker in ('p10_r3_transition_evidence_missing','stability_transition_evidence','transition_reason_mismatch'):
        if marker not in production: fail(f'production validator missing Stability evidence guard: {marker}')
    for marker in ('D10 must visibly allow competing duplicate semantic targets','D12 solution must establish water authority first','Production validator must reject Stability>1 content without concrete transition evidence'):
        if marker not in test: fail(f'Act-II headless acceptance marker missing: {marker}')
    if 'phase12d-act2-content-contract' not in runtime or 'test_act2_content_runner.gd' not in runtime: fail('runtime wrapper not wired for Act-II content')
    print('Phase 12D Act-II content audit: PASS (D09-D16 semantics/water/P10/Stability/progression)')

if __name__=='__main__': main()
