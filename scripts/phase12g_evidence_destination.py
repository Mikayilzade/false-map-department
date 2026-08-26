#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CANONICAL_EVIDENCE_ROOT = (ROOT / "empirical/evidence").resolve()


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
