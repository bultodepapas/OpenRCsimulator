#!/usr/bin/env python3
"""Assemble the reviewed R11 Windows/Linux native receipt without rebuilding either library."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any


FORMAT = "openrc-ground-vehicle-native-receipt"
BACKEND = "native"
BACKEND_VERSION = "openrc-ground-vehicle-native-evaluate-v2"
ABI_VERSION = 1
SOLVER_VERSION = "openrc-ground-vehicle-dynamics-rk4-v3"
HEX_SHA256 = re.compile(r"^[0-9a-f]{64}$")
PLATFORMS = ("linux", "windows")
RECORD_KEYS = (
    "platform",
    "architecture",
    "backend",
    "backend_version",
    "abi_version",
    "solver_version",
    "source_sha256",
    "toolchain_sha256",
    "binary_sha256",
    "toolchain",
    "floating_point_flags",
    "exception_flags",
)


class ReceiptError(ValueError):
    """Input receipt or binary does not match the reviewed native identity."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReceiptError(f"could not read JSON receipt {path}: {error}") from error
    if not isinstance(value, dict):
        raise ReceiptError(f"receipt root must be an object: {path}")
    return value


def _platform_record(receipt: dict[str, Any], platform: str) -> dict[str, Any]:
    """Accept either a platform row or a one/multi-platform aggregate receipt."""
    if "platforms" not in receipt:
        record = receipt
    else:
        if receipt.get("format") != FORMAT:
            raise ReceiptError(f"{platform} aggregate receipt has an unsupported format")
        platform_rows = receipt.get("platforms")
        if not isinstance(platform_rows, dict):
            raise ReceiptError(f"{platform} aggregate receipt has no platform map")
        record = platform_rows.get(platform)
        if not isinstance(record, dict):
            raise ReceiptError(f"{platform} row is missing from its aggregate receipt")
        for key, expected in (
            ("backend", BACKEND),
            ("backend_version", BACKEND_VERSION),
            ("solver_version", SOLVER_VERSION),
        ):
            if receipt.get(key) != expected:
                raise ReceiptError(f"{platform} aggregate top-level {key} is incompatible")
        if type(receipt.get("abi_version")) is not int or receipt["abi_version"] != ABI_VERSION:
            raise ReceiptError(f"{platform} aggregate top-level abi_version must be integer {ABI_VERSION}")

    missing = [key for key in RECORD_KEYS if key not in record]
    if missing:
        raise ReceiptError(f"{platform} record is missing keys: {', '.join(missing)}")
    if record.get("platform") != platform:
        raise ReceiptError(f"receipt platform is {record.get('platform')!r}, expected {platform!r}")
    if record.get("architecture") != "x86_64":
        raise ReceiptError(f"{platform} architecture must be x86_64")
    if type(record.get("abi_version")) is not int or record["abi_version"] != ABI_VERSION:
        raise ReceiptError(f"{platform} record abi_version must be integer {ABI_VERSION}")
    for key, expected in (
        ("backend", BACKEND),
        ("backend_version", BACKEND_VERSION),
        ("solver_version", SOLVER_VERSION),
    ):
        if record.get(key) != expected:
            raise ReceiptError(f"{platform} record has incompatible {key}")
    for key in ("source_sha256", "toolchain_sha256", "binary_sha256"):
        value = record.get(key)
        if not isinstance(value, str) or HEX_SHA256.fullmatch(value) is None:
            raise ReceiptError(f"{platform} {key} must be a lowercase SHA-256 digest")
    if not isinstance(record.get("toolchain"), dict):
        raise ReceiptError(f"{platform} toolchain identity must be an object")
    if not isinstance(record.get("floating_point_flags"), list) or not isinstance(record.get("exception_flags"), list):
        raise ReceiptError(f"{platform} compiler flags must be arrays")
    return record


def assemble_receipt(
    windows_receipt_path: Path,
    windows_binary_path: Path,
    linux_receipt_path: Path,
    linux_binary_path: Path,
    expected_source_sha256: str,
    expected_windows_toolchain_sha256: str,
    expected_linux_toolchain_sha256: str,
    output_path: Path,
) -> dict[str, Any]:
    """Validate both platform artifacts and write a fresh aggregate receipt."""
    for name, digest in (
        ("expected source", expected_source_sha256),
        ("expected Windows toolchain", expected_windows_toolchain_sha256),
        ("expected Linux toolchain", expected_linux_toolchain_sha256),
    ):
        if HEX_SHA256.fullmatch(digest) is None:
            raise ReceiptError(f"{name} SHA-256 must be a lowercase 64-character digest")
    if output_path.exists():
        raise ReceiptError(f"refusing to overwrite existing aggregate receipt: {output_path}")

    inputs = {
        "windows": (windows_receipt_path, windows_binary_path, expected_windows_toolchain_sha256),
        "linux": (linux_receipt_path, linux_binary_path, expected_linux_toolchain_sha256),
    }
    rows: dict[str, dict[str, Any]] = {}
    for platform in PLATFORMS:
        receipt_path, binary_path, expected_toolchain = inputs[platform]
        receipt = _read_json(receipt_path)
        record = _platform_record(receipt, platform)
        if record["source_sha256"] != expected_source_sha256:
            raise ReceiptError(f"{platform} source SHA-256 does not match the frozen native source")
        if record["toolchain_sha256"] != expected_toolchain:
            raise ReceiptError(f"{platform} toolchain SHA-256 differs from its retained build receipt")
        try:
            actual_binary_sha256 = sha256_file(binary_path)
        except OSError as error:
            raise ReceiptError(f"could not read {platform} binary {binary_path}: {error}") from error
        if record["binary_sha256"] != actual_binary_sha256:
            raise ReceiptError(f"{platform} binary SHA-256 does not match its retained build receipt")
        # Keep the original row values (including historical compiler/toolchain labels) intact.
        rows[platform] = dict(record)

    if rows["windows"]["source_sha256"] != rows["linux"]["source_sha256"]:
        raise ReceiptError("Windows and Linux rows do not identify the same native source")
    aggregate = {
        "format": FORMAT,
        "backend": BACKEND,
        "backend_version": BACKEND_VERSION,
        "abi_version": ABI_VERSION,
        "solver_version": SOLVER_VERSION,
        "platforms": rows,
    }
    try:
        serialized = json.dumps(aggregate, indent=2, sort_keys=True, allow_nan=False) + "\n"
    except ValueError as error:
        raise ReceiptError(f"aggregate contains a non-JSON numeric value: {error}") from error
    output_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with output_path.open("x", encoding="utf-8", newline="\n") as destination:
            destination.write(serialized)
    except FileExistsError as error:
        raise ReceiptError(f"refusing to overwrite existing aggregate receipt: {output_path}") from error
    return aggregate


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--windows-receipt", type=Path, required=True)
    parser.add_argument("--windows-binary", type=Path, required=True)
    parser.add_argument("--linux-receipt", type=Path, required=True)
    parser.add_argument("--linux-binary", type=Path, required=True)
    parser.add_argument("--expected-source-sha256", required=True)
    parser.add_argument("--expected-windows-toolchain-sha256", required=True)
    parser.add_argument("--expected-linux-toolchain-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        aggregate = assemble_receipt(
            args.windows_receipt,
            args.windows_binary,
            args.linux_receipt,
            args.linux_binary,
            args.expected_source_sha256,
            args.expected_windows_toolchain_sha256,
            args.expected_linux_toolchain_sha256,
            args.output,
        )
    except ReceiptError as error:
        print(f"receipt assembly failed: {error}", file=sys.stderr)
        return 1
    print(
        "R11_NATIVE_RECEIPT_ASSEMBLED "
        f"platforms={','.join(aggregate['platforms'])} "
        f"source_sha256={aggregate['platforms']['linux']['source_sha256']} "
        f"windows_binary_sha256={aggregate['platforms']['windows']['binary_sha256']} "
        f"linux_binary_sha256={aggregate['platforms']['linux']['binary_sha256']} "
        f"output={args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
