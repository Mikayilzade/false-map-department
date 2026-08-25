#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROTOCOLS = ROOT / "empirical" / "phase12g_session_protocols.json"
EVIDENCE = ROOT / "empirical" / "evidence" / "E7.jsonl"


def fail(message: str) -> None:
    raise SystemExit(f"E7 REVIEW APPEND FAIL: {message}")


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot load {path.relative_to(ROOT)}: {exc}")
    if not isinstance(value, dict):
        fail(f"{path.relative_to(ROOT)} must contain an object")
    return value


def shippable_ids() -> list[str]:
    return [f"D{i:02d}" for i in range(1, 41)] + [f"DEMO{i:02d}" for i in range(1, 6)] + [f"REMIX{i:02d}" for i in range(1, 13)]


def scenario_table() -> dict[str, dict]:
    protocols = load_json(PROTOCOLS)
    rows = protocols.get("protocols", {}).get("E7", {}).get("capture_scenarios", [])
    result: dict[str, dict] = {}
    for row in rows:
        if isinstance(row, dict) and row.get("scenario_id"):
            result[str(row["scenario_id"])] = row
    return result


def source_run_id(review: dict) -> int:
    if isinstance(review.get("source"), dict) and review["source"].get("workflow_run_id") is not None:
        return int(review["source"]["workflow_run_id"])
    if review.get("source_run_id") is not None:
        return int(review["source_run_id"])
    fail("review is missing source workflow run id")


def source_artifact(review: dict) -> tuple[int, str]:
    source = review.get("source", {}) if isinstance(review.get("source"), dict) else {}
    artifact_id = source.get("artifact_id", review.get("source_artifact_id"))
    digest = source.get("artifact_sha256", review.get("source_artifact_digest"))
    if artifact_id is None or not digest:
        fail("review is missing exact artifact id/digest")
    digest_text = str(digest)
    if digest_text.startswith("sha256:"):
        digest_text = digest_text.removeprefix("sha256:")
    if len(digest_text) != 64:
        fail("review artifact digest must be SHA-256")
    return int(artifact_id), digest_text


def reviewed_ids(review: dict) -> list[str]:
    if isinstance(review.get("rows"), list):
        ids: list[str] = []
        for row in review["rows"]:
            if not isinstance(row, dict) or not row.get("capture_review_pass", False):
                fail("every explicit review row must be capture_review_pass=true")
            ids.append(str(row.get("dossier_id", "")))
        return ids
    if isinstance(review.get("reviewed_dossier_ids"), list):
        ids = [str(item) for item in review["reviewed_dossier_ids"]]
        if int(review.get("capture_review_pass_count", -1)) != len(ids) or int(review.get("capture_review_fail_count", -1)) != 0:
            fail("aggregate review counts do not prove every reviewed dossier passed")
        return ids
    fail("review has no per-dossier reviewed IDs")


def interaction_proven(review: dict, expected_count: int) -> None:
    interaction = review.get("interaction_acquisition")
    if not isinstance(interaction, dict):
        fail("review lacks exact interaction acquisition evidence")
    status = str(interaction.get("source_manifest_status", interaction.get("status", "")))
    rows = int(interaction.get("rows", interaction.get("counts", {}).get("rows", -1)))
    passed = int(interaction.get("interaction_pass", interaction.get("counts", {}).get("interaction_pass", -1)))
    failed = int(interaction.get("failed_or_timeout", interaction.get("counts", {}).get("failed_or_timeout", -1)))
    blocked = int(interaction.get("blocked_runtime_binding", interaction.get("counts", {}).get("blocked_runtime_binding", -1)))
    if status != "INTERACTION_ACQUISITION_PASS" or rows != expected_count or passed != expected_count or failed != 0 or blocked != 0:
        fail(f"interaction acquisition is incomplete: status={status} rows={rows} pass={passed} failed={failed} blocked={blocked}")


def scenario_signature(review: dict, scenario: dict) -> None:
    sig = review.get("scenario_signature") if isinstance(review.get("scenario_signature"), dict) else review
    expected = {
        "device_mode": str(scenario["device_mode"]),
        "ui_scale": int(scenario["ui_scale"]),
        "reduced_motion": bool(scenario["reduced_motion"]),
        "non_color": bool(scenario["non_color"]),
        "no_audio": bool(scenario["no_audio"]),
    }
    actual = {
        "device_mode": str(sig.get("device_mode", "")),
        "ui_scale": int(sig.get("ui_scale_percent", sig.get("ui_scale", -1))),
        "reduced_motion": bool(sig.get("reduced_motion", False)),
        "non_color": bool(sig.get("non_color", False)),
        "no_audio": bool(sig.get("no_audio", False)),
    }
    if actual != expected:
        fail(f"review scenario signature mismatch: expected={expected} actual={actual}")


def existing_keys() -> tuple[str, set[tuple[str, str]]]:
    if not EVIDENCE.exists():
        return "", set()
    text = EVIDENCE.read_text(encoding="utf-8")
    keys: set[tuple[str, str]] = set()
    for line_number, raw in enumerate(text.splitlines(), start=1):
        if not raw.strip():
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError as exc:
            fail(f"existing E7 row {line_number} malformed: {exc}")
        key = (str(row.get("dossier_id", "")), str(row.get("scenario_id", "")))
        if key in keys:
            fail(f"existing E7 duplicate row: {key}")
        keys.add(key)
    return text, keys


def normalized_rows(review_path: Path) -> list[dict]:
    review = load_json(review_path)
    if str(review.get("gate_id", "")) != "E7":
        fail(f"{review_path.relative_to(ROOT)} is not E7 evidence")
    scenario_id = str(review.get("scenario_id", ""))
    scenarios = scenario_table()
    if scenario_id not in scenarios:
        fail(f"unknown E7 scenario in review: {scenario_id}")
    scenario = scenarios[scenario_id]
    scenario_signature(review, scenario)
    ids = reviewed_ids(review)
    expected_ids = shippable_ids()
    if ids != expected_ids:
        fail(f"reviewed IDs must exactly match the ordered 57-case shippable set; got {len(ids)}")
    interaction_proven(review, len(expected_ids))
    run_id = source_run_id(review)
    source_artifact(review)
    review_ref = str(review_path.relative_to(ROOT)).replace("\\", "/")
    rows: list[dict] = []
    for dossier_id in expected_ids:
        rows.append({
            "gate_id": "E7",
            "dossier_id": dossier_id,
            "device_mode": str(scenario["device_mode"]),
            "ui_scale": int(scenario["ui_scale"]),
            "reduced_motion": bool(scenario["reduced_motion"]),
            "non_color": bool(scenario["non_color"]),
            "no_audio": bool(scenario["no_audio"]),
            "interaction_complete": True,
            "capture_review_pass": True,
            "scenario_id": scenario_id,
            "source_run_id": run_id,
            "review_ref": review_ref,
        })
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description="Append raw E7 rows only from complete reviewed capture+interaction evidence. Existing rows remain byte-for-byte unchanged.")
    parser.add_argument("--review", action="append", required=True, help="Repository-relative reviewed E7 JSON file; may be passed more than once.")
    args = parser.parse_args()

    original, keys = existing_keys()
    append: list[str] = []
    appended_scenarios: list[str] = []
    for raw_path in args.review:
        path = (ROOT / raw_path).resolve()
        if ROOT not in path.parents:
            fail("review path escapes repository")
        rows = normalized_rows(path)
        scenario_id = str(rows[0]["scenario_id"])
        scenario_new_count = 0
        for row in rows:
            key = (str(row["dossier_id"]), scenario_id)
            if key in keys:
                continue
            append.append(json.dumps(row, separators=(",", ":")))
            keys.add(key)
            scenario_new_count += 1
        if scenario_new_count not in (0, 57):
            fail(f"partial scenario already present for {scenario_id}: would append {scenario_new_count}/57")
        if scenario_new_count == 57:
            appended_scenarios.append(scenario_id)

    if append:
        prefix = original
        if prefix and not prefix.endswith("\n"):
            prefix += "\n"
        EVIDENCE.write_text(prefix + "\n".join(append) + "\n", encoding="utf-8")
    print(json.dumps({"appended_rows": len(append), "appended_scenarios": appended_scenarios, "total_unique_rows": len(keys)}, sort_keys=True))


if __name__ == "__main__":
    main()
