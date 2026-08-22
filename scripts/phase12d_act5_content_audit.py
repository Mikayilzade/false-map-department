#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
CAMPAIGN=ROOT/'content/campaign'
REGISTRY=ROOT/'content/registry.json'

def canon(v): return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False)
def fail(m): raise SystemExit(f'PHASE12D ACT5 FAIL: {m}')
def load(did):
    p=CAMPAIGN/f'{did}.json'
    if not p.exists(): fail(f'{did} missing')
    d=json.loads(p.read_text(encoding='utf-8'))
    body=dict(d); declared=body.pop('content_hash','')
    if hashlib.sha256(canon(body).encode()).hexdigest()!=declared: fail(f'{did} content_hash mismatch')
    return d

def editable_layers(d): return sum(bool(x.get('editable_candidates')) for x in d.get('map_layers',[]))
def required_clauses(d): return sum(bool(x.get('required',False)) for k in ('objectives','protected_invariants') for x in d.get(k,[]))
def families(d): return {r.get('family_id') for k in ('objectives','protected_invariants') for r in d.get(k,[])}
def has_agent(d,prefix): return any(str(a.get('archetype_id','')).startswith(prefix) for a in d.get('agents',[]))
def linked_dag_ok(d):
    targets=set(); graph={x.get('layer_id'):set() for x in d.get('map_layers',[])}
    for r in d.get('linked_authority_relations',[]):
        if r.get('direction')!='one-way': return False
        key=(r.get('target_layer_id'),r.get('target_projection_id'))
        if key in targets: return False
        targets.add(key); graph.setdefault(r.get('source_layer_id'),set()).add(r.get('target_layer_id'))
    indeg={k:0 for k in graph}
    for vals in graph.values():
        for dst in vals: indeg[dst]=indeg.get(dst,0)+1
    ready=sorted(k for k,v in indeg.items() if v==0); seen=[]
    while ready:
        x=ready.pop(0); seen.append(x)
        for dst in sorted(graph.get(x,set())):
            indeg[dst]-=1
            if indeg[dst]==0: ready.append(dst); ready.sort()
    return len(seen)==len(indeg)

def main():
    reg=json.loads(REGISTRY.read_text(encoding='utf-8'))
    payload=dict(reg); declared=payload.pop('registry_hash','')
    if hashlib.sha256(canon(payload).encode()).hexdigest()!=declared: fail('registry_hash mismatch')
    prefix=[f'D{i:02d}' for i in range(1,41)]
    if [e.get('dossier_id') for e in reg.get('campaign',[])]!=prefix: fail('registry campaign must be exact contiguous D01-D40')
    remix_ids=[e.get('dossier_id') for e in reg.get('remixes',[])]
    if len(remix_ids)>12: fail('remix ceiling exceeded after Act V')
    if remix_ids!=[f'REMIX{i:02d}' for i in range(1,len(remix_ids)+1)]: fail('registered remixes must form a contiguous REMIX01 prefix')
    allc={did:load(did) for did in prefix}

    taught=set(); prior=set()
    for did in prefix:
        d=allc[did]
        for p in d.get('prerequisite_dossier_ids',[]):
            if p not in prior: fail(f'{did} prerequisite not earlier: {p}')
        for tag in d.get('required_tutorial_tags',[]):
            if tag not in taught: fail(f'{did} requires untaught tutorial tag: {tag}')
        prior.add(did); taught.update(d.get('tutorial_tags',[]))

    for i in range(33,41):
        did=f'D{i:02d}'; d=allc[did]; md=d.get('validation_metadata',{})
        if d.get('act_index')!=5: fail(f'{did} must be Act V')
        if len(d.get('agents',[]))>10 or len(d.get('editable_primitive_permissions',[]))>6: fail(f'{did} Act-V agent/primitive ceiling exceeded')
        if d.get('reaction_beats_after_edit',99)>5 or d.get('stability_required_cycles',99)>5: fail(f'{did} reaction/Stability ceiling exceeded')
        if len(d.get('map_layers',[]))>(3 if i<=36 else 4): fail(f'{did} linked layer curve exceeded')
        if editable_layers(d)>2 or md.get('max_simultaneous_editing_surfaces',99)>2: fail(f'{did} exceeds two-surface ceiling')
        if required_clauses(d)>6: fail(f'{did} exceeds six required evaluation clauses')
        if not md.get('known_solution_envelope',{}).get('solution_commands'): fail(f'{did} known solution missing')
        cb=md.get('causal_presentation_budget',{})
        if cb.get('max_material_nodes',99)>5 or cb.get('max_visible_sibling_branches',99)>2 or not cb.get('all_required_chains_compressible'): fail(f'{did} P10-R6 causal budget invalid')
        for layer in d.get('map_layers',[]):
            if not layer.get('editable_candidates'): continue
            lid=layer.get('layer_id'); fg=md.get('focus_graph_by_layer',{}).get(lid,{})
            if set(fg.get('required_focusable_candidate_ids',[]))!=set(layer.get('editable_candidates',[])): fail(f'{did} P10-R7 focus candidates do not cover editable layer {lid}')
        if d.get('linked_authority_relations'):
            if not linked_dag_ok(d): fail(f'{did} linked authority is not one-way acyclic single-target')
            lb=md.get('linked_readability_budget',{})
            if lb.get('max_cross_layer_projection_edges_per_required_chain',99)>3 or not lb.get('authoritative_source_unique_for_every_required_chain'): fail(f'{did} P10-R5 linked readability invalid')
        if d.get('stability_required_cycles',0)>1:
            sol=md.get('known_solution_envelope',{}); ev=sol.get('stability_transition_evidence',[])
            if len(ev)!=d.get('stability_required_cycles') or not sol.get('relevant_temporal_transition_observed'): fail(f'{did} P10-R3 Stability proof invalid')
        if 'landmark' in d.get('editable_primitive_permissions',[]):
            p=md.get('semantic_non_dominance',{})
            if not p.get('all_initial_single_relabels_tested') or not p.get('relabel_plus_cheapest_intervention_tested') or p.get('bypasses_central_causal_lesson',True): fail(f'{did} P10-R2 relabel proof invalid')
        for m in d.get('mastery_contracts',[]):
            if len(str(m.get('mastery_distinction_note','')).strip())<12 or not m.get('distinction_kind'): fail(f'{did} P10-R4 mastery distinction invalid')

    transforms={i:allc[f'D{i:02d}']['validation_metadata'].get('dominant_reasoning_transformation','') for i in range(13,41)}
    for start in range(13,39):
        if len({transforms[i] for i in range(start,start+3)})<2: fail(f'P10-R1 3-window failed at D{start:02d}')
    for start in range(13,37):
        if len({transforms[i] for i in range(start,start+5)})<3: fail(f'P10-R1 5-window failed at D{start:02d}')

    d33=allc['D33']; d34=allc['D34']; d35=allc['D35']; d36=allc['D36']; d37=allc['D37']; d38=allc['D38']; d39=allc['D39']; d40=allc['D40']
    if len(d33.get('map_layers',[]))!=3 or not d33['validation_metadata'].get('compact_three_layer_optimization'): fail('D33 compact three-layer optimization contract missing')
    if not d34['validation_metadata'].get('semantic_relabel_beats_infrastructure_expansion'): fail('D34 must explicitly prefer semantic authority over expansion')
    if not d35['validation_metadata'].get('maximum_connectivity_is_harmful'): fail('D35 must make maximum connectivity explicitly wrong')
    if 'border' not in d36.get('editable_primitive_permissions',[]) or not d36.get('mastery_contracts') or not d36['validation_metadata'].get('border_move_solves_three_systems'): fail('D36 border compression + optional mastery contract missing')
    if len(d37.get('map_layers',[]))!=4 or editable_layers(d37)!=2 or not d37['validation_metadata'].get('first_four_layer_case'): fail('D37 must be first four-layer case with exactly two editable surfaces')
    sol38=d38['validation_metadata']['known_solution_envelope']
    if not has_agent(d38,'A8_') or not {'O8_VISIT_SEQUENCE','O12_CROSS_LAYER_CONNECTOR_STATE'}<=families(d38) or d38.get('stability_required_cycles')!=2 or len(sol38.get('stability_transition_evidence',[]))!=2: fail('D38 portal + Procession Stability grammar invalid')
    sol39=d39['validation_metadata']['known_solution_envelope']
    if d39.get('stability_required_cycles')!=5 or len(sol39.get('stability_transition_evidence',[]))!=5 or not d39.get('mastery_contracts'): fail('D39 five-cycle civic synthesis/mastery contract invalid')
    md40=d40['validation_metadata']
    if len(d40.get('map_layers',[]))!=4 or editable_layers(d40)!=2 or required_clauses(d40)!=6: fail('D40 final shape invalid')
    if md40.get('baseline_requires_mastery',True) or not md40.get('zero_mastery_baseline_proven'): fail('D40 zero-mastery baseline proof missing')
    if not md40.get('final_department_synthesis') or not md40.get('no_bespoke_boss_mechanic'): fail('D40 must be synthesis without bespoke boss mechanics')

    runtime=(ROOT/'scripts/run_phase12a_runtime.sh').read_text(encoding='utf-8')
    test=(ROOT/'tests/test_act5_content_runner.gd').read_text(encoding='utf-8')
    if 'phase12d-act5-content-contract' not in runtime or 'test_act5_content_runner.gd' not in runtime: fail('runtime wrapper not wired for Act V')
    for marker in ('D37 must be the first four-layer case','D39 must require the full five-cycle Stability ceiling','D40 must remain reachable with zero mastery'):
        if marker not in test: fail(f'Act-V headless marker missing: {marker}')
    print('Phase 12D Act-V content audit: PASS (D33-D40 final campaign synthesis + zero-mastery D40; remix prefix allowed)')

if __name__=='__main__': main()
