#!/usr/bin/env python3
"""Check the race bound and lake counterexamples from a production checkout. Python 3 standard library."""
import argparse
import json
import math
from pathlib import Path


def gate_result():
    dt = 1.0 / 240
    width = 1.5
    margin = 0.00075
    normal_velocity = 2.0
    tangent_velocity = 20.0
    acceleration = 50.0
    max_acceleration = 250.0
    sag = acceleration * dt**2 / 8
    # Centered time s. Solve 0.5*a*s^2 + vn*s - sag = 0 using the cancellation-safe conjugate.
    root = 2 * sag / (normal_velocity + math.sqrt(normal_velocity**2 + 2 * acceleration * sag))
    normal_at_root = normal_velocity * root + 0.5 * acceleration * (root**2 - (dt / 2)**2)
    assert abs(normal_at_root) < 1e-18
    epsilon = max_acceleration * dt**2 / 8
    tangent_deviation = tangent_velocity * root
    edge = width - margin + tangent_deviation
    assert normal_velocity - acceleration * dt / 2 > 0
    assert edge > width and width - margin + epsilon < width
    assert width - margin < width
    return {
        "T_s": dt, "width_half_m": width, "production_band_m": epsilon,
        "endpoint_normal_velocities_mps": [normal_velocity - acceleration * dt / 2, normal_velocity + acceleration * dt / 2],
        "acceleration_mps2": acceleration, "chord_u_m": width - margin,
        "curve_u_m": edge, "time_shift_s": root, "u_error_m": tangent_deviation,
        "synchronous_sag_m": sag,
        "axis_bound_given_full_acceleration_envelope_m": epsilon * math.hypot(1, tangent_velocity / normal_velocity),
    }


def cross(a, b):
    return a[0] * b[1] - a[1] * b[0]


def segment_distance(point, a, b):
    delta = (b[0] - a[0], b[1] - a[1])
    rel = (point[0] - a[0], point[1] - a[1])
    t = min(1.0, max(0.0, sum(x * y for x, y in zip(delta, rel)) / sum(x * x for x in delta)))
    return math.hypot(rel[0] - t * delta[0], rel[1] - t * delta[1])


def signed_distance(point, ring):
    inside = False
    nearest = math.inf
    for a, b in zip(ring, ring[1:] + ring[:1]):
        nearest = min(nearest, segment_distance(point, a, b))
        if (a[1] > point[1]) != (b[1] > point[1]):
            x_on_edge = a[0] + (point[1] - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
            if point[0] < x_on_edge:
                inside = not inside
    return nearest if inside else -nearest


def lake_result(repo):
    raw = json.loads((repo / "app/data/fields/lake.json").read_text(encoding="utf-8"))
    dt = 1.0 / 240
    down = 0.3951
    travel = (-28.8, -49.883063257983665)
    waves = raw["waves"]["components"]
    directions = [(math.cos(w["heading_rad"]), math.sin(w["heading_rad"])) for w in waves]
    assert len(waves) == len(directions) == 2
    # Set each phase to pi/2 + k*2*pi at the midpoint. Solve two nonparallel linear spatial constraints.
    projected = [w["wavelength_m"] * (k + 0.25 + dt / 2 / w["period_s"] - w["phase_rad"] / math.tau)
                 for w, k in zip(waves, (11, 23))]
    n_columns = (directions[0][0], directions[1][0])
    e_columns = (directions[0][1], directions[1][1])
    det = cross(n_columns, e_columns)
    crest = (cross(projected, e_columns) / det, cross(n_columns, projected) / det)
    assert math.dist(crest, (106.64877984412676, 128.02108157112164)) < 1e-12
    length = math.hypot(*travel) * dt
    rings = {}
    for key in ("shoreline_offsets_ne_m", "bank_offsets_ne_m"):
        ring = [(raw["origin"]["north_m"] + n, raw["origin"]["east_m"] + e) for n, e in raw[key]]
        rings[key] = signed_distance(crest, ring)
    assert min(rings.values()) - length / 2 > raw["waves"]["shore_fade_m"] + 0.025
    # Relative angular phase velocity on a linear path. Each component is A*cos(omega*(t-T/2)).
    omega = [math.tau * (sum(x * v for x, v in zip(direction, travel)) / w["wavelength_m"] - 1 / w["period_s"])
             for w, direction in zip(waves, directions)]
    assert all(0 < abs(rate * dt / 2) < math.pi / 2 for rate in omega)

    def immersion(fraction):
        return down - raw["water_level_down_m"] + math.fsum(
            w["amplitude_m"] * math.cos(rate * dt * (fraction - 0.5)) for w, rate in zip(waves, omega)
        )

    assert immersion(0) < -9.4e-5 and immersion(0.5) > 9.99e-5 and immersion(1) < -9.4e-5
    lo, hi = 0.0, 0.5
    for _ in range(80):
        mid = (lo + hi) / 2
        if immersion(mid) > 0:
            hi = mid
        else:
            lo = mid
    steps = max([1, math.ceil(length / 0.25)] + [max(math.ceil(8 * length / w["wavelength_m"]),
                                                        math.ceil(8 * dt / w["period_s"])) for w in waves])
    assert steps == 1
    return {
        "stock_lake_id": raw["id"], "T_s": dt, "midpoint_ne_m": crest, "velocity_ne_mps": travel,
        "down_m": down, "path_length_m": length, "signed_distances_at_midpoint_m": rings,
        "angular_phase_velocities_rad_s": omega, "endpoint_clearance_m": -immersion(0),
        "midpoint_immersion_m": immersion(0.5), "analytic_entry_fraction": (lo + hi) / 2,
        "analytic_exit_fraction": 1 - (lo + hi) / 2, "subdivisions": steps,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", type=Path, help="OpenRCsimulator checkout root")
    options = parser.parse_args()
    print(json.dumps({"gate": gate_result(), "lake": lake_result(options.repo)}, indent=2, allow_nan=False))
