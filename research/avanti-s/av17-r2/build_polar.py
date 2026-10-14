"""Build an estimated finite-wing polar candidate for openrc-aircraft v2 data.

The Sandia table supplies an NACA 0015/Re 1e6 proxy, not Avanti S section data.
The attached-fraction values and table scaling are explicit candidate policy.
This module has no Godot, NumPy, or network dependency.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


FORMAT = "openrc-aircraft v2"
METHOD = "tabulated-wing-v1"
BASIS = "finite-wing-strip-reference"
STRIPS_PER_SIDE = 3  # Mirrors Aero.WING_STATIONS_PER_SIDE.
SOURCE_TRANSCRIPTION = Path(__file__).with_name("sandia_naca0015_transcription.json")
DEFAULT_AIRCRAFT = Path(__file__).resolve().parents[3] / "app/data/aircraft/sebart_avanti_s_a200.json"
PI = math.pi
TAU = 2.0 * PI


def _number(value: Any, path: str, unit: str | None = None) -> float:
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected a quantity object")
    if unit is not None and value.get("unit") != unit:
        raise ValueError(f"{path}: expected unit {unit!r}")
    number = value.get("value")
    if isinstance(number, bool) or not isinstance(number, (int, float)):
        raise ValueError(f"{path}: expected a number")
    result = float(number)
    if not math.isfinite(result):
        raise ValueError(f"{path}: expected a finite number")
    return result


def _array(value: Any, path: str, unit: str, length: int) -> list[float]:
    if not isinstance(value, dict) or value.get("unit") != unit:
        raise ValueError(f"{path}: expected a {unit!r} quantity")
    raw = value.get("value")
    if not isinstance(raw, list) or len(raw) != length:
        raise ValueError(f"{path}: expected {length} values")
    result: list[float] = []
    for index, item in enumerate(raw):
        if isinstance(item, bool) or not isinstance(item, (int, float)):
            raise ValueError(f"{path}.value[{index}]: expected a number")
        number = float(item)
        if not math.isfinite(number):
            raise ValueError(f"{path}.value[{index}]: expected a finite number")
        result.append(number)
    return result


def _root_tip(raw: dict[str, Any]) -> list[float]:
    reference = raw.get("reference")
    if not isinstance(reference, dict):
        raise ValueError("reference: expected an object")
    planform = reference.get("planform", "rectangular")
    if planform == "rectangular":
        return []
    if planform != "tapered":
        raise ValueError("reference.planform: expected 'rectangular' or 'tapered'")
    root = _number(reference.get("root_chord"), "reference.root_chord", "m")
    tip = _number(reference.get("tip_chord"), "reference.tip_chord", "m")
    if root <= 0.0 or tip <= 0.0 or tip > root:
        raise ValueError("reference: tapered wing chords must be positive with tip <= root")
    return [root, tip]


def _station_centres(span: float, chords: list[float]) -> list[float]:
    n = STRIPS_PER_SIDE
    half_span = span / 2.0
    centres: list[float] = []
    if not chords or chords[0] == chords[1]:
        for index in range(n):
            centres.append((index + 0.5) / n * half_span)
    else:
        root = chords[0]
        chord_slope = (chords[1] - root) / half_span

        def area(y: float) -> float:
            return root * y + chord_slope * y * y / 2.0

        def moment(y: float) -> float:
            return root * y * y / 2.0 + chord_slope * y * y * y / 3.0

        total = area(half_span)
        y0 = 0.0
        for index in range(n):
            target = total * (index + 1) / n
            y1 = (
                half_span
                if index == n - 1
                else (-root + math.sqrt(root * root + 2.0 * chord_slope * target)) / chord_slope
            )
            centres.append((moment(y1) - moment(y0)) / (area(y1) - area(y0)))
            y0 = y1
    return [-centres[index] for index in range(n - 1, -1, -1)] + centres


def _station_edges(span: float, chords: list[float]) -> list[float]:
    n = STRIPS_PER_SIDE
    half_span = span / 2.0
    right = [0.0]
    if not chords or chords[0] == chords[1]:
        for index in range(n):
            right.append((index + 1.0) / n * half_span)
    else:
        root = chords[0]
        chord_slope = (chords[1] - root) / half_span
        total = root * half_span + chord_slope * half_span * half_span / 2.0
        for index in range(n):
            target = total * (index + 1) / n
            edge = (
                half_span
                if index == n - 1
                else (-root + math.sqrt(root * root + 2.0 * chord_slope * target)) / chord_slope
            )
            right.append(edge)
    return [-right[index] for index in range(n, 0, -1)] + right


def _vortex_z(px: float, py: float, x1: float, y1: float, x2: float, y2: float) -> float:
    r1x = px - x1
    r1y = py - y1
    r2x = px - x2
    r2y = py - y2
    cross = r1x * r2y - r1y * r2x
    if abs(cross) < 1.0e-14:
        return 0.0
    n1 = math.sqrt(r1x * r1x + r1y * r1y)
    n2 = math.sqrt(r2x * r2x + r2y * r2y)
    dot = (x2 - x1) * (r1x / n1 - r2x / n2) + (y2 - y1) * (r1y / n1 - r2y / n2)
    return dot / (4.0 * PI * cross)


def _strip_influence(edges: list[float], ys: list[float], chords: list[float]) -> list[float]:
    n = len(ys)
    result = [0.0] * (n * n)
    for i in range(n):
        px = chords[i] / 2.0
        py = ys[i]
        for j in range(n):
            a = edges[j]
            b = edges[j + 1]
            wake = (
                _vortex_z(px, py, 1.0e5, a, 0.0, a)
                + _vortex_z(px, py, 0.0, a, 0.0, b)
                + _vortex_z(px, py, 0.0, b, 1.0e5, b)
            )
            result[i * n + j] = -wake * 0.5 * chords[j] - (1.0 / TAU if i == j else 0.0)
    return result


def _effective_angle_map(k_map: list[float], section_slope: float, n: int) -> list[float]:
    matrix = [0.0] * (n * n)
    inverse = [0.0] * (n * n)
    for i in range(n):
        for j in range(n):
            matrix[i * n + j] = (1.0 if i == j else 0.0) + section_slope * k_map[i * n + j]
        inverse[i * n + i] = 1.0
    for column in range(n):
        pivot = column
        for row in range(column + 1, n):
            if abs(matrix[row * n + column]) > abs(matrix[pivot * n + column]):
                pivot = row
        for index in range(n):
            value = matrix[column * n + index]
            matrix[column * n + index] = matrix[pivot * n + index]
            matrix[pivot * n + index] = value
            value = inverse[column * n + index]
            inverse[column * n + index] = inverse[pivot * n + index]
            inverse[pivot * n + index] = value
        divisor = matrix[column * n + column]
        if divisor == 0.0 or not math.isfinite(divisor):
            raise ValueError("induced map: singular or nonfinite section-slope solve")
        for index in range(n):
            matrix[column * n + index] /= divisor
            inverse[column * n + index] /= divisor
        for row in range(n):
            if row != column:
                factor = matrix[row * n + column]
                for index in range(n):
                    matrix[row * n + index] -= factor * matrix[column * n + index]
                    inverse[row * n + index] -= factor * inverse[column * n + index]
    return inverse


def _row_mean(matrix: list[float], n: int) -> float:
    total = 0.0
    for value in matrix:
        total += value
    return total / float(n)


def _finite_wing_line(data: dict[str, Any]) -> tuple[float, float]:
    """Mirror AircraftData._induced_map and its later wing-polar slope/offset extraction."""
    reference = data.get("reference")
    aero = data.get("aero")
    if not isinstance(reference, dict) or not isinstance(aero, dict):
        raise ValueError("reference and aero must be objects")
    surfaces = aero.get("surfaces")
    horizontal = surfaces.get("horizontal") if isinstance(surfaces, dict) else None
    if not isinstance(horizontal, dict):
        raise ValueError("aero.surfaces.horizontal: expected an object")

    area = _number(reference.get("wing_area"), "reference.wing_area", "m2")
    span = _number(reference.get("wing_span"), "reference.wing_span", "m")
    cla = _number(aero.get("coefficients", {}).get("CLa"), "aero.coefficients.CLa", "1/rad")
    cl0 = _number(aero.get("coefficients", {}).get("CL0"), "aero.coefficients.CL0", "1")
    tail_area = _number(horizontal.get("area"), "aero.surfaces.horizontal.area", "m2")
    tail_slope = _number(horizontal.get("lift_slope"), "aero.surfaces.horizontal.lift_slope", "1/rad")
    tail_incidence = _number(horizontal.get("incidence"), "aero.surfaces.horizontal.incidence", "rad")
    if area <= 0.0 or span <= 0.0 or cla <= 0.0:
        raise ValueError("reference area, span, and CLa must be positive")
    chords = _root_tip(data)
    ys = _station_centres(span, chords)
    edges = _station_edges(span, chords)
    half_span = span / 2.0
    station_chords = [
        area / span if not chords else chords[0] + (chords[1] - chords[0]) * abs(y) / half_span
        for y in ys
    ]
    k_map = _strip_influence(edges, ys, station_chords)
    tail_share = tail_area / area * tail_slope
    target = cla - tail_share
    if not math.isfinite(target) or target <= 0.0:
        raise ValueError("induced map: positive wing lift-slope target required")

    lo = 0.1
    hi = 50.0
    e_map: list[float] = []
    for _ in range(80):
        section_slope = 0.5 * (lo + hi)
        if section_slope == lo or section_slope == hi:
            break
        e_map = _effective_angle_map(k_map, section_slope, len(ys))
        if section_slope * _row_mean(e_map, len(ys)) < target:
            lo = section_slope
        else:
            hi = section_slope
    section_slope = 0.5 * (lo + hi)
    e_map = _effective_angle_map(k_map, section_slope, len(ys))
    mean_row_sum = _row_mean(e_map, len(ys))
    solved = section_slope * mean_row_sum
    if (
        not all(math.isfinite(value) for value in e_map)
        or not math.isfinite(solved)
        or abs(solved - target) > 1.0e-10 * max(1.0, abs(target))
    ):
        raise ValueError("induced map: calibrated slope did not converge")

    raw_surfaces = aero["surfaces"]
    twist_node = raw_surfaces.get("wing_station_incidence")
    if twist_node is None:
        root_to_tip = [0.0] * STRIPS_PER_SIDE
    else:
        root_to_tip = _array(twist_node, "aero.surfaces.wing_station_incidence", "rad", STRIPS_PER_SIDE)
        if abs(sum(root_to_tip) / STRIPS_PER_SIDE) > 1.0e-6:
            raise ValueError("wing station incidence must have zero equal-area mean")
    twist = [root_to_tip[index] for index in range(STRIPS_PER_SIDE - 1, -1, -1)] + root_to_tip

    twist_lift = 0.0
    n = len(ys)
    for i in range(n):
        for k in range(n):
            twist_lift += e_map[i * n + k] * twist[k]
    twist_lift *= section_slope / float(n)

    strip_alpha_zero = (cl0 - tail_share * tail_incidence - twist_lift) / (section_slope * mean_row_sum)
    strip_offsets: list[float] = []
    for i in range(n):
        row_sum = 0.0
        for k in range(n):
            row_sum += e_map[i * n + k]
        strip_offsets.append(section_slope * strip_alpha_zero * row_sum)
    wing_slope = section_slope * mean_row_sum
    wing_offset = 0.0
    for value in strip_offsets:
        wing_offset += value / float(n)
    if not math.isfinite(wing_slope) or wing_slope <= 0.0 or not math.isfinite(wing_offset):
        raise ValueError("induced map: derived wing slope/offset must be finite")
    return wing_slope, wing_offset


def _source_record() -> dict[str, Any]:
    try:
        record = json.loads(SOURCE_TRANSCRIPTION.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read transcription record {SOURCE_TRANSCRIPTION}: {error}") from error
    source = record.get("source")
    rows = record.get("rows")
    if not isinstance(source, dict) or not isinstance(rows, list) or not rows:
        raise ValueError("transcription record must contain source metadata and rows")
    for index, row in enumerate(rows):
        if (
            not isinstance(row, list)
            or len(row) != 3
            or any(isinstance(item, bool) or not isinstance(item, (int, float)) or not math.isfinite(float(item)) for item in row)
        ):
            raise ValueError(f"transcription rows[{index}] must be finite [angle deg, CL, CD]")
    return record


def _evidence_source(
    data: dict[str, Any], source_record: dict[str, Any], side: str, scale: float, angle_factor: float
) -> str:
    cl_max = data["aero"]["envelope"]["CL_max"]
    original_source = str(cl_max.get("source", "input aero.envelope.CL_max"))
    report = source_record["source"]
    return (
        f"Estimated {side} finite-wing post-stall proxy. Source CL/CD rows transcribed from {report['report']}, "
        f"{report['table']}, printed pp. {report['printed_pages'][0]}–{report['printed_pages'][1]} "
        f"(PDF pp. {report['pdf_pages'][0]}–{report['pdf_pages'][1]}), NACA 0015 at Re={report['reynolds_number']}; "
        f"PDF SHA-256 {report['pdf_sha256']}. This does not identify the Avanti S airfoil or its flight polar. "
        "Table 3 is hybrid data and includes computed/synthesized pre-stall and extended high-angle values; these rows "
        "are not all measured. "
        f"The input CL_max is {float(cl_max['value']):.6g} ({original_source}); table CL scale={scale:.12g} and "
        f"angle scale={angle_factor:.12g}. Profile CD uses input CD0 + source CD - 0.0126. The attached fraction uses "
        "min(previous, max(0, 2*sqrt(source_CL/(0.11*source_angle_deg))-1)^2), an inverse Kirchhoff-style surrogate "
        "motivated by NASA-TM-103855 eq. 2.58, not measured separation. Rows at 45/60/75/90 degrees use the input CD90 "
        "flat-plate continuation."
    )


def build_polar(data: dict[str, Any]) -> dict[str, Any]:
    """Return a closed `aero.wing_polar` candidate object for raw v2 aircraft data."""
    if not isinstance(data, dict) or data.get("format") != FORMAT:
        raise ValueError(f"data.format must be {FORMAT!r}")
    aero = data.get("aero")
    if not isinstance(aero, dict) or not isinstance(aero.get("coefficients"), dict):
        raise ValueError("aero.coefficients: expected an object")
    if not isinstance(aero.get("envelope"), dict):
        raise ValueError("aero.envelope: expected an object")

    wing_slope, wing_offset = _finite_wing_line(data)
    cl_max = _number(aero["envelope"].get("CL_max"), "aero.envelope.CL_max", "1")
    cla = _number(aero["coefficients"].get("CLa"), "aero.coefficients.CLa", "1/rad")
    cd0 = _number(aero["coefficients"].get("CD0"), "aero.coefficients.CD0", "1")
    cd90 = _number(aero["envelope"].get("CD90"), "aero.envelope.CD90", "1")
    if cl_max <= 0.0 or cla <= 0.0 or cd0 < 0.0 or cd90 <= 0.0:
        raise ValueError("CL_max, CLa, and CD90 must be positive; CD0 must be nonnegative")

    source_record = _source_record()
    source_rows = source_record["rows"]
    scale = cl_max * (wing_slope / cla) / 1.0971
    angle_factor = scale * (0.11 * 180.0 / PI) / wing_slope
    if (
        not math.isfinite(scale)
        or scale <= 0.0
        or not math.isfinite(angle_factor)
        or angle_factor <= 0.0
        or source_rows[0][0] * angle_factor <= 8.0
    ):
        raise ValueError("candidate policy produced a nonfinite scale or a mapped first source angle below 8 degrees")

    branches: dict[str, dict[str, Any]] = {}
    for name, side in (("positive", 1.0), ("negative", -1.0)):
        values = [8.0, wing_slope * math.radians(8.0) + side * wing_offset, cd0, 1.0]
        attached_fraction = 1.0
        for source_angle, source_cl, source_cd in source_rows:
            fraction_root = max(0.0, 2.0 * math.sqrt(source_cl / (0.11 * source_angle)) - 1.0)
            attached_fraction = min(attached_fraction, fraction_root * fraction_root)
            values.extend(
                [
                    source_angle * angle_factor,
                    source_cl * scale,
                    cd0 + source_cd - 0.0126,
                    attached_fraction,
                ]
            )
        for angle in (45.0, 60.0, 75.0, 90.0):
            radians = math.radians(angle)
            lift = 0.5 * cd90 * math.sin(2.0 * radians) if angle < 90.0 else 0.0
            drag = cd0 + cd90 * math.sin(radians) ** 2
            values.extend([angle, lift, drag, 0.0])
        if not all(math.isfinite(item) for item in values):
            raise ValueError(f"{name}: candidate samples contain nonfinite values")
        branches[name] = {
            "value": values,
            "unit": "deg, 1, 1, 1",
            "kind": "estimated",
            "source": _evidence_source(data, source_record, name, scale, angle_factor),
        }

    # Prevent a silent change in the checked-in input/evidence from yielding an invalid closed polar.
    if not math.isfinite(wing_offset):
        raise ValueError("finite-wing offset must be finite")
    return {"method": METHOD, "basis": BASIS, **branches}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aircraft", type=Path, default=DEFAULT_AIRCRAFT, help="raw openrc-aircraft v2 JSON")
    parser.add_argument("--output", type=Path, help="write the polar JSON here; stdout is used by default")
    args = parser.parse_args()
    try:
        data = json.loads(args.aircraft.read_text(encoding="utf-8"))
        polar = build_polar(data)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        parser.error(str(error))
    output = json.dumps(polar, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if args.output is None:
        print(output, end="")
    else:
        args.output.write_text(output, encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
