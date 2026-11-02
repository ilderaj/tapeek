#!/usr/bin/env python3
"""Generate deterministic Markdown and ZIP fixtures for Tapeek tests.

Committed fixtures live in Samples/zip. Large performance samples live in
.build/fixtures and are never committed. Use --check to validate the committed
manifest and, when present, the large-sample manifest without writing files.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import struct
import subprocess
import sys
import tempfile
import unicodedata
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SAMPLES_ZIP = ROOT / "Samples" / "zip"
FIXTURES = ROOT / ".build" / "fixtures"
STAMP = (2020, 1, 2, 3, 4, 6)

# Must match PreviewLimits.maxZipEntries. The large manifest records the
# expected visible prefix, because the reader truncates listings at this limit.
DEFAULT_ENTRY_LIMIT = 20_000
LARGE_MARKDOWN_TARGETS = {
    "large-500kb.md": 500 * 1024,
    "large-2.1mb.md": 2_200_000,
}


def nfc(value: str) -> str:
    return unicodedata.normalize("NFC", value)


def name_without_trailing_slash(value: str) -> str:
    return value[:-1] if value.endswith("/") else value


def write_zip(path: Path, records: list[tuple[str, bytes, str]], *, force_zip64=False):
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as zf:
        for name, payload, kind in records:
            info = zipfile.ZipInfo(name, STAMP)
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            if kind == "directory":
                info.external_attr = (stat.S_IFDIR | 0o755) << 16 | 0x10
            elif kind == "symlink":
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
            else:
                info.external_attr = (stat.S_IFREG | 0o644) << 16
            if force_zip64:
                with zf.open(info, "w", force_zip64=True) as stream:
                    stream.write(payload)
            else:
                zf.writestr(info, payload)


def gbk_zip(path: Path):
    name = "中文.txt".encode("gbk")
    data = b""
    crc = 0
    local = struct.pack("<IHHHHHIIIHH", 0x04034B50, 20, 0, 0, 0, 0, crc, 0, 0, len(name), 0) + name
    central = struct.pack("<IHHHHHHIIIHHHHHII", 0x02014B50, 20, 20, 0, 0, 0, 0, crc, 0, 0, len(name), 0, 0, 0, 0, (stat.S_IFREG | 0o644) << 16, 0) + name
    eocd = struct.pack("<IHHHHIIH", 0x06054B50, 0, 0, 1, 1, len(central), len(local), 0)
    path.write_bytes(local + central + eocd)


def zip_structure(path: Path) -> dict:
    """Raw central-directory structure, independent of the app parser."""
    try:
        with zipfile.ZipFile(path) as zf:
            infos = zf.infolist()
    except (zipfile.BadZipFile, UnicodeDecodeError, OSError):
        return {"corrupt": True}
    return {
        "entryCount": len(infos),
        "fileCount": sum(not i.is_dir() and not stat.S_ISLNK(i.external_attr >> 16) for i in infos),
        "directoryCount": sum(i.is_dir() for i in infos),
        "totalUncompressedBytes": sum(i.file_size for i in infos if not i.is_dir()),
        "hasEncryptedEntries": any(i.flag_bits & 1 for i in infos),
        "zip64": any(i.extract_version >= 45 for i in infos) or len(infos) >= 65535,
        "names": sorted(nfc(i.filename) for i in infos),
    }


def large_structure(path: Path, limit: int = DEFAULT_ENTRY_LIMIT) -> dict:
    """Expected ZipArchiveReader listing after the default entry limit."""
    try:
        with zipfile.ZipFile(path) as zf:
            infos = zf.infolist()
    except (zipfile.BadZipFile, UnicodeDecodeError, OSError):
        return {"corrupt": True}
    shown = infos[:limit]
    return {
        "totalEntries": len(infos),
        "shownEntries": len(shown),
        "fileCount": sum(not i.is_dir() for i in shown),
        "directoryCount": sum(i.is_dir() for i in shown),
        "totalUncompressedBytes": sum(i.file_size for i in shown if not i.is_dir()),
        "hasEncryptedEntries": any(i.flag_bits & 1 for i in shown),
        "zip64": any(i.extract_version >= 45 for i in infos) or len(infos) >= 65535,
        "isTruncated": len(infos) > limit,
        "names": sorted(nfc(name_without_trailing_slash(i.filename)) for i in shown),
    }


def build_manifest(directory: Path, manifest_path: Path):
    manifest = {}
    for path in sorted(directory.glob("*.zip")):
        manifest[path.name] = zip_structure(path)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


def build_large_manifest(paths: list[Path]):
    manifest = {path.name: large_structure(path) for path in paths}
    FIXTURES.mkdir(parents=True, exist_ok=True)
    (FIXTURES / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


def compare_structures(name: str, expected: dict, actual: dict) -> list[str]:
    errors: list[str] = []
    if expected.get("corrupt") or actual.get("corrupt"):
        if not (expected.get("corrupt") and actual.get("corrupt")):
            errors.append(f"{name}: corrupt status expected={bool(expected.get('corrupt'))} actual={bool(actual.get('corrupt'))}")
        return errors
    for key in expected:
        if key in ("names", "corrupt"):
            continue
        if expected.get(key) != actual.get(key):
            errors.append(f"{name}: {key} expected={expected.get(key)!r} actual={actual.get(key)!r}")
    expected_names = set(expected.get("names", []))
    actual_names = set(actual.get("names", []))
    if expected_names != actual_names:
        missing = sorted(expected_names - actual_names)
        extra = sorted(actual_names - expected_names)
        errors.append(
            f"{name}: names differ; missing={missing[:5]!r} ({len(missing)}), "
            f"extra={extra[:5]!r} ({len(extra)})"
        )
    return errors


def check_committed_manifest() -> list[str]:
    errors: list[str] = []
    manifest_path = SAMPLES_ZIP / "manifest.json"
    if not manifest_path.exists():
        return [f"{manifest_path}: manifest missing"]
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    actual_names = sorted(path.name for path in SAMPLES_ZIP.glob("*.zip"))
    manifest_names = sorted(name for name in manifest if name.endswith(".zip"))
    for name in sorted(set(actual_names) - set(manifest_names)):
        errors.append(f"{name}: ZIP exists but is missing from manifest")
    for name in sorted(set(manifest_names) - set(actual_names)):
        errors.append(f"{name}: manifest entry exists but ZIP file is missing")
    for name in actual_names:
        if name not in manifest:
            continue
        actual = zip_structure(SAMPLES_ZIP / name)
        errors.extend(compare_structures(name, manifest[name], actual))
    return errors


def check_large_manifest(require_large: bool = False) -> list[str]:
    errors: list[str] = []
    large_paths = [FIXTURES / "many-entries.zip", FIXTURES / "zip64.zip"]
    missing = [path.name for path in large_paths if not path.exists()]
    missing_markdown = [name for name in LARGE_MARKDOWN_TARGETS if not (FIXTURES / name).exists()]
    manifest_path = FIXTURES / "manifest.json"

    if require_large:
        for name in missing:
            errors.append(f"{name}: required large ZIP sample is missing")
        for name in missing_markdown:
            errors.append(f"{name}: required large Markdown sample is missing")
        if not manifest_path.exists():
            errors.append(f"{manifest_path}: required large manifest is missing")
    else:
        if missing:
            print(f"large samples not generated, skipped and NOT verified (未生成，跳过且未验证): {', '.join(missing)}")
        if missing_markdown:
            print(f"large markdown not generated, skipped and NOT verified (未生成，跳过且未验证): {', '.join(missing_markdown)}")

    if not manifest_path.exists():
        return errors
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for path in large_paths:
        if not path.exists():
            continue
        if path.name not in manifest:
            errors.append(f"{path.name}: present but missing from large manifest")
            continue
        errors.extend(compare_structures(path.name, manifest[path.name], large_structure(path)))
    return errors


def generate_committed():
    SAMPLES_ZIP.mkdir(parents=True, exist_ok=True)
    records = [
        ("docs/", b"", "directory"), ("docs/readme.txt", b"Read me\n", "file"),
        ("src/main.swift", b"print(1)\n", "file"), ("空目录/", b"", "directory"),
        ("中文.txt", b"Chinese\n", "file"),
    ]
    write_zip(SAMPLES_ZIP / "typical.zip", records)
    write_zip(SAMPLES_ZIP / "flat.zip", [(f"file-{i:02}.txt", b"x", "file") for i in range(5)])
    write_zip(SAMPLES_ZIP / "empty.zip", [])
    write_zip(SAMPLES_ZIP / "chinese-utf8.zip", [("你好/文件.txt", b"hello", "file")])
    gbk_zip(SAMPLES_ZIP / "chinese-gbk.zip")
    # A compact ZIP64 entry exercises ZIP64 extra field resolution without a huge file.
    zip_name = b"zip64.txt"
    payload = b"zip64"
    import binascii
    crc = binascii.crc32(payload) & 0xFFFFFFFF
    local_header = struct.pack("<IHHHHHIIIHH", 0x04034B50, 45, 0, 0, 0, 0, crc, len(payload), len(payload), len(zip_name), 0) + zip_name + payload
    extra64 = struct.pack("<HHQQ", 0x0001, 16, len(payload), len(payload))
    central_header = struct.pack("<IHHHHHHIIIHHHHHII", 0x02014B50, 45, 45, 0, 0, 0, 0, crc, 0xFFFFFFFF, 0xFFFFFFFF, len(zip_name), len(extra64), 0, 0, 0, (stat.S_IFREG | 0o644) << 16, 0) + zip_name + extra64
    zip64_end_offset = len(local_header) + len(central_header)
    zip64_end = struct.pack("<IQHHIIQQQQ", 0x06064B50, 44, 45, 45, 0, 0, 1, 1, len(central_header), len(local_header))
    locator = struct.pack("<IIQI", 0x07064B50, 0, zip64_end_offset, 1)
    eocd = struct.pack("<IHHHHIIH", 0x06054B50, 0, 0, 0xFFFF, 0xFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0)
    (SAMPLES_ZIP / "zip64-entry.zip").write_bytes(local_header + central_header + zip64_end + locator + eocd)
    write_zip(SAMPLES_ZIP / "duplicates.zip", [("same.txt", b"first", "file"), ("same.txt", b"second", "file")])
    write_zip(SAMPLES_ZIP / "unsafe-paths.zip", [("../evil.txt", b"", "file"), ("/abs.txt", b"", "file"), ("a/../../b.txt", b"", "file"), ("safe.txt", b"ok", "file")])
    write_zip(SAMPLES_ZIP / "missing-dirs.zip", [("a/b/c.txt", b"c", "file")])
    write_zip(SAMPLES_ZIP / "empty-dirs.zip", [("empty/", b"", "directory"), ("nested/empty/", b"", "directory")])
    write_zip(SAMPLES_ZIP / "sort.zip", [("z.txt", b"", "file"), ("b/", b"", "directory"), ("a.txt", b"", "file"), ("a/", b"", "directory")])
    write_zip(SAMPLES_ZIP / "single-root.zip", [("Project/README.md", b"", "file"), ("Project/docs/a.md", b"", "file")])
    write_zip(SAMPLES_ZIP / "long-names.zip", [("n" * 200 + ".txt", b"", "file")])
    write_zip(SAMPLES_ZIP / "macos-noise.zip", [("__MACOSX/", b"", "directory"), ("__MACOSX/._readme.md", b"", "file"), (".DS_Store", b"", "file")])
    write_zip(SAMPLES_ZIP / "symlink.zip", [("link", b"target", "symlink")])

    # Deterministic encrypted fixture when the system zip command supports encryption.
    with tempfile.TemporaryDirectory(prefix="tapeek-zip-fixtures-") as td:
        src = Path(td) / "secret.txt"
        src.write_bytes(b"secret")
        fixed_epoch = 1_577_934_246  # 2020-01-02 03:04:06 UTC
        os.utime(src, (fixed_epoch, fixed_epoch))
        encrypted_path = SAMPLES_ZIP / "encrypted.zip"
        encrypted_path.unlink(missing_ok=True)
        env = dict(os.environ, TZ="UTC")
        result = subprocess.run(["zip", "-q", "-0", "-P", "tapeek", str(encrypted_path), "secret.txt"], cwd=td, env=env, check=False)
        if result.returncode != 0:
            write_zip(SAMPLES_ZIP / "encrypted.zip", [("secret.txt", b"secret", "file")])
            data = bytearray((SAMPLES_ZIP / "encrypted.zip").read_bytes())
            pos = data.find(b"PK\x01\x02")
            if pos >= 0:
                flags = struct.unpack_from("<H", data, pos + 8)[0] | 1
                struct.pack_into("<H", data, pos + 8, flags)
            (SAMPLES_ZIP / "encrypted.zip").write_bytes(data)
    base = (SAMPLES_ZIP / "typical.zip").read_bytes()
    (SAMPLES_ZIP / "corrupt.zip").write_bytes(base[:-12])
    (SAMPLES_ZIP / "sfx.zip").write_bytes(b"Tapeek deterministic SFX prefix\n" + base)
    build_manifest(SAMPLES_ZIP, SAMPLES_ZIP / "manifest.json")


def write_large_markdown(path: Path, target_bytes: int):
    blocks: list[str] = []
    total = 0
    index = 0
    while total < target_bytes:
        block = (
            f"## Section {index:05d}\n\n"
            f"Paragraph {index:05d}: Tapeek benchmark content. "
            "The quick brown fox jumps over the lazy dog. "
            "This line is repeated with a distinct heading so the parser cannot "
            "collapse the document into one block.\n\n"
            "- item alpha\n- item beta\n- item gamma\n\n"
        )
        blocks.append(block)
        total += len(block.encode("utf-8"))
        index += 1
    path.write_text("".join(blocks), encoding="utf-8", newline="\n")


def generate_large():
    FIXTURES.mkdir(parents=True, exist_ok=True)
    for name, target in LARGE_MARKDOWN_TARGETS.items():
        write_large_markdown(FIXTURES / name, target)
    many = FIXTURES / "many-entries.zip"
    zip64 = FIXTURES / "zip64.zip"
    write_zip(many, [(f"entry-{i:05d}.txt", b"", "file") for i in range(25_000)])
    write_zip(zip64, [(f"entry-{i:05d}.txt", b"", "file") for i in range(70_000)])
    build_large_manifest([many, zip64])


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def report_generated(paths: list[Path]):
    for path in paths:
        structure = zip_structure(path) if path.suffix == ".zip" else {}
        entries = structure.get("entryCount", "-")
        print(f"{path.relative_to(ROOT)} entries={entries} sha256={sha256(path)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate manifests without writing files")
    parser.add_argument("--require-large", action="store_true", help="fail if large performance samples are missing")
    parser.add_argument("--large-only", action="store_true", help="generate only .build/fixtures large samples")
    args = parser.parse_args()

    if args.check:
        errors = check_committed_manifest()
        errors.extend(check_large_manifest(require_large=args.require_large))
        if errors:
            print(f"fixture check failed with {len(errors)} error(s):", file=sys.stderr)
            for error in errors:
                print(f"  - {error}", file=sys.stderr)
            return 1
        committed = len(list(SAMPLES_ZIP.glob("*.zip")))
        print(f"fixture check passed: {committed} committed ZIP fixtures match manifest")
        if args.require_large:
            print("large samples: required and verified")
        else:
            print("large samples: checked only when present; missing samples are NOT verified")
        return 0

    if not args.large_only:
        generate_committed()
        print(f"Generated {len(list(SAMPLES_ZIP.glob('*.zip')))} committed ZIP fixtures in {SAMPLES_ZIP}")
    generate_large()
    generated = sorted(SAMPLES_ZIP.glob("*.zip")) if not args.large_only else []
    generated.extend(sorted(FIXTURES.glob("large-*.md")))
    generated.extend([FIXTURES / "many-entries.zip", FIXTURES / "zip64.zip"])
    report_generated(generated)
    print(f"Large fixtures and manifest written to {FIXTURES}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
