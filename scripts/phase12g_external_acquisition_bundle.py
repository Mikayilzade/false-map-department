#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import tarfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
SHA40 = 40
BUNDLE_SCHEMA = "fmd.phase12g.external-acquisition-bundle.v2"

REQUIRED_PATHS = (
    "IMPLEMENTATION_START_HERE.md",
    "CI_NOTIFICATION_POLICY.md",
    "GAME2_PHASE11_FINAL_FREEZE.md",
    "empirical/PHASE12G_PROTOCOL.md",
    "empirical/phase12g_gate_registry.json",
    "empirical/phase12g_session_protocols.json",
    "scripts/fetch_pinned_godot.sh",
    "scripts/phase12g_human_field_kit.py",
    "scripts/phase12g_field_kit_offline_verify.py",
    "scripts/phase12g_field_kit_offline_finalize.py",
    "scripts/phase12g_field_kit_ingest.py",
    "scripts/phase12g_marketing_expectation_packet.py",
    "scripts/phase12g_marketing_expectation_ingest.py",
    "scripts/phase12g_reference_profile_ingest.py",
    "tests/phase12g_reference_profile_runner.gd",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_output(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def exact_head() -> str:
    return git_output("rev-parse", "HEAD")


def validate_source_head(value: str) -> str:
    value = value.strip().lower()
    if len(value) != SHA40 or any(ch not in "0123456789abcdef" for ch in value):
        raise SystemExit("source-head must be an exact 40-character lowercase Git commit SHA")
    current = exact_head()
    if current != value:
        raise SystemExit(f"source-head mismatch: requested {value}, checkout is {current}")
    return value


def ensure_required_paths() -> None:
    missing = [path for path in REQUIRED_PATHS if not (ROOT / path).is_file()]
    if missing:
        raise SystemExit(f"required acquisition path(s) missing: {missing}")


def write_operator_guide(path: Path, source_head: str) -> None:
    path.write_text(
        "\n".join([
            "# False Map Department — Phase 12G external acquisition bundle",
            "",
            f"Exact source commit: `{source_head}`",
            "",
            "This bundle is acquisition material only. It does not contain or imply new human, market, or reference-hardware evidence.",
            "Keep every unobserved gate PENDING until a genuine observation is deliberately ingested and re-evaluated.",
            "",
            "## Verify first",
            "Run `python3 BUNDLE-VERIFY.py .` from the bundle root before extracting the source archive. Stop if verification fails; the verifier checks file hashes plus the tar member/root/path/symlink contract.",
            "",
            "## Human field kit (E1-E6, E9-E11)",
            "Use the verified archived repository at this exact source commit. Prepare the v4 field kit with `scripts/phase12g_human_field_kit.py`, transport it intact, verify with the bundled field-kit verifier, collect genuine observations, and finalize locally before repository ingest.",
            "",
            "## Marketing expectation (E8)",
            "Do not prepare E8 until all five representative asset roles exist: store_key_art, gameplay_map_world, gameplay_consequence, late_game_linked, trailer. Use `scripts/phase12g_marketing_expectation_packet.py` with this exact source SHA; respondent fields remain blank until real respondents observe the immutable asset set.",
            "",
            "## Deck-class performance (T8-44)",
            "Run Godot 4.7.1 on actual Deck-class reference hardware against this exact source commit. Use `tests/phase12g_reference_profile_runner.gd` with `FMD_T8_DISPOSITION=reference_run` and `FMD_T8_REFERENCE_ATTESTATION=actual_deck_class_reference`. Hosted CI and diagnostic timings are non-evidence.",
            "",
            "## Return / ingest boundary",
            "All ingest tools default to dry-run. Verify exact source equality first, then use explicit append only for genuine completed observations. Run the evidence harness/dashboard after deliberate append. Nothing in this bundle marks a gate PASS or FAIL by itself.",
            "",
        ]) + "\n",
        encoding="utf-8",
    )


def write_bundle_verifier(path: Path) -> None:
    source = (ROOT / "scripts" / "phase12g_external_acquisition_bundle_verify.py").read_text(encoding="utf-8")
    path.write_text(source, encoding="utf-8")


def create_source_archive(target: Path, source_head: str) -> None:
    subprocess.run(
        ["git", "archive", "--format=tar.gz", f"--prefix=false-map-department-{source_head[:12]}/", "-o", str(target), source_head],
        cwd=ROOT,
        check=True,
    )


def member_is_within_root(name: str, archive_root: str) -> bool:
    return name == archive_root.rstrip("/") or name.startswith(archive_root)


def inspect_source_archive(path: Path, archive_root: str) -> dict:
    required_members = {archive_root + rel for rel in REQUIRED_PATHS}
    seen: set[str] = set()
    member_count = 0
    with tarfile.open(path, "r:gz") as archive:
        for member in archive.getmembers():
            member_count += 1
            name = member.name
            pure = PurePosixPath(name)
            if pure.is_absolute() or ".." in pure.parts or not member_is_within_root(name, archive_root):
                raise SystemExit(f"unsafe archive member path: {name}")
            if member.issym() or member.islnk():
                raise SystemExit(f"archive links are forbidden in acquisition bundle: {name}")
            if member.isfile():
                seen.add(name)
    missing = sorted(required_members - seen)
    if missing:
        raise SystemExit(f"source archive missing required acquisition member(s): {missing}")
    return {
        "archive_root": archive_root,
        "member_count": member_count,
        "required_regular_files": list(REQUIRED_PATHS),
        "forbid_links": True,
        "forbid_absolute_or_parent_paths": True,
    }


def build(args: argparse.Namespace) -> None:
    source_head = validate_source_head(args.source_head)
    ensure_required_paths()
    out = Path(args.output).resolve()
    if out.exists() and any(out.iterdir()):
        raise SystemExit("refusing to overwrite a non-empty external acquisition bundle directory")
    out.mkdir(parents=True, exist_ok=True)

    archive_root = f"false-map-department-{source_head[:12]}/"
    archive_name = f"false-map-department-source-{source_head[:12]}.tar.gz"
    archive_path = out / archive_name
    create_source_archive(archive_path, source_head)
    archive_contract = inspect_source_archive(archive_path, archive_root)
    guide_path = out / "OPERATOR-GUIDE.md"
    write_operator_guide(guide_path, source_head)
    verifier_path = out / "BUNDLE-VERIFY.py"
    write_bundle_verifier(verifier_path)
    (out / "SOURCE_HEAD.txt").write_text(source_head + "\n", encoding="utf-8")

    files = []
    for path in sorted(p for p in out.iterdir() if p.name != "bundle-manifest.json"):
        if path.is_file():
            files.append({"path": path.name, "sha256": sha256(path), "bytes": path.stat().st_size})
    manifest = {
        "schema": BUNDLE_SCHEMA,
        "phase": "12G",
        "source_head": source_head,
        "archive_contract": archive_contract,
        "files": files,
        "evidence_appended": False,
        "gate_dispositions_changed": False,
        "evidence_boundary": "Portable acquisition material only; no human, market, accessibility-review or Deck-class empirical outcome is inferred by bundle creation or verification.",
    }
    (out / "bundle-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "source_head": source_head, "output": str(out), "file_count": len(files), "archive_member_count": archive_contract["member_count"]}, sort_keys=True))


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a portable exact-source Phase 12G external acquisition bundle without creating empirical evidence")
    parser.add_argument("--source-head", required=True)
    parser.add_argument("--output", required=True)
    build(parser.parse_args())


if __name__ == "__main__":
    main()
