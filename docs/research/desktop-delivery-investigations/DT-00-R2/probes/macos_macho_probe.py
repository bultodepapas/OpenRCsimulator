#!/usr/bin/env python3
"""Read the main Mach-O executable and Info.plist from an existing macOS export ZIP.

This is a static parser, not a codesign or Gatekeeper verifier. It writes only
JSON to stdout and extracts the single executable into a temporary file.
"""

from __future__ import annotations

import hashlib
import json
import os
import plistlib
import struct
import sys
import tempfile
import uuid
import zipfile
from pathlib import Path


CPU_TYPES = {0x01000007: "x86_64", 0x0100000C: "arm64"}
DYLIB_COMMANDS = {
    0x0000000C: "LC_LOAD_DYLIB",
    0x0000000D: "LC_ID_DYLIB",
    0x00000018: "LC_LOAD_WEAK_DYLIB",
    0x0000001F: "LC_REEXPORT_DYLIB",
    0x00000020: "LC_LOAD_LAZY_DYLIB",
    0x00000023: "LC_LOAD_UPWARD_DYLIB",
}
LC_BUILD_VERSION = 0x32
LC_VERSION_MIN_MACOSX = 0x24
LC_UUID = 0x1B
LC_CODE_SIGNATURE = 0x1D
LC_RPATH = 0x8000001C
CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_CODEDIRECTORY = 0xFADE0C02
CS_ADHOC = 0x2
CS_RUNTIME = 0x10000


def version(value: int) -> str:
    return f"{value >> 16}.{(value >> 8) & 0xff}.{value & 0xff}"


def c_string(data: bytes, offset: int) -> str:
    return data[offset:].split(b"\0", 1)[0].decode("utf-8", "replace")


def code_directory_flags(fd: int, absolute_offset: int, size: int) -> dict:
    header = os.pread(fd, 12, absolute_offset)
    if len(header) < 12:
        return {"error": "short signature superblob"}
    magic, length, count = struct.unpack(">III", header)
    if magic != CSMAGIC_EMBEDDED_SIGNATURE or length > size:
        return {"error": "not a bounded embedded-signature superblob", "magic": hex(magic)}
    indexes = os.pread(fd, min(count, 256) * 8, absolute_offset + 12)
    out = {"superblob_magic": hex(magic), "code_directories": []}
    for i in range(len(indexes) // 8):
        slot_type, blob_offset = struct.unpack_from(">II", indexes, i * 8)
        blob_header = os.pread(fd, 16, absolute_offset + blob_offset)
        if len(blob_header) < 16:
            continue
        blob_magic, blob_length, blob_version, flags = struct.unpack(">IIII", blob_header)
        if blob_magic != CSMAGIC_CODEDIRECTORY or blob_length < 16 or blob_length > size - blob_offset:
            continue
        out["code_directories"].append({
            "slot_type": slot_type,
            "version": hex(blob_version),
            "flags": hex(flags),
            "adhoc_flag": bool(flags & CS_ADHOC),
            "hardened_runtime_flag": bool(flags & CS_RUNTIME),
        })
    return out


def macho_slice(fd: int, offset: int, size: int, fat_arch: str | None) -> dict:
    head = os.pread(fd, 32, offset)
    if len(head) < 28:
        raise ValueError("short Mach-O header")
    magic_le = struct.unpack_from("<I", head)[0]
    if magic_le in (0xFEEDFACE, 0xFEEDFACF):
        endian = "<"
        is_64 = magic_le == 0xFEEDFACF
    else:
        magic_be = struct.unpack_from(">I", head)[0]
        if magic_be not in (0xFEEDFACE, 0xFEEDFACF):
            raise ValueError(f"unknown Mach-O magic {head[:4].hex()}")
        endian = ">"
        is_64 = magic_be == 0xFEEDFACF
    magic, cpu, subtype, filetype, ncmds, sizeofcmds, flags = struct.unpack_from(endian + "IiiIIII", head)
    header_size = 32 if is_64 else 28
    commands = []
    min_os = None
    signature = None
    offset_in_commands = 0
    for _ in range(ncmds):
        raw = os.pread(fd, 8, offset + header_size + offset_in_commands)
        if len(raw) != 8:
            raise ValueError("short load command")
        cmd, cmdsize = struct.unpack(endian + "II", raw)
        if cmdsize < 8 or offset_in_commands + cmdsize > sizeofcmds:
            raise ValueError("invalid load-command size")
        data = os.pread(fd, cmdsize, offset + header_size + offset_in_commands)
        item = {"command": f"0x{cmd:08x}", "size": cmdsize}
        if cmd in DYLIB_COMMANDS and cmdsize >= 24:
            name_offset = struct.unpack_from(endian + "I", data, 8)[0]
            item.update({"name": DYLIB_COMMANDS[cmd], "path": c_string(data, name_offset)})
            commands.append(item)
        elif cmd == LC_RPATH and cmdsize >= 12:
            name_offset = struct.unpack_from(endian + "I", data, 8)[0]
            item.update({"name": "LC_RPATH", "path": c_string(data, name_offset)})
            commands.append(item)
        elif cmd == LC_BUILD_VERSION and cmdsize >= 24:
            platform_id, min_value, sdk_value, tool_count = struct.unpack_from(endian + "IIII", data, 8)
            min_os = {"load_command": "LC_BUILD_VERSION", "platform": platform_id,
                      "minimum": version(min_value), "sdk": version(sdk_value), "tools": tool_count}
            commands.append({"name": "LC_BUILD_VERSION", **min_os})
        elif cmd == LC_VERSION_MIN_MACOSX and cmdsize >= 16:
            min_value, sdk_value = struct.unpack_from(endian + "II", data, 8)
            min_os = {"load_command": "LC_VERSION_MIN_MACOSX", "platform": "macOS",
                      "minimum": version(min_value), "sdk": version(sdk_value)}
            commands.append({"name": "LC_VERSION_MIN_MACOSX", **min_os})
        elif cmd == LC_UUID and cmdsize >= 24:
            commands.append({"name": "LC_UUID", "uuid": str(uuid.UUID(bytes=data[8:24]))})
        elif cmd == LC_CODE_SIGNATURE and cmdsize >= 16:
            data_offset, data_size = struct.unpack_from(endian + "II", data, 8)
            signature = code_directory_flags(fd, offset + data_offset, data_size)
            commands.append({"name": "LC_CODE_SIGNATURE", "data_size": data_size})
        offset_in_commands += cmdsize
    cpu_name = CPU_TYPES.get(cpu & 0xFFFFFFFF, f"0x{cpu & 0xffffffff:08x}")
    return {"architecture": fat_arch or cpu_name, "cpu_type": cpu_name, "cpu_subtype": subtype,
            "file_type": filetype, "mach_header": "64-bit" if is_64 else "32-bit",
            "flags": f"0x{flags:08x}", "minimum_os": min_os, "signature_flags": signature,
            "load_commands": commands}


def inspect_binary(path: Path) -> dict:
    fd = os.open(path, os.O_RDONLY)
    try:
        file_size = os.fstat(fd).st_size
        header = os.pread(fd, 8, 0)
        fat_magic = struct.unpack(">I", header[:4])[0]
        slices = []
        if fat_magic in (0xCAFEBABE, 0xCAFEBABF):
            count = struct.unpack(">I", header[4:8])[0]
            is_64 = fat_magic == 0xCAFEBABF
            record_size = 32 if is_64 else 20
            records = os.pread(fd, count * record_size, 8)
            for i in range(count):
                row = records[i * record_size:(i + 1) * record_size]
                if is_64:
                    cpu, subtype, offset, size, _, _ = struct.unpack(">IIQQII", row)
                else:
                    cpu, subtype, offset, size, _ = struct.unpack(">IIIII", row)
                cpu_name = CPU_TYPES.get(cpu, f"0x{cpu:08x}")
                slices.append(macho_slice(fd, offset, size, cpu_name))
        else:
            slices.append(macho_slice(fd, 0, file_size, None))
        return {"binary_size": file_size, "slices": slices}
    finally:
        os.close(fd)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} macOS-export.zip", file=sys.stderr)
        return 2
    archive = Path(sys.argv[1])
    archive_hash = hashlib.sha256()
    with archive.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            archive_hash.update(block)
    with zipfile.ZipFile(archive) as zf:
        candidates = [item for item in zf.infolist() if item.filename.endswith("/Contents/MacOS/OpenRC Simulator")]
        if len(candidates) != 1:
            raise ValueError(f"expected one app executable, found {len(candidates)}")
        plist_candidates = [item for item in zf.infolist() if item.filename.endswith("/Contents/Info.plist")]
        if len(plist_candidates) != 1:
            raise ValueError(f"expected one app Info.plist, found {len(plist_candidates)}")
        info_plist = plistlib.loads(zf.read(plist_candidates[0]))
        item = candidates[0]
        with tempfile.NamedTemporaryFile(prefix="openrc-macos-probe-") as extracted:
            with zf.open(item) as member:
                for block in iter(lambda: member.read(1024 * 1024), b""):
                    extracted.write(block)
            extracted.flush()
            binary = inspect_binary(Path(extracted.name))
    out = {
        "probe": "macos-macho-static-v1",
        "archive_path": str(archive),
        "archive_sha256": archive_hash.hexdigest(),
        "archive_member": item.filename,
        "archive_member_size": item.file_size,
        "archive_member_mode": oct((item.external_attr >> 16) & 0o777),
        "info_plist": {
            key: info_plist.get(key) for key in (
                "CFBundleExecutable", "CFBundleIdentifier", "LSMinimumSystemVersion",
                "LSMinimumSystemVersionByArchitecture", "LSArchitecturePriority",
                "LSRequiresNativeExecution", "NSHighResolutionCapable",
            )
        },
        "scope": "main Mach-O load commands including LC_UUID, Info.plist deployment/identity fields, and embedded CodeDirectory flags; no cryptographic verification, dependency resolution, or macOS execution",
        **binary,
    }
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
