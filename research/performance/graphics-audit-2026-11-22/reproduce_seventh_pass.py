#!/usr/bin/env python3
"""Reproduce seventh-pass arithmetic and a reducer counterexample; no simulator."""
from __future__ import annotations

import argparse
import ast
import copy
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess

MAIN = "843f357c07af842054f3ccd6728f93beca9a57ef"
SOURCES = (
    "app/data/scenery/default.json",
    "app/scenery/imported_hedge.gd",
    "app/scenery/scenery.gd",
    "app/render/field.gd",
    "app/sim/race/race_model.gd",
    "app/sim/race/race_director.gd",
    "app/physics/math3d.gd",
    "app/physics/multirotor/allocator.gd",
    "app/physics/multirotor/flight_controller.gd",
    "research/native-kernel/src/nk_pack_ecm.hpp",
    "research/native-kernel/src/nk_electric_stage.hpp",
    "research/native-kernel/src/nk_stage.hpp",
    "app/assets/vehicle-paints/turbo-lumber-evolution/chapa_noble.gdshader",
    "app/render/timber_stock_paint.gd",
    "app/render/vehicle_paint.gd",
    "app/data/vehicle_paints.json",
    "app/render/flight_dynamic_resolution.gd",
    "app/debug/godtest_driver.gd",
    "tools/godtest/analysis.py",
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        parser.error("--out must be new")

    def source(path: str) -> bytes:
        return subprocess.check_output(["git", "show", f"{MAIN}:{path}"], cwd=args.repo)

    blobs = {path: source(path) for path in SOURCES}
    layout = json.loads(blobs["app/data/scenery/default.json"])

    def objects(value):
        if isinstance(value, dict):
            yield value
            for child in value.values():
                yield from objects(child)
        elif isinstance(value, list):
            for child in value:
                yield from objects(child)

    rows = [row for row in objects(layout) if row.get("id") == "club-perimeter"]
    assert len(rows) == 1
    hedge = rows[0]
    points = hedge["points"]["value"]
    height = hedge["height"]["value"]

    def f32(value):
        return struct.unpack("f", struct.pack("f", value))[0]

    def lengths(float32: bool):
        values = [[f32(v) for v in p] if float32 else p for p in points]
        result = []
        for a, b in zip(values, values[1:]):
            x, y = b[0] - a[0], b[1] - a[1]
            if float32:
                x, y = f32(x), f32(y)
                length = f32(math.sqrt(f32(f32(x * x) + f32(y * y))))
            else:
                length = math.hypot(x, y)
            assert length > 0.01
            result.append(length)
        return result

    geometry = {}
    for name, vector_float32 in (("authored_float64", False), ("vector_float32_model", True)):
        segments = lengths(vector_float32)
        total = sum(segments)
        tiers = {}
        for tier, ratio in (("low", .92), ("balanced", .78), ("high", .67)):
            spacing = max(height * ratio, total / 1024)
            counts, candidate_count = [], 0
            for length in segments:
                count = min(max(1, math.floor(length / spacing + .5)), 1024 - candidate_count)
                counts.append(count)
                candidate_count += count
            tiers[tier] = {
                "spacing_m": spacing,
                "segment_counts": counts,
                "cards": candidate_count,
                "card_mesh_triangles": 2 * candidate_count,
                "instance_setter_calls_per_build": 3 * candidate_count,
                "minimum_distance_to_rounding_half": min(abs((v / spacing) % 1 - .5) for v in segments),
            }
        geometry[name] = {"path_length_m": total, "segment_lengths_m": segments, "tiers": tiers}
    for tier in ("low", "balanced", "high"):
        assert geometry["authored_float64"]["tiers"][tier]["cards"] == geometry["vector_float32_model"]["tiers"][tier]["cards"]

    # Execute only the existing pure reducer function, isolated from module startup.
    # The candidate describes missing evidence; it is not an app-lifecycle replay.
    module = ast.parse(blobs["tools/godtest/analysis.py"].decode("utf-8"))
    functions = [node for node in module.body if isinstance(node, ast.FunctionDef) and node.name == "_dynamic_resolution_problem"]
    assert len(functions) == 1
    namespace = {"math": math}
    exec(compile(ast.Module(body=functions, type_ignores=[]), "pinned-analysis.py", "exec"), namespace)
    reducer = namespace["_dynamic_resolution_problem"]
    manifest = {"dynamic_resolution_fps": 60, "resolution": [1920, 1080], "render_scale": 100}
    observation = {"phase_id": "recover", "observed_usec": 5, "status": {
        "state": "observing", "target_fps": 60, "configured_scale": 1.0,
        "completed_frame": {"frame_id": 4, "generation": 3, "input_size": [1920, 1080], "output_size": [1920, 1080]},
    }}
    phase = {"id": "recover", "start_usec": 1, "end_usec": 100, "dynamic_resolution": [observation]}
    cases = {"earlier_confirmation_only": phase, "missing_all_observations": {**phase, "dynamic_resolution": []}}
    explicit_loss = copy.deepcopy(phase)
    explicit_loss["dynamic_resolution"].append({"phase_id": "recover", "observed_usec": 90,
        "status": {"state": "fixed", "target_fps": 60, "reason": "controller_stopped"}})
    cases["explicit_later_fixed_observation"] = explicit_loss
    reducer_results = {name: reducer(case, manifest) for name, case in cases.items()}
    assert reducer_results["earlier_confirmation_only"] == ""
    assert reducer_results["missing_all_observations"] and reducer_results["explicit_later_fixed_observation"]

    paint_headers = []
    for name in ("elan_35_fuselage.png", "elan_35_fuselage_low.png", "elan_35_wing.png", "elan_35_wing_low.png",
                 "jeti_ruby_fuselage.png", "jeti_ruby_wing.png", "jeti_ruby_fin.png", "jeti_ruby_stab.png"):
        path = "app/assets/vehicle-paints/avanti-s-a200/" + name
        data = source(path)
        assert data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR"
        width, pixel_height = struct.unpack(">II", data[16:24])
        paint_headers.append({"path": path, "width": width, "height": pixel_height,
            "base_texels": width * pixel_height, "sha256": hashlib.sha256(data).hexdigest()})

    data = {
        "schema": 1,
        "source_commit": MAIN,
        "reproducer_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "source_sha256": {p: hashlib.sha256(b).hexdigest() for p, b in blobs.items()},
        "paint_source_images": paint_headers,
        "paint_base_texel_totals": {"elan_low_medium_pair": 4096 * 4096 + 4096 * 2048,
            "elan_high_extreme_pair": 8192 * 8192 + 8192 * 4096,
            "jeti_four_albedos": 2 * 4096 * 4096 + 2 * 2048 * 2048,
            "not_measured": "Imported compression, residency, cache lifetime, RAM/VRAM and FPS."},
        "X01_hedge": geometry,
        "X02_race_per_simulated_second": {
            "assumption": "240 successful wrapped, no-start sampled ticks; endpoint extension additionally requires unfiltered non-RACING candidates and a proven validity guard",
            "sample_rotations": 240,
            "sample_norms": 240,
            "sample_plus_endpoint_rotations": 3 * 240,
            "sample_plus_endpoint_norms": 2 * 240,
        },
        "X03_pack_per_simulated_second": {
            "assumption": "240 admitted native successful one-piece RK4 ticks, one RC branch, four stages; not event/substep/refusal counts",
            "current_table_samples": 2 * 4 * 4 * 240,
            "maximum_guarded_sample_reuse": 4 * 4 * 240,
            "actual_equal_weight_hit_rate": None,
            "temperature_weight_preparations": 2 * 4 * 240,
            "candidate_temperature_preparations": 4 * 240,
        },
        "X04_allocator": {"free_rotor_masks": 2 ** 4, "maximum_active_set_iterations": 16, "reference_status_codes": 3 ** 4, "maximum_examined_reference_sets": 3 ** 4, "observed_saturation_fraction": None},
        "X05_chapa_noble": {"flake_airflow_derivative_threshold_m_per_pixel": 1 / 960, "hashes_per_mottling": 4, "source_hash_expression": "4 * eligible_striation_fragments + 4 * eligible_flake_fragments", "observed_pixel_coverage": None},
        "X06_observation_gap": {"pure_reducer_results": reducer_results,
            "meaning": "The reducer accepts an earlier confirmation with no later observation; it rejects an explicit later fixed state. Source shows an empty status is omitted by the producer. Actual in-flight stop reachability and whole-report outcomes are not executed."},
        "limitations": [
            "Source arithmetic only: no Godot, GPU, native component, whole-flight or hardware benchmark was executed by this reproducer.",
            "Both hedge arithmetic models agree on counts. The float32 model is not a Godot execution or proof of backend floating-point behavior.",
            "Source triangles and setter calls do not equal visible primitives, driver calls, memory allocations, milliseconds or FPS.",
            "The pack upper bound needs exact-weight guarded reuse; mathematical equality of average and weak SOC is insufficient.",
            "Cadence is per simulated second and successful eligible ticks. Event trials, substeps, pause and rejected samples change totals.",
        ],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("x", encoding="utf-8") as stream:
        json.dump(data, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")
    print(json.dumps({"source": MAIN, "hedge_cards": {k: v["cards"] for k, v in geometry["vector_float32_model"]["tiers"].items()}, "native_pack_sample_reuse_upper_bound_per_sim_second": 3840}))


if __name__ == "__main__":
    main()
