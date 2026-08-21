#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
CAMPAIGN=ROOT/'content/campaign'
REGISTRY=ROOT/'content/registry.json'

def canon(v): return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False)
def fail(m): raise SystemExit(f'PHASE12D ACT3 FAIL: {m}')
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
    prefix=[f'D{i:02d}' for i in range(1,25)]
    if [e.get('dossier_id') for e in reg.get('campaign',[])[:24]]!=prefix: fail('registry must be exact contiguous D01-D24 prefix')

    all_content={did:load(did) for did in prefix}
    taught=set(); prior=set()
    for did in prefix:
        d=all_content[did]
        for p in d.get('prerequisite_dossier_ids',[]):
            if p not in prior: fail(f'{did} prerequisite not earlier: {p}')
        for tag in d.get('required_tutorial_tags',[]):
            if tag not in taught: fail(f'{did} requires untaught tutorial tag: {tag}')
        prior.add(did); taught.update(d.get('tutorial_tags',[]))

    for i in range(17,25):
        did=f'D{i:02d}'; d=all_content[did]
        if d.get('act_index')!=3: fail(f'{did} must be Act III')
        if len(d.get('agents',[]))>7: fail(f'{did} Act-III agent ceiling exceeded')
        if len(d.get('editable_primitive_permissions',[]))>6: fail(f'{did} primitive ceiling exceeded')
        if d.get('reaction_beats_after_edit',99)>4 or d.get('stability_required_cycles',99)>3: fail(f'{did} Act-III reaction/Stability ceiling exceeded')
        editable_layers=[ly for ly in d.get('map_layers',[]) if ly.get('editable_candidates')]
        if i<25 and len(editable_layers)>1: fail(f'{did} cannot expose true two-layer edit before D25')
        sol=d.get('validation_metadata',{}).get('known_solution_envelope',{})
        if not sol.get('solution_commands'): fail(f'{did} known solution commands missing')
        budget=d.get('validation_metadata',{}).get('causal_presentation_budget',{})
        if budget.get('max_material_nodes',99)>5 or budget.get('max_visible_sibling_branches',99)>2 or not budget.get('all_required_chains_compressible'): fail(f'{did} P10-R6 causal budget invalid')

    transforms={i:all_content[f'D{i:02d}']['validation_metadata'].get('dominant_reasoning_transformation','') for i in range(13,25)}
    patterns={i:all_content[f'D{i:02d}']['validation_metadata'].get('primary_reasoning_pattern','') for i in range(13,25)}
    for start in range(13,23):
        if len({transforms[i] for i in range(start,start+3)})<2: fail(f'P10-R1 3-window failed D{start:02d}-D{start+2:02d}')
        if len({patterns[i] for i in range(start,start+3)})<2: fail(f'primary reasoning pattern 3-window failed D{start:02d}-D{start+2:02d}')
    for start in range(13,21):
        if len({transforms[i] for i in range(start,start+5)})<3: fail(f'P10-R1 5-window failed D{start:02d}-D{start+4:02d}')

    d17=all_content['D17']
    if not any(a.get('archetype_id')=='A3_PATROL' for a in d17.get('agents',[])): fail('D17 Patrol missing')
    if d17.get('editable_primitive_permissions')!=['border']: fail('D17 must shift jurisdiction through border authority only')

    d18=all_content['D18']; proc=next((a for a in d18.get('agents',[]) if a.get('archetype_id')=='A8_PROCESSION_ROUTE_CONSTRAINED'),{})
    if not proc: fail('D18 must be first A8 Procession')
    pred=proc.get('procession_predicate',{})
    if pred.get('exact_distinct_jurisdiction_count')!=2 or len(pred.get('visit_landmark_ids_in_order',[]))!=2: fail('D18 Procession exact route predicate changed')
    for earlier in range(1,18):
        if any(str(a.get('archetype_id','')).startswith('A8_') for a in all_content[f'D{earlier:02d}'].get('agents',[])): fail('A8 appears before D18')
    if d18.get('stability_required_cycles')!=2 or d18.get('stability_reason_tag')!='procession_sequence_progression': fail('D18 Stability justification invalid')

    d19=all_content['D19']; probe=d19.get('validation_metadata',{}).get('semantic_non_dominance',{})
    if not {'O6_WATER_CONNECTIVITY','O7_SEMANTIC_DESTINATION'} <= families(d19): fail('D19 water + semantic chain families missing')
    if not probe.get('all_initial_single_relabels_tested') or not probe.get('relabel_plus_cheapest_intervention_tested') or probe.get('bypasses_central_causal_lesson',True): fail('D19 P10-R2 evidence invalid')
    if probe.get('principal_solution_is_semantic_relabel'): fail('D19 may not collapse into relabel-only shortcut')

    d20=all_content['D20']
    if not any(a.get('archetype_id')=='A5_EMERGENCY_SERVICE' for a in d20.get('agents',[])): fail('D20 Emergency Service missing')
    cap=d20['map_layers'][0].get('capacity_one_node_ids',[])
    if 'D20_N_GATE' not in cap: fail('D20 authored capacity-one contention missing')
    if d20.get('stability_reason_tag')!='route_contention_priority_evolution': fail('D20 priority-evolution Stability reason missing')

    d21=all_content['D21']
    if 'O10_NETWORK_CONTINUITY' not in families(d21) or 'O2_NON_REACHABILITY' not in families(d21): fail('D21 continuity/isolation family mix missing')
    if not d21.get('validation_metadata',{}).get('maximum_connectivity_is_harmful'): fail('D21 anti-max-connectivity evidence missing')

    d22=all_content['D22']
    if set(d22.get('editable_primitive_permissions',[]))!={'road','border','restricted_zone'}: fail('D22 must remain one-layer three-system exam')
    mastery=d22.get('mastery_contracts',[])
    if len(mastery)!=1 or mastery[0].get('distinction_kind')!='cross_system_compression' or len(mastery[0].get('mastery_distinction_note',''))<12: fail('D22 P10-R4 mastery distinction invalid')
    if d22.get('validation_metadata',{}).get('baseline_requires_mastery',True): fail('D22 mastery must stay optional')

    for did in ('D23','D24'):
        d=all_content[did]; layers=d.get('map_layers',[]); rel=d.get('linked_authority_relations',[])
        if len(layers)!=2 or len(rel)!=1: fail(f'{did} linked teaching shape invalid')
        if sum(bool(ly.get('editable_candidates')) for ly in layers)!=1: fail(f'{did} remote layer must remain non-editable')
        r=rel[0]
        if r.get('direction')!='one-way' or r.get('source_layer_id')!=f'{did}_L1' or r.get('target_layer_id')!=f'{did}_L2': fail(f'{did} linked direction/source invalid')
        b=d.get('validation_metadata',{}).get('linked_readability_budget',{})
        if b.get('max_remote_target_layers_for_selected_chain')!=1 or b.get('max_cross_layer_projection_edges_per_required_chain')!=1 or not b.get('authoritative_source_unique_for_every_required_chain'): fail(f'{did} linked readability budget invalid')
        if any(str(a.get('archetype_id','')).startswith('A10_') for a in d.get('agents',[])): fail(f'{did} cannot introduce A10 before D25')
    if not all_content['D23']['validation_metadata'].get('linked_preview_only'): fail('D23 must remain preview-only linked inset')
    if all_content['D24']['linked_authority_relations'][0].get('projection_semantics')!='portal_availability': fail('D24 first functional projection must drive portal availability')
    lesson=all_content['D24']['validation_metadata'].get('projection_lesson',{})
    if not lesson.get('one_way') or not lesson.get('edits_remain_local'): fail('D24 one-way/local-edit lesson invalid')

    test=(ROOT/'tests/test_act3_content_runner.gd').read_text()
    runtime=(ROOT/'scripts/run_phase12a_runtime.sh').read_text()
    for marker in ('D18 must be the first authored A8 Procession','D23 remote inset must be read-only','D24 projected portal availability must come from local authority','D22 mastery must remain optional'):
        if marker not in test: fail(f'Act-III headless marker missing: {marker}')
    if 'phase12d-act3-content-contract' not in runtime or 'test_act3_content_runner.gd' not in runtime: fail('runtime wrapper not wired for Act-III')
    print('Phase 12D Act-III content audit: PASS (D17-D24 Procession/continuity/mastery/linked preview+projection)')

if __name__=='__main__':
    main()
