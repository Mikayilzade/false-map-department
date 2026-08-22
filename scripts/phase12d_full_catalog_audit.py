#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REG=ROOT/'content/registry.json'; CAM=ROOT/'content/campaign'; DEMO=ROOT/'content/demo'; REM=ROOT/'content/remix'
TRANSFORMS={'topology_restructuring','ownership_reinterpretation','semantic_target_reinterpretation','permission_asymmetry','cross_network_dependency','temporal_stability_dependency','linked_authority_dependency','causal_compression_elegance'}
ALLOWED_CHANGED={'initial_primitive_state','agent_start_nodes','semantic_target_assignments','semantic_label_vocabulary','jurisdiction_initial_ownership','optional_mastery_threshold','objective_selection'}
REMIX_KEYS={'changed_inputs','dossier_id','expected_new_reasoning_transformation','remix_pack_id','remix_schema_version','source_substrate_id','unlock_milestone_id','validation_metadata'}

def fail(m): raise SystemExit(f'PHASE12D FULL CATALOG FAIL: {m}')
def load(p): return json.loads(p.read_text(encoding='utf-8'))
def canon(v): return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False)
def sha(v): return hashlib.sha256(canon(v).encode()).hexdigest()

def verify_hashed_content(path, expected_id):
    d=load(path)
    if d.get('dossier_id')!=expected_id: fail(f'{expected_id} identity mismatch')
    declared=d.get('content_hash','')
    body=dict(d); body.pop('content_hash',None)
    if not declared or sha(body)!=declared: fail(f'{expected_id} content_hash mismatch')
    return d

def source_context(src):
    ls={x.get('layer_id'):x for x in src.get('map_layers',[])}
    ag={x.get('agent_id'):x for x in src.get('agents',[])}
    ns={n.get('node_id') for l in src.get('map_layers',[]) for n in l.get('nodes',[])}
    fam={x.get('family_id') for k in ('objectives','protected_invariants') for x in src.get(k,[])}
    req={x.get('family_id') for k in ('objectives','protected_invariants') for x in src.get(k,[]) if x.get('required')}
    jids={j.get('jurisdiction_id') for j in src.get('jurisdictions',[])}
    cells={c.get('cell_id') for l in src.get('map_layers',[]) for c in l.get('cells',[])}
    init_j={}
    for l in src.get('map_layers',[]): init_j.update(l.get('initial_primitives',{}).get('jurisdiction_by_cell',{}))
    vocab=set(src.get('semantic_label_vocabulary',[])) | {lab for lm in src.get('landmarks',[]) for lab in lm.get('allowed_semantic_labels',[])}
    return ls,ag,ns,fam,req,jids,cells,init_j,vocab

def validate_remix_inputs(remix,src):
    rid=remix['dossier_id']; changed=remix.get('changed_inputs',{})
    if not isinstance(changed,dict) or not changed or not set(changed)<=ALLOWED_CHANGED: fail(f'{rid} changed_inputs invalid')
    meta=remix.get('validation_metadata',{})
    if sorted(meta.get('bounded_parameter_families',[]))!=sorted(changed): fail(f'{rid} bounded_parameter_families mismatch')
    ls,ag,ns,fam,req,jids,cells,init_j,vocab=source_context(src)
    actual=False
    if 'initial_primitive_state' in changed:
        for lid,ov in changed['initial_primitive_state'].items():
            if lid not in ls or not isinstance(ov,dict): fail(f'{rid} invalid initial-state layer {lid}')
            layer=ls[lid]; initial=layer.get('initial_primitives',{})
            road_ids={e.get('edge_id') for e in layer.get('candidate_road_edges',[])}
            water_ids={e.get('edge_id') for e in layer.get('candidate_water_edges',[])}
            bridge_ids={x.get('bridge_candidate_id') for x in layer.get('crossing_slots',[]) if x.get('bridge_candidate_id')}
            for key,val in ov.items():
                if key not in initial: fail(f'{rid} unknown initial primitive field {lid}.{key}')
                if key=='active_road_edge_ids' and not set(val)<=road_ids: fail(f'{rid} unknown road edge in {lid}')
                if key=='active_water_edge_ids' and not set(val)<=water_ids: fail(f'{rid} unknown water edge in {lid}')
                if key=='active_bridge_ids' and not set(val)<=bridge_ids: fail(f'{rid} unknown bridge in {lid}')
                actual |= val!=initial.get(key)
    if 'agent_start_nodes' in changed:
        for aid,nid in changed['agent_start_nodes'].items():
            if aid not in ag or nid not in ns: fail(f'{rid} invalid agent start {aid}->{nid}')
            actual |= ag[aid].get('start_node_or_cell')!=nid
    if 'semantic_target_assignments' in changed:
        for aid,target in changed['semantic_target_assignments'].items():
            if aid not in ag or target not in vocab: fail(f'{rid} invalid semantic target {aid}->{target}')
            actual |= ag[aid].get('semantic_target')!=target
    if 'semantic_label_vocabulary' in changed:
        vals=changed['semantic_label_vocabulary']
        if not isinstance(vals,list) or not set(vals)<=vocab: fail(f'{rid} semantic vocabulary override not prevalidated')
        actual |= vals!=src.get('semantic_label_vocabulary',[])
    if 'jurisdiction_initial_ownership' in changed:
        for cid,jid in changed['jurisdiction_initial_ownership'].items():
            if cid not in cells or jid not in jids: fail(f'{rid} invalid jurisdiction ownership {cid}->{jid}')
            actual |= init_j.get(cid)!=jid
    if 'objective_selection' in changed:
        selected=changed['objective_selection'].get('required_family_ids',[])
        if not selected or not set(selected)<=fam: fail(f'{rid} objective selection outside source family set')
        actual |= set(selected)!=req
    if 'optional_mastery_threshold' in changed:
        if not src.get('mastery_contracts'): fail(f'{rid} mastery threshold override has no source mastery')
        actual=True
    if not actual: fail(f'{rid} overlay does not actually change source substrate')

def main():
    reg=load(REG)
    payload=dict(reg); declared=payload.pop('registry_hash','')
    if sha(payload)!=declared: fail('registry_hash mismatch')
    campaign_ids=[f'D{i:02d}' for i in range(1,41)]
    demo_ids=[f'DEMO{i:02d}' for i in range(1,6)]
    remix_ids=[f'REMIX{i:02d}' for i in range(1,13)]
    if [x.get('dossier_id') for x in reg.get('campaign',[])]!=campaign_ids: fail('campaign registry must be exact D01-D40')
    if [x.get('dossier_id') for x in reg.get('demo',[])]!=demo_ids: fail('demo registry must be exact DEMO01-DEMO05')
    if [x.get('dossier_id') for x in reg.get('remixes',[])]!=remix_ids: fail('remix registry must be exact REMIX01-REMIX12')
    for entry,did in zip(reg['campaign'],campaign_ids):
        if entry.get('path')!=f'res://content/campaign/{did}.json': fail(f'{did} registry path mismatch')
        verify_hashed_content(CAM/f'{did}.json',did)
    for entry,did in zip(reg['demo'],demo_ids):
        if entry.get('path')!=f'res://content/demo/{did}.json': fail(f'{did} registry path mismatch')
        verify_hashed_content(DEMO/f'{did}.json',did)
    mapping_path=ROOT/'content/demo/demo_to_full_mapping.json'
    mapping=load(mapping_path); mb=dict(mapping); mh=mb.pop('mapping_hash','')
    if not mh or sha(mb)!=mh: fail('demo import mapping hash mismatch')

    pack_transforms={'PACK01':set(),'PACK02':set(),'PACK03':set()}
    for idx,rid in enumerate(remix_ids,1):
        entry=reg['remixes'][idx-1]
        if entry.get('path')!=f'res://content/remix/{rid}.json': fail(f'{rid} registry path mismatch')
        remix=load(REM/f'{rid}.json')
        if set(remix)-REMIX_KEYS: fail(f'{rid} overlay contains non-remix top-level fields')
        expected_pack=f'PACK{((idx-1)//4)+1:02d}'
        if remix.get('dossier_id')!=rid or remix.get('remix_schema_version')!=1 or remix.get('remix_pack_id')!=expected_pack: fail(f'{rid} identity/schema/pack mismatch')
        sid=remix.get('source_substrate_id','')
        if not re.fullmatch(r'D\d{2}',sid) or not (CAM/f'{sid}.json').exists(): fail(f'{rid} source substrate invalid')
        if not str(remix.get('unlock_milestone_id','')).endswith('_CLEAR'): fail(f'{rid} unlock milestone invalid')
        transform=remix.get('expected_new_reasoning_transformation','')
        if transform not in TRANSFORMS: fail(f'{rid} transformation invalid')
        pack_transforms[expected_pack].add(transform)
        meta=remix.get('validation_metadata',{})
        if len(str(meta.get('actual_changed_causal_dependency','')).strip())<40 or meta.get('changed_dependency_proof') is not True: fail(f'{rid} changed dependency proof weak')
        for flag in ('no_new_agent_scripts','no_new_graph_topology','no_new_linked_authority','no_new_primitive_families'):
            if meta.get(flag) is not True: fail(f'{rid} safety flag missing: {flag}')
        validate_remix_inputs(remix,load(CAM/f'{sid}.json'))
    for pack_id,transforms in pack_transforms.items():
        if len(transforms)<3: fail(f'{pack_id} has fewer than three reasoning transformations')
    print('Phase 12D strict full-catalog audit: PASS (40 campaign + 5 demo + 12 source-bound remixes)')

if __name__=='__main__': main()
