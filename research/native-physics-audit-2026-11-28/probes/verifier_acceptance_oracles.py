"""Independent scalar controls for the current-main physics audit.

Run with Python 3. No project import, engine, package or external data is used.
The constants below specify the audited fixtures. Output is a JSON receipt.
"""

import cmath
import json
import math


def require_close(value, expected, absolute=1e-9):
    if not math.isclose(value, expected, rel_tol=0.0, abs_tol=absolute):
        raise ValueError(f"{value!r} differs from {expected!r}")


def bisect(function, lower, upper):
    """Return a bracketed zero; each caller supplies a single-root interval."""
    left = function(lower)
    right = function(upper)
    if left == 0:
        return lower
    if right == 0:
        return upper
    if (left > 0) == (right > 0):
        raise ValueError("a zero was not bracketed")
    for _ in range(70):
        mid = 0.5 * (lower + upper)
        value = function(mid)
        if value == 0:
            return mid
        if (left > 0) == (value > 0):
            lower = mid
        else:
            upper = mid
    return 0.5 * (lower + upper)


def polynomial(coefficients, time):
    total = 0.0
    for coefficient in reversed(coefficients):
        total = time * total + coefficient
    return total


def project(vector, normal):
    return (vector * normal.conjugate()).real


def synchronized_box():
    # Planar spinor u=1+s*d: the rotated point is R*u^2/|u|^2.
    # N/D represents the rotation at original full-tick time s.
    turn = math.radians(11.9)
    radius = 0.9
    pieces = math.ceil(turn / math.radians(2))
    end = 1.0 / pieces
    change = cmath.exp(0.5j * turn) - 1.0
    denom = [1.0, 2.0 * change.real, abs(change) ** 2]
    rotation = [radius, 2.0 * radius * change, radius * change**2]

    def rotated(time):
        return polynomial(rotation, time) / polynomial(denom, time)

    # Move the CG linearly until the first piece's rotated point endpoints coincide.
    origin = -radius
    translation_rate = (radius - rotated(end)) / end
    middle = end / 2.0
    deviation = origin + middle * translation_rate + rotated(middle)
    normal = deviation / abs(deviation)
    norm_at_end = math.sqrt(polynomial(denom, end))
    cos_half = (1.0 + change.real * end) / norm_at_end
    padding = radius * (1.0 - cos_half) + 1e-9
    face = 0.5 * (padding + abs(deviation))

    # Signed face distance times |u|^2, including synchronized CG translation.
    # A positive numerator lies beyond the chosen entry face.
    offset = project(origin, normal) - face
    rate = project(translation_rate, normal)
    coeff = [project(rotation[i], normal) + offset * denom[i] for i in range(3)] + [0.0]
    for i, value in enumerate(denom):
        coeff[i + 1] += rate * value
    signed = lambda time: polynomial(coeff, time)
    entry = bisect(signed, 0.0, middle)
    leave = bisect(signed, middle, end)
    derivative = [i * coeff[i] for i in range(1, 4)]
    # At a root, (N/D)'=N'/D. Convert metres/tick to metres/second.
    incoming = 240.0 * polynomial(derivative, entry) / polynomial(denom, entry)
    if not padding < face < abs(deviation) or not 0.0 < incoming < 0.05:
        raise ValueError("the broad-phase and response-floor discriminators were lost")
    require_close(entry, 0.081552969546, 2e-10)
    require_close(leave, 0.085144882281, 2e-10)
    require_close(incoming, 0.016716875452, 3e-9)
    return {
        "full_tick_pieces": pieces, "padding_um": padding * 1e6,
        "midpoint_um": abs(deviation) * 1e6, "face_um": face * 1e6,
        "entry_tick_fraction": entry, "exit_tick_fraction": leave,
        "geometric_incoming_m_per_s": incoming, "ordinary_response_floor_m_per_s": 0.05,
    }


def clear_endpoints_box():
    radius = 0.9
    half_sweep = math.radians(0.75)
    face = radius * math.cos(half_sweep / 2)
    first = cmath.exp(-0.5j * half_sweep)
    last = first.conjugate()

    def gap(time):
        spinor = first + time * (last - first)
        return face - radius * (spinor / spinor.conjugate()).real

    entry = bisect(gap, 0.0, 0.5)
    leave = bisect(gap, 0.5, 1.0)
    require_close(entry, 0.250002677321, 2e-10)
    require_close(leave, 0.749997322679, 2e-10)
    if not gap(0) > 0 > gap(0.5) or not gap(1) > 0 or gap(0.5) + 40e-6 <= 0:
        raise ValueError("the two-crossing or true-miss control failed")
    return {"gaps_um": [1e6 * gap(t) for t in (0, 0.5, 1)], "crossings": [entry, leave],
            "moved_face_minimum_gap_um": 1e6 * gap(0.5) + 40.0}


def controls():
    # Centered stick, north-facing nose, exact 180-degree roll. Desired quaternion is identity.
    # Its residual is the conjugate of the supplied quaternion. The stock scalar tie uses <0.
    def roll_request(w, x):
        sign = -1 if w < 0 else 1
        rotation = 2.0 * sign * math.atan2(abs(x), sign * w) * (-x) / abs(x)
        return min(400.0, max(-400.0, math.degrees(6.0 * rotation)))

    epsilon = math.cos(math.pi / 2)
    literal = [roll_request(0.0, 1.0), roll_request(-0.0, -1.0)]
    trig = [roll_request(epsilon, 1.0), roll_request(-epsilon, -1.0)]
    if literal != [-400.0, 400.0] or trig != [-400.0, -400.0]:
        raise ValueError("the antipodal representation discriminator failed")
    period = 1 / 240
    target = 0.5 * period / 0.14
    exposure_error = (5 / 6 - 3 / 4) * period * target
    return {"angle_literal_deg_s": literal, "angle_trig_deg_s": trig,
            "upstream_full_tracking_yaw_delta_nm": 0.008544739953 + 20 * period * (0.35 - 0.922831914878),
            "relieving_roll_integral_delta_nm": -0.1 * period,
            "half_tick_servo_exposure_error_normalized_s": exposure_error}


def wing():
    # Extra tapered semispan from gp_extra_300s_60.json and geometry.json.
    span, root_chord, tip_chord = 0.8128, 0.3885, 0.2034
    hinge_start, hinge_end = 0.262, 0.8042
    slope = (tip_chord - root_chord) / span

    def area(y):
        return y * (root_chord + slope * y / 2)

    def moment(y):
        return y * y * (root_chord / 2 + slope * y / 3)

    exact = moment(hinge_end) - moment(hinge_start)
    values = {}
    for count in (3, 6, 12):
        edges = [0.0]
        for i in range(1, count):
            target = area(span) * i / count
            edges.append(bisect(lambda y: area(y) - target, 0.0, span))
        edges.append(span)
        estimate = 0.0
        for start, end in zip(edges, edges[1:]):
            lo, hi = max(start, hinge_start), min(end, hinge_end)
            if hi > lo:
                centroid = (moment(end) - moment(start)) / (area(end) - area(start))
                estimate += centroid * (area(hi) - area(lo))
        values[str(count)] = estimate
    require_close(exact, 0.074178415228, 1e-12)
    require_close(values["3"], 0.073028212258, 1e-12)
    if not values["3"] < values["6"] < values["12"] < exact:
        raise ValueError("the held-footprint quadrature control failed")
    source = math.hypot(15, 0.5) * 4.5 * math.atan2(0.5, 15)
    return {"exact_hinge_first_moment_m3": exact, "offline_quadrature_m3": values,
            "positive_wing_only_source_m_per_s": source,
            "positive_lag_at_five_time_constants_m_per_s": -math.expm1(-5) * source}


def helicopter():
    speed = 3.0
    induced = math.sqrt(2 / (speed**2 + math.sqrt(speed**4 + 4)))
    magnitude = math.hypot(speed, induced)
    slopes = [0.0, math.tan(math.radians(15)), -math.tan(math.radians(15))]
    distances = []
    for slope in slopes:
        closing = (induced + slope * speed) / magnitude
        distances.append(1.1 / closing if closing > 0 else None)
    require_close(distances[0], 10.0207494515)
    require_close(distances[1], 2.92473739675)
    if distances[2] is not None:
        raise ValueError("falling plane falsely intersects the downstream ray")
    cut_jump = 1 - 0.9926 / (0.9926 + 0.03794 * (2 / 3)**2)
    reflected_driver = 8.3**2 * 0.001
    rotor = 0.0798
    common = (120 * reflected_driver + 100 * rotor) / (reflected_driver + rotor)
    loss = (reflected_driver * (120 - common)**2 + rotor * (100 - common)**2) / 2
    require_close(loss, 7.39447440985)
    return {"flat_rising_falling_distance_over_radius": distances,
            "hard_cutoff_jump_at_3R": cut_jump, "fixed_carrier_speed_rad_s": common,
            "fixed_carrier_loss_j": loss}


if __name__ == "__main__":
    print(json.dumps({"scope": "independent standard-library scalar and geometry fixtures",
                      "synchronized_box": synchronized_box(), "clear_endpoints_box": clear_endpoints_box(),
                      "controls": controls(), "fixed_wing": wing(), "helicopter": helicopter()},
                     indent=2, allow_nan=False))
