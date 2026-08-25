#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts/phase12g_mature_session_batch.py"
PROTOCOLS = json.loads((ROOT / "empirical/phase12g_session_protocols.json").read_text(encoding="utf-8"))["protocols"]


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G MATURE BATCH FAIL: {message}")


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        fail(f"{path}: expected object")
    return value


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-mature-") as tmp:
        base = Path(tmp)
        root = base / "original"
        subprocess.run([
            sys.executable,
            str(HELPER),
            "prepare",
            "--count", "2",
            "--tester-prefix", "AUDIT-MATURE-T",
            "--build-id", "AUDIT-BUILD-EXACT",
            "--output-dir", str(root),
        ], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)

        manifest_path = root / "batch-manifest.json"
        manifest = load(manifest_path)
        if manifest.get("batch_version") != 2 or manifest.get("path_contract") != "packet_paths_relative_to_batch_manifest":
            fail("batch manifest must declare portable relative-path contract")
        if manifest.get("packet_count") != 2:
            fail("prepare must create exactly two audit packets")
        if manifest.get("human_outcomes_required") is not True or manifest.get("repository_evidence_appended") is not False:
            fail("batch manifest must preserve the no-fabrication boundary")

        packets = manifest.get("packets", [])
        if len(packets) != 2:
            fail("batch manifest packet count mismatch")
        for packet in packets:
            if Path(str(packet.get("packet_dir", ""))).is_absolute() or Path(str(packet.get("observer_packet", ""))).is_absolute():
                fail("portable mature manifest must not store absolute packet paths")

        first = load(manifest_path.parent / str(packets[0]["observer_packet"]))
        second = load(manifest_path.parent / str(packets[1]["observer_packet"]))
        for packet in (first, second):
            if packet.get("build_id") != "AUDIT-BUILD-EXACT":
                fail("every packet must pin the explicit build ID")
            if packet.get("rules_known_before_session") is not None:
                fail("rule knowledge must remain blank until observed")
            if packet.get("human_outcomes_inferred") is not False:
                fail("packet must explicitly state that outcomes were not inferred")
            rows = packet.get("rows_by_gate", {})
            if set(rows) != {"E3", "E4", "E5", "E6", "E9", "E10"}:
                fail("packet must cover exactly the six mature-human gates")
            if len(rows["E3"]) != len(PROTOCOLS["E3"]["representative_dossiers"]) * 2:
                fail("E3 must cover both comparative methods for every representative dossier")
            if len(rows["E4"]) != len(PROTOCOLS["E4"]["windows"]):
                fail("E4 must cover both frozen repetition windows")
            if len(rows["E6"]) != len(PROTOCOLS["E6"]["representative_dossiers"]):
                fail("E6 must cover the frozen representative late-dossier set")
            if len(rows["E9"]) != 12:
                fail("E9 must prepare all 12 frozen remix comparisons")
            if len(rows["E10"]) < 2:
                fail("E10 must prepare deterministic comparisons over taught archetypes")
            for gate_id, gate_rows in rows.items():
                for row in gate_rows:
                    for key, value in row.items():
                        if key in {
                            "completion_seconds", "completed", "rule_knowledge_confirmed",
                            "same_trick_assessment", "notes", "requirement_id",
                            "identified_authority_layer", "correct", "tutorial_recall_used",
                            "answered_cause", "used_raw_debug_log",
                            "described_as_changed_causal_problem", "predicted_distinction",
                        } and value is not None:
                            fail(f"{gate_id}: human observation field {key} must remain null after prepare")

        first_e3 = first["rows_by_gate"]["E3"]
        second_e3 = second["rows_by_gate"]["E3"]
        if first_e3[0]["method"] == second_e3[0]["method"]:
            fail("adjacent tester packets must counterbalance first E3 method order")

        moved = base / "relocated"
        shutil.copytree(root, moved)
        shutil.rmtree(root)
        moved_manifest = moved / "batch-manifest.json"
        moved_payload = load(moved_manifest)

        status = subprocess.run([
            sys.executable,
            str(HELPER),
            "status",
            "--manifest", str(moved_manifest),
        ], cwd=ROOT, check=True, capture_output=True, text=True)
        status_payload = json.loads(status.stdout)
        if status_payload.get("counts", {}).get("PREPARED") != 2:
            fail("relocated blank packets must remain PREPARED, not ready/finalized")
        if status_payload.get("human_outcomes_inferred") is not False or status_payload.get("repository_evidence_appended") is not False:
            fail("status must not infer or append outcomes")

        first_packet_dir = moved_manifest.parent / str(moved_payload["packets"][0]["packet_dir"])
        finalize = subprocess.run([
            sys.executable,
            str(HELPER),
            "finalize",
            "--packet-dir", str(first_packet_dir),
        ], cwd=ROOT, capture_output=True, text=True)
        if finalize.returncode == 0:
            fail("blank packet must not finalize")
        for gate_id in ("E3", "E4", "E5", "E6", "E9", "E10"):
            if (first_packet_dir / f"completed-{gate_id}.jsonl").exists():
                fail("blank packet must not create completed evidence rows")

    print("Phase 12G mature-session batch audit: PASS (frozen selections + counterbalance + relocatable manifest paths + null human outcomes + no-evidence finalize guard)")


if __name__ == "__main__":
    main()
