"""Compatibility entry point for the MoonRunner X99 kit; see build_skin_kits.py."""

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_skin_kits import REGISTRY, build

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate the MoonRunner X99 skin starter kit")
    parser.add_argument("--output", help="Output ZIP (default: app/assets/skin-kit/moonrunner-x99.zip)")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    build("moonrunner-x99", json.loads(REGISTRY.read_text(encoding="utf-8"))["models"]["moonrunner-x99"], output=args.output)
