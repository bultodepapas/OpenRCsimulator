"""Compatibility entry point for the X8 kit; see build_skin_kits.py."""

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_skin_kits import REGISTRY, build

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate the X8 skin starter kit")
    parser.add_argument("--output", help="Output ZIP (default: app/assets/skin-kit/skywalker-x8.zip)")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    build("skywalker-x8", json.loads(REGISTRY.read_text(encoding="utf-8"))["models"]["skywalker-x8"], output=args.output)
