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

    ingest_path = SCRIPT_DIR / "phase12g_reference_profile_ingest.py"
    ingest = ingest_path.read_text(encoding="utf-8")
    required = [
        "import phase12g_evidence_destination as evidence_destination",
        "evidence_destination.resolve_evidence_root(args.evidence_root, append=args.append)",
        '"--evidence-root", str(evidence_root)',
    ]
    missing = [marker for marker in required if marker not in ingest]
    if missing:
        fail(f"T8 reference ingest is not bound to shared destination guard: {missing}")
    if '"--evidence-root", str(args.evidence_root)' in ingest:
        fail("T8 collector still receives unvalidated caller evidence root")

    print("Phase 12G evidence destination binding audit: PASS — T8 real append is canonical-root-only while alternate dry-run roots remain isolated-test compatible")


if __name__ == "__main__":
    main()
