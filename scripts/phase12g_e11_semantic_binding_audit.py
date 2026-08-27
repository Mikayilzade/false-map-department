#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))
from phase12g_audit_build_fixture import kit_build_args  # noqa: E402

KIT = SCRIPT_DIR / "phase12g_human_field_kit.py"
INGEST = SCRIPT_DIR / "phase12g_field_kit_ingest.py"
REGISTRY = ROOT / "empirical/phase12g_gate_registry.json"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G E11 SEMANTIC BINDING AUDIT FAIL: {message}")


def run(args: list[str], ok: bool = True, cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if ok and result.returncode != 0:
        fail(f"command failed: {' '.join(args)}\n{result.stdout}\n{result.stderr}")
    if not ok and result.returncode == 0:
        fail(f"command unexpectedly succeeded: {' '.join(args)}")
    return result


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        fail(f"{path}: expected object")
    return value


def write(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def repository_head() -> str:
    result = run(["git", "rev-parse", "--verify", "HEAD"])
    head = result.stdout.strip().lower()
    if len(head) != 40 or any(ch not in "0123456789abcdef" for ch in head):
        fail(f"invalid repository HEAD: {head!r}")
    return head


def assert_e11_registry_contract() -> None:
    registry = load(REGISTRY)
    e11 = next((gate for gate in registry.get("gates", []) if isinstance(gate, dict) and gate.get("gate_id") == "E11"), None)
    if not isinstance(e11, dict):
        fail("E11 registry entry missing")
    if e11.get("evidence_class") != "human_timing":
        fail("E11 evidence class changed; re-audit threat model")
    if e11.get("target_demo_window_minutes") != [15, 25]:
        fail("E11 target demo window changed; re-audit threat model")
    if e11.get("canonical_threshold") is not None:
        fail("E11 unexpectedly became an automatic numeric-threshold gate; re-audit threat model")


def main() -> None:
    assert_e11_registry_contract()
    source_head = repository_head()
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-e11-semantic-") as temp:
        root = Path(temp)
        kit_root = root / "kit"
        evidence_root = root / "evidence"
        build_args = kit_build_args(
            root / "source-builds",
            source_head=source_head,
            demo_build_id="e11-semantic-demo",
            production_build_id="e11-semantic-production",
        )
        run([
            sys.executable,
            str(KIT),
            "prepare",
            "--source-head",
            source_head,
            "--demo-build-id",
            "e11-semantic-demo",
            "--production-build-id",
            "e11-semantic-production",
            *build_args,
            "--first-count",
            "1",
            "--mature-count",
            "1",
            "--output-dir",
            str(kit_root),
        ])

        manifest = load(kit_root / "field-kit-manifest.json")
        first_batch_path = kit_root / str(manifest["first_session"]["batch_manifest"])
        first_batch = load(first_batch_path)
        packet = first_batch["packets"][0]
        session_dir = (first_batch_path.parent / str(packet["session_dir"])).resolve()
        session_manifest = load(session_dir / "session-manifest.json")
        observer_path = session_dir / "observer.json"
        observer = load(observer_path)
        observer.update({
            "naive": True,
            "e1_success": True,
            "e1_understood_at_seconds": 90.0,
            "e2_packet_completed": True,
            "e2_success": True,
            "first_collateral_aha_observed": True,
            "first_collateral_aha_seconds": 400.0,
            "session_end_seconds": 2000.0,
        })
        write(observer_path, observer)

        telemetry_path = session_dir / "telemetry.json"
        write(telemetry_path, {
            "tester_id": session_manifest["tester_id"],
            "session_id": session_manifest["session_id"],
            "demo_build_id": session_manifest["demo_build_id"],
            "session_started_ms": 111111111,
            "events": [],
        })

        finalizer = kit_root / "FIELD-KIT-FINALIZE.py"
        run([
            sys.executable,
            str(finalizer),
            "--kit-dir",
            str(kit_root),
            "--first-session",
            str(packet["session_id"]),
        ], cwd=kit_root)

        verifier = kit_root / "FIELD-KIT-VERIFY.py"
        baseline = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], cwd=kit_root)
        baseline_result = json.loads(baseline.stdout)
        if baseline_result.get("status") != "VERIFIED_OFFLINE":
            fail("canonical finalized packet did not verify")
        if baseline_result.get("finalized_semantic_eligibility_verified") is not True:
            fail("baseline verifier did not report finalized semantic verification")

        completed_e11 = session_dir / "completed-E11.jsonl"
        receipt_path = session_dir / "finalization-receipt.json"
        original_observer = observer_path.read_bytes()
        original_telemetry = telemetry_path.read_bytes()
        original_e11 = completed_e11.read_bytes()
        original_receipt = receipt_path.read_bytes()

        receipt = load(receipt_path)
        qualification = receipt.get("participant_qualification", {})
        if not isinstance(qualification, dict):
            fail("finalization receipt participant qualification missing")
        expected_snapshot = {
            "e11_start_timestamp": 111111111.0,
            "e11_first_collateral_aha_seconds": 400.0,
            "e11_completion_seconds": 2000.0,
            "e11_completed": False,
            "e11_completion_source": "observer_session_end",
            "e11_binding_scope": "finalization_snapshot_only",
        }
        for key, expected in expected_snapshot.items():
            if qualification.get(key) != expected:
                fail(f"finalization receipt did not freeze {key}: expected {expected!r}, got {qualification.get(key)!r}")
        if qualification.get("declaration_only") is not True or qualification.get("proves_human_truth_or_timing") is not False:
            fail("E11 receipt binding must remain declaration-only/non-proof")

        # Reproduce the disposition-changing rebound: after an incomplete finalized
        # session, rewrite telemetry + observer timing + completed-E11 to look like a
        # completed 20-minute demo, then refresh only the completed-file digest/size.
        # The independent finalization snapshot in the receipt must reject it.
        mutated_observer = load(observer_path)
        mutated_observer["first_collateral_aha_seconds"] = 100.0
        mutated_observer["session_end_seconds"] = 1200.0
        write(observer_path, mutated_observer)
        write(telemetry_path, {
            "tester_id": session_manifest["tester_id"],
            "session_id": session_manifest["session_id"],
            "demo_build_id": session_manifest["demo_build_id"],
            "session_started_ms": 222222222,
            "events": [{"event_type": "demo_completed", "elapsed_seconds": 1200.0}],
        })

        rows = [json.loads(line) for line in completed_e11.read_text(encoding="utf-8").splitlines() if line.strip()]
        if len(rows) != 1 or rows[0].get("completed") is not False or float(rows[0].get("completion_seconds", -1)) != 2000.0:
            fail("attack fixture did not begin with finalized incomplete E11 semantics")
        rows[0]["start_timestamp"] = 222222222
        rows[0]["first_collateral_aha_seconds"] = 100.0
        rows[0]["completion_seconds"] = 1200.0
        rows[0]["completed"] = True
        completed_e11.write_text(json.dumps(rows[0], sort_keys=True) + "\n", encoding="utf-8")

        rebound = False
        for entry in receipt.get("completed_files", []):
            if isinstance(entry, dict) and Path(str(entry.get("path", ""))).name == "completed-E11.jsonl":
                entry["sha256"] = sha256_file(completed_e11)
                entry["bytes"] = completed_e11.stat().st_size
                rebound = True
        if not rebound:
            fail("could not rebind mutated completed-E11 bytes inside finalization receipt")
        write(receipt_path, receipt)

        attacked = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], ok=False, cwd=kit_root)
        attacked_text = (attacked.stdout + attacked.stderr).lower()
        if "finalized e11 timing/completion semantic mismatch" not in attacked_text:
            fail("telemetry+observer+E11-row+digest rebound did not fail at finalization-time E11 boundary")
        if "completed=false" not in attacked_text:
            fail("E11 rejection did not identify the frozen incomplete finalization snapshot")

        ingest = run([
            sys.executable,
            str(INGEST),
            "--kit-dir",
            str(kit_root),
            "--expected-source-head",
            source_head,
            "--evidence-root",
            str(evidence_root),
        ], ok=False)
        ingest_text = (ingest.stdout + ingest.stderr).lower()
        if "finalized e11 timing/completion semantic mismatch" not in ingest_text:
            fail("repository ingest did not reject the E11 rebound through bundled verification")
        if evidence_root.exists() and any(evidence_root.glob("*.jsonl")):
            fail("rejected E11 rebound must append zero empirical evidence")

        observer_path.write_bytes(original_observer)
        telemetry_path.write_bytes(original_telemetry)
        completed_e11.write_bytes(original_e11)
        receipt_path.write_bytes(original_receipt)
        restored = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], cwd=kit_root)
        if json.loads(restored.stdout).get("status") != "VERIFIED_OFFLINE":
            fail("canonical finalized packet did not verify again after E11 attack restoration")

    print(
        "Phase 12G E11 semantic binding audit: PASS — finalized incomplete/start/aha/completion semantics cannot be rebound to a completed 20-minute row by telemetry+observer+row+digest mutation; receipt is a finalization snapshot only, proves no human truth/timing, ingest appends zero evidence, canonical packet restores cleanly"
    )


if __name__ == "__main__":
    main()
