#!/usr/bin/env python3
"""Verify recorded raw source hashes and separate checkout CRLF differences from code edits."""
import argparse
import hashlib
import json
from pathlib import Path


def audit(directory: Path) -> dict:
    manifest = json.loads((directory / "source-manifest.json").read_text())
    result = {"raw_hashes_verified": 0, "line_endings_only": [], "content_changes": []}
    contents = {}
    for label in ("baseline", "candidate"):
        contents[label] = {}
        for relative, expected in manifest[label]["files_sha256"].items():
            raw = (directory / label / "app" / relative).read_bytes()
            if hashlib.sha256(raw).hexdigest() != expected:
                raise ValueError(f"recorded source hash changed: {label}/{relative}")
            result["raw_hashes_verified"] += 1
            contents[label][relative] = raw
    for change in manifest["changed_paths"]:
        path = change["path"]
        before, after = contents["baseline"].get(path), contents["candidate"].get(path)
        text_only = False
        if before is not None and after is not None and b"\x00" not in before + after:
            try:
                text_only = before.decode("utf-8").replace("\r\n", "\n") == after.decode("utf-8").replace("\r\n", "\n")
            except UnicodeDecodeError:
                pass
        result["line_endings_only" if text_only else "content_changes"].append(path)
    result["ok"] = True
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="original compare.py output including snapshots")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    report = audit(args.directory)
    with args.out.open("x", encoding="utf-8") as output:
        json.dump(report, output, indent=2)
        output.write("\n")
    print(f"{report['raw_hashes_verified']} raw hashes verified; {len(report['content_changes'])} content changes; "
          f"{len(report['line_endings_only'])} CRLF-only differences")
