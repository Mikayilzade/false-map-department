#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

BUILD_SNAPSHOT_SCHEMA = "fmd.phase12g.acquisition-build-binding.v1"
BUILD_RECORD_SCHEMA = "fmd.phase12g.build-artifact-binding.v1"
FIRST_FINALIZED_GATES = ("E1", "E2", "E11")
MATURE_FINALIZED_GATES = ("E3", "E4", "E5", "E6", "E9", "E10")


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G OFFLINE FIELD KIT VERIFY FAIL: {message}")


def load_json(path: Path) -> dict:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"{path}: unreadable JSON: {exc}")
    if not isinstance(payload, dict):
        fail(f"{path}: expected JSON object")
    return payload


def load_jsonl(path: Path) -> list[dict]:
    rows: list[dict] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        fail(f"{path}: unreadable JSONL: {exc}")
    for line_no, raw in enumerate(lines, start=1):
        if not raw.strip():
            continue
        try:
            value = json.loads(raw)
        except json.JSONDecodeError as exc:
            fail(f"{path}:{line_no}: malformed JSON row: {exc}")
        if not isinstance(value, dict):
            fail(f"{path}:{line_no}: completed row must be an object")
        rows.append(value)
    if not rows:
        fail(f"{path}: finalized completed file contains no rows")
    return rows


def sha256_file(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as exc:
        fail(f"{path}: unreadable file: {exc}")


def canonical_sha256(payload: object) -> str:
    text = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def validate_source_head(value: object) -> str:
    source_head = str(value).strip().lower()
    if len(source_head) != 40 or any(ch not in "0123456789abcdef" for ch in source_head):
        fail("manifest source_head must be an exact 40-character Git commit SHA")
    return source_head


def resolve_relative(root: Path, value: object, label: str) -> Path:
    raw = Path(str(value))
    if raw.is_absolute() or ".." in raw.parts:
        fail(f"{label} must be relative")
    candidate = (root / raw).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        fail(f"{label} escapes owning root")
    return candidate


def string_array(value: object, label: str) -> list[str]:
    if not isinstance(value, list):
        fail(f"{label} must be an array")
    return [str(item) for item in value]


def verify_build_binding(root: Path, snapshot: object, source_head: str, role: str, build_id: str) -> dict:
    if not isinstance(snapshot, dict) or snapshot.get("schema") != BUILD_SNAPSHOT_SCHEMA:
        fail(f"{role} acquisition build binding missing/unsupported")
    if snapshot.get("source_head") != source_head or snapshot.get("role") != role or snapshot.get("build_id") != build_id:
        fail(f"{role} acquisition build identity mismatch")
    artifact = resolve_relative(root, snapshot.get("packet_artifact_path", ""), f"{role} packaged artifact path")
    record_path = resolve_relative(root, snapshot.get("packet_record_path", ""), f"{role} build record path")
    record = load_json(record_path)
    if record.get("schema") != BUILD_RECORD_SCHEMA:
        fail(f"{role} build record schema invalid")
    for key, expected in (("source_head", source_head), ("role", role), ("build_id", build_id)):
        if record.get(key) != expected:
            fail(f"{role} build record {key} mismatch")
    unhashed = dict(record)
    claimed_binding = str(unhashed.pop("binding_id", ""))
    if claimed_binding != canonical_sha256(unhashed):
        fail(f"{role} build binding_id mismatch")
    if claimed_binding != str(snapshot.get("binding_id", "")):
        fail(f"{role} acquisition snapshot binding_id drift")
    actual_hash = sha256_file(artifact)
    actual_bytes = artifact.stat().st_size
    if actual_hash != str(record.get("artifact_sha256", "")) or actual_bytes != record.get("artifact_bytes"):
        fail(f"{role} packaged build bytes changed after acquisition preparation")
    for key in ("artifact_sha256", "artifact_bytes", "artifact_filename"):
        if snapshot.get(key) != record.get(key):
            fail(f"{role} acquisition snapshot drift: {key}")
    if artifact.name != str(record.get("artifact_filename", "")):
        fail(f"{role} packaged build filename mismatch")
    if snapshot.get("acquisition_bytes_frozen") is not True or snapshot.get("evidence_appended") is not False:
        fail(f"{role} acquisition build boundary flags invalid")
    return snapshot


def verify_finalized_semantic_eligibility(
    packet_dir: Path,
    receipt_path: Path,
    receipt: dict,
    expected_gates: tuple[str, ...],
    packet_kind: str,
) -> None:
    """Keep finalized eligibility fields attached to their packet-local declarations.

    The receipt remains the packet-local participant qualification statement. For E2,
    packet-completion is a separate observed eligibility input created by the finalizer from
    observer.json, so the bundled verifier also requires the finalized E2 row to retain that
    packet-local observer declaration. A caller may transport returned bytes, but may not flip
    either eligibility field and merely recompute that completed file's mutable size/SHA entry.

    These checks do not prove human naivety, completion, rule knowledge, or timing. They only
    prevent contradictory packet-local semantic declarations from being silently rebound into
    collector eligibility after finalization.
    """
    qualification = receipt.get("participant_qualification")
    if not isinstance(qualification, dict):
        fail(f"{receipt_path}: participant_qualification missing/malformed")
    if qualification.get("declaration_only") is not True or qualification.get("proves_human_truth_or_timing") is not False:
        fail(f"{receipt_path}: participant qualification empirical-boundary markers invalid")

    if packet_kind == "first_session":
        declared_naive = qualification.get("naive")
        if not isinstance(declared_naive, bool):
            fail(f"{receipt_path}: first-session participant qualification must declare naive=true/false")
        observer_path = packet_dir / "observer.json"
        observer = load_json(observer_path)
        declared_packet_completed = observer.get("e2_packet_completed")
        if not isinstance(declared_packet_completed, bool):
            fail(f"{observer_path}: first-session observer must retain e2_packet_completed=true/false")
        for gate_id in expected_gates:
            path = packet_dir / f"completed-{gate_id}.jsonl"
            for row_index, row in enumerate(load_jsonl(path), start=1):
                row_naive = row.get("naive")
                if not isinstance(row_naive, bool):
                    fail(f"{path}:{row_index}: finalized first-session row must retain naive=true/false")
                if row_naive is not declared_naive:
                    fail(
                        f"{path}:{row_index}: finalized semantic eligibility mismatch; "
                        f"receipt declares naive={declared_naive}, row claims naive={row_naive}"
                    )
                if gate_id == "E2":
                    row_packet_completed = row.get("packet_completed")
                    if not isinstance(row_packet_completed, bool):
                        fail(f"{path}:{row_index}: E2 packet_completed must remain true/false")
                    if row_packet_completed is not declared_packet_completed:
                        fail(
                            f"{path}:{row_index}: finalized E2 packet completion mismatch; "
                            f"observer declares e2_packet_completed={declared_packet_completed}, "
                            f"row claims packet_completed={row_packet_completed}"
                        )
        return

    if packet_kind == "mature_session":
        if qualification.get("rules_known_before_session") is not True:
            fail(f"{receipt_path}: mature-session participant qualification must declare rules_known_before_session=true")
        for gate_id in expected_gates:
            path = packet_dir / f"completed-{gate_id}.jsonl"
            for row_index, row in enumerate(load_jsonl(path), start=1):
                if row.get("rules_known_before_session") is not True:
                    fail(
                        f"{path}:{row_index}: finalized semantic eligibility mismatch; "
                        "mature receipt declares rules_known_before_session=true"
                    )
                if gate_id == "E3" and row.get("rule_knowledge_confirmed") is not True:
                    fail(f"{path}:{row_index}: E3 rule_knowledge_confirmed must remain true")
                if gate_id == "E6" and row.get("used_raw_debug_log") is not False:
                    fail(f"{path}:{row_index}: E6 used_raw_debug_log must remain false")
        return

    fail(f"{receipt_path}: unsupported packet_kind for semantic eligibility verification: {packet_kind}")


def verify_optional_finalized_routing(packet_dir: Path, expected_gates: tuple[str, ...], packet_kind: str) -> None:
    """Bind any returned finalized files to the immutable packet's canonical gate routes.

    Unfinalized prepared packets remain valid. Once a finalization receipt exists, however,
    the packet must contain exactly one completed file for every gate owned by that packet,
    the receipt must name that same gate set, and every completed row must retain the gate ID
    implied by its receipt-bound filename. This is checked by the bundled verifier before the
    repository ingest can stage or append anything.
    """
    receipt_path = packet_dir / "finalization-receipt.json"
    completed_paths = sorted(packet_dir.glob("completed-*.jsonl"))
    if not receipt_path.exists():
        if completed_paths:
            fail(f"{packet_dir}: completed rows exist without a finalization receipt")
        return

    receipt = load_json(receipt_path)
    if str(receipt.get("packet_kind", "")) != packet_kind:
        fail(f"{receipt_path}: finalization receipt packet_kind mismatch")
    receipt_gates = string_array(receipt.get("completed_gates", []), f"{receipt_path} completed_gates")
    if receipt_gates != list(expected_gates):
        fail(f"{receipt_path}: finalized gate route set mismatch; expected {list(expected_gates)}, got {receipt_gates}")

    expected_names = [f"completed-{gate_id}.jsonl" for gate_id in expected_gates]
    actual_names = [path.name for path in completed_paths]
    if actual_names != sorted(expected_names):
        fail(f"{packet_dir}: finalized completed-file route set mismatch; expected {sorted(expected_names)}, got {actual_names}")

    receipt_entries = receipt.get("completed_files", [])
    if not isinstance(receipt_entries, list) or len(receipt_entries) != len(expected_gates):
        fail(f"{receipt_path}: completed-file receipt bindings must cover exactly {len(expected_gates)} gate routes")
    receipt_names: list[str] = []
    for index, raw_entry in enumerate(receipt_entries, start=1):
        if not isinstance(raw_entry, dict):
            fail(f"{receipt_path}: completed-file binding {index} must be an object")
        name = Path(str(raw_entry.get("path", ""))).name
        if not name:
            fail(f"{receipt_path}: completed-file binding {index} path missing")
        receipt_names.append(name)
    if sorted(receipt_names) != sorted(expected_names) or len(set(receipt_names)) != len(receipt_names):
        fail(f"{receipt_path}: receipt completed-file routes do not match immutable packet gate ownership")

    for gate_id in expected_gates:
        path = packet_dir / f"completed-{gate_id}.jsonl"
        for row_index, row in enumerate(load_jsonl(path), start=1):
            embedded_gate = str(row.get("gate_id", "")).strip()
            if embedded_gate != gate_id:
                shown = embedded_gate if embedded_gate else "<missing>"
                fail(f"{path}:{row_index}: finalized row gate_id mismatch; receipt-bound route is {gate_id}, row claims {shown}")

    verify_finalized_semantic_eligibility(packet_dir, receipt_path, receipt, expected_gates, packet_kind)


def first_contract(session_dir: Path) -> dict:
    manifest_path = session_dir / "session-manifest.json"
    observer_path = session_dir / "observer.json"
    manifest = load_json(manifest_path)
    observer = load_json(observer_path)
    return {"tester_id": str(manifest.get("tester_id", "")), "session_id": str(manifest.get("session_id", "")), "demo_build_id": str(manifest.get("demo_build_id", "")), "manifest_sha256": sha256_file(manifest_path), "observer_keys": sorted(observer.keys())}


def mature_contract(packet_dir: Path) -> dict:
    packet = load_json(packet_dir / "observer-packet.json")
    rows_by_gate = packet.get("rows_by_gate", {})
    if not isinstance(rows_by_gate, dict): fail(f"{packet_dir}: rows_by_gate must be an object")
    identities: dict[str, list[dict]] = {}
    for gate_id in ["E3", "E4", "E5", "E6", "E9", "E10"]:
        rows = rows_by_gate.get(gate_id, [])
        if not isinstance(rows, list): fail(f"{packet_dir}: {gate_id} rows must be an array")
        identities[gate_id] = [{key: row.get(key) for key in sorted(row) if key in {"gate_id","tester_id","dossier_id","method","counterbalance_order","window_id","dossier_ids","remix_id","source_dossier_id","agent_a","agent_b","scenario_id"}} for row in rows if isinstance(row, dict)]
    return {"tester_id": str(packet.get("tester_id", "")), "build_id": str(packet.get("build_id", "")), "identity_fingerprint": canonical_sha256(identities), "row_counts": {gate: len(identities[gate]) for gate in identities}}


def verify(kit_root: Path) -> dict:
    kit_root = kit_root.resolve()
    manifest = load_json(kit_root / "field-kit-manifest.json")
    if int(manifest.get("field_kit_version", 0)) < 5:
        fail("field kit version does not contain acquisition-time packaged-build binding")
    saved_hash = str(manifest.get("contract_hash", "")); clean_manifest = dict(manifest); clean_manifest.pop("contract_hash", None)
    if saved_hash != canonical_sha256(clean_manifest): fail("field-kit manifest contract hash mismatch")
    source_head = validate_source_head(manifest.get("source_head", ""))
    if manifest.get("repository_evidence_appended") is not False or manifest.get("prepared_packets_are_not_evidence") is not True: fail("field-kit evidence boundary flags changed")
    if manifest.get("acquisition_build_bytes_required") is not True: fail("acquisition build-byte requirement missing")
    build_artifacts = manifest.get("build_artifacts")
    if not isinstance(build_artifacts, dict): fail("build_artifacts contract missing")
    demo = verify_build_binding(kit_root, build_artifacts.get("demo"), source_head, "demo", str(manifest.get("demo_build_id", "")))
    production = verify_build_binding(kit_root, build_artifacts.get("production"), source_head, "production", str(manifest.get("production_build_id", "")))

    verifier = manifest.get("offline_verifier", {}); verifier_path = resolve_relative(kit_root, verifier.get("path", ""), "offline verifier path")
    if verifier_path.resolve() != Path(__file__).resolve() or sha256_file(verifier_path) != str(verifier.get("sha256", "")): fail("offline verifier identity/hash mismatch")
    finalizer = manifest.get("offline_finalizer", {}); finalizer_path = resolve_relative(kit_root, finalizer.get("path", ""), "offline finalizer path")
    if not finalizer_path.exists() or sha256_file(finalizer_path) != str(finalizer.get("sha256", "")): fail("offline finalizer missing/hash mismatch")
    if finalizer.get("requires_repository_checkout") is not False or finalizer.get("appends_repository_evidence") is not False: fail("offline finalizer boundary changed")
    expected_gates = ["E1","E2","E3","E4","E5","E6","E9","E10","E11"]
    if string_array(manifest.get("human_gates", []), "human_gates") != expected_gates: fail("human gate set changed")

    first_section = manifest.get("first_session", {}); mature_section = manifest.get("mature_session", {})
    first_manifest_path = resolve_relative(kit_root, first_section.get("batch_manifest", ""), "first batch manifest"); mature_manifest_path = resolve_relative(kit_root, mature_section.get("batch_manifest", ""), "mature batch manifest")
    if sha256_file(first_manifest_path) != str(first_section.get("batch_manifest_sha256", "")): fail("first-session batch manifest hash mismatch")
    if sha256_file(mature_manifest_path) != str(mature_section.get("batch_manifest_sha256", "")): fail("mature-session batch manifest hash mismatch")
    first_manifest = load_json(first_manifest_path); expected_first = {str(r.get("session_id", "")): r for r in first_section.get("packets", []) if isinstance(r, dict)}; first_count = 0
    for packet in first_manifest.get("packets", []):
        packet_dir = resolve_relative(first_manifest_path.parent, packet.get("session_dir", ""), "first-session packet path")
        actual = first_contract(packet_dir); expected = expected_first.get(actual["session_id"])
        if not isinstance(expected, dict) or any(actual.get(k) != expected.get(k) for k in ["tester_id","session_id","demo_build_id","manifest_sha256","observer_keys"]): fail(f"first-session immutable contract changed: {actual['session_id']}")
        verify_optional_finalized_routing(packet_dir, FIRST_FINALIZED_GATES, "first_session")
        first_count += 1
    if first_count != int(first_section.get("packet_count", -1)): fail("first-session packet count mismatch")
    mature_manifest = load_json(mature_manifest_path); expected_mature = {str(r.get("tester_id", "")): r for r in mature_section.get("packets", []) if isinstance(r, dict)}; mature_count = 0
    for packet in mature_manifest.get("packets", []):
        packet_dir = resolve_relative(mature_manifest_path.parent, packet.get("packet_dir", ""), "mature-session packet path")
        actual = mature_contract(packet_dir); expected = expected_mature.get(actual["tester_id"])
        if not isinstance(expected, dict) or any(actual.get(k) != expected.get(k) for k in ["tester_id","build_id","identity_fingerprint","row_counts"]): fail(f"mature-session immutable contract changed: {actual['tester_id']}")
        verify_optional_finalized_routing(packet_dir, MATURE_FINALIZED_GATES, "mature_session")
        mature_count += 1
    if mature_count != int(mature_section.get("packet_count", -1)): fail("mature-session packet count mismatch")
    return {"status":"VERIFIED_OFFLINE","source_head":source_head,"first_packets":first_count,"mature_packets":mature_count,"acquisition_build_bytes_verified":True,"demo_binding_id":demo["binding_id"],"production_binding_id":production["binding_id"],"finalized_gate_routes_verified":True,"finalized_semantic_eligibility_verified":True,"human_outcomes_inferred":False,"repository_evidence_appended":False}


def main() -> None:
    parser = argparse.ArgumentParser(); parser.add_argument("--kit-dir", default="."); args = parser.parse_args(); print(json.dumps(verify(Path(args.kit_dir)), indent=2, sort_keys=True))

if __name__ == "__main__": main()
