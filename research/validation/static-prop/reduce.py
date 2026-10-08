#!/usr/bin/env python3
"""VAL-7a: reduce matched static propeller readings; no simulator inputs are changed."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys


UNITS = {"thrust": "N", "rpm": "rpm", "diameter": "m", "density": "kg/m^3", "torque": "N*m"}
KINDS = ("measured", "estimated", "derived", "manual", "synthetic")
LIMITATIONS = [
    "Positive-thrust, positive-RPM static operation only; ambient axial inflow is assumed negligible, not verified.",
    "Readings must describe the same stabilized operating point and installed propeller configuration.",
    "Inputs are net axial thrust and, when present, positive motoring shaft torque into the propeller, with rig tare/friction corrections already applied.",
    "Reported uncertainties are first-order standard uncertainties (k=1), assuming independent input errors within each run.",
    "Shared instrument biases, correlations between distinct inputs/runs and unquantified rig/flow errors are not modeled.",
    "Ideal disc power is a theoretical static lower bound, not measured shaft power or an engine-power estimate.",
    "Static figure of merit is ideal disc power / shaft power, not propulsive efficiency; useful T*V power is zero at V=0.",
    "No torque measurement means no shaft-power, Cp or figure-of-merit inference from thrust and RPM alone.",
    "Synthetic fixtures verify reduction algebra; they do not validate the rig, aircraft, engine or propeller model.",
]


def fields(obj, required, where):
    if not isinstance(obj, dict) or set(obj) != set(required):
        raise ValueError(f"{where}: expected exactly {sorted(required)}")


def text(value, where):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{where}: expected nonempty text")


def number(value, where, positive=True):
    if type(value) not in (int, float) or not math.isfinite(value):
        raise ValueError(f"{where}: expected finite number (numeric booleans/strings refused)")
    if (positive and value <= 0) or (not positive and value < 0):
        raise ValueError(f"{where}: expected {'positive' if positive else 'nonnegative'} number")
    return float(value)


def unique_object(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise ValueError(f"duplicate JSON key: {key}")
        out[key] = value
    return out


def load(raw):
    def bad_constant(value):
        raise ValueError(f"nonfinite JSON constant: {value}")
    return json.loads(raw, object_pairs_hook=unique_object, parse_constant=bad_constant)


def power_law(readings, factor, powers, unit):
    """Direct input sensitivities avoid treating derived quantities as independent."""
    value = factor
    for name, exponent in powers.items():
        value *= readings[name]["value"] ** exponent
    if not math.isfinite(value) or value <= 0:
        raise ValueError("derived value outside finite positive range")
    contributions = {
        name: exponent * value / readings[name]["value"] * readings[name]["u"]
        for name, exponent in powers.items()
    }
    uncertainty = math.hypot(*contributions.values())
    if not math.isfinite(uncertainty):
        raise ValueError("derived uncertainty outside finite range")
    return {"value": value, "unit": unit, "u": uncertainty, "kind": "derived",
            "standard_uncertainty_contributions": contributions}


def reduce_run(run, evidence):
    fields(run, ("id", "notes", "thrust", "rpm", "diameter", "density", "torque"), "run")
    text(run["id"], "run.id")
    text(run["notes"], "run.notes")
    for name, unit in UNITS.items():
        quantity = run[name]
        if name == "torque" and quantity is None:
            continue
        fields(quantity, ("value", "unit", "u", "kind", "source"), name)
        number(quantity["value"], f"{name}.value")
        number(quantity["u"], f"{name}.u", positive=False)
        if quantity["unit"] != unit:
            raise ValueError(f"{name}: expected unit {unit}")
        if quantity["kind"] not in KINDS:
            raise ValueError(f"{name}: unsupported evidence kind")
        if evidence == "measured" and quantity["kind"] == "synthetic":
            raise ValueError("synthetic inputs cannot be labeled measured evidence")
        if evidence == "measured" and name in ("thrust", "rpm", "torque") and quantity["kind"] not in ("measured", "derived"):
            raise ValueError(f"{name}: measured campaigns require measured or measurement-derived readings")
        text(quantity["source"], f"{name}.source")

    outputs = {
        "ct": power_law(run, 60.0**2, {"thrust": 1, "density": -1, "rpm": -2, "diameter": -4}, "1"),
        "ideal_static_disc_power": power_law(run, math.sqrt(2/math.pi), {"thrust": 1.5, "density": -0.5, "diameter": -1}, "W"),
        "cp": None,
        "shaft_power": None,
        "static_figure_of_merit": None,
    }
    if run["torque"] is not None:
        outputs["shaft_power"] = power_law(run, 2*math.pi/60, {"rpm": 1, "torque": 1}, "W")
        outputs["cp"] = power_law(run, 2*math.pi*60**2, {"torque": 1, "density": -1, "rpm": -2, "diameter": -5}, "1")
        outputs["static_figure_of_merit"] = power_law(
            run, math.sqrt(2/math.pi)*60/(2*math.pi),
            {"thrust": 1.5, "density": -0.5, "diameter": -1, "rpm": -1, "torque": -1}, "1")
    diagnostics = []
    fom = outputs["static_figure_of_merit"]
    if fom is not None and fom["value"] > 1:
        diagnostics.append("Nominal figure of merit exceeds 1: check measurements, tare, flow and ideal-disc assumptions; not a rig acceptance test.")
    for name, estimate in outputs.items():
        if estimate is not None and estimate["u"] >= estimate["value"]:
            diagnostics.append(f"{name}: standard uncertainty reaches zero; first-order propagation is poorly resolved.")
    return {"id": run["id"], "outputs": outputs, "diagnostics": diagnostics}


def reduce_document(doc):
    fields(doc, ("format", "evidence", "configuration", "static_conditions_confirmed", "runs"), "document")
    if doc["format"] != "openrc-static-prop v1":
        raise ValueError("unsupported input format")
    if doc["evidence"] not in ("synthetic", "measured"):
        raise ValueError("evidence must be synthetic or measured")
    text(doc["configuration"], "configuration")
    if doc["static_conditions_confirmed"] is not True:
        raise ValueError("static_conditions_confirmed must explicitly be true")
    if not isinstance(doc["runs"], list) or not doc["runs"]:
        raise ValueError("runs must be a nonempty array")
    runs = [reduce_run(run, doc["evidence"]) for run in doc["runs"]]
    if len({run["id"] for run in runs}) != len(runs):
        raise ValueError("duplicate run ID")
    return {"format": "openrc-static-prop-result v1", "evidence": doc["evidence"], "input": doc,
            "assumed_advance_ratio": 0.0, "limitations": LIMITATIONS, "runs": runs}


def reduce_bytes(raw):
    try:
        report = reduce_document(load(raw))
        report["input_sha256"] = hashlib.sha256(raw).hexdigest()
        report["reducer_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        json.dumps(report, allow_nan=False)
        return report
    except (OverflowError, ZeroDivisionError) as exc:
        raise ValueError("numeric range exceeded during reduction") from exc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="static propeller measurement JSON; see README")
    args = parser.parse_args()
    try:
        report = reduce_bytes(args.input.read_bytes())
        output = json.dumps(report, sort_keys=True, indent=2, allow_nan=False)
    except (ValueError, OSError) as exc:
        print(f"static propeller reduction failed: {exc}", file=sys.stderr)
        return 1
    print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
