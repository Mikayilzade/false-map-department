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
    raise SystemExit(f"PHASE12G E5 SEMANTIC BINDING AUDIT FAIL: {message}")


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


def assert_e5_contract() -> None:
    registry = load(REGISTRY)
    e5 = next((gate for gate in registry.get("gates", []) if isinstance(gate, dict) and gate.get("gate_id") == "E5"), None)
    if not isinstance(e5, dict):
        fail("E5 registry entry missing")
    if e5.get("evidence_class") != "human_playtest" or e5.get("canonical_threshold") is not None:
        fail("E5 evidence/disposition contract changed; re-audit threat model")
    required = ["tester_id", "dossier_id", "requirement_id", "identified_authority_layer", "correct", "tutorial_recall_used"]
    if e5.get("required_fields") != required:
        fail("E5 required fields changed; re-audit threat model")
    protocols = load(PROTOCOLS)
    e5_protocol = protocols.get("protocols", {}).get("E5", {})
    if e5_protocol.get("dossier_selection") != "campaign dossiers with at least 3 map layers":
        fail("E5 dossier-selection contract changed; re-audit threat model")


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
    assert_e5_contract()
    source_head = repository_head()
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-e5-semantic-") as temp:
        root = Path(temp)
        kit_root = root / "kit"
        evidence_root = root / "evidence"
        build_args = kit_build_args(
            root / "source-builds",
            source_head=source_head,
            demo_build_id="e5-semantic-demo",
            production_build_id="e5-semantic-production",
        )
        run([
            sys.executable, str(KIT), "prepare",
            "--source-head", source_head,
            "--demo-build-id", "e5-semantic-demo",
            "--production-build-id", "e5-semantic-production",
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
        prepared_e5 = observer.get("rows_by_gate", {}).get("E5", [])
        if not isinstance(prepared_e5, list) or not prepared_e5:
            fail("E5 audit requires at least one prepared linked-authority row")
        if any(row.get("requirement_id") is not None for row in prepared_e5 if isinstance(row, dict)):
            fail("E5 requirement_id is no longer observation-time scope; re-audit identity model")
        fill_mature_packet(observer)
        write(observer_path, observer)

        finalizer = kit_root / "FIELD-KIT-FINALIZE.py"
        run([sys.executable, str(finalizer), "--kit-dir", str(kit_root), "--mature-tester", tester_id], cwd=kit_root)
        verifier = kit_root / "FIELD-KIT-VERIFY.py"
        baseline = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], cwd=kit_root)
        if json.loads(baseline.stdout).get("status") != "VERIFIED_OFFLINE":
            fail("canonical finalized mature packet did not verify")

        e5_path = packet_dir / "completed-E5.jsonl"
        receipt_path = packet_dir / "finalization-receipt.json"
        receipt = load(receipt_path)
        qualification = receipt.get("participant_qualification", {})
        if not isinstance(qualification, dict):
            fail("mature receipt qualification missing")
        if qualification.get("e5_binding_scope") != "finalization_snapshot_only":
            fail("E5 finalization snapshot marker missing")
        e5_hash = str(qualification.get("e5_semantic_sha256", ""))
        if len(e5_hash) != 64 or not isinstance(qualification.get("e5_row_count"), int):
            fail("E5 finalization semantic hash/count missing")
        if qualification.get("declaration_only") is not True or qualification.get("proves_human_truth_or_timing") is not False:
            fail("E5 receipt boundary must remain declaration-only/non-proof")

        original_observer = observer_path.read_bytes()
        original_e5 = e5_path.read_bytes()
        original_receipt = receipt_path.read_bytes()

        # Attack 1: move a finalized E5 observation to another prepared dossier while
        # refreshing only the completed-file digest. Prepared tester+dossier identity wins.
        rows = jsonl(e5_path)
        if len(rows) >= 2:
            rows[0]["dossier_id"] = rows[1]["dossier_id"]
            write_jsonl(e5_path, rows)
            mutated_receipt = load(receipt_path)
            refresh_completed_binding(mutated_receipt, e5_path)
            write(receipt_path, mutated_receipt)
            mapped = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], ok=False, cwd=kit_root)
            if "e5 finalized identity mapping mismatch" not in (mapped.stdout + mapped.stderr).lower():
                fail("E5 dossier identity rebound was not rejected against immutable prepared packet identity")
            e5_path.write_bytes(original_e5)
            receipt_path.write_bytes(original_receipt)

        # Attack 2: rewrite the observation-time requirement scope and all disposition-
        # relevant E5 declarations in packet+completed rows, then refresh only file digest.
        observer = load(observer_path)
        for row in observer["rows_by_gate"]["E5"]:
            row["requirement_id"] = "REBOUND_REQUIREMENT"
            row["identified_authority_layer"] = "REBOUND_LAYER"
            row["correct"] = False
            row["tutorial_recall_used"] = True
        write(observer_path, observer)
        rows = jsonl(e5_path)
        for row in rows:
            row["requirement_id"] = "REBOUND_REQUIREMENT"
            row["identified_authority_layer"] = "REBOUND_LAYER"
            row["correct"] = False
            row["tutorial_recall_used"] = True
        write_jsonl(e5_path, rows)
        mutated_receipt = load(receipt_path)
        refresh_completed_binding(mutated_receipt, e5_path)
        write(receipt_path, mutated_receipt)

        attacked = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], ok=False, cwd=kit_root)
        if "finalized e5 semantic mismatch" not in (attacked.stdout + attacked.stderr).lower():
            fail("observer+E5-row+digest semantic rebound did not fail at finalization snapshot boundary")

        ingest = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", source_head,
            "--evidence-root", str(evidence_root),
        ], ok=False)
        if "finalized e5 semantic mismatch" not in (ingest.stdout + ingest.stderr).lower():
            fail("repository ingest did not reject E5 semantic rebound through bundled verification")
        if evidence_root.exists() and any(evidence_root.glob("*.jsonl")):
            fail("rejected E5 rebound must append zero empirical evidence")

        observer_path.write_bytes(original_observer)
        e5_path.write_bytes(original_e5)
        receipt_path.write_bytes(original_receipt)
        restored = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], cwd=kit_root)
        if json.loads(restored.stdout).get("status") != "VERIFIED_OFFLINE":
            fail("canonical finalized mature packet did not verify after attack restoration")

    print(
        "Phase 12G E5 semantic binding audit: PASS — prepared tester+dossier identity remains authoritative; observation-time requirement scope plus authority/correctness/tutorial declarations are frozen by a declaration-only finalization snapshot; semantic rebounds are rejected, ingest appends zero evidence, canonical packet restores cleanly"
    )


if __name__ == "__main__":
    main()
