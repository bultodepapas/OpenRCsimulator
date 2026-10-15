#!/usr/bin/env python3
"""Prepare the R05B flight-session overlay while retaining b09's runway allowlist."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from datetime import datetime, timezone


EXPECTED_LIVE_SHA256 = "6ab22b03a16b9a5783931254bcf407c97d6e2a09edeb45a3974c09c2ec199f43"
BASE_REVISION = "b09aa20016d3dcc8133073e66424313b9bfbf0d7"
SOURCE_REL = "app/sim/flight_session.gd"
ALLOWLIST_PREFIX = b"const RUNWAY_AIRCRAFT_IDS := ["
P51_ENTRY = b', "p51d-mustang-120"'


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    source = root / SOURCE_REL
    data = source.read_bytes()
    live_hash = sha256(data)
    if live_hash != EXPECTED_LIVE_SHA256:
        raise SystemExit(f"integrated R05B flight_session hash mismatch: {live_hash}")

    base = subprocess.run(
        ["git", "-C", str(root), "show", f"{BASE_REVISION}:{SOURCE_REL}"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout
    base_lines = [line for line in base.splitlines(keepends=True) if line.startswith(ALLOWLIST_PREFIX)]
    current_lines = data.splitlines(keepends=True)
    current_indexes = [i for i, line in enumerate(current_lines) if line.startswith(ALLOWLIST_PREFIX)]
    if len(base_lines) != 1 or len(current_indexes) != 1:
        raise SystemExit(f"expected one base/current runway allowlist; base={len(base_lines)} current={len(current_indexes)}")
    current_line = current_lines[current_indexes[0]]
    if current_line.count(P51_ENTRY) != 1 or b"p51d-mustang-120" not in current_line:
        raise SystemExit("the sole expected P51 external hunk was absent or changed")
    restored_line = current_line.replace(P51_ENTRY, b"", 1)
    if restored_line != base_lines[0]:
        raise SystemExit("removing the P51 allowlist entry does not restore the exact b09 line")
    current_lines[current_indexes[0]] = restored_line
    output = b"".join(current_lines)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(output)
    meta = {
        "format": "openrc-r11-r05b-p51-overlay-exclusion-v1",
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "base_revision": BASE_REVISION,
        "path": SOURCE_REL,
        "live_overlay_sha256": live_hash,
        "base_allowlist_line": base_lines[0].decode("utf-8").rstrip("\r\n"),
        "live_allowlist_line": current_line.decode("utf-8").rstrip("\r\n"),
        "restored_allowlist_line": restored_line.decode("utf-8").rstrip("\r\n"),
        "only_edit": "remove the external p51d-mustang-120 runway allowlist entry so the isolated flight_session and test_runway_start remain consistent with b09",
        "overlay_sha256": sha256(output),
        "overlay_size_bytes": len(output),
        "overlay_path": str(args.output.resolve()),
    }
    args.metadata.parent.mkdir(parents=True, exist_ok=True)
    args.metadata.write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"live_sha256={live_hash}")
    print(f"restored_b09_allowlist={restored_line.decode('utf-8').strip()}")
    print(f"overlay_sha256={sha256(output)} size={len(output)}")
    print(f"overlay={args.output.resolve()}")
    print(f"metadata={args.metadata.resolve()}")


if __name__ == "__main__":
    main()
