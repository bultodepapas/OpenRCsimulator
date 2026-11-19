#!/usr/bin/env python3
"""Reproduce the research catalog from pinned, local source bytes.

The brand cards are references, not permission for Workshop placement. This
builder never retrieves source artwork from the web and never edits image bytes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BASELINE = "cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c"


def strict_object(pairs):
    """Reject duplicate JSON keys, including keys inside nested objects."""
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read_catalog():
    with (HERE / "catalog.json").open(encoding="utf-8") as file:
        catalog = json.load(file, object_pairs_hook=strict_object)
    if catalog.get("version") != 1 or catalog.get("baseline_commit") != BASELINE:
        raise ValueError("unexpected catalog version or baseline")
    if not isinstance(catalog.get("entries"), list):
        raise ValueError("catalog entries must be an array")
    return catalog


def source_bytes(entry):
    relative = PurePosixPath(entry["source_path"])
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"unsafe source path for {entry['id']}")
    path = ROOT.joinpath(*relative.parts)
    if path.is_file():
        return path.read_bytes()
    commit = entry.get("baseline_commit")
    if commit != BASELINE:
        raise ValueError(f"missing local source for {entry['id']}: {relative}")
    # A sparse checkout may omit the source file while retaining its Git blob.
    # Do not allow a partial clone to fetch a missing object during reproduction.
    env = dict(os.environ, GIT_NO_LAZY_FETCH="1", GIT_TERMINAL_PROMPT="0")
    try:
        return subprocess.run(
            ["git", "-C", str(ROOT), "show", f"{commit}:{relative.as_posix()}"],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ValueError(f"baseline source unavailable locally for {entry['id']}") from exc


def image_info(data):
    """Read the exact format and canvas dimensions without changing bytes."""
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        if len(data) < 24 or data[12:16] != b"IHDR":
            raise ValueError("invalid PNG header")
        return "png", *struct.unpack(">II", data[16:24])
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        if len(data) < 30 or data[12:16] != b"VP8X":
            raise ValueError("unsupported WebP header")
        return "webp", 1 + int.from_bytes(data[24:27], "little"), 1 + int.from_bytes(data[27:30], "little")
    try:
        element = ET.fromstring(data)
        if element.tag != "{http://www.w3.org/2000/svg}svg":
            raise ValueError("not an SVG root")
        width = int(element.attrib["width"])
        height = int(element.attrib["height"])
        return "svg", width, height
    except (ET.ParseError, KeyError, ValueError) as exc:
        raise ValueError("unsupported or invalid image") from exc


def build_outputs():
    """Return generated paths relative to HERE and their exact file bytes."""
    entries = read_catalog()["entries"]
    outputs = {}
    locked = []
    browser_assets = []
    seen = set()
    for entry in entries:
        id = entry["id"]
        if not isinstance(id, str) or not id or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-" for c in id) or id in seen:
            raise ValueError(f"invalid or duplicate entry id: {id!r}")
        seen.add(id)
        demo = entry["demo_placement"]
        if not isinstance(demo, bool):
            raise ValueError(f"demo_placement must be a boolean: {id}")
        image = None
        width = height = None
        if entry["source_path"] is not None:
            data = source_bytes(entry)
            digest = hashlib.sha256(data).hexdigest()
            if digest != entry["source_sha256"]:
                raise ValueError(f"source SHA-256 mismatch: {id}")
            fmt, width, height = image_info(data)
            filename = entry["asset_filename"]
            if filename != f"{id}.{fmt}" or (width, height) != (entry["width"], entry["height"]):
                raise ValueError(f"source format or dimensions mismatch: {id}")
            image = f"assets/{filename}"
            outputs[Path(image)] = data
            locked.append({"id": id, "source_path": entry["source_path"],
                           "baseline_commit": entry["baseline_commit"],
                           "source_sha256": digest, "output_path": image, "bytes": len(data),
                           "output_sha256": digest, "format": fmt,
                           "transform": "none; exact original bytes",
                           "width": width, "height": height})
        elif any(entry[key] is not None for key in ("source_sha256", "asset_filename", "width", "height", "baseline_commit")) or demo:
            raise ValueError(f"invalid metadata-only entry: {id}")
        browser_assets.append({"id": id, "brand": entry["brand"], "label": entry["label"],
                               "image": image, "width": width, "height": height,
                               "placement_enabled": demo, "reason": entry["reason"]})
    outputs[Path("asset-lock.json")] = (json.dumps({"format": "openrc-decal-research-assets", "version": 1,
        "baseline_commit": BASELINE, "assets": locked,
        "total_bytes": sum(item["bytes"] for item in locked)}, indent=2, ensure_ascii=False) + "\n").encode()
    outputs[Path("catalog.js")] = ("window.OPENRC_DECAL_CATALOG = " + json.dumps({"assets": browser_assets}, indent=2, ensure_ascii=False) + ";\n").encode()
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="compare generated files without writing")
    args = parser.parse_args()
    try:
        outputs = build_outputs()
        mismatches = []
        for relative, data in outputs.items():
            target = HERE / relative
            if args.check:
                if not target.is_file() or target.read_bytes() != data:
                    mismatches.append(str(relative))
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
        if args.check:
            actual = {p.relative_to(HERE) for p in (HERE / "assets").glob("*") if p.is_file()}
            expected = {p for p in outputs if p.parent == Path("assets")}
            mismatches.extend(str(p) for p in sorted(actual - expected))
            if mismatches:
                print("Generated files differ: " + ", ".join(mismatches), file=sys.stderr)
                return 1
        print(f"{'Verified' if args.check else 'Built'} {len(outputs) - 2} exact image assets and catalog outputs")
        return 0
    except (ValueError, KeyError, TypeError, OSError) as exc:
        print(f"Catalog error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
