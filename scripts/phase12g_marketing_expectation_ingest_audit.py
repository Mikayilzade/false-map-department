#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKET = ROOT / "scripts/phase12g_marketing_expectation_packet.py"
INGEST = ROOT / "scripts/phase12g_marketing_expectation_ingest.py"
SOURCE_HEAD = "1" * 40
WRONG_HEAD = "2" * 40
ROLES = (
    ("store_key_art", ".png"),
    ("gameplay_map_world", ".png"),
    ("gameplay_consequence", ".png"),
    ("late_game_linked", ".png"),
    ("trailer", ".mp4"),
)


def run(args: list[str], expect_ok: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if expect_ok and result.returncode != 0:
        raise SystemExit(f"command failed: {' '.join(args)}\nstdout={result.stdout}\nstderr={result.stderr}")
    if not expect_ok and result.returncode == 0:
        raise SystemExit(f"command unexpectedly succeeded: {' '.join(args)}")
    return result


def evidence_rows(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-e8-ingest-audit-") as raw:
        temp = Path(raw)
        media = temp / "media"
        media.mkdir()
        asset_args: list[str] = []
        for role, suffix in ROLES:
            path = media / f"{role}{suffix}"
            path.write_bytes((f"SYNTHETIC-AUDIT-ASSET:{role}\n").encode("utf-8"))
            asset_args += ["--asset", f"{role}={path}"]

        packet_root = temp / "packet"
        run([
            sys.executable,
            str(PACKET),
            "prepare",
            "--asset-version", "AUDIT-ASSET-V1",
            "--build-id", "AUDIT-BUILD",
            "--source-head", SOURCE_HEAD,
            *asset_args,
            "--representative-attestation",
            "--respondents", "2",
            "--output", str(packet_root),
        ])

        respondents_path = packet_root / "respondents.json"
        respondents = json.loads(respondents_path.read_text(encoding="utf-8"))
        respondents["rows"][0].update({
            "expected_play_category": "systemic puzzle",
            "freeform_builder_expectation": False,
            "notes": "synthetic audit observation A; not empirical evidence",
        })
        respondents["rows"][1].update({
            "expected_play_category": "map puzzle",
            "freeform_builder_expectation": False,
            "notes": "synthetic audit observation B; not empirical evidence",
        })
        respondents_path.write_text(json.dumps(respondents, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        run([sys.executable, str(PACKET), "finalize", "--packet", str(packet_root)])

        evidence_root = temp / "evidence"
        target = evidence_root / "E8.jsonl"
        dry = run([
            sys.executable, str(INGEST),
            "--packet", str(packet_root),
            "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root),
        ])
        dry_result = json.loads(dry.stdout)
        if dry_result.get("mode") != "dry_run" or dry_result.get("new_rows") != 2:
            raise SystemExit(f"unexpected E8 dry-run result: {dry_result}")
        if target.exists():
            raise SystemExit("E8 ingest dry-run mutated evidence")

        run([
            sys.executable, str(INGEST),
            "--packet", str(packet_root),
            "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root),
            "--append",
        ])
        rows = evidence_rows(target)
        if len(rows) != 2 or any(row.get("gate_id") != "E8" for row in rows):
            raise SystemExit("E8 append did not produce exactly two validated rows")

        repeat = run([
            sys.executable, str(INGEST),
            "--packet", str(packet_root),
            "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root),
            "--append",
        ])
        repeat_result = json.loads(repeat.stdout)
        if repeat_result.get("new_rows") != 0 or len(evidence_rows(target)) != 2:
            raise SystemExit("repeat E8 ingest was not idempotent")

        wrong = run([
            sys.executable, str(INGEST),
            "--packet", str(packet_root),
            "--expected-source-head", WRONG_HEAD,
            "--evidence-root", str(evidence_root),
        ], expect_ok=False)
        if "source_head mismatch" not in (wrong.stderr + wrong.stdout):
            raise SystemExit("E8 ingest did not reject wrong expected source head")

        completed_path = packet_root / "completed-E8.jsonl"
        original = completed_path.read_text(encoding="utf-8")
        tampered = [json.loads(line) for line in original.splitlines() if line.strip()]
        tampered[0]["expected_play_category"] = "tampered category"
        completed_path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in tampered), encoding="utf-8")
        mismatch = run([
            sys.executable, str(INGEST),
            "--packet", str(packet_root),
            "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root),
        ], expect_ok=False)
        if "does not exactly match" not in (mismatch.stderr + mismatch.stdout):
            raise SystemExit("E8 ingest did not reject completed-row tampering")

    print("Phase 12G E8 ingest audit: PASS — exact source pin + frozen assets + finalized respondent equality + dry-run + explicit append + idempotency; synthetic audit data never touched repository evidence")


if __name__ == "__main__":
    main()
