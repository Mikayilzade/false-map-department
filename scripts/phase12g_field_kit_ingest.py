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
FIRST_SESSION_GATES = {"E1", "E2", "E11"}
MATURE_SESSION_GATES = {"E3", "E4", "E5", "E6", "E9", "E10"}
RECEIPT_SCHEMA = "fmd.phase12g.field-kit-finalization-receipt.v1"
FIELD_KIT_CHANNEL = "human_field_kit_v4"
RETURN_IDENTITY_FIELDS = (
    "field_kit_return_namespace",
    "field_kit_packet_kind",
    "field_kit_contract_hash",
    "field_kit_finalization_receipt_sha256",
)

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


def repository_checkout_head() -> str:
    completed = subprocess.run(
        ["git", "rev-parse", "--verify", "HEAD"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        fail(f"repository checkout HEAD unavailable: {(completed.stdout + completed.stderr).strip()}")
    return validate_sha(completed.stdout.strip(), "repository checkout HEAD")


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


def return_namespace(receipt: dict, receipt_path: Path) -> str:
    packet_kind = str(receipt.get("packet_kind", ""))
    if packet_kind == "first_session":
        session_id = str(receipt.get("session_id", "")).strip()
        if not session_id:
            fail(f"{receipt_path}: first-session finalization receipt missing session_id")
        return f"first_session:{session_id}"
    if packet_kind == "mature_session":
        tester_id = str(receipt.get("tester_id", "")).strip()
        if not tester_id:
            fail(f"{receipt_path}: mature-session finalization receipt missing tester_id")
        return f"mature_session:{tester_id}"
    fail(f"{receipt_path}: unsupported packet_kind for return identity: {packet_kind!r}")


def verify_receipt_packet_identity(receipt_path: Path, receipt: dict) -> dict:
    packet_kind = str(receipt.get("packet_kind", ""))
    receipt_tester = str(receipt.get("tester_id", "")).strip()
    receipt_session = str(receipt.get("session_id", "")).strip()
    if not receipt_tester:
        fail(f"{receipt_path}: finalization receipt missing tester_id")
    if packet_kind == "first_session":
        manifest_path = receipt_path.parent / "session-manifest.json"
        packet = load_json(manifest_path)
        packet_tester = str(packet.get("tester_id", "")).strip()
        packet_session = str(packet.get("session_id", "")).strip()
        if not packet_tester or not packet_session:
            fail(f"{manifest_path}: immutable first-session packet identity missing")
        if receipt_tester != packet_tester or receipt_session != packet_session:
            fail(f"{receipt_path}: receipt identity does not match immutable first-session packet identity")
        return {"tester_id": packet_tester, "session_id": packet_session}
    if packet_kind == "mature_session":
        packet_path = receipt_path.parent / "observer-packet.json"
        packet = load_json(packet_path)
        packet_tester = str(packet.get("tester_id", "")).strip()
        if not packet_tester:
            fail(f"{packet_path}: immutable mature-session packet tester identity missing")
        if receipt_tester != packet_tester or receipt_session:
            fail(f"{receipt_path}: receipt identity does not match immutable mature-session packet identity")
        return {"tester_id": packet_tester, "session_id": ""}
    fail(f"{receipt_path}: unsupported packet_kind for immutable packet identity")


def verify_completed_row_identity(path: Path, gate_id: str, binding: dict, rows: list[dict]) -> None:
    packet_kind = str(binding.get("packet_kind", ""))
    tester_id = str(binding.get("packet_tester_id", ""))
    session_id = str(binding.get("packet_session_id", ""))
    expected_gates = FIRST_SESSION_GATES if packet_kind == "first_session" else MATURE_SESSION_GATES
    if gate_id not in expected_gates:
        fail(f"{path}: {packet_kind} receipt cannot bind completed {gate_id} rows")
    for index, row in enumerate(rows, start=1):
        if str(row.get("tester_id", "")).strip() != tester_id:
            fail(f"{path}:{index}: completed-row tester_id does not match immutable packet identity")
        if packet_kind == "first_session" and gate_id in {"E1", "E2"}:
            if str(row.get("session_id", "")).strip() != session_id:
                fail(f"{path}:{index}: completed-row session_id does not match immutable first-session packet identity")


def verify_finalization_receipts(kit_root: Path, manifest: dict, files_by_gate: dict[str, list[Path]]) -> dict[str, dict]:
    completed_paths = sorted(path.resolve() for paths in files_by_gate.values() for path in paths)
    receipts = sorted(kit_root.rglob("finalization-receipt.json"))
    if not receipts:
        fail("completed observed-row files require offline finalization receipt(s)")
    bound: dict[Path, dict] = {}
    namespace_identity: dict[str, tuple[str, str, str, str, str]] = {}
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
        packet_identity = verify_receipt_packet_identity(receipt_path, receipt)
        namespace = return_namespace(receipt, receipt_path)
        receipt_digest = sha256_file(receipt_path)
        identity = (
            str(receipt.get("packet_kind", "")),
            str(receipt.get("source_head", "")),
            str(receipt.get("field_kit_contract_hash", "")),
            str(receipt.get("demo_build_id", "")),
            str(receipt.get("production_build_id", "")),
        )
        prior_identity = namespace_identity.get(namespace)
        if prior_identity is not None and prior_identity != identity:
            fail(f"{receipt_path}: return namespace collision inside returned kit: {namespace}")
        namespace_identity[namespace] = identity
        entries = receipt.get("completed_files", [])
        if not isinstance(entries, list) or not entries:
            fail(f"{receipt_path}: finalization receipt contains no completed-file bindings")
        for entry in entries:
            if not isinstance(entry, dict):
                fail(f"{receipt_path}: malformed completed-file binding")
            path = resolve_inside(kit_root, entry.get("path", ""), "receipt completed-file path")
            if path.parent.resolve() != receipt_path.parent.resolve():
                fail(f"{receipt_path}: receipt may bind completed files only inside its own immutable packet directory")
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
            gate_id = path.name.removeprefix("completed-").removesuffix(".jsonl")
            rows = load_jsonl(path)
            binding = {
                "completed_file_sha256": actual_hash,
                "return_namespace": namespace,
                "packet_kind": str(receipt.get("packet_kind", "")),
                "field_kit_contract_hash": str(receipt.get("field_kit_contract_hash", "")),
                "finalization_receipt_sha256": receipt_digest,
                "packet_tester_id": packet_identity["tester_id"],
                "packet_session_id": packet_identity["session_id"],
            }
            verify_completed_row_identity(path, gate_id, binding, rows)
            bound[path] = binding
    missing = [path for path in completed_paths if path not in bound]
    extra = [path for path in bound if path not in completed_paths]
    if missing:
        fail(f"completed file(s) missing finalization receipt binding: {[str(p.relative_to(kit_root)) for p in missing]}")
    if extra:
        fail(f"finalization receipt binds unexpected completed file(s): {[str(p.relative_to(kit_root)) for p in extra]}")
    return {
        path.relative_to(kit_root).as_posix(): binding
        for path, binding in sorted(bound.items(), key=lambda item: str(item[0]))
    }


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


def identity_tuple(row: dict) -> tuple[str, str, str, str, str, str]:
    return (
        str(row.get("field_kit_packet_kind", "")),
        str(row.get("field_kit_contract_hash", "")),
        str(row.get("field_kit_finalization_receipt_sha256", "")),
        str(row.get("source_head", "")),
        str(row.get("source_build_id", "")),
        str(row.get("acquisition_channel", "")),
    )


def existing_return_identities(evidence_root: Path) -> dict[str, tuple[str, str, str, str, str, str]]:
    identities: dict[str, tuple[str, str, str, str, str, str]] = {}
    for gate_id in HUMAN_GATES:
        path = evidence_root / f"{gate_id}.jsonl"
        if not path.exists():
            continue
        for row in load_jsonl(path):
            if str(row.get("acquisition_channel", "")) != FIELD_KIT_CHANNEL:
                continue
            missing = [field for field in RETURN_IDENTITY_FIELDS if not str(row.get(field, "")).strip()]
            if missing:
                fail(f"{path}: existing field-kit evidence missing durable return identity fields: {', '.join(missing)}")
            namespace = str(row["field_kit_return_namespace"])
            identity = identity_tuple(row)
            prior = identities.get(namespace)
            if prior is not None and prior != identity:
                fail(f"{path}: existing field-kit return namespace collision: {namespace}")
            identities[namespace] = identity
    return identities


def ensure_return_identity_compatible(evidence_root: Path, rows: list[dict]) -> None:
    existing = existing_return_identities(evidence_root)
    proposed: dict[str, tuple[str, str, str, str, str, str]] = {}
    for row in rows:
        namespace = str(row.get("field_kit_return_namespace", ""))
        if not namespace:
            fail("staged field-kit row missing return namespace")
        identity = identity_tuple(row)
        prior_proposed = proposed.get(namespace)
        if prior_proposed is not None and prior_proposed != identity:
            fail(f"proposed field-kit rows conflict under return namespace: {namespace}")
        proposed[namespace] = identity
        prior_existing = existing.get(namespace)
        if prior_existing is not None and prior_existing != identity:
            fail(f"field-kit return namespace collision with existing evidence: {namespace}; use a new session/tester namespace for a distinct finalized return")


def staged_with_provenance(path: Path, gate_id: str, manifest: dict, source_head: str, kit_root: Path, binding: dict) -> tuple[Path, list[dict]]:
    try:
        rows = provenance.enrich_rows(load_jsonl(path), source_head=source_head, build_id=build_id_for_gate(manifest, gate_id), channel=FIELD_KIT_CHANNEL)
    except ValueError as exc:
        fail(f"{path}: {exc}")
    enriched: list[dict] = []
    for row in rows:
        item = dict(row)
        item.update({
            "field_kit_return_namespace": str(binding["return_namespace"]),
            "field_kit_packet_kind": str(binding["packet_kind"]),
            "field_kit_contract_hash": str(binding["field_kit_contract_hash"]),
            "field_kit_finalization_receipt_sha256": str(binding["finalization_receipt_sha256"]),
        })
        enriched.append(item)
    handle = tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", prefix=f".repository-ingest-{gate_id}-", suffix=".jsonl", dir=kit_root, delete=False)
    staged = Path(handle.name)
    try:
        for row in enriched:
            handle.write(json.dumps(row, sort_keys=True, ensure_ascii=False) + "\n")
    finally:
        handle.close()
    return staged, enriched


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify a returned Phase 12G human field kit and deliberately dry-run or append only receipt-bound completed observed rows.")
    parser.add_argument("--kit-dir", type=Path, required=True)
    parser.add_argument("--expected-source-head", required=True)
    parser.add_argument("--evidence-root", type=Path, default=ROOT / "empirical/evidence")
    parser.add_argument("--append", action="store_true", help="Deliberately append validated novel rows. Default is dry-run only.")
    args = parser.parse_args()

    kit_root = args.kit_dir.resolve()
    evidence_root = args.evidence_root.resolve()
    manifest = load_json(kit_root / "field-kit-manifest.json")
    expected_source = validate_sha(args.expected_source_head, "--expected-source-head")
    checkout_source = repository_checkout_head()
    if checkout_source != expected_source:
        fail(f"repository checkout source-head mismatch: checkout {checkout_source}, expected {expected_source}; checkout the exact field-kit source commit before ingest")
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
    receipt_bindings = verify_finalization_receipts(kit_root, manifest, files_by_gate)

    results: list[dict] = []
    for gate_id in HUMAN_GATES:
        for path in files_by_gate[gate_id]:
            rel = str(path.relative_to(kit_root)).replace("\\", "/")
            binding = receipt_bindings[rel]
            staged, staged_rows = staged_with_provenance(path, gate_id, manifest, manifest_source, kit_root, binding)
            try:
                ensure_return_identity_compatible(evidence_root, staged_rows)
                result = run_collector(staged, evidence_root, args.append)
            finally:
                staged.unlink(missing_ok=True)
            if str(result.get("gate_id", "")) != gate_id:
                fail(f"collector gate mismatch for {path}")
            results.append({
                "source": rel,
                "finalized_sha256": str(binding["completed_file_sha256"]),
                "return_namespace": str(binding["return_namespace"]),
                **result,
            })

    print(json.dumps({
        "status": "APPENDED" if args.append else "VALIDATED_DRY_RUN",
        "source_head": manifest_source,
        "repository_checkout_head": checkout_source,
        "kit_verified_offline": True,
        "finalization_receipts_verified": True,
        "completed_file_digests_verified": len(receipt_bindings),
        "return_identity_verified": True,
        "packet_identity_verified": True,
        "provenance_persisted_in_rows": True,
        "append_requested": args.append,
        "completed_file_count": len(results),
        "completed_gate_ids": sorted(present),
        "results": results,
        "human_outcomes_inferred": False,
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
