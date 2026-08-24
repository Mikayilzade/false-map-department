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


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def safe_name(value: str) -> str:
    return "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in value)


def main() -> None:
    parser = argparse.ArgumentParser(description="Create E7 capture artifacts. Artifacts remain unreviewed evidence inputs, never gate PASS outcomes.")
    parser.add_argument("--output-dir", default=str(ROOT / ".phase12g-e7-captures"))
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--execute", action="store_true", help="Actually launch Godot. Without this flag the command only writes a capture plan.")
    parser.add_argument("--dossier-id", action="append", default=[])
    parser.add_argument("--scenario-id", action="append", default=[])
    parser.add_argument("--max-captures", type=int, default=0)
    parser.add_argument("--timeout-seconds", type=int, default=30)
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
    if unknown_scenarios:
        raise SystemExit(f"Unknown E7 scenario(s): {unknown_scenarios}")
    unknown_ids = [item for item in selected_ids if item not in all_ids]
    if unknown_ids:
        raise SystemExit(f"Unknown dossier ID(s): {unknown_ids}")

    rows = []
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
                "review_outcome": None,
                "status": "PLANNED_UNREVIEWED",
                "capture_path": None,
                "sidecar_path": None,
                "process_returncode": None,
            }
            if dossier_id not in ready_set:
                row["status"] = "BLOCKED_RUNTIME_BINDING"
                rows.append(row)
                continue
            if not args.execute:
                rows.append(row)
                continue
            if args.max_captures > 0 and executed >= args.max_captures:
                row["status"] = "NOT_EXECUTED_LIMIT"
                rows.append(row)
                continue

            capture_dir = out_dir / safe_name(scenario_id)
            capture_dir.mkdir(parents=True, exist_ok=True)
            capture_path = capture_dir / f"{safe_name(dossier_id)}.png"
            env = os.environ.copy()
            env.update({
                "FMD_PLAYTEST_DOSSIER_ID": dossier_id,
                "FMD_EMPIRICAL_BROAD": "1",
                "FMD_E7_SCENARIO_ID": scenario_id,
                "FMD_E7_UI_SCALE_PERCENT": str(scenario["ui_scale"]),
                "FMD_E7_REDUCED_MOTION": "1" if scenario["reduced_motion"] else "0",
                "FMD_E7_NON_COLOR": "1" if scenario["non_color"] else "0",
                "FMD_E7_NO_AUDIO": "1" if scenario["no_audio"] else "0",
                "FMD_E7_CAPTURE_PATH": str(capture_path),
                "FMD_E7_QUIT_AFTER_CAPTURE": "1",
            })
            try:
                completed = subprocess.run(
                    [args.godot, "--headless", "--path", str(ROOT)],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=args.timeout_seconds,
                    check=False,
                )
                row["process_returncode"] = completed.returncode
                log_base = capture_dir / f"{safe_name(dossier_id)}.godot"
                log_base.with_suffix(".stdout.log").write_text(completed.stdout, encoding="utf-8")
                log_base.with_suffix(".stderr.log").write_text(completed.stderr, encoding="utf-8")
                row["capture_path"] = str(capture_path) if capture_path.is_file() else None
                sidecar = Path(str(capture_path) + ".json")
                row["sidecar_path"] = str(sidecar) if sidecar.is_file() else None
                row["status"] = "CAPTURED_UNREVIEWED" if completed.returncode == 0 and capture_path.is_file() and sidecar.is_file() else "CAPTURE_FAILED"
            except subprocess.TimeoutExpired as exc:
                row["status"] = "CAPTURE_TIMEOUT"
                row["process_returncode"] = None
                (capture_dir / f"{safe_name(dossier_id)}.timeout.log").write_text(str(exc), encoding="utf-8")
            executed += 1
            rows.append(row)

    manifest = {
        "schema_version": 1,
        "gate_id": "E7",
        "evidence_kind": "CAPTURE_ACQUISITION_MANIFEST_NOT_REVIEW_OUTCOME",
        "execute_requested": args.execute,
        "counts": {
            "rows": len(rows),
            "captured_unreviewed": sum(row["status"] == "CAPTURED_UNREVIEWED" for row in rows),
            "blocked_runtime_binding": sum(row["status"] == "BLOCKED_RUNTIME_BINDING" for row in rows),
            "failed_or_timeout": sum(row["status"] in {"CAPTURE_FAILED", "CAPTURE_TIMEOUT"} for row in rows),
            "reviewed_pass": 0,
        },
        "rows": rows,
    }
    manifest_path = out_dir / "capture-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(manifest_path)
    print(json.dumps(manifest["counts"], sort_keys=True))
    if args.execute and any(row["status"] in {"CAPTURE_FAILED", "CAPTURE_TIMEOUT"} for row in rows):
        raise SystemExit(2)


if __name__ == "__main__":
    main()
