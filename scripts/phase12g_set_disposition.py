#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "empirical/phase12g_gate_registry.json"
DEFAULT_EVIDENCE_ROOT = ROOT / "empirical/evidence"


def nonempty_rows(path: Path) -> int:
    if not path.exists():
        return 0
    return sum(1 for line in path.read_text(encoding="utf-8").splitlines() if line.strip())


def main() -> None:
    parser = argparse.ArgumentParser(description="Record an explicit evidence-backed disposition for a qualitative Phase 12G gate.")
    parser.add_argument("--gate", required=True)
    parser.add_argument("--status", choices=["PASS", "FAIL", "BLOCKED"], required=True)
    parser.add_argument("--rationale", required=True)
    parser.add_argument("--evidence-ref", action="append", dest="evidence_refs", required=True)
    parser.add_argument("--evidence-root", type=Path, default=DEFAULT_EVIDENCE_ROOT)
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
    refs = [ref.strip() for ref in args.evidence_refs if ref.strip()]
    if not refs:
        raise SystemExit("at least one evidence-ref is required")

    evidence_path = args.evidence_root / f"{args.gate}.jsonl"
    row_count = nonempty_rows(evidence_path)
    if row_count == 0:
        raise SystemExit(f"cannot disposition {args.gate}: no evidence rows exist")

    args.evidence_root.mkdir(parents=True, exist_ok=True)
    current_path = args.evidence_root / "dispositions.json"
    if current_path.exists():
        payload = json.loads(current_path.read_text(encoding="utf-8"))
    else:
        payload = {"schema_version": 1, "dispositions": {}}
    if not isinstance(payload.get("dispositions"), dict):
        raise SystemExit("existing dispositions.json is malformed")

    decided_at = datetime.now(timezone.utc).isoformat()
    decision = {
        "status": args.status,
        "rationale": args.rationale.strip(),
        "evidence_refs": refs,
        "evidence_rows_at_decision": row_count,
        "decided_at_utc": decided_at,
    }
    payload["schema_version"] = 1
    payload["dispositions"][args.gate] = decision
    current_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    history_path = args.evidence_root / "disposition_history.jsonl"
    history_row = {"gate_id": args.gate, **decision}
    with history_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(history_row, sort_keys=True) + "\n")

    print(json.dumps({"gate_id": args.gate, "status": args.status, "evidence_rows": row_count, "dispositions": str(current_path)}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
