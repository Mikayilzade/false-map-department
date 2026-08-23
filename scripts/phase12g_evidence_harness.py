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


def validate_required_fields(gate: dict, rows: list[dict]) -> list[str]:
    failures: list[str] = []
    required = list(gate.get("required_fields", []))
    for index, row in enumerate(rows, start=1):
        missing = [field for field in required if field not in row]
        if missing:
            failures.append(f"row {index} missing fields: {', '.join(missing)}")
    return failures


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate and summarize Phase 12G empirical evidence without fabricating missing observations.")
    parser.add_argument("--evidence-root", type=Path, default=DEFAULT_EVIDENCE_ROOT)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    registry = load_json(REGISTRY)
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
        else:
            status, detail = evaluate_numeric_threshold(rows, gate.get("canonical_threshold"))
        if gate.get("evidence_class") in {"human_playtest", "human_comparative_playtest", "human_timing", "market_test", "release_market_recheck", "reference_hardware_profile", "mixed_capture_interaction"} and not rows:
            status = "PENDING"
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
