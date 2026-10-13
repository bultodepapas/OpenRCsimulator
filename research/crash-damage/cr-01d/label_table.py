#!/usr/bin/env python3
"""CR-01d evidence: print each aircraft's crash-hull points (le frame: x aft, y right, z up) with their names."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
for path in sorted((ROOT / "app/data/aircraft").glob("*.json")):
    data = json.loads(path.read_text(encoding="utf-8"))
    points, names = data["crash_hull"]["value"], data.get("crash_hull_components", [])
    print(f"\n### {data['id']} ({len(points)} points)\n\n| # | Name | x aft | y right | z up |\n| ---: | --- | ---: | ---: | ---: |")
    for i, p in enumerate(points):
        print(f"| {i} | {names[i] if i < len(names) else '(none)'} | {p[0]:.3f} | {p[1]:.3f} | {p[2]:.3f} |")
