#!/usr/bin/env python3
"""Evaluate Khan's fitted static radial profile over the test-only Stik tails.

The evaluator intentionally accepts only the actual fixture tail stations and
the Eq. (5.18)/(5.20) zone. It is a dimensionless source-transfer estimate,
not a Stik calibration and not part of the runtime simulator.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
AIRCRAFT_PATH = ROOT / "app/data/aircraft/jensen_ugly_stik_60.json"
FIXTURE_PATH = ROOT / "app/tests/fixtures/stik_wash_profile.json"
OUTPUT_PATH = ROOT / "docs/research/propwash/E0b4/donor-profile.json"
GENERATOR = "research/propwash/e0b4/donor_profile.py"
RH_OVER_RP = (0.0, 0.1, 0.2)
SAMPLES_PER_INTERVAL = (128, 256)
EDGE_FRACTION = 0.15
TOL = 1e-12
AREA_MEAN_CONVERGENCE_ABS_TOL = 1e-6


def _read_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return value


def _quantity(data: dict[str, Any], key: str) -> float:
    value = data[key]["value"]
    if not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"Invalid finite numeric quantity {key}")
    return float(value)


def _axial_station(piece: dict[str, Any], hub: list[float]) -> float:
    """Aft distance along the fixture's axial shaft, in metres."""
    return float(piece["root"][0]) - float(hub[0])


def _branch_coordinate(ds: float, diameter: float) -> tuple[float, float, float, float]:
    """Return xi, d0, D0, R0 from Khan thesis Eqs. (5.13)-(5.14)."""
    d0 = 0.764 * diameter
    D0 = 0.74 * diameter
    R0 = 0.37 * diameter
    xi = (ds - d0) / D0
    return xi, d0, D0, R0


def _model_parameters(
    ds: float,
    diameter: float,
    hub_radius_ratio: float,
    actual_station_band: tuple[float, float],
) -> dict[str, float]:
    """Apply Eqs. (5.18)-(5.20), rejecting extrapolation beyond this task's data."""
    lo, hi = actual_station_band
    if ds < lo - TOL or ds > hi + TOL:
        raise ValueError(
            f"Axial station {ds:.9g} m is outside the actual Stik tail band "
            f"[{lo:.9g}, {hi:.9g}] m"
        )
    xi, d0, D0, R0 = _branch_coordinate(ds, diameter)
    if xi < 1.7 - TOL or xi > 4.25 + TOL:
        raise ValueError(
            f"Khan Eqs. (5.18)-(5.20) require 1.7 <= xi <= 4.25; got xi={xi:.9g}"
        )
    if not 0.0 <= hub_radius_ratio < 0.74:
        raise ValueError(f"Hub radius ratio must be in [0, 0.74); got {hub_radius_ratio}")

    # Thesis Eq. (5.10): Rmax,0 = 0.67 (R0 - Rh). The hub size is not
    # recorded for the Stik, so it is supplied only as an explicit sensitivity.
    rp = diameter / 2.0
    rh = hub_radius_ratio * rp
    rmax0 = 0.67 * (R0 - rh)

    # Thesis Eqs. (5.18)-(5.20), where the exponent uses (delta / width)^2.
    v0_over_w = 1.46 / math.sqrt(2.0 / math.pi)
    vmax_over_w = v0_over_w * (1.37 - 0.1529 * xi)
    rmax = rmax0 * (1.3 - 0.3059 * xi)
    gaussian_width = 0.5176 * rmax0 + 0.2295 * (ds - d0 - R0)
    if rmax0 <= 0.0 or gaussian_width <= 0.0 or vmax_over_w <= 0.0:
        raise ValueError("Khan profile produced a nonpositive radius, width, or peak speed")
    return {
        "xi": xi,
        "d0_m": d0,
        "D0_m": D0,
        "R0_m": R0,
        "Rmax0_m": rmax0,
        "Rmax_m": rmax,
        "gaussian_width_m": gaussian_width,
        "V0_over_w": v0_over_w,
        "Vmax_over_w": vmax_over_w,
    }


def _velocity_over_w(radius: float, parameters: dict[str, float]) -> float:
    delta = (radius - parameters["Rmax_m"]) / parameters["gaussian_width_m"]
    return parameters["Vmax_over_w"] * math.exp(-(delta * delta))


def _radial_distance(piece: dict[str, Any], offset: float, hub: list[float]) -> float:
    root = piece["root"]
    span_dir = piece["span_dir"]
    y = float(root[1]) + float(span_dir[1]) * offset - float(hub[1])
    z = float(root[2]) + float(span_dir[2]) * offset - float(hub[2])
    if abs(float(span_dir[0])) > TOL:
        raise ValueError("Fixture span axis must be transverse to the axial propeller shaft")
    return math.hypot(y, z)


def _occupancy(radius: float, wake_radius: float, edge: float) -> float:
    inner2 = wake_radius * wake_radius * (1.0 - edge) ** 2
    outer2 = wake_radius * wake_radius * (1.0 + edge) ** 2
    radius2 = radius * radius
    if radius2 <= inner2:
        return 1.0
    if radius2 >= outer2:
        return 0.0
    t = (radius2 - inner2) / (outer2 - inner2)
    return 1.0 - t * t * (3.0 - 2.0 * t)


def _integrate_piece(
    piece: dict[str, Any],
    hub: list[float],
    parameters: dict[str, float],
    samples_per_interval: int,
    occupancy_radius: float,
) -> dict[str, float]:
    area = q_integral = occupancy_integral = 0.0
    profile = piece["profile"]
    if not profile:
        raise ValueError(f"Empty piece profile: {piece.get('surface')}")
    for low, high, chord0, chord1 in profile:
        low, high, chord0, chord1 = map(float, (low, high, chord0, chord1))
        if high <= low or chord0 < -TOL or chord1 < -TOL:
            raise ValueError("Invalid piecewise-linear chord interval")
        step = (high - low) / samples_per_interval
        for index in range(samples_per_interval):
            span_offset = low + (index + 0.5) * step
            fraction = (span_offset - low) / (high - low)
            chord = chord0 + fraction * (chord1 - chord0)
            sample_area = chord * step
            radius = _radial_distance(piece, span_offset, hub)
            speed_over_w = _velocity_over_w(radius, parameters)
            area += sample_area
            q_integral += sample_area * speed_over_w * speed_over_w
            occupancy_integral += sample_area * _occupancy(radius, occupancy_radius, EDGE_FRACTION)
    if area <= 0.0:
        raise ValueError("Integrated piece area must be positive")
    expected_area = float(piece["area"])
    if abs(area - expected_area) > 2e-10:
        raise ValueError(f"Sampled area {area:.12g} differs from fixture {expected_area:.12g}")
    return {
        "sampled_area_m2": area,
        "area_mean_q_over_w2": q_integral / area,
        "area_mean_occupancy": occupancy_integral / area,
    }


def _piece_report(
    piece: dict[str, Any],
    hub: list[float],
    diameter: float,
    actual_station_band: tuple[float, float],
    rh_over_rp: float,
    occupancy_radius: float,
) -> dict[str, Any]:
    ds = _axial_station(piece, hub)
    parameters = _model_parameters(ds, diameter, rh_over_rp, actual_station_band)
    centerline = _velocity_over_w(0.0, parameters)
    if piece["surface"] == "horizontal":
        piece_name = "horizontal_left" if float(piece["span_dir"][1]) < 0.0 else "horizontal_right"
    else:
        piece_name = "vertical_fin"
    convergence: list[dict[str, float]] = []
    for sample_count in SAMPLES_PER_INTERVAL:
        integration = _integrate_piece(piece, hub, parameters, sample_count, occupancy_radius)
        convergence.append({
            "midpoints_per_profile_interval": sample_count,
            "sample_points": sample_count * len(piece["profile"]),
            **integration,
        })
    coarse = convergence[0]["area_mean_q_over_w2"]
    fine = convergence[1]["area_mean_q_over_w2"]
    if abs(fine - coarse) > AREA_MEAN_CONVERGENCE_ABS_TOL:
        raise ValueError(
            f"{piece['surface']} area-mean refinement {abs(fine - coarse):.9g} "
            f"exceeds {AREA_MEAN_CONVERGENCE_ABS_TOL:.9g}"
        )
    fine_occupancy = convergence[1]["area_mean_occupancy"]
    return {
        "piece": piece_name,
        "surface": piece["surface"],
        "axial_station_m": ds,
        "axial_station_D": ds / diameter,
        "xi": parameters["xi"],
        "radius_at_centerline_m": 0.0,
        "centerline_velocity_over_w": centerline,
        "centerline_q_over_w2": centerline * centerline,
        "area_mean_q_over_centerline_q_256": fine / (centerline * centerline),
        "Rmax_m": parameters["Rmax_m"],
        "gaussian_width_m": parameters["gaussian_width_m"],
        "Vmax_over_w": parameters["Vmax_over_w"],
        "convergence": convergence,
        "area_mean_q_over_w2_abs_delta_128_to_256": abs(fine - coarse),
        "area_mean_q_over_w2_relative_delta_128_to_256": abs(fine - coarse) / max(abs(fine), TOL),
        "smooth_occupancy_comparison_256": {
            "area_mean_occupancy": fine_occupancy,
            "uniform_increment_q_mean_over_centerline_q_proxy": fine_occupancy,
            "interpretation": "E0b3b occupancy weights the area receiving a uniform wash increment; it is not a local radial velocity profile. Under its load-weight interpretation, area-mean occupancy is the q proxy relative to a uniform-increment top hat. Compare this coverage proxy with the Gaussian q attenuation, not as a measured velocity shape.",
        },
    }


def _aggregate_surface(rows: list[dict[str, Any]], pieces: list[dict[str, Any]]) -> dict[str, Any]:
    area_total = sum(float(piece["area"]) for piece in pieces)
    if area_total <= 0.0:
        raise ValueError("Surface has no positive area")
    weighted_centerline_q = sum(
        float(piece["area"]) * row["centerline_q_over_w2"]
        for piece, row in zip(pieces, rows)
    ) / area_total
    sample_summaries: list[dict[str, float]] = []
    for sample_index, samples in enumerate(SAMPLES_PER_INTERVAL):
        q_mean = sum(
            float(piece["area"]) * row["convergence"][sample_index]["area_mean_q_over_w2"]
            for piece, row in zip(pieces, rows)
        ) / area_total
        occupancy_mean = sum(
            float(piece["area"]) * row["convergence"][sample_index]["area_mean_occupancy"]
            for piece, row in zip(pieces, rows)
        ) / area_total
        sample_summaries.append({
            "midpoints_per_profile_interval": samples,
            "sample_points": sum(samples * len(piece["profile"]) for piece in pieces),
            "area_m2": area_total,
            "area_mean_q_over_w2": q_mean,
            "area_mean_occupancy": occupancy_mean,
        })
    coarse = sample_summaries[0]["area_mean_q_over_w2"]
    fine = sample_summaries[1]["area_mean_q_over_w2"]
    occupancy = sample_summaries[1]["area_mean_occupancy"]
    centerline_at_surface = weighted_centerline_q
    if abs(fine - coarse) > AREA_MEAN_CONVERGENCE_ABS_TOL:
        raise ValueError(
            f"Surface area-mean refinement {abs(fine - coarse):.9g} "
            f"exceeds {AREA_MEAN_CONVERGENCE_ABS_TOL:.9g}"
        )
    return {
        "piece_count": len(pieces),
        "neutral_geometry_area_m2": area_total,
        "centerline_velocity_over_w_area_weighted_rms": math.sqrt(weighted_centerline_q),
        "centerline_q_over_w2_area_weighted": weighted_centerline_q,
        "area_mean_q_over_centerline_q_256": fine / centerline_at_surface,
        "convergence": sample_summaries,
        "area_mean_q_over_w2_abs_delta_128_to_256": abs(fine - coarse),
        "area_mean_q_over_w2_relative_delta_128_to_256": abs(fine - coarse) / max(abs(fine), TOL),
        "smooth_occupancy_comparison_256": {
            "area_mean_occupancy": occupancy,
            "uniform_increment_q_mean_over_centerline_q_proxy": occupancy,
            "interpretation": "Area-weighted occupancy is a geometric load weight; under the E0b3b uniform local wash increment, this is a coverage q proxy relative to the uniform-increment centerline.",
        },
    }


def build_report(aircraft: dict[str, Any], fixture: dict[str, Any]) -> dict[str, Any]:
    if fixture.get("test_only") is not True:
        raise ValueError("Refusing a non-test fixture")
    if fixture.get("format") != "openrc-stik-wash-profile-fixture-e0b3b v1":
        raise ValueError("Unexpected Stik fixture format")
    hub = fixture.get("hub")
    pieces = fixture.get("pieces")
    if not isinstance(hub, list) or len(hub) != 3 or not isinstance(pieces, list) or len(pieces) != 3:
        raise ValueError("Expected the current hub and exactly three generated Stik tail profiles")
    diameter = _quantity(aircraft["propulsion"]["propeller"], "diameter")
    stations = [_axial_station(piece, hub) for piece in pieces]
    station_band = (min(stations), max(stations))
    if diameter <= 0.0:
        raise ValueError("Propeller diameter must be positive")
    # Every actual fixture station must fit both the exact current Stik band and
    # the selected Khan zone. Tests immediately outside either limit fail.
    station_coordinates = []
    for piece, ds in zip(pieces, stations):
        xi, d0, D0, _ = _branch_coordinate(ds, diameter)
        if not 1.7 <= xi <= 4.25:
            raise ValueError(f"{piece['surface']} tail station falls outside Khan Eq. 5.18/5.20: xi={xi}")
        station_coordinates.append({
            "piece": piece["surface"],
            "axial_station_m": ds,
            "axial_station_D": ds / diameter,
            "xi": xi,
            "zone_branch": "Khan Eq. 5.18/5.20, 1.7 <= xi <= 4.25",
            "inside_selected_branch": True,
        })
    # Exercise both guards: one just outside the actual geometry band and one
    # just outside the fitted equation branch.
    for ds in (station_band[0] - 1e-9, station_band[1] + 1e-9):
        try:
            _model_parameters(ds, diameter, RH_OVER_RP[0], station_band)
        except ValueError:
            pass
        else:
            raise AssertionError("Evaluator accepted a station outside the actual Stik tail band")
    for xi in (1.7 - 1e-8, 4.25 + 1e-8):
        ds = 0.764 * diameter + 0.74 * diameter * xi
        try:
            _model_parameters(ds, diameter, RH_OVER_RP[0], (0.0, 10.0 * diameter))
        except ValueError:
            pass
        else:
            raise AssertionError("Evaluator accepted a station outside the Khan Eq. 5.18/5.20 branch")

    occupancy_radius = diameter / (2.0 * math.sqrt(2.0))
    cases = []
    for rh_ratio in RH_OVER_RP:
        by_piece = [
            _piece_report(piece, hub, diameter, station_band, rh_ratio, occupancy_radius)
            for piece in pieces
        ]
        surface_aggregates: dict[str, Any] = {}
        for surface in ("horizontal", "vertical"):
            selected = [(piece, row) for piece, row in zip(pieces, by_piece) if piece["surface"] == surface]
            surface_aggregates[surface] = _aggregate_surface(
                [row for _, row in selected], [piece for piece, _ in selected]
            )
        cases.append({
            "hub_radius_over_propeller_radius": rh_ratio,
            "input_kind": "assumed sensitivity point; not Stik measurement or source-propeller value",
            "pieces": by_piece,
            "surfaces": surface_aggregates,
        })

    return {
        "format": "openrc-e0b4-donor-profile v1",
        "generator": GENERATOR,
        "status": "Source-informed static transfer calculation; no Stik calibration, runtime configuration or enablement.",
        "input_files": {
            "test_geometry": "app/tests/fixtures/stik_wash_profile.json",
            "propeller_diameter": "app/data/aircraft/jensen_ugly_stik_60.json#/propulsion/propeller/diameter",
        },
        "input_sha256": {
            "fixture": hashlib.sha256(FIXTURE_PATH.read_bytes()).hexdigest(),
            "aircraft_data": hashlib.sha256(AIRCRAFT_PATH.read_bytes()).hexdigest(),
            "generator": hashlib.sha256(Path(__file__).resolve().read_bytes()).hexdigest(),
        },
        "source_model": {
            "reference": "Khan 2016 McGill PhD thesis, Chapter 5, Eqs. (5.10), (5.12)-(5.14), (5.18)-(5.20), printed pp. 115 and 118.",
            "thesis_record_url": "https://mcgill.scholaris.ca/items/56b70b0e-1f76-48ba-b973-d3b841d659ed",
            "official_pdf_bitstream_url": "https://mcgill.scholaris.ca/server/api/core/bitstreams/dcf4ec23-fc4d-457b-b4af-7e0fe29ce67c/content",
            "fit_propeller": "Electrifly Powerflow 10x4.5, D=0.254 m; fit coefficients at 5,425 rpm, T=6.43 +/- 0.03 N, CT=0.1542.",
            "equations": {
                "efflux_speed": "V0 = 1.46 n Dp sqrt(CT)",
                "efflux_plane": "d0 = 0.764 Dp",
                "contracted_radius": "R0 = 0.74 Rp; D0 = 2 R0 = 0.74 Dp",
                "initial_peak_radius": "Rmax,0 = 0.67 (R0 - Rh)",
                "coordinate": "xi = (ds - d0)/D0",
                "eq_5_18": "Vs,max = V0 (1.37 - 0.1529 xi), for 1.7 <= xi <= 4.25",
                "eq_5_19": "Rmax = Rmax,0 (1.3 - 0.3059 xi)",
                "eq_5_20": "Vs = Vs,max exp(-((rs - Rmax)/(0.5176 Rmax,0 + 0.2295(ds - d0 - R0)))^2)",
                "normalization": "Static actuator-disc induced speed w = n Dp sqrt(2 CT/pi), so V0/w = 1.46/sqrt(2/pi).",
            },
        },
        "geometry_and_station_scope": {
            "propeller_diameter_m": diameter,
            "propeller_hub_le_m": hub,
            "actual_stik_tail_station_band_m": list(station_band),
            "actual_stik_tail_station_band_D": [station_band[0] / diameter, station_band[1] / diameter],
            "actual_stations": station_coordinates,
            "equation_branch_guard": "The evaluator rejects stations outside the exact current Stik root-x band and rejects xi outside [1.7, 4.25]; it does not evaluate any other Khan axial branch.",
            "neutral_geometry": "Fixture piecewise-linear aggregate chord profiles; area and span first moment preserve the E0b2 neutral polygon groups. Horizontal halves use z=-0.040640 m, the neutral coverage plane; fin uses its full generated z profile.",
            "fixed_reference_x": "Each profile uses its current generated root/reference x. Flow is evaluated across transverse span only; chordwise wake variation and the 5 mm horizontal load-plane offset are not resolved.",
            "integration": "Midpoint quadrature independently subdivides every profile interval with 128 and 256 points; the local chord is linearly interpolated and weights each transverse radius.",
            "dimensionless_q_definition": "Every field ending q_over_w2 is mean(Vs^2)/w^2 = q_mean/(0.5 rho w^2) for constant density. The centerline value is Vs(0)^2/w^2.",
            "area_mean_convergence_absolute_tolerance": AREA_MEAN_CONVERGENCE_ABS_TOL,
        },
        "hub_radius_sensitivity": {
            "rh_over_rp": list(RH_OVER_RP),
            "status": "Assumed mathematical sensitivity points only. The Stik fixture and source aircraft data contain no measured propeller hub radius; no one case is selected as a Stik value.",
        },
        "smooth_occupancy_comparison": {
            "source": "Current E0b3b load-occupancy law in app/physics/slipstream.gd / docs/research/propwash/E0b3b/README.md.",
            "static_radius_m": occupancy_radius,
            "radius_assumption": "E0b3b momentum far-wake radius at u=0 is Rp/sqrt(2); static geometry only.",
            "edge_fraction": EDGE_FRACTION,
            "edge_fraction_kind": "estimated test-fixture regularization, not a measured wash edge or Gaussian width",
            "comparison": "The JSON reports both Gaussian area-mean q relative to its own centerline q and E0b3b mean occupancy as the uniform-increment load q proxy relative to its own centerline. These are shape/coverage diagnostics with distinct meanings; they are not equalized-speed measurements or a calibrated Stik dynamic pressure.",
        },
        "limitations": [
            "The thesis fit uses a different 10x4.5 propeller, motor, rpm and geometry. This normalized application transfers the fitted shape to Stik stations; it is not Stik calibration.",
            "The source fit coefficients use 5425 rpm data; the same propeller's 1750 and 6425 rpm tests report 0.6 m/s (13%) and 2 m/s (12%) overall RMS errors, respectively.",
            "The one-term Gaussian is symmetric; Khan reports under-prediction near the axis in the zone of flow establishment because measured profiles are asymmetric, with error fading downstream.",
            "The Stik tail stations are near the end of the source model's zone of flow establishment (xi about 4.00-4.09). The closest tabulated radial survey station is x/D=3.54; the next, x/D=4.33, lies in the distinct established-flow branch and is not interpolated here.",
            "Hub radius is unknown for the Stik; the three Rh/Rp cases show sensitivity without selecting a donor value.",
            "The fixture is estimated visual geometry and integrates aggregate projected area over span at a fixed x; it does not resolve individual chordwise gaps or local flow variation in x.",
            "No wind, advance-ratio effect, swirl, transport, Reynolds correction, aircraft-specific blockage or powered-cruise calibration is included.",
        ],
        "cases": cases,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if donor-profile.json is stale")
    args = parser.parse_args()
    report = build_report(_read_json(AIRCRAFT_PATH), _read_json(FIXTURE_PATH))
    rendered = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.check:
        if not OUTPUT_PATH.exists() or OUTPUT_PATH.read_text(encoding="utf-8") != rendered:
            raise SystemExit(f"Stale donor profile: regenerate with {GENERATOR}")
        print("donor-profile.json is current")
        return 0
    OUTPUT_PATH.write_text(rendered, encoding="utf-8")
    print(f"Wrote {OUTPUT_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
