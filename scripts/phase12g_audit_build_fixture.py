#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "scripts/phase12g_build_artifact_contract.py"


def create_bound_artifact(root: Path, *, source_head: str, role: str, build_id: str) -> tuple[Path, Path]:
    root.mkdir(parents=True, exist_ok=True)
    artifact = root / f"{role}-{build_id}.pck"
    artifact.write_bytes((f"FMD-AUDIT-PACKAGE\nrole={role}\nbuild_id={build_id}\nsource_head={source_head}\n").encode("utf-8"))
    record = root / f"{role}-{build_id}.binding.json"
    completed = subprocess.run(
        [
            sys.executable,
            str(CONTRACT),
            "create",
            "--source-head",
            source_head,
            "--role",
            role,
            "--build-id",
            build_id,
            "--artifact",
            str(artifact),
            "--output",
            str(record),
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"could not create bound {role} audit package: {completed.stdout}{completed.stderr}")
    return artifact, record


def kit_build_args(root: Path, *, source_head: str, demo_build_id: str, production_build_id: str) -> list[str]:
    demo_artifact, demo_record = create_bound_artifact(root, source_head=source_head, role="demo", build_id=demo_build_id)
    production_artifact, production_record = create_bound_artifact(root, source_head=source_head, role="production", build_id=production_build_id)
    return [
        "--demo-build-artifact", str(demo_artifact),
        "--demo-build-artifact-record", str(demo_record),
        "--production-build-artifact", str(production_artifact),
        "--production-build-artifact-record", str(production_record),
    ]
