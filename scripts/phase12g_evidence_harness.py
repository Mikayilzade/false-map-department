#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from statistics import mean

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "empirical/phase12g_gate_registry.json"
DEFAULT_EVIDENCE_ROOT = ROOT / "empirical/evidence"


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def evaluate_numeric_threshold(rows: list[dict], threshold: dict | None) -> tuple[str, dict]:
    if threshold is None:
        return "PENDING", {"reason": "canonical gate is qualitative or requires explicit disposition"}
    metric = threshold.get("metric")
    if metric in {"comprehension_rate", "prediction_success_rate", "shippable_dossiers_pass_rate"}:
        if not rows:
            return "PENDING", {"reason": "no evidence rows"}
        if metric == "comprehension_rate":
            eligible = [r for r in rows if bool(r.get("naive", False))]
            values = [1.0 if bool(r.get("success", False)) and float(r.get("understood_within_seconds", 10**9)) <= 180 else 0.0 for r in eligible]
        elif metric == "prediction_success_rate":
            eligible = [r for r in rows if bool(r.get("packet_completed", False))]
            values = [1.0 if bool(r.get("success", False)) else 0.0 for r in eligible]
        else:
            eligible = rows
            values = [1.0 if bool(r.get("interaction_complete", False)) and bool(r.get("capture_review_pass", False)) else 0.0 for r in eligible]
        if not values:
            return "PENDING", {"reason": "no eligible evidence rows"}
        value = mean(values)
        target = float(threshold["value"])
        op = threshold["operator"]
        passed = value >= target if op == ">=" else value == target
        return ("PASS" if passed else "FAIL"), {"metric": metric, "value": value, "target": target, "eligible_rows": len(values)}
    return "PENDING", {"reason": "threshold requires specialized evaluator"}


def evaluate_t844(rows: list[dict], threshold: dict) -> tuple[str, dict]:
    if not rows:
        return "PENDING", {"reason": "no Deck-class reference hardware evidence"}
    row = rows[-1]
    required = ["typical_edit_median_ms", "typical_edit_p95_ms", "late_game_edit_p99_ms", "stability_cycle_p95_ms"]
    values = {key: float(row[key]) for key in required}
    passed = (
        values["typical_edit_median_ms"] <= float(threshold["typical_edit_median_ms"])
        and values["typical_edit_p95_ms"] <= float(threshold["typical_edit_p95_ms"])
        and values["late_game_edit_p99_ms"] <= float(threshold["late_game_edit_p99_ms"])
        and values["stability_cycle_p95_ms"] <= float(threshold["stability_cycle_p95_ms"])
    )
    return ("PASS" if passed else "FAIL"), {"latest": values, "target": threshold, "sample_count": row.get("sample_count")}


def load_rows(evidence_root: Path, gate_id: str) -> list[dict]:
    path = evidence_root / f"{gate_id}.jsonl"
    if not path.exists():
        return []
    rows: list[dict] = []
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        parsed = json.loads(raw)
        if not isinstance(parsed, dict):
            raise SystemExit(f"{path}:{line_no}: evidence row must be an object")
        rows.append(parsed)
    return rows


def _missing_value(value) -> bool:
    if value is None:
        return True
    if isinstance(value, str) and not value.strip():
        return True
    if isinstance(value, (list, dict)) and not value:
        return True
    return False


def validate_required_fields(gate: dict, rows: list[dict]) -> list[str]:
    failures: list[str] = []
    required = list(gate.get("required_fields", []))
    gate_id = gate.get("gate_id", "")
    for index, row in enumerate(rows, start=1):
        if row.get("gate_id", gate_id) != gate_id:
            failures.append(f"row {index} gate_id mismatch")
        missing = [field for field in required if field not in row or _missing_value(row.get(field))]
        if missing:
            failures.append(f"row {index} missing/blank fields: {', '.join(missing)}")
    return failures


def load_dispositions(path: Path, registry: dict) -> dict[str, dict]:
    if not path.exists():
        return {}
    payload = load_json(path)
    if not isinstance(payload, dict) or not isinstance(payload.get("dispositions", {}), dict):
        raise SystemExit(f"{path}: expected object with dispositions map")
    by_gate = {gate["gate_id"]: gate for gate in registry["gates"]}
    result: dict[str, dict] = {}
    for gate_id, raw in payload.get("dispositions", {}).items():
        if gate_id not in by_gate:
            raise SystemExit(f"{path}: unknown disposition gate {gate_id}")
        gate = by_gate[gate_id]
        if gate_id == "T8-44" or gate.get("canonical_threshold") is not None:
            raise SystemExit(f"{path}: manual disposition forbidden for threshold gate {gate_id}")
        if not isinstance(raw, dict):
            raise SystemExit(f"{path}: disposition {gate_id} must be an object")
        status = raw.get("status")
        rationale = raw.get("rationale")
        refs = raw.get("evidence_refs")
        if status not in {"PASS", "FAIL", "BLOCKED"}:
            raise SystemExit(f"{path}: disposition {gate_id} has invalid status")
        if not isinstance(rationale, str) or not rationale.strip():
            raise SystemExit(f"{path}: disposition {gate_id} requires rationale")
        if not isinstance(refs, list) or not refs or any(not isinstance(ref, str) or not ref.strip() for ref in refs):
            raise SystemExit(f"{path}: disposition {gate_id} requires non-empty evidence_refs")
        result[gate_id] = {"status": status, "rationale": rationale.strip(), "evidence_refs": refs}
    return result


def evaluate_qualitative(gate_id: str, rows: list[dict], dispositions: dict[str, dict]) -> tuple[str, dict]:
    if not rows:
        return "PENDING", {"reason": "no evidence rows"}
    disposition = dispositions.get(gate_id)
    if disposition is None:
        return "PENDING", {"reason": "evidence rows exist but explicit evidence-backed disposition is missing"}
    return disposition["status"], {
        "rationale": disposition["rationale"],
        "evidence_refs": disposition["evidence_refs"],
        "evidence_rows": len(rows),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate and summarize Phase 12G empirical evidence without fabricating missing observations.")
    parser.add_argument("--evidence-root", type=Path, default=DEFAULT_EVIDENCE_ROOT)
    parser.add_argument("--dispositions", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    registry = load_json(REGISTRY)
    disposition_path = args.dispositions or (args.evidence_root / "dispositions.json")
    dispositions = load_dispositions(disposition_path, registry)
    results: list[dict] = []
    for gate in registry["gates"]:
        gate_id = gate["gate_id"]
        rows = load_rows(args.evidence_root, gate_id)
        field_failures = validate_required_fields(gate, rows)
        if field_failures:
            status = "BLOCKED"
            detail = {"schema_failures": field_failures}
        elif gate_id == "T8-44":
            status, detail = evaluate_t844(rows, gate["canonical_threshold"])
        elif gate.get("canonical_threshold") is None:
            status, detail = evaluate_qualitative(gate_id, rows, dispositions)
        else:
            status, detail = evaluate_numeric_threshold(rows, gate.get("canonical_threshold"))
        results.append({
            "gate_id": gate_id,
            "name": gate["name"],
            "evidence_class": gate["evidence_class"],
            "status": status,
            "rows": len(rows),
            "detail": detail,
            "automated_preconditions": gate.get("automated_preconditions", []),
        })

    summary = {
        "phase": "12G",
        "registry_version": registry["registry_version"],
        "counts": {status: sum(1 for r in results if r["status"] == status) for status in ["PASS", "FAIL", "PENDING", "BLOCKED"]},
        "gates": results,
    }
    text = json.dumps(summary, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    print(text, end="")


if __name__ == "__main__":
    main()
