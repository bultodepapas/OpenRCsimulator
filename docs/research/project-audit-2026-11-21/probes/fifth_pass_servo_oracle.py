#!/usr/bin/env python3
"""Independent inverse-mixer bound using the checked session probe log."""
import argparse
import json
import math
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("log", type=Path)
parser.add_argument("aircraft", type=Path)
args = parser.parse_args()
line = next(s for s in args.log.read_text().splitlines() if s.startswith("SESSION "))
observed = json.loads(line[len("SESSION "):])
config = json.loads(args.aircraft.read_text())
link = config["electronics"]["linkage"]
gc = link["collective_rad_per_unit"]["value"]
gl = link["longitudinal_rad_per_unit"]["value"]
gr = link["lateral_rad_per_unit"]["value"]
theta, forward, right = observed["angles"]
c, longitudinal, lateral = theta / gc, forward / gl, right / gr
implied = [c + longitudinal,
           c - longitudinal / 2 + math.sqrt(3) * lateral / 2,
           c - longitudinal / 2 - math.sqrt(3) * lateral / 2]
assert observed["accepted"] and observed["tick_after"] == 1 and not observed["fault"]
assert observed["servo"] == [1.0, 1.0, 1.0]
assert math.isclose(c, 1.0, abs_tol=1e-14)
assert observed["servo_linkage_angles"] == [gc, 0.0, 0.0]
assert math.isclose(forward, observed["trim"]["cyclic_forward_bias_rad"], abs_tol=1e-14)
assert math.isclose(right, observed["trim"]["cyclic_right_bias_rad"], abs_tol=1e-14)
assert abs(forward) > 1e-5 and abs(right) > 1e-5
assert max(implied) > 1.0
assert abs(sum(implied) / 3 - 1.0) < 1e-14
flap_delta = [a-b for a, b in zip(observed["flap_rate_actual"], observed["flap_rate_zero_bias"])]
assert len(flap_delta) == 2 and all(abs(v) > 1e-3 for v in flap_delta)
assert all(abs(v) < 1e-10 for v in observed["flap_rate_actual"])
print("control axes", c, longitudinal, lateral)
print("implied servo travel", *[f"{v:.12f}" for v in implied])
print("excess over upper limit", f"{max(implied)-1.0:.12f}")
print("flap rate delta actual minus zero cyclic bias", *[f"{v:.12f}" for v in flap_delta])
print("ORACLE_COMPLETE")
