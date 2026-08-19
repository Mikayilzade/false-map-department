#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(f"PRECHECK FAIL: {message}")


def canonical_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def main() -> None:
    required = [
        ROOT / "project.godot",
        ROOT / ".godot-version",
        ROOT / "src/domain/canonical_json.gd",
        ROOT / "src/domain/stable_id.gd",
        ROOT / "src/domain/map_authority_state.gd",
        ROOT / "src/domain/dossier_session_state.gd",
        ROOT / "src/application/player_command.gd",
        ROOT / "src/application/command_gate.gd",
        ROOT / "src/application/content_loader.gd",
        ROOT / "src/presentation/main.tscn",
        ROOT / "tests/test_runner.gd",
        ROOT / "tests/fixtures/tiny_dossier.json",
    ]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    if missing:
        fail("missing files: " + ", ".join(missing))

    if (ROOT / ".godot-version").read_text(encoding="utf-8").strip() != "4.7.1-stable":
        fail("engine pin must be exactly 4.7.1-stable")

    fixture = json.loads((ROOT / "tests/fixtures/tiny_dossier.json").read_text(encoding="utf-8"))
    if fixture.get("dossier_id") != "BOOT01":
        fail("tiny fixture dossier_id changed unexpectedly")
    if len(fixture.get("map_layers", [])) > 4:
        fail("fixture exceeds four-layer ceiling")

    canonical = canonical_json(fixture)
    reordered = dict(reversed(list(fixture.items())))
    if canonical != canonical_json(reordered):
        fail("canonical JSON is not key-order independent")
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    if len(digest) != 64:
        fail("SHA-256 digest malformed")

    command_source = (ROOT / "src/application/player_command.gd").read_text(encoding="utf-8")
    primitives = ["road", "bridge", "border", "waterway", "landmark", "restricted_zone"]
    if any(f'"{primitive}"' not in command_source for primitive in primitives):
        fail("semantic command does not expose all six frozen primitive families")
    if '"seventh_' in command_source:
        fail("unexpected seventh primitive marker")

    session_source = (ROOT / "src/domain/dossier_session_state.gd").read_text(encoding="utf-8")
    required_session_fields = [
        "content_version", "session_revision", "map_state_by_layer", "agent_state_by_id",
        "objective_state_by_id", "invariant_state_by_id", "stability_state",
        "intervention_footprint_state", "last_transaction_id", "history_cursor",
        "causal_graph_current", "completion_state",
    ]
    if any(field not in session_source for field in required_session_fields):
        fail("DossierSessionState is missing a canonical runtime field")

    map_source = (ROOT / "src/domain/map_authority_state.gd").read_text(encoding="utf-8")
    required_map_fields = [
        "active_road_edge_ids", "active_bridge_slot_ids", "active_water_edge_ids",
        "border_ownership_by_cell", "landmark_semantic_labels",
        "restricted_zone_cells_by_policy", "authoritative_linked_facts",
    ]
    if any(field not in map_source for field in required_map_fields):
        fail("MapAuthorityState is missing an authoritative map field")

    gate_source = (ROOT / "src/application/command_gate.gd").read_text(encoding="utf-8")
    for token in ["expected_pre_state_hash", "current_pre_state_hash", "stale_pre_state"]:
        if token not in gate_source:
            fail("command pre-state gate is incomplete")

    bootstrap_session = {
        "content_version": {
            "canonical_hash_version": 1,
            "content_hash": "fixture-content-hash",
            "content_schema_version": 1,
            "dossier_content_version": 1,
            "dossier_id": "BOOT01",
            "ruleset_version": 1,
        },
        "session_revision": 0,
        "map_state_by_layer": {
            "L1": {
                "active_bridge_slot_ids": [],
                "active_road_edge_ids": ["E01", "E02"],
                "active_water_edge_ids": [],
                "authoritative_linked_facts": {},
                "border_ownership_by_cell": {"C01": "J01"},
                "landmark_semantic_labels": {"LM01": "hospital"},
                "layer_id": "L1",
                "restricted_zone_cells_by_policy": {},
            }
        },
        "agent_state_by_id": {},
        "objective_state_by_id": {},
        "invariant_state_by_id": {},
        "stability_state": {},
        "intervention_footprint_state": {},
        "last_transaction_id": "",
        "history_cursor": 0,
        "causal_graph_current": {},
        "completion_state": "active",
    }
    session_digest = hashlib.sha256(canonical_json(bootstrap_session).encode("utf-8")).hexdigest()
    expected_session_digest = "c7e3412436a0182737ff67470b015c4d057326ca9475abc565cbe53232536751"
    if session_digest != expected_session_digest:
        fail("bootstrap session canonical hash fixture changed")

    for source in (ROOT / "src/domain").glob("*.gd"):
        text = source.read_text(encoding="utf-8")
        if "res://src/presentation" in text:
            fail(f"domain depends on presentation: {source.name}")

    print("FMD bootstrap preflight: PASS")
    print(f"fixture_sha256={digest}")
    print(f"session_sha256={session_digest}")


if __name__ == "__main__":
    main()
