#!/usr/bin/env python3
"""Generate deterministic ZIP fixtures for Tapeek's ZIP reader tests."""
from __future__ import annotations

import json
import os
import stat
import struct
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Samples" / "zip"
STAMP = (2020, 1, 2, 3, 4, 6)


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


def build_manifest():
    manifest = {}
    for path in sorted(OUT.glob("*.zip")):
        try:
            with zipfile.ZipFile(path) as zf:
                infos = zf.infolist()
                manifest[path.name] = {
                    "entryCount": len(infos),
                    "fileCount": sum(not i.is_dir() and not stat.S_ISLNK(i.external_attr >> 16) for i in infos),
                    "directoryCount": sum(i.is_dir() for i in infos),
                    "totalUncompressedBytes": sum(i.file_size for i in infos if not i.is_dir()),
                    "hasEncryptedEntries": any(i.flag_bits & 1 for i in infos),
                    "zip64": any(i.extract_version >= 45 for i in infos) or len(infos) >= 65535,
                    "names": sorted(i.filename for i in infos),
                }
        except (zipfile.BadZipFile, UnicodeDecodeError):
            manifest[path.name] = {"corrupt": True}
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    records = [
        ("docs/", b"", "directory"), ("docs/readme.txt", b"Read me\n", "file"),
        ("src/main.swift", b"print(1)\n", "file"), ("空目录/", b"", "directory"),
        ("中文.txt", b"Chinese\n", "file"),
    ]
    write_zip(OUT / "typical.zip", records)
    write_zip(OUT / "flat.zip", [(f"file-{i:02}.txt", b"x", "file") for i in range(5)])
    write_zip(OUT / "empty.zip", [])
    write_zip(OUT / "chinese-utf8.zip", [("你好/文件.txt", b"hello", "file")])
    gbk_zip(OUT / "chinese-gbk.zip")
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
    (OUT / "zip64-entry.zip").write_bytes(local_header + central_header + zip64_end + locator + eocd)
    write_zip(OUT / "duplicates.zip", [("same.txt", b"first", "file"), ("same.txt", b"second", "file")])
    write_zip(OUT / "unsafe-paths.zip", [("../evil.txt", b"", "file"), ("/abs.txt", b"", "file"), ("a/../../b.txt", b"", "file"), ("safe.txt", b"ok", "file")])
    write_zip(OUT / "missing-dirs.zip", [("a/b/c.txt", b"c", "file")])
    write_zip(OUT / "empty-dirs.zip", [("empty/", b"", "directory"), ("nested/empty/", b"", "directory")])
    write_zip(OUT / "sort.zip", [("z.txt", b"", "file"), ("b/", b"", "directory"), ("a.txt", b"", "file"), ("a/", b"", "directory")])
    write_zip(OUT / "single-root.zip", [("Project/README.md", b"", "file"), ("Project/docs/a.md", b"", "file")])
    write_zip(OUT / "long-names.zip", [("n" * 200 + ".txt", b"", "file")])
    write_zip(OUT / "macos-noise.zip", [("__MACOSX/", b"", "directory"), ("__MACOSX/._readme.md", b"", "file"), (".DS_Store", b"", "file")])
    write_zip(OUT / "symlink.zip", [("link", b"target", "symlink")])

    # Deterministic encrypted fixture when the system zip command supports encryption.
    with tempfile.TemporaryDirectory(prefix="tapeek-zip-fixtures-") as td:
        src = Path(td) / "secret.txt"
        src.write_bytes(b"secret")
        fixed_epoch = 1_577_934_246  # 2020-01-02 03:04:06 UTC
        os.utime(src, (fixed_epoch, fixed_epoch))
        encrypted_path = OUT / "encrypted.zip"
        encrypted_path.unlink(missing_ok=True)
        env = dict(os.environ, TZ="UTC")
        result = subprocess.run(["zip", "-q", "-0", "-P", "tapeek", str(encrypted_path), "secret.txt"], cwd=td, env=env, check=False)
        if result.returncode != 0:
            write_zip(OUT / "encrypted.zip", [("secret.txt", b"secret", "file")])
            data = bytearray((OUT / "encrypted.zip").read_bytes())
            pos = data.find(b"PK\x01\x02")
            if pos >= 0:
                flags = struct.unpack_from("<H", data, pos + 8)[0] | 1
                struct.pack_into("<H", data, pos + 8, flags)
            (OUT / "encrypted.zip").write_bytes(data)
    base = (OUT / "typical.zip").read_bytes()
    (OUT / "corrupt.zip").write_bytes(base[:-12])
    (OUT / "sfx.zip").write_bytes(b"Tapeek deterministic SFX prefix\n" + base)
    build_manifest()
    print(f"Generated {len(list(OUT.glob('*.zip')))} ZIP fixtures in {OUT}")


if __name__ == "__main__":
    main()
