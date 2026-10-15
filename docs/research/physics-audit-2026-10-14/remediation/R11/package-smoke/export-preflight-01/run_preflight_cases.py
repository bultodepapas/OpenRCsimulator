#!/usr/bin/env python3
"""Exercise the exact export.sh receipt preflight against retained package inputs."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    if len(sys.argv) != 5:
        raise SystemExit("usage: run_preflight_cases.py RECEIPT LINUX_SO WINDOWS_DLL OUTPUT_DIR")
    receipt_path, linux_path, windows_path, output_dir = map(Path, sys.argv[1:])
    output_dir.mkdir(parents=True, exist_ok=False)
    fixtures = output_dir / "fixtures"
    fixtures.mkdir()
    preflight = Path(__file__).with_name("preflight.py")
    base_receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    cases: list[tuple[str, Path, Path, Path, int, str]] = []
    cases.append(("positive_merged_receipt", receipt_path, linux_path, windows_path, 0, '"format": "openrc-native-export-artifacts-v1"'))

    missing_windows = json.loads(json.dumps(base_receipt))
    missing_windows["platforms"].pop("windows")
    missing_windows_path = fixtures / "missing-windows-row.json"
    missing_windows_path.write_text(json.dumps(missing_windows, indent=2) + "\n", encoding="utf-8")
    cases.append(("missing_windows_row", missing_windows_path, linux_path, windows_path, 1, "lacks the windows platform row"))

    boolean_abi = json.loads(json.dumps(base_receipt))
    boolean_abi["platforms"]["windows"]["abi_version"] = True
    boolean_abi_path = fixtures / "boolean-windows-abi.json"
    boolean_abi_path.write_text(json.dumps(boolean_abi, indent=2) + "\n", encoding="utf-8")
    cases.append(("boolean_windows_abi", boolean_abi_path, linux_path, windows_path, 1, "non-integer or unsupported ABI version"))

    source_mismatch = json.loads(json.dumps(base_receipt))
    source_mismatch["platforms"]["windows"]["source_sha256"] = "0" * 64
    source_mismatch_path = fixtures / "windows-source-mismatch.json"
    source_mismatch_path.write_text(json.dumps(source_mismatch, indent=2) + "\n", encoding="utf-8")
    cases.append(("windows_source_mismatch", source_mismatch_path, linux_path, windows_path, 1, "disagrees with the shared source identity"))

    envelope_source_mismatch = json.loads(json.dumps(base_receipt))
    envelope_source_mismatch["source_sha256"] = "0" * 64
    envelope_source_mismatch_path = fixtures / "envelope-source-mismatch.json"
    envelope_source_mismatch_path.write_text(json.dumps(envelope_source_mismatch, indent=2) + "\n", encoding="utf-8")
    cases.append(("envelope_source_mismatch", envelope_source_mismatch_path, linux_path, windows_path, 1, "disagrees with the shared source identity"))

    corrupted_windows = fixtures / "windows-binary-corrupted.dll"
    binary_bytes = bytearray(windows_path.read_bytes())
    if not binary_bytes:
        raise SystemExit("Windows native binary is empty")
    binary_bytes[-1] ^= 1
    corrupted_windows.write_bytes(binary_bytes)
    cases.append(("windows_binary_mismatch", receipt_path, linux_path, corrupted_windows, 1, "differs from its receipt"))

    inputs = {
        "preflight_sha256": sha256(preflight),
        "receipt_sha256": sha256(receipt_path),
        "linux_binary_sha256": sha256(linux_path),
        "windows_binary_sha256": sha256(windows_path),
    }
    results = []
    for label, case_receipt, case_linux, case_windows, expected_exit, expected_text in cases:
        completed = subprocess.run(
            [sys.executable, str(preflight), str(case_receipt), str(case_linux), str(case_windows)],
            capture_output=True,
            text=True,
            check=False,
        )
        output = completed.stdout + completed.stderr
        passed = completed.returncode == expected_exit and expected_text in output
        results.append({
            "case": label,
            "receipt": str(case_receipt),
            "linux_binary": str(case_linux),
            "windows_binary": str(case_windows),
            "exit_code": completed.returncode,
            "expected_exit_code": expected_exit,
            "expected_output": expected_text,
            "stdout": completed.stdout.strip(),
            "stderr": completed.stderr.strip(),
            "passed": passed,
        })

    report = {
        "format": "openrc-r11-native-export-preflight-cases-v1",
        "inputs": inputs,
        "case_count": len(results),
        "passed": all(result["passed"] for result in results),
        "cases": results,
    }
    report_path = output_dir / "results.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
