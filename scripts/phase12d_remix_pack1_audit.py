#!/usr/bin/env python3
from __future__ import annotations
import json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REG = ROOT / "content/registry.json"
CAM = ROOT / "content/campaign"
REM = ROOT / "content/remix"

ALLOWED_CHANGED = {
    "initial_primitive_state", "agent_start_nodes", "semantic_target_assignments",
    "semantic_label_vocabulary", "jurisdiction_initial_ownership",
    "optional_mastery_threshold", "objective_selection",
}
TRANSFORMS = {
    "topology_restructuring", "ownership_reinterpretation", "semantic_target_reinterpretation",
    "permission_asymmetry", "cross_network_dependency", "temporal_stability_dependency",
    "linked_authority_dependency", "causal_compression_elegance",
}

def fail(msg: str) -> None:
    raise SystemExit(f"PHASE12D REMIX PREFIX FAIL: {msg}")

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))

def source_layers(src):
    return {x.get("layer_id"): x for x in src.get("map_layers", [])}

def source_agents(src):
    return {x.get("agent_id"): x for x in src.get("agents", [])}

def source_nodes(src):
    return {n.get("node_id") for l in src.get("map_layers", []) for n in l.get("nodes", [])}

def source_families(src):
    return {x.get("family_id") for k in ("objectives", "protected_invariants") for x in src.get(k, [])}

def source_required_families(src):
    return {x.get("family_id") for k in ("objectives", "protected_invariants") for x in src.get(k, []) if x.get("required")}

def all_edge_ids(layer):
    return {x.get("edge_id") for k in ("candidate_road_edges", "candidate_water_edges") for x in layer.get(k, [])}

def all_bridge_ids(layer):
    return {x.get("bridge_candidate_id") for x in layer.get("crossing_slots", []) if x.get("bridge_candidate_id")}

def validate_changed_inputs(remix, src):
    rid = remix["dossier_id"]
    changed = remix.get("changed_inputs")
    if not isinstance(changed, dict) or not changed:
        fail(f"{rid} changed_inputs missing")
    if not set(changed) <= ALLOWED_CHANGED:
        fail(f"{rid} changed_inputs outside frozen whitelist")
    meta = remix.get("validation_metadata", {})
    if sorted(meta.get("bounded_parameter_families", [])) != sorted(changed):
        fail(f"{rid} bounded_parameter_families mismatch")

    layers = source_layers(src)
    agents = source_agents(src)
    nodes = source_nodes(src)
    families = source_families(src)
    actual_change = False

    if "agent_start_nodes" in changed:
        for aid, nid in changed["agent_start_nodes"].items():
            if aid not in agents or nid not in nodes:
                fail(f"{rid} invalid agent start override {aid}->{nid}")
            if agents[aid].get("start_node_or_cell") != nid:
                actual_change = True

    if "objective_selection" in changed:
        selected = changed["objective_selection"].get("required_family_ids", [])
        if not selected or not set(selected) <= families:
            fail(f"{rid} objective selection is not from source prevalidated families")
        if set(selected) != source_required_families(src):
            actual_change = True

    if "initial_primitive_state" in changed:
        for lid, override in changed["initial_primitive_state"].items():
            if lid not in layers or not isinstance(override, dict):
                fail(f"{rid} invalid initial-state layer {lid}")
            layer = layers[lid]
            initial = layer.get("initial_primitives", {})
            for key, val in override.items():
                if key not in initial:
                    fail(f"{rid} initial primitive field not present on substrate: {lid}.{key}")
                if key in ("active_road_edge_ids", "active_water_edge_ids") and not set(val) <= all_edge_ids(layer):
                    fail(f"{rid} unknown edge in {lid}.{key}")
                if key == "active_bridge_ids" and not set(val) <= all_bridge_ids(layer):
                    fail(f"{rid} unknown bridge in {lid}.{key}")
                if val != initial.get(key):
                    actual_change = True

    if not actual_change:
        fail(f"{rid} declares inputs but does not actually change the substrate")

def validate_pack(pack_id: str, ids: list[str]) -> None:
    transforms = set()
    for rid in ids:
        remix_path = REM / f"{rid}.json"
        if not remix_path.exists():
            fail(f"{rid} missing")
        remix = load(remix_path)
        if remix.get("dossier_id") != rid or remix.get("remix_schema_version") != 1:
            fail(f"{rid} identity/schema invalid")
        if remix.get("remix_pack_id") != pack_id:
            fail(f"{rid} must belong to {pack_id}")
        source_id = remix.get("source_substrate_id", "")
        if not re.fullmatch(r"D\d{2}", source_id):
            fail(f"{rid} source_substrate_id invalid")
        source_path = CAM / f"{source_id}.json"
        if not source_path.exists():
            fail(f"{rid} source substrate missing")
        source = load(source_path)
        transform = remix.get("expected_new_reasoning_transformation", "")
        if transform not in TRANSFORMS:
            fail(f"{rid} reasoning transformation invalid")
        source_transform = source.get("validation_metadata", {}).get("dominant_reasoning_transformation", "")
        if source_transform and transform == source_transform:
            fail(f"{rid} expected new reasoning transformation repeats its source substrate")
        transforms.add(transform)
        meta = remix.get("validation_metadata", {})
        if len(str(meta.get("actual_changed_causal_dependency", "")).strip()) < 40:
            fail(f"{rid} changed causal dependency explanation too weak")
        if not meta.get("changed_dependency_proof"):
            fail(f"{rid} changed dependency proof missing")
        for flag in ("no_new_agent_scripts", "no_new_graph_topology", "no_new_linked_authority", "no_new_primitive_families"):
            if meta.get(flag) is not True:
                fail(f"{rid} safety flag missing: {flag}")
        validate_changed_inputs(remix, source)
    if len(transforms) < 3:
        fail(f"{pack_id} must contain at least three distinct reasoning transformations")

def main():
    reg = load(REG)
    entries = reg.get("remixes", [])
    prefix8 = [f"REMIX{i:02d}" for i in range(1, 9)]
    ids = [e.get("dossier_id") for e in entries]
    if len(ids) < 8 or ids[:8] != prefix8:
        fail("registry must production-register contiguous REMIX01-REMIX08 prefix")
    validate_pack("PACK01", prefix8[:4])
    validate_pack("PACK02", prefix8[4:])
    print("Phase 12D Remix prefix audit: PASS (PACK01 + PACK02 / REMIX01-REMIX08 P10-R10)")

if __name__ == "__main__":
    main()
