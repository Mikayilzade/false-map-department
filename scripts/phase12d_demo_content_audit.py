#!/usr/bin/env python3
from __future__ import annotations
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEMO_DIR = ROOT / "content/demo"
REGISTRY = ROOT / "content/registry.json"
MAPPING = DEMO_DIR / "demo_to_full_mapping.json"
DEMO_IDS = [f"DEMO{i:02d}" for i in range(1, 6)]
EXPECTED_PERMISSIONS = {
    "DEMO01": ["road"],
    "DEMO02": ["road"],
    "DEMO03": ["bridge"],
    "DEMO04": ["road", "bridge"],
    "DEMO05": ["road", "border"],
}
EXCLUDED_EDITABLE = {"restricted_zone", "landmark", "waterway"}
EXCLUDED_ARCHETYPE_PREFIXES = ("A6_", "A7_", "A8_", "A9_", "A10_")

def canon(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)

def fail(message):
    raise SystemExit(f"PHASE12D DEMO FAIL: {message}")

def verify_hash(obj, field, label):
    body = dict(obj)
    declared = body.pop(field, "")
    actual = hashlib.sha256(canon(body).encode()).hexdigest()
    if declared != actual:
        fail(f"{label} {field} mismatch")

def main():
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    verify_hash(registry, "registry_hash", "registry")
    demo_entries = registry.get("demo", [])
    if [entry.get("dossier_id") for entry in demo_entries] != DEMO_IDS:
        fail("registry demo sequence must be exact DEMO01-DEMO05")
    if registry.get("demo_import_mapping_path") != "res://content/demo/demo_to_full_mapping.json":
        fail("registry must point to versioned production demo import mapping")

    taught = set()
    seen = set()
    for index, demo_id in enumerate(DEMO_IDS, 1):
        path = DEMO_DIR / f"{demo_id}.json"
        if not path.exists():
            fail(f"{demo_id} missing")
        dossier = json.loads(path.read_text(encoding="utf-8"))
        verify_hash(dossier, "content_hash", demo_id)
        if dossier.get("dossier_id") != demo_id:
            fail(f"{demo_id} identity mismatch")
        if dossier.get("editable_primitive_permissions") != EXPECTED_PERMISSIONS[demo_id]:
            fail(f"{demo_id} demo teaching permissions changed")
        if EXCLUDED_EDITABLE.intersection(dossier.get("editable_primitive_permissions", [])):
            fail(f"{demo_id} exposes a frozen demo-excluded editable primitive")
        if dossier.get("linked_authority_relations"):
            fail(f"{demo_id} must not contain linked authority")
        if len(dossier.get("map_layers", [])) != 1:
            fail(f"{demo_id} must remain one-layer demo content")
        if len(dossier.get("agents", [])) > 4:
            fail(f"{demo_id} exceeds four demo agent silhouettes")
        if int(dossier.get("stability_required_cycles", 0)) > 1:
            fail(f"{demo_id} exceeds demo Stability ceiling")
        for agent in dossier.get("agents", []):
            if str(agent.get("archetype_id", "")).startswith(EXCLUDED_ARCHETYPE_PREFIXES):
                fail(f"{demo_id} uses a frozen demo-excluded agent archetype")
        metadata = dossier.get("validation_metadata", {})
        if int(metadata.get("demo_sequence_index", 0)) != index:
            fail(f"{demo_id} sequence index mismatch")
        budget = metadata.get("causal_presentation_budget", {})
        if budget.get("max_material_nodes", 99) > 5 or budget.get("max_visible_sibling_branches", 99) > 2 or not budget.get("all_required_chains_compressible", False):
            fail(f"{demo_id} causal budget invalid")
        layers = dossier.get("map_layers", [])
        layer = layers[0]
        editable = layer.get("editable_candidates", [])
        focus = metadata.get("focus_graph_by_layer", {}).get(layer.get("layer_id"), {})
        if focus.get("required_focusable_candidate_ids") != editable:
            fail(f"{demo_id} focus graph must cover every authored editable candidate")
        if set(focus.get("neighbors_by_candidate_id", {})) != set(editable):
            fail(f"{demo_id} focus graph source set mismatch")
        for prerequisite in dossier.get("prerequisite_dossier_ids", []):
            if prerequisite not in seen:
                fail(f"{demo_id} prerequisite is not an earlier demo node: {prerequisite}")
        for tag in dossier.get("required_tutorial_tags", []):
            if tag not in taught:
                fail(f"{demo_id} requires untaught demo tag: {tag}")
        solution = metadata.get("known_solution_envelope", {})
        if not solution.get("baseline_valid") or not solution.get("all_required_predicates_true") or not solution.get("all_required_edits_structurally_legal"):
            fail(f"{demo_id} known solution proof incomplete")
        family_by_candidate = layer.get("editable_candidate_family_by_id", {})
        for command in solution.get("solution_commands", []):
            if command.get("layer_id") != layer.get("layer_id"):
                fail(f"{demo_id} solution references wrong layer")
            family = command.get("primitive_family")
            if family not in dossier.get("editable_primitive_permissions", []):
                fail(f"{demo_id} solution uses non-editable family")
            for candidate in command.get("candidate_ids", []):
                if candidate not in editable or family_by_candidate.get(candidate) != family:
                    fail(f"{demo_id} solution candidate/family mismatch: {candidate}")
        seen.add(demo_id)
        taught.update(dossier.get("tutorial_tags", []))

    demo05 = json.loads((DEMO_DIR / "DEMO05.json").read_text(encoding="utf-8"))
    relation = demo05.get("validation_metadata", {}).get("demo_campaign_relation", {})
    if relation.get("campaign_dossier_id") != "D05" or not relation.get("same_border_semantic_lesson"):
        fail("DEMO05 must explicitly record the shared D05 border lesson")
    if relation.get("baseline_clear_equivalence_inferred") is not False:
        fail("DEMO05 must explicitly reject inferred D05 clear equivalence")

    mapping = json.loads(MAPPING.read_text(encoding="utf-8"))
    verify_hash(mapping, "mapping_hash", "demo mapping")
    if mapping.get("mapping_schema_version") != 1 or not mapping.get("mapping_version"):
        fail("demo mapping must be versioned")
    mappings = mapping.get("demo_to_full_mapping", {})
    if sorted(mappings) != DEMO_IDS:
        fail("demo mapping must explicitly cover exact DEMO01-DEMO05")
    for index, demo_id in enumerate(DEMO_IDS, 1):
        row = mappings[demo_id]
        if row.get("target_campaign_dossier_id") != f"D{index:02d}":
            fail(f"{demo_id} target campaign relation must be explicit")
        if row.get("baseline_clear_equivalent") is not False:
            fail(f"{demo_id} must not claim unproven campaign-clear equivalence")
        if "full_clear_record" in row:
            fail(f"{demo_id} non-equivalent mapping must not carry a full clear record")
        if not isinstance(row.get("tutorial_tags"), list):
            fail(f"{demo_id} mapping tutorial tags missing")
        if not isinstance(row.get("mastery_equivalences_by_demo_mastery_id"), dict):
            fail(f"{demo_id} mapping mastery table missing")
    if mappings["DEMO05"].get("target_campaign_dossier_id") != "D05" or mappings["DEMO05"].get("baseline_clear_equivalent") is not False:
        fail("DEMO05 must not auto-clear D05 merely by ID/name/lesson")

    registry_service = (ROOT / "src/application/content_registry.gd").read_text(encoding="utf-8")
    test = (ROOT / "tests/test_demo_content_runner.gd").read_text(encoding="utf-8")
    runtime = (ROOT / "scripts/run_phase12a_runtime.sh").read_text(encoding="utf-8")
    for marker in ["available_demo_ids", "demo_import_mapping_hash_mismatch", "demo_import_mapping_identity_invalid", "content_kind"]:
        if marker not in registry_service:
            fail(f"content registry missing demo marker: {marker}")
    for marker in [
        "Demo registry must contain exact DEMO01-DEMO05",
        "DEMO05 must not auto-clear campaign D05",
        "Repeated production demo import receipt must be idempotent",
        "Demo import must transfer only explicit compatible tutorial tags/settings",
    ]:
        if marker not in test:
            fail(f"demo headless acceptance missing marker: {marker}")
    if "phase12d-demo-content-contract" not in runtime or "test_demo_content_runner.gd" not in runtime:
        fail("aggregate runtime is not wired to the demo population gate")
    print("Phase 12D demo content audit: PASS (DEMO01-DEMO05 + explicit versioned import mapping)")

if __name__ == "__main__":
    main()
