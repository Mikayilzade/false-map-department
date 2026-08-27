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
    raise SystemExit(f"PHASE12G E6 SEMANTIC BINDING AUDIT FAIL: {message}")


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


def assert_e6_contract() -> None:
    registry = load(REGISTRY)
    e6 = next((gate for gate in registry.get("gates", []) if isinstance(gate, dict) and gate.get("gate_id") == "E6"), None)
    if not isinstance(e6, dict):
        fail("E6 registry entry missing")
    if e6.get("evidence_class") != "human_playtest" or e6.get("canonical_threshold") is not None:
        fail("E6 evidence/disposition contract changed; re-audit threat model")
    required = ["tester_id", "dossier_id", "requirement_id", "answered_cause", "used_raw_debug_log", "correct"]
    if e6.get("required_fields") != required:
        fail("E6 required fields changed; re-audit threat model")
    protocols = load(PROTOCOLS)
    e6_protocol = protocols.get("protocols", {}).get("E6", {})
    if e6_protocol.get("dossier_ids") != [f"D{index:02d}" for index in range(33, 41)]:
        fail("E6 representative dossier contract changed; re-audit threat model")


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
    for index, row in enumerate(rows_by_gate.get("E5", []), start=1):
        row["requirement_id"] = f"AUDIT_REQ_{index:02d}"
        row["identified_authority_layer"] = f"AUDIT_LAYER_{index:02d}"
        row["correct"] = True
        row["tutorial_recall_used"] = False
    for index, row in enumerate(rows_by_gate.get("E6", []), start=1):
        row["requirement_id"] = f"AUDIT_CAUSE_REQ_{index:02d}"
        row["answered_cause"] = f"synthetic audit cause {index}; not human evidence"
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
    assert_e6_contract()
    source_head = repository_head()
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-e6-semantic-") as temp:
        root = Path(temp)
        kit_root = root / "kit"
        evidence_root = root / "evidence"
        build_args = kit_build_args(
            root / "source-builds",
            source_head=source_head,
            demo_build_id="e6-semantic-demo",
            production_build_id="e6-semantic-production",
        )
        run([
            sys.executable, str(KIT), "prepare",
            "--source-head", source_head,
            "--demo-build-id", "e6-semantic-demo",
            "--production-build-id", "e6-semantic-production",
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
        prepared_e6 = observer.get("rows_by_gate", {}).get("E6", [])
        if not isinstance(prepared_e6, list) or not prepared_e6:
            fail("E6 audit requires at least one prepared causal-readability row")
        if any(row.get("requirement_id") is not None for row in prepared_e6 if isinstance(row, dict)):
            fail("E6 requirement_id is no longer observation-time scope; re-audit identity model")
        fill_mature_packet(observer)
        write(observer_path, observer)

        finalizer = kit_root / "FIELD-KIT-FINALIZE.py"
        run([sys.executable, str(finalizer), "--kit-dir", str(kit_root), "--mature-tester", tester_id], cwd=kit_root)
        verifier = kit_root / "FIELD-KIT-VERIFY.py"
        baseline = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], cwd=kit_root)
        if json.loads(baseline.stdout).get("status") != "VERIFIED_OFFLINE":
            fail("canonical finalized mature packet did not verify")

        e6_path = packet_dir / "completed-E6.jsonl"
        receipt_path = packet_dir / "finalization-receipt.json"
        receipt = load(receipt_path)
        qualification = receipt.get("participant_qualification", {})
        if not isinstance(qualification, dict):
            fail("mature receipt qualification missing")
        if qualification.get("e6_binding_scope") != "finalization_snapshot_only":
            fail("E6 finalization snapshot marker missing")
        e6_hash = str(qualification.get("e6_semantic_sha256", ""))
        if len(e6_hash) != 64 or not isinstance(qualification.get("e6_row_count"), int):
            fail("E6 finalization semantic hash/count missing")
        if qualification.get("declaration_only") is not True or qualification.get("proves_human_truth_or_timing") is not False:
            fail("E6 receipt boundary must remain declaration-only/non-proof")

        original_observer = observer_path.read_bytes()
        original_e6 = e6_path.read_bytes()
        original_receipt = receipt_path.read_bytes()

        rows = jsonl(e6_path)
        if len(rows) >= 2:
            rows[0]["dossier_id"] = rows[1]["dossier_id"]
            write_jsonl(e6_path, rows)
            mutated_receipt = load(receipt_path)
            refresh_completed_binding(mutated_receipt, e6_path)
            write(receipt_path, mutated_receipt)
            mapped = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], ok=False, cwd=kit_root)
            if "e6 finalized identity mapping mismatch" not in (mapped.stdout + mapped.stderr).lower():
                fail("E6 dossier identity rebound was not rejected against immutable prepared packet identity")
            e6_path.write_bytes(original_e6)
            receipt_path.write_bytes(original_receipt)

        observer = load(observer_path)
        for row in observer["rows_by_gate"]["E6"]:
            row["requirement_id"] = "REBOUND_REQUIREMENT"
            row["answered_cause"] = "rebound causal answer"
            row["used_raw_debug_log"] = False
            row["correct"] = False
        write(observer_path, observer)
        rows = jsonl(e6_path)
        for row in rows:
            row["requirement_id"] = "REBOUND_REQUIREMENT"
            row["answered_cause"] = "rebound causal answer"
            row["used_raw_debug_log"] = False
            row["correct"] = False
        write_jsonl(e6_path, rows)
        mutated_receipt = load(receipt_path)
        refresh_completed_binding(mutated_receipt, e6_path)
        write(receipt_path, mutated_receipt)

        attacked = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], ok=False, cwd=kit_root)
        if "finalized e6 semantic mismatch" not in (attacked.stdout + attacked.stderr).lower():
            fail("observer+E6-row+digest semantic rebound did not fail at finalization snapshot boundary")

        ingest = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", source_head,
            "--evidence-root", str(evidence_root),
        ], ok=False)
        if "finalized e6 semantic mismatch" not in (ingest.stdout + ingest.stderr).lower():
            fail("repository ingest did not reject E6 semantic rebound through bundled verification")
        if evidence_root.exists() and any(evidence_root.glob("*.jsonl")):
            fail("rejected E6 rebound must append zero empirical evidence")

        observer_path.write_bytes(original_observer)
        e6_path.write_bytes(original_e6)
        receipt_path.write_bytes(original_receipt)
        restored = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], cwd=kit_root)
        if json.loads(restored.stdout).get("status") != "VERIFIED_OFFLINE":
            fail("canonical finalized mature packet did not verify after attack restoration")

    print(
        "Phase 12G E6 semantic binding audit: PASS — prepared tester+dossier identity remains authoritative; observation-time requirement scope plus causal-answer/debug/correctness declarations are frozen by a declaration-only finalization snapshot; semantic rebounds are rejected, ingest appends zero evidence, canonical packet restores cleanly"
    )


if __name__ == "__main__":
    main()
