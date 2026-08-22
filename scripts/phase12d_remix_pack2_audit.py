#!/usr/bin/env python3
from __future__ import annotations
import json, re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REG=ROOT/'content/registry.json'; CAM=ROOT/'content/campaign'; REM=ROOT/'content/remix'
ALLOWED={'initial_primitive_state','agent_start_nodes','semantic_target_assignments','semantic_label_vocabulary','jurisdiction_initial_ownership','optional_mastery_threshold','objective_selection'}
TRANSFORMS={'topology_restructuring','ownership_reinterpretation','semantic_target_reinterpretation','permission_asymmetry','cross_network_dependency','temporal_stability_dependency','linked_authority_dependency','causal_compression_elegance'}

def fail(m): raise SystemExit(f'PHASE12D REMIX PACK2 FAIL: {m}')
def load(p): return json.loads(p.read_text(encoding='utf-8'))
def layers(src): return {x.get('layer_id'):x for x in src.get('map_layers',[])}
def agents(src): return {x.get('agent_id'):x for x in src.get('agents',[])}
def families(src): return {x.get('family_id') for k in ('objectives','protected_invariants') for x in src.get(k,[])}
def edge_ids(layer): return {x.get('edge_id') for k in ('candidate_road_edges','candidate_water_edges') for x in layer.get(k,[])}

def validate_inputs(remix,src):
    rid=remix['dossier_id']; changed=remix.get('changed_inputs',{})
    if not isinstance(changed,dict) or not changed or not set(changed)<=ALLOWED: fail(f'{rid} changed_inputs invalid')
    if sorted(remix.get('validation_metadata',{}).get('bounded_parameter_families',[]))!=sorted(changed): fail(f'{rid} bounded_parameter_families mismatch')
    ls=layers(src); ag=agents(src); fam=families(src); actual=False
    if 'initial_primitive_state' in changed:
        for lid,ov in changed['initial_primitive_state'].items():
            if lid not in ls or not isinstance(ov,dict): fail(f'{rid} invalid initial-state layer {lid}')
            initial=ls[lid].get('initial_primitives',{})
            for key,val in ov.items():
                if key not in initial: fail(f'{rid} unknown initial primitive field {lid}.{key}')
                if key in ('active_road_edge_ids','active_water_edge_ids') and not set(val)<=edge_ids(ls[lid]): fail(f'{rid} unknown edge in {lid}.{key}')
                actual |= val!=initial.get(key)
    if 'objective_selection' in changed:
        selected=changed['objective_selection'].get('required_family_ids',[])
        if not selected or not set(selected)<=fam: fail(f'{rid} objective family not prevalidated by source')
        src_req={x.get('family_id') for k in ('objectives','protected_invariants') for x in src.get(k,[]) if x.get('required')}
        actual |= set(selected)!=src_req
    if 'semantic_target_assignments' in changed:
        vocab=set(src.get('semantic_label_vocabulary',[])) | {lab for lm in src.get('landmarks',[]) for lab in lm.get('allowed_semantic_labels',[])}
        for aid,target in changed['semantic_target_assignments'].items():
            if aid not in ag or target not in vocab: fail(f'{rid} semantic target override not prevalidated: {aid}->{target}')
            actual |= ag[aid].get('semantic_target')!=target
    if 'jurisdiction_initial_ownership' in changed:
        known_j={j.get('jurisdiction_id') for j in src.get('jurisdictions',[])}
        initial={}; known_cells=set()
        for layer in src.get('map_layers',[]):
            known_cells |= {c.get('cell_id') for c in layer.get('cells',[])}
            initial.update(layer.get('initial_primitives',{}).get('jurisdiction_by_cell',{}))
        for cid,jid in changed['jurisdiction_initial_ownership'].items():
            if cid not in known_cells or jid not in known_j: fail(f'{rid} jurisdiction ownership override invalid: {cid}->{jid}')
            actual |= initial.get(cid)!=jid
    if not actual: fail(f'{rid} does not actually change its source substrate')

def main():
    reg=load(REG); entries=reg.get('remixes',[])
    prefix=[f'REMIX{i:02d}' for i in range(1,9)]
    if len(entries)<8 or [x.get('dossier_id') for x in entries[:8]]!=prefix: fail('registry must preserve contiguous REMIX01-REMIX08 prefix')
    transforms=set()
    for i in range(5,9):
        rid=f'REMIX{i:02d}'; remix=load(REM/f'{rid}.json')
        if remix.get('dossier_id')!=rid or remix.get('remix_schema_version')!=1 or remix.get('remix_pack_id')!='PACK02': fail(f'{rid} identity/schema/pack invalid')
        sid=remix.get('source_substrate_id','')
        if not re.fullmatch(r'D\d{2}',sid) or not (CAM/f'{sid}.json').exists(): fail(f'{rid} source substrate invalid')
        transform=remix.get('expected_new_reasoning_transformation','')
        if transform not in TRANSFORMS: fail(f'{rid} reasoning transformation invalid')
        transforms.add(transform)
        meta=remix.get('validation_metadata',{})
        if len(str(meta.get('actual_changed_causal_dependency','')).strip())<40 or meta.get('changed_dependency_proof') is not True: fail(f'{rid} changed dependency proof weak')
        for flag in ('no_new_agent_scripts','no_new_graph_topology','no_new_linked_authority','no_new_primitive_families'):
            if meta.get(flag) is not True: fail(f'{rid} missing safety flag {flag}')
        validate_inputs(remix,load(CAM/f'{sid}.json'))
    if len(transforms)<3: fail('PACK02 must contain at least three distinct reasoning transformations')
    print('Phase 12D Remix Pack 2 audit: PASS (REMIX05-REMIX08 P10-R10, bounded source overlays)')

if __name__=='__main__': main()
