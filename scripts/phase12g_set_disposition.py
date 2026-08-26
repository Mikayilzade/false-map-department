#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "empirical/phase12g_gate_registry.json"
DEFAULT_EVIDENCE_ROOT = ROOT / "empirical/evidence"
QUALITATIVE_SCHEMA = "fmd.phase12g.qualitative-dispositions.v2"


def nonempty_rows(path: Path) -> int:
    if not path.exists():
        return 0
    return sum(1 for line in path.read_text(encoding="utf-8").splitlines() if line.strip())


def evidence_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_current(path: Path) -> dict:
    if not path.exists():
        return {"schema": QUALITATIVE_SCHEMA, "dispositions": {}}
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or not isinstance(payload.get("dispositions"), dict):
        raise SystemExit("existing dispositions.json is malformed")
    schema = payload.get("schema")
    if schema == QUALITATIVE_SCHEMA:
        return payload
    # The old schema stored only row count and could survive evidence replacement.
    # Never silently promote an existing reviewed decision into the exact-byte schema.
    if payload.get("dispositions"):
        raise SystemExit(
            "existing dispositions.json uses legacy unbound schema; re-review current evidence with the v2 recorder instead of migrating the old decision"
        )
    return {"schema": QUALITATIVE_SCHEMA, "dispositions": {}}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Record an explicit evidence-backed disposition for a qualitative Phase 12G gate, bound to exact evidence bytes."
    )
    parser.add_argument("--gate", required=True)
    parser.add_argument("--status", choices=["PASS", "FAIL", "BLOCKED"], required=True)
    parser.add_argument("--rationale", required=True)
    parser.add_argument("--evidence-ref", action="append", dest="evidence_refs", required=True)
    parser.add_argument("--reviewer-id", required=True, help="Pseudonymous explicit reviewer/operator identifier; never inferred by automation.")
    parser.add_argument("--evidence-root", type=Path, default=DEFAULT_EVIDENCE_ROOT)
    parser.add_argument("--replace", action="store_true", help="Deliberately replace an existing disposition after re-reviewing current evidence.")
    args = parser.parse_args()

    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    by_gate = {gate["gate_id"]: gate for gate in registry["gates"]}
    if args.gate not in by_gate:
        raise SystemExit(f"unknown gate: {args.gate}")
    gate = by_gate[args.gate]
    if args.gate == "T8-44" or gate.get("canonical_threshold") is not None:
        raise SystemExit(f"manual disposition is forbidden for threshold gate {args.gate}")
    if not args.rationale.strip():
        raise SystemExit("rationale must be non-empty")
    reviewer_id = args.reviewer_id.strip()
    if not reviewer_id:
        raise SystemExit("reviewer-id must be non-empty")
    refs = [ref.strip() for ref in args.evidence_refs if ref.strip()]
    if not refs:
        raise SystemExit("at least one evidence-ref is required")

    evidence_path = args.evidence_root / f"{args.gate}.jsonl"
    row_count = nonempty_rows(evidence_path)
    if row_count == 0:
        raise SystemExit(f"cannot disposition {args.gate}: no evidence rows exist")

    args.evidence_root.mkdir(parents=True, exist_ok=True)
    current_path = args.evidence_root / "dispositions.json"
    payload = load_current(current_path)
    dispositions = payload["dispositions"]
    if args.gate in dispositions and not args.replace:
        raise SystemExit(
            f"{args.gate}: disposition already exists; re-review current evidence and pass --replace for a deliberate replacement"
        )

    decided_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    decision = {
        "status": args.status,
        "rationale": args.rationale.strip(),
        "evidence_refs": refs,
        "reviewer_id": reviewer_id,
        "evidence_file": evidence_path.name,
        "evidence_sha256": evidence_sha256(evidence_path),
        "row_count": row_count,
        "recorded_at_utc": decided_at,
        "interpretation_mode": "explicit_human_or_operator_review",
    }
    payload["schema"] = QUALITATIVE_SCHEMA
    dispositions[args.gate] = decision
    current_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    # Preserve the legacy append-only audit trail while making every new row exact-byte bound.
    history_path = args.evidence_root / "disposition_history.jsonl"
    history_row = {"gate_id": args.gate, **decision}
    with history_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(history_row, sort_keys=True) + "\n")

    print(json.dumps({
        "gate_id": args.gate,
        "status": args.status,
        "evidence_rows": row_count,
        "evidence_sha256": decision["evidence_sha256"],
        "dispositions": str(current_path),
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
