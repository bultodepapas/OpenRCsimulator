"""Check equal-density launch inputs, FPV port powers, and static authority.

Run with Python 3, g++, the existing electric_probe.py/.cpp, and the repository path.
"""
import argparse
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import tempfile


def launch(repo, probes):
    spec = importlib.util.spec_from_file_location("electric_audit", probes / "electric_probe.py")
    baseline = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(baseline)
    original = baseline.native_cases(repo)
    model, start = original.split(" 4 calm ")
    assert start.startswith("1.225 288.15 0.0 ")
    density = 1.225
    cases = []
    for temperature in (278.15, 308.15):
        pressure = density * (287.05287 * temperature) / 100.0
        assert 870 <= pressure <= 1085
        recovered = (pressure * 100.0) / (287.05287 * temperature)
        assert recovered == density
        print(f"dry field: {temperature:.2f} K, {pressure:.10f} hPa, rho={recovered:.17g}, charge ratio={recovered / 1.225:g}", flush=True)
        cases.extend((f"T{temperature:.2f}", density, temperature, 0.0))
    payload = model + " 2 " + " ".join(map(str, cases)) + "\n"
    with tempfile.TemporaryDirectory() as stage:
        binary = Path(stage) / "electric"
        subprocess.run(["g++", "-std=c++17", "-O2", "-ffp-contract=off", "-fno-fast-math", "-I",
                        str(repo / "research/native-kernel/src"), str(probes / "electric_probe.cpp"), "-o", str(binary)], check=True)
        output = subprocess.run([str(binary)], input=payload, text=True, capture_output=True, check=True).stdout
    rows = [dict(pair.split("=", 1) for pair in line.split()[1:]) for line in output.splitlines() if line.startswith("T")]
    assert len(rows) == 2 and rows[0]["setup_rpm"] == rows[1]["setup_rpm"]
    assert float(rows[0]["setup_net_torque_Nm"]) < 0 < float(rows[1]["setup_net_torque_Nm"])
    print(output, end="")


def fpv(repo):
    model = json.loads((repo / "app/data/multirotors/openrc-fpv5-x1.json").read_text())
    batt, motor, rotor = model["battery"], model["powertrain"], model["rotor_law"]
    voc = batt["ocv_points"]["value"][-1][1]
    aux, rpack = batt["auxiliary_current"]["value"], batt["resistance"]["value"]
    kv, rm, i0 = (motor[key]["value"] for key in ("kv", "resistance", "no_load_current"))
    kt, kq = (rotor[key]["value"] for key in ("thrust_coefficient", "torque_coefficient"))
    mass = model["provenance"]["derived_diagnostics"]["mass_kg"]
    omega = math.sqrt(mass * 9.80665 / (4 * kt))
    d = motor["idle_command"]["value"]
    motor_current = -aux / (4 * d)
    bridge = (omega / kv + rm * motor_current) / d
    print(f"auxiliary port test: pack-side {voc*aux:.8f} W, link-side {bridge*aux:.8f} W, difference {(bridge-voc)*aux:.8f} W")
    for d in (0.2, 1.0):
        forces = []
        for rp in (0.0, rpack):
            req = rm + 4 * rp * d * d
            a, b, c = req * kv * kq, 1 / kv, req * i0 - d * (voc - rp * aux)
            speed = -2 * c / (b + math.sqrt(b*b - 4*a*c))
            current = i0 + kv * kq * speed**2
            bus = voc - rp * (aux + 4 * d * current)
            assert abs(current * rm - d * bus + speed / kv) < 1e-12
            forces.append(kt * speed**2)
        print(f"equal duties {d:g}: loaded bus {bus:.8f} V; OCV thrust {forces[0]:.8f} N/rotor; loaded thrust {forces[1]:.8f} N/rotor")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("repo", type=Path)
    parser.add_argument("--probes", type=Path, help="Directory holding the electric audit probe pair")
    args = parser.parse_args()
    root = args.repo.resolve()
    location = args.probes or root / "research/native-physics-audit-2026-11-28/probes"
    launch(root, location)
    fpv(root)
