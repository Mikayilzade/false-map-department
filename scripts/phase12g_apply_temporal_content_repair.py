#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGETS = {
    "D38": 0,
    "D39": 0,
}


def canonical_bytes(payload: dict) -> bytes:
    return json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def repair(dossier_id: str, reaction_beats: int) -> bool:
    path = ROOT / "content" / "campaign" / f"{dossier_id}.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("dossier_id") != dossier_id:
        raise SystemExit(f"identity mismatch in {path}")

    current = payload.get("reaction_beats_after_edit")
    if current == reaction_beats:
        body = dict(payload)
        declared = body.pop("content_hash", "")
        expected = hashlib.sha256(canonical_bytes(body)).hexdigest()
        if declared != expected:
            raise SystemExit(f"{dossier_id} already has target pacing but content_hash is stale")
        print(f"{dossier_id}: already repaired")
        return False

    if dossier_id == "D38" and current != 4:
        raise SystemExit(f"D38 expected pre-repair reaction beats 4, got {current!r}")
    if dossier_id == "D39" and current != 5:
        raise SystemExit(f"D39 expected pre-repair reaction beats 5, got {current!r}")

    payload["reaction_beats_after_edit"] = reaction_beats
    body = dict(payload)
    body.pop("content_hash", None)
    payload["content_hash"] = hashlib.sha256(canonical_bytes(body)).hexdigest()
    path.write_bytes(canonical_bytes(payload) + b"\n")
    print(f"{dossier_id}: reaction_beats_after_edit {current} -> {reaction_beats}; hash recomputed")
    return True


def main() -> None:
    changed = False
    for dossier_id, reaction_beats in TARGETS.items():
        changed = repair(dossier_id, reaction_beats) or changed
    print("changed=yes" if changed else "changed=no")


if __name__ == "__main__":
    main()
