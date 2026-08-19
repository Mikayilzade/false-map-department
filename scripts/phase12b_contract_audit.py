#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

DIRECT_VARIANT_GET_INFERENCE = re.compile(
    r'^\s*var\s+\w+\s*:=\s*[A-Za-z_]\w*(?:\[[^\]]+\])?\.get\(',
    re.MULTILINE,
)

def fail(message: str) -> None:
    raise SystemExit(f"PHASE12B CONTRACT FAIL: {message}")

def canonical_json(value) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)

def main() -> None:
    session = (ROOT / "src/application/slice_session.gd").read_text(encoding="utf-8")
    controller = (ROOT / "src/application/slice_interaction_controller.gd").read_text(encoding="utf-8")
    causal = (ROOT / "src/application/slice_causal_presenter.gd").read_text(encoding="utf-8")
    persistence = (ROOT / "src/application/persistence_service.gd").read_text(encoding="utf-8")
    active_persistence = (ROOT / "src/application/slice_active_dossier_persistence.gd").read_text(encoding="utf-8")
    presentation = (ROOT / "src/presentation/main.gd").read_text(encoding="utf-8")
    scene = (ROOT / "src/presentation/main.tscn").read_text(encoding="utf-8")
    input_actions = (ROOT / "src/application/input_actions.gd").read_text(encoding="utf-8")
    runtime_wrapper = (ROOT / "scripts/run_phase12a_runtime.sh").read_text(encoding="utf-8")
    definition = json.loads((ROOT / "content/vertical_slice/VS01.json").read_text(encoding="utf-8"))

    required_history_markers = [
        "pre_checkpoint", "post_checkpoint", "pre_state_hash", "post_state_hash",
        "func undo()", "func redo()", "_history.resize(_history_cursor)",
        "redo_checkpoint_not_byte_equivalent", "func submit_command(",
        "CommandGate.validate_pre_state",
        "func export_persistence_state()", "func restore_persistence_state(",
        "persistence_history_chain_checkpoint_mismatch",
        "persistence_cursor_checkpoint_mismatch",
    ]
    for marker in required_history_markers:
        if marker not in session:
            fail(f"missing history/persistence contract marker: {marker}")

    if "res://src/presentation" in session or "res://src/presentation" in controller or "res://src/presentation" in active_persistence:
        fail("application services may not depend on presentation")
    for forbidden in ["SliceSession", "PlayerCommand", "MicroSliceEngine", "attempt_road_toggle"]:
        if forbidden in presentation:
            fail(f"presentation bypasses application interaction boundary via {forbidden}")
    if "SliceInteractionController" not in presentation:
        fail("presentation is not wired through application interaction controller")
    if "SliceViewSnapshot" not in controller or "SliceCausalPresenter" not in controller:
        fail("interaction controller must expose read-only snapshot + causal presentation data")
    if "MAX_DEFAULT_NODES := 5" not in causal:
        fail("causal ribbon default five-node budget missing")

    required_controller_persistence = [
        '"selected_edge_id"', '"command_sequence"', '"session"',
        "func export_persistence_state()", "func restore_persistence_state(",
    ]
    for marker in required_controller_persistence:
        if marker not in controller:
            fail(f"missing interaction persistence marker: {marker}")

    required_active_persistence = [
        'DOCUMENT_TYPE := "active_session"',
        '"dossier_id"', '"content_schema_version"', '"dossier_content_version"',
        '"ruleset_version"', '"content_hash"', '"canonical_hash_version"',
        "PersistenceService.new", "controller.export_persistence_state()",
        "controller.restore_persistence_state",
        "active_session_content_identity_mismatch",
    ]
    for marker in required_active_persistence:
        if marker not in active_persistence:
            fail(f"missing active-session persistence marker: {marker}")

    for marker in ["func load_primary(", "save_envelope_invalid", "canonical_hash_version"]:
        if marker not in persistence:
            fail(f"generic persistence boundary missing marker: {marker}")

    required_actions = [
        "fmd_select", "fmd_inspect", "fmd_undo", "fmd_redo",
        "fmd_previous_candidate", "fmd_next_candidate",
        "JOY_BUTTON_A", "JOY_BUTTON_X", "JOY_BUTTON_DPAD_LEFT",
        "JOY_BUTTON_DPAD_RIGHT", "JOY_BUTTON_LEFT_SHOULDER",
        "JOY_BUTTON_RIGHT_SHOULDER",
    ]
    for marker in required_actions:
        if marker not in input_actions:
            fail(f"missing early multi-device action marker: {marker}")

    if "OFFICIAL MAP" not in scene or "DERIVED WORLD" not in scene:
        fail("dual map/world presentation contract missing")
    if "RoadList" not in scene or "CausalRibbon" not in scene or "HistoryControls" not in scene:
        fail("playable road selection / causal / history surfaces missing")

    edge_ids = sorted(definition["road_edges"])
    if edge_ids != ["E12", "E13", "E24", "E34", "EP"]:
        fail("vertical-slice road candidates drifted")
    if definition.get("layer_id") != "L1":
        fail("vertical slice must expose exact semantic layer_id L1")
    if definition["agents"]["AG01"]["archetype"] != "A1_DIRECT_COURIER":
        fail("vertical slice must use the frozen A1 Direct Courier")
    if definition["reaction_beats_after_edit"] != 1:
        fail("vertical slice must retain one bounded reaction beat")

    for identity_key in ["dossier_id", "content_schema_version", "dossier_content_version", "ruleset_version", "content_hash"]:
        if identity_key not in definition:
            fail(f"vertical slice missing immutable content identity: {identity_key}")
    canonical_definition = dict(definition)
    declared_hash = canonical_definition.pop("content_hash")
    computed_hash = hashlib.sha256(canonical_json(canonical_definition).encode("utf-8")).hexdigest()
    if declared_hash != computed_hash:
        fail("VS01 declared content_hash does not match canonical content")

    if "phase12b-persistence-suite" not in runtime_wrapper or "test_slice_persistence_runner.gd" not in runtime_wrapper:
        fail("runtime wrapper does not execute active-session persistence/loop suite")

    persistence_test = (ROOT / "tests/test_slice_persistence_runner.gd").read_text(encoding="utf-8")
    for marker in [
        "byte-equivalent canonical gameplay hash",
        "can_redo",
        "save_envelope_invalid",
        "content_identity_hash_mismatch",
        "Strategically harmful but legal edit must commit",
        "complete the clear condition",
    ]:
        if marker not in persistence_test:
            fail(f"persistence/loop acceptance coverage missing marker: {marker}")

    gdscript_roots = [ROOT / "src/domain", ROOT / "src/application", ROOT / "src/presentation"]
    for gdscript_root in gdscript_roots:
        for path in sorted(gdscript_root.glob("*.gd")):
            text = path.read_text(encoding="utf-8")
            match = DIRECT_VARIANT_GET_INFERENCE.search(text)
            if match:
                line_number = text.count("\n", 0, match.start()) + 1
                fail(
                    f"direct Variant inference from Dictionary.get in "
                    f"{path.relative_to(ROOT)}:{line_number}; add an explicit type"
                )

    print("Phase 12B contract audit: PASS")

if __name__ == "__main__":
    main()
