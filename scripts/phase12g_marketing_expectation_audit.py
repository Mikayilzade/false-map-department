#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"
PACKET = SCRIPT_DIR / "phase12g_marketing_expectation_packet.py"
PREPARE = SCRIPT_DIR / "phase12g_marketing_acquisition_prepare.py"
SOURCE = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip().lower()
sys.path.insert(0, str(SCRIPT_DIR))
import phase12g_audit_build_fixture as build_fixture  # noqa: E402

ROLES = (
    ("store_key_art", ".png"),
    ("gameplay_map_world", ".png"),
    ("gameplay_consequence", ".png"),
    ("late_game_linked", ".png"),
    ("trailer", ".webm"),
)


def run(command: list[str], expect_ok: bool = True) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    if expect_ok and proc.returncode != 0:
        raise SystemExit(f"E8 audit command failed: {' '.join(command)}\n{proc.stdout}\n{proc.stderr}")
    if not expect_ok and proc.returncode == 0:
        raise SystemExit(f"E8 audit expected rejection but command passed: {' '.join(command)}")
    return proc


def assets(root: Path) -> list[str]:
    root.mkdir(parents=True, exist_ok=True)
    result: list[str] = []
    for role, suffix in ROLES:
        path = root / f"{role}{suffix}"
        path.write_bytes(f"AUDIT-ONLY-{role}\n".encode())
        result += ["--asset", f"{role}={path}"]
    return result


def low_prepare(root: Path, asset_args: list[str]) -> None:
    run([
        sys.executable, str(PACKET), "prepare",
        "--asset-version", "E8-AUDIT-V3", "--build-id", "AUDIT-BUILD", "--source-head", SOURCE,
        *asset_args, "--representative-attestation", "--respondents", "3", "--output", str(root),
    ])


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-e8-audit-") as raw:
        temp = Path(raw)
        asset_args = assets(temp / "media")

        # Low-level asset preparation stays non-evidence and cannot finalize without package bytes.
        unbound = temp / "unbound"
        low_prepare(unbound, asset_args)
        asset_set = json.loads((unbound / "asset-set.json").read_text(encoding="utf-8"))
        respondents = json.loads((unbound / "respondents.json").read_text(encoding="utf-8"))
        expected_roles = [role for role, _ in ROLES]
        if [item["role"] for item in asset_set["assets"]] != expected_roles:
            raise SystemExit("E8 asset roles must be exact and ordered")
        if asset_set.get("source_head") != SOURCE or respondents.get("source_head") != SOURCE:
            raise SystemExit("E8 packet must pin exact source head")
        if respondents.get("evidence_appended") is not False or respondents.get("interpretation") is not None:
            raise SystemExit("E8 preparation must not append or interpret evidence")
        for row in respondents["rows"]:
            if any(row.get(field) is not None for field in ("expected_play_category", "freeform_builder_expectation", "notes")):
                raise SystemExit("E8 preparation fabricated human observation")
        blank_finalize = run([sys.executable, str(PACKET), "finalize", "--packet", str(unbound)], expect_ok=False)
        if (unbound / "completed-E8.jsonl").exists():
            raise SystemExit("blank/unbound E8 packet emitted completed evidence rows")

        # A filled but unbound packet also fails closed at receipt creation.
        for index, row in enumerate(respondents["rows"]):
            row.update({"expected_play_category": "systemic puzzle", "freeform_builder_expectation": False, "notes": f"audit row {index}"})
        (unbound / "respondents.json").write_text(json.dumps(respondents, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        unbound_finalize = run([sys.executable, str(PACKET), "finalize", "--packet", str(unbound)], expect_ok=False)
        if "NOT APPEND READY" not in (unbound_finalize.stdout + unbound_finalize.stderr):
            raise SystemExit("filled E8 packet without package bytes did not fail as NOT APPEND READY")
        if (unbound / "completed-E8.jsonl").exists():
            raise SystemExit("failed unbound finalization left completed rows")

        artifact, record = build_fixture.create_bound_artifact(temp / "build", source_head=SOURCE, role="production", build_id="AUDIT-BUILD")
        bound = temp / "bound"
        run([
            sys.executable, str(PREPARE),
            "--asset-version", "E8-AUDIT-BOUND", "--build-id", "AUDIT-BUILD", "--source-head", SOURCE,
            *asset_args, "--respondents", "3",
            "--production-build-artifact", str(artifact), "--production-build-artifact-record", str(record),
            "--output", str(bound),
        ])
        bound_asset = json.loads((bound / "asset-set.json").read_text(encoding="utf-8"))
        bound_rows = json.loads((bound / "respondents.json").read_text(encoding="utf-8"))
        if bound_asset.get("schema") != "fmd.phase12g.e8.asset-set.v3" or bound_rows.get("schema") != "fmd.phase12g.e8.respondent-packet.v3":
            raise SystemExit("real E8 acquisition wrapper must emit byte-bound v3 manifests")
        if bound_asset.get("acquisition_build_bytes_required") is not True:
            raise SystemExit("E8 bound manifest must require exact package bytes")
        for index, row in enumerate(bound_rows["rows"]):
            row.update({"expected_play_category": "systemic causal puzzle", "freeform_builder_expectation": index == 2, "notes": "synthetic audit only"})
        (bound / "respondents.json").write_text(json.dumps(bound_rows, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        run([sys.executable, str(PACKET), "finalize", "--packet", str(bound)])
        status = json.loads(run([sys.executable, str(PACKET), "status", "--packet", str(bound)]).stdout)
        if status.get("status") != "FINALIZED" or status.get("completion_receipt_verified") is not True:
            raise SystemExit(f"byte-bound E8 finalized state failed verification: {status}")

        tampered = temp / "tampered"
        low_prepare(tampered, assets(temp / "tamper-media"))
        tampered_manifest = json.loads((tampered / "asset-set.json").read_text(encoding="utf-8"))
        target = tampered / tampered_manifest["assets"][1]["packet_path"]
        target.write_bytes(b"CHANGED-AFTER-PREPARE\n")
        state = json.loads(run([sys.executable, str(PACKET), "status", "--packet", str(tampered)]).stdout)
        if state.get("status") != "INVALID_PACKET" or "frozen_asset" not in str(state.get("reason", "")):
            raise SystemExit("E8 status must reject post-prepare asset mutation")

    print("Phase 12G E8 marketing-acquisition audit: PASS (immutable representative assets + exact source + no fabricated observations + package-byte-bound v3 acquisition/finalization + tamper rejection)")


if __name__ == "__main__":
    main()
