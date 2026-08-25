#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OPERATOR = ROOT / "scripts/phase12g_first_session_operator.py"
DEFAULT_ROOT = ROOT / ".phase12g-first-sessions"
BATCH_VERSION = 1


def fail(message: str) -> None:
    raise SystemExit(message)


def load_json(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        fail(f"{path}: expected JSON object")
    return payload


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def identifier(prefix: str, index: int, width: int) -> str:
    value = f"{prefix}{index:0{width}d}"
    if not prefix or any(ch.isspace() for ch in value):
        fail("ID prefixes must be non-empty and contain no whitespace")
    return value


def packet_status(session_dir: Path) -> dict:
    manifest_path = session_dir / "session-manifest.json"
    observer_path = session_dir / "observer.json"
    telemetry_path = session_dir / "telemetry.json"
    completed = [session_dir / f"completed-{gate}.jsonl" for gate in ("E1", "E2", "E11")]
    if not manifest_path.exists() or not observer_path.exists():
        return {"status": "MISSING_PACKET", "ready_to_launch": False, "ready_to_finalize": False, "finalized": False}
    manifest = load_json(manifest_path)
    observer = load_json(observer_path)
    observed_fields = [
        "naive",
        "e1_success",
        "e1_understood_at_seconds",
        "e2_packet_completed",
        "e2_success",
        "first_collateral_aha_observed",
        "first_collateral_aha_seconds",
        "session_end_seconds",
    ]
    observer_complete = all(observer.get(key) is not None for key in observed_fields)
    telemetry_present = telemetry_path.exists()
    finalized = all(path.exists() and path.stat().st_size > 0 for path in completed)
    if finalized:
        status = "FINALIZED_LOCAL"
    elif telemetry_present and observer_complete:
        status = "READY_TO_FINALIZE"
    elif telemetry_present:
        status = "AWAITING_OBSERVER"
    else:
        status = "PREPARED"
    return {
        "status": status,
        "ready_to_launch": True,
        "ready_to_finalize": telemetry_present and observer_complete and not finalized,
        "finalized": finalized,
        "tester_id": str(manifest.get("tester_id", "")),
        "session_id": str(manifest.get("session_id", "")),
        "demo_build_id": str(manifest.get("demo_build_id", "")),
        "telemetry_present": telemetry_present,
        "observer_complete": observer_complete,
        "repository_evidence_appended": False,
    }


def cmd_prepare(args: argparse.Namespace) -> None:
    if args.count < 1:
        fail("--count must be >= 1")
    output_root = Path(args.output_dir).resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    width = max(3, len(str(args.start + args.count - 1)))
    packets: list[dict] = []
    for offset in range(args.count):
        number = args.start + offset
        tester_id = identifier(args.tester_prefix, number, width)
        session_id = identifier(args.session_prefix, number, width)
        session_dir = output_root / session_id
        command = [
            sys.executable,
            str(OPERATOR),
            "prepare",
            "--tester-id",
            tester_id,
            "--session-id",
            session_id,
            "--build-id",
            args.build_id,
            "--output-dir",
            str(output_root),
        ]
        subprocess.run(command, cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
        packets.append({
            "tester_id": tester_id,
            "session_id": session_id,
            "session_dir": str(session_dir),
            "launch_command": f"python3 scripts/phase12g_first_session_operator.py launch --session-dir {session_dir} --godot <Godot-4.7.1>",
            "finalize_command": f"python3 scripts/phase12g_first_session_operator.py finalize --session-dir {session_dir}",
        })

    manifest = {
        "batch_version": BATCH_VERSION,
        "purpose": "E1_E2_E11_real_human_first_session_acquisition",
        "demo_build_id": args.build_id,
        "packet_count": len(packets),
        "packets": packets,
        "human_outcomes_required": True,
        "templates_are_not_evidence": True,
        "repository_evidence_appended": False,
    }
    write_json(output_root / args.manifest_name, manifest)
    print(f"Prepared {len(packets)} first-session packets at {output_root}")
    print("No human outcome was inferred and no repository evidence was appended.")


def cmd_status(args: argparse.Namespace) -> None:
    manifest_path = Path(args.manifest).resolve()
    manifest = load_json(manifest_path)
    rows: list[dict] = []
    for packet in manifest.get("packets", []):
        if not isinstance(packet, dict):
            fail("batch manifest packet must be an object")
        session_dir = Path(str(packet.get("session_dir", "")))
        status = packet_status(session_dir)
        status["session_dir"] = str(session_dir)
        rows.append(status)
    counts: dict[str, int] = {}
    for row in rows:
        counts[row["status"]] = counts.get(row["status"], 0) + 1
    result = {
        "batch_version": int(manifest.get("batch_version", 0)),
        "packet_count": len(rows),
        "counts": counts,
        "packets": rows,
        "human_outcomes_inferred": False,
        "repository_evidence_appended": False,
    }
    if args.output:
        write_json(Path(args.output).resolve(), result)
    print(json.dumps(result, indent=2, sort_keys=True))


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare and inspect batches of real E1/E2/E11 first-session packets without fabricating human evidence.")
    sub = parser.add_subparsers(dest="command", required=True)

    prepare = sub.add_parser("prepare")
    prepare.add_argument("--count", type=int, required=True)
    prepare.add_argument("--start", type=int, default=1)
    prepare.add_argument("--tester-prefix", default="T")
    prepare.add_argument("--session-prefix", default="FS")
    prepare.add_argument("--build-id", default="phase12g-production-demo")
    prepare.add_argument("--output-dir", default=str(DEFAULT_ROOT))
    prepare.add_argument("--manifest-name", default="batch-manifest.json")
    prepare.set_defaults(func=cmd_prepare)

    status = sub.add_parser("status")
    status.add_argument("--manifest", required=True)
    status.add_argument("--output")
    status.set_defaults(func=cmd_status)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
