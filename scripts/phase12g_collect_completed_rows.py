#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "empirical/phase12g_gate_registry.json"
DEFAULT_EVIDENCE_ROOT = ROOT / "empirical/evidence"


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

    target = args.evidence_root / f"{gate_id}.jsonl"
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
    }
    print(json.dumps(result, indent=2, sort_keys=True))

    if not args.append or not novel:
        return
    args.evidence_root.mkdir(parents=True, exist_ok=True)
    with target.open("a", encoding="utf-8") as handle:
        for row in novel:
            handle.write(json.dumps(row, sort_keys=True, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
