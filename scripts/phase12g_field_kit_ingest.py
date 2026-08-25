#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = Path(__file__).resolve().parent
COLLECTOR = ROOT / "scripts/phase12g_collect_completed_rows.py"
HUMAN_GATES = ("E1", "E2", "E3", "E4", "E5", "E6", "E9", "E10", "E11")
RECEIPT_SCHEMA = "fmd.phase12g.field-kit-finalization-receipt.v1"

sys.path.insert(0, str(SCRIPT_DIR))
import phase12g_provenance as provenance  # noqa: E402


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G FIELD KIT INGEST FAIL: {message}")


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"{path}: unreadable JSON: {exc}")
    if not isinstance(value, dict):
        fail(f"{path}: expected JSON object")
    return value


def load_jsonl(path: Path) -> list[dict]:
    rows: list[dict] = []
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        try:
            value = json.loads(raw)
        except json.JSONDecodeError as exc:
            fail(f"{path}:{line_no}: malformed JSON row: {exc}")
        if not isinstance(value, dict):
            fail(f"{path}:{line_no}: row must be an object")
        rows.append(value)
    if not rows:
        fail(f"{path}: completed file contains no rows")
    return rows


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_sha(value: str, label: str) -> str:
    sha = value.strip().lower()
    if len(sha) != 40 or any(ch not in "0123456789abcdef" for ch in sha):
        fail(f"{label} must be an exact 40-character Git commit SHA")
    return sha


def resolve_inside(root: Path, raw_value: object, label: str) -> Path:
    raw = Path(str(raw_value))
    if raw.is_absolute() or ".." in raw.parts:
        fail(f"{label} must stay relative to field-kit root")
    candidate = (root / raw).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        fail(f"{label} escapes field-kit root")
    return candidate


def verify_offline(kit_root: Path, manifest: dict) -> None:
    verifier_contract = manifest.get("offline_verifier", {})
    if not isinstance(verifier_contract, dict):
        fail("offline verifier contract missing")
    verifier = resolve_inside(kit_root, verifier_contract.get("path", ""), "offline verifier path")
    if not verifier.exists():
        fail("bundled offline verifier missing")
    completed = subprocess.run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], cwd=kit_root, text=True, capture_output=True)
    if completed.returncode != 0:
        fail(f"bundled verifier rejected returned kit: {(completed.stdout + completed.stderr).strip()}")
    try:
        result = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        fail(f"bundled verifier returned malformed JSON: {exc}")
    if not isinstance(result, dict) or result.get("status") != "VERIFIED_OFFLINE":
        fail("bundled verifier returned unexpected disposition")


def completed_files(kit_root: Path) -> dict[str, list[Path]]:
    found: dict[str, list[Path]] = {gate: [] for gate in HUMAN_GATES}
    for path in sorted(kit_root.rglob("completed-*.jsonl")):
        try:
            path.resolve().relative_to(kit_root.resolve())
        except ValueError:
            fail(f"completed-row path escapes kit root: {path}")
        gate_id = path.name.removeprefix("completed-").removesuffix(".jsonl")
        if gate_id not in found:
            fail(f"unexpected completed gate file: {path}")
        found[gate_id].append(path)
    return found


def verify_finalization_receipts(kit_root: Path, manifest: dict, files_by_gate: dict[str, list[Path]]) -> dict[str, str]:
    completed_paths = sorted(path.resolve() for paths in files_by_gate.values() for path in paths)
    receipts = sorted(kit_root.rglob("finalization-receipt.json"))
    if not receipts:
        fail("completed observed-row files require offline finalization receipt(s)")
    bound: dict[Path, str] = {}
    for receipt_path in receipts:
        receipt = load_json(receipt_path)
        if receipt.get("schema") != RECEIPT_SCHEMA:
            fail(f"{receipt_path}: unsupported finalization receipt schema")
        if str(receipt.get("source_head", "")) != str(manifest.get("source_head", "")):
            fail(f"{receipt_path}: finalization receipt source_head mismatch")
        if str(receipt.get("field_kit_contract_hash", "")) != str(manifest.get("contract_hash", "")):
            fail(f"{receipt_path}: finalization receipt field-kit contract mismatch")
        if str(receipt.get("demo_build_id", "")) != str(manifest.get("demo_build_id", "")) or str(receipt.get("production_build_id", "")) != str(manifest.get("production_build_id", "")):
            fail(f"{receipt_path}: finalization receipt build identity mismatch")
        finalizer_contract = manifest.get("offline_finalizer", {})
        if not isinstance(finalizer_contract, dict) or str(receipt.get("finalizer_sha256", "")) != str(finalizer_contract.get("sha256", "")):
            fail(f"{receipt_path}: finalization receipt finalizer binding mismatch")
        if receipt.get("human_outcomes_inferred") is not False or receipt.get("repository_evidence_appended") is not False:
            fail(f"{receipt_path}: finalization receipt empirical boundary markers invalid")
        entries = receipt.get("completed_files", [])
        if not isinstance(entries, list) or not entries:
            fail(f"{receipt_path}: finalization receipt contains no completed-file bindings")
        for entry in entries:
            if not isinstance(entry, dict):
                fail(f"{receipt_path}: malformed completed-file binding")
            path = resolve_inside(kit_root, entry.get("path", ""), "receipt completed-file path")
            if not path.exists() or not path.is_file():
                fail(f"{receipt_path}: receipt-bound completed file missing: {path}")
            if path in bound:
                fail(f"{receipt_path}: completed file bound by multiple receipts: {path}")
            expected_bytes = entry.get("bytes")
            if isinstance(expected_bytes, bool) or not isinstance(expected_bytes, int) or expected_bytes < 0:
                fail(f"{receipt_path}: invalid receipt byte length for {path}")
            if path.stat().st_size != expected_bytes:
                fail(f"{path}: completed file changed after offline finalization (size mismatch)")
            expected_hash = str(entry.get("sha256", ""))
            if len(expected_hash) != 64 or any(ch not in "0123456789abcdef" for ch in expected_hash):
                fail(f"{receipt_path}: invalid receipt SHA-256 for {path}")
            actual_hash = sha256_file(path)
            if actual_hash != expected_hash:
                fail(f"{path}: completed file changed after offline finalization (digest mismatch)")
            bound[path] = actual_hash
    missing = [path for path in completed_paths if path not in bound]
    extra = [path for path in bound if path not in completed_paths]
    if missing:
        fail(f"completed file(s) missing finalization receipt binding: {[str(p.relative_to(kit_root)) for p in missing]}")
    if extra:
        fail(f"finalization receipt binds unexpected completed file(s): {[str(p.relative_to(kit_root)) for p in extra]}")
    return {path.relative_to(kit_root).as_posix(): digest for path, digest in sorted(bound.items(), key=lambda item: str(item[0]))}


def run_collector(path: Path, evidence_root: Path, append: bool) -> dict:
    command = [sys.executable, str(COLLECTOR), "--input", str(path), "--evidence-root", str(evidence_root)]
    if append:
        command.append("--append")
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    if completed.returncode != 0:
        fail(f"collector rejected {path}: {(completed.stdout + completed.stderr).strip()}")
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        fail(f"collector returned malformed JSON for {path}: {exc}")
    if not isinstance(payload, dict):
        fail(f"collector returned non-object for {path}")
    return payload


def build_id_for_gate(manifest: dict, gate_id: str) -> str:
    key = "demo_build_id" if gate_id in {"E1", "E2", "E11"} else "production_build_id"
    value = str(manifest.get(key, "")).strip()
    if not value:
        fail(f"field-kit manifest missing {key} for {gate_id}")
    return value


def staged_with_provenance(path: Path, gate_id: str, manifest: dict, source_head: str, kit_root: Path) -> Path:
    try:
        rows = provenance.enrich_rows(load_jsonl(path), source_head=source_head, build_id=build_id_for_gate(manifest, gate_id), channel="human_field_kit_v4")
    except ValueError as exc:
        fail(f"{path}: {exc}")
    handle = tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", prefix=f".repository-ingest-{gate_id}-", suffix=".jsonl", dir=kit_root, delete=False)
    staged = Path(handle.name)
    try:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True, ensure_ascii=False) + "\n")
    finally:
        handle.close()
    return staged


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify a returned Phase 12G human field kit and deliberately dry-run or append only receipt-bound completed observed rows.")
    parser.add_argument("--kit-dir", type=Path, required=True)
    parser.add_argument("--expected-source-head", required=True)
    parser.add_argument("--evidence-root", type=Path, default=ROOT / "empirical/evidence")
    parser.add_argument("--append", action="store_true", help="Deliberately append validated novel rows. Default is dry-run only.")
    args = parser.parse_args()

    kit_root = args.kit_dir.resolve()
    manifest = load_json(kit_root / "field-kit-manifest.json")
    expected_source = validate_sha(args.expected_source_head, "--expected-source-head")
    manifest_source = validate_sha(str(manifest.get("source_head", "")), "field-kit manifest source_head")
    if manifest_source != expected_source:
        fail(f"source-head mismatch: expected {expected_source}, kit has {manifest_source}")
    if manifest.get("prepared_packets_are_not_evidence") is not True or manifest.get("human_outcomes_required") is not True:
        fail("field-kit empirical boundary markers missing")
    if manifest.get("repository_evidence_appended") is not False:
        fail("returned kit claims repository evidence was already appended")

    verify_offline(kit_root, manifest)
    files_by_gate = completed_files(kit_root)
    present = {gate: paths for gate, paths in files_by_gate.items() if paths}
    if not present:
        fail("returned kit contains no completed observed-row files")
    receipt_digests = verify_finalization_receipts(kit_root, manifest, files_by_gate)

    results: list[dict] = []
    for gate_id in HUMAN_GATES:
        for path in files_by_gate[gate_id]:
            staged = staged_with_provenance(path, gate_id, manifest, manifest_source, kit_root)
            try:
                result = run_collector(staged, args.evidence_root.resolve(), args.append)
            finally:
                staged.unlink(missing_ok=True)
            if str(result.get("gate_id", "")) != gate_id:
                fail(f"collector gate mismatch for {path}")
            results.append({"source": str(path.relative_to(kit_root)), "finalized_sha256": receipt_digests[str(path.relative_to(kit_root)).replace('\\', '/')], **result})

    print(json.dumps({
        "status": "APPENDED" if args.append else "VALIDATED_DRY_RUN",
        "source_head": manifest_source,
        "kit_verified_offline": True,
        "finalization_receipts_verified": True,
        "completed_file_digests_verified": len(receipt_digests),
        "provenance_persisted_in_rows": True,
        "append_requested": args.append,
        "completed_file_count": len(results),
        "completed_gate_ids": sorted(present),
        "results": results,
        "human_outcomes_inferred": False,
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
