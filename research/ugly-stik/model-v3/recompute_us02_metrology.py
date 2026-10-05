#!/usr/bin/env python3
"""Recompute US-02 sheet1 derived values from the saved pixel readings.

Run with --write to update only derived fields, or without arguments to check
that the committed derived fields equal a fresh recomputation. Raw page pixel
coordinates and traced source points are never changed by this script.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[3]
DATA_PATH = ROOT / "research/ugly-stik/model-v3/us02-jensen-sheet1-metrology.json"
SCALE_REL_TOL = 5e-7


def rounded(value: float, digits: int = 6) -> float:
    return round(float(value), digits)


def close(a: float, b: float, tol: float = SCALE_REL_TOL) -> bool:
    return abs(float(a) - float(b)) <= tol


def apply_derived(data: dict) -> None:
    cal = data["calibration"]
    mpp = float(cal["metres_per_px_nominal"])
    anchors = cal["shared_model_mapping_inputs"]
    x_le = int(anchors["wing_le_page_x_px"])
    x_f1 = int(anchors["F1_page_x_px"])
    z_le = float(cal["shared_anchors_preserved"]["wing_le_z_m"])
    y_proxy_px = int(anchors["side_view_vertical_proxy_page_y_px"])
    y_proxy_m = float(cal["shared_anchors_preserved"]["shaft_y_m"])

    z_from_x = lambda x: z_le + (int(x) - x_le) * mpp
    y_from_page = lambda y: y_proxy_m + (y_proxy_px - int(y)) * mpp
    lateral_from_page = lambda y, center: (int(center) - int(y)) * mpp

    f1_z_calc = z_from_x(x_f1)
    f1_z_preserved = float(cal["shared_anchors_preserved"]["F1_z_m"])
    if not close(f1_z_calc, f1_z_preserved):
        raise ValueError(f"F1 anchor mismatch: calculated {f1_z_calc}, preserved {f1_z_preserved}")

    cal["scale_residual_percent"] = rounded(
        (float(cal["scale_check_readings"]["observed_chord_in"])
         - float(cal["scale_check_readings"]["title_block_chord_in"]))
        / float(cal["scale_check_readings"]["title_block_chord_in"]) * 100,
        6,
    )
    cal["shared_anchor_formula_check_F1_z_m"] = rounded(f1_z_calc)

    for section in data["fuselage_sections"]:
        x = int(section["page_x_px"])
        section["candidate_z_m"] = rounded(z_from_x(x))
        side = section["side_view"]
        roof = int(side["roof_page_y_px"])
        bottom = int(side["bottom_page_y_px"])
        side["roof_candidate_y_m_proxy"] = rounded(y_from_page(roof))
        side["bottom_candidate_y_m_proxy"] = rounded(y_from_page(bottom))
        side["height_m_scan_scale"] = rounded((bottom - roof) * mpp)
        top = section["top_view"]
        width = int(top["far_edge_page_y_px"]) - int(top["near_edge_page_y_px"])
        top["width_px"] = width
        top["width_m_scan_scale"] = rounded(width * mpp)

    hold = data["holdout_check"]
    hold["candidate_z_m"] = rounded(z_from_x(hold["page_x_px"]))
    f5, f6 = data["fuselage_sections"][1], data["fuselage_sections"][2]
    f5x, f6x = int(f5["page_x_px"]), int(f6["page_x_px"])
    hfrac = (int(hold["page_x_px"]) - f5x) / (f6x - f5x)
    hobs, hinterp = hold["observed"], hold["linear_interpolation_F5_F6"]
    f5side, f6side = f5["side_view"], f6["side_view"]
    hinterp["side_roof_page_y_px"] = round(
        int(f5side["roof_page_y_px"])
        + (int(f6side["roof_page_y_px"]) - int(f5side["roof_page_y_px"])) * hfrac,
        1,
    )
    hinterp["side_bottom_page_y_px"] = round(
        int(f5side["bottom_page_y_px"])
        + (int(f6side["bottom_page_y_px"]) - int(f5side["bottom_page_y_px"])) * hfrac,
        1,
    )
    f5w = int(f5["top_view"]["far_edge_page_y_px"]) - int(f5["top_view"]["near_edge_page_y_px"])
    f6w = int(f6["top_view"]["far_edge_page_y_px"]) - int(f6["top_view"]["near_edge_page_y_px"])
    hinterp["top_width_px"] = round(f5w + (f6w - f5w) * hfrac, 1)
    hobs["top_width_px"] = int(hobs["top_far_edge_page_y_px"]) - int(hobs["top_near_edge_page_y_px"])
    residual = hold["residual_observed_minus_interpolated_px"]
    residual["side_roof"] = round(int(hobs["side_roof_page_y_px"]) - hinterp["side_roof_page_y_px"], 1)
    residual["side_bottom"] = round(int(hobs["side_bottom_page_y_px"]) - hinterp["side_bottom_page_y_px"], 1)
    residual["top_width"] = round(int(hobs["top_width_px"]) - hinterp["top_width_px"], 1)
    hold["top_width_residual_m_scan_scale"] = rounded(residual["top_width"] * mpp)
    hold["interpretation"] = (
        "side-contour residual is below pick resolution; top-width residual is "
        "5 px (1.27 mm), below combined uncertainty from edge picks and interpolation, so this holdout "
        "does not resolve departure from linear taper."
    )

    root = data["wing_root_vertical_reading"]
    root["wing_le_candidate_y_m_proxy"] = rounded(y_from_page(root["wing_le_side_mid_page_y_px"]))
    root["wing_seat_roof_candidate_y_m_proxy"] = rounded(y_from_page(root["wing_seat_roof_side_mid_page_y_px"]))

    tail = data["horizontal_tail"]
    plan = tail["plan_view"]
    root_y = int(plan["plan_root_centerline_page_y_px"])
    tip_y = int(plan["plan_outboard_tip_page_y_px"])
    plan["semi_span_px"] = root_y - tip_y
    plan["semi_span_m_scan_scale"] = rounded(plan["semi_span_px"] * mpp)
    plan["full_span_m_scan_scale"] = rounded(2 * plan["semi_span_px"] * mpp)
    x_le_tail = int(plan["leading_edge_page_x_px"])
    x_hinge = int(plan["hinge_line_page_x_px"])
    x_te = int(plan["elevator_trailing_edge_page_x_px_nominal"])
    chord_px = x_te - x_le_tail
    elevator_px = x_te - x_hinge
    plan["chord_px_nominal"] = chord_px
    plan["chord_m_scan_scale"] = rounded(chord_px * mpp)
    plan["hinge_fraction_chord_nominal"] = round((x_hinge - x_le_tail) / chord_px, 4)
    plan["elevator_width_px_nominal"] = elevator_px
    plan["elevator_width_m_scan_scale"] = rounded(elevator_px * mpp)
    plan["candidate_z_m"] = {
        "leading_edge": rounded(z_from_x(x_le_tail)),
        "hinge": rounded(z_from_x(x_hinge)),
        "elevator_trailing_edge": rounded(z_from_x(x_te)),
    }

    trace_names = {
        "leading_edge": "leading_edge_trace_page_xy_px",
        "outboard_edge": "outboard_edge_trace_page_xy_px",
        "hinge_line": "hinge_line_trace_page_xy_px",
        "elevator_te": "elevator_te_trace_page_xy_px",
    }
    plan["converted_trace_candidate_coordinates_m"] = {
        "coordinate_order": ["z_m_from_page_x", "lateral_m_from_page_y"],
        "plan_centerline_page_y_px": root_y,
        "traces": {
            name: [
                [rounded(z_from_x(x)), rounded(lateral_from_page(y, root_y))]
                for x, y in plan[source_key]
            ]
            for name, source_key in trace_names.items()
        },
    }

    side = tail["side_view_placement"]
    side["candidate_z_m"] = {
        "hinge": rounded(z_from_x(side["fixed_to_moving_seam_page_x_px"])),
        "rounded_end": rounded(z_from_x(side["rounded_elevator_end_page_x_px"])),
    }
    side["candidate_y_m_proxy"] = rounded(y_from_page(side["tailplane_center_page_y_px"]))
    side["plan_te_vs_side_end_difference_px"] = (
        int(side["rounded_elevator_end_page_x_px"]) - x_te
    )

    data["arithmetic_audit"] = {
        "script": "research/ugly-stik/model-v3/recompute_us02_metrology.py",
        "method": "derived metric fields recomputed from saved source pixel picks; source point arrays unchanged",
        "source_coordinate_arrays_modified": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write recomputed derived values into the JSON")
    args = parser.parse_args()
    original = json.loads(DATA_PATH.read_text())
    recomputed = copy.deepcopy(original)
    apply_derived(recomputed)

    if args.write:
        DATA_PATH.write_text(json.dumps(recomputed, indent=2, ensure_ascii=False) + "\n")
        print(f"Wrote recomputed derived values: {DATA_PATH.relative_to(ROOT)}")
        return 0

    if original != recomputed:
        print("US-02 derived values differ from recomputation; run with --write.", file=sys.stderr)
        return 1
    print("US-02 arithmetic audit passed: saved derived values match raw-pick recomputation.")
    print(f"F6 z={recomputed['fuselage_sections'][2]['candidate_z_m']:.6f} m")
    print(f"Holdout z={recomputed['holdout_check']['candidate_z_m']:.6f} m")
    print("Tail elevator TE sample conversions (z m, lateral m):")
    for source, converted in zip(
        recomputed["horizontal_tail"]["plan_view"]["elevator_te_trace_page_xy_px"],
        recomputed["horizontal_tail"]["plan_view"]["converted_trace_candidate_coordinates_m"]["traces"]["elevator_te"],
    ):
        print(f"  px{tuple(source)} -> ({converted[0]:.6f}, {converted[1]:.6f})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
