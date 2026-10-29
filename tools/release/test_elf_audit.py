#!/usr/bin/env python3
"""Focused parser, ZIP safety and compiler-built ELF inventory tests."""

from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import warnings
import zipfile

if __package__:
    from . import elf_audit
else:
    import elf_audit


class ParserTests(unittest.TestCase):
    def test_version_needs_excludes_definitions_and_sorts_numerically(self) -> None:
        output = """\
Version symbols section '.gnu.version' contains 3 entries:
  000:  2 (GLIBCXX_900.0) 3 (GLIBC_800.0)

Version definition section '.gnu.version_d' contains 2 entries:
  0x00: Rev: 1  Flags: none  Index: 2  Cnt: 1  Name: GLIBC_999.99
  0x20: Rev: 1  Flags: none  Index: 3  Cnt: 1  Name: GLIBCXX_999.99

Version needs section '.gnu.version_r' contains 2 entries:
 Addr: 0x0  Offset: 0x0  Link: 1 (.dynstr)
  000000: Version: 1  File: libc.so.6  Cnt: 3
  0x0010:   Name: GLIBC_2.9  Flags: none  Version: 3
  0x0020:   Name: GLIBC_2.10  Flags: none  Version: 4
  0x0030:   Name: GLIBC_PRIVATE  Flags: none  Version: 5
  0x0040: Version: 1  File: libstdc++.so.6  Cnt: 3
  0x0050:   Name: GLIBCXX_3.4.9  Flags: none  Version: 6
  0x0060:   Name: GLIBCXX_3.4.10  Flags: none  Version: 7
  0x0070:   Name: CXXABI_1.3.13  Flags: none  Version: 8

Displaying notes found in: .note.gnu.property
"""
        versions, maxima, files = elf_audit._versions(output)
        self.assertEqual(files, 2)
        self.assertEqual(versions["GLIBC"], ["GLIBC_2.10", "GLIBC_2.9", "GLIBC_PRIVATE"])
        self.assertEqual(versions["GLIBCXX"], ["GLIBCXX_3.4.10", "GLIBCXX_3.4.9"])
        self.assertEqual(versions["CXXABI"], ["CXXABI_1.3.13"])
        self.assertEqual(maxima, {"GLIBC": "GLIBC_2.10", "GLIBCXX": "GLIBCXX_3.4.10", "CXXABI": "CXXABI_1.3.13"})

    def test_incomplete_needs_are_rejected(self) -> None:
        output = """\
Version needs section '.gnu.version_r' contains 1 entry:
 Addr: 0x0  Offset: 0x0  Link: 1 (.dynstr)
  000000: Version: 1  File: libc.so.6  Cnt: 2
  0x0010:   Name: GLIBC_2.9  Flags: none  Version: 3
"""
        with self.assertRaisesRegex(elf_audit.AuditError, "incomplete version needs"):
            elf_audit._versions(output)
        with self.assertRaisesRegex(elf_audit.AuditError, "unrecognized version needs section"):
            elf_audit._versions("Version needs section malformed\n")

    def test_unparsed_dynamic_tags_are_rejected(self) -> None:
        with self.assertRaisesRegex(elf_audit.AuditError, "unrecognized dynamic tag"):
            elf_audit._dynamic("unexpected output (NEEDED) Shared library: [libc.so.6]")
        with self.assertRaisesRegex(elf_audit.AuditError, "incomplete or ambiguous"):
            elf_audit._dynamic("  0x06fffffe (VERNEED) 0x1234\n")

    def test_stack_and_multiline_properties(self) -> None:
        self.assertEqual(elf_audit._stack("no program headers"),
                         {"present": False, "permissions": None, "executable": None})
        line = "  GNU_STACK 0x0 0x0 0x0 0x0 0x0 RWE 0x10"
        self.assertEqual(elf_audit._stack(line),
                         {"present": True, "permissions": "RWE", "executable": True})
        notes = """\
  GNU 0x00000020 NT_GNU_PROPERTY_TYPE_0 Properties: x86 ISA needed: x86-64-v2
      x86 ISA used: x86-64-v3

  GNU 0x00000014 NT_GNU_BUILD_ID Build ID: abcdef
"""
        self.assertEqual(elf_audit._properties(notes),
                         ["x86 ISA needed: x86-64-v2", "x86 ISA used: x86-64-v3"])

    def test_readelf_242_fallback_only_accepts_fdo_dlopen_note(self) -> None:
        self.assertTrue(elf_audit._binutils_242("GNU readelf 2.42"))
        self.assertFalse(elf_audit._binutils_242("GNU readelf 2.42.1"))
        sections = """\
  [ 1] .note.gnu.property NOTE 00000000 0000 000020 00 A 0 0 8
  [ 2] .note.dlopen NOTE 00000000 0020 000020 00 A 0 0 4
"""
        notes = """\
Displaying notes found in: .note.gnu.property
  Owner                Data size \tDescription
  GNU                  0x00000010\tNT_GNU_PROPERTY_TYPE_0\t      Properties: x86 ISA needed: x86-64-baseline

Displaying notes found in: .note.dlopen
  Owner                Data size \tDescription
  FDO                  0x00000003\tUnknown note type: (0x407c0c0a)\t
"""
        self.assertTrue(elf_audit._only_unsupported_fdo_notes(notes, sections))
        self.assertFalse(elf_audit._only_unsupported_fdo_notes(notes, sections + "  [ 3] .note.empty NOTE 0 0 0 0 A 0 0 4\n"))
        self.assertFalse(elf_audit._only_unsupported_fdo_notes(notes.replace("FDO  ", "FDOX "), sections))
        self.assertFalse(elf_audit._only_unsupported_fdo_notes(notes.replace("0x407c0c0a", "0x407c0c0b"), sections))
        self.assertFalse(elf_audit._only_unsupported_fdo_notes(notes.replace("GNU  ", "OTHER"), sections))
        self.assertFalse(elf_audit._only_unsupported_fdo_notes(notes.replace("NT_GNU_PROPERTY_TYPE_0", "NT_GNU_GOLD_VERSION"), sections))
        self.assertFalse(elf_audit._only_unsupported_fdo_notes(notes + "other note error", sections))
        result = subprocess.CompletedProcess([], 1, notes, "")
        sections_result = subprocess.CompletedProcess([], 0, sections, "")
        with mock.patch.object(elf_audit, "_run_readelf", side_effect=[result, sections_result]):
            self.assertEqual(elf_audit._readelf_notes("readelf", Path("payload"), "GNU readelf (GNU Binutils) 2.42"),
                             (notes, "fdo_dlopen_unsupported"))
        for result, version in [
            (subprocess.CompletedProcess([], 1, notes, "warning"), "GNU readelf (GNU Binutils) 2.42"),
            (subprocess.CompletedProcess([], 2, notes, ""), "GNU readelf (GNU Binutils) 2.42"),
            (subprocess.CompletedProcess([], 1, notes, ""), "GNU readelf (GNU Binutils) 2.43"),
            (subprocess.CompletedProcess([], 1, notes.replace("x86-64-baseline", "<corrupt length>"), ""),
             "GNU readelf (GNU Binutils) 2.42"),
            (subprocess.CompletedProcess([], 0, notes.replace("x86-64-baseline", "<corrupt length>"), ""),
             "GNU readelf (GNU Binutils) 2.42"),
        ]:
            with self.subTest(result=result, version=version), mock.patch.object(elf_audit, "_run_readelf", return_value=result):
                with self.assertRaises(elf_audit.AuditError):
                    elf_audit._readelf_notes("readelf", Path("payload"), version)


class ReportValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.report = {
            "format": "openrc-linux-abi-v1", "schema_version": 1,
            "archive": {"path": "release.zip", "sha256": "a" * 64, "bytes": 512},
            "expected_architecture": "x86_64", "readelf_version": "GNU readelf (GNU Binutils) 2.42",
            "elfs": [{
                "path": "native/library.so", "sha256": "b" * 64, "bytes": 400,
                "architecture": "x86_64", "elf_class": "ELF64", "endianness": "little",
                "os_abi": "UNIX - System V", "interpreter": None, "needed": ["libc.so.6"],
                "rpath": [], "runpath": [""],
                "required_versions": {
                    "GLIBC": ["GLIBC_2.10", "GLIBC_2.9", "GLIBC_PRIVATE"],
                    "GLIBCXX": ["GLIBCXX_3.4.10", "GLIBCXX_3.4.9"],
                    "CXXABI": ["CXXABI_1.3", "CXXABI_FLOAT128"],
                },
                "max_required_versions": {"GLIBC": "GLIBC_2.10", "GLIBCXX": "GLIBCXX_3.4.10", "CXXABI": "CXXABI_1.3"},
                "gnu_stack": {"present": True, "permissions": "RW", "executable": False},
                "gnu_properties": ["x86 ISA needed: x86-64-baseline"],
                "notes_status": "readelf_ok",
            }],
            "limitations": [
                "GNU properties do not certify the complete CPU instruction set or hardware compatibility.",
                "Dependencies loaded dynamically with dlopen and their closure are not certified.",
                "Graphics, audio, input and other driver closure is not certified.",
                "Static ELF metadata does not establish distribution support or successful execution.",
            ],
        }

    def assert_invalid(self, path: tuple[object, ...], value: object) -> None:
        report = copy.deepcopy(self.report)
        node = report
        for key in path[:-1]:
            node = node[key]
        node[path[-1]] = value
        with self.assertRaises(elf_audit.AuditError):
            elf_audit.validate_report(report)

    def test_valid_report_does_not_invoke_readelf(self) -> None:
        with mock.patch.object(elf_audit.subprocess, "run", side_effect=AssertionError("external command")):
            self.assertIsNone(elf_audit.validate_report(self.report))
            without_stack = copy.deepcopy(self.report)
            without_stack["elfs"][0]["gnu_stack"] = {"present": False, "permissions": None, "executable": None}
            self.assertIsNone(elf_audit.validate_report(without_stack))
            without_stack["elfs"][0]["notes_status"] = "fdo_dlopen_unsupported"
            self.assertIsNone(elf_audit.validate_report(without_stack))
            without_stack["readelf_version"] = "GNU readelf (GNU Binutils) 2.43"
            with self.assertRaises(elf_audit.AuditError):
                elf_audit.validate_report(without_stack)

    def test_rejects_unexpected_missing_and_non_object_records(self) -> None:
        for value in (None, [], {}, True):
            with self.subTest(value=value), self.assertRaises(elf_audit.AuditError):
                elf_audit.validate_report(value)
        for path, value in [
            (("format",), "other"), (("schema_version",), True), (("schema_version",), 1.0),
            (("elfs",), [None]), (("elfs",), []), (("elfs",), {}),
            (("readelf_version",), "LLVM readelf"), (("readelf_version",), "GNU readelf\nextra"),
            (("limitations",), ["Runtime closure certified"]),
        ]:
            with self.subTest(path=path, value=value):
                self.assert_invalid(path, value)
        missing = copy.deepcopy(self.report)
        del missing["elfs"][0]["gnu_stack"]
        with self.assertRaises(elf_audit.AuditError):
            elf_audit.validate_report(missing)
        extra = copy.deepcopy(self.report)
        extra["elfs"][0]["driver_certified"] = True
        with self.assertRaises(elf_audit.AuditError):
            elf_audit.validate_report(extra)
        extra = copy.deepcopy(self.report)
        extra["closure_certified"] = True
        with self.assertRaises(elf_audit.AuditError):
            elf_audit.validate_report(extra)

    def test_rejects_unsafe_identity_and_wrong_architecture(self) -> None:
        for path, value in [
            (("archive", "path"), "../release.zip"), (("archive", "path"), "sub/release.zip"),
            (("archive", "path"), "C:\\release.zip"), (("archive", "path"), "release\0.zip"),
            (("archive", "sha256"), "A" * 64), (("archive", "sha256"), "g" * 64),
            (("archive", "bytes"), True), (("archive", "bytes"), 0), (("archive", "bytes"), 512.0),
            (("elfs", 0, "path"), "native/../escape"), (("elfs", 0, "path"), "/absolute"),
            (("elfs", 0, "path"), "native/"), (("elfs", 0, "sha256"), "bad"),
            (("elfs", 0, "bytes"), False), (("elfs", 0, "bytes"), -1),
            (("elfs", 0, "bytes"), elf_audit.MAX_MEMBER_BYTES + 1),
            (("expected_architecture",), "mips"), (("elfs", 0, "architecture"), "arm64"),
            (("elfs", 0, "elf_class"), "ELF32"), (("elfs", 0, "endianness"), "big"),
        ]:
            with self.subTest(path=path, value=value):
                self.assert_invalid(path, value)
        duplicate = copy.deepcopy(self.report)
        duplicate["elfs"].append(copy.deepcopy(duplicate["elfs"][0]))
        with self.assertRaises(elf_audit.AuditError):
            elf_audit.validate_report(duplicate)
        duplicate["elfs"][1]["path"] += "/child"
        with self.assertRaises(elf_audit.AuditError):
            elf_audit.validate_report(duplicate)

    def test_rejects_inconsistent_version_and_stack_metadata(self) -> None:
        for path, value in [
            (("elfs", 0, "required_versions"), []),
            (("elfs", 0, "required_versions", "GLIBC"), ["GLIBCXX_3.4"]),
            (("elfs", 0, "required_versions", "GLIBC"), ["GLIBC_"]),
            (("elfs", 0, "required_versions", "GLIBC"), ["GLIBC_2.9", "GLIBC_2.10"]),
            (("elfs", 0, "required_versions", "GLIBC"), ["GLIBC_2.10", "GLIBC_2.10"]),
            (("elfs", 0, "max_required_versions", "GLIBC"), "GLIBC_2.9"),
            (("elfs", 0, "max_required_versions", "GLIBC"), None),
            (("elfs", 0, "gnu_stack", "present"), 1),
            (("elfs", 0, "gnu_stack", "executable"), 0),
            (("elfs", 0, "gnu_stack", "executable"), True),
            (("elfs", 0, "gnu_stack", "permissions"), "WR"),
            (("elfs", 0, "gnu_stack"), {"present": False, "permissions": "", "executable": False}),
            (("elfs", 0, "interpreter"), 1), (("elfs", 0, "needed"), [None]),
            (("elfs", 0, "gnu_properties"), [""]),
            (("elfs", 0, "notes_status"), "complete"),
        ]:
            with self.subTest(path=path, value=value):
                self.assert_invalid(path, value)


LINUX_TOOLS = sys.platform.startswith("linux") and shutil.which("cc") and shutil.which("readelf")
HOST_ARCH = {"x86_64": "x86_64", "amd64": "x86_64", "aarch64": "arm64", "arm64": "arm64"}.get(platform.machine().lower())


@unittest.skipUnless(LINUX_TOOLS and HOST_ARCH, "requires Linux, GNU readelf, cc, and an x86_64 or arm64 host")
class ArchiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.compilation = tempfile.TemporaryDirectory(prefix="openrc-elf-fixtures-")
        root = Path(cls.compilation.name)
        source = root / "fixture.c"
        source.write_text('#include <stdio.h>\nint main(void) { return puts("fixture") < 0; }\n', encoding="utf-8")
        shared = root / "shared.c"
        shared.write_text('#include <stdio.h>\nint exported(void) { return puts("fixture"); }\n', encoding="utf-8")
        script = root / "versions.map"
        script.write_text('GLIBC_999.99 { global: exported; local: *; };\n', encoding="utf-8")
        cls.executable = root / "fixture"
        cls.shared = root / "fixture.so"
        subprocess.run(["cc", str(source), "-Wl,-z,execstack", "-Wl,-rpath,$ORIGIN/lib path", "-o", str(cls.executable)], check=True)
        subprocess.run(["cc", "-shared", "-fPIC", str(shared), f"-Wl,--version-script={script}", "-o", str(cls.shared)], check=True)
        note = "@note" if HOST_ARCH == "x86_64" else "%note"
        progbits = "@progbits" if HOST_ARCH == "x86_64" else "%progbits"
        cls.property_type = 0xc0008002 if HOST_ARCH == "x86_64" else 0xc0000000
        assembly = root / "notes.S"
        assembly.write_text(f'''\
.section .note.dlopen,"a",{note}
.balign 4
.long 4, 3, 0x407c0c0a
.asciz "FDO"
.asciz "[]"
.balign 4
.section .note.openrc_test,"a",{note}
.balign 8
.long 4, 16, 5
.asciz "GNU"
.long {cls.property_type}, 4, 2, 0
.section .note.GNU-stack,"",{progbits}
''', encoding="utf-8")
        cls.fdo = root / "fixture-fdo"
        subprocess.run(["cc", str(source), str(assembly), "-o", str(cls.fdo)], check=True)
        cls.cpp = None
        if shutil.which("c++"):
            cpp_source = root / "fixture.cpp"
            cpp_source.write_text('#include <iostream>\n#include <stdexcept>\nint main(int n, char **v) { std::cout << v[0]; if (n > 1) throw std::runtime_error(v[1]); return 0; }\n', encoding="utf-8")
            cls.cpp = root / "cpp-fixture"
            subprocess.run(["c++", str(cpp_source), "-o", str(cls.cpp)], check=True)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.compilation.cleanup()

    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory(prefix="openrc-elf-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.archive = self.root / "release with spaces.zip"

    def write_zip(self, members: list[tuple[object, bytes]]) -> None:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(self.archive, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                for name, data in members:
                    archive.writestr(name, data)

    def audit(self) -> dict[str, object]:
        return elf_audit.audit_zip(self.archive, expected_architecture=HOST_ARCH)

    def test_every_elf_by_magic_metadata_and_immutable_zip(self) -> None:
        program = self.executable.read_bytes()
        shared = self.shared.read_bytes()
        self.write_zip([
            ("spaced folder/program with spaces", program),
            ("native/not-a-library.txt", shared),
            ("decoy.so", b"not ELF\x7fELF"),
            ("empty", b""),
        ])
        original = self.archive.read_bytes()
        with mock.patch.object(elf_audit, "validate_report", wraps=elf_audit.validate_report) as validator:
            report = self.audit()
            validator.assert_called_once_with(report)
        self.assertEqual(self.archive.read_bytes(), original)
        self.assertEqual(report["format"], "openrc-linux-abi-v1")
        self.assertEqual(report["archive"], {"path": self.archive.name, "bytes": len(original),
                                             "sha256": hashlib.sha256(original).hexdigest()})
        self.assertIn("GNU readelf", report["readelf_version"])
        records = {entry["path"]: entry for entry in report["elfs"]}
        self.assertEqual(set(records), {"spaced folder/program with spaces", "native/not-a-library.txt"})
        for path, data in (("spaced folder/program with spaces", program), ("native/not-a-library.txt", shared)):
            self.assertEqual(records[path]["bytes"], len(data))
            self.assertEqual(records[path]["sha256"], hashlib.sha256(data).hexdigest())
            self.assertEqual(records[path]["architecture"], HOST_ARCH)
            self.assertIsInstance(records[path]["gnu_properties"], list)
            self.assertIn("libc.so.6", records[path]["needed"])
        executable = records["spaced folder/program with spaces"]
        self.assertTrue(executable["interpreter"])
        self.assertIn("$ORIGIN/lib path", executable["rpath"] + executable["runpath"])
        self.assertEqual(executable["gnu_stack"]["permissions"], "RWE")
        self.assertTrue(executable["gnu_stack"]["executable"])
        library = records["native/not-a-library.txt"]
        self.assertIsNone(library["interpreter"])
        self.assertNotIn("GLIBC_999.99", library["required_versions"]["GLIBC"])
        self.assertTrue(library["required_versions"]["GLIBC"])
        self.assertNotEqual(library["max_required_versions"]["GLIBC"], "GLIBC_999.99")
        self.assertIn("dlopen", " ".join(report["limitations"]))

    def test_real_cpp_needs(self) -> None:
        if self.cpp is None:
            self.skipTest("C++ compiler is unavailable")
        self.write_zip([("cpp", self.cpp.read_bytes())])
        versions = self.audit()["elfs"][0]["required_versions"]
        self.assertTrue(versions["GLIBCXX"])
        self.assertTrue(versions["CXXABI"])

    def test_fdo_dlopen_note_and_other_corrupt_notes(self) -> None:
        original = self.fdo.read_bytes()
        self.write_zip([("app", original)])
        row = self.audit()["elfs"][0]
        readelf_version = elf_audit._readelf_version("readelf")
        expected = "fdo_dlopen_unsupported" if elf_audit._binutils_242(readelf_version) else "readelf_ok"
        self.assertEqual(row["notes_status"], expected)
        self.assertTrue(row["gnu_properties"])

        # Damage the FDO descriptor length on a disposable compiled fixture.
        fdo_marker = struct.pack("<III", 4, 3, 0x407c0c0a) + b"FDO\0[]\0\0"
        self.assertEqual(original.count(fdo_marker), 1)
        malformed = bytearray(original)
        offset = original.index(fdo_marker)
        malformed[offset + 4:offset + 8] = struct.pack("<I", 0xffffffff)
        self.write_zip([("app", bytes(malformed))])
        with self.assertRaises(elf_audit.AuditError):
            self.audit()

        # GNU readelf can print corrupt GNU properties only to stdout, while
        # the unrelated unknown FDO note already causes its nonzero status.
        property_marker = struct.pack("<III", 4, 16, 5) + b"GNU\0" + struct.pack("<IIII", self.property_type, 4, 2, 0)
        self.assertEqual(original.count(property_marker), 1)
        malformed = bytearray(original)
        offset = original.index(property_marker)
        malformed[offset + 20:offset + 24] = struct.pack("<I", 0xffff)
        mutated = self.root / "malformed-note"
        mutated.write_bytes(malformed)
        if elf_audit._binutils_242(readelf_version):
            result = subprocess.run(["readelf", "-W", "-n", str(mutated)], capture_output=True, text=True,
                                    env={**os.environ, "LC_ALL": "C"})
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stderr, "")
            self.assertIn("<corrupt", result.stdout.lower())
        self.write_zip([("app", bytes(malformed))])
        with self.assertRaises(elf_audit.AuditError):
            self.audit()

    def test_wrong_architecture_rejected(self) -> None:
        self.write_zip([("app", self.executable.read_bytes())])
        other_arch = "arm64" if HOST_ARCH == "x86_64" else "x86_64"
        with self.assertRaisesRegex(elf_audit.AuditError, "wrong ELF architecture"):
            elf_audit.audit_zip(self.archive, expected_architecture=other_arch)

    def test_mutated_and_truncated_elf_rejected(self) -> None:
        broken = self.executable.read_bytes()[:24]
        self.write_zip([("broken", broken)])
        with self.assertRaises(elf_audit.AuditError):
            self.audit()
        broken = bytearray(self.executable.read_bytes())
        broken[40:48] = b"\xff" * 8  # e_shoff beyond the end of the file
        self.write_zip([("broken", bytes(broken))])
        with self.assertRaises(elf_audit.AuditError):
            self.audit()

    def test_sectionless_elf_cannot_silently_hide_version_needs(self) -> None:
        broken = bytearray(self.executable.read_bytes())
        broken[40:48] = b"\0" * 8  # e_shoff
        broken[60:64] = b"\0" * 4  # e_shnum and e_shstrndx
        self.write_zip([("sectionless", bytes(broken))])
        with self.assertRaises(elf_audit.AuditError):
            self.audit()

    def test_unsafe_paths_duplicate_and_symlink_rejected(self) -> None:
        program = self.executable.read_bytes()
        for name in ("../escape", "/absolute", "C:/drive", "folder/../file", "folder\\file", "folder//file", "./file"):
            with self.subTest(name=name):
                self.write_zip([("app", program), (name, b"not ELF")])
                with self.assertRaisesRegex(elf_audit.AuditError, "unsafe ZIP member"):
                    self.audit()
        self.write_zip([("app", program), ("app", program)])
        with self.assertRaisesRegex(elf_audit.AuditError, "duplicate"):
            self.audit()
        self.write_zip([("app", program), ("app/child", b"nested")])
        with self.assertRaisesRegex(elf_audit.AuditError, "parent"):
            self.audit()
        link = zipfile.ZipInfo("symbolic")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        self.write_zip([("app", program), (link, b"app")])
        with self.assertRaisesRegex(elf_audit.AuditError, "symlink"):
            self.audit()

    def test_empty_inventory_and_size_limits_rejected(self) -> None:
        self.write_zip([("readme", b"text")])
        with self.assertRaisesRegex(elf_audit.AuditError, "no ELF"):
            self.audit()
        self.write_zip([("app", self.executable.read_bytes())])
        with mock.patch.object(elf_audit, "MAX_MEMBER_BYTES", 4):
            with self.assertRaisesRegex(elf_audit.AuditError, "member exceeds size"):
                self.audit()
        with mock.patch.object(elf_audit, "MAX_TOTAL_BYTES", 4):
            with self.assertRaisesRegex(elf_audit.AuditError, "total uncompressed size"):
                self.audit()

    def test_cli_writes_new_report_and_refuses_existing_output(self) -> None:
        self.write_zip([("app", self.executable.read_bytes())])
        report_path = self.root / "report with spaces.json"
        command = [sys.executable, str(Path(elf_audit.__file__)), str(self.archive), "--output", str(report_path),
                   "--architecture", HOST_ARCH]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        original = report_path.read_bytes()
        self.assertEqual(json.loads(original)["archive"]["path"], self.archive.name)
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already exists", result.stderr)
        self.assertEqual(report_path.read_bytes(), original)
        if hasattr(os, "symlink"):
            broken_link = self.root / "broken-link.json"
            broken_link.symlink_to(self.root / "does-not-exist")
            command[command.index(str(report_path))] = str(broken_link)
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(broken_link.is_symlink())
            self.assertFalse((self.root / "does-not-exist").exists())


if __name__ == "__main__":
    unittest.main()
