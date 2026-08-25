#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "empirical/phase12g_gate_registry.json"
DEFAULT_EVIDENCE_ROOT = ROOT / "empirical/evidence"
QUALITATIVE_SCHEMA = "fmd.phase12g.qualitative-dispositions.v2"


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def evidence_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def count_rows(path: Path) -> int:
    rows = 0
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        parsed = json.loads(raw)
        if not isinstance(parsed, dict):
            raise SystemExit(f"{path}:{line_no}: evidence row must be an object")
        rows += 1
    return rows


def validate(evidence_root: Path, dispositions_path: Path) -> dict:
    registry = load_json(REGISTRY)
    gates = {gate["gate_id"]: gate for gate in registry["gates"]}
    if not dispositions_path.exists():
        return {"ok": True, "validated_dispositions": 0, "reason": "no qualitative dispositions recorded"}

    payload = load_json(dispositions_path)
    if not isinstance(payload, dict) or payload.get("schema") != QUALITATIVE_SCHEMA:
        raise SystemExit(f"{dispositions_path}: expected schema {QUALITATIVE_SCHEMA}")
    dispositions = payload.get("dispositions")
    if not isinstance(dispositions, dict):
        raise SystemExit(f"{dispositions_path}: dispositions must be an object")

    validated = 0
    for gate_id, raw in sorted(dispositions.items()):
        gate = gates.get(gate_id)
        if gate is None:
            raise SystemExit(f"{dispositions_path}: unknown gate {gate_id}")
        if gate_id == "T8-44" or gate.get("canonical_threshold") is not None:
            raise SystemExit(f"{dispositions_path}: explicit qualitative disposition forbidden for threshold gate {gate_id}")
        if not isinstance(raw, dict):
            raise SystemExit(f"{dispositions_path}: {gate_id} disposition must be an object")
        for field in (
            "status",
            "rationale",
            "evidence_refs",
            "reviewer_id",
            "evidence_file",
            "evidence_sha256",
            "row_count",
            "recorded_at_utc",
            "interpretation_mode",
        ):
            if field not in raw:
                raise SystemExit(f"{dispositions_path}: {gate_id} missing {field}")
        if raw["status"] not in {"PASS", "FAIL", "BLOCKED"}:
            raise SystemExit(f"{dispositions_path}: {gate_id} invalid status")
        if not isinstance(raw["rationale"], str) or not raw["rationale"].strip():
            raise SystemExit(f"{dispositions_path}: {gate_id} rationale must be non-empty")
        refs = raw["evidence_refs"]
        if not isinstance(refs, list) or not refs or any(not isinstance(ref, str) or not ref.strip() for ref in refs):
            raise SystemExit(f"{dispositions_path}: {gate_id} evidence_refs must be non-empty strings")
        if not isinstance(raw["reviewer_id"], str) or not raw["reviewer_id"].strip():
            raise SystemExit(f"{dispositions_path}: {gate_id} reviewer_id must be non-empty")
        if raw["interpretation_mode"] != "explicit_human_or_operator_review":
            raise SystemExit(f"{dispositions_path}: {gate_id} interpretation_mode must remain explicit review")
        expected_file = f"{gate_id}.jsonl"
        if raw["evidence_file"] != expected_file:
            raise SystemExit(f"{dispositions_path}: {gate_id} evidence_file must be {expected_file}")
        evidence_path = evidence_root / expected_file
        if not evidence_path.exists():
            raise SystemExit(f"{dispositions_path}: {gate_id} disposition points to missing evidence file")
        current_rows = count_rows(evidence_path)
        current_sha = evidence_sha256(evidence_path)
        if isinstance(raw["row_count"], bool) or not isinstance(raw["row_count"], int) or raw["row_count"] <= 0:
            raise SystemExit(f"{dispositions_path}: {gate_id} row_count must be positive")
        if raw["row_count"] != current_rows or raw["evidence_sha256"] != current_sha:
            raise SystemExit(
                f"{dispositions_path}: {gate_id} disposition is stale; current evidence bytes/row count differ and require deliberate re-review"
            )
        validated += 1

    return {"ok": True, "validated_dispositions": validated, "schema": QUALITATIVE_SCHEMA}


def main() -> None:
    parser = argparse.ArgumentParser(description="Reject stale or unbound qualitative Phase 12G dispositions.")
    parser.add_argument("--evidence-root", type=Path, default=DEFAULT_EVIDENCE_ROOT)
    parser.add_argument("--dispositions", type=Path)
    args = parser.parse_args()
    dispositions = args.dispositions or (args.evidence_root / "dispositions.json")
    result = validate(args.evidence_root, dispositions)
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
