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
PROTOCOLS = ROOT / "empirical/phase12g_session_protocols.json"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G E9/E10 FINALIZATION BINDING AUDIT FAIL: {message}")


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


def jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def repository_head() -> str:
    head = run(["git", "rev-parse", "--verify", "HEAD"]).stdout.strip().lower()
    if len(head) != 40 or any(ch not in "0123456789abcdef" for ch in head):
        fail(f"invalid repository HEAD: {head!r}")
    return head


def assert_contracts() -> None:
    registry = load(REGISTRY)
    gates = {gate.get("gate_id"): gate for gate in registry.get("gates", []) if isinstance(gate, dict)}
    e9 = gates.get("E9")
    e10 = gates.get("E10")
    if not isinstance(e9, dict) or e9.get("required_fields") != ["tester_id", "remix_id", "source_dossier_id", "described_as_changed_causal_problem", "notes"]:
        fail("E9 registry contract changed; re-audit threat model")
    if not isinstance(e10, dict) or e10.get("required_fields") != ["tester_id", "agent_a", "agent_b", "scenario_id", "predicted_distinction", "correct"]:
        fail("E10 registry contract changed; re-audit threat model")
    if e9.get("canonical_threshold") is not None or e10.get("canonical_threshold") is not None:
        fail("E9/E10 qualitative disposition contract changed")
    protocols = load(PROTOCOLS).get("protocols", {})
    if protocols.get("E9", {}).get("dossier_selection") != "REMIX01-REMIX12 with declared source_substrate_id":
        fail("E9 protocol selection changed")
    if protocols.get("E10", {}).get("agent_selection") != "distinct taught archetype IDs discovered in campaign content":
        fail("E10 protocol selection changed")


def fill_packet(packet: dict) -> None:
    packet["rules_known_before_session"] = True
    rows = packet.get("rows_by_gate", {})
    if not isinstance(rows, dict):
        fail("rows_by_gate malformed")
    for i, row in enumerate(rows.get("E3", []), 1):
        row.update({"completion_seconds": float(300 + i), "completed": True, "rule_knowledge_confirmed": True})
    for row in rows.get("E4", []):
        row.update({"same_trick_assessment": "distinct", "notes": "synthetic audit fixture; not human evidence"})
    for i, row in enumerate(rows.get("E5", []), 1):
        row.update({"requirement_id": f"AUDIT_REQ_{i:02d}", "identified_authority_layer": f"AUDIT_LAYER_{i:02d}", "correct": True, "tutorial_recall_used": False})
    for i, row in enumerate(rows.get("E6", []), 1):
        row.update({"requirement_id": f"AUDIT_CAUSE_{i:02d}", "answered_cause": f"synthetic cause {i}", "used_raw_debug_log": False, "correct": True})
    for row in rows.get("E9", []):
        row.update({"described_as_changed_causal_problem": True, "notes": "synthetic changed-problem declaration; not human evidence"})
    for row in rows.get("E10", []):
        row.update({"predicted_distinction": "synthetic predicted behavioral distinction; not human evidence", "correct": True})


def refresh_binding(receipt: dict, completed_path: Path) -> None:
    for entry in receipt.get("completed_files", []):
        if isinstance(entry, dict) and Path(str(entry.get("path", ""))).name == completed_path.name:
            entry["sha256"] = sha256_file(completed_path)
            entry["bytes"] = completed_path.stat().st_size
            return
    fail(f"receipt binding missing for {completed_path.name}")


def attack_gate(kit_root: Path, packet_dir: Path, observer_path: Path, receipt_path: Path, verifier: Path, gate_id: str, evidence_root: Path, source_head: str) -> None:
    completed_path = packet_dir / f"completed-{gate_id}.jsonl"
    original_observer = observer_path.read_bytes()
    original_completed = completed_path.read_bytes()
    original_receipt = receipt_path.read_bytes()

    observer = load(observer_path)
    source_rows = observer["rows_by_gate"][gate_id]
    completed_rows = jsonl(completed_path)
    if gate_id == "E9":
        for row in source_rows:
            row["described_as_changed_causal_problem"] = False
            row["notes"] = "rebound E9 declaration"
        for row in completed_rows:
            row["described_as_changed_causal_problem"] = False
            row["notes"] = "rebound E9 declaration"
        expected = "finalized E9 outcome mismatch"
    else:
        for row in source_rows:
            row["predicted_distinction"] = "rebound E10 prediction"
            row["correct"] = False
        for row in completed_rows:
            row["predicted_distinction"] = "rebound E10 prediction"
            row["correct"] = False
        expected = "finalized E10 outcome mismatch"
    write(observer_path, observer)
    write_jsonl(completed_path, completed_rows)
    receipt = load(receipt_path)
    refresh_binding(receipt, completed_path)
    write(receipt_path, receipt)

    attacked = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], ok=False, cwd=kit_root)
    if expected.lower() not in (attacked.stdout + attacked.stderr).lower():
        fail(f"{gate_id} packet+completed-row+digest rebound did not fail at finalization snapshot boundary")
    ingest = run([sys.executable, str(INGEST), "--kit-dir", str(kit_root), "--expected-source-head", source_head, "--evidence-root", str(evidence_root)], ok=False)
    if expected.lower() not in (ingest.stdout + ingest.stderr).lower():
        fail(f"repository ingest did not reject {gate_id} rebound through bundled verification")
    if evidence_root.exists() and any(evidence_root.glob("*.jsonl")):
        fail(f"rejected {gate_id} rebound must append zero empirical evidence")

    observer_path.write_bytes(original_observer)
    completed_path.write_bytes(original_completed)
    receipt_path.write_bytes(original_receipt)
    restored = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], cwd=kit_root)
    if json.loads(restored.stdout).get("status") != "VERIFIED_OFFLINE":
        fail(f"canonical packet did not verify after {gate_id} attack restoration")


def main() -> None:
    assert_contracts()
    source_head = repository_head()
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-e9e10-binding-") as temp:
        root = Path(temp)
        kit_root = root / "kit"
        evidence_root = root / "evidence"
        build_args = kit_build_args(root / "source-builds", source_head=source_head, demo_build_id="e9e10-demo", production_build_id="e9e10-production")
        run([sys.executable, str(KIT), "prepare", "--source-head", source_head, "--demo-build-id", "e9e10-demo", "--production-build-id", "e9e10-production", *build_args, "--first-count", "1", "--mature-count", "1", "--output-dir", str(kit_root)])
        manifest = load(kit_root / "field-kit-manifest.json")
        mature_batch_path = kit_root / str(manifest["mature_session"]["batch_manifest"])
        mature_batch = load(mature_batch_path)
        packet_ref = mature_batch["packets"][0]
        tester_id = str(packet_ref["tester_id"])
        packet_dir = (mature_batch_path.parent / str(packet_ref["packet_dir"])).resolve()
        observer_path = packet_dir / "observer-packet.json"
        observer = load(observer_path)
        if not observer.get("rows_by_gate", {}).get("E9") or not observer.get("rows_by_gate", {}).get("E10"):
            fail("audit requires prepared E9 and E10 rows")
        fill_packet(observer)
        write(observer_path, observer)
        finalizer = kit_root / "FIELD-KIT-FINALIZE.py"
        verifier = kit_root / "FIELD-KIT-VERIFY.py"
        run([sys.executable, str(finalizer), "--kit-dir", str(kit_root), "--mature-tester", tester_id], cwd=kit_root)
        baseline = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], cwd=kit_root)
        if json.loads(baseline.stdout).get("status") != "VERIFIED_OFFLINE":
            fail("canonical finalized mature packet did not verify")
        receipt_path = packet_dir / "finalization-receipt.json"
        qualification = load(receipt_path).get("participant_qualification", {})
        for gate in ("e9", "e10"):
            if qualification.get(f"{gate}_binding_scope") != "finalization_snapshot_only":
                fail(f"{gate.upper()} finalization snapshot marker missing")
        if qualification.get("declaration_only") is not True or qualification.get("proves_human_truth_or_timing") is not False:
            fail("receipt boundary must remain declaration-only/non-proof")
        attack_gate(kit_root, packet_dir, observer_path, receipt_path, verifier, "E9", evidence_root, source_head)
        attack_gate(kit_root, packet_dir, observer_path, receipt_path, verifier, "E10", evidence_root, source_head)

    print("Phase 12G E9/E10 finalization binding audit: PASS — prepared remix/source and agent/scenario identities remain authoritative; observation-time qualitative declarations are frozen by declaration-only finalization snapshots; rebound attempts are rejected before ingest and append zero evidence")


if __name__ == "__main__":
    main()
