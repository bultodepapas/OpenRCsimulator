"""Emit deterministic independent-reference and P51 geometry diagnostics."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
from pathlib import Path

import numpy
import scipy

import geometry_quadrature as geometry
from test_geometry_quadrature import independent_p51_strip_area


ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _rect(x0: float, x1: float, y0: float, y1: float) -> list[list[float]]:
    return [[x0, y0, 0.0], [x1, y0, 0.0], [x1, y1, 0.0], [x0, y1, 0.0]]


def _circle_cap_area(delta: float) -> float:
    coefficient = 1.0
    integral = 0.0
    for order in range(32):
        if order > 0:
            coefficient *= (order - 1.5) / order
        integral += coefficient * (delta / 2.0) ** order / (2.0 * order + 3.0)
    return 4.0 * math.sqrt(2.0) * delta**1.5 * integral


def _counts(result: dict) -> dict:
    return {key: result[key] for key in (
        "adaptive_interval_calls", "accepted_y_panels", "y_quadrature_evaluations",
        "x_quadrature_evaluations", "quadrature_node_count")}


def diagnostics() -> dict:
    disk_radius = 0.37
    disk_field = geometry.make_field_sampler([0, 0, 1], [0, 0, 0], disk_radius, s_min=None)
    disk = geometry.integrate_panel(_rect(-2, 2, -2, 2), disk_field,
                                    tolerance=1e-9, keep_samples=False)
    disk_exact = math.pi * disk_radius**2

    parallel_radius = 0.2
    parallel_panel = _rect(-1, 1, -1, 1)
    parallel_rows = []
    for mu in (1e-1, 1e-2, 1e-3, 1e-5, 1e-8, 0.0):
        axis = [math.sqrt(max(0.0, 1.0 - mu * mu)), 0.0, mu]
        field = geometry.make_field_sampler(axis, [0, 0, 0], parallel_radius, s_min=None)
        result = geometry.integrate_panel(parallel_panel, field, tolerance=2e-9, keep_samples=False)
        if mu == 0.0:
            exact = 4.0 * parallel_radius
        else:
            edge = math.sqrt(parallel_radius**2 - mu**2)
            exact = (2.0 * edge + 2.0 * parallel_radius**2 / mu
                     * math.asin(mu / parallel_radius))
        parallel_rows.append({"mu": mu, "area_m2": result["outer_geometric_area_m2"],
                              "exact_m2": exact,
                              "relative_error": abs(result["outer_geometric_area_m2"] - exact) / exact,
                              "error_from_exact_band_m2": abs(result["outer_geometric_area_m2"] - 4 * parallel_radius),
                              "counts": _counts(result)})

    tangent_rows = []
    for delta in (1e-1, 1e-3, 1e-5, 1e-7):
        field = geometry.make_field_sampler([0, 0, 1], [0, 0, 0], 1.0, s_min=None)
        result = geometry.integrate_panel(_rect(-2, 2, 1.0 - delta, 1.1), field,
                                          tolerance=2e-8, max_depth=22, keep_samples=False)
        exact = _circle_cap_area(delta)
        tangent_rows.append({"cap_depth_m": delta, "area_m2": result["outer_geometric_area_m2"],
                             "series_reference_m2": exact,
                             "relative_error": abs(result["outer_geometric_area_m2"] - exact) / exact,
                             "counts": _counts(result)})

    shrinking_rows = []
    for radius in (1.0, 1e-1, 1e-2, 1e-3, 1e-5):
        field = geometry.make_field_sampler([0, 0, 1], [0, 0, 0], radius, s_min=None)
        result = geometry.integrate_panel(_rect(-2 * radius, 2 * radius, -2 * radius, 2 * radius),
                                          field, tolerance=1e-9, keep_samples=False)
        exact = math.pi * radius**2
        shrinking_rows.append({"radius_m": radius, "area_m2": result["outer_geometric_area_m2"],
                               "exact_m2": exact,
                               "relative_error": abs(result["outer_geometric_area_m2"] - exact) / exact,
                               "counts": _counts(result)})

    p51 = geometry.p51_physics_panels()
    wake_radius = geometry.p51_static_wake_radius(p51)
    wake_field = geometry.make_field_sampler(p51["wake_path_body"], p51["hub_body_m"],
                                             wake_radius, s_min=0.0)
    p51_rows = []
    for panel in p51["panels"]:
        result = geometry.integrate_panel(panel["vertices_body_m"], wake_field,
                                          tolerance=2e-7, max_depth=20, keep_samples=False)
        independent_area, independent_error = independent_p51_strip_area(panel, p51, wake_radius)
        p51_rows.append({"strip": panel["id"], "area_m2": panel["expected_area_m2"],
                         "hard_tube_overlap_m2": result["outer_geometric_area_m2"],
                         "independent_body_y_quad_area_m2": independent_area,
                         "independent_quad_reported_abs_error_m2": independent_error,
                         "candidate_minus_independent_m2": result["outer_geometric_area_m2"] - independent_area,
                         "overlap_fraction": result["outer_geometric_area_m2"] / panel["expected_area_m2"],
                         "centroid_inside": geometry.p51_strip_centroid_hit(panel, wake_field),
                         "counts": _counts(result)})

    inputs = {
        "aircraft_json": ROOT / "app/data/aircraft/p51d_mustang_120.json",
        "runtime_slipstream": ROOT / "app/physics/slipstream.gd",
        "reused_e0b2_geometry": ROOT / "research/propwash/e0b2/derive_geometry.py",
        "candidate_kernel": HERE / "geometry_quadrature.py",
        "candidate_test": HERE / "test_geometry_quadrature.py",
        "candidate_runner": HERE / "run_candidate_diagnostics.py",
        "candidate_requirements": HERE / "requirements.txt",
    }
    return {
        "status": "offline geometric candidate; not runtime behavior or physical validation",
        "numeric_environment": {"python": platform.python_version(), "numpy": numpy.__version__,
                                "scipy": scipy.__version__,
                                "gauss_legendre_nodes": "scipy.special.roots_legendre"},
        "sha256": {name: _sha256(path) for name, path in inputs.items()},
        "normal_disk": {"radius_m": disk_radius, "area_m2": disk["outer_geometric_area_m2"],
                        "analytic_area_m2": disk_exact,
                        "relative_error": abs(disk["outer_geometric_area_m2"] - disk_exact) / disk_exact,
                        "raw_first_moment_m3": disk["raw_first_moment_m3"],
                        "raw_second_moment_m4": disk["raw_second_moment_m4"],
                        "counts": _counts(disk)},
        "near_parallel_to_exact_band": parallel_rows,
        "near_tangent_unit_circle_caps": tangent_rows,
        "shrinking_normal_disk": shrinking_rows,
        "p51_static_geometry": {
            "source_json_sha256": p51["source_data_sha256"],
            "wing_area_m2": p51["wing_area_m2"], "span_m": p51["span_m"],
            "root_chord_m": p51["root_chord_m"], "tip_chord_m": p51["tip_chord_m"],
            "hub_body_m": p51["hub_body_m"], "wake_path_body": p51["wake_path_body"],
            "propeller_diameter_m": p51["prop_diameter_m"],
            "modeled_static_radius_ratio": 0.7071,
            "static_tube_radius_m": wake_radius,
            "strip_edges_m": p51["edges_m"],
            "strip_rows": p51_rows,
            "sum_strip_area_m2": math.fsum(row["area_m2"] for row in p51_rows),
            "sum_hard_tube_overlap_m2": math.fsum(row["hard_tube_overlap_m2"] for row in p51_rows),
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=HERE / "candidate-results.json")
    args = parser.parse_args()
    output = json.dumps(diagnostics(), indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    args.output.write_text(output, encoding="utf-8")
    print(output, end="")


if __name__ == "__main__":
    main()
