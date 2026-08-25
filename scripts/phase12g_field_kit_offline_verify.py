#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


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
    if raw.is_absolute():
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


def first_contract(session_dir: Path) -> dict:
    manifest_path = session_dir / "session-manifest.json"
    observer_path = session_dir / "observer.json"
    manifest = load_json(manifest_path)
    observer = load_json(observer_path)
    return {
        "tester_id": str(manifest.get("tester_id", "")),
        "session_id": str(manifest.get("session_id", "")),
        "demo_build_id": str(manifest.get("demo_build_id", "")),
        "manifest_sha256": sha256_file(manifest_path),
        "observer_keys": sorted(observer.keys()),
    }


def mature_contract(packet_dir: Path) -> dict:
    packet = load_json(packet_dir / "observer-packet.json")
    rows_by_gate = packet.get("rows_by_gate", {})
    if not isinstance(rows_by_gate, dict):
        fail(f"{packet_dir}: rows_by_gate must be an object")
    identities: dict[str, list[dict]] = {}
    for gate_id in ["E3", "E4", "E5", "E6", "E9", "E10"]:
        rows = rows_by_gate.get(gate_id, [])
        if not isinstance(rows, list):
            fail(f"{packet_dir}: {gate_id} rows must be an array")
        gate_identities: list[dict] = []
        for row in rows:
            if not isinstance(row, dict):
                fail(f"{packet_dir}: {gate_id} row must be an object")
            gate_identities.append({
                key: row.get(key)
                for key in sorted(row)
                if key in {
                    "gate_id", "tester_id", "dossier_id", "method", "counterbalance_order",
                    "window_id", "dossier_ids", "remix_id", "source_dossier_id",
                    "agent_a", "agent_b", "scenario_id",
                }
            })
        identities[gate_id] = gate_identities
    return {
        "tester_id": str(packet.get("tester_id", "")),
        "build_id": str(packet.get("build_id", "")),
        "identity_fingerprint": canonical_sha256(identities),
        "row_counts": {gate: len(identities[gate]) for gate in identities},
    }


def verify(kit_root: Path) -> dict:
    kit_root = kit_root.resolve()
    manifest_path = kit_root / "field-kit-manifest.json"
    manifest = load_json(manifest_path)
    if int(manifest.get("field_kit_version", 0)) < 3:
        fail("field kit version does not contain the offline-verifier contract")
    saved_hash = str(manifest.get("contract_hash", ""))
    clean_manifest = dict(manifest)
    clean_manifest.pop("contract_hash", None)
    if saved_hash != canonical_sha256(clean_manifest):
        fail("field-kit manifest contract hash mismatch")
    source_head = validate_source_head(manifest.get("source_head", ""))
    if manifest.get("repository_evidence_appended") is not False:
        fail("repository_evidence_appended boundary flag changed")
    if manifest.get("prepared_packets_are_not_evidence") is not True:
        fail("prepared_packets_are_not_evidence boundary flag changed")

    verifier = manifest.get("offline_verifier", {})
    if not isinstance(verifier, dict):
        fail("offline_verifier contract missing")
    verifier_path = resolve_relative(kit_root, verifier.get("path", ""), "offline verifier path")
    if verifier_path.resolve() != Path(__file__).resolve():
        fail("running verifier does not match manifest-pinned offline verifier path")
    if sha256_file(verifier_path) != str(verifier.get("sha256", "")):
        fail("offline verifier hash mismatch")

    expected_gates = ["E1", "E2", "E3", "E4", "E5", "E6", "E9", "E10", "E11"]
    if string_array(manifest.get("human_gates", []), "human_gates") != expected_gates:
        fail("human gate set changed")

    first_section = manifest.get("first_session", {})
    mature_section = manifest.get("mature_session", {})
    if not isinstance(first_section, dict) or not isinstance(mature_section, dict):
        fail("nested batch sections malformed")
    first_manifest_path = resolve_relative(kit_root, first_section.get("batch_manifest", ""), "first batch manifest")
    mature_manifest_path = resolve_relative(kit_root, mature_section.get("batch_manifest", ""), "mature batch manifest")
    if sha256_file(first_manifest_path) != str(first_section.get("batch_manifest_sha256", "")):
        fail("first-session batch manifest hash mismatch")
    if sha256_file(mature_manifest_path) != str(mature_section.get("batch_manifest_sha256", "")):
        fail("mature-session batch manifest hash mismatch")

    first_manifest = load_json(first_manifest_path)
    expected_first_rows = first_section.get("packets", [])
    if not isinstance(expected_first_rows, list):
        fail("first-session packet contract list malformed")
    expected_first = {str(row.get("session_id", "")): row for row in expected_first_rows if isinstance(row, dict)}
    first_count = 0
    for packet in first_manifest.get("packets", []):
        if not isinstance(packet, dict):
            fail("first-session batch packet must be an object")
        session_dir = resolve_relative(first_manifest_path.parent, packet.get("session_dir", ""), "first-session packet path")
        actual = first_contract(session_dir)
        expected = expected_first.get(actual["session_id"])
        if not isinstance(expected, dict):
            fail(f"unexpected first-session packet identity: {actual['session_id']}")
        for key in ["tester_id", "session_id", "demo_build_id", "manifest_sha256", "observer_keys"]:
            if actual.get(key) != expected.get(key):
                fail(f"first-session immutable contract changed for {actual['session_id']}: {key}")
        first_count += 1
    if first_count != int(first_section.get("packet_count", -1)):
        fail("first-session packet count mismatch")

    mature_manifest = load_json(mature_manifest_path)
    expected_mature_rows = mature_section.get("packets", [])
    if not isinstance(expected_mature_rows, list):
        fail("mature-session packet contract list malformed")
    expected_mature = {str(row.get("tester_id", "")): row for row in expected_mature_rows if isinstance(row, dict)}
    mature_count = 0
    for packet in mature_manifest.get("packets", []):
        if not isinstance(packet, dict):
            fail("mature-session batch packet must be an object")
        packet_dir = resolve_relative(mature_manifest_path.parent, packet.get("packet_dir", ""), "mature-session packet path")
        actual = mature_contract(packet_dir)
        expected = expected_mature.get(actual["tester_id"])
        if not isinstance(expected, dict):
            fail(f"unexpected mature-session packet identity: {actual['tester_id']}")
        for key in ["tester_id", "build_id", "identity_fingerprint", "row_counts"]:
            if actual.get(key) != expected.get(key):
                fail(f"mature-session immutable contract changed for {actual['tester_id']}: {key}")
        mature_count += 1
    if mature_count != int(mature_section.get("packet_count", -1)):
        fail("mature-session packet count mismatch")

    return {
        "status": "VERIFIED_OFFLINE",
        "source_head": source_head,
        "first_packets": first_count,
        "mature_packets": mature_count,
        "portable_paths_verified": True,
        "human_outcomes_inferred": False,
        "repository_evidence_appended": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Self-contained integrity verifier copied into a Phase 12G human field kit.")
    parser.add_argument("--kit-dir", default=".")
    args = parser.parse_args()
    print(json.dumps(verify(Path(args.kit_dir)), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
