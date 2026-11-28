"""Reproduce the electric audit from a checkout. Writes only a temporary executable."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile


def value(obj, key):
    return obj[key]["value"]


def read_json(path):
    return json.loads(path.read_bytes())


def pinned_json(path, descriptor):
    raw = path.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == descriptor["sha256"], path
    return json.loads(raw)


def flatten(rows):
    return [x for row in rows for x in row]


def weather_density(temp_c, elevation_m, humidity):
    temperature = 273.15 + temp_c
    height = 6356766.0 * elevation_m / (6356766.0 + elevation_m)
    pressure = 101325.0 * (1.0 - 0.0065 * height / 288.15) ** (9.80665 / (287.05287 * 0.0065))
    es = 611.21 * math.exp((18.678 - temp_c / 234.5) * temp_c / (257.14 + temp_c))
    vapor = humidity * es
    return (pressure - vapor) / (287.05287 * temperature) + vapor / (461.523329 * temperature)


def native_cases(repo):
    data = repo / "app/data"
    prop = read_json(data / "aircraft/battery/moonrunner_x99_6s_pack.json")["propulsion"]
    battery, motor, fan = prop["battery"], prop["motor"], prop["propeller"]
    pack_ref = battery["pack"]
    pack = pinned_json(data / "batteries/packs" / (pack_ref["id"] + ".json"), pack_ref)
    cell_ref = pack["cell_template"]
    cell = pinned_json(data / "batteries/cells" / (cell_ref["id"] + ".json"), cell_ref)
    capacity = value(pack, "rated_capacity_ah")
    resistance_scale = value(cell, "reference_capacity_ah") / capacity * value(pack, "resistance_scale")
    weak = battery["weak_cell"]
    heat = pack["heat_transfer"]
    fields = [value(motor, "kv_rpm_per_volt"), value(motor, "resistance_ohm"), value(motor, "no_load_current_a"),
              value(fan, "diameter"), value(fan, "rotating_inertia")]

    def vector(values):
        fields.extend((len(values), *values))

    vector(flatten(value(fan, "ct_table")))
    vector(flatten(value(fan, "cp_table")))
    fields.extend([pack["series"], len(cell["rc_branches"]), 3600 * capacity, value(battery, "initial_soc"),
                   value(weak, "capacity_factor"), value(weak, "resistance_factor"), value(weak, "soc_offset"),
                   value(pack, "interconnect_resistance_ohm"), value(battery, "auxiliary_current_a"),
                   value(battery, "cooling_airflow_fraction"), value(pack, "mass_kg") * value(cell, "specific_heat_j_per_kg_k"),
                   value(heat, "still_air_w_per_k"), value(heat, "forced_w_per_k_per_sqrt_mps"),
                   value(prop["esc"]["low_voltage_cutoff"], "voltage_filter_s")])
    vector(value(cell, "soc_knots"))
    vector(value(cell, "temperature_knots_k"))
    vector(flatten(value(cell, "ocv_v")))
    vector([x * resistance_scale for x in flatten(value(cell, "r0_ohm"))])
    for branch in cell["rc_branches"]:
        vector([x * resistance_scale for x in flatten(value(branch, "r_ohm"))])
        vector(flatten(value(branch, "tau_s")))
    # Each case holds density fixed across its legacy and context-matched solve.
    cases = [("calm", 1.225, 288.15, 0.), ("steady", 1.225, 288.15, 3.),
             ("cool-dense", weather_density(5., 0., 0.), 278.15, 0.),
             ("hot-high", weather_density(35., 1500., .5), 308.15, 0.)]
    fields.append(len(cases))
    for case in cases:
        fields.extend(case)
    return " ".join(map(str, fields)) + "\n"


def fpv_probes(repo):
    quad = read_json(repo / "app/data/multirotors/openrc-fpv5-x1.json")
    battery, motor = quad["battery"], quad["powertrain"]
    assert motor["braking"] == "damped"
    aux = value(battery, "auxiliary_current")
    rp = value(battery, "resistance")
    capacity = value(battery, "capacity") * 3600
    d = value(motor, "idle_command")
    r = value(motor, "resistance")
    kv = value(motor, "kv")
    stock = quad["provenance"]["derived_diagnostics"]
    omega = math.sqrt(9.80665 * stock["mass_kg"] / (4 * value(quad["rotor_law"], "thrust_coefficient")))
    emf = omega / kv
    for headroom in [0., .01]:
        # Same four-shaft prescribed operating point and OCV interpolation as the stock law.
        soc = 1 - headroom / capacity
        (z0, v0), (z1, v1) = value(battery, "ocv_points")[-2:]
        voc = v0 + (v1 - v0) * ((soc - z0) / (z1 - z0))
        sum_emf = 4 * d * emf / r
        sum_duty = 4 * d * d / r
        v_free = (voc - rp * aux + rp * sum_emf) / (1 + rp * sum_duty)
        i_free = aux + 4 * d * (d * v_free - emf) / r
        limit = headroom / .2
        assert i_free < -limit
        v_clamped = (sum_emf - aux - limit) / sum_duty
        i_motor = (d * v_clamped - emf) / r
        i_pack = aux + 4 * d * i_motor
        assert abs(i_pack + limit) < 1e-12
        active_loss = (voc - v_clamped) * i_pack
        chem_balance = voc * i_pack - v_clamped * i_pack - active_loss
        bridge_balance = v_clamped * i_pack - (v_clamped * aux + 4 * (r * i_motor**2 + emf * i_motor))
        assert abs(chem_balance) < 1e-10 and abs(bridge_balance) < 1e-10
        physical_terminal = voc - rp * i_pack
        print(f"FPV headroom_C={headroom:g} omega={omega:.8f} duty={d:g} raw_V={v_free:.8f} "
              f"raw_A={i_free:.8f} limited_bus_V={v_clamped:.8f} pack_A={i_pack:.8f} "
              f"motor_A={i_motor:.8f} terminal_Thevenin_V={physical_terminal:.8f} "
              f"OSD_cell_V={v_clamped/value(battery, 'cells'):.8f} assigned_loss_W={active_loss:.8f} "
              f"ohmic_loss_W={rp*i_pack*i_pack:.8f} ledger_residual_W={chem_balance:.3g} bridge_residual_W={bridge_balance:.3g}", flush=True)
    rows = read_json(repo / "research/drone-racing/openrc-fpv5-x1/sources.json")["motor_rows"]["rows"]
    row = rows[0]
    v, current = row["voltage_v"], row["current_a"]
    e = row["rpm"] / 2150
    old = (e + r * current) / v
    new = (e + math.sqrt(e*e + 4*v*r*current)) / (2*v)
    assert abs(old - stock["fit_row50_implied_duty"]) < 1e-12
    assert abs(new * (new*v - e) / r - current) < 1e-11
    print(f"F50 source_W={v*current:.8f} old_duty={old:.9f} old_source_A={old*current:.9f} "
          f"old_source_W={v*old*current:.7f} corrected_duty={new:.9f} corrected_motor_A={current/new:.8f} "
          f"effective_R_ohm={r:.9f}", flush=True)


def main():
    args = argparse.ArgumentParser()
    args.add_argument("repo", type=Path, help="OpenRCsimulator checkout")
    repo = args.parse_args().repo.resolve()
    fpv_probes(repo)
    with tempfile.TemporaryDirectory(prefix="openrc-electric-audit-") as scratch:
        exe = Path(scratch) / "probe"
        subprocess.run(["g++", "-std=c++17", "-O2", "-ffp-contract=off", "-fno-fast-math",
                        "-I", str(repo / "research/native-kernel/src"),
                        str(Path(__file__).with_name("electric_probe.cpp")), "-o", str(exe)], check=True)
        subprocess.run([str(exe)], input=native_cases(repo), text=True, check=True)


if __name__ == "__main__":
    main()
