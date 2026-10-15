"""Independent rigid-coordinate covariance checks for the offline R02 kernel.

This probe does not change candidate-results.json. It checks both integrated
moments and direct field samples under one proper rotation and one reflection.
The reflection transforms angular velocity as an axial vector.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import math
import platform
import sys
from pathlib import Path

import numpy as np
import scipy


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
KERNEL_PATH = HERE / "geometry_quadrature.py"
KERNEL_SPEC = importlib.util.spec_from_file_location("r02_geometry_quadrature", KERNEL_PATH)
assert KERNEL_SPEC is not None and KERNEL_SPEC.loader is not None
gq = importlib.util.module_from_spec(KERNEL_SPEC)
sys.modules[KERNEL_SPEC.name] = gq
KERNEL_SPEC.loader.exec_module(gq)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def unit(v):
    arr = np.asarray(v, dtype=float)
    return arr / np.linalg.norm(arr)


def skew_axis_rotation(axis, angle):
    x, y, z = unit(axis)
    c, s = math.cos(angle), math.sin(angle)
    one_c = 1.0 - c
    return np.array([
        [c + x*x*one_c, x*y*one_c - z*s, x*z*one_c + y*s],
        [y*x*one_c + z*s, c + y*y*one_c, y*z*one_c - x*s],
        [z*x*one_c - y*s, z*y*one_c + x*s, c + z*z*one_c],
    ])


def packed_to_matrix(values):
    xx, xy, xz, yy, yz, zz = values
    return np.array([[xx, xy, xz], [xy, yy, yz], [xz, yz, zz]], dtype=float)


def pack_symmetric(matrix):
    return [float(matrix[0, 0]), float(matrix[0, 1]), float(matrix[0, 2]),
            float(matrix[1, 1]), float(matrix[1, 2]), float(matrix[2, 2])]


def transformed_expected(result, q, translation):
    t = np.asarray(translation, dtype=float)
    answer = {
        "source_panel_area_m2": result["source_panel_area_m2"],
        "outer_geometric_area_m2": result["outer_geometric_area_m2"],
        "occupancy_weighted_area_m2": result["occupancy_weighted_area_m2"],
    }
    for prefix, area_key in (("raw", "outer_geometric_area_m2"),
                             ("weighted", "occupancy_weighted_area_m2")):
        area = result[area_key]
        first = np.asarray(result[f"{prefix}_first_moment_m3"], dtype=float)
        second = packed_to_matrix(result[f"{prefix}_second_moment_m4"])
        qfirst = q @ first
        answer[f"{prefix}_first_moment_m3"] = qfirst + area * t
        answer[f"{prefix}_second_moment_m4"] = pack_symmetric(
            q @ second @ q.T + np.outer(qfirst, t) + np.outer(t, qfirst)
            + area * np.outer(t, t))

    velocity_first = np.asarray(result["velocity_first_moment_m3ps"], dtype=float)
    velocity_second = packed_to_matrix(result["velocity_second_moment_m4ps2"])
    answer["velocity_first_moment_m3ps"] = q @ velocity_first
    answer["velocity_second_moment_m4ps2"] = pack_symmetric(q @ velocity_second @ q.T)
    return answer


def compare_integrals(reference, observed, q, translation):
    expected = transformed_expected(reference, q, translation)
    comparisons = {}
    for key, target in expected.items():
        actual = observed[key]
        target_array = np.asarray(target, dtype=float)
        actual_array = np.asarray(actual, dtype=float)
        residual = actual_array - target_array
        comparisons[key] = {
            "max_abs_residual": float(np.max(np.abs(residual))),
            "l2_residual": float(np.linalg.norm(residual.ravel())),
            "relative_l2_residual": float(np.linalg.norm(residual.ravel()) /
                max(1.0, float(np.linalg.norm(target_array.ravel())))),
        }
    return comparisons


def transform_field_input(field_spec, q, translation, *, axial_omega=True):
    determinant = float(np.linalg.det(q))
    axis = q @ np.asarray(field_spec["axis"])
    origin = q @ np.asarray(field_spec["origin"]) + translation
    delta_v = q @ np.asarray(field_spec["delta_v"])
    omega0 = np.asarray(field_spec["omega"])
    omega = (determinant * (q @ omega0) if axial_omega else q @ omega0)
    # Keep v(p)=ambient + omega×p + delta_v covariant despite translation.
    ambient = q @ np.asarray(field_spec["ambient"]) - np.cross(omega, translation)
    return {**field_spec, "axis": axis.tolist(), "origin": origin.tolist(),
            "delta_v": delta_v.tolist(), "omega": omega.tolist(),
            "ambient": ambient.tolist()}


def transform_panel(panel, q, translation):
    return [(q @ np.asarray(p, dtype=float) + translation).tolist() for p in panel]


def direct_field_check(field, transformed_field_spec, q, translation):
    transformed_field = gq.make_field_sampler(**transformed_field_spec)
    samples = []
    path = np.asarray(field["axis"])
    origin = np.asarray(field["origin"])
    basis_seed = np.array([1.0, -0.4, 0.7])
    radial = unit(basis_seed - path * float(path @ basis_seed))
    radial_2 = np.cross(path, radial)
    # Stay off the discontinuous finite-s endpoints and hard radial boundary:
    # a rigid transform in float64 can move an exact boundary sample by one ulp.
    s_values = [field["s_min"] - 1e-7, field["s_min"] + 1e-7,
                0.5 * (field["s_min"] + field["s_max"]),
                field["s_max"] - 1e-7, field["s_max"] + 1e-7]
    if field["edge_fraction"] == 0.0:
        radius_values = [0.0, field["radius"] * (1.0 - 1e-7),
                         field["radius"] * (1.0 + 1e-7), field["radius"] * 1.13]
    else:
        inner, outer = field["inner_radius"], field["outer_radius"]
        radius_values = [0.0, inner, 0.5 * (inner + field["radius"]),
                         field["radius"], 0.5 * (field["radius"] + outer),
                         outer, outer * 1.13]
    for s in s_values:
        for r in radius_values:
            for phase in (0.0, 1.7):
                radial_dir = math.cos(phase) * radial + math.sin(phase) * radial_2
                point = origin + s * path + r * radial_dir
                moved = q @ point + translation
                before = field["sample_at"](point.tolist())
                after = transformed_field["sample_at"](moved.tolist())
                occ_error = abs(after["occupancy"] - before["occupancy"])
                s_error = abs(after["s"] - before["s"])
                expected_air = q @ np.asarray(before["air_velocity"])
                air_error = float(np.max(np.abs(np.asarray(after["air_velocity"]) - expected_air)))
                expected_dv = q @ np.asarray(before["weighted_delta_v"])
                dv_error = float(np.max(np.abs(np.asarray(after["weighted_delta_v"]) - expected_dv)))
                samples.append({"s_m": s, "radial_m": r, "phase_rad": phase,
                                "occupancy_abs_error": occ_error,
                                "path_coordinate_abs_error_m": s_error,
                                "air_velocity_max_abs_error_mps": air_error,
                                "weighted_delta_v_max_abs_error_mps": dv_error})
    return {
        "sample_count": len(samples),
        "max_occupancy_abs_error": max(row["occupancy_abs_error"] for row in samples),
        "max_path_coordinate_abs_error_m": max(row["path_coordinate_abs_error_m"] for row in samples),
        "max_air_velocity_abs_error_mps": max(row["air_velocity_max_abs_error_mps"] for row in samples),
        "max_weighted_delta_v_abs_error_mps": max(row["weighted_delta_v_max_abs_error_mps"] for row in samples),
        "cases": samples,
    }


def main():
    center = np.array([0.31, -0.42, 0.23])
    e_a = unit([0.91, 0.27, -0.19])
    candidate_b = np.array([-0.24, 0.83, 0.49])
    e_b = unit(candidate_b - e_a * float(e_a @ candidate_b))
    half_a, half_b = 0.72, 0.39
    panel = [
        (center - half_a * e_a - half_b * e_b).tolist(),
        (center + half_a * e_a - half_b * e_b).tolist(),
        (center + half_a * e_a + half_b * e_b).tolist(),
        (center - half_a * e_a + half_b * e_b).tolist(),
    ]
    axis = unit([0.22, 0.79, 0.57])
    radial0 = unit(np.array([0.7, -0.2, 0.4]) - axis * float(axis @ np.array([0.7, -0.2, 0.4])))
    origin = center - 0.27 * axis + 0.13 * radial0
    base_spec = {
        "axis": axis.tolist(), "origin": origin.tolist(), "radius": 0.43,
        "delta_v": [7.5, -1.7, 2.2], "ambient": [3.1, -2.6, 1.4],
        "omega": [0.37, -0.29, 0.61], "s_min": 0.04, "s_max": 0.54,
    }
    translation = np.array([1.35, -0.88, 0.46])
    q_rotation = skew_axis_rotation([0.4, -0.7, 0.3], 0.81)
    mirror_normal = unit([0.35, 0.61, -0.71])
    q_mirror = np.eye(3) - 2.0 * np.outer(mirror_normal, mirror_normal)

    output = {
        "title": "R02 wing immersion rigid-coordinate covariance probe",
        "probe_scope": "synthetic tilted planar panel; proper rotation and mirror; no runtime/data changes",
        "python": platform.python_version(), "numpy": np.__version__, "scipy": scipy.__version__,
        "transform_parameters": {
            "translation_m": translation.tolist(),
            "proper_rotation_matrix": q_rotation.tolist(),
            "proper_rotation_determinant": float(np.linalg.det(q_rotation)),
            "mirror_matrix": q_mirror.tolist(),
            "mirror_determinant": float(np.linalg.det(q_mirror)),
            "mirror_omega_rule": "omega_prime = det(Q) * Q * omega (axial vector)",
            "ambient_translation_rule": "ambient_prime = Q*ambient - omega_prime cross translation",
        },
        "source_parameters": {"panel_vertices_body_m": panel, "field": base_spec,
                               "quadrature_tolerance": 2e-9, "max_depth": 18},
        "cases": [],
    }

    for edge_fraction in (0.0, 0.14):
        field_spec = {**base_spec, "edge_fraction": edge_fraction}
        base_field = gq.make_field_sampler(**field_spec)
        baseline = gq.integrate_panel(panel, base_field, tolerance=2e-9,
                                      max_depth=18, keep_samples=False)
        for label, q in (("proper_rotation", q_rotation), ("mirror", q_mirror)):
            moved_spec = transform_field_input(field_spec, q, translation)
            moved_field = gq.make_field_sampler(**moved_spec)
            moved_panel = transform_panel(panel, q, translation)
            moved = gq.integrate_panel(moved_panel, moved_field, tolerance=2e-9,
                                       max_depth=18, keep_samples=False)
            field_check = direct_field_check(base_field, moved_spec, q, translation)
            wrong_omega_check = None
            if label == "mirror":
                wrong_spec = transform_field_input(field_spec, q, translation, axial_omega=False)
                wrong_omega_check = direct_field_check(base_field, wrong_spec, q, translation)
            output["cases"].append({
                "edge_fraction": edge_fraction,
                "occupancy_model": "hard" if edge_fraction == 0.0 else "smooth cubic in squared radius",
                "transform": label,
                "determinant": float(np.linalg.det(q)),
                "source_area_m2": baseline["source_panel_area_m2"],
                "integrated_raw_area_m2": baseline["outer_geometric_area_m2"],
                "integrated_occupancy_area_m2": baseline["occupancy_weighted_area_m2"],
                "baseline_quadrature_counts": {
                    "x": baseline["x_quadrature_evaluations"],
                    "y": baseline["y_quadrature_evaluations"],
                    "adaptive_calls": baseline["adaptive_interval_calls"],
                },
                "transformed_quadrature_counts": {
                    "x": moved["x_quadrature_evaluations"],
                    "y": moved["y_quadrature_evaluations"],
                    "adaptive_calls": moved["adaptive_interval_calls"],
                },
                "integral_covariance_residuals": compare_integrals(baseline, moved, q, translation),
                "direct_sampler_covariance": field_check,
                "incorrect_polar_omega_negative_control": wrong_omega_check,
                "moved_raw_area_m2": moved["outer_geometric_area_m2"],
                "moved_occupancy_area_m2": moved["occupancy_weighted_area_m2"],
            })

    paths = {
        "probe": Path(__file__),
        "kernel": KERNEL_PATH,
        "candidate_results_preserved": HERE / "candidate-results.json",
        "readme": REPO / "docs" / "research" / "physics-audit-2026-10-14" / "remediation" / "R02-powered-wing-candidate" / "README.md",
        "p51_source": REPO / "app" / "data" / "aircraft" / "p51d_mustang_120.json",
        "slipstream_source": REPO / "app" / "physics" / "slipstream.gd",
    }
    output["source_sha256"] = {key: sha256(path) for key, path in paths.items()}
    out_path = HERE / "coordinate-covariance-results.json"
    out_path.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(out_path), "cases": len(output["cases"]),
        "max_integral_relative_l2": max(
            residual["relative_l2_residual"]
            for case in output["cases"]
            for residual in case["integral_covariance_residuals"].values()),
        "max_direct_air_velocity_error_mps": max(
            case["direct_sampler_covariance"]["max_air_velocity_abs_error_mps"]
            for case in output["cases"]),
        "sha256": sha256(out_path),
    }, indent=2))


if __name__ == "__main__":
    main()
