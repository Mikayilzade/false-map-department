#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
READINESS = ROOT / "scripts" / "phase12g_runtime_readiness.py"
REPAIRED_IDS = {"D06", "D07", "D08", "D14", "D16", "D17", "D26"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"PHASE12G FULL READINESS AUDIT FAIL: {message}")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-readiness-") as temp_dir:
        output = Path(temp_dir) / "runtime-readiness.json"
        completed = subprocess.run(
            [sys.executable, str(READINESS), "--output", str(output)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        require(completed.returncode == 0, f"runtime readiness script rc={completed.returncode}: {completed.stderr}")
        payload = json.loads(output.read_text(encoding="utf-8"))

    counts = payload.get("counts") or {}
    require(counts.get("total") == 57, f"expected total=57, got {counts}")
    require(counts.get("ready") == 57, f"expected ready=57, got {counts}")
    require(counts.get("blocked") == 0, f"expected blocked=0, got {counts}")
    require(payload.get("blocked_ids") == [], f"blocked IDs remain: {payload.get('blocked_ids')}")
    ready = set(payload.get("ready_ids") or [])
    require(REPAIRED_IDS <= ready, f"repaired IDs not all ready: {sorted(REPAIRED_IDS - ready)}")
    for gate_id, row in (payload.get("protocol_readiness") or {}).items():
        require(row.get("blocked") == [], f"{gate_id} still has blocked protocol IDs: {row.get('blocked')}")

    print("Phase 12G full runtime readiness audit: PASS (57/57 shippable IDs ready; zero binding blockers)")


if __name__ == "__main__":
    main()
