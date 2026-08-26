#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EVIDENCE_ROOT = ROOT / "empirical/evidence"
HUMAN_GATES = ("E1", "E2", "E3", "E4", "E5", "E6", "E9", "E10", "E11")
FIELD_KIT_CHANNEL = "human_field_kit_v4"
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA64 = re.compile(r"^[0-9a-f]{64}$")
REQUIRED_FIELDS = (
    "field_kit_return_namespace",
    "field_kit_packet_kind",
    "field_kit_contract_hash",
    "field_kit_finalization_receipt_sha256",
    "source_head",
    "source_build_id",
)


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G HUMAN RETURN IDENTITY INTEGRITY FAIL: {message}")


def load_rows(path: Path) -> list[dict]:
    rows: list[dict] = []
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        try:
            value = json.loads(raw)
        except json.JSONDecodeError as exc:
            fail(f"{path}:{line_no}: malformed JSON: {exc}")
        if not isinstance(value, dict):
            fail(f"{path}:{line_no}: row must be an object")
        rows.append(value)
    return rows


def identity_tuple(row: dict) -> tuple[str, str, str, str, str, str]:
    return (
        str(row.get("field_kit_packet_kind", "")),
        str(row.get("field_kit_contract_hash", "")),
        str(row.get("field_kit_finalization_receipt_sha256", "")),
        str(row.get("source_head", "")),
        str(row.get("source_build_id", "")),
        str(row.get("acquisition_channel", "")),
    )


def validate_row(path: Path, line_no: int, row: dict) -> tuple[str, tuple[str, str, str, str, str, str]]:
    missing = [field for field in REQUIRED_FIELDS if not str(row.get(field, "")).strip()]
    if missing:
        fail(f"{path}:{line_no}: field-kit evidence missing durable return identity: {', '.join(missing)}")
    namespace = str(row["field_kit_return_namespace"])
    packet_kind = str(row["field_kit_packet_kind"])
    if packet_kind not in {"first_session", "mature_session"}:
        fail(f"{path}:{line_no}: unsupported field_kit_packet_kind {packet_kind!r}")
    if not namespace.startswith(packet_kind + ":") or not namespace.split(":", 1)[1].strip():
        fail(f"{path}:{line_no}: return namespace is not bound to packet kind")
    if not SHA64.fullmatch(str(row["field_kit_contract_hash"])):
        fail(f"{path}:{line_no}: invalid field-kit contract hash")
    if not SHA64.fullmatch(str(row["field_kit_finalization_receipt_sha256"])):
        fail(f"{path}:{line_no}: invalid finalization receipt hash")
    if not SHA40.fullmatch(str(row["source_head"])):
        fail(f"{path}:{line_no}: invalid source_head")
    return namespace, identity_tuple(row)


def validate_evidence_root(evidence_root: Path) -> tuple[int, int]:
    identities: dict[str, tuple[str, str, str, str, str, str]] = {}
    field_kit_rows = 0
    for gate_id in HUMAN_GATES:
        path = evidence_root / f"{gate_id}.jsonl"
        if not path.exists():
            continue
        rows = load_rows(path)
        for line_no, row in enumerate(rows, start=1):
            if str(row.get("acquisition_channel", "")) != FIELD_KIT_CHANNEL:
                continue
            field_kit_rows += 1
            namespace, identity = validate_row(path, line_no, row)
            prior = identities.get(namespace)
            if prior is not None and prior != identity:
                fail(f"{path}:{line_no}: return namespace collision across durable evidence: {namespace}")
            identities[namespace] = identity
    return field_kit_rows, len(identities)


def main() -> None:
    parser = argparse.ArgumentParser(description="Reject conflicting reuse of finalized human field-kit return namespaces across durable Phase 12G evidence.")
    parser.add_argument("--evidence-root", type=Path, default=DEFAULT_EVIDENCE_ROOT)
    args = parser.parse_args()
    rows, namespaces = validate_evidence_root(args.evidence_root.resolve())
    print(f"Phase 12G human return identity integrity: PASS ({rows} field-kit evidence rows, {namespaces} finalized return namespaces; exact-return multi-row reuse allowed, conflicting reuse rejected)")


if __name__ == "__main__":
    main()
