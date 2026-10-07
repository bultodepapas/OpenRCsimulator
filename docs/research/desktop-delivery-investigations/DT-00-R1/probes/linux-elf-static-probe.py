#!/usr/bin/env python3
"""Record static Linux ELF facts using file/readelf only; never execute target."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def run(argv: list[str]) -> dict[str, object]:
    completed = subprocess.run(argv, capture_output=True, text=True, check=False)
    return {
        "argv": argv,
        "returncode": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
    }


def version(tool: str) -> str:
    result = run([tool, "--version"])
    return result["stdout"].splitlines()[0] if result["stdout"] else str(result["stderr"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path, help="ELF file to inspect; it is never executed")
    parser.add_argument("--output", type=Path, help="write JSON here instead of stdout")
    args = parser.parse_args()

    target = args.artifact.resolve(strict=True)
    if not target.is_file():
        parser.error(f"not a regular file: {target}")
    for required in ("file", "readelf"):
        if shutil.which(required) is None:
            parser.error(f"required static inspection tool is missing: {required}")

    digest = hashlib.sha256()
    with target.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    stat = target.stat()
    commands = {
        "file": run(["file", "--", str(target)]),
        "elf_header": run(["readelf", "-W", "-h", str(target)]),
        "program_headers": run(["readelf", "-W", "-l", str(target)]),
        "dynamic_section": run(["readelf", "-W", "-d", str(target)]),
        "notes": run(["readelf", "-W", "-n", str(target)]),
        "symbol_versions": run(["readelf", "-W", "--version-info", str(target)]),
    }
    symbol_text = str(commands["symbol_versions"]["stdout"])
    glibc_versions = re.findall(r"GLIBC_([0-9]+(?:\.[0-9]+)+)", symbol_text)

    result: dict[str, object] = {
        "schema": "openrc-linux-elf-static-probe-v1",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "probe_mode": "static only: file and readelf; target executable was not launched",
        "target": {
            "path": str(target),
            "size_bytes": stat.st_size,
            "mode_octal": oct(stat.st_mode & 0o777),
            "mtime_utc": datetime.fromtimestamp(stat.st_mtime, timezone.utc).isoformat(),
            "sha256": digest.hexdigest(),
        },
        "tools": {"file": version("file"), "readelf": version("readelf")},
        "maximum_glibc_symbol_version_seen": max(
            glibc_versions,
            key=lambda value: tuple(int(part) for part in value.split(".")),
            default=None,
        ),
        "commands": commands,
        "interpretation_limit": (
            "ELF notes and direct metadata do not prove a hard minimum kernel or runtime support. "
            "This probe does not resolve dependencies, inspect dlopen paths, or test graphics, input, audio, or launch behavior."
        ),
    }
    encoded = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")
    return 0 if all(command["returncode"] == 0 for command in commands.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
