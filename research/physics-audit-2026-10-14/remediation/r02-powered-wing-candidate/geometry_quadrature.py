"""Offline geometry-only sampler for a planar wing panel inside a prop-wake tube.

This is a research candidate, not production code. It integrates a convex planar
panel against the exact quadratic cross-section of an infinite/axially-clipped
cylinder. The cylinder is never polygonized into an ellipse: each fixed-y slice
has a stable analytic x interval, including the exactly parallel (band) limit.
"""

from __future__ import annotations

import functools
import json
import math
import sys
from pathlib import Path
from typing import Iterable, Sequence

from scipy.special import roots_legendre


REPO_ROOT = Path(__file__).resolve().parents[4]
_E0B2 = REPO_ROOT / "research" / "propwash" / "e0b2"
sys.path.insert(0, str(_E0B2))
from derive_geometry import area as polygon_area_2d  # noqa: E402
from derive_geometry import clip as clip_axis_halfplane  # noqa: E402


Vec2 = tuple[float, float]
Vec3 = tuple[float, float, float]


def _v3(value: Sequence[float], name: str) -> Vec3:
    if len(value) != 3:
        raise ValueError(f"{name} must have three components")
    result = tuple(float(x) for x in value)
    if not all(math.isfinite(x) for x in result):
        raise ValueError(f"{name} must be finite")
    return result  # type: ignore[return-value]


def _add(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _scale(a: Vec3, s: float) -> Vec3:
    return (a[0] * s, a[1] * s, a[2] * s)


def _dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a: Vec3, b: Vec3) -> Vec3:
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def _norm(a: Vec3) -> float:
    return math.sqrt(_dot(a, a))


def _unit(a: Vec3, name: str) -> Vec3:
    length = _norm(a)
    if not math.isfinite(length) or length <= 1e-15:
        raise ValueError(f"{name} has zero or non-finite length")
    return _scale(a, 1.0 / length)


def _outer6(v: Vec3) -> tuple[float, ...]:
    return (v[0] * v[0], v[0] * v[1], v[0] * v[2],
            v[1] * v[1], v[1] * v[2], v[2] * v[2])


def _symmetric_sum(values: Iterable[Sequence[float]], count: int) -> list[float]:
    rows = list(values)
    return [math.fsum(row[k] for row in rows) for k in range(count)]


def _signed_area(poly: Sequence[Sequence[float]]) -> float:
    return 0.5 * math.fsum(
        poly[i][0] * poly[(i + 1) % len(poly)][1]
        - poly[(i + 1) % len(poly)][0] * poly[i][1]
        for i in range(len(poly)))


def _is_convex_ccw(poly: Sequence[Sequence[float]]) -> bool:
    if len(poly) < 3 or _signed_area(poly) <= 0.0:
        return False
    signs = []
    for i in range(len(poly)):
        a, b, c = poly[i], poly[(i + 1) % len(poly)], poly[(i + 2) % len(poly)]
        cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        if abs(cross) > 1e-14:
            signs.append(cross > 0.0)
    return bool(signs) and all(signs)


def _roots_quadratic(a: float, b: float, c: float) -> list[float]:
    """Stable real roots for a*x*x+b*x+c, reducing to linear when appropriate."""
    scale = max(abs(a), abs(b), abs(c), 1e-300)
    eps = 32.0 * sys.float_info.epsilon
    if abs(a) <= eps * max(abs(b), abs(c), 1e-300):
        if abs(b) <= eps * max(abs(c), 1e-300):
            return []
        return [-c / b]
    disc = b * b - 4.0 * a * c
    disc_tol = 64.0 * sys.float_info.epsilon * max(b * b, abs(4.0 * a * c), scale * scale * 1e-30)
    if disc < -disc_tol:
        return []
    root = math.sqrt(max(0.0, disc))
    q = -0.5 * (b + math.copysign(root, b if b != 0.0 else 1.0))
    if q == 0.0:
        return [-b / (2.0 * a)]
    first = q / a
    second = c / q
    return [first] if first == second else [first, second]


@functools.lru_cache(maxsize=None)
def _gauss_legendre(order: int) -> tuple[tuple[float, ...], tuple[float, ...]]:
    if order < 2:
        raise ValueError("Gauss-Legendre order must be at least two")
    roots, weights = roots_legendre(order)
    return tuple(float(value) for value in roots), tuple(float(value) for value in weights)


def _map_gauss(lo: float, hi: float, order: int) -> tuple[list[float], list[float]]:
    roots, weights = _gauss_legendre(order)
    middle = 0.5 * (lo + hi)
    half = 0.5 * (hi - lo)
    return ([middle + half * x for x in roots], [half * w for w in weights])


def _flow_at(point: Vec3, ambient: Vec3, omega: Vec3, delta_v: Vec3) -> Vec3:
    spin = _cross(omega, point)
    return (ambient[0] + spin[0] + delta_v[0],
            ambient[1] + spin[1] + delta_v[1],
            ambient[2] + spin[2] + delta_v[2])


def make_field_sampler(
        axis: Sequence[float], origin: Sequence[float], radius: float,
        delta_v: Sequence[float] = (0.0, 0.0, 0.0),
        ambient: Sequence[float] = (0.0, 0.0, 0.0),
        omega: Sequence[float] = (0.0, 0.0, 0.0),
        s_min: float | None = 0.0, s_max: float | None = None,
        edge_fraction: float = 0.0):
    """Return normalized straight-tube geometry and a pointwise field sampler.

    `axis` is the tube's downstream geometric path. `delta_v` is an independent
    signed air-velocity increment; it need not point down that path. This keeps
    centerline geometry distinct from a propulsion sign convention.
    """
    path = _unit(_v3(axis, "axis"), "axis")
    center = _v3(origin, "origin")
    dv = _v3(delta_v, "delta_v")
    base = _v3(ambient, "ambient")
    rates = _v3(omega, "omega")
    radius = float(radius)
    edge_fraction = float(edge_fraction)
    if not math.isfinite(radius) or radius <= 0.0:
        raise ValueError("radius must be finite and positive")
    if not math.isfinite(edge_fraction) or not 0.0 <= edge_fraction < 1.0:
        raise ValueError("edge_fraction must be in [0, 1)")
    if s_min is not None and not math.isfinite(float(s_min)):
        raise ValueError("s_min must be finite or None")
    if s_max is not None and not math.isfinite(float(s_max)):
        raise ValueError("s_max must be finite or None")
    if s_min is not None and s_max is not None and float(s_max) < float(s_min):
        raise ValueError("s_max must be greater than or equal to s_min")

    inner_radius = radius * (1.0 - edge_fraction)
    outer_radius = radius * (1.0 + edge_fraction)
    inner2, outer2 = inner_radius * inner_radius, outer_radius * outer_radius

    def sample(point: Sequence[float]) -> dict:
        p = _v3(point, "point")
        relative = _sub(p, center)
        along = _dot(relative, path)
        if s_min is not None and along < float(s_min):
            occupancy = 0.0
        elif s_max is not None and along > float(s_max):
            occupancy = 0.0
        else:
            radial = _sub(relative, _scale(path, along))
            radial2 = _dot(radial, radial)
            if edge_fraction == 0.0:
                occupancy = 1.0 if radial2 <= radius * radius else 0.0
            elif radial2 <= inner2:
                occupancy = 1.0
            elif radial2 >= outer2:
                occupancy = 0.0
            else:
                t = (radial2 - inner2) / (outer2 - inner2)
                occupancy = 1.0 - t * t * (3.0 - 2.0 * t)
        applied_dv = _scale(dv, occupancy)
        # The interpolated increment is returned separately; this velocity field
        # uses the signed, unweighted increment only where occupancy is nonzero.
        local_air = _flow_at(p, base, rates, _scale(dv, 1.0 if occupancy > 0.0 else 0.0))
        return {"inside": occupancy > 0.0, "occupancy": occupancy, "s": along,
                "delta_v": dv, "weighted_delta_v": applied_dv,
                "air_velocity": local_air}

    return {"axis": path, "origin": center, "radius": radius,
            "inner_radius": inner_radius, "outer_radius": outer_radius,
            "delta_v": dv, "ambient": base, "omega": rates,
            "s_min": None if s_min is None else float(s_min),
            "s_max": None if s_max is None else float(s_max),
            "edge_fraction": edge_fraction, "sample_at": sample}


def _plane_frame(panel: Sequence[Sequence[float]], axis: Vec3):
    vertices = [_v3(p, "panel vertex") for p in panel]
    if len(vertices) < 3:
        raise ValueError("panel needs at least three vertices")
    p0 = vertices[0]
    edge_a, edge_b = _sub(vertices[1], p0), _sub(vertices[2], p0)
    normal = _unit(_cross(edge_a, edge_b), "panel normal")
    scale = max(1.0, max(_norm(_sub(p, p0)) for p in vertices))
    for point in vertices[3:]:
        if abs(_dot(_sub(point, p0), normal)) > 1e-10 * scale:
            raise ValueError("panel vertices are not coplanar")
    axis_in_plane = _sub(axis, _scale(normal, _dot(axis, normal)))
    if _norm(axis_in_plane) > 1e-14:
        e2 = _unit(axis_in_plane, "projected axis")
    else:
        e2 = _unit(edge_a, "panel edge")
    e1 = _unit(_cross(e2, normal), "panel cross-axis")
    local = [(_dot(_sub(point, p0), e1), _dot(_sub(point, p0), e2)) for point in vertices]
    signed = _signed_area(local)
    if abs(signed) <= 1e-15 * scale * scale:
        raise ValueError("panel area is zero")
    if signed < 0.0:
        vertices.reverse()
        local.reverse()
    if not _is_convex_ccw(local):
        raise ValueError("panel must be a convex polygon")
    return p0, normal, e1, e2, local


def _q2(x: float, y: float, dx: float, dy: float, mu2: float, f: float) -> float:
    return (x + dx) * (x + dx) + mu2 * y * y + 2.0 * dy * y + f - dx * dx


def _x_range(poly: Sequence[Sequence[float]], y: float) -> tuple[float, float] | None:
    intersections: list[float] = []
    for i, first in enumerate(poly):
        second = poly[(i + 1) % len(poly)]
        y0, y1 = first[1], second[1]
        if y0 == y1:
            continue
        if min(y0, y1) < y < max(y0, y1):
            t = (y - y0) / (y1 - y0)
            intersections.append(first[0] + t * (second[0] - first[0]))
    if len(intersections) < 2:
        return None
    return min(intersections), max(intersections)


def _unique_breaks(values: Iterable[float], lo: float, hi: float) -> list[float]:
    keep = sorted(x for x in values if math.isfinite(x) and lo <= x <= hi)
    scale = max(1.0, abs(lo), abs(hi), abs(hi - lo))
    eps = 16.0 * sys.float_info.epsilon * scale
    result: list[float] = []
    for value in keep:
        if not result or value - result[-1] > eps:
            result.append(value)
    if not result or result[0] != lo:
        result.insert(0, lo)
    if result[-1] != hi:
        result.append(hi)
    return result


def _geometry_breaks(poly: Sequence[Sequence[float]], dx: float, dy: float,
                     mu2: float, f: float) -> list[float]:
    ys = [point[1] for point in poly]
    lo, hi = min(ys), max(ys)
    candidates = list(ys)
    # Every point where the cylinder boundary meets a polygon edge is a change
    # in the active x bound. Solving the edge quadratic avoids ellipse sampling.
    for i, first in enumerate(poly):
        second = poly[(i + 1) % len(poly)]
        vx, vy = second[0] - first[0], second[1] - first[1]
        q0 = _q2(first[0], first[1], dx, dy, mu2, f)
        qa = vx * vx + mu2 * vy * vy
        qb = 2.0 * ((first[0] + dx) * vx + (mu2 * first[1] + dy) * vy)
        for t in _roots_quadratic(qa, qb, q0):
            if 0.0 < t < 1.0 and vy != 0.0:
                candidates.append(first[1] + t * vy)
    # Include the ellipse's y extrema, where the slice discriminant vanishes.
    for y in _roots_quadratic(mu2, 2.0 * dy, f - dx * dx):
        if lo < y < hi:
            candidates.append(y)
    return _unique_breaks(candidates, lo, hi)


_VECTOR_SIZE = 29
_X_ORDER = 8
_Y_ORDER = 8


def integrate_panel(
        panel: Sequence[Sequence[float]], field: dict,
        *, tolerance: float = 1e-9, max_depth: int = 18,
        keep_samples: bool = True) -> dict:
    """Integrate pointwise geometry/velocity moments over one convex panel.

    The outer cylinder radius is integrated as raw geometric area. `occupancy`
    uses the same C1 cubic in squared radius as Slipstream.profile_moments; it
    weights the increment but does not create a radial velocity profile.
    Returned sample weights are raw dA and occupancy is separate.
    """
    if not isinstance(field, dict) or "sample_at" not in field:
        raise ValueError("field must come from make_field_sampler")
    tolerance, max_depth = float(tolerance), int(max_depth)
    if not math.isfinite(tolerance) or tolerance <= 0.0 or max_depth < 0:
        raise ValueError("tolerance must be positive and max_depth nonnegative")
    axis: Vec3 = field["axis"]
    origin: Vec3 = field["origin"]
    p0, normal, e1, e2, poly = _plane_frame(panel, axis)
    source_area = polygon_area_2d([list(p) for p in poly])
    if source_area <= 0.0:
        raise ValueError("panel area is zero")

    # In this frame the projected axis is e2, so path distance has no x term.
    # `e1·axis=0` is an exact geometric identity; dropping its roundoff-sized
    # residue keeps a distant half-space from magnifying that numerical noise.
    d0 = _sub(p0, origin)
    t_axis = _dot(axis, e2)
    s0 = _dot(d0, axis)
    smin, smax = field["s_min"], field["s_max"]
    if t_axis <= 1e-14:
        if ((smin is not None and s0 < smin) or (smax is not None and s0 > smax)):
            return _empty_result(source_area, p0, normal, e1, e2)
    else:
        if smin is not None:
            poly = clip_axis_halfplane(poly, 1, (smin - s0) / t_axis, True)
        if smax is not None and len(poly) >= 3:
            poly = clip_axis_halfplane(poly, 1, (smax - s0) / t_axis, False)
    if len(poly) < 3 or polygon_area_2d([list(p) for p in poly]) <= 0.0:
        return _empty_result(source_area, p0, normal, e1, e2)

    # d_perp = P_axis(p0-origin), P=I-aaᵀ. In the chosen frame, the
    # section inequality is (x+dx)^2 + mu² y² + 2dy*y + f <= 0.
    along0 = _dot(d0, axis)
    radial0 = _sub(d0, _scale(axis, along0))
    dx = _dot(radial0, e1)
    dy = _dot(radial0, e2)
    mu = _dot(axis, normal)
    mu2 = max(0.0, mu * mu)
    f = _dot(radial0, radial0) - field["outer_radius"] ** 2
    breaks = _geometry_breaks(poly, dx, dy, mu2, f)
    y_tangencies = sorted(_roots_quadratic(mu2, 2.0 * dy, f - dx * dx)) if mu2 > 0.0 else []

    def slice_discriminant(y: float) -> float:
        # Factoring at the exact ellipse extrema avoids catastrophic subtraction
        # in an arbitrarily thin tangent cap or a very small-radius wake.
        if len(y_tangencies) == 2 and y_tangencies[0] <= y <= y_tangencies[1]:
            return mu2 * (y - y_tangencies[0]) * (y_tangencies[1] - y)
        return dx * dx - (mu2 * y * y + 2.0 * dy * y + f)

    y_nodes_total = 0
    x_nodes_total = 0
    attempted_panels = 0
    accepted_panels = 0
    all_rows: list[list[float]] = []
    all_samples: list[dict] = []
    quadrature_x_nodes, quadrature_x_weights = _gauss_legendre(_X_ORDER)
    ambient: Vec3 = field["ambient"]
    omega: Vec3 = field["omega"]
    delta_v: Vec3 = field["delta_v"]
    sample_at = field["sample_at"]

    def integrate_y(u_lo: float, u_hi: float, base_lo: float, base_hi: float,
                    transform: str, collect: bool,
                    area_only: bool = False) -> tuple[list[float], list[dict]]:
        nonlocal y_nodes_total, x_nodes_total
        if u_hi <= u_lo:
            return [0.0] * (1 if area_only else _VECTOR_SIZE), []
        us, uweights = _map_gauss(u_lo, u_hi, _Y_ORDER)
        length = base_hi - base_lo
        ys: list[float] = []
        yweights: list[float] = []
        tangent_discs: list[float | None] = []
        for u, weight in zip(us, uweights):
            if transform == "left_tangent":
                y = base_lo + length * u * u
                jacobian = 2.0 * length * u
                if len(y_tangencies) == 2 and abs(y_tangencies[0] - base_lo) <= 1e-12 * max(1.0, abs(base_lo)):
                    tangent_discs.append(mu2 * (length * u * u) * (y_tangencies[1] - base_lo - length * u * u))
                else:
                    tangent_discs.append(None)
            elif transform == "right_tangent":
                y = base_hi - length * u * u
                jacobian = 2.0 * length * u
                if len(y_tangencies) == 2 and abs(y_tangencies[1] - base_hi) <= 1e-12 * max(1.0, abs(base_hi)):
                    tangent_discs.append(mu2 * (base_hi - y_tangencies[0] - length * u * u) * (length * u * u))
                else:
                    tangent_discs.append(None)
            elif transform == "both_tangent":
                sine = math.sin(0.5 * math.pi * u)
                cosine = math.cos(0.5 * math.pi * u)
                y = base_lo + length * sine * sine
                jacobian = 0.5 * length * math.pi * math.sin(math.pi * u)
                tangent_discs.append(mu2 * length * length * sine * sine * cosine * cosine)
            else:
                y = base_lo + length * u
                jacobian = length
                tangent_discs.append(None)
            ys.append(y)
            yweights.append(weight * jacobian)
        rows: list[list[float]] = []
        samples: list[dict] = []
        y_nodes_total += len(ys)
        for y, wy, tangent_disc in zip(ys, yweights, tangent_discs):
            polygon_x = _x_range(poly, y)
            if polygon_x is None:
                continue
            disc = slice_discriminant(y) if tangent_disc is None else tangent_disc
            disc_scale = max(dx * dx, abs(mu2 * y * y), abs(2.0 * dy * y), abs(f), 1e-300)
            disc_tol = 64.0 * sys.float_info.epsilon * disc_scale
            if disc < -disc_tol:
                continue
            half_width = math.sqrt(max(0.0, disc))
            low = max(polygon_x[0], -dx - half_width)
            high = min(polygon_x[1], -dx + half_width)
            if high <= low:
                continue
            x_ranges = [(low, high)]
            if not area_only and field["edge_fraction"] > 0.0:
                inner_disc = disc - (field["outer_radius"]**2 - field["inner_radius"]**2)
                if inner_disc > 0.0:
                    inner_half_width = math.sqrt(inner_disc)
                    inner_low = max(low, -dx - inner_half_width)
                    inner_high = min(high, -dx + inner_half_width)
                    if inner_high > inner_low:
                        x_ranges = [(low, inner_low), (inner_low, inner_high),
                                    (inner_high, high)]
            for x_low, x_high in x_ranges:
                if x_high <= x_low:
                    continue
                xmid, xhalf = 0.5 * (x_low + x_high), 0.5 * (x_high - x_low)
                x_nodes_total += len(quadrature_x_nodes)
                for root, weight in zip(quadrature_x_nodes, quadrature_x_weights):
                    x = xmid + xhalf * root
                    d_area = wy * xhalf * weight
                    if area_only:
                        rows.append([d_area])
                        continue
                    point = _add(p0, _add(_scale(e1, x), _scale(e2, y)))
                    radial = _sub(_sub(point, origin), _scale(axis, _dot(_sub(point, origin), axis)))
                    radial2 = _dot(radial, radial)
                    if field["edge_fraction"] == 0.0:
                        # The analytic slice already constrains every node to the
                        # sharp outer cylinder; avoid reclassifying boundary-near
                        # nodes through a second rounded distance comparison.
                        occupancy = 1.0
                    elif radial2 <= field["inner_radius"] ** 2:
                        occupancy = 1.0
                    elif radial2 >= field["outer_radius"] ** 2:
                        occupancy = 0.0
                    else:
                        inner2 = field["inner_radius"] ** 2
                        outer2 = field["outer_radius"] ** 2
                        t = (radial2 - inner2) / (outer2 - inner2)
                        occupancy = 1.0 - t * t * (3.0 - 2.0 * t)
                    flow = _flow_at(point, ambient, omega, delta_v)
                    raw = [d_area]
                    raw.extend(d_area * xvalue for xvalue in point)
                    raw.extend(d_area * value for value in _outer6(point))
                    eff = d_area * occupancy
                    raw.append(eff)
                    raw.extend(eff * xvalue for xvalue in point)
                    raw.extend(eff * value for value in _outer6(point))
                    raw.extend(eff * value for value in flow)
                    raw.extend(eff * value for value in _outer6(flow))
                    if len(raw) != _VECTOR_SIZE:
                        raise AssertionError("internal moment vector has wrong size")
                    rows.append(raw)
                    if collect:
                        point_sample = sample_at(point)
                        samples.append({"point_body": list(point), "dA_m2": d_area,
                                        "occupancy": occupancy, "s_m": point_sample["s"],
                                        "radial_distance_m": math.sqrt(max(0.0, radial2)),
                                        "delta_v_body_mps": list(delta_v),
                                        "air_velocity_body_mps": list(flow)})
        return _symmetric_sum(rows, 1 if area_only else _VECTOR_SIZE), samples

    # Partition at every panel-edge/cylinder crossing and ellipse tangent before
    # adapting. This first pass estimates the whole intersection area, so tiny
    # local slices and near-zero signed moments are judged against a shared
    # global absolute scale instead of a vanishing leaf's own area.
    interval_jobs: list[tuple[float, float, str]] = []
    for lo, hi in zip(breaks, breaks[1:]):
        if hi <= lo:
            continue
        middle = 0.5 * (lo + hi)
        polygon_x = _x_range(poly, middle)
        if polygon_x is None:
            continue
        disc = slice_discriminant(middle)
        if disc < 0.0:
            continue
        half_width = math.sqrt(max(0.0, disc))
        if min(polygon_x[1], -dx + half_width) <= max(polygon_x[0], -dx - half_width):
            continue

        def disc_at(y: float) -> tuple[float, float]:
            value = slice_discriminant(y)
            scale = max(dx * dx, abs(mu2 * y * y), abs(2.0 * dy * y), abs(f),
                        field["outer_radius"] ** 2, 1e-300)
            return value, scale

        d_lo, scale_lo = disc_at(lo)
        d_hi, scale_hi = disc_at(hi)
        tangent_lo = abs(d_lo) <= 128.0 * sys.float_info.epsilon * scale_lo
        tangent_hi = abs(d_hi) <= 128.0 * sys.float_info.epsilon * scale_hi
        transform = ("both_tangent" if tangent_lo and tangent_hi else
                     "left_tangent" if tangent_lo else
                     "right_tangent" if tangent_hi else "linear")
        interval_jobs.append((lo, hi, transform))

    global_area_scale = math.fsum(
        integrate_y(0.0, 1.0, lo, hi, transform, False, True)[0][0]
        for lo, hi, transform in interval_jobs)
    if global_area_scale <= 0.0:
        return _empty_result(source_area, p0, normal, e1, e2)
    global_area_scale = min(global_area_scale, source_area)

    position_scale = max(1e-12, *(abs(float(value)) for point in panel for value in point))
    velocity_scale = max(1e-12, *(abs(value) for value in ambient),
                         *(abs(value) for value in delta_v),
                         _norm(omega) * position_scale)
    component_scales = (
        [global_area_scale]
        + [global_area_scale * position_scale] * 3
        + [global_area_scale * position_scale * position_scale] * 6
        + [global_area_scale]
        + [global_area_scale * position_scale] * 3
        + [global_area_scale * position_scale * position_scale] * 6
        + [global_area_scale * velocity_scale] * 3
        + [global_area_scale * velocity_scale * velocity_scale] * 6)

    def error_ratios(coarse: Sequence[float], fine: Sequence[float]) -> list[float]:
        return [abs(c - f_) / max(abs(f_), scale * 1e-10, 1e-300)
                for c, f_, scale in zip(coarse, fine, component_scales)]

    def relative_error(coarse: Sequence[float], fine: Sequence[float]) -> float:
        return max(error_ratios(coarse, fine))

    def adaptive(u_lo: float, u_hi: float, base_lo: float, base_hi: float,
                 transform: str, depth: int) -> None:
        nonlocal attempted_panels, accepted_panels
        attempted_panels += 1
        coarse, _ = integrate_y(u_lo, u_hi, base_lo, base_hi, transform, False)
        mid = 0.5 * (u_lo + u_hi)
        left, left_samples = integrate_y(u_lo, mid, base_lo, base_hi, transform, keep_samples)
        right, right_samples = integrate_y(mid, u_hi, base_lo, base_hi, transform, keep_samples)
        fine = [left[k] + right[k] for k in range(_VECTOR_SIZE)]
        error = relative_error(coarse, fine)
        if error <= tolerance:
            accepted_panels += 1
            all_rows.extend([left, right])
            if keep_samples:
                all_samples.extend(left_samples)
                all_samples.extend(right_samples)
            return
        if depth >= max_depth:
            ratios = error_ratios(coarse, fine)
            worst = max(range(_VECTOR_SIZE), key=ratios.__getitem__)
            raise ArithmeticError(
                f"adaptive quadrature failed tolerance={tolerance:g} on y=[{base_lo:.17g},{base_hi:.17g}] "
                f"u=[{u_lo:.17g},{u_hi:.17g}], error={error:.3g}, component={worst} "
                f"coarse={coarse[worst]:.17g}, fine={fine[worst]:.17g}")
        adaptive(u_lo, mid, base_lo, base_hi, transform, depth + 1)
        adaptive(mid, u_hi, base_lo, base_hi, transform, depth + 1)

    for lo, hi, transform in interval_jobs:
        adaptive(0.0, 1.0, lo, hi, transform, 0)

    sums = _symmetric_sum(all_rows, _VECTOR_SIZE) if all_rows else [0.0] * _VECTOR_SIZE
    result = {
        "ok": True,
        "source_panel_area_m2": source_area,
        "outer_geometric_area_m2": sums[0],
        "occupancy_weighted_area_m2": sums[10],
        "raw_first_moment_m3": sums[1:4],
        "raw_second_moment_m4": sums[4:10],
        "weighted_first_moment_m3": sums[11:14],
        "weighted_second_moment_m4": sums[14:20],
        "velocity_first_moment_m3ps": sums[20:23],
        "velocity_second_moment_m4ps2": sums[23:29],
        "centroid_body_m": _centroid(sums[1:4], sums[0]),
        "weighted_centroid_body_m": _centroid(sums[11:14], sums[10]),
        "panel_plane_normal_body": list(normal),
        "panel_basis_body": {"cross_axis": list(e1), "projected_path_axis": list(e2)},
        "path_normal_cosine": _dot(axis, normal),
        "breakpoint_count": len(breaks),
        "global_area_scale_estimate_m2": global_area_scale,
        "y_intervals": sum(1 for lo, hi in zip(breaks, breaks[1:]) if hi > lo),
        "adaptive_interval_calls": attempted_panels,
        "accepted_y_panels": accepted_panels,
        "y_quadrature_evaluations": y_nodes_total,
        "x_quadrature_evaluations": x_nodes_total,
        "quadrature_node_count": len(all_samples) if keep_samples else None,
        "gauss_order_xy": [_X_ORDER, _Y_ORDER],
        "requested_relative_tolerance": tolerance,
        "samples": all_samples if keep_samples else [],
    }
    return result


def _centroid(moment: Sequence[float], area: float) -> list[float] | None:
    if area <= 0.0:
        return None
    return [value / area for value in moment]


def _empty_result(source_area: float, p0: Vec3, normal: Vec3, e1: Vec3, e2: Vec3) -> dict:
    zeros = [0.0] * 3
    return {"ok": True, "source_panel_area_m2": source_area,
            "outer_geometric_area_m2": 0.0, "occupancy_weighted_area_m2": 0.0,
            "raw_first_moment_m3": zeros.copy(), "raw_second_moment_m4": [0.0] * 6,
            "weighted_first_moment_m3": zeros.copy(), "weighted_second_moment_m4": [0.0] * 6,
            "velocity_first_moment_m3ps": zeros.copy(), "velocity_second_moment_m4ps2": [0.0] * 6,
            "centroid_body_m": None, "weighted_centroid_body_m": None,
            "panel_plane_normal_body": list(normal),
            "panel_basis_body": {"cross_axis": list(e1), "projected_path_axis": list(e2)},
            "path_normal_cosine": None, "breakpoint_count": 0, "y_intervals": 0,
            "adaptive_interval_calls": 0, "accepted_y_panels": 0,
            "y_quadrature_evaluations": 0, "quadrature_node_count": 0,
            "x_quadrature_evaluations": 0,
            "gauss_order_xy": [_X_ORDER, _Y_ORDER], "requested_relative_tolerance": None,
            "samples": []}


def _source_value(node):
    return node["value"]


def p51_physics_panels() -> dict:
    """Load the current P51 tapered, planar six-strip *physics* approximation.

    The panels deliberately do not import the render model's estimated dihedral,
    twist, sweep, or control geometry. The active aero strips are flat/unswept.
    """
    path = REPO_ROOT / "app" / "data" / "aircraft" / "p51d_mustang_120.json"
    aircraft = json.loads(path.read_text(encoding="utf-8"))
    reference = aircraft["reference"]
    span = _source_value(reference["wing_span"])
    root = _source_value(reference["root_chord"])
    tip = _source_value(reference["tip_chord"])
    area = _source_value(reference["wing_area"])
    z_plane = _source_value(reference["aero_reference_point"])[2]
    cg = _source_value(aircraft["balance"]["plan_cg"])
    hub_le = _source_value(aircraft["propulsion"]["propeller"]["slipstream"]["hub"])
    diameter = _source_value(aircraft["propulsion"]["propeller"]["diameter"])
    down_deg, right_deg = _source_value(aircraft["propulsion"]["propeller"]["thrust_angles"])
    half = span / 2.0
    slope = (tip - root) / half
    total_half = root * half + 0.5 * slope * half * half
    right_edges = [0.0]
    for index in range(1, 4):
        target = total_half * index / 3.0
        right_edges.append(half if index == 3 else (-root + math.sqrt(root * root + 2.0 * slope * target)) / slope)
    edges = [-right_edges[3], -right_edges[2], -right_edges[1], 0.0,
             right_edges[1], right_edges[2], right_edges[3]]

    def chord(y: float) -> float:
        return root + (tip - root) * abs(y) / half

    def le_to_body(point: Sequence[float]) -> Vec3:
        # Source LE [x_aft, y_right, z_up] to body FRD relative to the plan CG.
        return (cg[0] - point[0], point[1] - cg[1], cg[2] - point[2])

    panels = []
    for index, (y0, y1) in enumerate(zip(edges, edges[1:])):
        local_le = [(0.0, y0, z_plane),
                    (chord(y0), y0, z_plane),
                    (chord(y1), y1, z_plane),
                    (0.0, y1, z_plane)]
        panels.append({"id": f"strip_{index}",
                       "span_edges_le_m": [y0, y1],
                       "vertices_body_m": [le_to_body(point) for point in local_le],
                       "expected_area_m2": (y1 - y0) * 0.5 * (chord(y0) + chord(y1)),
                       "centroid_le_m": [
                           # Exact area centroid of a linear-chord trapezoid.
                           (chord(y0) ** 2 + chord(y0) * chord(y1) + chord(y1) ** 2)
                           / (3.0 * (chord(y0) + chord(y1))),
                           (y0 + y1) * 0.5 + (y1 - y0) *
                           (chord(y1) - chord(y0)) /
                           (6.0 * (chord(y0) + chord(y1))),
                           z_plane],
                       "centroid_body_m": le_to_body([
                           (chord(y0) ** 2 + chord(y0) * chord(y1) + chord(y1) ** 2)
                           / (3.0 * (chord(y0) + chord(y1))),
                           (y0 + y1) * 0.5 + (y1 - y0) *
                           (chord(y1) - chord(y0)) /
                           (6.0 * (chord(y0) + chord(y1))),
                           z_plane])})
    thrust = [math.cos(math.radians(down_deg)) * math.cos(math.radians(right_deg)),
              math.cos(math.radians(down_deg)) * math.sin(math.radians(right_deg)),
              math.sin(math.radians(down_deg))]
    hub_body = le_to_body(hub_le)
    return {"source_data_sha256": __import__("hashlib").sha256(path.read_bytes()).hexdigest(),
            "wing_area_m2": area, "span_m": span, "root_chord_m": root,
            "tip_chord_m": tip, "plane_z_up_le_m": z_plane,
            "cg_le_m": cg, "hub_le_m": hub_le, "hub_body_m": hub_body,
            "prop_diameter_m": diameter,
            "thrust_angles_deg_down_right": [down_deg, right_deg],
            "prop_axis_body": thrust,
            "wake_path_body": [-value for value in thrust],
            "edges_m": edges, "panels": panels}


def p51_static_wake_radius(data: dict) -> float:
    """Current sharp-radius model at u=0; copies Slipstream.RADIUS_MIN=0.7071."""
    return 0.5 * data["prop_diameter_m"] * 0.7071


def p51_strip_centroid_hit(panel: dict, field: dict) -> bool:
    return field["sample_at"](panel["centroid_body_m"])["inside"]

