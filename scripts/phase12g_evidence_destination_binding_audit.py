#!/usr/bin/env python3
from __future__ import annotations

import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"

import sys
sys.path.insert(0, str(SCRIPT_DIR))
import phase12g_evidence_destination as destination  # noqa: E402


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G EVIDENCE DESTINATION FAIL: {message}")


def require(path: Path, markers: list[str], label: str) -> str:
    text = path.read_text(encoding="utf-8")
    missing = [marker for marker in markers if marker not in text]
    if missing:
        fail(f"{label} missing destination-boundary markers: {missing}")
    return text


def main() -> None:
    canonical = (ROOT / "empirical/evidence").resolve()
    if destination.CANONICAL_EVIDENCE_ROOT != canonical:
        fail("shared canonical evidence root does not resolve to empirical/evidence")
    if destination.resolve_evidence_root(canonical, append=True) != canonical:
        fail("canonical append destination was not accepted")

    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-evidence-destination-") as raw:
        alternate = Path(raw) / "evidence"
        if destination.resolve_evidence_root(alternate, append=False) != alternate.resolve():
            fail("alternate dry-run evidence root must remain available for isolated validation")
        try:
            destination.resolve_evidence_root(alternate, append=True)
        except ValueError as exc:
            if "canonical repository root" not in str(exc):
                fail(f"alternate append rejection was not explicit: {exc}")
        else:
            fail("alternate append evidence root was accepted")

    collector = require(
        SCRIPT_DIR / "phase12g_collect_completed_rows.py",
        [
            "from phase12g_evidence_destination import resolve_evidence_root",
            "resolve_evidence_root(args.evidence_root, append=args.append)",
            "evidence destination rejected",
        ],
        "central collector",
    )
    if "evidence_root = args.evidence_root.resolve()" in collector:
        fail("central collector still resolves caller destination without the shared append guard")

    reference_ingest = require(
        SCRIPT_DIR / "phase12g_reference_profile_ingest.py",
        [
            "import phase12g_evidence_destination as evidence_destination",
            "evidence_destination.resolve_evidence_root(args.evidence_root, append=args.append)",
            '"--evidence-root", str(evidence_root)',
        ],
        "T8 reference ingest",
    )
    if '"--evidence-root", str(args.evidence_root)' in reference_ingest:
        fail("T8 collector still receives unvalidated caller evidence root")

    field_audit = require(
        SCRIPT_DIR / "phase12g_field_kit_ingest_audit.py",
        [
            "alternate evidence roots must remain valid for isolated dry-run validation",
            "real field-kit append must reject a caller-controlled noncanonical evidence root",
            "append evidence destination must be the canonical repository root",
        ],
        "human field-kit ingest audit",
    )
    if "explicit append must write exactly one validated" in field_audit:
        fail("human field-kit audit still expects production append to an isolated noncanonical root")

    e8_audit = require(
        SCRIPT_DIR / "phase12g_marketing_expectation_ingest_audit.py",
        [
            "E8 real append must reject a caller-controlled noncanonical evidence root",
            "append evidence destination must be the canonical repository root",
            "assert_no_evidence(evidence_root)",
        ],
        "E8 marketing ingest audit",
    )
    if "E8 append did not produce exactly two validated rows" in e8_audit:
        fail("E8 audit still expects production append to an isolated noncanonical root")

    print(
        "Phase 12G evidence destination binding audit: PASS — shared collector append is canonical-root-only for human/E8/T8; "
        "alternate roots remain dry-run-only and synthetic audits prove rejection without repository evidence mutation"
    )


if __name__ == "__main__":
    main()
