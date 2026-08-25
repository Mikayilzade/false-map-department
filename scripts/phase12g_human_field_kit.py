#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIRST_BATCH = ROOT / "scripts/phase12g_first_session_batch.py"
MATURE_BATCH = ROOT / "scripts/phase12g_mature_session_batch.py"
OFFLINE_VERIFIER = ROOT / "scripts/phase12g_field_kit_offline_verify.py"
KIT_VERSION = 3
HUMAN_GATES = ["E1", "E2", "E3", "E4", "E5", "E6", "E9", "E10", "E11"]


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G FIELD KIT FAIL: {message}")


def load_json(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        fail(f"{path}: expected JSON object")
    return payload


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_sha256(payload: object) -> str:
    text = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def run(command: list[str]) -> None:
    subprocess.run(command, cwd=ROOT, check=True, stdout=subprocess.DEVNULL)


def validate_source_head(value: str) -> str:
    source_head = value.strip().lower()
    if len(source_head) != 40 or any(ch not in "0123456789abcdef" for ch in source_head):
        fail("--source-head must be an exact 40-character Git commit SHA")
    return source_head


def resolve_batch_packet(manifest_path: Path, value: object, label: str) -> Path:
    raw = Path(str(value))
    if raw.is_absolute():
        fail(f"{label} must remain relative to its batch manifest")
    candidate = (manifest_path.parent / raw).resolve()
    try:
        candidate.relative_to(manifest_path.parent.resolve())
    except ValueError:
        fail(f"{label} escapes batch root")
    return candidate


def first_contract(session_dir: Path) -> dict:
    manifest = load_json(session_dir / "session-manifest.json")
    observer = load_json(session_dir / "observer.json")
    return {
        "tester_id": str(manifest.get("tester_id", "")),
        "session_id": str(manifest.get("session_id", "")),
        "demo_build_id": str(manifest.get("demo_build_id", "")),
        "manifest_sha256": sha256_file(session_dir / "session-manifest.json"),
        "observer_keys": sorted(observer.keys()),
        "observer_initially_blank": all(
            observer.get(key) is None
            for key in [
                "naive",
                "e1_success",
                "e1_understood_at_seconds",
                "e2_packet_completed",
                "e2_success",
                "first_collateral_aha_observed",
                "first_collateral_aha_seconds",
                "session_end_seconds",
            ]
        ),
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
        "rules_known_before_session_initially_blank": packet.get("rules_known_before_session") is None,
        "identity_fingerprint": canonical_sha256(identities),
        "row_counts": {gate: len(identities[gate]) for gate in identities},
    }


def cmd_prepare(args: argparse.Namespace) -> None:
    if args.first_count < 1 or args.mature_count < 1:
        fail("first and mature participant counts must both be >= 1")
    source_head = validate_source_head(args.source_head)
    if not args.demo_build_id.strip() or not args.production_build_id.strip():
        fail("build IDs must be non-empty")
    if not OFFLINE_VERIFIER.exists():
        fail("offline field-kit verifier source is missing")

    kit_root = Path(args.output_dir).resolve()
    if (kit_root / "field-kit-manifest.json").exists():
        fail("refusing to overwrite an existing field kit manifest")
    first_root = kit_root / "first-session"
    mature_root = kit_root / "mature-session"

    run([
        sys.executable, str(FIRST_BATCH), "prepare",
        "--count", str(args.first_count),
        "--tester-prefix", args.first_tester_prefix,
        "--session-prefix", args.first_session_prefix,
        "--build-id", args.demo_build_id,
        "--output-dir", str(first_root),
    ])
    run([
        sys.executable, str(MATURE_BATCH), "prepare",
        "--count", str(args.mature_count),
        "--tester-prefix", args.mature_tester_prefix,
        "--build-id", args.production_build_id,
        "--output-dir", str(mature_root),
    ])

    first_manifest_path = first_root / "batch-manifest.json"
    mature_manifest_path = mature_root / "batch-manifest.json"
    first_manifest = load_json(first_manifest_path)
    mature_manifest = load_json(mature_manifest_path)
    first_packets = [
        first_contract(resolve_batch_packet(first_manifest_path, row["session_dir"], "first-session packet path"))
        for row in first_manifest.get("packets", [])
    ]
    mature_packets = [
        mature_contract(resolve_batch_packet(mature_manifest_path, row["packet_dir"], "mature-session packet path"))
        for row in mature_manifest.get("packets", [])
    ]
    if not all(row["observer_initially_blank"] for row in first_packets):
        fail("first-session preparation unexpectedly populated a human outcome")
    if not all(row["rules_known_before_session_initially_blank"] for row in mature_packets):
        fail("mature-session preparation unexpectedly populated human eligibility")

    kit_root.mkdir(parents=True, exist_ok=True)
    bundled_verifier = kit_root / "FIELD-KIT-VERIFY.py"
    shutil.copy2(OFFLINE_VERIFIER, bundled_verifier)

    manifest = {
        "field_kit_version": KIT_VERSION,
        "source_head": source_head,
        "demo_build_id": args.demo_build_id,
        "production_build_id": args.production_build_id,
        "path_contract": "all nested manifests and packet paths are relative to their owning manifest",
        "human_gates": HUMAN_GATES,
        "offline_verifier": {
            "path": "FIELD-KIT-VERIFY.py",
            "sha256": sha256_file(bundled_verifier),
            "requires_repository_checkout": False,
        },
        "first_session": {
            "batch_manifest": "first-session/batch-manifest.json",
            "batch_manifest_sha256": sha256_file(first_manifest_path),
            "packet_count": len(first_packets),
            "packets": first_packets,
        },
        "mature_session": {
            "batch_manifest": "mature-session/batch-manifest.json",
            "batch_manifest_sha256": sha256_file(mature_manifest_path),
            "packet_count": len(mature_packets),
            "packets": mature_packets,
        },
        "human_outcomes_required": True,
        "prepared_packets_are_not_evidence": True,
        "repository_evidence_appended": False,
        "evidence_append_requires_deliberate_separate_command": "scripts/phase12g_collect_completed_rows.py --append",
    }
    manifest["contract_hash"] = canonical_sha256(manifest)
    write_json(kit_root / "field-kit-manifest.json", manifest)
    (kit_root / "FIELD-KIT-INSTRUCTIONS.txt").write_text(
        "Phase 12G HUMAN FIELD KIT\n"
        "This directory contains blank acquisition packets, not empirical evidence.\n"
        "The entire directory may be moved/copied intact; nested packet paths are manifest-relative.\n"
        "Integrity can be checked without a repository checkout: python3 FIELD-KIT-VERIFY.py --kit-dir .\n"
        "Use the repository first-session and mature-session protocols without coaching when running/finalizing sessions.\n"
        "After real observations, run the offline verifier, finalize locally with the matching source-head repository tools, then validate completed rows.\n"
        "Appending to empirical/evidence is always a separate deliberate step.\n",
        encoding="utf-8",
    )
    print(json.dumps({
        "status": "PREPARED",
        "source_head": source_head,
        "first_packets": len(first_packets),
        "mature_packets": len(mature_packets),
        "offline_verifier_bundled": True,
        "human_outcomes_inferred": False,
        "repository_evidence_appended": False,
        "manifest": str(kit_root / "field-kit-manifest.json"),
    }, indent=2, sort_keys=True))


def cmd_verify(args: argparse.Namespace) -> None:
    kit_root = Path(args.kit_dir).resolve()
    manifest = load_json(kit_root / "field-kit-manifest.json")
    verifier = manifest.get("offline_verifier", {})
    if not isinstance(verifier, dict):
        fail("offline verifier contract missing")
    raw_path = Path(str(verifier.get("path", "")))
    if raw_path.is_absolute() or ".." in raw_path.parts:
        fail("offline verifier path must remain inside field-kit root")
    verifier_path = (kit_root / raw_path).resolve()
    try:
        verifier_path.relative_to(kit_root)
    except ValueError:
        fail("offline verifier path escapes field-kit root")
    if not verifier_path.exists():
        fail("bundled offline verifier is missing")
    if sha256_file(verifier_path) != str(verifier.get("sha256", "")):
        fail("bundled offline verifier hash mismatch")
    completed = subprocess.run(
        [sys.executable, str(verifier_path), "--kit-dir", str(kit_root)],
        cwd=kit_root,
        text=True,
        capture_output=True,
    )
    if completed.returncode != 0:
        detail = (completed.stdout + completed.stderr).strip()
        fail(f"bundled offline verifier rejected kit: {detail}")
    try:
        result = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        fail(f"bundled offline verifier returned malformed JSON: {exc}")
    if not isinstance(result, dict) or result.get("status") != "VERIFIED_OFFLINE":
        fail("bundled offline verifier returned unexpected disposition")
    result["status"] = "VERIFIED"
    result["offline_verifier_used"] = True
    print(json.dumps(result, indent=2, sort_keys=True))


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare and integrity-check a portable Phase 12G real-human acquisition field kit without creating empirical outcomes.")
    sub = parser.add_subparsers(dest="command", required=True)

    prepare = sub.add_parser("prepare")
    prepare.add_argument("--source-head", required=True)
    prepare.add_argument("--demo-build-id", required=True)
    prepare.add_argument("--production-build-id", required=True)
    prepare.add_argument("--first-count", type=int, default=8)
    prepare.add_argument("--mature-count", type=int, default=6)
    prepare.add_argument("--first-tester-prefix", default="NAIVE-T")
    prepare.add_argument("--first-session-prefix", default="FIRST-S")
    prepare.add_argument("--mature-tester-prefix", default="MATURE-T")
    prepare.add_argument("--output-dir", default=str(ROOT / ".phase12g-human-field-kit"))
    prepare.set_defaults(func=cmd_prepare)

    verify = sub.add_parser("verify")
    verify.add_argument("--kit-dir", required=True)
    verify.set_defaults(func=cmd_verify)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
