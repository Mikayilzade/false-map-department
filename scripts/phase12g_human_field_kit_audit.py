#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "scripts/phase12g_human_field_kit.py"
SOURCE_HEAD = "0123456789abcdef0123456789abcdef01234567"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G FIELD KIT AUDIT FAIL: {message}")


def run(args: list[str], expect_ok: bool = True, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, cwd=cwd or ROOT, text=True, capture_output=True)
    if expect_ok and result.returncode != 0:
        fail(f"command failed unexpectedly: {' '.join(args)}\n{result.stdout}\n{result.stderr}")
    if not expect_ok and result.returncode == 0:
        fail(f"command succeeded unexpectedly: {' '.join(args)}")
    return result


def load_json(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        fail(f"{path}: expected object")
    return payload


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def resolve_relative(base: Path, value: object) -> Path:
    raw = Path(str(value))
    if raw.is_absolute():
        fail(f"portable audit found unexpected absolute path: {raw}")
    return base / raw


def complete_first_packet(session_dir: Path) -> None:
    manifest = load_json(session_dir / "session-manifest.json")
    observer = load_json(session_dir / "observer.json")
    observer.update({
        "naive": True,
        "e1_success": True,
        "e1_understood_at_seconds": 42.0,
        "e2_packet_completed": True,
        "e2_success": True,
        "first_collateral_aha_observed": True,
        "first_collateral_aha_seconds": 300.0,
        "session_end_seconds": 900.0,
    })
    write_json(session_dir / "observer.json", observer)
    write_json(session_dir / "telemetry.json", {
        "tester_id": manifest["tester_id"],
        "session_id": manifest["session_id"],
        "demo_build_id": manifest["demo_build_id"],
        "session_started_ms": 123456789,
        "events": [{"event_type": "demo_completed", "elapsed_seconds": 900.0}],
    })


def complete_mature_packet(packet_dir: Path) -> None:
    packet = load_json(packet_dir / "observer-packet.json")
    packet["rules_known_before_session"] = True
    for gate_id, rows in packet["rows_by_gate"].items():
        for row in rows:
            if gate_id == "E3":
                row.update({"completion_seconds": 120.0, "completed": True, "rule_knowledge_confirmed": True})
            elif gate_id == "E4":
                row.update({"same_trick_assessment": "distinct", "notes": "synthetic audit fixture only"})
            elif gate_id == "E5":
                row.update({"requirement_id": "REQ_AUDIT", "identified_authority_layer": "L_AUDIT", "correct": True, "tutorial_recall_used": False})
            elif gate_id == "E6":
                row.update({"requirement_id": "REQ_AUDIT", "answered_cause": "synthetic audit cause", "used_raw_debug_log": False, "correct": True})
            elif gate_id == "E9":
                row.update({"described_as_changed_causal_problem": True, "notes": "synthetic audit fixture only"})
            elif gate_id == "E10":
                row.update({"predicted_distinction": "synthetic audit distinction", "correct": True})
    write_json(packet_dir / "observer-packet.json", packet)


def assert_completed_gate(path: Path, gate_id: str) -> None:
    if not path.exists() or path.stat().st_size == 0:
        fail(f"offline finalizer did not create {path.name}")
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not rows or any(row.get("gate_id") != gate_id for row in rows):
        fail(f"offline finalizer produced malformed {gate_id} rows")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-field-kit-") as temp:
        root = Path(temp)
        original = root / "kit-original"
        prepared = run([
            sys.executable, str(TOOL), "prepare",
            "--source-head", SOURCE_HEAD,
            "--demo-build-id", "audit-demo-build",
            "--production-build-id", "audit-production-build",
            "--first-count", "2",
            "--mature-count", "2",
            "--output-dir", str(original),
        ])
        summary = json.loads(prepared.stdout)
        if summary.get("status") != "PREPARED" or summary.get("repository_evidence_appended") is not False:
            fail("prepare must report a non-evidence PREPARED kit")
        if summary.get("offline_verifier_bundled") is not True or summary.get("offline_finalizer_bundled") is not True:
            fail("prepare must report self-contained verifier and finalizer bundles")

        manifest = load_json(original / "field-kit-manifest.json")
        if manifest.get("field_kit_version") != 4 or manifest.get("source_head") != SOURCE_HEAD:
            fail("field kit must pin exact v4 source-head provenance")
        if manifest.get("human_gates") != ["E1", "E2", "E3", "E4", "E5", "E6", "E9", "E10", "E11"]:
            fail("field kit must cover exact real-human acquisition gates")
        if manifest.get("prepared_packets_are_not_evidence") is not True or manifest.get("repository_evidence_appended") is not False:
            fail("field kit must preserve non-evidence preparation boundary")
        if int(manifest["first_session"]["packet_count"]) != 2 or int(manifest["mature_session"]["packet_count"]) != 2:
            fail("audit field kit packet counts must be deterministic")
        if not all(row.get("observer_initially_blank") is True for row in manifest["first_session"]["packets"]):
            fail("first-session human outcomes must start blank")
        if not all(row.get("rules_known_before_session_initially_blank") is True for row in manifest["mature_session"]["packets"]):
            fail("mature eligibility must start blank")
        for section in ("first_session", "mature_session"):
            if Path(str(manifest[section]["batch_manifest"])).is_absolute():
                fail("field-kit batch manifests must be relative")
            if len(str(manifest[section].get("batch_manifest_sha256", ""))) != 64:
                fail("field-kit batch manifest must be hash-pinned")

        verifier_contract = manifest.get("offline_verifier", {})
        finalizer_contract = manifest.get("offline_finalizer", {})
        if verifier_contract.get("path") != "FIELD-KIT-VERIFY.py" or len(str(verifier_contract.get("sha256", ""))) != 64:
            fail("offline verifier must be root-relative and SHA-256 pinned")
        if finalizer_contract.get("path") != "FIELD-KIT-FINALIZE.py" or len(str(finalizer_contract.get("sha256", ""))) != 64:
            fail("offline finalizer must be root-relative and SHA-256 pinned")
        if finalizer_contract.get("requires_repository_checkout") is not False or finalizer_contract.get("appends_repository_evidence") is not False:
            fail("offline finalizer must explicitly avoid repository dependency/evidence append")
        if not (original / "FIELD-KIT-VERIFY.py").exists() or not (original / "FIELD-KIT-FINALIZE.py").exists():
            fail("prepared kit must physically contain offline verifier and finalizer")
        instructions = (original / "FIELD-KIT-INSTRUCTIONS.txt").read_text(encoding="utf-8")
        for marker in [
            "python3 FIELD-KIT-VERIFY.py --kit-dir .",
            "python3 FIELD-KIT-FINALIZE.py --kit-dir . --first-session <SESSION_ID>",
            "python3 FIELD-KIT-FINALIZE.py --kit-dir . --mature-tester <TESTER_ID>",
        ]:
            if marker not in instructions:
                fail(f"field-kit instructions missing portable command: {marker}")

        # The kit must genuinely survive relocation with the original path removed.
        relocated = root / "kit-relocated"
        shutil.copytree(original, relocated)
        shutil.rmtree(original)
        verifier = relocated / "FIELD-KIT-VERIFY.py"
        finalizer = relocated / "FIELD-KIT-FINALIZE.py"
        offline = run([sys.executable, str(verifier), "--kit-dir", "."], cwd=relocated)
        offline_summary = json.loads(offline.stdout)
        if offline_summary.get("status") != "VERIFIED_OFFLINE" or offline_summary.get("portable_paths_verified") is not True:
            fail("relocated kit must verify using only its bundled verifier")
        if offline_summary.get("offline_finalizer_verified") is not True:
            fail("offline verification must pin the bundled finalizer bytes")
        if offline_summary.get("repository_evidence_appended") is not False:
            fail("offline verification must never append evidence")

        # Repository-side verify deliberately delegates to the same hash-pinned bundled verifier.
        verified = run([sys.executable, str(TOOL), "verify", "--kit-dir", str(relocated)])
        verify_summary = json.loads(verified.stdout)
        if verify_summary.get("status") != "VERIFIED" or verify_summary.get("offline_verifier_used") is not True:
            fail("repository verify must consume the bundled offline verifier")

        manifest = load_json(relocated / "field-kit-manifest.json")
        first_manifest_path = resolve_relative(relocated, manifest["first_session"]["batch_manifest"])
        mature_manifest_path = resolve_relative(relocated, manifest["mature_session"]["batch_manifest"])
        first_manifest = load_json(first_manifest_path)
        mature_manifest = load_json(mature_manifest_path)
        first_session_dir = resolve_relative(first_manifest_path.parent, first_manifest["packets"][0]["session_dir"])
        mature_packet_dir = resolve_relative(mature_manifest_path.parent, mature_manifest["packets"][0]["packet_dir"])

        # Synthetic audit fixtures exercise transformation only; they are never appended as evidence.
        complete_first_packet(first_session_dir)
        complete_mature_packet(mature_packet_dir)
        run([sys.executable, str(verifier), "--kit-dir", "."], cwd=relocated)

        first_result = run([
            sys.executable, str(finalizer), "--kit-dir", ".", "--first-session", str(first_manifest["packets"][0]["session_id"]),
        ], cwd=relocated)
        first_summary = json.loads(first_result.stdout)
        if first_summary.get("status") != "FINALIZED_LOCAL_OFFLINE" or first_summary.get("repository_evidence_appended") is not False:
            fail("offline first-session finalization must remain local/non-evidence")
        for gate_id in ("E1", "E2", "E11"):
            assert_completed_gate(first_session_dir / f"completed-{gate_id}.jsonl", gate_id)

        mature_result = run([
            sys.executable, str(finalizer), "--kit-dir", ".", "--mature-tester", str(mature_manifest["packets"][0]["tester_id"]),
        ], cwd=relocated)
        mature_summary = json.loads(mature_result.stdout)
        if mature_summary.get("status") != "FINALIZED_LOCAL_OFFLINE" or mature_summary.get("repository_evidence_appended") is not False:
            fail("offline mature-session finalization must remain local/non-evidence")
        for gate_id in ("E3", "E4", "E5", "E6", "E9", "E10"):
            assert_completed_gate(mature_packet_dir / f"completed-{gate_id}.jsonl", gate_id)

        # Mutable human fields and completed local rows do not alter immutable packet identity.
        run([sys.executable, str(verifier), "--kit-dir", "."], cwd=relocated)

        # Immutable packet identity/build metadata must be pinned. Tampering is rejected offline.
        session_manifest_path = first_session_dir / "session-manifest.json"
        session_manifest = load_json(session_manifest_path)
        original_session_manifest = dict(session_manifest)
        session_manifest["demo_build_id"] = "tampered-build"
        write_json(session_manifest_path, session_manifest)
        rejected = run([sys.executable, str(verifier), "--kit-dir", "."], expect_ok=False, cwd=relocated)
        if "immutable contract changed" not in (rejected.stdout + rejected.stderr):
            fail("tampered immutable packet contract must fail offline with an integrity reason")
        write_json(session_manifest_path, original_session_manifest)

        # The verifier itself and finalizer are both manifest-pinned executable acquisition infrastructure.
        finalizer_original = finalizer.read_text(encoding="utf-8")
        finalizer.write_text(finalizer_original + "\n# tampered\n", encoding="utf-8")
        rejected_finalizer = run([sys.executable, str(verifier), "--kit-dir", "."], expect_ok=False, cwd=relocated)
        if "offline finalizer hash mismatch" not in (rejected_finalizer.stdout + rejected_finalizer.stderr):
            fail("tampered bundled finalizer must be rejected by offline verifier")
        finalizer.write_text(finalizer_original, encoding="utf-8")

        verifier.write_text(verifier.read_text(encoding="utf-8") + "\n# tampered\n", encoding="utf-8")
        rejected_verifier = run([sys.executable, str(TOOL), "verify", "--kit-dir", str(relocated)], expect_ok=False)
        if "offline verifier hash mismatch" not in (rejected_verifier.stdout + rejected_verifier.stderr):
            fail("tampered bundled verifier must be rejected by its manifest hash")

        invalid = root / "invalid-head-kit"
        rejected_head = run([
            sys.executable, str(TOOL), "prepare",
            "--source-head", "audit-head-0123456789abcdef",
            "--demo-build-id", "audit-demo-build",
            "--production-build-id", "audit-production-build",
            "--first-count", "1",
            "--mature-count", "1",
            "--output-dir", str(invalid),
        ], expect_ok=False)
        if "40-character Git commit SHA" not in (rejected_head.stdout + rejected_head.stderr):
            fail("invalid source head must be rejected explicitly")

        evidence_root = ROOT / "empirical/evidence"
        if (evidence_root / "FIELD-KIT.jsonl").exists():
            fail("field kit audit must never invent repository evidence")

    print("Phase 12G human field-kit audit: PASS (E1-E6/E9-E11 relocatable packets + self-contained verify/finalize + exact source/tool pinning + immutable tamper rejection + observer-local completed rows + no evidence append)")


if __name__ == "__main__":
    main()
