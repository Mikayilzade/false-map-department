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
    raise SystemExit(f"PHASE12G E4 SEMANTIC BINDING AUDIT FAIL: {message}")


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


def assert_e4_contract() -> None:
    registry = load(REGISTRY)
    e4 = next((gate for gate in registry.get("gates", []) if isinstance(gate, dict) and gate.get("gate_id") == "E4"), None)
    if not isinstance(e4, dict):
        fail("E4 registry entry missing")
    if e4.get("evidence_class") != "human_playtest" or e4.get("canonical_threshold") is not None:
        fail("E4 evidence/disposition contract changed; re-audit threat model")
    required = ["tester_id", "window_id", "dossier_ids", "same_trick_assessment", "notes"]
    if e4.get("required_fields") != required:
        fail("E4 required fields changed; re-audit threat model")
    protocols = load(PROTOCOLS)
    e4_protocol = protocols.get("protocols", {}).get("E4", {})
    if e4_protocol.get("assessment_values") != ["distinct", "mixed", "predominantly_same_trick"]:
        fail("E4 assessment vocabulary changed; re-audit threat model")
    windows = e4_protocol.get("windows", {})
    if set(windows) != {"D13_D22", "D29_D36"}:
        fail("E4 campaign windows changed; re-audit threat model")


def fill_mature_packet(packet: dict) -> None:
    packet["rules_known_before_session"] = True
    rows_by_gate = packet.get("rows_by_gate", {})
    if not isinstance(rows_by_gate, dict):
        fail("mature audit packet rows_by_gate malformed")
    for index, row in enumerate(rows_by_gate.get("E3", []), start=1):
        row["completion_seconds"] = float(300 + index * 10)
        row["completed"] = True
        row["rule_knowledge_confirmed"] = True
    for row in rows_by_gate.get("E4", []):
        row["same_trick_assessment"] = "distinct"
        row["notes"] = "synthetic audit fixture; not human evidence"
    for row in rows_by_gate.get("E5", []):
        row["requirement_id"] = "AUDIT_REQUIREMENT"
        row["identified_authority_layer"] = "AUDIT_LAYER"
        row["correct"] = True
        row["tutorial_recall_used"] = False
    for row in rows_by_gate.get("E6", []):
        row["requirement_id"] = "AUDIT_REQUIREMENT"
        row["answered_cause"] = "synthetic audit cause"
        row["used_raw_debug_log"] = False
        row["correct"] = True
    for row in rows_by_gate.get("E9", []):
        row["described_as_changed_causal_problem"] = True
        row["notes"] = "synthetic audit fixture; not human evidence"
    for row in rows_by_gate.get("E10", []):
        row["predicted_distinction"] = "synthetic audit distinction"
        row["correct"] = True


def refresh_completed_binding(receipt: dict, completed_path: Path) -> None:
    for entry in receipt.get("completed_files", []):
        if isinstance(entry, dict) and Path(str(entry.get("path", ""))).name == completed_path.name:
            entry["sha256"] = sha256_file(completed_path)
            entry["bytes"] = completed_path.stat().st_size
            return
    fail(f"receipt binding missing for {completed_path.name}")


def main() -> None:
    assert_e4_contract()
    source_head = repository_head()
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-e4-semantic-") as temp:
        root = Path(temp)
        kit_root = root / "kit"
        evidence_root = root / "evidence"
        build_args = kit_build_args(
            root / "source-builds",
            source_head=source_head,
            demo_build_id="e4-semantic-demo",
            production_build_id="e4-semantic-production",
        )
        run([
            sys.executable, str(KIT), "prepare",
            "--source-head", source_head,
            "--demo-build-id", "e4-semantic-demo",
            "--production-build-id", "e4-semantic-production",
            *build_args,
            "--first-count", "1",
            "--mature-count", "1",
            "--output-dir", str(kit_root),
        ])

        manifest = load(kit_root / "field-kit-manifest.json")
        mature_batch_path = kit_root / str(manifest["mature_session"]["batch_manifest"])
        mature_batch = load(mature_batch_path)
        packet_ref = mature_batch["packets"][0]
        tester_id = str(packet_ref["tester_id"])
        packet_dir = (mature_batch_path.parent / str(packet_ref["packet_dir"])).resolve()
        observer_path = packet_dir / "observer-packet.json"
        observer = load(observer_path)
        fill_mature_packet(observer)
        write(observer_path, observer)

        finalizer = kit_root / "FIELD-KIT-FINALIZE.py"
        run([sys.executable, str(finalizer), "--kit-dir", str(kit_root), "--mature-tester", tester_id], cwd=kit_root)
        verifier = kit_root / "FIELD-KIT-VERIFY.py"
        baseline = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], cwd=kit_root)
        if json.loads(baseline.stdout).get("status") != "VERIFIED_OFFLINE":
            fail("canonical finalized mature packet did not verify")

        e4_path = packet_dir / "completed-E4.jsonl"
        receipt_path = packet_dir / "finalization-receipt.json"
        receipt = load(receipt_path)
        qualification = receipt.get("participant_qualification", {})
        if not isinstance(qualification, dict):
            fail("mature receipt qualification missing")
        if qualification.get("e4_binding_scope") != "finalization_snapshot_only":
            fail("E4 finalization snapshot marker missing")
        e4_hash = str(qualification.get("e4_outcome_sha256", ""))
        if len(e4_hash) != 64 or not isinstance(qualification.get("e4_row_count"), int):
            fail("E4 finalization outcome hash/count missing")
        if qualification.get("declaration_only") is not True or qualification.get("proves_human_truth_or_timing") is not False:
            fail("E4 receipt boundary must remain declaration-only/non-proof")

        original_observer = observer_path.read_bytes()
        original_e4 = e4_path.read_bytes()
        original_receipt = receipt_path.read_bytes()

        rows = jsonl(e4_path)
        if len(rows) < 2:
            fail("E4 audit requires both frozen campaign windows")
        rows[0]["window_id"] = rows[1]["window_id"]
        rows[0]["dossier_ids"] = list(rows[1]["dossier_ids"])
        write_jsonl(e4_path, rows)
        mutated_receipt = load(receipt_path)
        refresh_completed_binding(mutated_receipt, e4_path)
        write(receipt_path, mutated_receipt)
        mapped = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], ok=False, cwd=kit_root)
        if "e4 finalized identity mapping mismatch" not in (mapped.stdout + mapped.stderr).lower():
            fail("E4 identity rebound was not rejected against immutable prepared packet identity")

        e4_path.write_bytes(original_e4)
        receipt_path.write_bytes(original_receipt)

        observer = load(observer_path)
        for row in observer["rows_by_gate"]["E4"]:
            row["same_trick_assessment"] = "predominantly_same_trick"
            row["notes"] = "synthetic rebound; not human evidence"
        write(observer_path, observer)
        rows = jsonl(e4_path)
        for row in rows:
            row["same_trick_assessment"] = "predominantly_same_trick"
            row["notes"] = "synthetic rebound; not human evidence"
        write_jsonl(e4_path, rows)
        mutated_receipt = load(receipt_path)
        refresh_completed_binding(mutated_receipt, e4_path)
        write(receipt_path, mutated_receipt)

        attacked = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], ok=False, cwd=kit_root)
        attacked_text = (attacked.stdout + attacked.stderr).lower()
        if "finalized e4 outcome mismatch" not in attacked_text:
            fail("observer+E4-row+digest outcome rebound did not fail at finalization snapshot boundary")

        ingest = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", source_head,
            "--evidence-root", str(evidence_root),
        ], ok=False)
        if "finalized e4 outcome mismatch" not in (ingest.stdout + ingest.stderr).lower():
            fail("repository ingest did not reject E4 outcome rebound through bundled verification")
        if evidence_root.exists() and any(evidence_root.glob("*.jsonl")):
            fail("rejected E4 rebound must append zero empirical evidence")

        observer_path.write_bytes(original_observer)
        e4_path.write_bytes(original_e4)
        receipt_path.write_bytes(original_receipt)
        restored = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], cwd=kit_root)
        if json.loads(restored.stdout).get("status") != "VERIFIED_OFFLINE":
            fail("canonical finalized mature packet did not verify after attack restoration")

    print(
        "Phase 12G E4 semantic binding audit: PASS — finalized window mapping is checked against immutable prepared packet identity; assessment/notes are frozen by a declaration-only finalization snapshot; identity and observer+row+digest rebounds are rejected, ingest appends zero evidence, canonical packet restores cleanly"
    )


if __name__ == "__main__":
    main()
