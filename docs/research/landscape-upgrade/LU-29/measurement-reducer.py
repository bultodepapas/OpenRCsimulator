from pathlib import Path
import json
import statistics
from PIL import Image

base = Path(__file__).parent
night_dir = base / ("accepted-night" if (base / "accepted-night").exists() else "night")
on = json.loads((night_dir / "report.json").read_text())
flash = {}
for case in ["regional_turbines", "regional_antenna"]:
    lit = Image.open(night_dir / f"{case}.png")
    dark = Image.open(base / "flash-off" / f"{case}.png")
    rows = []
    for xy in on["cases"][case]["regional_flashes_px"]:
        x, y = map(int, xy)
        if 4 < x < 1275 and 4 < y < 715:
            def peak(img):
                return max(img.getpixel((xx, yy))[0]
                           for xx in range(x-4, x+5) for yy in range(y-4, y+5))
            rows.append({"pixel": xy, "on_red_peak": peak(lit), "off_red_peak": peak(dark)})
    flash[case] = rows
assert len(flash["regional_turbines"]) == 4
assert all(r["on_red_peak"] > r["off_red_peak"] + 40 for r in flash["regional_turbines"])
# Antenna camera also sees distant turbine lights offscreen; only the visible mast top is tested.
assert any(r["on_red_peak"] > r["off_red_peak"] + 100 for r in flash["regional_antenna"])
(base / "flash-check.json").write_text(json.dumps(flash, indent=2) + "\n")
print("Flash checks:", flash)

def report_path(pair, state):
    scratch = base / f"bench-{pair}-{state}/report.json"
    return scratch if scratch.exists() else base / "bench" / f"pair-{pair}-{state}.json"

reports = {(pair, state): json.loads(report_path(pair, state).read_text())
           for pair in range(1, 4) for state in ("off", "on")}
out = {"adapter": on["adapter"], "renderer": on["renderer"], "width": on["width"], "height": on["height"],
       "note": "Three alternating matched pairs; median of per-run p95 frame intervals, not isolated GPU timing.",
       "cases": {}}
for case in reports[1, "on"]["cases"]:
    row = {}
    for state in ("off", "on"):
        samples = [reports[pair, state]["cases"][case] for pair in range(1, 4)]
        row[state] = {"p95_ms": [s["p95_ms"] for s in samples],
                      "median_p95_ms": statistics.median(s["p95_ms"] for s in samples),
                      "draws": [s["draws"] for s in samples]}
    row["difference_ms"] = row["on"]["median_p95_ms"] - row["off"]["median_p95_ms"]
    out["cases"][case] = row
for pair in range(1, 4):
    # Existing world population must match; build timings are not comparable.
    for key in ("instances", "botanical_plants", "woodland_edge_plants", "vegetation_instances", "population"):
        assert reports[pair, "on"]["botanical_stats"][key] == reports[pair, "off"]["botanical_stats"][key]
    for key in reports[pair, "on"]["lake"]:
        if key != "grass_texture":  # runtime object ID in its debug string is process-local
            assert reports[pair, "on"]["lake"][key] == reports[pair, "off"]["lake"][key]
(base / "performance.json").write_text(json.dumps(out, indent=2) + "\n")
print(json.dumps(out, indent=2))
