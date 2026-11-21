#!/usr/bin/env python3
"""A36 R4: independent geometry/force witnesses for the fixed-wing tail wake.

This is NOT a Godot execution or a complete model-admission test. It repeats the
published formulas, NOT application helper calls, for a synthetic valid-range
vertical-tail piece at small angle and compares a duplicated piece with its
physically unique area. Python 3 standard library only.
"""
import math
from pathlib import Path
import argparse

RHO_KG_M3 = 1.225
TAIL_LIFT_SLOPE_RAD_INV = 4.0
TAIL_CD0 = 0.02
TAIL_K = 0.05
TAIL_CD90 = 1.2
PHYSICAL_TAIL_AREA_M2 = 0.15
PIECE_AREA_M2 = 0.10
AXIAL_UNWASHED_MPS = 12.0
AXIAL_WASHED_MPS = 17.0
SIDE_FLOW_MPS = 0.8


def vertical_tail_side_force(u_mps: float, side_mps: float, area_m2: float) -> float:
    """Source-matched attached _tail_curve + _surface_with_flow FY."""
    v = math.hypot(u_mps, side_mps)
    alpha = math.atan2(side_mps, u_mps)
    cl = TAIL_LIFT_SLOPE_RAD_INV * alpha
    cd = TAIL_CD0 + TAIL_K * cl * cl + TAIL_CD90 * math.sin(alpha)**2
    lift_n = 0.5 * RHO_KG_M3 * v*v * area_m2 * cl
    drag_scale = -0.5 * RHO_KG_M3 * v * area_m2 * cd
    return side_mps * drag_scale - lift_n * u_mps/v


def run(repo_root: Path | None = None) -> None:
    free = vertical_tail_side_force(AXIAL_UNWASHED_MPS, SIDE_FLOW_MPS, PIECE_AREA_M2)
    washed = vertical_tail_side_force(AXIAL_WASHED_MPS, SIDE_FLOW_MPS, PIECE_AREA_M2)
    one = washed - free
    duplicate = one + one
    assert math.isclose(one, -0.98285091063401, abs_tol=1e-11)
    assert math.isclose(duplicate, 2 * one, rel_tol=1e-14)
    assert one != 0
    fraction = 2 * PIECE_AREA_M2 / PHYSICAL_TAIL_AREA_M2
    assert fraction > 1.
    print("A36 R4: analytical wake-force source-formula mirror; NO Godot run")
    print(f"one-piece free side force:     {free:.12f} N")
    print(f"one-piece washed side force:   {washed:.12f} N")
    print(f"one-piece delta:               {one:.12f} N")
    print(f"two identical pieces delta:    {duplicate:.12f} N")
    print(f"identical-force ratio:         {duplicate/one:.12f} x")
    print(f"claimed/physical surface area: {fraction:.12f} x")
    # In the spatial path the model has 6 wing + 2 tail + 1 propulsion
    # point plus one reference datum: ten ambient samples per stage.
    stations = 6 + 2 + 1
    queries_per_stage = 1 + stations
    typical_stage_calls = 4
    physics_tick_hz = 240
    print(f"typical conventional spatial-stage wind queries: {queries_per_stage}/stage")
    print(f"4 evaluations at 240 Hz: {queries_per_stage*typical_stage_calls*physics_tick_hz}/s")
    print("This is an illustrative count for the stated configuration, not a measured call count, upper bound or FPS/memory benchmark; see A6 O5.")
    if repo_root is not None:
        loader = (repo_root/"app/physics/aircraft_data.gd").read_text()
        aero = (repo_root/"app/physics/aero.gd").read_text()
        wake = (repo_root/"app/physics/slipstream.gd").read_text()
        swirl = (repo_root/"app/physics/swirl_loads.gd").read_text()
        native = (repo_root/"research/native-kernel/src/nk_wake.hpp").read_text()
        assert 'for name in (["vertical"] if tailless else ["horizontal", "vertical"])' in loader
        assert 'if not vertical and not surfaces.has("horizontal"):' in aero
        assert 'if surfaces.horizontal.has("free_slope")' in wake
        assert 'if surfaces.horizontal.has("free_slope")' in swirl
        assert 'if (m.horizontal.present && m.horizontal.free)' in native
        assert 'for piece_index in ss.pieces.size():' in wake
        assert 'if not (surface in ["horizontal", "vertical"]):' in loader
        print("PASS source fingerprints match; no admission/runtime inference made.")
    print("PASS independent physical-area and numerical checks.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=None)
    args = parser.parse_args()
    run(args.repo_root)
