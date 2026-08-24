#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "content" / "registry.json"
BINDINGS = ROOT / "content" / "runtime_bindings.json"
PROTOCOLS = ROOT / "empirical" / "phase12g_session_protocols.json"
ALLOWED_REMIX_CHANGES = {
    "initial_primitive_state",
    "agent_start_nodes",
    "objective_selection",
    "semantic_target_assignments",
    "jurisdiction_initial_ownership",
}


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def res_path(value: str) -> Path:
    if not value.startswith("res://"):
        raise ValueError(f"Expected res:// path, got {value!r}")
    return ROOT / value[len("res://") :]


def records(value):
    return value if isinstance(value, list) else []


def record_ids(items, field):
    return {str(row.get(field, "")) for row in records(items) if isinstance(row, dict)}


def materialize_remix(overlay: dict, campaign_by_id: dict[str, dict]) -> dict:
    remix_id = str(overlay.get("dossier_id", ""))
    source_id = str(overlay.get("source_substrate_id", ""))
    if overlay.get("remix_schema_version") != 1 or not remix_id.startswith("REMIX"):
        raise ValueError(f"Invalid remix identity: {remix_id}")
    if source_id not in campaign_by_id:
        raise ValueError(f"Missing remix source substrate: {source_id}")
    changed = overlay.get("changed_inputs") or {}
    unknown = set(changed) - ALLOWED_REMIX_CHANGES
    if unknown:
        raise ValueError(f"Unsupported remix change families for {remix_id}: {sorted(unknown)}")
    if not changed:
        raise ValueError(f"Remix {remix_id} has no changed_inputs")
    guards = overlay.get("validation_metadata") or {}
    for guard in ("no_new_agent_scripts", "no_new_graph_topology", "no_new_linked_authority", "no_new_primitive_families", "changed_dependency_proof"):
        if guards.get(guard) is not True:
            raise ValueError(f"Remix {remix_id} failed guard {guard}")

    dossier = copy.deepcopy(campaign_by_id[source_id])
    layer_by_id = {str(layer.get("layer_id", "")): layer for layer in records(dossier.get("map_layers")) if isinstance(layer, dict)}
    for layer_id, patch in (changed.get("initial_primitive_state") or {}).items():
        if layer_id not in layer_by_id:
            raise ValueError(f"Remix {remix_id} missing layer {layer_id}")
        initial = layer_by_id[layer_id].setdefault("initial_primitives", {})
        for key, value in (patch or {}).items():
            initial[str(key)] = copy.deepcopy(value)

    agents = {str(row.get("agent_id", "")): row for row in records(dossier.get("agents")) if isinstance(row, dict)}
    for agent_id, node_id in (changed.get("agent_start_nodes") or {}).items():
        if agent_id not in agents:
            raise ValueError(f"Remix {remix_id} missing agent {agent_id}")
        agents[agent_id]["start_node_or_cell"] = str(node_id)
    for agent_id, semantic_target in (changed.get("semantic_target_assignments") or {}).items():
        if agent_id not in agents:
            raise ValueError(f"Remix {remix_id} missing agent {agent_id}")
        agents[agent_id]["semantic_target"] = str(semantic_target)

    for cell_id, jurisdiction_id in (changed.get("jurisdiction_initial_ownership") or {}).items():
        owner_layer = next((layer for layer in records(dossier.get("map_layers")) if cell_id in record_ids(layer.get("cells"), "cell_id")), None)
        if owner_layer is None:
            raise ValueError(f"Remix {remix_id} missing cell {cell_id}")
        owner_layer.setdefault("initial_primitives", {}).setdefault("jurisdiction_by_cell", {})[cell_id] = str(jurisdiction_id)

    selection = changed.get("objective_selection") or {}
    if selection:
        required = list(selection.get("required_family_ids") or [])
        if not required:
            raise ValueError(f"Remix {remix_id} has empty objective_selection")
        for field in ("objectives", "protected_invariants"):
            for contract in records(dossier.get(field)):
                if isinstance(contract, dict):
                    contract["required"] = str(contract.get("family_id", "")) in required

    dossier["dossier_id"] = remix_id
    dossier.pop("content_hash", None)
    dossier["source_substrate_id"] = source_id
    dossier["runtime_materialized_remix"] = True
    dossier["remix_changed_inputs"] = copy.deepcopy(changed)
    return dossier


def analyze(dossier: dict, scope: str, binding: dict) -> dict:
    dossier_id = str(dossier.get("dossier_id", ""))
    blockers: list[str] = []
    node_layers: dict[str, list[str]] = {}
    layer_by_id: dict[str, dict] = {}
    editable_family_by_id: dict[str, str] = {}

    for layer in records(dossier.get("map_layers")):
        if not isinstance(layer, dict):
            continue
        layer_id = str(layer.get("layer_id", ""))
        layer_by_id[layer_id] = layer
        for node in records(layer.get("nodes")):
            node_id = str(node.get("node_id", ""))
            node_layers.setdefault(node_id, []).append(layer_id)
        editable_family_by_id.update({str(k): str(v) for k, v in (layer.get("editable_candidate_family_by_id") or {}).items()})

        cells = record_ids(layer.get("cells"), "cell_id")
        if cells:
            node_cell = binding.get("node_cell_id") or {}
            for node in records(layer.get("nodes")):
                node_id = str(node.get("node_id", ""))
                mapped = str(node_cell.get(node_id, ""))
                if not mapped:
                    blockers.append(f"node_cell_binding_missing:{node_id}")
                elif mapped not in cells:
                    blockers.append(f"node_cell_binding_unknown_cell:{node_id}:{mapped}")

    border_bindings = binding.get("border_candidates") or {}
    zone_bindings = binding.get("restricted_zone_candidates") or {}
    landmark_ids = record_ids(dossier.get("landmarks"), "landmark_id")
    for candidate_id, family in sorted(editable_family_by_id.items()):
        if family == "border":
            row = border_bindings.get(candidate_id)
            if not isinstance(row, dict) or not row.get("cell_id") or not row.get("target_jurisdiction_id"):
                blockers.append(f"border_binding_missing:{candidate_id}")
        elif family == "restricted_zone":
            row = zone_bindings.get(candidate_id)
            if not isinstance(row, dict) or not row.get("cell_id") or not row.get("policy_id"):
                blockers.append(f"zone_binding_missing:{candidate_id}")
        elif family == "landmark" and candidate_id not in landmark_ids:
            blockers.append(f"landmark_candidate_missing:{candidate_id}")

    explicit_agent_layers = binding.get("agent_layer_by_id") or {}
    for agent in records(dossier.get("agents")):
        if not isinstance(agent, dict):
            continue
        agent_id = str(agent.get("agent_id", ""))
        start_id = str((binding.get("agent_start_node_by_id") or {}).get(agent_id, agent.get("start_node_or_cell", "")))
        owners = node_layers.get(start_id, [])
        if agent_id in explicit_agent_layers:
            if str(explicit_agent_layers[agent_id]) not in layer_by_id:
                blockers.append(f"agent_explicit_layer_unknown:{agent_id}")
        elif len(owners) != 1:
            blockers.append(f"agent_layer_ambiguous:{agent_id}:{start_id}")

    for relation in records(dossier.get("linked_authority_relations")):
        if not isinstance(relation, dict):
            continue
        source_layer = str(relation.get("source_layer_id", ""))
        fact_id = str(relation.get("source_fact_id", ""))
        layer = layer_by_id.get(source_layer)
        if layer is None:
            blockers.append(f"linked_source_layer_missing:{source_layer}")
            continue
        resolvable = False
        if fact_id in editable_family_by_id:
            family = editable_family_by_id[fact_id]
            if family == "border":
                resolvable = fact_id in border_bindings
            elif family == "restricted_zone":
                resolvable = fact_id in zone_bindings
            else:
                resolvable = True
        if fact_id in record_ids(layer.get("candidate_road_edges"), "edge_id"):
            resolvable = True
        if fact_id in record_ids(layer.get("candidate_water_edges"), "edge_id"):
            resolvable = True
        for slot in records(layer.get("crossing_slots")):
            if isinstance(slot, dict) and str(slot.get("bridge_candidate_id", "")) == fact_id:
                resolvable = True
        layer_slot_ids = record_ids(layer.get("landmark_slots"), "landmark_slot_id")
        for landmark in records(dossier.get("landmarks")):
            if isinstance(landmark, dict) and str(landmark.get("landmark_id", "")) == fact_id and str(landmark.get("slot_id", "")) in layer_slot_ids:
                resolvable = True
        if not resolvable:
            initial_facts = (layer.get("initial_primitives") or {}).get("authoritative_linked_facts") or {}
            if fact_id not in initial_facts:
                blockers.append(f"linked_source_fact_unbound:{source_layer}:{fact_id}")

    blockers = sorted(set(blockers))
    return {
        "dossier_id": dossier_id,
        "source_substrate_id": str(dossier.get("source_substrate_id", "")),
        "scope": scope,
        "status": "READY_FOR_RUNTIME_CAPTURE" if not blockers else "BLOCKED_RUNTIME_BINDING",
        "blockers": blockers,
        "layer_count": len(records(dossier.get("map_layers"))),
        "agent_count": len(records(dossier.get("agents"))),
        "editable_families": sorted(set(str(x) for x in records(dossier.get("editable_primitive_permissions")))),
        "linked_relation_count": len(records(dossier.get("linked_authority_relations"))),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output")
    args = parser.parse_args()

    registry = load(REGISTRY)
    bindings_doc = load(BINDINGS)
    protocols = load(PROTOCOLS)
    binding_by_id = bindings_doc.get("dossiers") or {}
    rows = []
    dossier_by_id: dict[str, dict] = {}
    campaign_by_id: dict[str, dict] = {}

    for entry in registry.get("campaign", []):
        dossier = load(res_path(str(entry["path"])))
        dossier_id = str(dossier.get("dossier_id", ""))
        campaign_by_id[dossier_id] = dossier
        dossier_by_id[dossier_id] = dossier
        rows.append(analyze(dossier, "campaign", binding_by_id.get(dossier_id) or {}))
    for entry in registry.get("demo", []):
        dossier = load(res_path(str(entry["path"])))
        dossier_id = str(dossier.get("dossier_id", ""))
        dossier_by_id[dossier_id] = dossier
        rows.append(analyze(dossier, "demo", binding_by_id.get(dossier_id) or {}))
    for entry in registry.get("remixes", []):
        overlay = load(res_path(str(entry["path"])))
        dossier = materialize_remix(overlay, campaign_by_id)
        dossier_id = str(dossier.get("dossier_id", ""))
        source_id = str(dossier.get("source_substrate_id", ""))
        dossier_by_id[dossier_id] = dossier
        rows.append(analyze(dossier, "remix", binding_by_id.get(dossier_id) or binding_by_id.get(source_id) or {}))

    rows.sort(key=lambda row: row["dossier_id"])
    ready = [row["dossier_id"] for row in rows if row["status"] == "READY_FOR_RUNTIME_CAPTURE"]
    blocked = [row["dossier_id"] for row in rows if row["status"] != "READY_FOR_RUNTIME_CAPTURE"]
    if len(rows) != 57:
        raise SystemExit(f"Expected 57 shippable dossiers, got {len(rows)}")

    p = protocols["protocols"]
    protocol_sets = {
        "E3": list(p["E3"]["representative_dossiers"]),
        "E4": sorted({item for window in p["E4"]["windows"].values() for item in window}),
        "E5": sorted([dossier_id for dossier_id, dossier in dossier_by_id.items() if dossier_id.startswith("D") and len(records(dossier.get("map_layers"))) >= 3]),
        "E6": list(p["E6"]["representative_dossiers"]),
        "E9": [f"REMIX{i:02d}" for i in range(1, 13)],
    }
    protocol_readiness = {}
    ready_set = set(ready)
    for gate_id, ids in protocol_sets.items():
        protocol_readiness[gate_id] = {
            "selected": ids,
            "ready": [item for item in ids if item in ready_set],
            "blocked": [item for item in ids if item not in ready_set],
        }

    result = {
        "schema_version": 1,
        "evidence_kind": "PHASE12G_RUNTIME_ACQUISITION_PRECONDITION_NOT_GATE_OUTCOME",
        "counts": {"total": len(rows), "ready": len(ready), "blocked": len(blocked)},
        "ready_ids": ready,
        "blocked_ids": blocked,
        "protocol_readiness": protocol_readiness,
        "rows": rows,
    }
    text = json.dumps(result, indent=2, sort_keys=True)
    if args.output:
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text + "\n", encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
