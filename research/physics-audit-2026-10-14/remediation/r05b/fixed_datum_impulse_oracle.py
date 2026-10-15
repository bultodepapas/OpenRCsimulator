"""Independent fixed-datum impact oracle for the R05-B proposed contact contract.

Pure Python/float64; intentionally does not import the application implementation.
Run from the repository root with: python tmp/physics-audit-r05b-review/fixed_datum_impulse_oracle.py
The dynamic fuel sample is synthetic bookkeeping for same-fraction consistency only.
"""

from __future__ import annotations

import json
import math

ASSERTION_COUNT = 0


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def add(a, b):
    return [x + y for x, y in zip(a, b)]


def sub(a, b):
    return [x - y for x, y in zip(a, b)]


def scale(s, a):
    return [s * x for x in a]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def norm(a):
    return math.sqrt(dot(a, a))


def transpose(a):
    return [list(row) for row in zip(*a)]


def matvec(a, x):
    return [dot(row, x) for row in a]


def matmul(a, b):
    bt = transpose(b)
    return [[dot(row, col) for col in bt] for row in a]


def eye(n):
    return [[1.0 if i == j else 0.0 for j in range(n)] for i in range(n)]


def solve(a, b):
    """Pivoted Gauss-Jordan solve, independent of any simulator tensor helper."""
    n = len(b)
    aug = [list(a[i]) + [float(b[i])] for i in range(n)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda row: abs(aug[row][col]))
        if abs(aug[pivot][col]) < 1e-14:
            raise ValueError("singular matrix")
        aug[col], aug[pivot] = aug[pivot], aug[col]
        p = aug[col][col]
        aug[col] = [v / p for v in aug[col]]
        for row in range(n):
            if row == col:
                continue
            factor = aug[row][col]
            aug[row] = [x - factor * y for x, y in zip(aug[row], aug[col])]
    return [aug[i][-1] for i in range(n)]


def inverse(a):
    n = len(a)
    columns = [solve(a, [1.0 if row == col else 0.0 for row in range(n)]) for col in range(n)]
    return transpose(columns)


def quat_rotate(q, v):
    """Scalar-first unit quaternion, body to NED: q * [0,v] * q-conjugate."""
    w, x, y, z = q
    qv = [x, y, z]
    t = scale(2.0, cross(qv, v))
    return add(v, add(scale(w, t), cross(qv, t)))


def unit(v):
    return scale(1.0 / norm(v), v)


def energy_cg(mass, c, inertia_c, v_o, omega):
    v_c = add(v_o, cross(omega, c))
    return 0.5 * mass * dot(v_c, v_c) + 0.5 * dot(omega, matvec(inertia_c, omega))


def cross_matrix(v):
    x, y, z = v
    return [[0.0, -z, y], [z, 0.0, -x], [-y, x, 0.0]]


def fixed_origin_mass_matrix(mass, c, inertia_c):
    """K for coordinates [v_O, omega] from T=.5*m|v_O + omega x c|² + .5*w'I_Cw."""
    cx = cross_matrix(c)
    neg_cx = [[-x for x in row] for row in cx]
    upper_left = [[mass * x for x in row] for row in eye(3)]
    upper_right = [[mass * x for x in row] for row in neg_cx]
    lower_left = transpose(upper_right)
    lower_right = [[inertia_c[i][j] + mass * matmul(transpose(cx), cx)[i][j]
                    for j in range(3)] for i in range(3)]
    return [upper_left[i] + upper_right[i] for i in range(3)] + [
        lower_left[i] + lower_right[i] for i in range(3)
    ]


def block_impulse(mass, c, inertia_c, r_o, impulse):
    moment_o = cross(r_o, impulse)
    generalized_impulse = impulse + moment_o
    delta = solve(fixed_origin_mass_matrix(mass, c, inertia_c), generalized_impulse)
    return delta[:3], delta[3:]


def assert_close(actual, expected, tol=2e-11, label=""):
    global ASSERTION_COUNT
    ASSERTION_COUNT += 1
    error = abs(actual - expected)
    if error > tol * max(1.0, abs(actual), abs(expected)):
        raise AssertionError(f"{label}: actual={actual:.17g}, expected={expected:.17g}, abs_error={error:.3g}")


def assert_vector_close(actual, expected, tol=2e-11, label=""):
    for i, (a, e) in enumerate(zip(actual, expected)):
        assert_close(a, e, tol, f"{label}[{i}]")


def props_at_fraction(f):
    """Synthetic uniform-fraction tank depletion, solely testing coherent event sampling."""
    dry_mass = 9.2
    dry_i_o = [[1.75, 0.07, -0.04], [0.07, 2.15, 0.09], [-0.04, 0.09, 2.8]]
    fuel_full = 1.8
    fuel_r = [0.56, -0.14, 0.19]
    dims = [0.42, 0.27, 0.20]
    fuel_mass = fuel_full * f
    mass = dry_mass + fuel_mass
    c = scale(fuel_mass / mass, fuel_r)
    d2 = dot(fuel_r, fuel_r)
    pp = [[d2 * (1.0 if i == j else 0.0) - fuel_r[i] * fuel_r[j] for j in range(3)] for i in range(3)]
    i_intrinsic_per_kg = [
        [(dims[1] ** 2 + dims[2] ** 2) / 12.0, 0.0, 0.0],
        [0.0, (dims[0] ** 2 + dims[2] ** 2) / 12.0, 0.0],
        [0.0, 0.0, (dims[0] ** 2 + dims[1] ** 2) / 12.0],
    ]
    i_o = [[dry_i_o[i][j] + fuel_mass * (i_intrinsic_per_kg[i][j] + pp[i][j])
            for j in range(3)] for i in range(3)]
    c_parallel = [[mass * ((dot(c, c) if i == j else 0.0) - c[i] * c[j]) for j in range(3)] for i in range(3)]
    i_c = [[i_o[i][j] - c_parallel[i][j] for j in range(3)] for i in range(3)]
    return {"fraction": f, "mass": mass, "cg": c, "inertia_c": i_c}


def impact(props, r_o, n_world, q_body_to_ned, v_o, omega, surface_v_world, restitution):
    n_world = unit(n_world)
    q_inverse = [q_body_to_ned[0], -q_body_to_ned[1], -q_body_to_ned[2], -q_body_to_ned[3]]
    n_body = unit(quat_rotate(q_inverse, n_world))
    surface_v_body = quat_rotate(q_inverse, surface_v_world)
    point_v_body = sub(add(v_o, cross(omega, r_o)), surface_v_body)
    vn = dot(point_v_body, n_body)
    if vn >= 0.0:
        raise AssertionError("fixture must be closing along outward normal")
    r_c = sub(r_o, props["cg"])
    i_inv = inverse(props["inertia_c"])
    angular_arm = cross(r_c, n_body)
    beta = 1.0 / props["mass"] + dot(angular_arm, matvec(i_inv, angular_arm))
    meff = 1.0 / beta
    impulse_mag = -(1.0 + restitution) * vn / beta
    impulse = scale(impulse_mag, n_body)
    delta_omega = matvec(i_inv, cross(r_c, impulse))
    delta_v_o = sub(scale(1.0 / props["mass"], impulse), cross(delta_omega, props["cg"]))

    point_delta = add(delta_v_o, cross(delta_omega, r_o))
    vn_after = vn + dot(point_delta, n_body)
    k_before = energy_cg(props["mass"], props["cg"], props["inertia_c"], v_o, omega)
    k_after = energy_cg(props["mass"], props["cg"], props["inertia_c"], add(v_o, delta_v_o), add(omega, delta_omega))
    # Relative restitution uses the moving contact surface velocity; vehicle-only K also receives
    # the external work J·v_surface. For the frequent fixed-ground case this term is zero.
    expected_dk = -0.5 * (1.0 - restitution * restitution) * vn * vn / beta + dot(impulse, surface_v_body)

    delta_v_o_block, delta_omega_block = block_impulse(props["mass"], props["cg"], props["inertia_c"], r_o, impulse)
    assert_vector_close(delta_v_o, delta_v_o_block, label="fixed-origin block dvO")
    assert_vector_close(delta_omega, delta_omega_block, label="fixed-origin block domega")
    assert_close(vn_after, -restitution * vn, label="restitution")
    assert_close(k_after - k_before, expected_dk, label="CG kinetic-energy change")
    assert_vector_close(add(delta_v_o, cross(delta_omega, props["cg"])), scale(1.0 / props["mass"], impulse),
                        label="CG translational jump")
    return {"fraction": props["fraction"], "mass_kg": props["mass"], "cg_body_m": props["cg"],
            "vn_before_mps": vn, "vn_after_mps": vn_after, "effective_mass_kg": meff,
            "impulse_n_s_body": impulse, "delta_v_o_mps_body": delta_v_o,
            "delta_omega_rad_s_body": delta_omega, "delta_k_j": k_after-k_before,
            "expected_delta_k_j": expected_dk,
            "surface_work_j": dot(impulse, surface_v_body), "block_matrix_max_delta": max(
                max(abs(a-b) for a,b in zip(delta_v_o, delta_v_o_block)),
                max(abs(a-b) for a,b in zip(delta_omega, delta_omega_block))) }


def main():
    mass = 12.4
    cg = [0.23, -0.07, 0.11]
    inertia_c = [[2.8, 0.21, -0.13], [0.21, 3.7, 0.17], [-0.13, 0.17, 4.5]]
    r_o = [1.1, 0.42, -0.31]
    axis = unit([0.4, -0.2, 0.89])
    half = 0.235
    q = [math.cos(half), *(math.sin(half) * x for x in axis)]
    n_body = unit([0.21, -0.28, 0.936])
    n_world = quat_rotate(q, n_body)
    v_o = [-4.0, 0.8, -1.5]
    omega = [0.4, -0.8, 0.23]
    surface_v_world = quat_rotate(q, [0.17, -0.08, 0.03])
    static_props = {"fraction": None, "mass": mass, "cg": cg, "inertia_c": inertia_c}
    restitution_rows = [impact(static_props, r_o, n_world, q, v_o, omega, surface_v_world, e) for e in [0.0, 0.37, 1.0]]

    # Contact through the instantaneous CG has no angular impulse leverage.
    center = impact(static_props, cg, n_world, q, v_o, omega, surface_v_world, 0.5)
    assert_close(center["effective_mass_kg"], mass, label="CG point effective mass")
    if norm(center["delta_omega_rad_s_body"]) > 1e-12:
        raise AssertionError("CG point contact generated angular velocity")

    fraction = 0.37
    sampled = props_at_fraction(fraction)
    event = impact(sampled, r_o, n_world, q, v_o, omega, surface_v_world, 0.0)
    start = props_at_fraction(0.0)
    end = props_at_fraction(1.0)
    if sampled["fraction"] != event["fraction"]:
        raise AssertionError("event did not retain its exact event-time mass sample")
    if abs(sampled["mass"] - start["mass"]) < 1e-8 or abs(sampled["mass"] - end["mass"]) < 1e-8:
        raise AssertionError("fraction fixture did not distinguish event-time from endpoint properties")
    if norm(sub(sampled["cg"], end["cg"])) < 1e-5:
        raise AssertionError("fraction fixture did not distinguish CG at TOI from endpoint")

    print(json.dumps({"oracle": "independent fixed-datum impulse / 6x6 mass-matrix",
                      "scalar_assertions": ASSERTION_COUNT,
                      "restitution_cases": restitution_rows, "center_of_mass_contact": center,
                      "same_fraction_sample": {"event_fraction": event["fraction"],
                          "event_mass_kg": event["mass_kg"], "event_cg_body_m": event["cg_body_m"],
                          "start_mass_kg": start["mass"], "end_mass_kg": end["mass"],
                          "effective_mass_kg": event["effective_mass_kg"]}}, indent=2))


if __name__ == "__main__":
    main()
