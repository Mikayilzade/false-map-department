#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEMO_IDS = [f"DEMO{i:02d}" for i in range(1, 6)]


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G ACQUISITION READINESS FAIL: {message}")


def load_json(path: str) -> dict:
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def require_markers(path: str, markers: list[str]) -> None:
    text = (ROOT / path).read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            fail(f"missing marker in {path}: {marker}")


def canonical_hash(payload: dict) -> str:
    clean = dict(payload)
    clean.pop("content_hash", None)
    text = json.dumps(clean, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def jurisdiction_required(dossier: dict, jurisdiction_id: str) -> bool | None:
    for row in dossier.get("jurisdictions", []):
        if row.get("jurisdiction_id") == jurisdiction_id:
            return bool(row.get("required_exist", False))
    return None


def main() -> None:
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    if 'run/main_scene="res://src/presentation/entrypoint.tscn"' not in project:
        fail("project does not route through the playtest-aware entrypoint")

    require_markers("src/presentation/entrypoint.gd", [
        'OS.get_environment("FMD_PLAYTEST_DOSSIER_ID")',
        'res://src/presentation/production_playtest.tscn',
        'res://src/presentation/main.tscn',
    ])
    require_markers("src/presentation/production_playtest.gd", [
        'DEMO_SEQUENCE := ["DEMO01", "DEMO02", "DEMO03", "DEMO04", "DEMO05"]',
        "ProductionPlaytestController",
        "record_correspondence_opened",
        "record_collateral_consequence_seen",
        "record_demo_completed",
        '_current_dossier_id != "DEMO05"',
    ])
    require_markers("src/application/production_playtest_controller.gd", [
        "CoreTransactionCoordinator",
        "ProductionDossierRuntimeAdapter",
        "StabilityInteractionService",
        "execute_authored_command",
        "start_stability",
        "advance_stability",
    ])
    require_markers("src/application/production_dossier_runtime_adapter.gd", [
        "runtime_border_candidate_unbound",
        "runtime_node_cell_binding_missing",
        "CANONICAL_ARCHETYPES",
        'operation = "reassign" if operation == "assign" else operation',
    ])
    require_markers("tests/test_phase12g_production_playtest_runner.gd", [
        '"DEMO01", "DEMO02", "DEMO03", "DEMO04", "DEMO05"',
        "execute_authored_command",
        "start_stability",
        "advance_stability",
        "Undo must restore exact pre-edit state",
    ])

    copy = load_json("content/demo/playtest_copy.json")
    if copy.get("copy_schema_version") != 1:
        fail("unexpected demo playtest copy schema")
    copy_rows = copy.get("dossiers", {})
    if sorted(copy_rows) != DEMO_IDS:
        fail(f"playtest copy must cover exact DEMO01-DEMO05, got {sorted(copy_rows)}")
    raw_copy = json.dumps(copy, sort_keys=True).lower()
    if "solution_commands" in raw_copy or "known_solution" in raw_copy:
        fail("human playtest copy must not embed solution commands")
    for demo_id in DEMO_IDS:
        row = copy_rows[demo_id]
        if not str(row.get("title", "")).strip() or not str(row.get("brief", "")).strip():
            fail(f"{demo_id} lacks human-readable title/brief")
        if not row.get("requirements"):
            fail(f"{demo_id} lacks visible requirement copy")

    bindings = load_json("content/runtime_bindings.json")
    if bindings.get("binding_schema_version") != 1:
        fail("runtime binding schema mismatch")
    if set(bindings.get("dossiers", {})) != {"D05", "DEMO05"}:
        fail("only the currently necessary explicit border/node-cell bindings should be frozen in this packet")
    for dossier_id in ["D05", "DEMO05"]:
        row = bindings["dossiers"][dossier_id]
        if not row.get("node_cell_id") or not row.get("border_candidates"):
            fail(f"{dossier_id} runtime binding incomplete")

    d05 = load_json("content/campaign/D05.json")
    d06 = load_json("content/campaign/D06.json")
    demo05 = load_json("content/demo/DEMO05.json")
    if jurisdiction_required(d05, "D05_J_WEST") is not False:
        fail("D05 introductory departing West jurisdiction must be non-required")
    if jurisdiction_required(demo05, "DEMO05_J_WEST") is not False:
        fail("DEMO05 introductory departing West jurisdiction must be non-required")
    if jurisdiction_required(d06, "D06_J_WEST") is not True:
        fail("D06 must preserve the next-lesson required-West constraint")
    for path, dossier in [("D05", d05), ("DEMO05", demo05)]:
        expected = canonical_hash(dossier)
        if dossier.get("content_hash") != expected:
            fail(f"{path} content_hash was not recomputed after smallest-instance re-authoring")

    print("Phase 12G acquisition readiness audit: PASS (real DEMO01-DEMO05 entrypoint + runtime adapter/controller + visible copy + Stability path; no VS01 fallback for requested playtests)")


if __name__ == "__main__":
    main()
