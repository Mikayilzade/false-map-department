#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
CAMPAIGN=ROOT/'content/campaign'
REGISTRY=ROOT/'content/registry.json'

def canon(v): return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False)
def fail(m): raise SystemExit(f'PHASE12D ACT4 FAIL: {m}')
def load(did):
    p=CAMPAIGN/f'{did}.json'
    if not p.exists(): fail(f'{did} missing')
    d=json.loads(p.read_text())
    body=dict(d); declared=body.pop('content_hash','')
    if hashlib.sha256(canon(body).encode()).hexdigest()!=declared: fail(f'{did} content_hash mismatch')
    return d

def editable_layers(d): return sum(bool(x.get('editable_candidates')) for x in d.get('map_layers',[]))
def families(d): return {r.get('family_id') for k in ('objectives','protected_invariants') for r in d.get(k,[])}
def has_a10(d): return any(str(a.get('archetype_id','')).startswith('A10_') for a in d.get('agents',[]))

def main():
    reg=json.loads(REGISTRY.read_text())
    payload=dict(reg); declared=payload.pop('registry_hash','')
    if hashlib.sha256(canon(payload).encode()).hexdigest()!=declared: fail('registry_hash mismatch')
    prefix=[f'D{i:02d}' for i in range(1,33)]
    if [e.get('dossier_id') for e in reg.get('campaign',[])[:32]]!=prefix: fail('registry must be exact contiguous D01-D32 prefix')
    allc={did:load(did) for did in prefix}

    taught=set(); prior=set()
    for did in prefix:
        d=allc[did]
        for p in d.get('prerequisite_dossier_ids',[]):
            if p not in prior: fail(f'{did} prerequisite not earlier: {p}')
        for tag in d.get('required_tutorial_tags',[]):
            if tag not in taught: fail(f'{did} requires untaught tutorial tag: {tag}')
        prior.add(did); taught.update(d.get('tutorial_tags',[]))

    for i in range(25,33):
        did=f'D{i:02d}'; d=allc[did]
        if d.get('act_index')!=4: fail(f'{did} must be Act IV')
        if len(d.get('agents',[]))>9 or len(d.get('editable_primitive_permissions',[]))>6: fail(f'{did} Act-IV agent/primitive ceiling exceeded')
        if d.get('reaction_beats_after_edit',99)>5 or d.get('stability_required_cycles',99)>4: fail(f'{did} Act-IV reaction/Stability ceiling exceeded')
        ceiling=2 if i<=28 else 3
        if len(d.get('map_layers',[]))>ceiling: fail(f'{did} linked layer curve exceeded')
        if editable_layers(d)>2: fail(f'{did} exceeds maximum two simultaneous editing surfaces')
        if len(d.get('linked_authority_relations',[]))<1: fail(f'{did} must exercise linked authority')
        b=d.get('validation_metadata',{}).get('linked_readability_budget',{})
        if b.get('max_remote_target_layers_for_selected_chain')!=1 or b.get('max_cross_layer_projection_edges_per_required_chain',99)>2: fail(f'{did} P10-R5 readability budget invalid')
        if not b.get('authoritative_source_unique_for_every_required_chain'): fail(f'{did} authority source must be explicit')
        cb=d.get('validation_metadata',{}).get('causal_presentation_budget',{})
        if cb.get('max_material_nodes',99)>5 or cb.get('max_visible_sibling_branches',99)>2 or not cb.get('all_required_chains_compressible'): fail(f'{did} P10-R6 causal budget invalid')
        if not d.get('validation_metadata',{}).get('known_solution_envelope',{}).get('solution_commands'): fail(f'{did} known solution missing')
        targets=set(); graph={x.get('layer_id'):set() for x in d.get('map_layers',[])}
        for r in d.get('linked_authority_relations',[]):
            if r.get('direction')!='one-way': fail(f'{did} relation must be one-way')
            key=(r.get('target_layer_id'),r.get('target_projection_id'))
            if key in targets: fail(f'{did} double-owns projected target')
            targets.add(key); graph.setdefault(r.get('source_layer_id'),set()).add(r.get('target_layer_id'))
        indeg={k:0 for k in graph}
        for src,vals in graph.items():
            for dst in vals: indeg[dst]=indeg.get(dst,0)+1
        ready=sorted(k for k,v in indeg.items() if v==0); seen=[]
        while ready:
            x=ready.pop(0); seen.append(x)
            for dst in sorted(graph.get(x,set())):
                indeg[dst]-=1
                if indeg[dst]==0: ready.append(dst); ready.sort()
        if len(seen)!=len(indeg): fail(f'{did} linked authority cycle')

    transforms={i:allc[f'D{i:02d}']['validation_metadata'].get('dominant_reasoning_transformation','') for i in range(13,33)}
    for start in range(13,31):
        if len({transforms[i] for i in range(start,start+3)})<2: fail(f'P10-R1 3-window failed at D{start:02d}')
    for start in range(13,29):
        if len({transforms[i] for i in range(start,start+5)})<3: fail(f'P10-R1 5-window failed at D{start:02d}')

    d25=allc['D25']
    if editable_layers(d25)!=2 or not d25['validation_metadata'].get('first_true_two_layer_edit'): fail('D25 must be first true two-layer editable authority case')
    d26=allc['D26']
    if d26.get('editable_primitive_permissions')!=['border','road'] or d26['linked_authority_relations'][0].get('projection_semantics')!='fact_mirror': fail('D26 route + jurisdiction projection contract changed')
    d27=allc['D27']; probe=d27['validation_metadata'].get('semantic_non_dominance',{})
    if 'landmark' not in d27.get('editable_primitive_permissions',[]) or not probe.get('all_initial_single_relabels_tested') or not probe.get('relabel_plus_cheapest_intervention_tested') or probe.get('bypasses_central_causal_lesson',True): fail('D27 P10-R2 semantic connector proof invalid')
    d28=allc['D28']
    if not any(a.get('archetype_id')=='A7_FERRY_WATER_CARRIER' for a in d28.get('agents',[])) or not {'O6_WATER_CONNECTIVITY','O12_CROSS_LAYER_CONNECTOR_STATE'}<=families(d28): fail('D28 water/Ferry portal dependency missing')
    d29=allc['D29']
    if len(d29.get('map_layers',[]))!=3 or d29['validation_metadata'].get('active_required_remote_chain_count')!=1: fail('D29 must be first three-layer case with one active required remote chain')
    for i in range(1,30):
        if has_a10(allc[f'D{i:02d}']): fail(f'A10 appears before D30 at D{i:02d}')
    d30=allc['D30']
    if not has_a10(d30) or 'O12_CROSS_LAYER_CONNECTOR_STATE' not in families(d30) or not d30.get('protected_invariants'): fail('D30 first A10 + local invariant contract missing')
    d31=allc['D31']; sol=d31['validation_metadata']['known_solution_envelope']
    if d31.get('stability_required_cycles')!=3 or d31.get('stability_reason_tag')!='linked_connector_state_propagation' or len(sol.get('stability_transition_evidence',[]))!=3: fail('D31 cross-layer Stability evidence invalid')
    d32=allc['D32']
    if len(d32.get('map_layers',[]))!=3 or len(d32.get('linked_authority_relations',[]))!=2 or editable_layers(d32)!=2 or not d32['validation_metadata'].get('act4_synthesis'): fail('D32 Act-IV synthesis shape invalid')
    if {r.get('target_layer_id') for r in d32['linked_authority_relations']}!={'D32_L3'}: fail('D32 required remote effects must converge on one readable target layer')

    runtime=(ROOT/'scripts/run_phase12a_runtime.sh').read_text()
    test=(ROOT/'tests/test_act4_content_runner.gd').read_text()
    if 'phase12d-act4-content-contract' not in runtime or 'test_act4_content_runner.gd' not in runtime: fail('runtime wrapper not wired for Act IV')
    for marker in ('D25 must expose exactly two editable authority layers','D30 must be the first A10 Regional Connector','D32 projections must converge on one read-only remote layer'):
        if marker not in test: fail(f'Act-IV headless marker missing: {marker}')
    print('Phase 12D Act-IV content audit: PASS (D25-D32 linked authority/A10/Stability/synthesis)')

if __name__=='__main__': main()
