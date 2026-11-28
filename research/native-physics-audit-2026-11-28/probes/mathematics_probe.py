#!/usr/bin/env python3
"""Run the physics audit component controls; pass --repo /path/to/OpenRCsimulator.

The C++ experiment executes the repository's headers. The airship has a GDScript
stage, so those two experiments independently transcribe its scalar binary64 laws.
No Godot process, package, graphics driver or external Python package is required.
"""
import argparse
import json
import math
import pathlib
import subprocess
import tempfile
from decimal import Decimal, localcontext


def stock_data(repo, relpath):
    return json.loads((repo / relpath).read_text())


def q(data, key):
    return data[key]["value"]


def run_headers(repo):
    definition = stock_data(repo, "app/data/aircraft/jensen_ugly_stik_60.json")["propulsion"]
    engine, prop = definition["engine"], definition["propeller"]
    idle, target, lag = [q(engine, k) for k in ("idle_rpm", "max_rpm_static", "lag_time_constant")]
    diameter = q(prop, "diameter")
    ct, cp = [q(prop, key)[0][1] for key in ("ct_table", "cp_table")]
    assert not ({"shaft", "glow_installation"} & engine.keys())
    flags = ["-std=c++17", "-O2", "-fno-fast-math", "-ffp-contract=off"]
    source = pathlib.Path(__file__).with_suffix(".cpp")
    with tempfile.TemporaryDirectory() as tmp:
        exe = pathlib.Path(tmp) / "math_probe"
        subprocess.run(["g++", *flags, "-I", repo/"research/native-kernel/src", source, "-o", exe], check=True)
        args = [str(v) for v in (idle, target, lag, diameter, ct, cp)]
        result = subprocess.check_output([exe, *args], text=True)
    result_fields = {
        "ballistic": ["position_error_m", "world_velocity_error_m_s", "attitude_error_rad", "unit_norm_error"],
        "mass": ["momentum_error_kg_m_s", "angular_momentum_error_kg_m2_s", "final_fuel_kg"],
        "mass_omit_datum": ["momentum_error_kg_m_s", "angular_momentum_error_kg_m2_s", "final_fuel_kg"],
        "event": ["event_time_s", "analytic_time_error_s"],
        "contact": ["rebound_m_s_at_1e6", "energy_ratio_at_1e6", "energy_ratio_at_1e5", "energy_ratio_at_400",
                    "energy_ratio_1e6_with_16_substeps", "max_16_substep_energy_ratio_error_over_32_phases"],
        "prop": ["end_held_impulse_Ns", "stage_time_impulse_Ns", "first_interval_held_Ns", "final_rpm"],
        "fixed_hold": ["impulse_Ns"],
    }
    rows = {case: {} for case in result_fields}
    for line in result.splitlines():
        case, rate, *values = line.split()
        rows[case][rate] = dict(zip(result_fields[case], map(float, values), strict=True))

    def exact_impulse(duration):
        a, b = target, idle-target
        scale = 1.225 * ct * diameter**4 / 3600
        return scale * (a*a*duration-2*a*b*lag*math.expm1(-duration/lag)
                        - b*b*lag/2*math.expm1(-2*duration/lag))

    oracle = exact_impulse(0.25)
    for rate, row in rows["prop"].items():
        first = exact_impulse(1/int(rate))
        row["first_interval_error_percent"] = 100*(row["first_interval_held_Ns"]/first-1)
        row["held_error_percent"] = 100*(row["end_held_impulse_Ns"]/oracle-1)
        row["stage_time_error_Ns"] = row["stage_time_impulse_Ns"]-oracle
    rows["propulsion_oracle"] = {"impulse_Ns_at_0.25_s": oracle, "rpm_idle_full": [idle, target],
                                 "tau_s": lag, "rho_kg_m3": 1.225, "diameter_m": diameter, "Ct_static": ct}
    return {"compiler": subprocess.check_output(["g++", "--version"], text=True).splitlines()[0],
            "flags": flags, "source": source.name, "results": rows}


def airship_electrical(doc):
    """Symmetry reduces the live four-rotor RHS to n,n,share*n,0. All three axial time constants agree."""
    battery, motors = doc["battery"], doc["rotors"]
    side = q(doc["mixer"], "stern_axial_share")
    inputs = [1, 1, side, 0]
    assert q(motors[0], "response_time") == q(motors[1], "response_time") == q(motors[2], "response_time")
    tau = q(motors[0], "response_time")
    power_full = sum(abs(v)**3 * q(m, "max_shaft_power")/q(m, "motor_efficiency") for v, m in zip(inputs, motors))
    thrust_full = sum(v*abs(v)*q(m, "static_thrust_max") for v, m in zip(inputs, motors))
    cells, resistance = q(battery, "cells"), q(battery, "internal_resistance")
    volts_ref, band = q(battery, "reference_voltage"), q(battery, "cutoff_band")
    capacity = 3600*q(battery, "capacity")
    table = q(battery, "cell_ocv")
    soc_start, v_empty, v_start = table[1][0], table[0][1], table[1][1]
    assert table[0][0] == 0 and soc_start == .05
    ocv_slope = (v_start-v_empty)/soc_start

    def point(n, soc, v_cutoff):
        # Simulated SOC never exceeds the first OCV segment in this experiment.
        ocv = cells*(v_empty+ocv_slope*max(0., soc))
        power = power_full*abs(n)**3
        disc = ocv*ocv-4*power*resistance
        volts = (ocv+math.sqrt(disc))/2 if disc>0 else ocv/2
        amps = power/volts if disc>0 else (ocv-volts)/resistance
        supply = volts/volts_ref*max(0., min(1., (volts-cells*v_cutoff)/band))
        return amps, supply, volts, power

    def fixed_point(v_cutoff):
        if point(0., 0., v_cutoff)[1] == 0.:
            _, _, volts, _ = point(0., 0., v_cutoff)
            return {"normalized_axial_speed": 0., "current_A": 0., "bus_V": volts, "bus_W": 0.,
                    "static_thrust_N": 0., "speed_fixed_point_residual": 0.}
        lo, hi = 0., 1.
        for _ in range(85):
            mid = (lo+hi)/2
            _, command, _, _ = point(mid, 0., v_cutoff)
            if command>mid:
                lo=mid
            else:
                hi=mid
        n=(lo+hi)/2
        amps, demand, volts, power=point(n,0.,v_cutoff)
        return {"normalized_axial_speed": n, "current_A": amps, "bus_V": volts, "bus_W": power,
                "static_thrust_N": thrust_full*n*n, "speed_fixed_point_residual": n-demand}

    def finite_charge(rate):
        dt=1/rate
        n, soc, total_charge, crossing = 0., soc_start, 0., None
        extra_seconds = 10
        def rhs(n, s):
            amps, demand, _, _=point(n,s,3.2)
            return (demand-n)/tau, (-amps/capacity if s>0 else 0.), amps
        for tick in range(1200*rate):
            f=rhs(n,soc)
            g=rhs(n+.5*dt*f[0],soc+.5*dt*f[1])
            h=rhs(n+.5*dt*g[0],soc+.5*dt*g[1])
            i=rhs(n+dt*h[0],soc+dt*h[1])
            change=tuple(dt/6*(f[j]+2*g[j]+2*h[j]+i[j]) for j in range(3))
            n+=change[0]; soc+=change[1]; total_charge+=change[2]
            if crossing is None and soc<=0:
                crossing=(tick+1,soc,total_charge)
            if crossing is not None and tick+1-crossing[0]==extra_seconds*rate:
                amps, _, volts, power=point(n,soc,3.2)
                return {"first_nonpositive_endpoint_s": crossing[0]/rate, "endpoint_SOC": soc,
                        "remaining_charge_C": soc*capacity, "extra_seconds": extra_seconds,
                        "extra_charge_drawn_C": total_charge-crossing[2], "tail_bus_W":power,
                        "tail_current_A":amps, "tail_bus_V":volts, "tail_static_thrust_N":thrust_full*n*n}
        raise AssertionError("depletion benchmark did not finish")

    return {"command": "0 roll/pitch/yaw, 1 throttle; held 240-Hz input tape",
            "case": "stock airship, cutoff 3.2 V/cell, initially 5% charged, stock 2.2 Ah",
            "empty_stock_cutoff":fixed_point(q(battery,"cutoff_cell_voltage")),
            "empty_admitted_cutoff":fixed_point(3.2),
            "finite_charge":{str(hz):finite_charge(hz) for hz in (120,240,480)}}


def spheroid_coefficients(a,b):
    # Binary64 transcription in GDScript expression order.
    ecc=math.sqrt(1.-(b*b)/(a*a)); log_term=math.log((1+ecc)/(1-ecc))
    e2=ecc*ecc;e3=e2*ecc
    alpha=2.*(1.-e2)/e3*(.5*log_term-ecc)
    beta=1./e2-(1.-e2)/(2.*e3)*log_term
    return alpha/(2.-alpha),beta/(2.-beta),e2*e2*(beta-alpha)/((2.-e2)*(2.*e2-(2.-e2)*(beta-alpha)))


def spheroid_oracle(a,b):
    # 80-place positive power series for atanh(e)-e, independent of binary64 log/cancellation.
    with localcontext() as ctx:
        ctx.prec=80
        ratio=Decimal.from_float(b)/Decimal.from_float(a)
        e2=1-ratio*ratio; power=Decimal(1); acc=Decimal(0)
        for k in range(15000):
            inc=power/(2*k+3);acc+=inc
            if abs(inc)<Decimal("1e-74"):break
            power*=e2
        else: raise AssertionError("spheroid oracle did not converge")
        alpha=2*(1-e2)*acc;beta=1-alpha/2;delta=beta-alpha
        kr=e2*e2*delta/((2-e2)*(2*e2-(2-e2)*delta))
        return float(alpha/(2-alpha)),float(beta/(2-beta)),float(kr)


def spheroids(doc):
    cases={"stock":(q(doc["envelope"],"length"),q(doc["envelope"],"volume"))}
    for delta in (1e-4,1e-8,1e-9,1e-10,1e-11,1e-12):
        length,diameter=2.,2*(1-delta)
        # Exactly the repository's analytical fixture generation and its derived equivalent radius.
        cases[f"near_sphere_{delta:g}"]=(length,math.pi*length*diameter*diameter/6.)
    table={}
    for name,(length,volume) in cases.items():
        a=0.5*length;b=math.sqrt(3*volume/(4*math.pi*a))
        current=spheroid_coefficients(a,b);ref=spheroid_oracle(a,b)
        table[name]={"a":a,"b":b,"current_k1_k2_krot":list(current),"oracle_k1_k2_krot":list(ref)}
    return table


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo",type=pathlib.Path,default=pathlib.Path.cwd())
    repo=parser.parse_args().repo.resolve()
    if not (repo/"research/native-kernel/src/nk_tick.hpp").exists():
        parser.error("--repo must identify the OpenRCsimulator working tree")
    airship=stock_data(repo,"app/data/airships/rc-blimp-5m.json")
    packet={"source_commit":subprocess.check_output(["git","-C",repo,"rev-parse","HEAD"],text=True).strip(),
            "native_headers":run_headers(repo),"airship_charge_script_law":airship_electrical(airship),
            "airship_shape_script_law":spheroids(airship)}
    print(json.dumps(packet,indent=2,allow_nan=False))


if __name__=="__main__":
    main()
