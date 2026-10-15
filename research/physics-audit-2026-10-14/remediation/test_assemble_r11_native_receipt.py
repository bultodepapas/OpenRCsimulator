#!/usr/bin/env python3
"""Focused tests for the offline R11 native receipt assembler."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from assemble_r11_native_receipt import (
    BACKEND,
    BACKEND_VERSION,
    FORMAT,
    ABI_VERSION,
    SOLVER_VERSION,
    ReceiptError,
    assemble_receipt,
)


SOURCE_SHA256 = "e2ae0a5ffebc8d81636302d66238348035ee92bf51d2f40965db7053bb251541"


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


class ReceiptAssemblerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.win_bytes = b"reviewed Windows native fixture"
        self.linux_bytes = b"reviewed Linux native fixture"
        self.win_binary = self.root / "openrc_ground_vehicle.dll"
        self.linux_binary = self.root / "libopenrc_ground_vehicle.so"
        self.win_binary.write_bytes(self.win_bytes)
        self.linux_binary.write_bytes(self.linux_bytes)
        self.windows_toolchain = sha256_bytes(b"retained Windows toolchain")
        self.linux_toolchain = sha256_bytes(b"retained Linux toolchain")
        self.windows_row = self._row("windows", self.windows_toolchain, self.win_bytes)
        self.linux_row = self._row("linux", self.linux_toolchain, self.linux_bytes)
        self.windows_receipt = self.root / "windows-row.json"
        self.windows_receipt.write_text(json.dumps(self.windows_row), encoding="utf-8")
        self.linux_receipt = self.root / "linux-aggregate.json"
        self.linux_receipt.write_text(
            json.dumps(
                {
                    "format": FORMAT,
                    "backend": BACKEND,
                    "backend_version": BACKEND_VERSION,
                    "abi_version": ABI_VERSION,
                    "solver_version": SOLVER_VERSION,
                    "platforms": {"linux": self.linux_row},
                }
            ),
            encoding="utf-8",
        )
        self.output = self.root / "out" / "build-receipt.json"

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def _row(platform: str, toolchain_sha256: str, binary: bytes) -> dict[str, object]:
        return {
            "platform": platform,
            "architecture": "x86_64",
            "backend": BACKEND,
            "backend_version": BACKEND_VERSION,
            "abi_version": ABI_VERSION,
            "solver_version": SOLVER_VERSION,
            "source_sha256": SOURCE_SHA256,
            "toolchain_sha256": toolchain_sha256,
            "binary_sha256": sha256_bytes(binary),
            "toolchain": {"fixture_label": f"retained {platform} toolchain"},
            "floating_point_flags": ["strict-fixture"],
            "exception_flags": ["exceptions-fixture"],
        }

    def _assemble(self) -> dict[str, object]:
        return assemble_receipt(
            self.windows_receipt,
            self.win_binary,
            self.linux_receipt,
            self.linux_binary,
            SOURCE_SHA256,
            self.windows_toolchain,
            self.linux_toolchain,
            self.output,
        )

    def test_valid_rows_merge_without_rewriting_platform_identity(self) -> None:
        aggregate = self._assemble()
        self.assertEqual(list(aggregate["platforms"]), ["linux", "windows"])
        self.assertEqual(aggregate["platforms"]["windows"], self.windows_row)
        self.assertEqual(aggregate["platforms"]["linux"], self.linux_row)
        self.assertEqual(json.loads(self.output.read_text(encoding="utf-8")), aggregate)

    def test_mismatched_source_is_rejected(self) -> None:
        self.windows_row["source_sha256"] = "0" * 64
        self.windows_receipt.write_text(json.dumps(self.windows_row), encoding="utf-8")
        with self.assertRaisesRegex(ReceiptError, "source SHA-256"):
            self._assemble()
        self.assertFalse(self.output.exists())

    def test_mismatched_binary_bytes_are_rejected(self) -> None:
        self.win_binary.write_bytes(b"different Windows bytes")
        with self.assertRaisesRegex(ReceiptError, "binary SHA-256"):
            self._assemble()
        self.assertFalse(self.output.exists())

    def test_boolean_abi_version_is_rejected(self) -> None:
        self.windows_row["abi_version"] = True
        self.windows_receipt.write_text(json.dumps(self.windows_row), encoding="utf-8")
        with self.assertRaisesRegex(ReceiptError, "abi_version must be integer"):
            self._assemble()
        self.assertFalse(self.output.exists())

    def test_nonfinite_metadata_cannot_be_serialized_as_json(self) -> None:
        self.windows_row["toolchain"]["unexpected_number"] = float("nan")
        self.windows_receipt.write_text(json.dumps(self.windows_row), encoding="utf-8")
        with self.assertRaisesRegex(ReceiptError, "non-JSON numeric value"):
            self._assemble()
        self.assertFalse(self.output.exists())

    def test_changed_toolchain_identity_is_rejected(self) -> None:
        with self.assertRaisesRegex(ReceiptError, "toolchain SHA-256"):
            assemble_receipt(
                self.windows_receipt,
                self.win_binary,
                self.linux_receipt,
                self.linux_binary,
                SOURCE_SHA256,
                "f" * 64,
                self.linux_toolchain,
                self.output,
            )
        self.assertFalse(self.output.exists())

    def test_existing_output_is_never_overwritten(self) -> None:
        self.output.parent.mkdir(parents=True)
        self.output.write_text("sentinel", encoding="utf-8")
        with self.assertRaisesRegex(ReceiptError, "refusing to overwrite"):
            self._assemble()
        self.assertEqual(self.output.read_text(encoding="utf-8"), "sentinel")


if __name__ == "__main__":
    unittest.main(verbosity=2)
