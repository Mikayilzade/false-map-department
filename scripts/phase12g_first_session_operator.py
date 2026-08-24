#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREDICTION_PROMPT_ID = "DEMO02_PRE_EDIT_SECOND_ORDER_01"
PROTOCOL_VERSION = 1


def load_json(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return payload


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def require_id(value: str, label: str) -> str:
    value = value.strip()
    if not value:
        raise SystemExit(f"{label} is required")
    if any(ch.isspace() for ch in value):
        raise SystemExit(f"{label} must be pseudonymous and contain no whitespace")
    return value


def require_bool(payload: dict, key: str) -> bool:
    value = payload.get(key)
    if not isinstance(value, bool):
        raise SystemExit(f"observer field {key} must be true/false")
    return value


def require_number(payload: dict, key: str, minimum: float = 0.0) -> float:
    value = payload.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise SystemExit(f"observer field {key} must be numeric")
    value = float(value)
    if value < minimum:
        raise SystemExit(f"observer field {key} must be >= {minimum}")
    return value


def event_elapsed(telemetry: dict, event_type: str) -> float | None:
    for raw in telemetry.get("events", []):
        if isinstance(raw, dict) and raw.get("event_type") == event_type:
            value = raw.get("elapsed_seconds")
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                return float(value)
    return None


def session_paths(session_dir: Path) -> dict[str, Path]:
    return {
        "manifest": session_dir / "session-manifest.json",
        "observer": session_dir / "observer.json",
        "telemetry": session_dir / "telemetry.json",
        "launch_env": session_dir / "launch.env.txt",
        "e1": session_dir / "completed-E1.jsonl",
        "e2": session_dir / "completed-E2.jsonl",
        "e11": session_dir / "completed-E11.jsonl",
    }


def cmd_prepare(args: argparse.Namespace) -> None:
    tester_id = require_id(args.tester_id, "tester_id")
    session_id = require_id(args.session_id, "session_id")
    build_id = require_id(args.build_id, "build_id")
    session_dir = Path(args.output_dir).resolve() / session_id
    if session_dir.exists() and any(session_dir.iterdir()) and not args.force:
        raise SystemExit(f"{session_dir}: non-empty session directory; use --force only for an intentionally reset packet")
    session_dir.mkdir(parents=True, exist_ok=True)
    paths = session_paths(session_dir)

    manifest = {
        "protocol_version": PROTOCOL_VERSION,
        "tester_id": tester_id,
        "session_id": session_id,
        "demo_build_id": build_id,
        "dossier_sequence": ["DEMO01", "DEMO02", "DEMO03", "DEMO04", "DEMO05"],
        "prediction_prompt_id": PREDICTION_PROMPT_ID,
        "telemetry_path": str(paths["telemetry"]),
        "observer_outcomes_are_explicit": True,
        "raw_collateral_event_is_not_human_aha": True,
    }
    observer = {
        "protocol_version": PROTOCOL_VERSION,
        "tester_id": tester_id,
        "session_id": session_id,
        "naive": None,
        "e1_success": None,
        "e1_understood_at_seconds": None,
        "e2_packet_completed": None,
        "e2_success": None,
        "e2_prediction_prompt_id": PREDICTION_PROMPT_ID,
        "first_collateral_aha_observed": None,
        "first_collateral_aha_seconds": None,
        "session_end_seconds": None,
        "observer_notes": "",
    }
    write_json(paths["manifest"], manifest)
    write_json(paths["observer"], observer)
    paths["launch_env"].write_text(
        "\n".join([
            "FMD_PLAYTEST_DOSSIER_ID=DEMO01",
            f"FMD_EMPIRICAL_TESTER_ID={tester_id}",
            f"FMD_EMPIRICAL_SESSION_ID={session_id}",
            f"FMD_EMPIRICAL_DEMO_BUILD_ID={build_id}",
            f"FMD_EMPIRICAL_TELEMETRY_PATH={paths['telemetry']}",
        ]) + "\n",
        encoding="utf-8",
    )
    print(session_dir)
    print("Prepared blank observer packet. No evidence row was created or appended.")


def cmd_launch(args: argparse.Namespace) -> None:
    session_dir = Path(args.session_dir).resolve()
    paths = session_paths(session_dir)
    manifest = load_json(paths["manifest"])
    env = os.environ.copy()
    env.update({
        "FMD_PLAYTEST_DOSSIER_ID": "DEMO01",
        "FMD_EMPIRICAL_TESTER_ID": require_id(str(manifest.get("tester_id", "")), "tester_id"),
        "FMD_EMPIRICAL_SESSION_ID": require_id(str(manifest.get("session_id", "")), "session_id"),
        "FMD_EMPIRICAL_DEMO_BUILD_ID": require_id(str(manifest.get("demo_build_id", "")), "demo_build_id"),
        "FMD_EMPIRICAL_TELEMETRY_PATH": str(paths["telemetry"]),
    })
    command = [args.godot, "--path", str(ROOT)]
    print("Launching representative GUI session:", " ".join(command))
    completed = subprocess.run(command, cwd=ROOT, env=env, check=False)
    raise SystemExit(completed.returncode)


def cmd_finalize(args: argparse.Namespace) -> None:
    session_dir = Path(args.session_dir).resolve()
    paths = session_paths(session_dir)
    manifest = load_json(paths["manifest"])
    observer = load_json(paths["observer"])
    telemetry = load_json(paths["telemetry"])

    tester_id = require_id(str(manifest.get("tester_id", "")), "tester_id")
    session_id = require_id(str(manifest.get("session_id", "")), "session_id")
    build_id = require_id(str(manifest.get("demo_build_id", "")), "demo_build_id")
    if observer.get("tester_id") != tester_id or observer.get("session_id") != session_id:
        raise SystemExit("observer identity does not match session manifest")
    if telemetry.get("tester_id") != tester_id or telemetry.get("session_id") != session_id:
        raise SystemExit("telemetry identity does not match session manifest")
    if telemetry.get("demo_build_id") != build_id:
        raise SystemExit("telemetry demo_build_id does not match session manifest")

    naive = require_bool(observer, "naive")
    e1_success = require_bool(observer, "e1_success")
    e1_time = require_number(observer, "e1_understood_at_seconds")
    e2_packet_completed = require_bool(observer, "e2_packet_completed")
    e2_success = require_bool(observer, "e2_success")
    prompt_id = str(observer.get("e2_prediction_prompt_id", "")).strip()
    if prompt_id != PREDICTION_PROMPT_ID:
        raise SystemExit(f"e2_prediction_prompt_id must remain {PREDICTION_PROMPT_ID}")
    aha_observed = require_bool(observer, "first_collateral_aha_observed")
    aha_seconds = require_number(observer, "first_collateral_aha_seconds", minimum=-1.0)
    if aha_observed and aha_seconds < 0:
        raise SystemExit("first_collateral_aha_seconds must be >=0 when an aha was observed")
    if not aha_observed and aha_seconds != -1.0:
        raise SystemExit("use first_collateral_aha_seconds=-1 when no genuine aha was observed")
    session_end = require_number(observer, "session_end_seconds")

    completion_seconds = event_elapsed(telemetry, "demo_completed")
    completed = completion_seconds is not None
    if completion_seconds is None:
        completion_seconds = session_end

    start_marker = telemetry.get("session_started_ms")
    if isinstance(start_marker, bool) or not isinstance(start_marker, (int, float)):
        raise SystemExit("telemetry session_started_ms missing/invalid")

    # Deliberately do not read collateral_consequence_seen as human comprehension or aha.
    e1 = {
        "schema_version": 1,
        "gate_id": "E1",
        "tester_id": tester_id,
        "naive": naive,
        "session_id": session_id,
        "understood_within_seconds": e1_time,
        "success": e1_success,
    }
    e2 = {
        "schema_version": 1,
        "gate_id": "E2",
        "tester_id": tester_id,
        "session_id": session_id,
        "packet_completed": e2_packet_completed,
        "prediction_prompt_id": prompt_id,
        "success": e2_success,
    }
    e11 = {
        "schema_version": 1,
        "gate_id": "E11",
        "tester_id": tester_id,
        "demo_build_id": build_id,
        "start_timestamp": start_marker,
        "first_collateral_aha_seconds": aha_seconds,
        "completion_seconds": completion_seconds,
        "completed": completed,
    }

    paths["e1"].write_text(json.dumps(e1, sort_keys=True) + "\n", encoding="utf-8")
    paths["e2"].write_text(json.dumps(e2, sort_keys=True) + "\n", encoding="utf-8")
    paths["e11"].write_text(json.dumps(e11, sort_keys=True) + "\n", encoding="utf-8")
    print(paths["e1"])
    print(paths["e2"])
    print(paths["e11"])
    print("Finalized observer-controlled rows locally. Nothing was appended to empirical/evidence.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare, launch and finalize real Phase 12G E1/E2/E11 first-session evidence without inferring human outcomes from telemetry.")
    sub = parser.add_subparsers(dest="command", required=True)

    prepare = sub.add_parser("prepare")
    prepare.add_argument("--tester-id", required=True)
    prepare.add_argument("--session-id", required=True)
    prepare.add_argument("--build-id", default="phase12g-production-demo")
    prepare.add_argument("--output-dir", default=str(ROOT / ".phase12g-first-sessions"))
    prepare.add_argument("--force", action="store_true")
    prepare.set_defaults(func=cmd_prepare)

    launch = sub.add_parser("launch")
    launch.add_argument("--session-dir", required=True)
    launch.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    launch.set_defaults(func=cmd_launch)

    finalize = sub.add_parser("finalize")
    finalize.add_argument("--session-dir", required=True)
    finalize.set_defaults(func=cmd_finalize)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
