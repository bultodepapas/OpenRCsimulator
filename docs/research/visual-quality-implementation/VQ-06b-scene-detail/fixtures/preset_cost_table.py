"""VQ-06b: per-level drawn cost table from attribution summaries, and the ordering check.

Usage: preset_cost_table.py low=<summary.json> medium=<...> high=<...> extreme=<...>
Each summary comes from tools/scenery/attribution_report.py --json at that Scene detail level.
Exits nonzero when a level draws more than the level above it in any view class.
"""
import json
import sys

LEVELS = ["low", "medium", "high", "extreme"]
CLASSES = ["pilot", "ground", "aerial"]


def main() -> None:
    paths = dict(argument.split("=", 1) for argument in sys.argv[1:])
    summaries = {level: json.load(open(paths[level])) for level in LEVELS if level in paths}
    rows = ["| Level | " + " | ".join(f"{name.capitalize()} worst view: primitives / draws" for name in CLASSES)
            + " | Pilot median primitives | 3D field trees, pilot worst |",
            "| --- | " + " | ".join("---:" for _ in CLASSES) + " | ---: | ---: |"]
    failures = []
    previous = None
    for level in LEVELS:
        if level not in summaries:
            continue
        summary = summaries[level]
        if summary.get("scene_detail", "high") != level:
            failures.append(f"{level}: summary was measured at {summary.get('scene_detail', 'high')}")
        cells = []
        for name in CLASSES:
            total = summary["classes"][name]["total"]
            cells.append(f"{total['primitives_max']:,} / {total['draws_max']}")
            if previous is not None:
                below = summaries[previous]["classes"][name]["total"]
                if total["primitives_max"] < below["primitives_max"]:
                    failures.append(f"{level} {name}: {total['primitives_max']:,} primitives < {previous} "
                                    f"{below['primitives_max']:,}")
        trees = summary["classes"]["pilot"]["groups"].get("field_treelineDetail", {}).get("primitives_max", 0)
        rows.append(f"| {level.capitalize()} | " + " | ".join(cells)
                    + f" | {summary['classes']['pilot']['total']['primitives_median']:,.0f} | {trees:,} |")
        previous = level
    print("\n".join(rows))
    if failures:
        raise SystemExit("ordering or provenance failures:\n  " + "\n  ".join(failures))


if __name__ == "__main__":
    main()
