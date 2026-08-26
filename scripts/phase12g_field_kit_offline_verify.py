#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

BUILD_SNAPSHOT_SCHEMA = "fmd.phase12g.acquisition-build-binding.v1"
BUILD_RECORD_SCHEMA = "fmd.phase12g.build-artifact-binding.v1"


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
        actual = first_contract(resolve_relative(first_manifest_path.parent, packet.get("session_dir", ""), "first-session packet path")); expected = expected_first.get(actual["session_id"])
        if not isinstance(expected, dict) or any(actual.get(k) != expected.get(k) for k in ["tester_id","session_id","demo_build_id","manifest_sha256","observer_keys"]): fail(f"first-session immutable contract changed: {actual['session_id']}")
        first_count += 1
    if first_count != int(first_section.get("packet_count", -1)): fail("first-session packet count mismatch")
    mature_manifest = load_json(mature_manifest_path); expected_mature = {str(r.get("tester_id", "")): r for r in mature_section.get("packets", []) if isinstance(r, dict)}; mature_count = 0
    for packet in mature_manifest.get("packets", []):
        actual = mature_contract(resolve_relative(mature_manifest_path.parent, packet.get("packet_dir", ""), "mature-session packet path")); expected = expected_mature.get(actual["tester_id"])
        if not isinstance(expected, dict) or any(actual.get(k) != expected.get(k) for k in ["tester_id","build_id","identity_fingerprint","row_counts"]): fail(f"mature-session immutable contract changed: {actual['tester_id']}")
        mature_count += 1
    if mature_count != int(mature_section.get("packet_count", -1)): fail("mature-session packet count mismatch")
    return {"status":"VERIFIED_OFFLINE","source_head":source_head,"first_packets":first_count,"mature_packets":mature_count,"acquisition_build_bytes_verified":True,"demo_binding_id":demo["binding_id"],"production_binding_id":production["binding_id"],"human_outcomes_inferred":False,"repository_evidence_appended":False}


def main() -> None:
    parser = argparse.ArgumentParser(); parser.add_argument("--kit-dir", default="."); args = parser.parse_args(); print(json.dumps(verify(Path(args.kit_dir)), indent=2, sort_keys=True))

if __name__ == "__main__": main()
