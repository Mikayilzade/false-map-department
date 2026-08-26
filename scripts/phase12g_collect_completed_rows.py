#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "empirical/phase12g_gate_registry.json"
DEFAULT_EVIDENCE_ROOT = ROOT / "empirical/evidence"
EXTERNAL_CHANNELS = {"human_field_kit_v4", "e8_marketing_packet", "t8_reference_profile"}
ARTIFACT_FIELDS = (
    "source_build_role",
    "build_artifact_sha256",
    "build_artifact_bytes",
    "build_artifact_binding_id",
    "build_artifact_filename",
    "build_artifact_bytes_verified",
)
FORCE_ARTIFACT_ENV = "FMD_PHASE12G_REQUIRE_BUILD_ARTIFACT_BYTES"


def missing(value) -> bool:
    if value is None:
        return True
    if isinstance(value, str) and not value.strip():
        return True
    if isinstance(value, (list, dict)) and not value:
        return True
    return False


def canonical(row: dict) -> str:
    return json.dumps(row, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def load_jsonl(path: Path) -> list[dict]:
    rows: list[dict] = []
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        row = json.loads(raw)
        if not isinstance(row, dict):
            raise SystemExit(f"{path}:{line_no}: row must be an object")
        rows.append(row)
    return rows


def reject_duplicate_input_rows(rows: list[dict]) -> None:
    first_index_by_row: dict[str, int] = {}
    duplicates: list[str] = []
    for index, row in enumerate(rows, start=1):
        key = canonical(row)
        if key in first_index_by_row:
            duplicates.append(f"row {index} duplicates row {first_index_by_row[key]}")
        else:
            first_index_by_row[key] = index
    if duplicates:
        raise SystemExit("input contains duplicate canonical observation rows: " + "; ".join(duplicates))


def expected_role(gate_id: str, channel: str) -> str:
    if channel == "human_field_kit_v4" and gate_id in {"E1", "E2", "E11"}:
        return "demo"
    return "production"


def external_artifact_environment_available() -> bool:
    return bool(os.environ.get("FMD_PHASE12G_BUILD_ARTIFACT_RECORD", "").strip()) and bool(
        os.environ.get("FMD_PHASE12G_BUILD_ARTIFACT_PATH", "").strip()
    )


def verify_external_artifact_rows(rows: list[dict], gate_id: str) -> None:
    record_path = os.environ.get("FMD_PHASE12G_BUILD_ARTIFACT_RECORD", "").strip()
    artifact_path = os.environ.get("FMD_PHASE12G_BUILD_ARTIFACT_PATH", "").strip()
    if not record_path or not artifact_path:
        raise SystemExit(
            "external Phase 12G evidence append requires independently verified packaged build bytes; "
            "set FMD_PHASE12G_BUILD_ARTIFACT_RECORD and FMD_PHASE12G_BUILD_ARTIFACT_PATH. "
            "Without immutable build bytes the gate remains PENDING."
        )
    import phase12g_build_artifact_contract as artifact_contract

    try:
        record = artifact_contract.load_record(Path(record_path).expanduser().resolve())
    except ValueError as exc:
        raise SystemExit(f"build artifact record invalid: {exc}") from exc

    for index, row in enumerate(rows, start=1):
        channel = str(row.get("acquisition_channel", ""))
        if channel not in EXTERNAL_CHANNELS:
            continue
        try:
            verified = artifact_contract.verify_record(
                record,
                artifact_path=Path(artifact_path).expanduser().resolve(),
                source_head=row.get("source_head", ""),
                build_id=row.get("source_build_id", ""),
                role=expected_role(gate_id, channel),
            )
        except ValueError as exc:
            raise SystemExit(f"row {index} build artifact verification failed: {exc}") from exc
        expected = {
            "source_build_role": verified["role"],
            "build_artifact_sha256": verified["artifact_sha256"],
            "build_artifact_bytes": verified["artifact_bytes"],
            "build_artifact_binding_id": verified["binding_id"],
            "build_artifact_filename": verified["artifact_filename"],
            "build_artifact_bytes_verified": True,
        }
        missing_fields = [field for field in ARTIFACT_FIELDS if field not in row]
        if missing_fields:
            raise SystemExit(
                f"row {index} external provenance lacks packaged build byte fields: {', '.join(missing_fields)}"
            )
        for field, value in expected.items():
            if row.get(field) != value:
                raise SystemExit(f"row {index} packaged build provenance conflict for {field}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate completed Phase 12G rows and append only new, complete observations to the evidence root.")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--evidence-root", type=Path, default=DEFAULT_EVIDENCE_ROOT)
    parser.add_argument("--append", action="store_true", help="Actually append validated rows. Without this flag the command is a dry run.")
    args = parser.parse_args()

    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    by_gate = {gate["gate_id"]: gate for gate in registry["gates"]}
    rows = load_jsonl(args.input)
    if not rows:
        raise SystemExit("input contains no rows")
    reject_duplicate_input_rows(rows)

    gate_ids = {str(row.get("gate_id", "")) for row in rows}
    if len(gate_ids) != 1 or "" in gate_ids:
        raise SystemExit("input must contain exactly one non-empty gate_id")
    gate_id = next(iter(gate_ids))
    if gate_id not in by_gate:
        raise SystemExit(f"unknown gate_id: {gate_id}")
    gate = by_gate[gate_id]
    required = list(gate.get("required_fields", []))

    failures: list[str] = []
    for index, row in enumerate(rows, start=1):
        blank = [field for field in required if field not in row or missing(row.get(field))]
        if blank:
            failures.append(f"row {index} missing/blank required fields: {', '.join(blank)}")
    if failures:
        raise SystemExit("\n".join(failures))

    external_rows = [row for row in rows if str(row.get("acquisition_channel", "")) in EXTERNAL_CHANNELS]
    evidence_root = args.evidence_root.resolve()
    enforce_external_artifact = bool(external_rows) and (
        evidence_root == DEFAULT_EVIDENCE_ROOT.resolve() or os.environ.get(FORCE_ARTIFACT_ENV, "") == "1"
    )
    append_ready = not enforce_external_artifact or external_artifact_environment_available()
    if args.append and enforce_external_artifact:
        verify_external_artifact_rows(rows, gate_id)
        append_ready = True

    target = evidence_root / f"{gate_id}.jsonl"
    existing_rows = load_jsonl(target) if target.exists() else []
    existing = {canonical(row) for row in existing_rows}
    novel = [row for row in rows if canonical(row) not in existing]

    result = {
        "gate_id": gate_id,
        "input_rows": len(rows),
        "existing_rows": len(existing_rows),
        "new_rows": len(novel),
        "mode": "append" if args.append else "dry_run",
        "target": str(target),
        "external_build_artifact_required": enforce_external_artifact,
        "build_artifact_bytes_verified": bool(args.append and enforce_external_artifact) or not enforce_external_artifact,
        "append_ready": append_ready,
    }
    print(json.dumps(result, indent=2, sort_keys=True))

    if not args.append or not novel:
        return
    evidence_root.mkdir(parents=True, exist_ok=True)
    with target.open("a", encoding="utf-8") as handle:
        for row in novel:
            handle.write(json.dumps(row, sort_keys=True, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
