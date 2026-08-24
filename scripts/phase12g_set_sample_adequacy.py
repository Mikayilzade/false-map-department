#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EVIDENCE_ROOT = ROOT / "empirical" / "evidence"
ALLOWED_GATES = {"E1", "E2"}


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def count_rows(path: Path) -> int:
    return sum(1 for line in path.read_text(encoding="utf-8").splitlines() if line.strip())


def load_existing(path: Path) -> dict:
    if not path.exists():
        return {"schema_version": 1, "gates": {}}
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or not isinstance(payload.get("gates", {}), dict):
        raise SystemExit(f"{path}: malformed sample adequacy file")
    return payload


def main() -> None:
    parser = argparse.ArgumentParser(description="Record evidence-backed representativeness adequacy for E1/E2 without changing their frozen percentage thresholds.")
    parser.add_argument("--gate", required=True, choices=sorted(ALLOWED_GATES))
    parser.add_argument("--confirmed", required=True, choices=["true", "false"])
    parser.add_argument("--rationale", required=True)
    parser.add_argument("--evidence-ref", action="append", required=True)
    parser.add_argument("--evidence-root", type=Path, default=DEFAULT_EVIDENCE_ROOT)
    args = parser.parse_args()

    rationale = args.rationale.strip()
    refs = [ref.strip() for ref in args.evidence_ref if ref.strip()]
    if not rationale:
        raise SystemExit("sample adequacy rationale must be non-empty")
    if not refs:
        raise SystemExit("at least one evidence reference is required")

    evidence_root = args.evidence_root.resolve()
    evidence_root.mkdir(parents=True, exist_ok=True)
    evidence_path = evidence_root / f"{args.gate}.jsonl"
    if not evidence_path.exists() or count_rows(evidence_path) == 0:
        raise SystemExit(f"{args.gate}: sample adequacy cannot be recorded before real evidence rows exist")

    row_count = count_rows(evidence_path)
    evidence_sha = sha256_file(evidence_path)
    confirmed = args.confirmed == "true"
    now = datetime.now(timezone.utc).isoformat()
    record = {
        "confirmed": confirmed,
        "rationale": rationale,
        "evidence_refs": refs,
        "evidence_sha256": evidence_sha,
        "row_count": row_count,
        "recorded_at_utc": now,
    }

    adequacy_path = evidence_root / "sample_adequacy.json"
    payload = load_existing(adequacy_path)
    payload.setdefault("schema_version", 1)
    payload.setdefault("gates", {})
    payload["gates"][args.gate] = record
    adequacy_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    history_path = evidence_root / "sample_adequacy_history.jsonl"
    history_row = {"gate_id": args.gate, **record}
    with history_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(history_row, sort_keys=True) + "\n")

    print(json.dumps({"gate_id": args.gate, **record}, indent=2, sort_keys=True))
    print("Sample adequacy records whether the frozen threshold may be evaluated; it never overrides the 80%/70% result.")


if __name__ == "__main__":
    main()
