#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import phase12g_e8_acquisition_build_bind as e8_build_binding

RECEIPT_SCHEMA = "fmd.phase12g.e8.completion-receipt.v2"
RECEIPT_FILENAME = "completion-receipt.json"
FINALIZATION_BINDING_SCOPE = "finalization_snapshot_only"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_sha256(payload: object) -> str:
    text = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _load_completed_rows(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        value = json.loads(raw)
        if not isinstance(value, dict):
            raise ValueError(f"completed E8 row {line_no} must be an object")
        rows.append(value)
    return rows


def finalized_outcome_snapshot(completed_path: Path) -> list[dict[str, Any]]:
    """Return declaration-only E8 outcomes in finalized row order.

    Respondent slot identity + asset_version are already frozen before observation by
    the acquisition-time respondent identity binding. This independent snapshot
    binds only the disposition-relevant observation fields after finalization. It
    does not prove the declarations came from a real or representative respondent.
    """
    snapshot: list[dict[str, Any]] = []
    for index, row in enumerate(_load_completed_rows(completed_path), start=1):
        category = row.get("expected_play_category")
        builder = row.get("freeform_builder_expectation")
        notes = row.get("notes")
        if not isinstance(category, str) or not category.strip():
            raise ValueError(f"completed E8 row {index} expected_play_category must be non-empty")
        if not isinstance(builder, bool):
            raise ValueError(f"completed E8 row {index} freeform_builder_expectation must be boolean")
        if not isinstance(notes, str) or not notes.strip():
            raise ValueError(f"completed E8 row {index} notes must be non-empty")
        snapshot.append({
            "expected_play_category": category,
            "freeform_builder_expectation": builder,
            "notes": notes,
        })
    return snapshot


def _file_record(root: Path, path: Path) -> dict[str, Any]:
    resolved_root = root.resolve()
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(resolved_root).as_posix()
    except ValueError as exc:
        raise ValueError(f"receipt file escapes E8 packet: {path}") from exc
    return {
        "path": relative,
        "sha256": sha256(resolved),
        "bytes": resolved.stat().st_size,
    }


def _binding_receipt(root: Path, asset_set: dict[str, Any], respondents: dict[str, Any]) -> dict[str, Any]:
    snapshot = e8_build_binding.verify_packet_binding(root, asset_set, respondents)
    return {
        "binding_id": snapshot["binding_id"],
        "artifact_sha256": snapshot["artifact_sha256"],
        "artifact_bytes": snapshot["artifact_bytes"],
        "artifact_filename": snapshot["artifact_filename"],
        "role": snapshot["role"],
        "build_id": snapshot["build_id"],
        "source_head": snapshot["source_head"],
    }


def _finalization_binding(completed_path: Path) -> dict[str, Any]:
    snapshot = finalized_outcome_snapshot(completed_path)
    if not snapshot:
        raise ValueError("cannot finalize E8 declaration binding without completed respondent rows")
    return {
        "outcome_sha256": canonical_sha256(snapshot),
        "row_count": len(snapshot),
        "binding_scope": FINALIZATION_BINDING_SCOPE,
        "declaration_only": True,
        "proves_human_truth_or_representativeness": False,
    }


def write_receipt(root: Path, asset_set: dict[str, Any], respondents: dict[str, Any], completed_path: Path) -> Path:
    root = root.resolve()
    asset_path = root / "asset-set.json"
    respondents_path = root / "respondents.json"
    for path in (asset_path, respondents_path, completed_path):
        if not path.is_file():
            raise ValueError(f"cannot finalize E8 receipt; missing file: {path.name}")
    binding = _binding_receipt(root, asset_set, respondents)
    finalization_binding = _finalization_binding(completed_path)

    receipt = {
        "schema": RECEIPT_SCHEMA,
        "gate_id": "E8",
        "asset_version": str(asset_set.get("asset_version", "")),
        "build_id": str(asset_set.get("build_id", "")),
        "source_head": str(asset_set.get("source_head", "")),
        "respondent_count": len(respondents.get("rows", [])),
        "asset_set": _file_record(root, asset_path),
        "respondents": _file_record(root, respondents_path),
        "completed_rows": _file_record(root, completed_path),
        "acquisition_build_binding": binding,
        "finalized_outcome_binding": finalization_binding,
        "acquisition_build_bytes_verified": True,
        "human_outcomes_inferred": False,
        "repository_evidence_appended": False,
        "evidence_boundary": "Digest receipt binds the finalized respondent return to the exact immutable E8 assets/source/build and frozen production package bytes. The independent declaration-only outcome snapshot binds finalized answer fields but does not prove human truth, representativeness, market expectation or an E8 disposition.",
    }
    receipt_path = root / RECEIPT_FILENAME
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return receipt_path


def verify_receipt(root: Path, asset_set: dict[str, Any], respondents: dict[str, Any], completed_path: Path) -> dict[str, Any]:
    root = root.resolve()
    receipt_path = root / RECEIPT_FILENAME
    if not receipt_path.is_file():
        return {"ok": False, "code": "e8_completion_receipt_missing"}
    try:
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return {"ok": False, "code": "e8_completion_receipt_unreadable", "detail": str(exc)}
    if not isinstance(receipt, dict) or receipt.get("schema") != RECEIPT_SCHEMA or receipt.get("gate_id") != "E8":
        return {"ok": False, "code": "e8_completion_receipt_schema_invalid"}

    expected_identity = {
        "asset_version": str(asset_set.get("asset_version", "")),
        "build_id": str(asset_set.get("build_id", "")),
        "source_head": str(asset_set.get("source_head", "")),
        "respondent_count": len(respondents.get("rows", [])),
    }
    for key, expected in expected_identity.items():
        if receipt.get(key) != expected:
            return {"ok": False, "code": "e8_completion_receipt_identity_mismatch", "field": key}

    expected_paths = {
        "asset_set": root / "asset-set.json",
        "respondents": root / "respondents.json",
        "completed_rows": completed_path,
    }
    for key, path in expected_paths.items():
        record = receipt.get(key)
        if not isinstance(record, dict):
            return {"ok": False, "code": "e8_completion_receipt_file_record_missing", "field": key}
        try:
            expected_record = _file_record(root, path)
        except (OSError, ValueError) as exc:
            return {"ok": False, "code": "e8_completion_receipt_target_unreadable", "field": key, "detail": str(exc)}
        if record != expected_record:
            return {"ok": False, "code": "e8_completion_receipt_digest_mismatch", "field": key}

    try:
        binding = _binding_receipt(root, asset_set, respondents)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return {"ok": False, "code": "e8_completion_receipt_build_binding_invalid", "detail": str(exc)}
    if receipt.get("acquisition_build_binding") != binding:
        return {"ok": False, "code": "e8_completion_receipt_build_binding_mismatch"}

    try:
        finalization_binding = _finalization_binding(completed_path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return {"ok": False, "code": "e8_finalized_outcome_binding_unreadable", "detail": str(exc)}
    stored_finalization = receipt.get("finalized_outcome_binding")
    if not isinstance(stored_finalization, dict):
        return {"ok": False, "code": "e8_finalized_outcome_binding_missing"}
    if stored_finalization != finalization_binding:
        return {"ok": False, "code": "e8_finalized_outcome_binding_mismatch"}
    if stored_finalization.get("binding_scope") != FINALIZATION_BINDING_SCOPE:
        return {"ok": False, "code": "e8_finalized_outcome_binding_scope_invalid"}
    if stored_finalization.get("declaration_only") is not True or stored_finalization.get("proves_human_truth_or_representativeness") is not False:
        return {"ok": False, "code": "e8_finalized_outcome_boundary_invalid"}

    if receipt.get("acquisition_build_bytes_verified") is not True:
        return {"ok": False, "code": "e8_completion_receipt_build_boundary_invalid"}
    if receipt.get("human_outcomes_inferred") is not False or receipt.get("repository_evidence_appended") is not False:
        return {"ok": False, "code": "e8_completion_receipt_boundary_invalid"}
    return {
        "ok": True,
        "receipt_path": receipt_path.as_posix(),
        "receipt_sha256": sha256(receipt_path),
        "schema": RECEIPT_SCHEMA,
        "build_binding_id": binding["binding_id"],
        "artifact_sha256": binding["artifact_sha256"],
        "artifact_bytes": binding["artifact_bytes"],
        "finalized_outcome_sha256": finalization_binding["outcome_sha256"],
        "finalized_outcome_row_count": finalization_binding["row_count"],
        "finalization_binding_scope": FINALIZATION_BINDING_SCOPE,
        "declaration_only": True,
        "proves_human_truth_or_representativeness": False,
    }
