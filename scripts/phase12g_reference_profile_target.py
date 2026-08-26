#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CAMPAIGN_ROOT = ROOT / "content/campaign"
DOSSIER_ID = re.compile(r"^D[0-9]{2}$")


def validate_reference_target(dossier_id: str) -> dict[str, Any]:
    """Validate that one T8-44 row names representative late-game content.

    T8-44 records one dossier_id for typical-edit, late-game-edit and Stability
    sample families.  Therefore the named dossier must itself be canonical Act V
    content that actually contains a justified multi-cycle Stability window.
    This is an acquisition-integrity rule, not a new performance threshold.
    """
    dossier_id = dossier_id.strip()
    if not DOSSIER_ID.fullmatch(dossier_id):
        raise ValueError("T8-44 dossier_id must be a canonical campaign dossier ID")

    path = CAMPAIGN_ROOT / f"{dossier_id}.json"
    if not path.is_file():
        raise ValueError(f"T8-44 dossier_id does not exist in canonical campaign content: {dossier_id}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"T8-44 canonical dossier unreadable: {dossier_id}: {exc}") from exc
    if not isinstance(payload, dict) or str(payload.get("dossier_id", "")) != dossier_id:
        raise ValueError(f"T8-44 canonical dossier identity mismatch: {dossier_id}")

    act_index = int(payload.get("act_index", 0))
    if act_index != 5:
        raise ValueError(f"T8-44 reference target must be representative Act V late-game content: {dossier_id}")

    stability_cycles = int(payload.get("stability_required_cycles", 0))
    if stability_cycles <= 1:
        raise ValueError(
            f"T8-44 reference target must contain a real multi-cycle Stability verification window: {dossier_id}"
        )

    validation_metadata = payload.get("validation_metadata", {})
    if not isinstance(validation_metadata, dict):
        raise ValueError(f"T8-44 canonical validation metadata malformed: {dossier_id}")
    envelope = validation_metadata.get("known_solution_envelope", {})
    if not isinstance(envelope, dict) or envelope.get("relevant_temporal_transition_observed") is not True:
        raise ValueError(
            f"T8-44 reference target must have canonical non-idle Stability transition evidence: {dossier_id}"
        )
    transitions = envelope.get("stability_transition_evidence", [])
    if not isinstance(transitions, list) or not transitions:
        raise ValueError(
            f"T8-44 reference target must declare Stability transition evidence: {dossier_id}"
        )

    return {
        "dossier_id": dossier_id,
        "act_index": act_index,
        "stability_required_cycles": stability_cycles,
        "stability_reason_tag": str(payload.get("stability_reason_tag", "")),
        "temporal_transition_count": len(transitions),
    }
