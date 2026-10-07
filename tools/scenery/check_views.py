#!/usr/bin/env python3
"""SCENERY-PLAN SC-03: budget and repeatability check for tools/scenery/capture.sh output (stdlib only).

Budgets (SCENERY-PLAN, proposed): in the pilot's views the scenery adds <= 40 visible draw calls and <= 150 k primitives;
no view adds shadow-pass draws; two scenery-on runs give byte-identical PNGs. Writes <out>/summary.json.
"""
import hashlib
import json
import sys
from pathlib import Path

PILOT_VIEWS = ("pilot_north", "pilot_south", "pilot_east", "pilot_west")
MAX_DRAWS = 40
MAX_PRIMITIVES = 150_000


def main() -> int:
    out = Path(sys.argv[1])
    off = json.loads((out / "off/views.json").read_text())
    on = json.loads((out / "on/views.json").read_text())
    failures = []
    rows = {}
    for name, v in on["views"].items():
        base = off["views"][name]
        d_draw = v["draw_calls"] - base["draw_calls"]
        d_prim = v["primitives"] - base["primitives"]
        a = (out / "on" / f"{name}.png").read_bytes()
        b = (out / "on-repeat" / f"{name}.png").read_bytes()
        same = hashlib.sha256(a).hexdigest() == hashlib.sha256(b).hexdigest()
        rows[name] = {"draw_calls_added": d_draw, "primitives_added": d_prim, "shadow_draw_calls": v["shadow_draw_calls"],
                      "repeat_identical": same, "sha256": hashlib.sha256(a).hexdigest()}
        if v["shadow_draw_calls"] != 0:
            failures.append(f"{name}: {v['shadow_draw_calls']} shadow-pass draws")
        if not same:
            failures.append(f"{name}: two scenery-on runs differ")
        if name in PILOT_VIEWS and d_draw > MAX_DRAWS:
            failures.append(f"{name}: +{d_draw} draw calls > {MAX_DRAWS}")
        if name in PILOT_VIEWS and d_prim > MAX_PRIMITIVES:
            failures.append(f"{name}: +{d_prim} primitives > {MAX_PRIMITIVES}")
    summary = {"budgets": {"pilot_views": PILOT_VIEWS, "max_draw_calls_added": MAX_DRAWS, "max_primitives_added": MAX_PRIMITIVES},
               "stats": on.get("stats", {}), "field_build_ms": on.get("field_build_ms"), "adapter": on.get("adapter"),
               "views": rows, "failures": failures}
    (out / "summary.json").write_text(json.dumps(summary, indent=1, sort_keys=True) + "\n")
    for name, r in rows.items():
        mark = "*" if name in PILOT_VIEWS else " "
        print(f"{mark} {name:18s} +{r['draw_calls_added']:4.0f} draws  +{r['primitives_added']:8.0f} prims  shadow {r['shadow_draw_calls']}  repeat {'yes' if r['repeat_identical'] else 'NO'}")
    if failures:
        print("FAIL\n  " + "\n  ".join(failures))
        return 1
    print("scenery captures within budget and byte-repeatable")
    return 0


if __name__ == "__main__":
    sys.exit(main())
