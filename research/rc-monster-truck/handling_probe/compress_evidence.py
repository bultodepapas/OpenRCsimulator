#!/usr/bin/env python3
"""Gzip completed RC trace CSVs and update their JSON receipts safely."""

from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def count_rows(path: Path, compressed: bool) -> int:
    opener = gzip.open if compressed else open
    with opener(path, "rt", newline="", encoding="utf-8") as stream:
        return sum(1 for _ in csv.DictReader(stream))


def compress_receipt(receipt_path: Path) -> Path:
    receipt_path = receipt_path.resolve()
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    csv_info = receipt.get("csv")
    if not isinstance(csv_info, dict) or not isinstance(csv_info.get("path"), str):
        raise ValueError(f"receipt has no CSV path: {receipt_path}")
    if csv_info.get("storage_format"):
        raise ValueError(f"receipt already has a compressed storage artifact: {receipt_path}")
    source = Path(csv_info["path"])
    if not source.is_absolute():
        source = (receipt_path.parent / source).resolve()
    if source.suffix.lower() != ".csv":
        raise ValueError(f"expected an uncompressed .csv path: {source}")
    if not source.is_file():
        raise FileNotFoundError(source)
    source_hash = sha256_file(source)
    if source_hash != csv_info.get("sha256"):
        raise ValueError(f"uncompressed CSV hash mismatch: {source}")
    rows = count_rows(source, compressed=False)
    if rows != int(csv_info.get("rows", -1)):
        raise ValueError(f"CSV row count mismatch: {source}")

    target = source.with_suffix(source.suffix + ".gz")
    if target.exists():
        raise FileExistsError(target)
    fd, temporary_name = tempfile.mkstemp(prefix=target.name + ".", suffix=".tmp", dir=target.parent)
    os.close(fd)
    temporary = Path(temporary_name)
    try:
        with source.open("rb") as input_stream, temporary.open("wb") as output_stream:
            with gzip.GzipFile(filename="", mode="wb", compresslevel=9, fileobj=output_stream, mtime=0) as gzip_stream:
                shutil.copyfileobj(input_stream, gzip_stream)
        compressed_hash = sha256_file(temporary)
        if count_rows(temporary, compressed=True) != rows:
            raise ValueError(f"compressed CSV row count mismatch: {temporary}")
        with gzip.open(temporary, "rb") as stream:
            decoded_hash = hashlib.sha256(stream.read()).hexdigest()
        if decoded_hash != source_hash:
            raise ValueError(f"gzip payload hash mismatch: {temporary}")
        temporary.replace(target)

        csv_info["storage_path"] = target.resolve().as_posix()
        csv_info["storage_sha256"] = compressed_hash
        csv_info["storage_format"] = "gzip"
        receipt_temp = receipt_path.with_suffix(receipt_path.suffix + ".tmp")
        receipt_temp.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        receipt_temp.replace(receipt_path)
        source.unlink()
        return target
    except Exception:
        if temporary.exists():
            temporary.unlink()
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipts", nargs="+", type=Path, help="completed JSON run receipts")
    args = parser.parse_args()
    for receipt in args.receipts:
        output = compress_receipt(receipt)
        print(f"compressed: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
