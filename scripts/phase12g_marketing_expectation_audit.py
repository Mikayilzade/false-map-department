#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/phase12g_marketing_expectation_packet.py"
AUDIT_HEAD = "0123456789abcdef0123456789abcdef01234567"


def run(*args: str, expect_ok: bool = True) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run([sys.executable, str(SCRIPT), *args], text=True, capture_output=True)
    if expect_ok and proc.returncode != 0:
        raise SystemExit(f"E8 audit command failed: {' '.join(args)}\n{proc.stdout}\n{proc.stderr}")
    if not expect_ok and proc.returncode == 0:
        raise SystemExit(f"E8 audit expected rejection but command passed: {' '.join(args)}")
    return proc


def prepare_packet(tmp: Path, assets: dict[str, Path], name: str = "packet") -> Path:
    packet = tmp / name
    common = [
        "prepare",
        "--asset-version", "E8-AUDIT-V2",
        "--build-id", "AUDIT-BUILD",
        "--source-head", AUDIT_HEAD,
        "--representative-attestation",
        "--respondents", "3",
        "--output", str(packet),
    ]
    for role, path in assets.items():
        common += ["--asset", f"{role}={path}"]
    run(*common)
    return packet


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-e8-audit-") as raw_tmp:
        tmp = Path(raw_tmp)
        assets: dict[str, Path] = {}
        for role, suffix in (
            ("store_key_art", ".png"),
            ("gameplay_map_world", ".png"),
            ("gameplay_consequence", ".png"),
            ("late_game_linked", ".png"),
            ("trailer", ".webm"),
        ):
            path = tmp / f"{role}{suffix}"
            path.write_bytes((f"AUDIT-ONLY-{role}\n").encode("utf-8"))
            assets[role] = path

        packet = prepare_packet(tmp, assets)
        asset_set = json.loads((packet / "asset-set.json").read_text(encoding="utf-8"))
        respondents = json.loads((packet / "respondents.json").read_text(encoding="utf-8"))
        roles = [item["role"] for item in asset_set["assets"]]
        expected_roles = ["store_key_art", "gameplay_map_world", "gameplay_consequence", "late_game_linked", "trailer"]
        if roles != expected_roles:
            raise SystemExit(f"E8 asset roles must be exact and ordered: {roles}")
        if asset_set.get("schema") != "fmd.phase12g.e8.asset-set.v2":
            raise SystemExit("E8 packet must use immutable asset-set v2 schema")
        if asset_set.get("source_head") != AUDIT_HEAD or respondents.get("source_head") != AUDIT_HEAD:
            raise SystemExit("E8 packet must pin exact source-head provenance")
        if not asset_set.get("representative_asset_attestation"):
            raise SystemExit("E8 prepared asset set must record explicit representative attestation")
        if "not a freeform map builder" not in " ".join(asset_set.get("claims", [])).lower():
            raise SystemExit("E8 canonical claims must explicitly reject freeform-builder expectation")
        if respondents.get("evidence_appended") is not False or respondents.get("interpretation") is not None:
            raise SystemExit("E8 preparation must not append or interpret evidence")
        for item in asset_set["assets"]:
            stored = packet / item["packet_path"]
            if not stored.is_file() or not str(item["packet_path"]).startswith("assets/"):
                raise SystemExit("E8 prepare must freeze every shown asset inside the packet")
            if stored.name == item.get("source_filename") and stored.parent == assets[item["role"]].parent:
                raise SystemExit("E8 asset record must point to packet-owned immutable copy")
        for row in respondents.get("rows", []):
            for field in ("expected_play_category", "freeform_builder_expectation", "notes"):
                if row.get(field) is not None:
                    raise SystemExit(f"E8 preparation fabricated observed field {field}")

        state = json.loads(run("status", "--packet", str(packet)).stdout)
        if state.get("status") != "PREPARED" or state.get("completed_rows") != 0 or state.get("total_rows") != 3:
            raise SystemExit(f"Unexpected blank E8 readiness state: {state}")
        if not state.get("frozen_assets_verified") or state.get("source_head") != AUDIT_HEAD:
            raise SystemExit("E8 status must reverify frozen assets and source provenance")
        run("finalize", "--packet", str(packet), expect_ok=False)
        if (packet / "completed-E8.jsonl").exists():
            raise SystemExit("Blank E8 packet must not emit completed evidence rows")

        incomplete = tmp / "incomplete"
        incomplete_args = [
            "prepare", "--asset-version", "E8-BAD", "--build-id", "AUDIT-BUILD", "--source-head", AUDIT_HEAD,
            "--representative-attestation", "--output", str(incomplete),
        ]
        for role in expected_roles[:-1]:
            incomplete_args += ["--asset", f"{role}={assets[role]}"]
        run(*incomplete_args, expect_ok=False)

        no_attestation = tmp / "no-attestation"
        no_attestation_args = [
            "prepare", "--asset-version", "E8-BAD2", "--build-id", "AUDIT-BUILD", "--source-head", AUDIT_HEAD,
            "--output", str(no_attestation),
        ]
        for role, path in assets.items():
            no_attestation_args += ["--asset", f"{role}={path}"]
        run(*no_attestation_args, expect_ok=False)

        bad_head = tmp / "bad-head"
        bad_head_args = [
            "prepare", "--asset-version", "E8-BAD3", "--build-id", "AUDIT-BUILD", "--source-head", "main",
            "--representative-attestation", "--output", str(bad_head),
        ]
        for role, path in assets.items():
            bad_head_args += ["--asset", f"{role}={path}"]
        run(*bad_head_args, expect_ok=False)

        tampered = prepare_packet(tmp, assets, "tampered")
        tampered_manifest = json.loads((tampered / "asset-set.json").read_text(encoding="utf-8"))
        tampered_asset = tampered / tampered_manifest["assets"][1]["packet_path"]
        tampered_asset.write_bytes(b"CHANGED-AFTER-PREPARE\n")
        tamper_state = json.loads(run("status", "--packet", str(tampered)).stdout)
        if tamper_state.get("status") != "INVALID_PACKET" or "frozen_asset" not in str(tamper_state.get("reason", "")):
            raise SystemExit(f"E8 status must reject post-prepare asset mutation: {tamper_state}")
        run("finalize", "--packet", str(tampered), expect_ok=False)

        rows = respondents["rows"]
        for index, row in enumerate(rows):
            row["expected_play_category"] = "systemic causal puzzle"
            row["freeform_builder_expectation"] = index == 2
            row["notes"] = "Observed response recorded by audit fixture; not repository evidence."
        (packet / "respondents.json").write_text(json.dumps(respondents, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        ready = json.loads(run("status", "--packet", str(packet)).stdout)
        if ready.get("status") != "READY_TO_FINALIZE" or not ready.get("frozen_assets_verified"):
            raise SystemExit(f"Completed E8 observer fixture must be ready only with intact assets: {ready}")
        run("finalize", "--packet", str(packet))
        completed = (packet / "completed-E8.jsonl").read_text(encoding="utf-8").strip().splitlines()
        if len(completed) != 3:
            raise SystemExit("E8 finalizer must emit one local row per actual completed respondent row")

    print("Phase 12G E8 marketing-acquisition audit: PASS (packet-owned immutable assets + exact source head + re-hash tamper rejection + blank-human anti-fabrication + local-only finalization)")


if __name__ == "__main__":
    main()
