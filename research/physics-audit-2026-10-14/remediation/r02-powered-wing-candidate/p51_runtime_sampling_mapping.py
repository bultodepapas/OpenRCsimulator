"""Compare P-51 candidate polygon geometry with current runtime wing samples.

The output is a mapping receipt only. It does not change candidate-results.json
or claim that the inferred flat trapezoid is the runtime's wing surface.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import math
import sys
import re
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
KERNEL_PATH = HERE / "geometry_quadrature.py"
SPEC = importlib.util.spec_from_file_location("r02_geometry_quadrature", KERNEL_PATH)
assert SPEC is not None and SPEC.loader is not None
gq = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = gq
SPEC.loader.exec_module(gq)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_value(node):
    return node["value"]


def runtime_station_ys(span: float, root: float, tip: float, stations_per_side: int):
    """Port AircraftData.station_ys() trapezoid branch for evidence comparison."""
    h = span / 2.0
    centres = []
    if math.isclose(root, tip, rel_tol=1e-5, abs_tol=1e-5):
        centres = [(k + 0.5) / stations_per_side * h
                   for k in range(stations_per_side)]
    else:
        slope = (tip - root) / h
        area = lambda y: root * y + slope * y * y / 2.0
        moment = lambda y: root * y * y / 2.0 + slope * y * y * y / 3.0
        total = area(h)
        y0 = 0.0
        for k in range(stations_per_side):
            target = total * (k + 1) / stations_per_side
            y1 = (h if k == stations_per_side - 1 else
                  (-root + math.sqrt(root * root + 2.0 * slope * target)) / slope)
            centres.append((moment(y1) - moment(y0)) / (area(y1) - area(y0)))
            y0 = y1
    return [-centres[k] for k in range(stations_per_side - 1, -1, -1)] + centres


def main():
    aircraft_path = REPO / "app" / "data" / "aircraft" / "p51d_mustang_120.json"
    aero_path = REPO / "app" / "physics" / "aero.gd"
    aero_source = aero_path.read_text(encoding="utf-8")
    station_count_match = re.search(r"const WING_STATIONS_PER_SIDE := (\d+)", aero_source)
    if station_count_match is None:
        raise RuntimeError("could not read Aero.WING_STATIONS_PER_SIDE from the current source")
    stations_per_side = int(station_count_match.group(1))
    aircraft = json.loads(aircraft_path.read_text(encoding="utf-8"))
    physics = gq.p51_physics_panels()
    ref = aircraft["reference"]
    arp = source_value(ref["aero_reference_point"])
    cg = source_value(aircraft["balance"]["plan_cg"])
    span = source_value(ref["wing_span"])
    root_chord = source_value(ref["root_chord"])
    tip_chord = source_value(ref["tip_chord"])
    ys = runtime_station_ys(span, root_chord, tip_chord, stations_per_side)

    # Aero._arm([aft,right,up], cg) -> body FRD arm from CG. _wing_flow
    # samples at arm.x/z and arm.y + station_y; _local_loads uses the same axes.
    arp_arm_body = [-(arp[0] - cg[0]), arp[1] - cg[1], -(arp[2] - cg[2])]
    runtime_points = [
        {"station_index": i, "station_y_m": y,
         "point_body_m": [arp_arm_body[0], arp_arm_body[1] + y, arp_arm_body[2]]}
        for i, y in enumerate(ys)
    ]

    radius = gq.p51_static_wake_radius(physics)
    field = gq.make_field_sampler(physics["wake_path_body"], physics["hub_body_m"],
                                  radius, s_min=0.0, s_max=None, edge_fraction=0.0)
    runtime_hits = []
    for sample in runtime_points:
        classification = field["sample_at"](sample["point_body_m"])
        delta = [sample["point_body_m"][i] - physics["hub_body_m"][i] for i in range(3)]
        along = sum(delta[i] * physics["wake_path_body"][i] for i in range(3))
        radial = [delta[i] - along * physics["wake_path_body"][i] for i in range(3)]
        runtime_hits.append({**sample, "candidate_tube_s_m": classification["s"],
                             "radial_distance_m": math.sqrt(sum(value * value for value in radial)),
                             "inside_candidate_static_hard_tube": classification["inside"],
                             "occupancy": classification["occupancy"]})

    panel_comparison = []
    for panel in physics["panels"]:
        station_index = int(panel["id"].replace("strip_", ""))
        runtime_point = runtime_points[station_index]["point_body_m"]
        centroid = panel["centroid_body_m"]
        point_sample = field["sample_at"](centroid)
        overlap = gq.integrate_panel(panel["vertices_body_m"], field,
                                     tolerance=1e-9, max_depth=18,
                                     keep_samples=False)
        panel_comparison.append({
            "strip_id": panel["id"],
            "runtime_station_sample_index": station_index,
            "runtime_station_sample_body_m": runtime_point,
            "candidate_polygon_source_area_m2": panel["expected_area_m2"],
            "candidate_polygon_centroid_body_m": centroid,
            "runtime_point_minus_polygon_centroid_body_m": [runtime_point[i] - centroid[i] for i in range(3)],
            "candidate_centroid_inside_candidate_static_hard_tube": point_sample["inside"],
            "candidate_polygon_hard_tube_intersection_area_m2": overlap["outer_geometric_area_m2"],
            "candidate_polygon_weighted_area_m2": overlap["occupancy_weighted_area_m2"],
        })

    outputs = {
        "title": "P-51 runtime wing-sample versus candidate polygon mapping",
        "scope": "Read-only mapping of current strip sampling points to the candidate wake; no runtime or aircraft data changes",
        "geometry_identity": {
            "aircraft_data_sha256": physics["source_data_sha256"],
            "candidate_geometry_kernel_sha256": sha256(KERNEL_PATH),
        },
        "source_locations": {
            "aero_wing_flow": "app/physics/aero.gd:267-294; x/z at ARP arm and y at ARP arm plus station_ys",
            "aero_local_load_arms": "app/physics/aero.gd:306-329, 398-443; station force moments use ARP x/z and station y",
            "aero_arm_conversion": "app/physics/aero.gd:537-539; LE [aft,right,up] to body FRD arm",
            "station_ys": "app/physics/aircraft_data.gd:580-604; equal-area strip centroid locations",
            "station_count": f"app/physics/aero.gd:19; {stations_per_side} stations per semispan, parsed from source",
            "candidate_polygon_builder": "research/physics-audit-2026-10-14/remediation/r02-powered-wing-candidate/geometry_quadrature.py:p51_physics_panels",
        },
        "interpretation": {
            "runtime_representation": "Six spanwise strip sample/load points; no explicit planform polygon vertices are used by _wing_flow/_local_loads.",
            "candidate_representation": "A separate inferred flat, unswept trapezoid panel per strip, from authored span/root/tip chord and the ARP z plane; each polygon centroid is an area centroid.",
            "not_equivalent": "Candidate polygon centroids have varying x along the trapezoid and do not equal runtime points at the ARP x/z. Polygon hit area is not the current runtime's per-strip aerodynamic integration.",
            "wake": "The geometric query uses authored hub and thrust axis, runtime RADIUS_MIN=0.7071, and s>=0 as a candidate static hard tube. It is not the current dynamic wake state or an existing wing-wash load coupling.",
            "current_wing_wash_behavior": "Aero._wing_flow/_local_loads use the six ARP-based points without a Slipstream sample. Dynamics adds Slipstream.loads separately; that opt-in path computes washed tail loads.",
        },
        "derived_runtime_samples": {
            "arp_le_m": arp, "plan_cg_le_m": cg, "arp_body_arm_m": arp_arm_body,
            "span_m": span, "root_chord_m": root_chord, "tip_chord_m": tip_chord,
            "station_ys_m": ys, "points_body_frd_m": runtime_points,
            "wake_origin_hub_body_m": physics["hub_body_m"],
            "wake_path_body": physics["wake_path_body"],
            "wake_radius_m": radius,
            "hard_wake_boundaries": {"s_min_m": 0.0, "s_max": None, "edge_fraction": 0.0},
        },
        "runtime_point_wake_hits": runtime_hits,
        "candidate_polygon_and_centroid_comparison": panel_comparison,
        "summary": {
            "runtime_sample_candidate_tube_hit_count": sum(bool(row["inside_candidate_static_hard_tube"]) for row in runtime_hits),
            "candidate_centroid_candidate_tube_hit_count": sum(bool(row["candidate_centroid_inside_candidate_static_hard_tube"]) for row in panel_comparison),
            "candidate_polygon_nonzero_overlap_count": sum(row["candidate_polygon_hard_tube_intersection_area_m2"] > 0.0 for row in panel_comparison),
        },
        "source_sha256": {
            "aircraft_json": sha256(aircraft_path),
            "aero_gd": sha256(aero_path),
            "aircraft_data_gd": sha256(REPO / "app" / "physics" / "aircraft_data.gd"),
            "slipstream_gd": sha256(REPO / "app" / "physics" / "slipstream.gd"),
            "geometry_quadrature_py": sha256(KERNEL_PATH),
            "mapping_probe_py": sha256(Path(__file__)),
            "historical_candidate_results_unchanged": sha256(HERE / "candidate-results.json"),
            "coordinate_covariance_results": sha256(HERE / "coordinate-covariance-results.json")
                if (HERE / "coordinate-covariance-results.json").exists() else None,
            "r02_readme": sha256(REPO / "docs" / "research" / "physics-audit-2026-10-14" / "remediation" / "R02-powered-wing-candidate" / "README.md"),
        },
    }
    output_path = HERE / "p51-runtime-sampling-mapping.json"
    output_path.write_text(json.dumps(outputs, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output_path), **outputs["summary"],
                      "sha256": sha256(output_path)}, indent=2))


if __name__ == "__main__":
    main()
