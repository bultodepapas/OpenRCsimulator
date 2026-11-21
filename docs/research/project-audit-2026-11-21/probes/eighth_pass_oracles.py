#!/usr/bin/env python3
"""Independently reconstruct R8 quantities from retained raw engine observations.

Only the Python standard library is used. Observation checks establish the
stated reference-code behavior, not physical calibration or a production fix.
"""
import argparse
import hashlib
import json
from pathlib import Path

from eighth_pass_oracle_skid import verify as verify_skid
from eighth_pass_oracle_arming import verify as verify_arming
from eighth_pass_oracle_rotor import verify as verify_rotor


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text())
    stock_bytes = (args.project/"data/aircraft/xcell_60_research.json").read_bytes()
    stock = json.loads(stock_bytes)
    stock_hash = hashlib.sha256(stock_bytes).hexdigest()
    assert stock_hash==evidence["stock_data_sha256"]
    field = json.loads((args.project/"data/fields/default.json").read_text())
    pad = field["rotorcraft_pad"]
    envelope = next(x for x in pad["aircraft_envelopes"] if x["aircraft_id"]==stock["id"])
    surface = next(x for x in field["surfaces"] if x["id"]==pad["surface_id"])
    assert envelope["radius"]["value"]==1.25
    assert surface["length_east_west"]["value"]==surface["width_north_south"]["value"]==6.0
    assert surface["center_north"]["value"]==pad["north"]["value"]
    assert surface["center_east"]["value"]==pad["east"]["value"]
    assert surface["type"]==pad["material"]=="rotorpad"
    friction = json.loads((args.project/"data/ground/surface_friction.json").read_text())
    effective_mu = friction["surfaces"]["rotorpad"]["friction_factor"]["value"]*stock["skids"]["friction"]["value"]
    assert abs(effective_mu-0.35)<1e-15  # Matches the probe's traction normalization.
    logs = {item["label"]:item["engine_log"] for item in evidence["checks"]}
    result = {"format":"openrc-a36-r8-independent-oracles v1","results":{
        "skid":verify_skid(logs["skid-admission"],stock),
        "arming":verify_arming(logs["arming"],stock),
        "rotor":verify_rotor(logs["rotor-consistency"],stock)}}
    assert result["results"]["arming"]["logged_aircraft_sha256"]==stock_hash
    assert result["results"]["rotor"]["results"]["constructed_session"]["aircraft_sha256"]==stock_hash
    for line in logs["skid-admission"].splitlines():
        if line.startswith("R8_SKID "):
            row = json.loads(line.split(" ",1)[1])
            actual = (args.project/row["path"].removeprefix("res://")).read_bytes()
            assert hashlib.sha256(actual).hexdigest()==row["aircraft_sha256"]
    result["ok"] = True
    print(json.dumps(result, indent=2, allow_nan=False))


if __name__=="__main__": main()
