#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROTOCOLS = ROOT / "empirical" / "phase12g_session_protocols.json"
READINESS_SCRIPT = ROOT / "scripts" / "phase12g_runtime_readiness.py"
INTERACTION_SCRIPT = ROOT / "scripts" / "phase12g_e7_interaction.py"


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def safe_name(value: str) -> str:
    return "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in value)


def resolve_capture_command(
    godot: str,
    root: Path,
    requested_mode: str = "auto",
    *,
    platform: str | None = None,
    display: str | None = None,
    xvfb_path: str | None = None,
) -> tuple[list[str], str]:
    """Resolve a bounded E7 launch mode.

    E7 capture review needs a real rendered window. Linux CI therefore prefers Xvfb
    instead of Godot --headless. Headless remains an explicit diagnostic option but
    is never counted as a reviewable visual capture.
    """
    platform = sys.platform if platform is None else platform
    display = os.environ.get("DISPLAY", "") if display is None else display
    xvfb_path = shutil.which("xvfb-run") if xvfb_path is None else xvfb_path

    native = [godot, "--path", str(root), "--quit-after", "240"]
    headless = [godot, "--headless", "--path", str(root), "--quit-after", "240"]

    if requested_mode == "native":
        return native, "native"
    if requested_mode == "headless":
        return headless, "headless_diagnostic"
    if requested_mode == "xvfb":
        if not xvfb_path:
            raise RuntimeError("xvfb-run is required for requested E7 graphical capture mode")
        return [
            xvfb_path,
            "-a",
            "-s",
            "-screen 0 1280x800x24",
            godot,
            "--path",
            str(root),
            "--quit-after",
            "240",
        ], "xvfb"
    if requested_mode != "auto":
        raise ValueError(f"Unknown capture launch mode: {requested_mode}")

    if platform.startswith("linux") and not display:
        if not xvfb_path:
            raise RuntimeError("E7 graphical capture requires DISPLAY or xvfb-run on Linux; refusing silent headless fallback")
        return [
            xvfb_path,
            "-a",
            "-s",
            "-screen 0 1280x800x24",
            godot,
            "--path",
            str(root),
            "--quit-after",
            "240",
        ], "xvfb"
    return native, "native"


def build_interaction_command(
    python_executable: str,
    interaction_script: Path,
    godot: str,
    output_dir: Path,
    dossier_ids: list[str],
    scenario_ids: list[str],
    *,
    max_checks: int = 0,
    timeout_seconds: int = 20,
) -> list[str]:
    command = [
        python_executable,
        str(interaction_script),
        "--godot",
        godot,
        "--output-dir",
        str(output_dir),
        "--timeout-seconds",
        str(timeout_seconds),
    ]
    for dossier_id in dossier_ids:
        command.extend(["--dossier-id", dossier_id])
    for scenario_id in scenario_ids:
        command.extend(["--scenario-id", scenario_id])
    if max_checks > 0:
        command.extend(["--max-checks", str(max_checks)])
    return command


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create E7 graphical captures and, when executing, the matching presentation-level interaction artifacts. Neither component is a gate PASS by itself."
    )
    parser.add_argument("--output-dir", default=str(ROOT / ".phase12g-e7-captures"))
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--execute", action="store_true", help="Actually launch Godot. Without this flag the command only writes a capture plan and never runs interaction probes.")
    parser.add_argument("--capture-launch-mode", choices=["auto", "xvfb", "native", "headless"], default="auto")
    parser.add_argument("--dossier-id", action="append", default=[])
    parser.add_argument("--scenario-id", action="append", default=[])
    parser.add_argument("--max-captures", type=int, default=0)
    parser.add_argument("--timeout-seconds", type=int, default=30)
    parser.add_argument("--interaction-timeout-seconds", type=int, default=20)
    parser.add_argument("--skip-interaction", action="store_true", help="Execute graphical captures only. This is an explicit diagnostic/acquisition override and never implies interaction completeness.")
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
    launch_resolution_error: str | None = None
    capture_command: list[str] | None = None
    launch_mode = "not_executed"
    if args.execute:
        try:
            capture_command, launch_mode = resolve_capture_command(args.godot, ROOT, args.capture_launch_mode)
        except (RuntimeError, ValueError) as exc:
            launch_resolution_error = str(exc)
            launch_mode = "unavailable"

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
                "launch_mode": launch_mode,
            }
            if dossier_id not in ready_set:
                row["status"] = "BLOCKED_RUNTIME_BINDING"
                rows.append(row)
                continue
            if not args.execute:
                rows.append(row)
                continue
            if launch_resolution_error is not None or capture_command is None:
                row["status"] = "CAPTURE_DISPLAY_UNAVAILABLE"
                row["launch_error"] = launch_resolution_error
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
            env.setdefault("LIBGL_ALWAYS_SOFTWARE", "1")
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
                "FMD_E7_CAPTURE_LAUNCH_MODE": launch_mode,
            })
            try:
                completed = subprocess.run(
                    capture_command,
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
                visual_mode = launch_mode in {"xvfb", "native"}
                if completed.returncode == 0 and capture_path.is_file() and sidecar.is_file() and visual_mode:
                    row["status"] = "CAPTURED_UNREVIEWED"
                elif completed.returncode == 0 and capture_path.is_file() and sidecar.is_file():
                    row["status"] = "CAPTURED_NONVISUAL_UNREVIEWABLE"
                else:
                    row["status"] = "CAPTURE_FAILED"
            except subprocess.TimeoutExpired as exc:
                row["status"] = "CAPTURE_TIMEOUT"
                row["process_returncode"] = None
                (capture_dir / f"{safe_name(dossier_id)}.timeout.log").write_text(str(exc), encoding="utf-8")
            executed += 1
            rows.append(row)

    failure_statuses = {"CAPTURE_FAILED", "CAPTURE_TIMEOUT", "CAPTURE_DISPLAY_UNAVAILABLE"}
    interaction_summary: dict = {
        "requested": False,
        "status": "NOT_REQUESTED",
        "returncode": None,
        "manifest_path": None,
        "counts": {},
    }
    interaction_rc = 0
    if args.execute and not args.skip_interaction:
        interaction_summary["requested"] = True
        interaction_dir = out_dir / "interaction"
        interaction_command = build_interaction_command(
            sys.executable,
            INTERACTION_SCRIPT,
            args.godot,
            interaction_dir,
            list(selected_ids),
            list(selected_scenarios),
            max_checks=args.max_captures,
            timeout_seconds=args.interaction_timeout_seconds,
        )
        completed_interaction = subprocess.run(
            interaction_command,
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        interaction_rc = int(completed_interaction.returncode)
        (out_dir / "interaction-command.stdout.log").write_text(completed_interaction.stdout, encoding="utf-8")
        (out_dir / "interaction-command.stderr.log").write_text(completed_interaction.stderr, encoding="utf-8")
        interaction_manifest_path = interaction_dir / "interaction-manifest.json"
        interaction_summary.update({
            "returncode": interaction_rc,
            "status": "INTERACTION_ACQUISITION_PASS" if interaction_rc == 0 else "INTERACTION_ACQUISITION_FAIL",
            "manifest_path": str(interaction_manifest_path) if interaction_manifest_path.is_file() else None,
        })
        if interaction_manifest_path.is_file():
            interaction_summary["counts"] = load(interaction_manifest_path).get("counts", {})
        elif interaction_rc == 0:
            interaction_rc = 2
            interaction_summary["returncode"] = interaction_rc
            interaction_summary["status"] = "INTERACTION_MANIFEST_MISSING"

    manifest = {
        "schema_version": 2,
        "gate_id": "E7",
        "evidence_kind": "CAPTURE_AND_INTERACTION_ACQUISITION_MANIFEST_NOT_REVIEW_OUTCOME",
        "execute_requested": args.execute,
        "requested_launch_mode": args.capture_launch_mode,
        "resolved_launch_mode": launch_mode,
        "interaction_acquisition": interaction_summary,
        "counts": {
            "rows": len(rows),
            "captured_unreviewed": sum(row["status"] == "CAPTURED_UNREVIEWED" for row in rows),
            "captured_nonvisual_unreviewable": sum(row["status"] == "CAPTURED_NONVISUAL_UNREVIEWABLE" for row in rows),
            "blocked_runtime_binding": sum(row["status"] == "BLOCKED_RUNTIME_BINDING" for row in rows),
            "failed_or_timeout": sum(row["status"] in failure_statuses for row in rows),
            "reviewed_pass": 0,
        },
        "rows": rows,
    }
    manifest_path = out_dir / "capture-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(manifest_path)
    print(json.dumps({"capture": manifest["counts"], "interaction": interaction_summary}, sort_keys=True))
    capture_failed = args.execute and any(row["status"] in failure_statuses for row in rows)
    if capture_failed or interaction_rc != 0:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
