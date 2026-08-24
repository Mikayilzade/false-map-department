#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROTOCOLS = ROOT / "empirical" / "phase12g_session_protocols.json"
READINESS_SCRIPT = ROOT / "scripts" / "phase12g_runtime_readiness.py"
RUNNER = "res://tests/test_phase12g_e7_interaction_probe_runner.gd"


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def safe_name(value: str) -> str:
    return "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in value)


def main() -> None:
    parser = argparse.ArgumentParser(description="Execute presentation-level E7 controller interaction checks. Results are evidence inputs, never gate PASS by themselves.")
    parser.add_argument("--output-dir", default=str(ROOT / ".phase12g-e7-interactions"))
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--dossier-id", action="append", default=[])
    parser.add_argument("--scenario-id", action="append", default=[])
    parser.add_argument("--max-checks", type=int, default=0)
    parser.add_argument("--timeout-seconds", type=int, default=20)
    args = parser.parse_args()

    out_dir = Path(args.output_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    readiness_path = out_dir / "runtime-readiness.json"
    subprocess.run([sys.executable, str(READINESS_SCRIPT), "--output", str(readiness_path)], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    readiness = load(readiness_path)
    ready_set = set(readiness["ready_ids"])
    all_ids = [row["dossier_id"] for row in readiness["rows"]]
    selected_ids = args.dossier_id or all_ids

    protocols = load(PROTOCOLS)
    scenarios = {row["scenario_id"]: row for row in protocols["protocols"]["E7"]["capture_scenarios"]}
    selected_scenarios = args.scenario_id or list(scenarios)
    unknown_scenarios = [item for item in selected_scenarios if item not in scenarios]
    unknown_ids = [item for item in selected_ids if item not in all_ids]
    if unknown_scenarios:
        raise SystemExit(f"Unknown E7 scenario(s): {unknown_scenarios}")
    if unknown_ids:
        raise SystemExit(f"Unknown dossier ID(s): {unknown_ids}")

    rows: list[dict] = []
    executed = 0
    for dossier_id in selected_ids:
        for scenario_id in selected_scenarios:
            scenario = scenarios[scenario_id]
            row = {
                "dossier_id": dossier_id,
                "scenario_id": scenario_id,
                "device_mode": scenario["device_mode"],
                "ui_scale": scenario["ui_scale"],
                "reduced_motion": scenario["reduced_motion"],
                "non_color": scenario["non_color"],
                "no_audio": scenario["no_audio"],
                "interaction_complete": False,
                "status": "PLANNED",
                "result_path": None,
                "process_returncode": None,
            }
            if dossier_id not in ready_set:
                row["status"] = "BLOCKED_RUNTIME_BINDING"
                rows.append(row)
                continue
            if args.max_checks > 0 and executed >= args.max_checks:
                row["status"] = "NOT_EXECUTED_LIMIT"
                rows.append(row)
                continue

            result_dir = out_dir / safe_name(scenario_id)
            result_dir.mkdir(parents=True, exist_ok=True)
            result_path = result_dir / f"{safe_name(dossier_id)}.interaction.json"
            env = os.environ.copy()
            env.update({
                "FMD_PLAYTEST_DOSSIER_ID": dossier_id,
                "FMD_EMPIRICAL_BROAD": "1",
                "FMD_E7_SCENARIO_ID": scenario_id,
                "FMD_E7_UI_SCALE_PERCENT": str(scenario["ui_scale"]),
                "FMD_E7_REDUCED_MOTION": "1" if scenario["reduced_motion"] else "0",
                "FMD_E7_NON_COLOR": "1" if scenario["non_color"] else "0",
                "FMD_E7_NO_AUDIO": "1" if scenario["no_audio"] else "0",
                "FMD_E7_INTERACTION_RESULT_PATH": str(result_path),
            })
            command = [args.godot, "--headless", "--path", str(ROOT), "--script", RUNNER]
            try:
                completed = subprocess.run(
                    command,
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=args.timeout_seconds,
                    check=False,
                )
                row["process_returncode"] = completed.returncode
                log_base = result_dir / f"{safe_name(dossier_id)}.interaction"
                log_base.with_suffix(".stdout.log").write_text(completed.stdout, encoding="utf-8")
                log_base.with_suffix(".stderr.log").write_text(completed.stderr, encoding="utf-8")
                row["result_path"] = str(result_path) if result_path.is_file() else None
                if result_path.is_file():
                    payload = load(result_path)
                    row["interaction_complete"] = bool(payload.get("interaction_complete", False))
                    row["checks"] = payload.get("checks", {})
                    row["notes"] = payload.get("notes", [])
                row["status"] = "INTERACTION_PASS" if completed.returncode == 0 and row["interaction_complete"] else "INTERACTION_FAIL"
            except subprocess.TimeoutExpired as exc:
                row["status"] = "INTERACTION_TIMEOUT"
                (result_dir / f"{safe_name(dossier_id)}.interaction.timeout.log").write_text(str(exc), encoding="utf-8")
            executed += 1
            rows.append(row)

    manifest = {
        "schema_version": 1,
        "gate_id": "E7",
        "evidence_kind": "E7_PRESENTATION_INTERACTION_MANIFEST_NOT_CAPTURE_REVIEW",
        "counts": {
            "rows": len(rows),
            "interaction_pass": sum(row["status"] == "INTERACTION_PASS" for row in rows),
            "blocked_runtime_binding": sum(row["status"] == "BLOCKED_RUNTIME_BINDING" for row in rows),
            "failed_or_timeout": sum(row["status"] in {"INTERACTION_FAIL", "INTERACTION_TIMEOUT"} for row in rows),
        },
        "rows": rows,
    }
    manifest_path = out_dir / "interaction-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(manifest_path)
    print(json.dumps(manifest["counts"], sort_keys=True))
    if any(row["status"] in {"INTERACTION_FAIL", "INTERACTION_TIMEOUT"} for row in rows):
        raise SystemExit(2)


if __name__ == "__main__":
    main()
