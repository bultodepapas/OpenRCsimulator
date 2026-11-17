#!/usr/bin/env python3
"""Constant-axis counterexamples to shortest-path orientation interpolation.

Offline arithmetic only, not Godot execution or a measured aircraft envelope.
The analytical input rate is radians per simulation-second. Gaps refer to the
accepted simulation trajectory (12 ticks at 240 Hz = 50 ms at normal speed).
"""

from __future__ import annotations

import json
import math


def case(name: str, rate: float, gap: float) -> dict:
    actual = rate * gap
    # Equivalent endpoint orientation, with shortest signed rotation in [-pi, pi].
    shortest = math.atan2(math.sin(actual), math.cos(actual))
    samples = []
    for fraction in (0.0, 0.25, 0.5, 0.75, 1.0):
        error = abs(math.remainder(fraction * (actual - shortest), 2 * math.pi))
        samples.append({"fraction": fraction, "angular_error_degrees": round(math.degrees(error), 6)})
    return {
        "id": name, "axis_rate_rad_per_sim_second": rate,
        "accepted_simulation_gap_seconds": gap,
        "actual_rotation_degrees": round(math.degrees(actual), 6),
        "shortest_endpoint_rotation_degrees": round(math.degrees(shortest), 6),
        "within_component_outer_guard_100_radps": abs(rate) <= 100,
        "path_length_below_pi": abs(actual) < math.pi,
        "sampled_errors": samples,
    }


def document() -> dict:
    return {
        "format": "openrc-mp-rotation-sampling-research-v1",
        "status": "analytical constant-axis examples; no flight or network was measured",
        "cases": [
            case("ordinary_50ms", 20, 0.05),
            case("outer_guard_50ms", 100, 0.05),
            case("one_missing_20hz_sample", 40, 0.1),
            case("full_turn_in_100ms", 2 * math.pi / 0.1, 0.1),
            case("negative_roll_50ms", -100, 0.05),
        ],
        "scope": [
            "0.05/0.10 seconds are simulation-time gaps; mapping them to 20 Hz wall-time sends assumes a 1:1 simulation/wall-time ratio",
            "errors compare equal simulation-time fractions; applying them to equal wall-time fractions also assumes linear simulation-time progression within that bracket",
            "endpoints do not reveal the number or direction of intervening full turns",
            "the 100 rad/s per-component guard is not a measured admitted-aircraft envelope",
            "for varying axes, a path bound needs an integral bound on angular-speed norm; tick-sampled quadrature is only an estimate unless within-tick motion is bounded",
            "path length below pi excludes this wrap ambiguity but does not prove interpolation accuracy",
            "packet loss and scheduling can widen the available bracket beyond one nominal send interval",
            "delay, float64 precision and quaternion sign normalization cannot recreate missing turns",
            "implementation must qualify recorded stock-aircraft motion and a bounded gap/freeze policy",
        ],
    }


if __name__ == "__main__":
    print(json.dumps(document(), indent=2, allow_nan=False))
