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
HUMAN_FIELD_KIT_CHANNEL = "human_field_kit_v4"
FIRST_SESSION_GATES = {"E1", "E2", "E11"}
MATURE_SESSION_GATES = {"E3", "E4", "E5", "E6", "E9", "E10"}
EXPECTED_EXTERNAL_CHANNEL_BY_GATE = {
    "E1": HUMAN_FIELD_KIT_CHANNEL,
    "E2": HUMAN_FIELD_KIT_CHANNEL,
    "E3": HUMAN_FIELD_KIT_CHANNEL,
    "E4": HUMAN_FIELD_KIT_CHANNEL,
    "E5": HUMAN_FIELD_KIT_CHANNEL,
    "E6": HUMAN_FIELD_KIT_CHANNEL,
    "E8": "e8_marketing_packet",
    "E9": HUMAN_FIELD_KIT_CHANNEL,
    "E10": HUMAN_FIELD_KIT_CHANNEL,
    "E11": HUMAN_FIELD_KIT_CHANNEL,
    "T8-44": "t8_reference_profile",
}
ARTIFACT_FIELDS = (
    "source_build_role",
    "build_artifact_sha256",
    "build_artifact_bytes",
    "build_artifact_binding_id",
    "build_artifact_filename",
    "build_artifact_bytes_verified",
)
FORCE_ARTIFACT_ENV = "FMD_PHASE12G_REQUIRE_BUILD_ARTIFACT_BYTES"
FORCE_CHANNEL_ENV = "FMD_PHASE12G_REQUIRE_CANONICAL_ACQUISITION_CHANNEL"


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


def verify_required_acquisition_channel(rows: list[dict], gate_id: str, evidence_root: Path) -> None:
    """Prevent caller-controlled channel labels from bypassing external evidence safeguards.

    The external human/market/reference-hardware gates each have one prepared ingest path.
    When writing the real repository evidence root (or when an audit explicitly forces this
    check), their rows must retain that canonical channel. Otherwise a caller could remove or
    relabel acquisition_channel and skip the channel-gated qualification/build-byte checks.
    """
    expected = EXPECTED_EXTERNAL_CHANNEL_BY_GATE.get(gate_id)
    if expected is None:
        return
    enforce = evidence_root.resolve() == DEFAULT_EVIDENCE_ROOT.resolve() or os.environ.get(FORCE_CHANNEL_ENV, "") == "1"
    if not enforce:
        return
    for index, row in enumerate(rows, start=1):
        channel = str(row.get("acquisition_channel", "")).strip()
        if channel != expected:
            shown = channel if channel else "<missing>"
            raise SystemExit(
                f"row {index} {gate_id} acquisition_channel must be {expected}; got {shown}. "
                "Use the gate-specific finalized ingest path; relabeling the channel cannot bypass provenance safeguards."
            )


def verify_human_participant_qualification(rows: list[dict], gate_id: str) -> None:
    """Fail closed on declared cohort eligibility carried by receipt-bound field-kit rows.

    These fields preserve the operator's declaration through finalization/ingest. They do not
    prove that the human was actually naive or that rule knowledge was acquired at a particular
    time; those remain empirical/operator facts.
    """
    for index, row in enumerate(rows, start=1):
        if str(row.get("acquisition_channel", "")) != HUMAN_FIELD_KIT_CHANNEL:
            continue
        if gate_id in FIRST_SESSION_GATES:
            naive = row.get("naive")
            if not isinstance(naive, bool):
                raise SystemExit(f"row {index} field-kit first-session evidence must carry receipt-bound naive=true/false qualification")
            if gate_id == "E2" and naive is not True:
                raise SystemExit("row %d E2 evidence is ineligible: canonical second-order prediction gate requires a naive tester" % index)
        if gate_id in MATURE_SESSION_GATES:
            if row.get("rules_known_before_session") is not True:
                raise SystemExit(f"row {index} mature field-kit evidence must carry rules_known_before_session=true")
            if gate_id == "E3" and row.get("rule_knowledge_confirmed") is not True:
                raise SystemExit(f"row {index} E3 evidence is ineligible: comparison must occur after rules are known")


def expected_role(gate_id: str, channel: str) -> str:
    if channel == HUMAN_FIELD_KIT_CHANNEL and gate_id in FIRST_SESSION_GATES:
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

    evidence_root = args.evidence_root.resolve()
    verify_required_acquisition_channel(rows, gate_id, evidence_root)
    verify_human_participant_qualification(rows, gate_id)

    external_rows = [row for row in rows if str(row.get("acquisition_channel", "")) in EXTERNAL_CHANNELS]
    enforce_external_artifact = bool(external_rows) and (
        evidence_root == DEFAULT_EVIDENCE_ROOT.resolve() or os.environ.get(FORCE_ARTIFACT_ENV, "") == "1"
    )
    append_ready = not enforce_external_artifact
    build_artifact_bytes_verified = not enforce_external_artifact
    if enforce_external_artifact:
        if external_artifact_environment_available():
            # A dry run is a readiness check, so environment strings alone are not enough.
            # Recompute the packaged artifact bytes and bind them to every staged row now;
            # otherwise `append_ready=true` would overstate what has actually been verified.
            verify_external_artifact_rows(rows, gate_id)
            append_ready = True
            build_artifact_bytes_verified = True
        elif args.append:
            # Reuse the canonical verifier for the actionable missing-input diagnostic.
            verify_external_artifact_rows(rows, gate_id)

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
        "build_artifact_bytes_verified": build_artifact_bytes_verified,
        "participant_qualification_checked": any(str(row.get("acquisition_channel", "")) == HUMAN_FIELD_KIT_CHANNEL for row in rows),
        "canonical_acquisition_channel_checked": gate_id in EXPECTED_EXTERNAL_CHANNEL_BY_GATE and (
            evidence_root == DEFAULT_EVIDENCE_ROOT.resolve() or os.environ.get(FORCE_CHANNEL_ENV, "") == "1"
        ),
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
