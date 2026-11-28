"""Independent multirotor contact and isolated steady axial-power oracles.

Run with Python, NumPy, SciPy, and the OpenRC simulator repository path.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from scipy.integrate import solve_ivp


def contact_response(mobility, jacobian, incoming, normal, mu):
    """Resolve the declared normal-then-friction response at one fixed point."""
    point_before = jacobian @ incoming
    point_mobility = jacobian @ mobility @ jacobian.T
    normal_impulse = -1.2 * (normal @ point_before) / (normal @ point_mobility @ normal)
    impulse = normal_impulse * normal
    point_after_normal = point_before + point_mobility @ impulse
    normal_speed = normal @ point_after_normal
    slide = point_after_normal - normal_speed * normal
    slip = np.linalg.norm(slide)
    if slip > 1e-9 and mu > 0:
        tangent = slide / slip
        magnitude = min(mu * normal_impulse, slip / (tangent @ point_mobility @ tangent))
        normal_reduction = normal @ point_mobility @ tangent
        if normal_reduction > 0:
            magnitude = min(magnitude, normal_speed / normal_reduction)
        impulse -= magnitude * tangent
    change = mobility @ jacobian.T @ impulse
    return incoming + change, impulse, normal_speed, normal @ jacobian @ (incoming + change)


def mass_and_geometry(data):
    diagnostics = data["provenance"]["derived_diagnostics"]
    xx, yy, zz, xy, xz, yz = diagnostics["inertia_kg_m2"]
    locked = np.array([[xx, xy, xz], [xy, yy, yz], [xz, yz, zz]])
    rotor_j = np.array([r["inertia"]["value"] for r in data["rotors"]])
    spin = np.array([r["spin"] for r in data["rotors"]])
    mass = np.zeros((10, 10))
    mass[:3, :3] = np.eye(3) * diagnostics["mass_kg"]
    mass[3:6, 3:6] = locked
    mass[5, 6:] = mass[6:, 5] = -spin * rotor_j
    mass[6:, 6:] = np.diag(rotor_j)
    arm = np.array(data["rotors"][1]["hub_frd"]["value"])
    top = min(p[2] for p in data["contacts"]["hull"]["value"])
    arm[2] = (top + 2 * (-0.021 + 1e-6)) / 3
    return mass, arm, spin


def contact_checks(data):
    mass, arm, spin = mass_and_geometry(data)
    full_mobility = np.linalg.inv(mass)
    frozen_mobility = np.zeros_like(mass)
    frozen_mobility[:6, :6] = np.linalg.inv(mass[:6, :6])
    angle = math.radians(10)
    normal = np.array([-math.cos(angle), -math.sin(angle), 0.])
    for label, point, initial_shafts in [
        ("gate", arm, [1600, 600, 600, 1600]),
        ("balanced", arm, [1000] * 4),
        ("through_cg", np.zeros(3), [1600, 600, 600, 1600]),
    ]:
        initial = np.r_[-0.2 * normal, np.zeros(3), initial_shafts]
        jacobian = np.zeros((3, 10))
        jacobian[:, :3] = np.eye(3)
        jacobian[:, 3:6] = np.cross(np.eye(3), point).T
        for law, mobility in [("frozen", frozen_mobility), ("coupled", full_mobility)]:
            final, impulse, normal_only, final_normal = contact_response(
                mobility, jacobian, initial, normal, 0.4)
            change = final - initial
            delta_k = .5 * ((final + initial) @ mass @ change)
            residual = mass @ change - jacobian.T @ impulse
            shaft_momentum = np.max(abs(residual[6:]))
            axial_error = np.max(abs(change[5] - spin * change[6:]))
            print(f"{label:10} {law:8} dK={delta_k:+.12f} J; "
                  f"angular_residual={np.linalg.norm(residual[3:6]):.3e} N m s; "
                  f"shaft_residual={shaft_momentum:.3e} N m s; axial_jump={axial_error:.9f} rad/s; "
                  f"vn_normal={normal_only:.9f} vn_final={final_normal:.9f} m/s")
            assert np.max(abs(residual[:6])) < 1e-12
            if law == "coupled" or label == "through_cg":
                assert shaft_momentum < 1e-15 and axial_error < 1e-10 and delta_k < 0
            elif label == "gate":
                assert delta_k > .0107 and axial_error > 1
            else:
                assert delta_k < 0 and axial_error > 1


def axial_checks(data):
    rpm_law = data["rotor_law"]
    diameter = data["rotors"][0]["diameter"]["value"]
    omega, rho = 1000., 1.225
    area = math.pi * diameter**2 / 4
    thrust = rpm_law["thrust_coefficient"]["value"] * omega**2
    shaft_power = rpm_law["torque_coefficient"]["value"] * omega**3
    for speed in (0., 8., 15.):
        disk_speed = .5 * (speed + math.sqrt(speed**2 + 2 * thrust / (rho * area)))
        ideal_power = thrust * disk_speed
        print(f"axial={speed:2.0f} m/s Pshaft={shaft_power:.8f} W Puse={thrust*speed:.8f} W "
              f"Pideal={ideal_power:.8f} W eta={thrust*speed/shaft_power:.8f}")
        if speed == 8:
            assert thrust * speed < shaft_power < ideal_power
        elif speed == 0:
            assert 0 < ideal_power < shaft_power
        else:
            assert shaft_power < thrust * speed < ideal_power


def allocation_check(data):
    spin = np.array([r["spin"] for r in data["rotors"]])
    thrust_0, delta = 1.5, 0.1
    for quadratic in (0., .001):
        def torque(thrust):
            return .009 * thrust + quadratic * thrust**2
        commanded = thrust_0 + spin * delta
        frozen = spin @ (commanded * torque(thrust_0) / thrust_0)
        actual = spin @ torque(commanded)
        derivative = 4 * delta * (.009 + 2 * quadratic * thrust_0)
        print(f"synthetic Q(T), b={quadratic:g}: fixed={frozen:.8f}, "
              f"achieved={actual:.8f}, differential={derivative:.8f} Nm")
        assert abs(actual - derivative) < 1e-14
        assert abs((actual - frozen) - 4 * delta * quadratic * thrust_0) < 1e-14


def crossing_check(data):
    """Symmetric stock motors activate together inside a manufactured geometry interval."""
    motor = data["powertrain"]
    battery = data["battery"]
    kv = motor["kv"]["value"]
    resistance = motor["resistance"]["value"]
    idle = motor["no_load_current"]["value"]
    pack_r = battery["resistance"]["value"]
    aux = battery["auxiliary_current"]["value"]
    capacity = 3600 * battery["capacity"]["value"]
    soc, voltage = np.array(battery["ocv_points"]["value"]).T
    shaft_j = data["rotors"][0]["inertia"]["value"]
    kq = data["rotor_law"]["torque_coefficient"]["value"]
    duty, period, strike_speed = 0.20, 1 / 240, 300.

    def rates(time, state):
        omega, consumed, _ = state
        voc = np.interp(1 - consumed / capacity, soc, voltage)
        emf = omega / kv
        pack_i = (aux + 4 * duty * (duty * voc - emf) / resistance) / (
            1 + 4 * duty**2 * pack_r / resistance)
        vbus = voc - pack_r * pack_i
        motor_i = (duty * vbus - emf) / resistance
        assert pack_i > 0 and omega > 100
        return [((motor_i - idle) / kv - kq * omega**2) / shaft_j, pack_i, vbus * pack_i]

    def threshold(time, state):
        return state[0] - strike_speed

    results = []
    for steps in (8, 32):
        solution = solve_ivp(rates, (0., period), [285., 0., 0.], events=threshold,
                             method="DOP853", dense_output=True, max_step=period / steps,
                             rtol=2e-12, atol=1e-13)
        assert solution.success and len(solution.t_events[0]) == 1
        event = solution.t_events[0][0]
        speed_at_edges = solution.sol(np.array([.1, .3]) * period)[0]
        assert speed_at_edges[0] < strike_speed < speed_at_edges[1]
        assert .1 < event / period < .3
        charge_event, energy_event = solution.sol(event)[1:]
        charge_end, energy_end = solution.sol(period)[1:]
        results.append(event)
    assert abs(results[0] - results[1]) < 1e-11
    print(f"overlap: Ω(entry/exit)={speed_at_edges[0]:.6f}/{speed_at_edges[1]:.6f} rad/s; "
          f"activation={event/period:.9f} tick, {event*1e6:.6f} µs; "
          f"consumed event/end={charge_event:.9f}/{charge_end:.9f} C; "
          f"terminal energy event/end={energy_event:.9f}/{energy_end:.9f} J")


if __name__ == "__main__":
    source = Path(sys.argv[1]) / "app/data/multirotors/openrc-fpv5-x1.json"
    aircraft = json.loads(source.read_text())
    contact_checks(aircraft)
    axial_checks(aircraft)
    allocation_check(aircraft)
    crossing_check(aircraft)
