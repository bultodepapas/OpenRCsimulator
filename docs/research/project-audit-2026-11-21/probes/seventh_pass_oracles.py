#!/usr/bin/env python3
"""Independent scalar/vector checks of R7's observed Godot rows.

No Godot code is imported. These are equation/ledger oracles, not a replacement
simulation or empirical validation. The physical rotor interpretation is limited
to the tested still-air, positive-spin, no-contact frames.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path


def rows(evidence, label, prefix):
    log = next(c["engine_log"] for c in evidence["checks"] if c["label"] == label)
    return [json.loads(line[len(prefix):]) for line in log.splitlines() if line.startswith(prefix)]


def close(a, b, tolerance=1e-8):
    assert math.isfinite(a) and math.isfinite(b) and abs(a-b) <= tolerance, (a, b, tolerance)


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def cross(a, b):
    return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]


def inertia_mul(j, a):
    return [j[0]*a[0]+j[3]*a[1]+j[4]*a[2],
            j[3]*a[0]+j[1]*a[1]+j[5]*a[2],
            j[4]*a[0]+j[5]*a[1]+j[2]*a[2]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text())
    raw = json.loads((args.project/"data/multirotors/openrc-fpv5-x1.json").read_text())
    custom = json.loads((args.project/"r7_custom_motor.json").read_text())
    expected = json.loads(json.dumps(raw))
    expected["powertrain"]["resistance"].update(value=.001, kind="estimated",
        source="estimated: manufactured R7 motor stiffness diagnostic; not identified hardware")
    assert custom == expected, "only the stated custom physical value/provenance may change"
    results = []

    # A polynomial proof, independent of the implementation's prepared constants.
    for row in rows(evidence, "rates", "R7_RATES "):
        r = row["result"]
        e = {"zero": 0., "hundred": 1., "bad_positive": 2., "bad_negative": 2.}[row["case_name"]]
        x = r["pilot"][0]
        expected_rate = 200*x*((1-e)+e*abs(x)**3)
        close(r["direct_dps"], expected_rate)
        close(r["setpoint_dps"], expected_rate, 1e-6)
        assert r["ok"] and r["import_ok"] and r["validation_ok"] and r["tick"] == 482
        assert r["body_rate_dps"]*expected_rate > 0
        results.append({"oracle": "rates polynomial", "case": row["case_name"], "rate_dps": expected_rate})
    close(200*(2-1), 200)
    reversal_boundary = (0.5)**(1/3)
    assert 0.5 < reversal_boundary < 1

    # Resultant target inclination comes from an independent Euler rotation identity;
    # observed inclination comes from the printed accepted quaternion.
    for row in rows(evidence, "angle", "R7_ANGLE "):
        r = row["result"]
        limit = math.radians(r["max_config"])
        roll, pitch = r["requested_axes"]
        target = math.degrees(math.acos(math.cos(roll*limit)*math.cos(pitch*limit)))
        q = r["final_quaternion"]
        close(sum(v*v for v in q), 1, 1e-10)
        observed = math.degrees(math.acos(max(-1., min(1., 1-2*(q[1]**2+q[2]**2)))))
        close(r["final_tilt"], observed)
        assert r["ok"] and r["tick"] == 602
        if row["case_name"] == "diagonal":
            assert target > r["max_config"]+15 and observed > 70
        elif row["case_name"] == "solo":
            close(target, 55)
        else:
            assert target < 55
        results.append({"oracle": "target and observed tilt", "case": row["case_name"],
                        "target_deg": target, "observed_deg": observed})

    admissions = rows(evidence, "motor", "R7_MOTOR_ADMISSION ")
    assert len(admissions) == 8
    for name in ("stock", "custom"):
        group = {r["forced_plant_pieces"]:r for r in admissions if r["name"] == name}
        assert len({r["before_frame_hex_sha256"] for r in group.values()}) == 1
        assert all(r["candidate_commands"] == group[0]["candidate_commands"] for r in group.values())
        for n, r in group.items():
            assert r["loader_ok"] and not r["loader_errors"] and r["prepared"]
            if name == "custom" and n == 0:
                assert not r["accepted_arm_tick"] and r["tick"] == 1 and r["rollback_preserved"]
                assert "RK joint stage evaluation is nonfinite or malformed" in r["fault"]
            else:
                assert r["accepted_arm_tick"] and r["tick"] == 2 and r["controller_samples"] == 2 and not r["fault"]
        d8 = max(abs(a-b) for a,b in zip(group[4]["omega"],group[8]["omega"]))
        d16 = max(abs(a-b) for a,b in zip(group[8]["omega"],group[16]["omega"]))
        assert d16 < d8 and d16 < .05
        results.append({"oracle": "same-sample plant refinement", "case": name,
                        "max_delta_4_8_rad_s": d8, "max_delta_8_16_rad_s": d16})
    for r in rows(evidence, "motor", "R7_MOTOR_MODE "):
        lam = -(1/(r["motor_resistance_ohm"]*r["kv_rad_s_per_v"]**2)
                +2*r["kq_n_m_s2"]*r["omega_rad_s"])/r["rotor_inertia_kg_m2"]
        close(lam, r["measured_lambda_s_inv"], 1e-5)
        assert all(i>0 for i in r["motor_current_a"]), "motoring branch required for this diagnostic"
        z=lam/240
        gain=1+z+z*z/2+z**3/6+z**4/24
        assert (gain>1) if r["name"]=="custom" else (0<gain<1)
        results.append({"oracle":"separate local motor mode", "case":r["name"],"h_lambda":z,
                        "rk4_gain":gain,"exact_linear_gain":math.exp(z)})

    mass = raw["provenance"]["derived_diagnostics"]["mass_kg"]
    inertia = raw["provenance"]["derived_diagnostics"]["inertia_kg_m2"]
    kt = raw["rotor_law"]["thrust_coefficient"]["value"]
    kq = raw["rotor_law"]["torque_coefficient"]["value"]
    kh = raw["rotor_law"]["rotor_drag"]["value"]
    motor_kt = 1/raw["powertrain"]["kv"]["value"]
    no_load = raw["powertrain"]["no_load_current"]["value"]
    areas = raw["airframe"]["drag_areas"]["value"]

    def mechanical_rate(r):
        b,c,bd,cd = (r[k] for k in ("body","continuous","body_derivative","continuous_derivative"))
        v,w,vd,alpha = b[3:6],b[10:13],bd[3:6],bd[10:13]
        value=mass*dot(v,vd)+dot(w,inertia_mul(inertia,alpha))
        for i,rotor in enumerate(raw["rotors"]):
            j,s = rotor["inertia"]["value"],rotor["spin"]
            value += j*c[i]*cd[i]-j*s*(alpha[2]*c[i]+w[2]*cd[i])
        return value

    for r in rows(evidence,"rotor","R7_RATE "):
        q = kq*r["relative_shaft_rad_s"]**2
        expected_port = -q*r["air_relative_signed_rad_s"]
        close(r["thrust_n"],kt*r["relative_shaft_rad_s"]**2,1e-12)
        close(r["rotor_aero_port_w"],expected_port,2e-10)
        close(mechanical_rate(r),r["body_drag_w"]+r["shaft_friction_w"]+expected_port,2e-10)
        assert r["accepted_tick"]
        results.append({"oracle":"constructed near-stop rotor port", "yaw_rad_s":r["yaw_rad_s"],
                        "port_w":expected_port,"whole_mechanical_rate_w":mechanical_rate(r)})
    climb=rows(evidence,"rotor","R7_CLIMB ")[0]
    assert climb["accepted_ticks"]==1602 and not climb["fault"] and not climb["crash"]
    for key in ("first_violation","best_punch","best"):
        r=climb[key]; l=r["ledger"]
        b,c=l["body"],l["continuous"]
        v,w=b[3:6],b[10:13]
        assert all(x>=0 for x in c[:4]) and all(x==1 for x in c[8:12])
        assert l["wind_ned_mps"]==[0.,0.,0.]
        thrust=torque=inplane=motor=friction=0.
        for i,rotor in enumerate(raw["rotors"]):
            hub=rotor["hub_frd"]["value"]
            vh=[a+d for a,d in zip(v,cross(w,hub))]
            speed=c[i]
            thrust += -kt*speed**2*vh[2]
            torque += kq*speed**2*(rotor["spin"]*w[2]-speed)
            inplane -= kh*speed*(vh[0]**2+vh[1]**2)
            motor += motor_kt*l["motor_current_a"][i]*speed
            friction -= motor_kt*no_load*min(1.,speed/30)*speed
        body_drag=-.5*l["rho_kg_m3"]*sum(a*abs(x)**3 for a,x in zip(areas,v))
        port=thrust+torque+inplane
        expected_power=port+body_drag+motor+friction
        close(mechanical_rate(l),expected_power,1e-7)
        for actual,expected in ((l["rotor_air_power_w"],port),(l["rotor_thrust_work_w"],thrust),
                                (l["rotor_torque_work_w"],torque),(l["rotor_inplane_work_w"],inplane),
                                (l["body_drag_w"],body_drag),(l["motor_power_w"],motor),(l["friction_w"],friction)):
            close(actual,expected,1e-7)
        assert port>0
        if key=="best": assert expected_power<0, "this witness is not whole-craft energy growth"
        results.append({"oracle":"stock airborne full power ledger", "case":key,"tick":r["tick"],
                        "rotor_air_power_w":port,"whole_gravity_free_mechanical_rate_w":expected_power})
    print(json.dumps({"ok":True,"scalar_oracle_cases":len(results),"results":results},indent=2,allow_nan=False))


if __name__ == "__main__":
    main()
