"""Generate the closed runtime overlay source-input proofs."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FAMILIES = {
    "moonrunner-x99": ("assets/aircraft/moonrunner-x99-overlay", "openrc-moonrunner-overlay-source-proof"),
    "stik-electric-6s": ("assets/aircraft/stik-electric-6s", "openrc-stik-electric-6s-overlay-source-proof"),
}
COMMON_PATHS = (
    "res://aircraft/customization_overlay.gd",
    "res://aircraft/model_manifest.gd",
    "res://aircraft/model_overlay_registry.gd",
    "res://aircraft/model_registry.gd",
    "res://aircraft/overlay_source_proof.gd",
)


def generate(root: Path, check: bool) -> int:
    try:
        for family, (directory, proof_format) in FAMILIES.items():
            sources = []
            paths = (f"{directory}/customization-bindings.json", f"{directory}/model-bindings.json", *COMMON_PATHS)
            for resource in paths:
                path = root / ("app/" + resource.removeprefix("res://") if resource.startswith("res://") else resource)
                data = path.read_bytes().replace(b"\r\n", b"\n")
                data.decode("utf-8")
                if not data:
                    raise ValueError(f"empty source: {resource}")
                sources.append({"path": resource, "sha256": hashlib.sha256(data).hexdigest()})
            rendered = (json.dumps({"format": proof_format, "version": 1, "sources": sources}, indent=2) + "\n").encode("utf-8")
            output = root / directory / "runtime-proof.json"
            if check:
                if not output.is_file() or output.read_bytes() != rendered:
                    raise ValueError(f"stale overlay source proof: {output.relative_to(root)}")
                print(f"{family} runtime source proof is current")
            else:
                output.parent.mkdir(parents=True, exist_ok=True)
                if not output.is_file() or output.read_bytes() != rendered:
                    output.write_bytes(rendered)
                print(f"generated {family} runtime source proof")
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
