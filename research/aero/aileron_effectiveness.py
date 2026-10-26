"""Author conventional-wing aileron effectiveness for the current six-strip law.

Uses the D11d Weissinger algebra (d11d/lifting_line.py) and AircraftData's
equal-area geometry and section-slope calibration. The returned angle gain
matches the antisymmetric attached roll derivative about the aerodynamic
reference point. This establishes model consistency, not measured authority.
"""

from __future__ import annotations

import math
from collections.abc import Sequence


STRIPS_PER_SIDE = 3


def _number(value: float, name: str, *, positive: bool = True) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{name} must be a finite number")
    try:
        value = float(value)
    except OverflowError as error:
        raise ValueError(f"{name} is unrepresentable") from error
    if not math.isfinite(value) or (value <= 0.0 if positive else value < 0.0):
        raise ValueError(f"{name} must be finite and {'positive' if positive else 'nonnegative'}")
    return value


def _geometry(area: float, span: float, chords: Sequence[float] | None):
    root = tip = area / span
    if chords is not None:
        if not isinstance(chords, Sequence) or isinstance(chords, (str, bytes)) or len(chords) != 2:
            raise ValueError("chords must contain root and tip chord")
        root, tip = (_number(value, "chord") for value in chords)
        if tip > root or abs(span * (root + tip) / 2.0 - area) / area > 0.01:
            raise ValueError("chords must taper toward the tip and reproduce area within 1%")
    half = span / 2.0
    slope = (tip - root) / half
    right = [0.0]
    centres = []
    # Godot is_equal_approx(root, tip), used by station_ys/station_edges.
    rectangular = abs(root - tip) < max(1e-5, 1e-5 * abs(root))
    for k in range(STRIPS_PER_SIDE):
        target = (root * half + slope * half * half / 2.0) * (k + 1) / STRIPS_PER_SIDE
        end = half if k == STRIPS_PER_SIDE - 1 else (
            (k + 1) * half / STRIPS_PER_SIDE if rectangular
            else 2.0 * target / (root + math.sqrt(root * root + 2.0 * slope * target))
        )
        start = right[-1]
        middle = (start + end) / 2.0
        centre = middle if rectangular else middle + slope * (end - start) ** 2 / (12.0 * (root + slope * middle))
        right.append(end)
        centres.append(centre)
    edges = [-value for value in reversed(right[1:])] + right
    ys = [-value for value in reversed(centres)] + centres
    local_chords = [root + slope * abs(y) for y in ys]
    if not all(math.isfinite(value) for value in edges + ys + local_chords):
        raise ValueError("nonfinite strip geometry")
    return edges, ys, local_chords


def _vortex_z(px, py, x1, y1, x2, y2):
    r1x, r1y, r2x, r2y = px - x1, py - y1, px - x2, py - y2
    cross = r1x * r2y - r1y * r2x
    if abs(cross) < 1e-14:
        return 0.0
    n1, n2 = math.hypot(r1x, r1y), math.hypot(r2x, r2y)
    dot = (x2 - x1) * (r1x / n1 - r2x / n2) + (y2 - y1) * (r1y / n1 - r2y / n2)
    return dot / (4.0 * math.pi * cross)


def _influence(edges, ys, chords):
    matrix = []
    for i, y in enumerate(ys):
        row = []
        for j, chord in enumerate(chords):
            start, end = edges[j:j + 2]
            velocity = (_vortex_z(chords[i] / 2.0, y, 1e5, start, 0.0, start)
                        + _vortex_z(chords[i] / 2.0, y, 0.0, start, 0.0, end)
                        + _vortex_z(chords[i] / 2.0, y, 0.0, end, 1e5, end))
            row.append(-velocity * 0.5 * chord - (1.0 / math.tau if i == j else 0.0))
        matrix.append(row)
    return matrix


def _angle_map(influence, section_slope):
    n = len(influence)
    matrix = [[float(i == j) + section_slope * value for j, value in enumerate(row)]
              + [float(i == j) for j in range(n)] for i, row in enumerate(influence)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda row: abs(matrix[row][col]))
        matrix[col], matrix[pivot] = matrix[pivot], matrix[col]
        divisor = matrix[col][col]
        if not math.isfinite(divisor) or abs(divisor) < 1e-14:
            raise ValueError("singular induced-flow calibration")
        matrix[col] = [value / divisor for value in matrix[col]]
        for row in range(n):
            if row != col:
                factor = matrix[row][col]
                matrix[row] = [a - factor * b for a, b in zip(matrix[row], matrix[col])]
    result = [row[n:] for row in matrix]
    if not all(math.isfinite(value) for row in result for value in row):
        raise ValueError("nonfinite induced-flow calibration")
    return result


def _calibrate(influence, target):
    def response(slope):
        angle_map = _angle_map(influence, slope)
        return slope * sum(sum(row) for row in angle_map) / len(angle_map), angle_map

    low, high = 0.1, 50.0  # AircraftData._induced_map's admitted section-slope range.
    if not response(low)[0] < target < response(high)[0]:
        raise ValueError("wing lift slope cannot be calibrated in section-slope range (0.1, 50)")
    for _ in range(80):
        middle = (low + high) / 2.0
        if middle == low or middle == high:
            break
        if response(middle)[0] < target:
            low = middle
        else:
            high = middle
    slope = (low + high) / 2.0
    solved, angle_map = response(slope)
    if abs(solved - target) > 1e-10 * max(1.0, abs(target)):
        raise ValueError("induced-flow calibration did not converge")
    return slope, angle_map


def derive_effectiveness(area: float, span: float, lift_slope: float,
                         tail_lift_share: float, clda_right: float,
                         chords: Sequence[float] | None = None) -> float:
    """Return authored tau in [0.01, 1], or raise ValueError for invalid inputs.

    Dimensions: area m², span/chords m, lift slopes and Clda_right per radian.
    tail_lift_share is horizontal_area / wing_area * effective_tail_lift_slope.
    Clda_right is negative for trailing-edge down; the symmetric left derivative
    is its opposite. The calibration uses clean attached flow at alpha=0,
    before polar/stall continuation, without ground effect or propulsion.
    """
    area = _number(area, "area")
    span = _number(span, "span")
    lift_slope = _number(lift_slope, "lift_slope")
    tail_lift_share = _number(tail_lift_share, "tail_lift_share", positive=False)
    target = lift_slope - tail_lift_share
    if target <= 0.0:
        raise ValueError("horizontal tail leaves no positive wing lift slope")
    if isinstance(clda_right, bool) or not isinstance(clda_right, (int, float)):
        raise ValueError("clda_right must be a finite negative number")
    magnitude = _number(-clda_right, "negative clda_right")
    try:
        edges, ys, local_chords = _geometry(area, span, chords)
        slope, angle_map = _calibrate(_influence(edges, ys, local_chords), target)
        # Unit right-only incidence. Symmetry supplies the opposite left value;
        # differential control doubles both the target and this response.
        derivative = -slope * sum(y * sum(row[STRIPS_PER_SIDE:])
                                  for y, row in zip(ys, angle_map)) / (len(ys) * span)
        effectiveness = -magnitude / derivative
    except (OverflowError, ZeroDivisionError) as error:
        raise ValueError("unrepresentable induced-flow calibration") from error
    if not math.isfinite(effectiveness) or not 0.01 <= effectiveness <= 1.0:
        raise ValueError("derived aileron effectiveness lies outside aircraft bounds [0.01, 1]")
    return effectiveness
