#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKET = ROOT / "scripts/phase12g_marketing_expectation_packet.py"
BINDER = ROOT / "scripts/phase12g_e8_acquisition_build_bind.py"


def run_checked(command: list[str]) -> None:
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    if completed.returncode != 0:
        raise SystemExit((completed.stdout + completed.stderr).strip() or "E8 acquisition preparation failed")


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare a real E8 acquisition packet with the exact production package bytes frozen before respondent observation.")
    parser.add_argument("--asset-version", required=True)
    parser.add_argument("--build-id", required=True)
    parser.add_argument("--source-head", required=True)
    parser.add_argument("--asset", action="append", default=[], required=True)
    parser.add_argument("--claims")
    parser.add_argument("--respondents", type=int, default=5)
    parser.add_argument("--respondent-prefix", default="E8R-")
    parser.add_argument("--production-build-artifact", type=Path, required=True)
    parser.add_argument("--production-build-artifact-record", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    command = [
        sys.executable, str(PACKET), "prepare",
        "--asset-version", args.asset_version,
        "--build-id", args.build_id,
        "--source-head", args.source_head,
        "--representative-attestation",
        "--respondents", str(args.respondents),
        "--respondent-prefix", args.respondent_prefix,
        "--output", str(args.output),
    ]
    if args.claims:
        command += ["--claims", args.claims]
    for asset in args.asset:
        command += ["--asset", asset]
    run_checked(command)
    try:
        run_checked([
            sys.executable, str(BINDER), "bind",
            "--packet", str(args.output),
            "--artifact", str(args.production_build_artifact),
            "--record", str(args.production_build_artifact_record),
        ])
    except BaseException:
        # A half-prepared packet is not safe acquisition material.
        # Preserve files for diagnosis but stamp a visible fail-closed marker.
        (args.output / "NOT-APPEND-READY.txt").write_text(
            "E8 acquisition preparation failed before packaged-build byte binding completed. Do not collect respondent observations with this packet.\n",
            encoding="utf-8",
        )
        raise
    print(f"Prepared byte-bound E8 acquisition packet at {args.output}; no respondent outcome was created or appended")


if __name__ == "__main__":
    main()
