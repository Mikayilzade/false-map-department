#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import io
import json
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "scripts" / "phase12g_external_acquisition_bundle.py"
VERIFY = ROOT / "scripts" / "phase12g_external_acquisition_bundle_verify.py"
EVIDENCE = ROOT / "empirical" / "evidence"
EXPECTED_BINDINGS = {
    "BUNDLE-VERIFY.py": "scripts/phase12g_external_acquisition_bundle_verify.py",
    "EXTRACTED-SOURCE-VERIFY.py": "scripts/phase12g_extracted_source_verify.py",
    "FIELD-KIT-VERIFY.py": "scripts/phase12g_field_kit_offline_verify.py",
    "FIELD-KIT-FINALIZE.py": "scripts/phase12g_field_kit_offline_finalize.py",
    "RETURN-INGEST.md": "empirical/PHASE12G_RETURN_INGEST.md",
}


def digest_tree(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        digest.update(path.relative_to(root).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(command: list[str], *, expect: int = 0, cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(command, cwd=cwd, capture_output=True, text=True, check=False)
    if completed.returncode != expect:
        raise SystemExit(
            f"command returncode mismatch: expected {expect}, got {completed.returncode}\n"
            f"cmd={command}\nstdout={completed.stdout}\nstderr={completed.stderr}"
        )
    return completed


def run_rejected(command: list[str], expected_code: str, *, cwd: Path = ROOT) -> None:
    completed = subprocess.run(command, cwd=cwd, capture_output=True, text=True, check=False)
    if completed.returncode == 0 or expected_code not in completed.stdout:
        raise SystemExit(
            f"expected verifier rejection {expected_code}\ncmd={command}\n"
            f"stdout={completed.stdout}\nstderr={completed.stderr}"
        )


def verifier_command(bundle: Path, expected_head: str) -> list[str]:
    return [sys.executable, str(VERIFY), str(bundle), "--expected-source-head", expected_head]


def extracted_verifier_command(bundle: Path, extracted: Path, expected_head: str) -> list[str]:
    return [
        sys.executable,
        str(bundle / "EXTRACTED-SOURCE-VERIFY.py"),
        str(bundle),
        str(extracted),
        "--expected-source-head",
        expected_head,
    ]


def refresh_file_row(manifest_path: Path, target: Path) -> None:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for row in manifest["files"]:
        if row.get("path") == target.name:
            row["bytes"] = target.stat().st_size
            row["sha256"] = sha256(target)
            manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            return
    raise SystemExit(f"bundle file row missing for {target.name}")


def rewrite_archive_with_extra_member(archive_path: Path, member: tarfile.TarInfo, data: bytes = b"") -> None:
    rewritten = archive_path.with_suffix(".rewrite.tar.gz")
    with tarfile.open(archive_path, "r:gz") as source, tarfile.open(rewritten, "w:gz") as target:
        for existing in source.getmembers():
            fileobj = source.extractfile(existing) if existing.isfile() else None
            target.addfile(existing, fileobj)
        member.size = len(data)
        target.addfile(member, io.BytesIO(data) if data else None)
    rewritten.replace(archive_path)


def rewrite_archive_member(archive_path: Path, member_name: str, replacement: bytes) -> None:
    rewritten = archive_path.with_suffix(".rewrite.tar.gz")
    found = False
    with tarfile.open(archive_path, "r:gz") as source, tarfile.open(rewritten, "w:gz") as target:
        for existing in source.getmembers():
            if existing.name == member_name:
                found = True
                info = tarfile.TarInfo(existing.name)
                info.mode = existing.mode
                info.uid = existing.uid
                info.gid = existing.gid
                info.mtime = existing.mtime
                info.type = tarfile.REGTYPE
                info.size = len(replacement)
                target.addfile(info, io.BytesIO(replacement))
            else:
                fileobj = source.extractfile(existing) if existing.isfile() else None
                target.addfile(existing, fileobj)
    if not found:
        raise SystemExit(f"archive member not found for replacement: {member_name}")
    rewritten.replace(archive_path)


def refresh_archive_manifest(manifest_path: Path, archive_path: Path, member_delta: int = 0) -> None:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["archive_contract"]["member_count"] = int(manifest["archive_contract"]["member_count"]) + member_delta
    for row in manifest["files"]:
        if row.get("path") == archive_path.name:
            row["bytes"] = archive_path.stat().st_size
            row["sha256"] = sha256(archive_path)
            manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            return
    raise SystemExit("archive file row missing while preparing adversarial fixture")


def archive_bytes(archive_path: Path, member_name: str) -> bytes:
    with tarfile.open(archive_path, "r:gz") as archive:
        member = archive.getmember(member_name)
        handle = archive.extractfile(member)
        if handle is None:
            raise SystemExit(f"archive member unreadable: {member_name}")
        return handle.read()


def extract_verified_archive(archive_path: Path, destination: Path, expected_root: str) -> Path:
    destination.mkdir(parents=True, exist_ok=True)
    root_member = expected_root.rstrip("/")
    with tarfile.open(archive_path, "r:gz") as archive:
        for member in archive.getmembers():
            if member.name == root_member:
                if not member.isdir():
                    raise SystemExit("verified archive root member must be a directory")
                continue
            if not member.name.startswith(expected_root):
                raise SystemExit(f"verified archive member escaped expected root during test extraction: {member.name}")
            rel = member.name[len(expected_root):].rstrip("/")
            if not rel:
                continue
            target = destination / root_member / rel
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            if not member.isfile():
                raise SystemExit(f"unexpected non-file member after bundle verification: {member.name}")
            target.parent.mkdir(parents=True, exist_ok=True)
            handle = archive.extractfile(member)
            if handle is None:
                raise SystemExit(f"archive member unreadable during extraction: {member.name}")
            target.write_bytes(handle.read())
            target.chmod(0o755 if (member.mode & 0o111) else 0o644)
    return destination / root_member


def main() -> None:
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    evidence_before = digest_tree(EVIDENCE)
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-external-bundle-") as raw:
        temp = Path(raw)
        bundle = temp / "bundle"
        built = run([sys.executable, str(BUILDER), "--source-head", head, "--output", str(bundle)])
        payload = json.loads(built.stdout.strip().splitlines()[-1])
        if not payload.get("ok") or payload.get("source_head") != head:
            raise SystemExit("builder did not preserve exact current source head")
        if int(payload.get("source_binding_count", 0)) != len(EXPECTED_BINDINGS):
            raise SystemExit("builder did not emit the complete source-binding set")

        verified = run(verifier_command(bundle, head))
        verify_payload = json.loads(verified.stdout.strip().splitlines()[-1])
        expected_root = f"false-map-department-{head[:12]}/"
        if not verify_payload.get("ok") or verify_payload.get("evidence_appended") is not False:
            raise SystemExit("fresh external acquisition bundle failed offline verification/evidence boundary")
        if verify_payload.get("expected_source_head") != head:
            raise SystemExit("offline verifier did not preserve independently supplied expected source head")
        if verify_payload.get("archive_root") != expected_root:
            raise SystemExit("offline verifier did not preserve exact archive root")
        if int(verify_payload.get("source_binding_count", 0)) != len(EXPECTED_BINDINGS):
            raise SystemExit("offline verifier did not verify every mandatory source binding")

        wrong_expected = "0" * 40 if head != "0" * 40 else "1" * 40
        run_rejected(verifier_command(bundle, wrong_expected), "bundle_expected_source_head_mismatch")

        manifest_path = bundle / "bundle-manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("schema") != "fmd.phase12g.external-acquisition-bundle.v4":
            raise SystemExit("portable bundle must use source-bound v4 schema")
        binding_rows = manifest.get("source_bindings", [])
        actual_bindings = {str(row.get("bundle_path")): str(row.get("source_archive_path")) for row in binding_rows}
        if actual_bindings != EXPECTED_BINDINGS:
            raise SystemExit(f"source binding mapping mismatch: {actual_bindings}")
        contract = manifest.get("archive_contract", {})
        for required_path in ["empirical/PHASE12G_RETURN_INGEST.md", "scripts/phase12g_extracted_source_verify.py"]:
            if required_path not in contract.get("required_regular_files", []):
                raise SystemExit(f"source archive contract must require {required_path}")
        if manifest.get("gate_dispositions_changed") is not False or manifest.get("evidence_appended") is not False:
            raise SystemExit("bundle manifest may not claim empirical mutation")
        guide_text = (bundle / "OPERATOR-GUIDE.md").read_text(encoding="utf-8")
        if f"--expected-source-head {head}" not in guide_text or "trusted handoff" not in guide_text:
            raise SystemExit("operator guide must carry the independent expected-source verification step")
        if "EXTRACTED-SOURCE-VERIFY.py" not in guide_text or "directory name" not in guide_text:
            raise SystemExit("operator guide must require extracted-tree verification without trusting directory naming")

        archive = bundle / str(verify_payload.get("source_archive", ""))
        pristine_archive = temp / "pristine-source.tar.gz"
        shutil.copy2(archive, pristine_archive)
        original_manifest = manifest_path.read_text(encoding="utf-8")

        for bundle_path, source_path in EXPECTED_BINDINGS.items():
            root_bytes = (bundle / bundle_path).read_bytes()
            source_bytes = archive_bytes(archive, expected_root + source_path)
            if root_bytes != source_bytes:
                raise SystemExit(f"fresh source binding is not byte-identical: {bundle_path}")

        extracted_root = extract_verified_archive(archive, temp / "extract", expected_root)
        extracted_verified = run(extracted_verifier_command(bundle, extracted_root, head), cwd=bundle)
        extracted_payload = json.loads(extracted_verified.stdout.strip().splitlines()[-1])
        if extracted_payload.get("status") != "EXTRACTED_SOURCE_VERIFIED":
            raise SystemExit("fresh extracted source did not verify")
        if extracted_payload.get("expected_source_head") != head:
            raise SystemExit("extracted verifier did not preserve independent source head")
        if extracted_payload.get("extracted_root_name_trusted") is not False or extracted_payload.get("source_head_text_trusted") is not False:
            raise SystemExit("extracted verifier must explicitly reject name/copied-source-text as identity authorities")

        renamed_root = extracted_root.parent / "arbitrary-working-tree-name"
        extracted_root.rename(renamed_root)
        run(extracted_verifier_command(bundle, renamed_root, head), cwd=bundle)

        tampered = renamed_root / "IMPLEMENTATION_START_HERE.md"
        pristine_tampered = tampered.read_bytes()
        tampered.write_bytes(pristine_tampered + b"\ntransport tamper\n")
        run_rejected(extracted_verifier_command(bundle, renamed_root, head), "extracted_source_file_hash_mismatch", cwd=bundle)
        tampered.write_bytes(pristine_tampered)

        extra = renamed_root / "UNTRACKED-ACQUISITION-MUTATION.txt"
        extra.write_text("extra", encoding="utf-8")
        run_rejected(extracted_verifier_command(bundle, renamed_root, head), "extracted_source_file_set_mismatch", cwd=bundle)
        extra.unlink()
        run_rejected(extracted_verifier_command(bundle, renamed_root, wrong_expected), "extracted_bundle_verification_failed", cwd=bundle)

        finalizer = bundle / "FIELD-KIT-FINALIZE.py"
        pristine_finalizer = finalizer.read_bytes()
        finalizer.write_bytes(pristine_finalizer + b"\n# transport tamper\n")
        refresh_file_row(manifest_path, finalizer)
        run_rejected(verifier_command(bundle, head), "bundle_source_binding_size_mismatch")
        finalizer.write_bytes(pristine_finalizer)
        manifest_path.write_text(original_manifest, encoding="utf-8")

        return_member = expected_root + EXPECTED_BINDINGS["RETURN-INGEST.md"]
        source_return = archive_bytes(archive, return_member)
        rewrite_archive_member(archive, return_member, source_return + b"\ntransport tamper\n")
        refresh_archive_manifest(manifest_path, archive)
        run_rejected(verifier_command(bundle, head), "bundle_source_binding_size_mismatch")
        shutil.copy2(pristine_archive, archive)
        manifest_path.write_text(original_manifest, encoding="utf-8")

        malformed = json.loads(original_manifest)
        malformed["source_bindings"] = malformed["source_bindings"][:-1]
        manifest_path.write_text(json.dumps(malformed, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        run_rejected(verifier_command(bundle, head), "bundle_source_binding_set_mismatch")
        manifest_path.write_text(original_manifest, encoding="utf-8")

        backslash = tarfile.TarInfo(expected_root + "scripts\\portable-escape.py")
        rewrite_archive_with_extra_member(archive, backslash, b"unsafe")
        refresh_archive_manifest(manifest_path, archive, 1)
        run_rejected(verifier_command(bundle, head), "bundle_archive_unsafe_portable_member_path")
        shutil.copy2(pristine_archive, archive)
        manifest_path.write_text(original_manifest, encoding="utf-8")

        guide = bundle / "OPERATOR-GUIDE.md"
        guide.write_text(guide.read_text(encoding="utf-8") + "tamper\n", encoding="utf-8")
        run_rejected(verifier_command(bundle, head), "bundle_file_")

        wrong_out = temp / "wrong"
        wrong_run = subprocess.run(
            [sys.executable, str(BUILDER), "--source-head", wrong_expected, "--output", str(wrong_out)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        if wrong_run.returncode == 0 or "source-head mismatch" not in (wrong_run.stdout + wrong_run.stderr):
            raise SystemExit("builder did not reject a non-checkout source head")

    evidence_after = digest_tree(EVIDENCE)
    if evidence_before != evidence_after:
        raise SystemExit("external bundle audit mutated empirical evidence")
    print(
        "Phase 12G external acquisition bundle audit: PASS "
        "(exact-source v4 archive + independent expected-source handoff + byte-bound extracted-tree verifier + directory-name/SOURCE_HEAD distrust + adversarial extraction/transport rejection + zero evidence/disposition mutation)"
    )


if __name__ == "__main__":
    main()
