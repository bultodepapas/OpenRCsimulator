#!/usr/bin/env python3
"""Independent algebra for OpenRC FPV Angle-mode and rate-controller test cases.

Run from the repository root with 'python3 /path/to/controls_probe.py .'.
No engine launch or numerical package is required. This is not a GDScript run.
"""
import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path


def clamp(x, low, high):
    return max(low, min(high, x))


def quaternion(heading, pitch, roll):
    cy, cp, cr = [math.cos(x / 2) for x in (heading, pitch, roll)]
    sy, sp, sr = [math.sin(x / 2) for x in (heading, pitch, roll)]
    return (cr * cp * cy + sr * sp * sy, sr * cp * cy - cr * sp * sy,
            cr * sp * cy + sr * cp * sy, cr * cp * sy - sr * sp * cy)


def multiply(a, b):
    w, x, y, z = a
    p, i, j, k = b
    return (w*p-x*i-y*j-z*k, w*i+x*p+y*k-z*j,
            w*j-x*k+y*p+z*i, w*k+x*j-y*i+z*p)


def conjugate(q):
    w, x, y, z = q
    return (w, -x, -y, -z)


def rotate(q, vector):
    return multiply(multiply(q, (0.0, *vector)), conjugate(q))[1:]


def angle_targets(q, angle_settings):
    # FRD body to NED. Stick-centered goal keeps the computed heading.
    nose = rotate(q, (1, 0, 0))
    top = rotate(q, (0, 0, -1))
    if math.hypot(nose[0], nose[1]) > 0.2:
        heading = math.atan2(nose[1], nose[0])
    elif nose[2] < 0.0:
        heading = math.atan2(-top[1], -top[0])
    else:
        heading = math.atan2(top[1], top[0])
    delta = multiply(conjugate(q), quaternion(heading, 0.0, 0.0))
    flip = -1.0 if delta[0] < 0 else 1.0
    norm = math.hypot(*delta[1:])
    scale = 2.0 * flip
    if norm > 1e-9:
        scale *= math.atan2(norm, flip * delta[0]) / norm
    gain = angle_settings["gain"]["value"]
    cap = angle_settings["rate_limit"]["value"]
    rates = [clamp(math.degrees(gain * scale * axis), -cap, cap) for axis in delta[1:3]]
    return (math.degrees(heading), *rates)


def angle_case(controller):
    print("CTRL-01: Angle-mode heading and roll/pitch demand (degrees and degrees/s)")
    pitch_at_switch = math.acos(0.2)
    alpha = 1 - math.exp(-2 * math.pi * controller["setpoint_lpf"]["value"] /
                         controller["sample_rate"]["value"])
    for bank in (45, 0):
        for eps in (1e-5, 1e-8):
            results = []
            for perturbation in (-eps, eps):
                q = quaternion(0, pitch_at_switch + perturbation, math.radians(bank))
                heading, roll_rate, pitch_rate = angle_targets(q, controller["angle"])
                # A single physical attitude has two quaternion representations.
                qneg = tuple(-v for v in q)
                other = angle_targets(qneg, controller["angle"])
                assert all(abs(a-b) < 1e-9 for a, b in zip((heading, roll_rate, pitch_rate), other))
                results.append((heading, roll_rate, pitch_rate))
            jump = abs(results[1][1] - results[0][1])
            assert (jump > 190 if bank else jump < 1e-8)
            print(f" bank={bank:2d} eps_rad={eps:g} low={results[0]} high={results[1]} "
                  f"roll_jump={jump:.8f} next_LPF_jump={alpha*jump:.8f}")


def solve_four(matrix, values):
    """Solve the independent 4x4 wrench equations with pivoted elimination."""
    rows = [list(r) + [v] for r, v in zip(matrix, values)]
    for i in range(4):
        pivot = max(range(i, 4), key=lambda k: abs(rows[k][i]))
        rows[i], rows[pivot] = rows[pivot], rows[i]
        assert abs(rows[i][i]) > 1e-12
        rows[i] = [v / rows[i][i] for v in rows[i]]
        for j in range(4):
            if j != i:
                factor = rows[j][i]
                rows[j] = [a-factor*b for a, b in zip(rows[j], rows[i])]
    return [row[-1] for row in rows]


def windup_case(quad):
    print("CTRL-02: First armed yaw step, held zero rates/previous demand/I, static allocation")
    controller = quad["controller"]
    motor = quad["powertrain"]
    rotor = quad["rotor_law"]
    ts = 1.0 / controller["sample_rate"]["value"]
    alpha = 1 - math.exp(-2 * math.pi * controller["setpoint_lpf"]["value"] * ts)
    k_thrust = rotor["thrust_coefficient"]["value"]
    k_torque = rotor["torque_coefficient"]["value"]
    kv = motor["kv"]["value"]
    resistance = motor["resistance"]["value"]
    no_load = motor["no_load_current"]["value"]
    idle = motor["idle_command"]["value"]
    top = motor["max_command"]["value"]
    ocv = quad["battery"]["ocv_points"]["value"][-1][1]
    kp = controller["kp"]["value"][2]
    ki = controller["ki"]["value"][2]
    kaw = controller["kaw"]["value"][2]
    cap = controller["tau_limit"]["value"][2]
    assert controller["kff"]["value"][2] == controller["kd"]["value"][2] == 0.0

    def thrust(u):
        # kt is the motor torque constant (different from the rotor thrust coefficient).
        kt = 1.0 / kv
        b = kt / (kv * resistance)
        c = kt * (u * ocv / resistance - no_load)
        omega = (-b + math.sqrt(b*b + 4*k_torque*c)) / (2*k_torque)
        return k_thrust * omega * omega

    landmarks = [r["hub_frd"]["value"] for r in quad["rotors"]]
    matrix = [[1.0] * 4, [-v[1] for v in landmarks], [v[0] for v in landmarks],
              [r["spin"]*k_torque/k_thrust for r in quad["rotors"]]]
    collective = 0.65
    assert collective > controller["arm_low_throttle"]["value"]
    force = 4.0 * thrust(idle + collective*(top-idle))
    low, high = thrust(idle), thrust(top)
    # +1, -1 and centered are actual default-profile inputs. At |stick|=1
    # the ACTUAL 20/67/58/1998 curve commands exactly 670 degrees/s.
    for stick in (1.0, -1.0, 0.0):
        error = alpha * math.radians(670*stick)
        raw = kp * error
        clipped = clamp(raw, -cap, cap)
        force_targets = solve_four(matrix, [force, 0.0, 0.0, clipped])
        assert all(low < f < high for f in force_targets)
        reconstructed = [sum(w*f for w, f in zip(row, force_targets)) for row in matrix]
        assert all(abs(a-b) < 1e-12 for a, b in zip(reconstructed, [force, 0.0, 0.0, clipped]))
        current_delta = ts * (ki*error + kaw*(reconstructed[3]-clipped))
        track_all_limits_delta = ts * (ki*error + kaw*(reconstructed[3]-raw))
        if stick:
            assert abs(raw) > cap and current_delta*stick > 0 and track_all_limits_delta*stick < 0
        else:
            assert abs(current_delta) < 1e-14
        print(f" stick={stick:+.0f} supply={ocv:.6f} force_bounds=({low:.8f},{high:.8f}) "
              f"targets={[round(f,8) for f in force_targets]} err={error:.8f} "
              f"raw={raw:.8f} cap={clipped:.8f} allocation={reconstructed[3]:.8f} "
              f"dI={current_delta:.8f} full_tracking_example_dI={track_all_limits_delta:.8f}")

    # Four equally driven, healthy motors, frozen SOC, static air, fixed body.
    # All currents are positive, so the regeneration branch is never active.
    print("Coverage: four-motor steady thrust at the controller's OCV versus the plant's bus")
    for supply_resistance in (quad["battery"]["resistance"]["value"], 0.0):
        auxiliary = quad["battery"]["auxiliary_current"]["value"]
        for duty in (0.2, 1.0):
            omega_min, omega_max = 0.0, kv*ocv
            for _ in range(65):
                omega = (omega_min+omega_max)/2
                current = no_load+k_torque*omega*omega*kv
                bus = ocv - supply_resistance*(auxiliary+4*duty*current)
                if duty*bus-omega/kv-current*resistance > 0:
                    omega_min = omega
                else:
                    omega_max = omega
            load_thrust = k_thrust*omega*omega
            assert current > 0 and bus > 0
            if supply_resistance == 0.0:
                assert abs(thrust(duty)-load_thrust) < 1e-12
            print(f" Rpack={supply_resistance:.3f} duty={duty:.1f} bus_V={bus:.6f} "
                  f"predicted_per_rotor_N={thrust(duty):.6f} steady_per_rotor_N={load_thrust:.6f}")


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    quad = json.loads((root / "app/data/multirotors/openrc-fpv5-x1.json").read_text())
    angle_case(quad["controller"])
    windup_case(quad)
    if "--native" in sys.argv[2:]:
        sys.stdout.flush()
        with tempfile.TemporaryDirectory(prefix="openrc-controls-") as work:
            binary = Path(work) / "controls-probe"
            subprocess.run(["c++", "-std=c++17", "-O2", "-ffp-contract=off",
                            "-I", str(root / "research/native-kernel/src"),
                            str(Path(__file__).with_suffix(".cpp")), "-o", str(binary)], check=True)
            subprocess.run([str(binary)], check=True)
