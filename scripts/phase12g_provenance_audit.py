#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"
COLLECTOR = SCRIPT_DIR / "phase12g_collect_completed_rows.py"

sys.path.insert(0, str(SCRIPT_DIR))
import phase12g_provenance as provenance  # noqa: E402

SOURCE = "1" * 40
BUILD = "BUILD-PROVENANCE-AUDIT"
CHANNEL = "audit_channel"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G PROVENANCE AUDIT FAIL: {message}")


def expect(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def test_helper() -> dict:
    base = {
        "schema_version": 1,
        "gate_id": "E1",
        "tester_id": "AUDIT_TESTER",
        "naive": True,
        "session_id": "AUDIT_SESSION",
        "understood_within_seconds": 12,
        "success": True,
    }
    enriched = provenance.enrich_row(base, source_head=SOURCE, build_id=BUILD, channel=CHANNEL)
    expect(enriched["source_head"] == SOURCE, "source_head was not persisted")
    expect(enriched["source_build_id"] == BUILD, "source_build_id was not persisted")
    expect(enriched["acquisition_channel"] == CHANNEL, "acquisition_channel was not persisted")
    expect(enriched["evidence_provenance_version"] == 1, "provenance version missing")
    expect(enriched["tester_id"] == base["tester_id"], "observation fields changed while enriching provenance")

    conflicted = dict(base)
    conflicted["source_head"] = "2" * 40
    try:
        provenance.enrich_row(conflicted, source_head=SOURCE, build_id=BUILD, channel=CHANNEL)
    except ValueError:
        pass
    else:
        fail("conflicting pre-existing source_head was accepted")

    for kwargs, label in [
        ({"source_head": "bad", "build_id": BUILD, "channel": CHANNEL}, "invalid source SHA"),
        ({"source_head": SOURCE, "build_id": "", "channel": CHANNEL}, "blank build ID"),
        ({"source_head": SOURCE, "build_id": BUILD, "channel": ""}, "blank channel"),
    ]:
        try:
            provenance.enrich_row(base, **kwargs)
        except ValueError:
            continue
        fail(f"{label} was accepted")
    return enriched


def test_collector_persistence(enriched: dict) -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-provenance-") as raw:
        root = Path(raw)
        input_path = root / "input.jsonl"
        evidence_root = root / "evidence"
        input_path.write_text(json.dumps(enriched, sort_keys=True) + "\n", encoding="utf-8")
        completed = subprocess.run(
            [sys.executable, str(COLLECTOR), "--input", str(input_path), "--evidence-root", str(evidence_root), "--append"],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        expect(completed.returncode == 0, f"collector rejected enriched audit row: {(completed.stdout + completed.stderr).strip()}")
        target = evidence_root / "E1.jsonl"
        expect(target.is_file(), "collector did not create temporary evidence target")
        rows = [json.loads(line) for line in target.read_text(encoding="utf-8").splitlines() if line.strip()]
        expect(len(rows) == 1, "temporary append did not preserve exactly one row")
        stored = rows[0]
        for key in ["source_head", "source_build_id", "acquisition_channel", "evidence_provenance_version"]:
            expect(stored.get(key) == enriched.get(key), f"collector lost provenance field {key}")


def test_ingest_wiring() -> None:
    required = {
        "phase12g_field_kit_ingest.py": ["phase12g_provenance", "human_field_kit_v4", "provenance_persisted_in_rows"],
        "phase12g_marketing_expectation_ingest.py": ["phase12g_provenance", "e8_marketing_packet", "provenance_persisted_in_rows"],
        "phase12g_reference_profile_ingest.py": ["phase12g_provenance", "t8_reference_profile", "provenance_persisted_in_rows"],
    }
    for name, markers in required.items():
        text = (SCRIPT_DIR / name).read_text(encoding="utf-8")
        missing = [marker for marker in markers if marker not in text]
        expect(not missing, f"{name} missing provenance wiring markers: {missing}")


def main() -> None:
    enriched = test_helper()
    test_collector_persistence(enriched)
    test_ingest_wiring()
    print("Phase 12G evidence provenance audit: PASS (source SHA + build + acquisition channel persist through deliberate append)")


if __name__ == "__main__":
    main()
