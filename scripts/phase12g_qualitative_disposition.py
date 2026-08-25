#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "empirical/phase12g_gate_registry.json"
DEFAULT_EVIDENCE_ROOT = ROOT / "empirical/evidence"
ALLOWED_STATUSES = {"PASS", "FAIL", "BLOCKED"}


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def evidence_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def count_rows(path: Path) -> int:
    count = 0
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        parsed = json.loads(raw)
        if not isinstance(parsed, dict):
            raise SystemExit(f"{path}:{line_no}: evidence row must be an object")
        count += 1
    return count


def qualitative_gate(registry: dict, gate_id: str) -> dict:
    for gate in registry["gates"]:
        if gate.get("gate_id") != gate_id:
            continue
        if gate_id == "T8-44" or gate.get("canonical_threshold") is not None:
            raise SystemExit(f"{gate_id}: explicit qualitative disposition is forbidden for threshold-evaluated gates")
        return gate
    raise SystemExit(f"unknown gate: {gate_id}")


def load_disposition_document(path: Path) -> dict:
    if not path.exists():
        return {"schema": "fmd.phase12g.qualitative-dispositions.v2", "dispositions": {}}
    payload = load_json(path)
    if not isinstance(payload, dict) or not isinstance(payload.get("dispositions"), dict):
        raise SystemExit(f"{path}: expected object with dispositions map")
    schema = payload.get("schema")
    if schema not in {None, "fmd.phase12g.qualitative-dispositions.v2"}:
        raise SystemExit(f"{path}: unsupported disposition schema {schema!r}")
    payload["schema"] = "fmd.phase12g.qualitative-dispositions.v2"
    return payload


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Record an explicit qualitative Phase 12G disposition bound to the exact current evidence bytes."
    )
    parser.add_argument("gate_id")
    parser.add_argument("--status", required=True, choices=sorted(ALLOWED_STATUSES))
    parser.add_argument("--rationale", required=True)
    parser.add_argument("--evidence-ref", action="append", required=True, dest="evidence_refs")
    parser.add_argument("--reviewer-id", required=True, help="Pseudonymous reviewer/operator identifier; never inferred by automation.")
    parser.add_argument("--evidence-root", type=Path, default=DEFAULT_EVIDENCE_ROOT)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--replace", action="store_true", help="Deliberately replace an existing disposition after re-reviewing current evidence.")
    args = parser.parse_args()

    registry = load_json(REGISTRY)
    qualitative_gate(registry, args.gate_id)

    rationale = args.rationale.strip()
    reviewer_id = args.reviewer_id.strip()
    refs = [item.strip() for item in args.evidence_refs if item.strip()]
    if not rationale:
        raise SystemExit("rationale must be non-empty")
    if not reviewer_id:
        raise SystemExit("reviewer-id must be non-empty")
    if not refs:
        raise SystemExit("at least one non-empty evidence-ref is required")

    evidence_path = args.evidence_root / f"{args.gate_id}.jsonl"
    if not evidence_path.exists():
        raise SystemExit(f"{args.gate_id}: no evidence file exists at {evidence_path}")
    row_count = count_rows(evidence_path)
    if row_count <= 0:
        raise SystemExit(f"{args.gate_id}: cannot disposition empty evidence")

    output = args.output or (args.evidence_root / "dispositions.json")
    document = load_disposition_document(output)
    dispositions = document["dispositions"]
    if args.gate_id in dispositions and not args.replace:
        raise SystemExit(
            f"{args.gate_id}: disposition already exists; re-review current evidence and pass --replace for a deliberate replacement"
        )

    record = {
        "status": args.status,
        "rationale": rationale,
        "evidence_refs": refs,
        "reviewer_id": reviewer_id,
        "evidence_file": f"{args.gate_id}.jsonl",
        "evidence_sha256": evidence_sha256(evidence_path),
        "row_count": row_count,
        "recorded_at_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "interpretation_mode": "explicit_human_or_operator_review",
    }
    dispositions[args.gate_id] = record
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"gate_id": args.gate_id, "output": str(output), "record": record}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
