#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

FIRST_GATES = ("E1", "E2", "E11")
MATURE_GATES = ("E3", "E4", "E5", "E6", "E9", "E10")
PREDICTION_PROMPT_ID = "DEMO02_PRE_EDIT_SECOND_ORDER_01"
RECEIPT_SCHEMA = "fmd.phase12g.field-kit-finalization-receipt.v1"
E4_ASSESSMENT_VALUES = {"distinct", "mixed", "predominantly_same_trick"}
MATURE_REQUIRED_FIELDS = {
    "E3": ["tester_id", "dossier_id", "method", "completion_seconds", "completed", "rule_knowledge_confirmed"],
    "E4": ["tester_id", "window_id", "dossier_ids", "same_trick_assessment", "notes"],
    "E5": ["tester_id", "dossier_id", "requirement_id", "identified_authority_layer", "correct", "tutorial_recall_used"],
    "E6": ["tester_id", "dossier_id", "requirement_id", "answered_cause", "used_raw_debug_log", "correct"],
    "E9": ["tester_id", "remix_id", "source_dossier_id", "described_as_changed_causal_problem", "notes"],
    "E10": ["tester_id", "agent_a", "agent_b", "scenario_id", "predicted_distinction", "correct"],
}


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G OFFLINE FIELD KIT FINALIZE FAIL: {message}")


def load_json(path: Path) -> dict:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"{path}: unreadable JSON: {exc}")
    if not isinstance(payload, dict):
        fail(f"{path}: expected JSON object")
    return payload


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_sha256(payload: object) -> str:
    text = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def e3_outcome_snapshot(rows: list[dict]) -> list[dict]:
    """Freeze only E3 outcome semantics not already in the immutable prepared identity.

    dossier_id/method/counterbalance_order are bound by the field-kit mature packet
    identity fingerprint. The finalization receipt independently freezes the human-
    declared completion outcome/timing so later packet+completed-row edits cannot
    rebound a comparative result by merely refreshing completed-file digests.
    This is a declaration snapshot and is not proof that a human outcome/timing is true.
    """
    snapshot: list[dict] = []
    for index, row in enumerate(rows, start=1):
        completion = row.get("completion_seconds")
        completed = row.get("completed")
        if isinstance(completion, bool) or not isinstance(completion, (int, float)) or float(completion) < 0:
            fail(f"E3 row {index}: completion_seconds must be numeric >= 0")
        if not isinstance(completed, bool):
            fail(f"E3 row {index}: completed must be true/false")
        snapshot.append({
            "completion_seconds": float(completion),
            "completed": completed,
        })
    return snapshot


def e4_outcome_snapshot(rows: list[dict]) -> list[dict]:
    """Freeze only mutable E4 assessment semantics at finalization.

    tester_id/window_id/dossier_ids are already protected by the prepared mature
    packet identity fingerprint. The receipt snapshot binds the observer-declared
    qualitative assessment and notes after observation. It remains declaration-only
    and does not prove that a human actually perceived campaign repetition this way.
    """
    snapshot: list[dict] = []
    for index, row in enumerate(rows, start=1):
        assessment = str(row.get("same_trick_assessment", "")).strip()
        notes = row.get("notes")
        if assessment not in E4_ASSESSMENT_VALUES:
            fail(f"E4 row {index}: same_trick_assessment must be one of {sorted(E4_ASSESSMENT_VALUES)}")
        if not isinstance(notes, str) or not notes.strip():
            fail(f"E4 row {index}: notes must be a non-empty string")
        snapshot.append({
            "same_trick_assessment": assessment,
            "notes": notes,
        })
    return snapshot


def e5_semantic_snapshot(rows: list[dict]) -> list[dict]:
    """Freeze E5 observation scope plus disposition-relevant observer declarations.

    The prepared mature identity already fixes tester_id+dossier_id. requirement_id is
    selected only when an actual requirement is tested, so it is mutable before
    finalization but becomes part of the observed E5 scope. The authority-layer answer,
    correctness declaration and tutorial-recall declaration are likewise finalized here.
    This snapshot is declaration-only and cannot prove human comprehension or correctness.
    """
    snapshot: list[dict] = []
    for index, row in enumerate(rows, start=1):
        requirement_id = str(row.get("requirement_id", "")).strip()
        authority_layer = str(row.get("identified_authority_layer", "")).strip()
        correct = row.get("correct")
        tutorial_recall_used = row.get("tutorial_recall_used")
        if not requirement_id or any(ch.isspace() for ch in requirement_id):
            fail(f"E5 row {index}: requirement_id must be a non-empty stable identifier without whitespace")
        if not authority_layer or any(ch.isspace() for ch in authority_layer):
            fail(f"E5 row {index}: identified_authority_layer must be a non-empty stable identifier without whitespace")
        if not isinstance(correct, bool):
            fail(f"E5 row {index}: correct must be true/false")
        if not isinstance(tutorial_recall_used, bool):
            fail(f"E5 row {index}: tutorial_recall_used must be true/false")
        snapshot.append({
            "requirement_id": requirement_id,
            "identified_authority_layer": authority_layer,
            "correct": correct,
            "tutorial_recall_used": tutorial_recall_used,
        })
    return snapshot


def e6_semantic_snapshot(rows: list[dict]) -> list[dict]:
    """Freeze E6 observation scope plus disposition-relevant observer declarations.

    Prepared mature identity already fixes tester_id+dossier_id. requirement_id is chosen
    at observation time, while answered_cause and correct are human observer declarations.
    used_raw_debug_log must remain false by protocol. This declaration-only snapshot binds
    those mutable fields after finalization without claiming human truth or correctness.
    """
    snapshot: list[dict] = []
    for index, row in enumerate(rows, start=1):
        requirement_id = str(row.get("requirement_id", "")).strip()
        answered_cause = row.get("answered_cause")
        used_raw_debug_log = row.get("used_raw_debug_log")
        correct = row.get("correct")
        if not requirement_id or any(ch.isspace() for ch in requirement_id):
            fail(f"E6 row {index}: requirement_id must be a non-empty stable identifier without whitespace")
        if not isinstance(answered_cause, str) or not answered_cause.strip():
            fail(f"E6 row {index}: answered_cause must be a non-empty observer declaration")
        if used_raw_debug_log is not False:
            fail(f"E6 row {index}: used_raw_debug_log must be false")
        if not isinstance(correct, bool):
            fail(f"E6 row {index}: correct must be true/false")
        snapshot.append({
            "requirement_id": requirement_id,
            "answered_cause": answered_cause,
            "used_raw_debug_log": False,
            "correct": correct,
        })
    return snapshot


def resolve_relative(root: Path, value: object, label: str) -> Path:
    raw = Path(str(value))
    if raw.is_absolute():
        fail(f"{label} must be relative")
    candidate = (root / raw).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        fail(f"{label} escapes owning root")
    return candidate


def verify_kit(kit_root: Path) -> dict:
    manifest = load_json(kit_root / "field-kit-manifest.json")
    verifier_contract = manifest.get("offline_verifier", {})
    if not isinstance(verifier_contract, dict):
        fail("offline verifier contract missing")
    verifier = resolve_relative(kit_root, verifier_contract.get("path", ""), "offline verifier path")
    completed = subprocess.run(
        [sys.executable, str(verifier), "--kit-dir", str(kit_root)],
        cwd=kit_root,
        text=True,
        capture_output=True,
    )
    if completed.returncode != 0:
        fail(f"kit integrity verification failed before finalization: {(completed.stdout + completed.stderr).strip()}")
    try:
        result = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        fail(f"offline verifier returned malformed JSON: {exc}")
    if not isinstance(result, dict) or result.get("status") != "VERIFIED_OFFLINE":
        fail("offline verifier returned unexpected disposition")
    if int(manifest.get("field_kit_version", 0)) >= 5 and result.get("acquisition_build_bytes_verified") is not True:
        fail("v5 field kit did not verify acquisition build bytes")
    return manifest


def require_id(value: object, label: str) -> str:
    text = str(value).strip()
    if not text or any(ch.isspace() for ch in text):
        fail(f"{label} must be a non-empty pseudonymous identifier without whitespace")
    return text


def require_bool(payload: dict, key: str) -> bool:
    value = payload.get(key)
    if not isinstance(value, bool):
        fail(f"observer field {key} must be true/false")
    return value


def require_number(payload: dict, key: str, minimum: float = 0.0) -> float:
    value = payload.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        fail(f"observer field {key} must be numeric")
    number = float(value)
    if number < minimum:
        fail(f"observer field {key} must be >= {minimum}")
    return number


def event_elapsed(telemetry: dict, event_type: str) -> float | None:
    events = telemetry.get("events", [])
    if not isinstance(events, list):
        fail("telemetry events must be an array")
    for raw in events:
        if isinstance(raw, dict) and raw.get("event_type") == event_type:
            value = raw.get("elapsed_seconds")
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                return float(value)
    return None


def first_packet_dir(kit_root: Path, manifest: dict, session_id: str) -> Path:
    section = manifest.get("first_session", {})
    if not isinstance(section, dict):
        fail("first_session section malformed")
    batch_path = resolve_relative(kit_root, section.get("batch_manifest", ""), "first batch manifest")
    batch = load_json(batch_path)
    for packet in batch.get("packets", []):
        if isinstance(packet, dict) and str(packet.get("session_id", "")) == session_id:
            return resolve_relative(batch_path.parent, packet.get("session_dir", ""), "first-session packet path")
    fail(f"first-session packet not found: {session_id}")


def mature_packet_dir(kit_root: Path, manifest: dict, tester_id: str) -> Path:
    section = manifest.get("mature_session", {})
    if not isinstance(section, dict):
        fail("mature_session section malformed")
    batch_path = resolve_relative(kit_root, section.get("batch_manifest", ""), "mature batch manifest")
    batch = load_json(batch_path)
    for packet in batch.get("packets", []):
        if isinstance(packet, dict) and str(packet.get("tester_id", "")) == tester_id:
            return resolve_relative(batch_path.parent, packet.get("packet_dir", ""), "mature-session packet path")
    fail(f"mature-session packet not found: {tester_id}")


def finalize_first(session_dir: Path) -> tuple[dict, list[Path]]:
    session_manifest = load_json(session_dir / "session-manifest.json")
    observer = load_json(session_dir / "observer.json")
    telemetry = load_json(session_dir / "telemetry.json")
    tester_id = require_id(session_manifest.get("tester_id", ""), "tester_id")
    session_id = require_id(session_manifest.get("session_id", ""), "session_id")
    build_id = require_id(session_manifest.get("demo_build_id", ""), "demo_build_id")
    if observer.get("tester_id") != tester_id or observer.get("session_id") != session_id:
        fail("observer identity does not match first-session manifest")
    if telemetry.get("tester_id") != tester_id or telemetry.get("session_id") != session_id or telemetry.get("demo_build_id") != build_id:
        fail("telemetry identity does not match first-session manifest")

    naive = require_bool(observer, "naive")
    e1_success = require_bool(observer, "e1_success")
    e1_time = require_number(observer, "e1_understood_at_seconds")
    packet_completed = require_bool(observer, "e2_packet_completed")
    e2_success = require_bool(observer, "e2_success")
    prompt_id = str(observer.get("e2_prediction_prompt_id", "")).strip()
    if prompt_id != PREDICTION_PROMPT_ID:
        fail(f"e2_prediction_prompt_id must remain {PREDICTION_PROMPT_ID}")

    aha_observed = require_bool(observer, "first_collateral_aha_observed")
    aha_seconds = require_number(observer, "first_collateral_aha_seconds", minimum=-1.0)
    if aha_observed and aha_seconds < 0:
        fail("first_collateral_aha_seconds must be >=0 when an aha was observed")
    if not aha_observed and aha_seconds != -1.0:
        fail("use first_collateral_aha_seconds=-1 when no genuine aha was observed")

    session_end = require_number(observer, "session_end_seconds")
    start_marker = telemetry.get("session_started_ms")
    if isinstance(start_marker, bool) or not isinstance(start_marker, (int, float)):
        fail("telemetry session_started_ms missing/invalid")
    completion_event_seconds = event_elapsed(telemetry, "demo_completed")
    completed = completion_event_seconds is not None
    completion_source = "telemetry_demo_completed" if completed else "observer_session_end"
    completion_seconds = completion_event_seconds if completion_event_seconds is not None else session_end

    rows = {
        "E1": {"schema_version": 1, "gate_id": "E1", "tester_id": tester_id, "naive": naive, "session_id": session_id, "understood_within_seconds": e1_time, "success": e1_success},
        "E2": {"schema_version": 1, "gate_id": "E2", "tester_id": tester_id, "naive": naive, "session_id": session_id, "packet_completed": packet_completed, "prediction_prompt_id": prompt_id, "success": e2_success},
        "E11": {"schema_version": 1, "gate_id": "E11", "tester_id": tester_id, "naive": naive, "demo_build_id": build_id, "start_timestamp": start_marker, "first_collateral_aha_seconds": aha_seconds, "completion_seconds": completion_seconds, "completed": completed},
    }
    paths: list[Path] = []
    for gate_id, row in rows.items():
        path = session_dir / f"completed-{gate_id}.jsonl"
        write_jsonl(path, [row])
        paths.append(path)

    return {
        "kind": "first_session",
        "session_id": session_id,
        "tester_id": tester_id,
        "naive_declared": naive,
        "e1_success_declared": e1_success,
        "e1_understood_at_seconds_declared": e1_time,
        "e2_packet_completed_declared": packet_completed,
        "e11_start_timestamp_finalized": float(start_marker),
        "e11_first_collateral_aha_seconds_declared": aha_seconds,
        "e11_completion_seconds_finalized": float(completion_seconds),
        "e11_completed_finalized": completed,
        "e11_completion_source": completion_source,
        "completed_gates": list(FIRST_GATES),
    }, paths


def field_missing(row: dict, field: str) -> bool:
    if field not in row:
        return True
    value = row[field]
    return value is None or (isinstance(value, str) and not value.strip()) or (isinstance(value, list) and not value)


def finalize_mature(packet_dir: Path) -> tuple[dict, list[Path]]:
    packet = load_json(packet_dir / "observer-packet.json")
    tester_id = require_id(packet.get("tester_id", ""), "tester_id")
    if packet.get("rules_known_before_session") is not True:
        fail("rules_known_before_session must be explicitly true before mature-human rows can be finalized")
    rows_by_gate = packet.get("rows_by_gate", {})
    if not isinstance(rows_by_gate, dict):
        fail("mature rows_by_gate must be an object")
    paths: list[Path] = []
    finalized_e3_outcomes: list[dict] = []
    finalized_e4_outcomes: list[dict] = []
    finalized_e5_semantics: list[dict] = []
    finalized_e6_semantics: list[dict] = []
    for gate_id in MATURE_GATES:
        rows = rows_by_gate.get(gate_id, [])
        if not isinstance(rows, list) or not rows:
            fail(f"{gate_id}: packet has no rows")
        checked: list[dict] = []
        for index, raw in enumerate(rows, start=1):
            if not isinstance(raw, dict):
                fail(f"{gate_id} row {index}: expected object")
            missing = [field for field in MATURE_REQUIRED_FIELDS[gate_id] if field_missing(raw, field)]
            if missing:
                fail(f"{gate_id} row {index}: missing observed fields: {', '.join(missing)}")
            if str(raw.get("tester_id", "")) != tester_id:
                fail(f"{gate_id} row {index}: tester identity mismatch")
            if gate_id == "E3" and raw.get("rule_knowledge_confirmed") is not True:
                fail("E3 rows require rule_knowledge_confirmed=true; the frozen comparison is after rules are known")
            if gate_id == "E6" and raw.get("used_raw_debug_log") is not False:
                fail("E6 rows require used_raw_debug_log=false; raw debug logs are forbidden by protocol")
            item = dict(raw)
            item["rules_known_before_session"] = True
            checked.append(item)
        if gate_id == "E3":
            finalized_e3_outcomes = e3_outcome_snapshot(checked)
        if gate_id == "E4":
            finalized_e4_outcomes = e4_outcome_snapshot(checked)
        if gate_id == "E5":
            finalized_e5_semantics = e5_semantic_snapshot(checked)
        if gate_id == "E6":
            finalized_e6_semantics = e6_semantic_snapshot(checked)
        path = packet_dir / f"completed-{gate_id}.jsonl"
        write_jsonl(path, checked)
        paths.append(path)
    return {
        "kind": "mature_session",
        "tester_id": tester_id,
        "rules_known_before_session_declared": True,
        "e3_finalized_outcome_sha256": canonical_sha256(finalized_e3_outcomes),
        "e3_finalized_row_count": len(finalized_e3_outcomes),
        "e4_finalized_outcome_sha256": canonical_sha256(finalized_e4_outcomes),
        "e4_finalized_row_count": len(finalized_e4_outcomes),
        "e5_finalized_semantic_sha256": canonical_sha256(finalized_e5_semantics),
        "e5_finalized_row_count": len(finalized_e5_semantics),
        "e6_finalized_semantic_sha256": canonical_sha256(finalized_e6_semantics),
        "e6_finalized_row_count": len(finalized_e6_semantics),
        "completed_gates": list(MATURE_GATES),
    }, paths


def write_receipt(kit_root: Path, packet_dir: Path, manifest: dict, result: dict, completed_paths: list[Path]) -> Path:
    finalizer_contract = manifest.get("offline_finalizer", {})
    if not isinstance(finalizer_contract, dict):
        fail("offline finalizer contract missing")
    entries = []
    for path in sorted(completed_paths):
        entries.append({"path": path.resolve().relative_to(kit_root.resolve()).as_posix(), "sha256": sha256_file(path), "bytes": path.stat().st_size})

    qualification = {"declaration_only": True, "proves_human_truth_or_timing": False}
    if result.get("kind") == "first_session":
        qualification.update({
            "naive": bool(result.get("naive_declared", False)),
            "e1_success": bool(result.get("e1_success_declared", False)),
            "e1_understood_at_seconds": float(result.get("e1_understood_at_seconds_declared", 0.0)),
            "e2_packet_completed": bool(result.get("e2_packet_completed_declared", False)),
            "e11_start_timestamp": float(result.get("e11_start_timestamp_finalized", 0.0)),
            "e11_first_collateral_aha_seconds": float(result.get("e11_first_collateral_aha_seconds_declared", -1.0)),
            "e11_completion_seconds": float(result.get("e11_completion_seconds_finalized", 0.0)),
            "e11_completed": bool(result.get("e11_completed_finalized", False)),
            "e11_completion_source": str(result.get("e11_completion_source", "")),
            "e11_binding_scope": "finalization_snapshot_only",
        })
    else:
        qualification.update({
            "rules_known_before_session": result.get("rules_known_before_session_declared") is True,
            "e3_outcome_sha256": str(result.get("e3_finalized_outcome_sha256", "")),
            "e3_row_count": int(result.get("e3_finalized_row_count", 0)),
            "e3_binding_scope": "finalization_snapshot_only",
            "e4_outcome_sha256": str(result.get("e4_finalized_outcome_sha256", "")),
            "e4_row_count": int(result.get("e4_finalized_row_count", 0)),
            "e4_binding_scope": "finalization_snapshot_only",
            "e5_semantic_sha256": str(result.get("e5_finalized_semantic_sha256", "")),
            "e5_row_count": int(result.get("e5_finalized_row_count", 0)),
            "e5_binding_scope": "finalization_snapshot_only",
            "e6_semantic_sha256": str(result.get("e6_finalized_semantic_sha256", "")),
            "e6_row_count": int(result.get("e6_finalized_row_count", 0)),
            "e6_binding_scope": "finalization_snapshot_only",
        })

    receipt = {
        "schema": RECEIPT_SCHEMA,
        "source_head": str(manifest.get("source_head", "")),
        "field_kit_contract_hash": str(manifest.get("contract_hash", "")),
        "demo_build_id": str(manifest.get("demo_build_id", "")),
        "production_build_id": str(manifest.get("production_build_id", "")),
        "packet_kind": str(result.get("kind", "")),
        "tester_id": str(result.get("tester_id", "")),
        "session_id": str(result.get("session_id", "")),
        "participant_qualification": qualification,
        "completed_gates": list(result.get("completed_gates", [])),
        "completed_files": entries,
        "finalizer_sha256": str(finalizer_contract.get("sha256", "")),
        "human_outcomes_inferred": False,
        "repository_evidence_appended": False,
    }
    # For v5, field_kit_contract_hash cryptographically binds the exact demo and production binding IDs/SHA-256s in the immutable manifest.
    if int(manifest.get("field_kit_version", 0)) >= 5:
        bindings = manifest.get("build_artifacts", {})
        role = "demo" if result.get("kind") == "first_session" else "production"
        binding = bindings.get(role) if isinstance(bindings, dict) else None
        if not isinstance(binding, dict):
            fail(f"verified manifest missing {role} acquisition build binding")
        receipt["build_artifact_binding"] = {
            "role": role,
            "binding_id": str(binding.get("binding_id", "")),
            "artifact_sha256": str(binding.get("artifact_sha256", "")),
            "artifact_bytes": binding.get("artifact_bytes"),
        }
    receipt_path = packet_dir / "finalization-receipt.json"
    write_json(receipt_path, receipt)
    return receipt_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Finalize already-observed Phase 12G human field-kit packets without a repository checkout. Never appends repository evidence.")
    parser.add_argument("--kit-dir", default=".")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--first-session")
    group.add_argument("--mature-tester")
    args = parser.parse_args()
    kit_root = Path(args.kit_dir).resolve()
    manifest = verify_kit(kit_root)
    if args.first_session:
        packet_dir = first_packet_dir(kit_root, manifest, args.first_session)
        result, completed_paths = finalize_first(packet_dir)
    else:
        packet_dir = mature_packet_dir(kit_root, manifest, args.mature_tester)
        result, completed_paths = finalize_mature(packet_dir)
    receipt_path = write_receipt(kit_root, packet_dir, manifest, result, completed_paths)
    result.update({
        "status": "FINALIZED_LOCAL_OFFLINE",
        "finalization_receipt": receipt_path.relative_to(kit_root).as_posix(),
        "completed_file_digests_bound": True,
        "participant_qualification_bound": True,
        "finalized_semantic_eligibility_bound": True,
        "acquisition_build_bytes_bound": int(manifest.get("field_kit_version", 0)) >= 5,
        "human_outcomes_inferred": False,
        "repository_evidence_appended": False,
        "append_requires_matching_repository_review": True,
    })
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
