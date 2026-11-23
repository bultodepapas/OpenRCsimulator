#!/usr/bin/env python3
"""Offline source-identity witness; does not run Godot or qualify replay parity."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

PINS = [
    ("main control", "85a2475f60029a4b6b09f23f643119bceea84a45", True),
    ("earlier audit control", "f1d1151ae3841d97a080c499a5a0280ab3bdd3d9", True),
    ("later audit source", "ee46d96b7be4a77e040d814f6db71ab968751f01", False),
]
LOADER = "app/ai/companions/profile_loader.gd"
QUALIFICATION = "tools/companions/qualification.json"
PROFILE = "app/data/ai/companions/aircraft/jensen-das-ugly-stik-60.json"
DIRECTORIES = ["app/physics", "app/sim", "app/failures"]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        parser.error("--out must be new")

    def git(*arguments: str) -> bytes:
        return subprocess.check_output(["git", *arguments], cwd=args.repo)

    cache: dict[str, bytes] = {}
    cases = []
    for label, rev, expected_match in PINS:
        entries = []
        listing = git("ls-tree", "-r", rev, "--", *DIRECTORIES).decode("utf-8")
        for line in listing.splitlines():
            metadata, path = line.split("\t", 1)
            mode, kind, sha = metadata.split()
            if kind != "blob" or not path.endswith(".gd"):
                continue
            if mode != "100644" or not path.isascii():
                raise ValueError("Unqualified source path/mode; inspect before adapting witness")
            entries.append(("res://" + path.removeprefix("app/"), sha))
        if not entries:
            raise ValueError("Empty source set")
        digest = hashlib.sha256()
        for path, sha in sorted(entries):
            if sha not in cache:
                raw = git("cat-file", "blob", sha)
                text = raw.decode("utf-8")
                if not raw or text.encode("utf-8") != raw:
                    raise ValueError("Invalid/empty UTF-8 source")
                cache[sha] = text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
            # profile_loader.gd canonical_solver_identity: sorted path then normalized source.
            digest.update(path.encode("utf-8"))
            digest.update(cache[sha])
        qualification = json.loads(git("show", f"{rev}:{QUALIFICATION}"))
        profile = json.loads(git("show", f"{rev}:{PROFILE}"))
        qualification_pin = qualification["accepted"]["solver_sha256"]
        profile_pin = profile["solver"]["sha256"]
        matches = digest.hexdigest() == qualification_pin == profile_pin
        if matches != expected_match:
            raise ValueError(f"Pinned witness outcome changed for {rev}")
        cases.append({
            "label": label, "commit": rev, "source_count": len(entries),
            "computed_normalized_sha256": digest.hexdigest(),
            "qualification_pin": qualification_pin, "profile_pin": profile_pin,
            "matches_both_pins": matches,
            "loader_sha256": hashlib.sha256(git("show", f"{rev}:{LOADER}")).hexdigest(),
            "qualification_blob_sha": git("rev-parse", f"{rev}:{QUALIFICATION}").decode().strip(),
            "profile_blob_sha": git("rev-parse", f"{rev}:{PROFILE}").decode().strip(),
        })
    receipt = {
        "schema": 1,
        "method": "Python translation of pinned canonical_solver_identity: sorted ASCII res:// paths for .gd blobs in physics/sim/failures, then UTF-8 content with CRLF/CR normalized to LF; SHA-256 without extra separators.",
        "reproducer_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "cases": cases,
        "limitations": [
            "Reads committed Git source blobs, not a packaged or live Godot filesystem.",
            "Matching two accepted controls checks this translation; no engine API or replay was executed.",
            "The mismatch is source-identity evidence, not changed physics, FPS, or failed physical validation.",
            "Never replace a qualification pin merely with this computed digest; the owning rebind requires tape comparison.",
            "Later branch commits may repair the mismatch; the witness remains pinned to ee46d96b.",
        ],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("x", encoding="utf-8") as output:
        json.dump(receipt, output, indent=2, sort_keys=True, allow_nan=False)
        output.write("\n")
    for case in cases:
        print(f"{case['label']}: {case['source_count']} sources; match={case['matches_both_pins']}; "
              f"sha256={case['computed_normalized_sha256']}")


if __name__ == "__main__":
    main()
