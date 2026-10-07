#!/usr/bin/env python3
"""Exercise the existing ZIP checker with non-executable synthetic metadata only.

The fixtures deliberately contain no valid executable code or cryptographic
signature. They show the checker's policy/scope, not a bypass of macOS trust.
"""

import hashlib
import json
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[5]
CHECKER = ROOT / "app/tests/check_macos_export.py"


def slice_bytes(cpu, flags):
    directory = struct.pack(">5I", 0xFADE0C02, 20, 0, flags, 0)
    blob = struct.pack(">5I", 0xFADE0CC0, 40, 1, 0, 20) + directory
    header = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 1, 16, 0, 0)
    return header + struct.pack("<4I", 0x1D, 16, 48, len(blob)) + blob


def fixture(flags):
    cpus = [0x01000007, 0x0100000C]
    slices = [slice_bytes(cpu, flags) for cpu in cpus]
    offset = 8 + 20 * len(slices)
    table = b""
    for cpu, data in zip(cpus, slices):
        table += struct.pack(">5I", cpu, 0, offset, len(data), 0)
        offset += len(data)
    return struct.pack(">2I", 0xCAFEBABE, len(slices)) + table + b"".join(slices)


def main():
    source = CHECKER.read_bytes()
    results = []
    with tempfile.TemporaryDirectory(prefix="openrc-mac-checker-") as temp:
        for label, flags, expected in [
            ("synthetic_adhoc_runtime", 0x10002, 0),
            ("synthetic_nonadhoc_runtime", 0x10000, 1),
        ]:
            archive = Path(temp) / (label + ".zip")
            info = zipfile.ZipInfo("Fixture.app/Contents/MacOS/Fixture")
            info.create_system = 3
            info.external_attr = 0o100755 << 16
            with zipfile.ZipFile(archive, "w") as package:
                package.writestr(info, fixture(flags))
            run = subprocess.run(
                [sys.executable, str(CHECKER), str(archive)],
                capture_output=True, text=True, timeout=10,
            )
            assert run.returncode == expected, run.stdout + run.stderr
            results.append({"case": label, "flags": hex(flags),
                            "exit_code": run.returncode, "expected_exit_code": expected,
                            "stdout": run.stdout, "stderr": run.stderr})
    assert source == CHECKER.read_bytes(), "Checker changed during probe; repeat on frozen source"
    result = {
        "format": "openrc-macos-checker-contract v1", "date": "2026-10-07",
        "checker": str(CHECKER.relative_to(ROOT)),
        "checker_sha256": hashlib.sha256(source).hexdigest(),
        "passed": True, "cases": results,
        "scope": "Python checker executed on synthetic ZIP metadata in temporary files. "
                 "No valid native executable/signature exists in either fixture. "
                 "No macOS execution, signature verification or trust bypass tested. "
                 "Acceptance demonstrates structural-only scope; rejection demonstrates ad-hoc-only policy.",
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
