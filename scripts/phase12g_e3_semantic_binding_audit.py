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
    raise SystemExit(f"PHASE12G E3 SEMANTIC BINDING AUDIT FAIL: {message}")


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


def assert_e3_registry_contract() -> None:
    registry = load(REGISTRY)
    e3 = next((gate for gate in registry.get("gates", []) if isinstance(gate, dict) and gate.get("gate_id") == "E3"), None)
    if not isinstance(e3, dict):
        fail("E3 registry entry missing")
    if e3.get("evidence_class") != "human_comparative_playtest" or e3.get("canonical_threshold") is not None:
        fail("E3 evidence/disposition contract changed; re-audit threat model")
    required = ["tester_id", "dossier_id", "method", "completion_seconds", "completed", "rule_knowledge_confirmed"]
    if e3.get("required_fields") != required:
        fail("E3 required fields changed; re-audit threat model")


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
    found = False
    for entry in receipt.get("completed_files", []):
        if isinstance(entry, dict) and Path(str(entry.get("path", ""))).name == completed_path.name:
            entry["sha256"] = sha256_file(completed_path)
            entry["bytes"] = completed_path.stat().st_size
            found = True
    if not found:
        fail(f"receipt binding missing for {completed_path.name}")


def main() -> None:
    assert_e3_registry_contract()
    source_head = repository_head()
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-e3-semantic-") as temp:
        root = Path(temp)
        kit_root = root / "kit"
        evidence_root = root / "evidence"
        build_args = kit_build_args(
            root / "source-builds",
            source_head=source_head,
            demo_build_id="e3-semantic-demo",
            production_build_id="e3-semantic-production",
        )
        run([
            sys.executable, str(KIT), "prepare",
            "--source-head", source_head,
            "--demo-build-id", "e3-semantic-demo",
            "--production-build-id", "e3-semantic-production",
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
        baseline_payload = json.loads(baseline.stdout)
        if baseline_payload.get("status") != "VERIFIED_OFFLINE":
            fail("canonical finalized mature packet did not verify")

        e3_path = packet_dir / "completed-E3.jsonl"
        receipt_path = packet_dir / "finalization-receipt.json"
        receipt = load(receipt_path)
        qualification = receipt.get("participant_qualification", {})
        if not isinstance(qualification, dict):
            fail("mature receipt qualification missing")
        if qualification.get("e3_binding_scope") != "finalization_snapshot_only":
            fail("E3 finalization snapshot marker missing")
        if not isinstance(qualification.get("e3_row_count"), int) or qualification.get("e3_row_count") < 1:
            fail("E3 finalization row-count snapshot missing")
        e3_hash = str(qualification.get("e3_outcome_sha256", ""))
        if len(e3_hash) != 64:
            fail("E3 finalization outcome hash missing")
        if qualification.get("declaration_only") is not True or qualification.get("proves_human_truth_or_timing") is not False:
            fail("E3 receipt boundary must remain declaration-only/non-proof")

        original_observer = observer_path.read_bytes()
        original_e3 = e3_path.read_bytes()
        original_receipt = receipt_path.read_bytes()

        # Attack 1: remap a finalized E3 row to the other comparison method while
        # preserving the immutable prepared observer packet, then refresh only the
        # completed-file digest. The verifier must use prepared identity authority.
        rows = jsonl(e3_path)
        rows[0]["method"] = "systematic_legal_edit_search" if rows[0]["method"] != "systematic_legal_edit_search" else "causal_reasoning"
        write_jsonl(e3_path, rows)
        mutated_receipt = load(receipt_path)
        refresh_completed_binding(mutated_receipt, e3_path)
        write(receipt_path, mutated_receipt)
        mapped = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], ok=False, cwd=kit_root)
        if "e3 finalized identity mapping mismatch" not in (mapped.stdout + mapped.stderr).lower():
            fail("E3 method rebound was not rejected against immutable prepared packet identity")

        e3_path.write_bytes(original_e3)
        receipt_path.write_bytes(original_receipt)

        # Attack 2: change mutable observer outcome fields and finalized E3 outcome
        # together, then refresh the completed-file digest. Prepared identity still
        # verifies because outcomes are intentionally mutable pre-finalization; the
        # independent finalization snapshot must now reject the rebound.
        observer = load(observer_path)
        first_observed = observer["rows_by_gate"]["E3"][0]
        first_observed["completion_seconds"] = 1.0
        first_observed["completed"] = False
        write(observer_path, observer)
        rows = jsonl(e3_path)
        rows[0]["completion_seconds"] = 1.0
        rows[0]["completed"] = False
        write_jsonl(e3_path, rows)
        mutated_receipt = load(receipt_path)
        refresh_completed_binding(mutated_receipt, e3_path)
        write(receipt_path, mutated_receipt)

        attacked = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], ok=False, cwd=kit_root)
        attacked_text = (attacked.stdout + attacked.stderr).lower()
        if "finalized e3 outcome semantic mismatch" not in attacked_text:
            fail("observer+E3-row+digest outcome rebound did not fail at finalization snapshot boundary")

        ingest = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", source_head,
            "--evidence-root", str(evidence_root),
        ], ok=False)
        if "finalized e3 outcome semantic mismatch" not in (ingest.stdout + ingest.stderr).lower():
            fail("repository ingest did not reject E3 outcome rebound through bundled verification")
        if evidence_root.exists() and any(evidence_root.glob("*.jsonl")):
            fail("rejected E3 rebound must append zero empirical evidence")

        observer_path.write_bytes(original_observer)
        e3_path.write_bytes(original_e3)
        receipt_path.write_bytes(original_receipt)
        restored = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], cwd=kit_root)
        if json.loads(restored.stdout).get("status") != "VERIFIED_OFFLINE":
            fail("canonical finalized mature packet did not verify after attack restoration")

    print(
        "Phase 12G E3 semantic binding audit: PASS — finalized method mapping is checked against immutable prepared packet identity; completion timing/outcome is frozen by a declaration-only finalization snapshot; method and observer+row+digest rebounds are rejected, ingest appends zero evidence, canonical packet restores cleanly"
    )


if __name__ == "__main__":
    main()
