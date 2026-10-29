"""Generate the closed MoonRunner runtime overlay source-input proof."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = Path("assets/aircraft/moonrunner-x99-overlay/runtime-proof.json")
PATHS = (
    "assets/aircraft/moonrunner-x99-overlay/customization-bindings.json",
    "assets/aircraft/moonrunner-x99-overlay/model-bindings.json",
    "res://aircraft/customization_overlay.gd",
    "res://aircraft/model_manifest.gd",
    "res://aircraft/model_overlay_registry.gd",
    "res://aircraft/model_registry.gd",
    "res://aircraft/overlay_source_proof.gd",
)


def generate(root: Path, check: bool) -> int:
    try:
        sources = []
        for resource in PATHS:
            path = root / ("app/" + resource.removeprefix("res://") if resource.startswith("res://") else resource)
            data = path.read_bytes().replace(b"\r\n", b"\n")
            data.decode("utf-8")
            if not data:
                raise ValueError(f"empty source: {resource}")
            sources.append({"path": resource, "sha256": hashlib.sha256(data).hexdigest()})
        rendered = (json.dumps({"format": "openrc-moonrunner-overlay-source-proof", "version": 1, "sources": sources}, indent=2) + "\n").encode("utf-8")
        output = root / OUTPUT
        if check:
            if not output.is_file() or output.read_bytes() != rendered:
                raise ValueError(f"stale overlay source proof: {OUTPUT}")
            print("MoonRunner runtime source proof is current")
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
            if not output.is_file() or output.read_bytes() != rendered:
                output.write_bytes(rendered)
            print("generated MoonRunner runtime source proof")
        return 0
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"overlay source proof generation failed: {exc}", file=sys.stderr)
        return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    args = parser.parse_args()
    return generate(args.root.resolve(), args.check)


if __name__ == "__main__":
    raise SystemExit(main())
