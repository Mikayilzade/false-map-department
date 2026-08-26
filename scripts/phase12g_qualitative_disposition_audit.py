#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RECORDER = ROOT / "scripts/phase12g_qualitative_disposition.py"
INTEGRITY = ROOT / "scripts/phase12g_qualitative_disposition_integrity.py"
HARNESS = ROOT / "scripts/phase12g_evidence_harness.py"
DASHBOARD = ROOT / "scripts/phase12g_gate_dashboard.py"
CANONICAL_EVIDENCE_ROOT = ROOT / "empirical/evidence"


def run(args: list[str], *, expect_ok: bool = True) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if expect_ok and completed.returncode != 0:
        raise SystemExit(f"command failed: {' '.join(args)}\nSTDOUT:\n{completed.stdout}\nSTDERR:\n{completed.stderr}")
    if not expect_ok and completed.returncode == 0:
        raise SystemExit(f"command unexpectedly passed: {' '.join(args)}")
    return completed


def require_control_rejection(completed: subprocess.CompletedProcess[str], control_kind: str) -> None:
    rendered = (completed.stdout + completed.stderr).lower().replace("_", " ")
    if "canonical" not in rendered or control_kind.replace("_", " ") not in rendered:
        raise SystemExit(
            f"redirected canonical {control_kind} control must fail with an explicit routing error; got:\n{rendered}"
        )


def harness_payload(root: Path) -> dict:
    result = run([sys.executable, str(HARNESS), "--evidence-root", str(root)])
    return json.loads(result.stdout)


def harness_gate(root: Path, gate_id: str) -> dict:
    payload = harness_payload(root)
    for gate in payload["gates"]:
        if gate["gate_id"] == gate_id:
            return gate
    raise SystemExit(f"missing {gate_id} in harness output")


def harness_status(root: Path, gate_id: str) -> str:
    return str(harness_gate(root, gate_id)["status"])


def write_e8(path: Path, respondent_id: str, builder: bool) -> None:
    row = {
        "gate_id": "E8",
        "respondent_id": respondent_id,
        "asset_version": "SYNTHETIC-AUDIT-ASSET",
        "expected_play_category": "civic puzzle",
        "freeform_builder_expectation": builder,
        "notes": "synthetic audit row; never repository evidence",
    }
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, sort_keys=True) + "\n")


def test_canonical_control_routing(temp_root: Path) -> None:
    redirected_dispositions = temp_root / "redirected-dispositions.json"
    redirected_adequacy = temp_root / "redirected-sample-adequacy.json"

    # The raw harness is a disposition consumer. Canonical evidence may never be
    # paired with an alternate decision file, even if that alternate file could be
    # made byte-consistent with the repository evidence.
    disposition_harness = run(
        [
            sys.executable,
            str(HARNESS),
            "--evidence-root", str(CANONICAL_EVIDENCE_ROOT),
            "--dispositions", str(redirected_dispositions),
        ],
        expect_ok=False,
    )
    require_control_rejection(disposition_harness, "dispositions")

    # E1/E2 representative-sample eligibility is also gate-controlling state. A
    # caller-selected adequacy file must not be able to qualify canonical rows.
    adequacy_harness = run(
        [
            sys.executable,
            str(HARNESS),
            "--evidence-root", str(CANONICAL_EVIDENCE_ROOT),
            "--sample-adequacy", str(redirected_adequacy),
        ],
        expect_ok=False,
    )
    require_control_rejection(adequacy_harness, "sample adequacy")

    # Standalone integrity must reject the same redirect instead of blessing an
    # alternate review document against canonical evidence bytes.
    integrity_redirect = run(
        [
            sys.executable,
            str(INTEGRITY),
            "--evidence-root", str(CANONICAL_EVIDENCE_ROOT),
            "--dispositions", str(redirected_dispositions),
        ],
        expect_ok=False,
    )
    require_control_rejection(integrity_redirect, "dispositions")

    # The recorder must reject the alternate production destination before it can
    # read or mutate empirical state. E8 may currently be empty; routing ownership
    # is deliberately checked before evidence presence.
    recorder_redirect = run(
        [
            sys.executable,
            str(RECORDER),
            "E8",
            "--status", "PASS",
            "--rationale", "Synthetic routing probe only; must never be recorded.",
            "--evidence-ref", "synthetic:routing-probe",
            "--reviewer-id", "SYNTHETIC_ROUTING_PROBE",
            "--evidence-root", str(CANONICAL_EVIDENCE_ROOT),
            "--output", str(redirected_dispositions),
        ],
        expect_ok=False,
    )
    require_control_rejection(recorder_redirect, "dispositions")
    if redirected_dispositions.exists() or redirected_adequacy.exists():
        raise SystemExit("canonical control-routing rejection must not create redirected control files")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-disposition-audit-") as temp:
        root = Path(temp)
        test_canonical_control_routing(root)

        evidence = root / "E8.jsonl"
        dispositions = root / "dispositions.json"
        dashboard = root / "dashboard.md"
        write_e8(evidence, "SYNTHETIC_R1", False)

        # Noncanonical roots remain intentionally usable for isolated synthetic
        # audits; the production-path guard must not destroy this test surface.
        if harness_status(root, "E8") != "PENDING":
            raise SystemExit("E8 with rows but no explicit disposition must remain PENDING")

        run([
            sys.executable,
            str(RECORDER),
            "E8",
            "--status", "PASS",
            "--rationale", "Synthetic explicit interpretation for provenance audit only.",
            "--evidence-ref", "synthetic:E8.jsonl",
            "--reviewer-id", "SYNTHETIC_REVIEWER",
            "--evidence-root", str(root),
            "--output", str(dispositions),
        ])
        run([sys.executable, str(INTEGRITY), "--evidence-root", str(root), "--dispositions", str(dispositions)])
        if harness_status(root, "E8") != "PASS":
            raise SystemExit("explicit disposition should become visible to the harness only after rows exist")
        current_payload = harness_payload(root)
        if not current_payload.get("qualitative_disposition_integrity", {}).get("ok", False):
            raise SystemExit("raw harness must expose current qualitative-disposition integrity state")
        run([sys.executable, str(DASHBOARD), "--evidence-root", str(root), "--output", str(dashboard)])
        if "E8 — marketing expectation | PASS" not in dashboard.read_text(encoding="utf-8"):
            raise SystemExit("dashboard must show the current exact-byte qualitative disposition")

        # Recorder is write-once by default: a changed/reconsidered interpretation must be deliberate.
        run([
            sys.executable, str(RECORDER), "E8",
            "--status", "FAIL",
            "--rationale", "Should not overwrite without explicit replacement.",
            "--evidence-ref", "synthetic:E8.jsonl",
            "--reviewer-id", "SYNTHETIC_REVIEWER",
            "--evidence-root", str(root),
            "--output", str(dispositions),
        ], expect_ok=False)

        # Appending evidence invalidates the recorded interpretation until the new bytes are re-reviewed.
        write_e8(evidence, "SYNTHETIC_R2", True)
        stale = run([sys.executable, str(INTEGRITY), "--evidence-root", str(root), "--dispositions", str(dispositions)], expect_ok=False)
        if "stale" not in (stale.stdout + stale.stderr).lower():
            raise SystemExit("post-disposition evidence mutation must fail explicitly as stale")

        # The raw harness itself must now fail closed: stale reviewed evidence may
        # not surface the previously recorded PASS even when the operator skips
        # the standalone integrity command.
        stale_payload = harness_payload(root)
        stale_gate = next(gate for gate in stale_payload["gates"] if gate["gate_id"] == "E8")
        if stale_gate["status"] != "PENDING":
            raise SystemExit("raw harness must downgrade stale qualitative disposition to PENDING")
        integrity_state = stale_payload.get("qualitative_disposition_integrity", {})
        if integrity_state.get("ok", True) or "stale" not in str(integrity_state.get("reason", "")).lower():
            raise SystemExit("raw harness must expose the stale exact-byte integrity reason")
        if "integrity" not in str(stale_gate.get("detail", {}).get("reason", "")).lower():
            raise SystemExit("raw harness qualitative gate detail must explain fail-closed integrity handling")

        # The standalone operator dashboard must enforce the same exact-byte
        # review binding and fail closed until deliberate re-review occurs.
        stale_dashboard = run(
            [sys.executable, str(DASHBOARD), "--evidence-root", str(root), "--output", str(dashboard)],
            expect_ok=False,
        )
        if "stale" not in (stale_dashboard.stdout + stale_dashboard.stderr).lower():
            raise SystemExit("dashboard must fail closed with an explicit stale-disposition error")

        run([
            sys.executable, str(RECORDER), "E8",
            "--status", "FAIL",
            "--rationale", "Synthetic re-review after evidence changed.",
            "--evidence-ref", "synthetic:E8.jsonl",
            "--reviewer-id", "SYNTHETIC_REVIEWER",
            "--evidence-root", str(root),
            "--output", str(dispositions),
            "--replace",
        ])
        run([sys.executable, str(INTEGRITY), "--evidence-root", str(root), "--dispositions", str(dispositions)])
        if harness_status(root, "E8") != "FAIL":
            raise SystemExit("deliberately replaced disposition must reflect the newly reviewed evidence batch")
        recovered_payload = harness_payload(root)
        if not recovered_payload.get("qualitative_disposition_integrity", {}).get("ok", False):
            raise SystemExit("raw harness integrity state must recover after deliberate exact-byte re-review")
        run([sys.executable, str(DASHBOARD), "--evidence-root", str(root), "--output", str(dashboard)])
        if "E8 — marketing expectation | FAIL" not in dashboard.read_text(encoding="utf-8"):
            raise SystemExit("dashboard must recover only after current evidence is deliberately re-reviewed")

        # Threshold gates may never be manually dispositioned through this path.
        e7 = root / "E7.jsonl"
        e7.write_text('{"gate_id":"E7"}\n', encoding="utf-8")
        run([
            sys.executable, str(RECORDER), "E7",
            "--status", "PASS",
            "--rationale", "forbidden",
            "--evidence-ref", "synthetic:E7.jsonl",
            "--reviewer-id", "SYNTHETIC_REVIEWER",
            "--evidence-root", str(root),
            "--output", str(dispositions),
        ], expect_ok=False)

    print("Phase 12G qualitative disposition audit: PASS (canonical control-path binding + explicit review + exact evidence digest/row binding + raw-harness/dashboard stale rejection + deliberate replacement + threshold-gate guard)")


if __name__ == "__main__":
    main()
