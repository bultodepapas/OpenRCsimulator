"""Investigation 08: reproduce a scan-scale diagnostic, not aircraft dimensions.

The manually inspected pixel endpoints are in plan-measurements.json.
Run: python3 research/ugly-stik/measure_plan.py
Only writes evidence under docs/research/ugly-stik-investigations/evidence/.
"""

import hashlib
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main():
    data = json.loads((HERE / "plan-measurements.json").read_text())
    pdf = ROOT / data["source_path"]
    if pdf.exists():
        assert hashlib.sha256(pdf.read_bytes()).hexdigest() == data["source_sha256"], "Source PDF changed"
        source_check = "SHA-256 verified"
    else:
        source_check = "PDF unavailable; calculation uses recorded endpoints only"
    diameter_mm = data["labelled_diameter_in"] * 25.4
    dx = math.dist(*data["x_endpoints_px"])
    dy = math.dist(*data["y_endpoints_px"])
    error = 2 * data["endpoint_uncertainty_px"]
    assert dx > error and dy > error
    scale_x = diameter_mm / dx
    scale_y = diameter_mm / dy
    from_page = data["pdf_page_width_pt"] / 72 * 25.4 / data["raster_width_px"]
    result = {
        "source_check": source_check,
        "measured_object": "raster representation, not built aircraft",
        "diameter_x_px": dx,
        "diameter_y_px": dy,
        "conditional_mm_per_pixel_x": scale_x,
        "conditional_mm_per_pixel_y": scale_y,
        "conditional_x_scale_interval_mm_per_pixel": [diameter_mm / (dx + error), diameter_mm / (dx - error)],
        "pdf_page_mm_per_pixel": from_page,
        "conditional_scale_difference_from_pdf_percent": 100 * (scale_x / from_page - 1),
        "conclusion": "A single wheel annotation does not establish whole-sheet scale. Check a second long dimension and both axes before accepting contours.",
    }
    out = ROOT / "docs/research/ugly-stik-investigations/evidence/plan-scale.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
