#!/usr/bin/env python3
"""Reject direct transcendental calls in physics/sim outside math3d.gd."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path


APP_ROOT = Path(__file__).resolve().parents[1]
FUNCTIONS = (
    "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sqrt", "pow", "log", "exp",
    "sinh", "cosh", "tanh", "asinh", "acosh", "atanh",
)
CALL = re.compile(r"(?<![\w.])(" + "|".join(sorted(FUNCTIONS, key=len, reverse=True)) + r")(?=\s*\()")


def _mask_strings_and_comments(source: str) -> str:
    """Keep code positions while masking quoted strings and # comments."""
    result = list(source)
    index = 0
    while index < len(source):
        char = source[index]
        if char in ('"', "'"):
            quote = char
            triple = source.startswith(quote * 3, index)
            delimiter = quote * (3 if triple else 1)
            end = index + len(delimiter)
            while end < len(source):
                if source[end] == "\\":
                    end += 2
                    continue
                if source.startswith(delimiter, end):
                    end += len(delimiter)
                    break
                end += 1
            for offset in range(index, min(end, len(source))):
                if result[offset] != "\n":
                    result[offset] = " "
            index = end
            continue
        if char == "#":
            end = source.find("\n", index)
            if end < 0:
                end = len(source)
            for offset in range(index, end):
                result[offset] = " "
            index = end
            continue
        index += 1
    return "".join(result)


def scan(root: Path) -> list[str]:
    findings: list[str] = []
    for folder in (root / "physics", root / "sim"):
        if not folder.is_dir():
            continue
        for path in sorted(folder.rglob("*.gd")):
            if path.name == "math3d.gd":
                continue  # This file is the sole implementation boundary for the built-ins.
            code = _mask_strings_and_comments(path.read_text(encoding="utf-8"))
            for match in CALL.finditer(code):
                line = code.count("\n", 0, match.start()) + 1
                findings.append(f"{path.relative_to(root)}:{line}: bare {match.group(1)}( call")
    return findings


def self_test() -> bool:
    """Prove that a deliberately injected call fails in an isolated source tree."""
    with tempfile.TemporaryDirectory(prefix="openrc-math-guard-") as temporary:
        root = Path(temporary)
        (root / "physics").mkdir()
        (root / "sim").mkdir()
        (root / "physics" / "injected.gd").write_text(
            "extends RefCounted\nstatic func bad() -> float:\n\treturn sin(0.25)\n", encoding="utf-8"
        )
        run = subprocess.run(
            [sys.executable, str(Path(__file__).resolve()), "--root", str(root)],
            text=True, capture_output=True, check=False,
        )
        if run.returncode == 0 or "physics/injected.gd:3: bare sin( call" not in run.stdout:
            print("transcendental guard self-test failed", file=sys.stderr)
            print(run.stdout, end="", file=sys.stderr)
            print(run.stderr, end="", file=sys.stderr)
            return False
    print("isolated injection rejected")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=APP_ROOT, help="app directory to scan")
    parser.add_argument("--self-test", action="store_true", help="verify that an isolated injected call is rejected")
    args = parser.parse_args()
    if args.self_test:
        return 0 if self_test() else 1
    findings = scan(args.root.resolve())
    if findings:
        print("direct transcendental calls found outside physics/math3d.gd:")
        print("\n".join(findings))
        return 1
    print("all physics/sim transcendental calls route through math3d")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
