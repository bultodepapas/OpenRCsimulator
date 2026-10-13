"""Independent fixed-datum and moving-CG variable-mass mechanics reference.

All vectors and tensors are expressed in body axes.  The body datum O is fixed
in the dry structure.  Outflow rates are positive out of the modeled body, and
each outlet's relative velocity is measured from the local rigid-body velocity
at that outlet.  This module is a small stdlib-only verification oracle, not a
production flight integrator.
"""

from __future__ import annotations

from dataclasses import dataclass
from math import cos, isfinite, sin, sqrt
from typing import Iterable, Sequence

Vec3 = tuple[float, float, float]
Mat3 = tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float]]

ZERO: Vec3 = (0.0, 0.0, 0.0)
ZERO_MAT: Mat3 = ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0))


def add(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def scale(k: float, a: Vec3) -> Vec3:
    return (k * a[0], k * a[1], k * a[2])


def dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a: Vec3, b: Vec3) -> Vec3:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def mat_add(a: Mat3, b: Mat3) -> Mat3:
    return tuple(tuple(a[i][j] + b[i][j] for j in range(3)) for i in range(3))  # type: ignore[return-value]


def mat_sub(a: Mat3, b: Mat3) -> Mat3:
    return tuple(tuple(a[i][j] - b[i][j] for j in range(3)) for i in range(3))  # type: ignore[return-value]


def mat_scale(k: float, a: Mat3) -> Mat3:
    return tuple(tuple(k * a[i][j] for j in range(3)) for i in range(3))  # type: ignore[return-value]


def mat_vec(a: Mat3, v: Vec3) -> Vec3:
    return tuple(sum(a[i][j] * v[j] for j in range(3)) for i in range(3))  # type: ignore[return-value]


def parallel_axis(r: Vec3) -> Mat3:
    """Return S(r) = |r|^2 I - r r^T, the inertia contribution per kg."""
    rr = dot(r, r)
    return (
        (rr - r[0] * r[0], -r[0] * r[1], -r[0] * r[2]),
        (-r[1] * r[0], rr - r[1] * r[1], -r[1] * r[2]),
        (-r[2] * r[0], -r[2] * r[1], rr - r[2] * r[2]),
    )


@dataclass(frozen=True)
class Component:
    """One rigid component with centroid and inertia about its own centroid."""

    mass: float
    center: Vec3
    inertia_center: Mat3


@dataclass(frozen=True)
class MassProperties:
    """Mass and first/second spatial moments about the fixed body datum O."""

    mass: float
    first_moment: Vec3
    inertia_origin: Mat3

    @property
    def center(self) -> Vec3:
        if self.mass <= 0.0:
            raise ValueError("mass must be positive")
        return scale(1.0 / self.mass, self.first_moment)

    @property
    def inertia_center(self) -> Mat3:
        c = self.center
        return mat_sub(self.inertia_origin, mat_scale(self.mass, parallel_axis(c)))


@dataclass(frozen=True)
class Outflow:
    """A body-fixed outlet with positive outward rate and local relative speed."""

    mass_rate: float
    position: Vec3
    relative_velocity: Vec3 = ZERO


@dataclass(frozen=True)
class BodyState:
    """Velocity of O and angular velocity, both resolved in body axes."""

    origin_velocity: Vec3
    angular_velocity: Vec3


@dataclass(frozen=True)
class Wrench:
    """External force and moment about O, both resolved in body axes."""

    force: Vec3
    moment_origin: Vec3


@dataclass(frozen=True)
class FixedDatumAcceleration:
    origin_velocity_dot: Vec3
    angular_velocity_dot: Vec3


@dataclass(frozen=True)
class CgAcceleration:
    """Derivative of P/m and omega, plus the changing CG body coordinate."""

    momentum_velocity_dot: Vec3
    angular_velocity_dot: Vec3
    center_dot: Vec3


def combine_components(components: Iterable[Component]) -> MassProperties:
    """Combine component mass, first moment, and full symmetric inertia tensors."""
    mass = 0.0
    first = ZERO
    inertia = ZERO_MAT
    found = False
    for component in components:
        found = True
        if component.mass < 0.0:
            raise ValueError("component mass cannot be negative")
        mass += component.mass
        first = add(first, scale(component.mass, component.center))
        inertia = mat_add(
            inertia,
            mat_add(component.inertia_center, mat_scale(component.mass, parallel_axis(component.center))),
        )
    if not found or mass <= 0.0:
        raise ValueError("components must have positive total mass")
    result = MassProperties(mass, first, inertia)
    if not is_symmetric(result.inertia_center) or not is_positive_definite(result.inertia_center):
        raise ValueError("combined centroidal inertia must be symmetric positive definite")
    return result


def is_symmetric(a: Mat3, tol: float = 1e-12) -> bool:
    return all(abs(a[i][j] - a[j][i]) <= tol for i in range(3) for j in range(3))


def is_positive_definite(a: Mat3) -> bool:
    """Cholesky check for a symmetric 3x3 tensor."""
    if not is_symmetric(a):
        return False
    lower = [[0.0] * 3 for _ in range(3)]
    for i in range(3):
        for j in range(i + 1):
            value = a[i][j] - sum(lower[i][k] * lower[j][k] for k in range(j))
            if i == j:
                if value <= 0.0:
                    return False
                lower[i][j] = sqrt(value)
            else:
                lower[i][j] = value / lower[j][j]
    return True


def mass_property_rates(outflows: Sequence[Outflow]) -> tuple[float, Vec3, Mat3]:
    """Return (m_dot, h_dot, J_O_dot) for material removed at the listed ports."""
    mass_dot = 0.0
    first_dot = ZERO
    inertia_dot = ZERO_MAT
    for flow in outflows:
        if flow.mass_rate < 0.0:
            raise ValueError("outflow rates must be nonnegative")
        mass_dot -= flow.mass_rate
        first_dot = sub(first_dot, scale(flow.mass_rate, flow.position))
        inertia_dot = mat_sub(inertia_dot, mat_scale(flow.mass_rate, parallel_axis(flow.position)))
    return mass_dot, first_dot, inertia_dot


def center_rates(props: MassProperties, outflows: Sequence[Outflow]) -> tuple[Vec3, Mat3]:
    """Return exact body-coordinate c_dot and I_CG_dot for the same material outlets."""
    if props.mass <= 0.0:
        raise ValueError("mass must be positive")
    c = props.center
    center_dot = ZERO
    inertia_center_dot = ZERO_MAT
    for flow in outflows:
        if flow.mass_rate < 0.0:
            raise ValueError("outflow rates must be nonnegative")
        q = sub(flow.position, c)
        center_dot = sub(center_dot, scale(flow.mass_rate / props.mass, q))
        inertia_center_dot = mat_sub(
            inertia_center_dot,
            mat_scale(flow.mass_rate, parallel_axis(q)),
        )
    return center_dot, inertia_center_dot


def _cross_matrix(v: Vec3) -> list[list[float]]:
    return [[0.0, -v[2], v[1]], [v[2], 0.0, -v[0]], [-v[1], v[0], 0.0]]


def _solve_linear(a: Sequence[Sequence[float]], b: Sequence[float]) -> list[float]:
    """Partial-pivot Gaussian elimination; dimensions here are at most six."""
    n = len(b)
    if len(a) != n or any(len(row) != n for row in a):
        raise ValueError("linear system must be square")
    work = [list(map(float, row)) + [float(b[i])] for i, row in enumerate(a)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda row: abs(work[row][col]))
        if abs(work[pivot][col]) <= 1e-14:
            raise ValueError("singular spatial inertia")
        work[col], work[pivot] = work[pivot], work[col]
        divisor = work[col][col]
        for j in range(col, n + 1):
            work[col][j] /= divisor
        for row in range(n):
            if row == col:
                continue
            factor = work[row][col]
            for j in range(col, n + 1):
                work[row][j] -= factor * work[col][j]
    answer = [work[i][n] for i in range(n)]
    if not all(isfinite(x) for x in answer):
        raise ValueError("non-finite acceleration")
    return answer


def solve_fixed_datum(
    props: MassProperties,
    state: BodyState,
    wrench: Wrench,
    outflows: Sequence[Outflow] = (),
) -> FixedDatumAcceleration:
    """Solve open-system Newton-Euler equations at the fixed dry-body datum O.

    The mass, first moment, and inertia rates must correspond to ``outflows``.
    Co-moving outlet momentum cancels those property rates exactly; only the
    outlet's velocity relative to the local rigid-body motion remains.
    """
    if props.mass <= 0.0:
        raise ValueError("mass must be positive")
    if not is_symmetric(props.inertia_origin) or not is_positive_definite(props.inertia_center):
        raise ValueError("mass properties need a symmetric positive centroidal tensor")

    m = props.mass
    h = props.first_moment
    j = props.inertia_origin
    v = state.origin_velocity
    omega = state.angular_velocity

    momentum = add(scale(m, v), cross(omega, h))
    angular_momentum_o = add(cross(h, v), mat_vec(j, omega))

    relative_force_flux = ZERO
    relative_moment_flux = ZERO
    for flow in outflows:
        if flow.mass_rate < 0.0:
            raise ValueError("outflow rates must be nonnegative")
        relative_force_flux = add(relative_force_flux, scale(flow.mass_rate, flow.relative_velocity))
        relative_moment_flux = add(
            relative_moment_flux,
            scale(flow.mass_rate, cross(flow.position, flow.relative_velocity)),
        )

    rhs_force = sub(
        sub(
            sub(wrench.force, scale(m, cross(omega, v))),
            cross(omega, cross(omega, h)),
        ),
        relative_force_flux,
    )
    rhs_moment = sub(
        sub(
            sub(wrench.moment_origin, cross(omega, angular_momentum_o)),
            cross(v, momentum),
        ),
        relative_moment_flux,
    )

    h_cross = _cross_matrix(h)
    matrix = [[0.0] * 6 for _ in range(6)]
    for i in range(3):
        for j_index in range(3):
            matrix[i][j_index] = m if i == j_index else 0.0
            matrix[i][j_index + 3] = -h_cross[i][j_index]
            matrix[i + 3][j_index] = h_cross[i][j_index]
            matrix[i + 3][j_index + 3] = j[i][j_index]
    answer = _solve_linear(matrix, list(rhs_force + rhs_moment))
    return FixedDatumAcceleration(tuple(answer[:3]), tuple(answer[3:]))  # type: ignore[arg-type]


def solve_current_cg(
    props: MassProperties,
    state: BodyState,
    wrench: Wrench,
    outflows: Sequence[Outflow] = (),
) -> CgAcceleration:
    """Solve the equivalent equations at the instantaneous mass center.

    ``momentum_velocity`` is P/m in body axes.  It is not the derivative of
    geometric CG position when the CG moves through the body.
    """
    if props.mass <= 0.0:
        raise ValueError("mass must be positive")
    center = props.center
    inertia = props.inertia_center
    if not is_symmetric(inertia) or not is_positive_definite(inertia):
        raise ValueError("current-CG tensor must be symmetric positive definite")

    m = props.mass
    omega = state.angular_velocity
    momentum_velocity = add(state.origin_velocity, cross(omega, center))
    center_dot, inertia_dot = center_rates(props, outflows)

    translation_flux = ZERO
    moment_flux = ZERO
    for flow in outflows:
        q = sub(flow.position, center)
        relative_to_cg = add(cross(omega, q), flow.relative_velocity)
        translation_flux = add(translation_flux, scale(flow.mass_rate, relative_to_cg))
        moment_flux = add(moment_flux, scale(flow.mass_rate, cross(q, relative_to_cg)))

    momentum_velocity_dot = scale(
        1.0 / m,
        sub(sub(wrench.force, scale(m, cross(omega, momentum_velocity))), translation_flux),
    )

    moment_center = sub(wrench.moment_origin, cross(center, wrench.force))
    angular_momentum_c = mat_vec(inertia, omega)
    rotational_bias = add(
        add(cross(omega, angular_momentum_c), mat_vec(inertia_dot, omega)),
        moment_flux,
    )
    angular_rhs = sub(moment_center, rotational_bias)
    angular_velocity_dot = tuple(_solve_linear(inertia, angular_rhs))  # type: ignore[arg-type]
    return CgAcceleration(momentum_velocity_dot, angular_velocity_dot, center_dot)


def momentum_velocity_at_cg(state: BodyState, center: Vec3) -> Vec3:
    """Return P/m in body axes for a rigid velocity field about O."""
    return add(state.origin_velocity, cross(state.angular_velocity, center))


def geometric_cg_position_rate_body(
    state: BodyState,
    center: Vec3,
    center_dot: Vec3,
) -> Vec3:
    """Return R^T x_C_dot for x_C = x_O + R c, including c_dot exactly."""
    return add(momentum_velocity_at_cg(state, center), center_dot)


def rotate_exp(v: Vec3, omega: Vec3, t: float) -> Vec3:
    """Apply exp([omega] t) to v; used only by the kinematic finite-difference test."""
    rate = sqrt(dot(omega, omega))
    if rate == 0.0:
        return v
    angle = rate * t
    first = scale(sin(angle) / rate, cross(omega, v))
    second = scale((1.0 - cos(angle)) / (rate * rate), cross(omega, cross(omega, v)))
    return add(add(v, first), second)


def origin_position_for_constant_body_twist(v: Vec3, omega: Vec3, t: float) -> Vec3:
    """Integrate x_O_dot = R v for constant body-axis v and omega from R(0)=I."""
    rate = sqrt(dot(omega, omega))
    if rate == 0.0:
        return scale(t, v)
    rate2 = rate * rate
    first = scale((1.0 - cos(rate * t)) / rate2, cross(omega, v))
    second = scale((t / rate2 - sin(rate * t) / (rate2 * rate)), cross(omega, cross(omega, v)))
    return add(add(scale(t, v), first), second)
