#!/usr/bin/env python3
"""Inventory ELF metadata in a Linux ZIP without executing its contents."""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
from typing import BinaryIO
import zipfile


MAX_MEMBER_BYTES = 4 * 1024**3
MAX_TOTAL_BYTES = 8 * 1024**3
CHUNK_BYTES = 1024 * 1024
FAMILIES = ("GLIBC", "GLIBCXX", "CXXABI")
MACHINES = {"x86_64": "Advanced Micro Devices X86-64", "arm64": "AArch64"}
LIMITATIONS = (
    "GNU properties do not certify the complete CPU instruction set or hardware compatibility.",
    "Dependencies loaded dynamically with dlopen and their closure are not certified.",
    "Graphics, audio, input and other driver closure is not certified.",
    "Static ELF metadata does not establish distribution support or successful execution.",
)


class AuditError(ValueError):
    """The archive or its ELF metadata cannot be safely inventoried."""


def _run_readelf(argv: list[str]) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["LC_ALL"] = "C"
    env["LANG"] = "C"
    try:
        return subprocess.run(
            argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            env=env, encoding="utf-8", errors="backslashreplace", timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise AuditError(f"could not run readelf: {exc}") from exc


def _readelf(argv: list[str]) -> str:
    result = _run_readelf(argv)
    # GNU readelf can emit a malformed-file error and still exit successfully.
    if result.returncode != 0 or result.stderr.strip():
        detail = result.stderr.strip() or f"exit status {result.returncode}"
        raise AuditError(f"readelf failed: {detail}")
    return result.stdout


def _binutils_242(version: str) -> bool:
    return bool(re.fullmatch(r"GNU readelf(?:\s+.*)?\s+2\.42", version))


def _only_unsupported_fdo_notes(notes: str, sections: str) -> bool:
    """Recognize only the GNU 2.42 FDO-dlopen failure, with all note sections accounted for."""
    section_names: list[str] = []
    for line in sections.splitlines():
        if re.match(r"^[ \t]*\[[ \t]*\d+\]", line) and re.search(r"\bNOTE\s", line):
            entry = re.match(r"^[ \t]*\[[ \t]*\d+\][ \t]+(\S+)[ \t]+NOTE[ \t]+", line)
            if not entry:
                return False
            section_names.append(entry.group(1))
    headings = list(re.finditer(r"(?m)^Displaying notes found in: (\S+)[ \t]*$", notes))
    if not section_names or Counter(section_names) != Counter(heading.group(1) for heading in headings):
        return False
    saw_fdo = False
    for index, heading in enumerate(headings):
        end = headings[index + 1].start() if index + 1 < len(headings) else len(notes)
        block = notes[heading.end():end]
        header = re.match(r"\s*Owner\s+Data size\s+Description\s*\n", block)
        if not header:
            return False
        contents = block[header.end():]
        if heading.group(1) == ".note.dlopen":
            entry = r"\s*FDO[ \t]+0x[0-9a-fA-F]+\tUnknown note type: \(0x407c0c0a\)\t"
            if not re.fullmatch(rf"(?:{entry})+\s*", contents):
                return False
            saw_fdo = True
        else:
            entries = re.findall(r"(?<!\S)(\S+)[ \t]+0x[0-9a-fA-F]+\t([^\t\n]+)\t", contents)
            # Unlike e.g. GNU GOLD version notes, these three readelf
            # renderers do not print arbitrary strings from the ELF. That
            # prevents a note from forging section headings in stdout.
            allowed = {"NT_GNU_PROPERTY_TYPE_0", "NT_GNU_ABI_TAG", "NT_GNU_BUILD_ID"}
            if not entries or any(owner != "GNU" or kind.split(" ", 1)[0] not in allowed
                                  for owner, kind in entries):
                return False
    return saw_fdo


def _readelf_notes(readelf: str, path: Path, version: str) -> tuple[str, str]:
    result = _run_readelf([readelf, "-W", "-n", str(path)])
    # Some malformed GNU properties are reported only in stdout with exit 0.
    if result.stderr.strip() or "<corrupt" in result.stdout.lower():
        raise AuditError(f"readelf notes failed: {result.stderr.strip() or 'corrupt note output'}")
    if result.returncode == 0:
        return result.stdout, "readelf_ok"
    # Binutils 2.42's print_fdo_note returns false for FDO dlopen notes, even
    # after process_notes_at has checked their ELF note framing. Accept only
    # this exact output, and account for every SHT_NOTE section independently.
    if result.returncode == 1 and _binutils_242(version):
        sections = _readelf([readelf, "-W", "-S", str(path)])
        if "<corrupt" not in sections.lower() and _only_unsupported_fdo_notes(result.stdout, sections):
            return result.stdout, "fdo_dlopen_unsupported"
    raise AuditError(f"readelf notes failed: exit status {result.returncode}")


def _readelf_version(readelf: str) -> str:
    lines = _readelf([readelf, "--version"]).splitlines()
    if not lines or not lines[0].startswith("GNU readelf"):
        raise AuditError("GNU readelf is required")
    return lines[0]


def _field(output: str, name: str) -> str:
    matches = re.findall(rf"^\s*{re.escape(name)}:\s*(.*?)\s*$", output, re.MULTILINE)
    if len(matches) != 1 or not matches[0]:
        raise AuditError(f"missing or ambiguous ELF header field: {name}")
    return matches[0]


def _numeric_maxima(versions: dict[str, list[str]]) -> dict[str, str | None]:
    maxima: dict[str, str | None] = {}
    try:
        for family in FAMILIES:
            numeric = [version for version in versions[family]
                       if re.fullmatch(rf"{family}_[0-9]+(?:\.[0-9]+)*", version)]
            maxima[family] = max(
                numeric, key=lambda version: tuple(int(part) for part in version.split("_", 1)[1].split(".")),
                default=None,
            )
    except ValueError as exc:
        raise AuditError("unrepresentable numeric version") from exc
    return maxima


def _versions(output: str) -> tuple[dict[str, list[str]], dict[str, str | None], int]:
    """Read only version needs, never definitions or the version symbol table."""
    found: dict[str, set[str]] = {family: set() for family in FAMILIES}
    active = False
    section_count = 0
    seen_files = 0
    expected_files: int | None = None
    expected_names: int | None = None
    seen_names = 0

    def finish_file() -> None:
        if expected_names is not None and seen_names != expected_names:
            raise AuditError("incomplete version needs entries from readelf")

    def finish_section() -> None:
        finish_file()
        if expected_files is not None and seen_files != expected_files:
            raise AuditError("incomplete version needs section from readelf")

    for line in output.splitlines():
        header = re.match(r"^Version needs section .* contains (\d+) entr(?:y|ies):\s*$", line)
        if header:
            if active:
                finish_section()
            section_count += 1
            active = True
            expected_files = int(header.group(1))
            seen_files = 0
            expected_names = None
            seen_names = 0
            continue
        if line.startswith("Version needs section"):
            raise AuditError("unrecognized version needs section from readelf")
        if not active:
            continue
        if not line.strip() or re.match(r"^(?:Version .* section|Displaying notes found in:)", line):
            finish_section()
            active = False
            continue
        if re.match(r"^\s*Addr:\s", line):
            continue
        entry = re.match(r"^\s*(?:0x)?[0-9a-fA-F]+:\s+Version:\s+\d+\s+File:\s+.+?\s+Cnt:\s+(\d+)\s*$", line)
        if entry:
            finish_file()
            expected_names = int(entry.group(1))
            seen_names = 0
            seen_files += 1
            continue
        name = re.match(r"^\s*(?:0x)?[0-9a-fA-F]+:\s+Name:\s+(\S+)\s+Flags:\s+.*\s+Version:\s+\d+\s*$", line)
        if name and expected_names is not None:
            seen_names += 1
            version = name.group(1)
            for family in FAMILIES:
                if version.startswith(family + "_"):
                    found[family].add(version)
                    break
            continue
        raise AuditError(f"unrecognized version needs output: {line.strip()}")
    if active:
        finish_section()
    if section_count > 1:
        raise AuditError("multiple version needs sections")

    versions = {family: sorted(found[family]) for family in FAMILIES}
    return versions, _numeric_maxima(versions), seen_files if section_count else 0


def _dynamic(output: str) -> tuple[list[str], list[str], list[str], int | None]:
    tags: dict[str, list[str]] = {name: [] for name in ("NEEDED", "RPATH", "RUNPATH")}
    need_pointers = 0
    need_counts: list[int] = []
    for line in output.splitlines():
        tag = re.match(r"^\s*0x[0-9a-fA-F]+\s+\(([^)]+)\)\s+(.*?)\s*$", line)
        if not tag:
            if re.search(r"\((?:NEEDED|RPATH|RUNPATH|VERNEED|VERNEEDNUM)\)", line):
                raise AuditError("unrecognized dynamic tag from readelf")
            continue
        kind, value = tag.groups()
        if kind in tags:
            match = re.fullmatch(r"(?:Shared library|Library rpath|Library runpath):\s*\[(.*)\]", value)
            if match is None or "<corrupt>" in value:
                raise AuditError(f"unrecognized {kind} value from readelf")
            tags[kind].append(match.group(1))
        elif kind == "VERNEED":
            need_pointers += 1
        elif kind == "VERNEEDNUM":
            if not re.fullmatch(r"\d+", value):
                raise AuditError("unrecognized VERNEEDNUM value from readelf")
            need_counts.append(int(value))
    if need_pointers != len(need_counts) or need_pointers > 1:
        raise AuditError("incomplete or ambiguous dynamic version needs metadata")
    return tags["NEEDED"], tags["RPATH"], tags["RUNPATH"], need_counts[0] if need_counts else None


def _stack(output: str) -> dict[str, object]:
    matches = [line.split() for line in output.splitlines() if re.match(r"^\s*GNU_STACK\s", line)]
    if not matches:
        return {"present": False, "permissions": None, "executable": None}
    if len(matches) != 1:
        raise AuditError("multiple GNU_STACK program headers")
    fields = matches[0]
    if (len(fields) < 7 or any(not re.fullmatch(r"0x[0-9a-fA-F]+", value) for value in fields[1:6])
            or not re.fullmatch(r"0x[0-9a-fA-F]+", fields[-1])):
        raise AuditError("unrecognized GNU_STACK output from readelf")
    flags = "".join(fields[6:-1])
    if any(flag not in "RWE" for flag in flags) or len(flags) != len(set(flags)):
        raise AuditError("unrecognized GNU_STACK flags from readelf")
    permissions = "".join(flag for flag in "RWE" if flag in flags)
    return {"present": True, "permissions": permissions, "executable": "E" in flags}


def _properties(output: str) -> list[str]:
    properties: list[str] = []
    collecting = False
    for line in output.splitlines():
        if "NT_GNU_PROPERTY_TYPE_0" in line:
            collecting = True
            suffix = line.split("NT_GNU_PROPERTY_TYPE_0", 1)[1]
            if "Properties:" in suffix:
                value = suffix.split("Properties:", 1)[1].strip()
                if value:
                    properties.append(value)
            continue
        if not collecting:
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith(("Displaying notes", "Owner")) or re.match(r"^\S+\s+0x[0-9a-fA-F]+\s+NT_", stripped):
            collecting = False
            continue
        if stripped.startswith("Properties:"):
            stripped = stripped[len("Properties:"):].strip()
        if stripped:
            properties.append(stripped)
    return properties


def _inspect_elf(path: Path, archive_path: str, size: int, digest: str,
                 expected_architecture: str, readelf: str, readelf_version: str) -> dict[str, object]:
    try:
        output = _readelf([readelf, "-W", "-h", "-l", "-d", "--version-info", str(path)])
        notes, notes_status = _readelf_notes(readelf, path, readelf_version)
        output += "\n" + notes
        if "ELF Header:" not in output:
            raise AuditError("missing ELF header")
        elf_class = _field(output, "Class")
        data = _field(output, "Data")
        machine = _field(output, "Machine")
        if elf_class != "ELF64" or data != "2's complement, little endian" or machine != MACHINES[expected_architecture]:
            raise AuditError(f"wrong ELF architecture: class={elf_class}, data={data}, machine={machine}")
        interpreter_headers = sum(bool(re.match(r"^\s*INTERP\s", line)) for line in output.splitlines())
        interpreters = re.findall(r"^\s*\[Requesting program interpreter:\s*(.*?)\]\s*$", output, re.MULTILINE)
        if interpreter_headers != len(interpreters) or len(interpreters) > 1 or any(not value for value in interpreters):
            raise AuditError("incomplete or ambiguous ELF interpreter")
        dynamic_headers = sum(bool(re.match(r"^\s*DYNAMIC\s", line)) for line in output.splitlines())
        dynamic_sections = sum(bool(re.match(r"^Dynamic (?:section|segment) at offset ", line)) for line in output.splitlines())
        if dynamic_headers > 1 or (dynamic_headers and not dynamic_sections):
            raise AuditError("readelf could not recover the dynamic segment")
        needed, rpath, runpath, expected_needs = _dynamic(output)
        versions, maxima, actual_needs = _versions(output)
        # readelf -V uses section headers; it can print no needs for a valid
        # sectionless ELF even when DT_VERNEED/DT_VERNEEDNUM are present.
        if expected_needs is not None and actual_needs != expected_needs:
            raise AuditError("readelf could not recover all dynamic version needs")
        return {
            "path": archive_path, "sha256": digest, "bytes": size,
            "architecture": expected_architecture, "elf_class": elf_class,
            "endianness": "little", "os_abi": _field(output, "OS/ABI"),
            "interpreter": interpreters[0] if interpreters else None,
            "needed": needed, "rpath": rpath, "runpath": runpath,
            "required_versions": versions, "max_required_versions": maxima,
            "gnu_stack": _stack(output), "gnu_properties": _properties(output), "notes_status": notes_status,
        }
    except AuditError as exc:
        raise AuditError(f"{archive_path}: {exc}") from exc


def _member_path(info: zipfile.ZipInfo) -> tuple[str, bool]:
    name = info.filename
    if name != info.orig_filename or not name or "\\" in name or ":" in name or name.startswith("/"):
        raise AuditError(f"unsafe ZIP member path: {info.orig_filename!r}")
    is_dir = info.is_dir()
    path = name[:-1] if is_dir else name
    if not path or any(part in ("", ".", "..") for part in path.split("/")):
        raise AuditError(f"unsafe ZIP member path: {name!r}")
    mode = info.external_attr >> 16
    file_type = stat.S_IFMT(mode)
    if file_type not in (0, stat.S_IFREG, stat.S_IFDIR):
        raise AuditError(f"ZIP member is a symlink or special file: {name!r}")
    if (is_dir and file_type == stat.S_IFREG) or (not is_dir and file_type == stat.S_IFDIR):
        raise AuditError(f"inconsistent ZIP member type: {name!r}")
    if is_dir and info.file_size:
        raise AuditError(f"ZIP directory has data: {name!r}")
    return path, is_dir


def _report_object(value: object, fields: set[str], name: str) -> dict[str, object]:
    if type(value) is not dict or set(value) != fields:
        raise AuditError(f"invalid {name} fields")
    return value


def _report_string(value: object, name: str, *, empty: bool = False) -> str:
    if type(value) is not str or (not empty and not value) or "\x00" in value:
        raise AuditError(f"invalid {name} string")
    return value


def _report_path(value: object, name: str, *, basename: bool = False) -> str:
    path = _report_string(value, name)
    try:
        normalized, is_dir = _member_path(zipfile.ZipInfo(path))
    except (AuditError, ValueError) as exc:
        raise AuditError(f"invalid {name} path: {path!r}") from exc
    if is_dir or normalized != path or (basename and "/" in path):
        raise AuditError(f"invalid {name} path: {path!r}")
    return path


def _report_identity(value: object, name: str, *, member: bool = False) -> None:
    if type(value) is not dict:
        raise AuditError(f"invalid {name}")
    digest = value.get("sha256")
    size = value.get("bytes")
    if type(digest) is not str or not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise AuditError(f"invalid {name} sha256")
    if type(size) is not int or size <= 0 or (member and size > MAX_MEMBER_BYTES):
        raise AuditError(f"invalid {name} bytes")


def _report_strings(value: object, name: str, *, empty_items: bool = False) -> None:
    if type(value) is not list:
        raise AuditError(f"invalid {name} list")
    for item in value:
        _report_string(item, name, empty=empty_items)


def validate_report(report: object) -> None:
    """Validate a v1 inventory's shape and internal consistency without readelf."""
    data = _report_object(report, {"format", "schema_version", "archive", "expected_architecture",
                                   "readelf_version", "elfs", "limitations"}, "report")
    if data["format"] != "openrc-linux-abi-v1" or type(data["format"]) is not str:
        raise AuditError("invalid report format")
    if type(data["schema_version"]) is not int or data["schema_version"] != 1:
        raise AuditError("invalid report schema version")
    archive = _report_object(data["archive"], {"path", "sha256", "bytes"}, "archive")
    _report_path(archive["path"], "archive", basename=True)
    _report_identity(archive, "archive")
    architecture = _report_string(data["expected_architecture"], "expected architecture")
    if architecture not in MACHINES:
        raise AuditError("invalid expected architecture")
    version = _report_string(data["readelf_version"], "readelf version")
    if not version.startswith("GNU readelf") or "\n" in version or "\r" in version:
        raise AuditError("invalid readelf version")
    if (type(data["limitations"]) is not list
            or any(type(item) is not str for item in data["limitations"])
            or data["limitations"] != list(LIMITATIONS)):
        raise AuditError("invalid report limitations")
    elfs = data["elfs"]
    if type(elfs) is not list or not elfs:
        raise AuditError("invalid ELF inventory")

    paths: set[str] = set()
    total_size = 0
    for item in elfs:
        elf = _report_object(item, {"path", "sha256", "bytes", "architecture", "elf_class", "endianness",
                                    "os_abi", "interpreter", "needed", "rpath", "runpath",
                                    "required_versions", "max_required_versions", "gnu_stack", "gnu_properties",
                                    "notes_status"}, "ELF")
        path = _report_path(elf["path"], "ELF")
        if path in paths:
            raise AuditError(f"duplicate ELF path: {path!r}")
        paths.add(path)
        _report_identity(elf, "ELF", member=True)
        total_size += elf["bytes"]
        if total_size > MAX_TOTAL_BYTES:
            raise AuditError("ELF inventory exceeds total size limit")
        if type(elf["architecture"]) is not str or elf["architecture"] != architecture:
            raise AuditError("ELF architecture does not match report")
        if elf["elf_class"] != "ELF64" or type(elf["elf_class"]) is not str:
            raise AuditError("invalid ELF class")
        if elf["endianness"] != "little" or type(elf["endianness"]) is not str:
            raise AuditError("invalid ELF endianness")
        _report_string(elf["os_abi"], "OS/ABI")
        if elf["interpreter"] is not None:
            _report_string(elf["interpreter"], "interpreter")
        _report_strings(elf["needed"], "needed")
        _report_strings(elf["rpath"], "rpath", empty_items=True)
        _report_strings(elf["runpath"], "runpath", empty_items=True)
        _report_strings(elf["gnu_properties"], "GNU properties")
        if (type(elf["notes_status"]) is not str
                or elf["notes_status"] not in ("readelf_ok", "fdo_dlopen_unsupported")
                or (elf["notes_status"] == "fdo_dlopen_unsupported" and not _binutils_242(version))):
            raise AuditError("invalid ELF notes status")
        versions = _report_object(elf["required_versions"], set(FAMILIES), "required versions")
        maxima = _report_object(elf["max_required_versions"], set(FAMILIES), "maximum versions")
        for family in FAMILIES:
            values = versions[family]
            _report_strings(values, f"{family} versions")
            if any(not value.startswith(family + "_") or len(value) == len(family) + 1
                   or any(char.isspace() for char in value) for value in values):
                raise AuditError(f"invalid {family} version name")
            if values != sorted(set(values)):
                raise AuditError(f"unsorted or duplicate {family} versions")
            if maxima[family] is not None:
                _report_string(maxima[family], f"maximum {family} version")
        if maxima != _numeric_maxima(versions):
            raise AuditError("maximum versions do not match version needs")
        stack = _report_object(elf["gnu_stack"], {"present", "permissions", "executable"}, "GNU stack")
        if type(stack["present"]) is not bool:
            raise AuditError("invalid GNU stack presence")
        if stack["present"]:
            permissions = _report_string(stack["permissions"], "GNU stack permissions", empty=True)
            if (permissions not in ("", "R", "W", "E", "RW", "RE", "WE", "RWE")
                    or type(stack["executable"]) is not bool or stack["executable"] != ("E" in permissions)):
                raise AuditError("invalid GNU stack permissions or executable flag")
        elif stack["permissions"] is not None or stack["executable"] is not None:
            raise AuditError("absent GNU stack must have unknown permissions and executable flag")

    for path in paths:
        parts = path.split("/")
        if any("/".join(parts[:index]) in paths for index in range(1, len(parts))):
            raise AuditError(f"ELF file is a parent of another member: {path!r}")


def _archive_hash(stream: BinaryIO) -> tuple[str, int]:
    stream.seek(0)
    digest = hashlib.sha256()
    size = 0
    while True:
        chunk = stream.read(CHUNK_BYTES)
        if not chunk:
            break
        digest.update(chunk)
        size += len(chunk)
    return digest.hexdigest(), size


def audit_zip(path: Path, expected_architecture: str = "x86_64", readelf: str = "readelf") -> dict[str, object]:
    """Inventory all magic-detected ELFs in a ZIP; raise AuditError on failure."""
    if expected_architecture not in MACHINES:
        raise AuditError(f"unsupported architecture: {expected_architecture}")
    archive = Path(path)
    version = _readelf_version(readelf)
    elfs: list[dict[str, object]] = []
    try:
        with archive.open("rb") as source:
            before_hash, before_size = _archive_hash(source)
            source.seek(0)
            with zipfile.ZipFile(source) as bundle, tempfile.TemporaryDirectory(prefix="openrc-elf-audit-") as temporary:
                members = bundle.infolist()
                seen: dict[str, bool] = {}
                total_size = 0
                for info in members:
                    member_path, is_dir = _member_path(info)
                    if member_path in seen:
                        raise AuditError(f"duplicate ZIP member path: {member_path!r}")
                    seen[member_path] = is_dir
                    if info.file_size > MAX_MEMBER_BYTES:
                        raise AuditError(f"ZIP member exceeds size limit: {member_path!r}")
                    total_size += info.file_size
                    if total_size > MAX_TOTAL_BYTES:
                        raise AuditError("ZIP exceeds total uncompressed size limit")
                for member_path in seen:
                    parts = member_path.split("/")
                    for index in range(1, len(parts)):
                        parent = "/".join(parts[:index])
                        if parent in seen and not seen[parent]:
                            raise AuditError(f"ZIP file is a parent of another member: {parent!r}")

                temporary_elf = Path(temporary) / "payload.elf"
                for info in members:
                    member_path, is_dir = _member_path(info)
                    with bundle.open(info, "r") as member:
                        first = member.read(4)
                        candidate = not is_dir and first == b"\x7fELF"
                        digest = hashlib.sha256()
                        count = len(first)
                        if candidate:
                            digest.update(first)
                        with temporary_elf.open("wb") if candidate else _NullWriter() as extracted:
                            if candidate:
                                extracted.write(first)
                            while True:
                                chunk = member.read(CHUNK_BYTES)
                                if not chunk:
                                    break
                                count += len(chunk)
                                if count > info.file_size or count > MAX_MEMBER_BYTES:
                                    raise AuditError(f"ZIP member exceeds declared size: {member_path!r}")
                                if candidate:
                                    digest.update(chunk)
                                    extracted.write(chunk)
                        if count != info.file_size:
                            raise AuditError(f"ZIP member has an incorrect size: {member_path!r}")
                    if candidate:
                        elfs.append(_inspect_elf(temporary_elf, member_path, count, digest.hexdigest(),
                                                expected_architecture, readelf, version))
                if not elfs:
                    raise AuditError("ZIP contains no ELF files")
            after_hash, after_size = _archive_hash(source)
            if (before_hash, before_size) != (after_hash, after_size):
                raise AuditError("ZIP changed during audit")
    except (OSError, zipfile.BadZipFile, zipfile.LargeZipFile, EOFError, RuntimeError, NotImplementedError) as exc:
        raise AuditError(f"cannot inspect ZIP {archive}: {exc}") from exc

    report = {
        "format": "openrc-linux-abi-v1", "schema_version": 1,
        "archive": {"path": archive.name, "sha256": before_hash, "bytes": before_size},
        "expected_architecture": expected_architecture, "readelf_version": version,
        "elfs": sorted(elfs, key=lambda elf: str(elf["path"])),
        "limitations": list(LIMITATIONS),
    }
    validate_report(report)
    return report


class _NullWriter:
    """Context manager for non-ELF entries, which are read but never extracted."""

    def __enter__(self) -> _NullWriter:
        return self

    def __exit__(self, *args: object) -> None:
        pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="final Linux ZIP to inspect")
    parser.add_argument("--output", type=Path, required=True, help="new JSON report path")
    parser.add_argument("--architecture", choices=tuple(MACHINES), default="x86_64")
    args = parser.parse_args(argv)
    try:
        # Exclusive creation also rejects symlinks and a competing writer.
        if os.path.lexists(args.output):
            raise AuditError(f"output already exists: {args.output}")
        report = audit_zip(args.archive, expected_architecture=args.architecture)
        with args.output.open("x", encoding="utf-8", newline="\n") as output:
            json.dump(report, output, indent=2, ensure_ascii=False)
            output.write("\n")
    except (AuditError, OSError) as exc:
        print(f"ELF audit failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
