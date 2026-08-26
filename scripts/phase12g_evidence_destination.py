#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CANONICAL_EVIDENCE_ROOT = (ROOT / "empirical/evidence").resolve()
CANONICAL_CONTROL_FILES = {
    "dispositions": (CANONICAL_EVIDENCE_ROOT / "dispositions.json").resolve(),
    "sample_adequacy": (CANONICAL_EVIDENCE_ROOT / "sample_adequacy.json").resolve(),
}


def resolve_evidence_root(requested: Path, *, append: bool) -> Path:
    """Resolve a caller-supplied evidence root and fail closed for real appends.

    Alternate roots remain useful for dry-run validation and audit isolation, but a
    deliberate empirical append must always target the repository's canonical
    append-only evidence directory. This prevents a caller-controlled destination
    from crossing the final ingest trust boundary.
    """
    resolved = requested.resolve()
    if append and resolved != CANONICAL_EVIDENCE_ROOT:
        raise ValueError(
            "append evidence destination must be the canonical repository root "
            f"{CANONICAL_EVIDENCE_ROOT}; got {resolved}"
        )
    return resolved


def resolve_control_path(evidence_root: Path, requested: Path, *, control_kind: str) -> Path:
    """Bind production disposition/adequacy consumption to canonical evidence bytes.

    Synthetic and dry-run roots may keep caller-selected sidecar files for isolated
    audits. Once the canonical repository evidence root is selected, however, the
    disposition and representative-sample controls must come from their canonical
    sibling files under that exact root. Otherwise a caller could review real
    evidence bytes into an alternate control file and ask the harness to consume
    that different decision without changing the repository's reviewed state.
    """
    root = evidence_root.resolve()
    resolved = requested.resolve()
    if control_kind not in CANONICAL_CONTROL_FILES:
        raise ValueError(f"unknown Phase 12G control kind: {control_kind}")
    canonical = CANONICAL_CONTROL_FILES[control_kind]
    if root == CANONICAL_EVIDENCE_ROOT and resolved != canonical:
        raise ValueError(
            f"canonical evidence root requires canonical {control_kind} control file "
            f"{canonical}; got {resolved}"
        )
    return resolved
