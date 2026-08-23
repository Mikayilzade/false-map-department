#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G SESSION PACKET FAIL: {message}")


def load_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def main() -> None:
    protocols = json.loads((ROOT / "empirical/phase12g_session_protocols.json").read_text(encoding="utf-8"))
    if protocols.get("protocol_version") != 1:
        fail("protocol version drift")
    if not protocols["rules"].get("templates_are_not_evidence", False):
        fail("template/evidence separation disabled")
    scenarios = protocols["protocols"]["E7"]["capture_scenarios"]
    if len(scenarios) != 5:
        fail("E7 must retain five frozen capture scenarios")
    if not any(row.get("ui_scale") == 150 for row in scenarios):
        fail("E7 maximum UI-scale scenario must use production 150% ceiling")

    accessibility = (ROOT / "src/application/accessibility_settings_service.gd").read_text(encoding="utf-8")
    if "UI_SCALE_MAX_PERCENT := 150" not in accessibility:
        fail("production UI-scale ceiling no longer matches capture protocol")

    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-") as tmp:
        out = Path(tmp)
        subprocess.run(
            [sys.executable, str(ROOT / "scripts/phase12g_prepare_session_packets.py"), "--output", str(out)],
            cwd=ROOT,
            check=True,
            stdout=subprocess.DEVNULL,
        )
        manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
        counts = manifest["counts"]
        expected = {
            "E3_rows": 12,
            "E4_rows": 2,
            "E6_rows": 8,
            "E7_shippable_ids": 57,
            "E7_scenarios": 5,
            "E7_rows": 285,
            "E9_rows": 12,
            "E10_archetypes": 10,
            "E10_pairs": 45,
        }
        for key, value in expected.items():
            if counts.get(key) != value:
                fail(f"unexpected generated count {key}: {counts.get(key)} != {value}")
        if counts.get("E5_rows", 0) < 1:
            fail("no 3-4-layer linked-authority dossiers discovered for E5")

        expected_families = [f"A{i}" for i in range(1, 11)]
        if manifest.get("agent_archetypes") != expected_families:
            fail(f"E10 canonical family set drift: {manifest.get('agent_archetypes')}")
        variants = manifest.get("agent_archetype_variants_by_family", {})
        if sorted(variants, key=lambda value: int(value[1:])) != expected_families:
            fail("E10 variant manifest must cover every canonical A1-A10 family")
        if any(not values for values in variants.values()):
            fail("E10 canonical family has no production variant")
        if counts.get("E10_raw_variant_ids", 0) < 10:
            fail("E10 raw variant inventory cannot be smaller than the ten canonical families")

        e3 = load_jsonl(out / "E3_session_template.jsonl")
        if any(row.get("tester_id") is not None or row.get("completion_seconds") is not None or row.get("completed") is not None for row in e3):
            fail("E3 template contains fabricated observation outcome")
        e7 = load_jsonl(out / "E7_capture_matrix.jsonl")
        if any(row.get("interaction_complete") is not None or row.get("capture_review_pass") is not None for row in e7):
            fail("E7 matrix contains fabricated PASS data")
        e9 = load_jsonl(out / "E9_remix_template.jsonl")
        if any(not row.get("source_dossier_id") for row in e9):
            fail("E9 remix/source mapping incomplete")
        e10 = load_jsonl(out / "E10_agent_pair_template.jsonl")
        if any(row.get("predicted_distinction") is not None or row.get("correct") is not None for row in e10):
            fail("E10 template contains fabricated human result")
        pair_members = {str(row.get("agent_a")) for row in e10} | {str(row.get("agent_b")) for row in e10}
        if pair_members != set(expected_families):
            fail("E10 pair template must compare canonical A1-A10 families, not raw themed variant IDs")

    print("Phase 12G session packet audit: PASS (E3-E7 + E9/E10 templates, E10 canonical A1-A10 families, 57x5 E7 matrix, zero fabricated outcomes)")


if __name__ == "__main__":
    main()
