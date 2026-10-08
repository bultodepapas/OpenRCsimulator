#!/usr/bin/env python3
"""VAL-6a: small-amplitude swing-test reduction, Python standard library only."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys


FORMAT = "openrc-swing-test v1"
UNITS = {"mass": "kg", "spacing": "m", "length": "m", "height": "m", "elapsed": "s"}
LIMITATIONS = [
    "Small-amplitude, effectively undamped motion assumed, not checked; no damping or amplitude correction.",
    "Bifilar: equal-length parallel vertical strings; spacing is the full separation; axis through object CG.",
    "Tare and loaded rig must rotate about the same axis with unchanged rig geometry.",
    "Effective inertia in air, not corrected rigid-body inertia; added air inertia is unresolved.",
    "Compound CG estimate uses a rigid-mass axis shift; added-air axis transfer remains unresolved.",
    "First-order uncertainty omits curvature, even when a stationary sensitivity gives zero contribution.",
    "Buoyancy neglected: the same mass is used for restoring torque and the parallel-axis shift.",
    "Distinct readings with common instrument biases need covariance not represented by this input format.",
    "First-order standard uncertainty (k=1); different quantity IDs are independent, reused IDs fully correlated.",
    "Uncertainty excludes unquantified alignment, sway, damping, amplitude and air-inertia biases.",
    "A 3% nominal plank comparison is diagnostic; it does not validate the physical rig or aircraft.",
]


def fields(obj, required, optional=(), where="input"):
    if not isinstance(obj, dict) or not set(required) <= obj.keys() or obj.keys() - set(required) - set(optional):
        raise ValueError(f"{where}: expected fields {sorted(required)}; optional {sorted(optional)}")


def number(value, where, positive=True):
    if type(value) not in (int, float) or not math.isfinite(value) or (value <= 0 if positive else value < 0):
        raise ValueError(f"{where}: expected finite {'positive' if positive else 'nonnegative'} number")
    return float(value)


def nonempty(value, where):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{where}: expected nonempty text")
    return value


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


def combine(*terms):
    """Linear combination of (weight, gradient) pairs; preserve shared-input covariance."""
    out = {}
    for weight, gradient in terms:
        for key, derivative in gradient.items():
            out[key] = out.get(key, 0.0) + weight * derivative
    return out


class Reduction:
    def __init__(self, doc):
        fields(doc, ("format", "evidence", "configuration", "gravity", "quantities", "experiments"))
        if doc["format"] != FORMAT or doc["evidence"] not in ("synthetic", "measured"):
            raise ValueError("unsupported format or evidence (synthetic/measured required)")
        nonempty(doc["configuration"], "configuration")
        self.doc = doc
        self.quantities = doc["quantities"]
        if not isinstance(self.quantities, dict) or not self.quantities:
            raise ValueError("quantities must be a nonempty object")
        for key, q in self.quantities.items():
            nonempty(key, "quantity ID")
            fields(q, ("value", "unit", "u", "kind", "source"), where=key)
            number(q["value"], key)
            number(q["u"], f"{key}.u", positive=False)
            if q["unit"] not in ("kg", "m", "s", "m/s^2"):
                raise ValueError(f"{key}: unsupported unit")
            if q["kind"] not in ("measured", "estimated", "derived", "reference", "synthetic"):
                raise ValueError(f"{key}: unsupported kind")
            if doc["evidence"] == "measured" and q["kind"] == "synthetic":
                raise ValueError("synthetic quantities cannot be reported as measured evidence")
            nonempty(q["source"], f"{key}.source")
        self.g = self.ref(doc["gravity"], "m/s^2")

    def ref(self, key, unit):
        if not isinstance(key, str) or key not in self.quantities:
            raise ValueError(f"unknown quantity reference: {key}")
        q = self.quantities[key]
        if q["unit"] != unit:
            raise ValueError(f"{key}: expected {unit}, got {q['unit']}")
        return float(q["value"])

    def estimate(self, value, gradient, unit):
        if not math.isfinite(value) or any(not math.isfinite(d) for d in gradient.values()):
            raise ValueError("nonfinite derived result")
        components = {key: derivative * self.quantities[key]["u"] for key, derivative in sorted(gradient.items())}
        u = math.hypot(*components.values())
        if not math.isfinite(u):
            raise ValueError("nonfinite derived uncertainty")
        return {"value": value, "unit": unit, "u": u, "kind": "derived", "standard_uncertainty_contributions": components}

    def run(self, run, method):
        keys = ("mass", "elapsed", "cycles", "spacing", "length") if method == "bifilar" else ("mass", "elapsed", "cycles", "height")
        fields(run, keys, where="swing run")
        if type(run["cycles"]) is not int or run["cycles"] < 1:
            raise ValueError("cycles must be a positive integer number of complete periods")
        v = {key: self.ref(run[key], UNITS[key]) for key in keys if key != "cycles"}
        m, elapsed = v["mass"], v["elapsed"]
        period = elapsed / run["cycles"]
        if method == "bifilar":
            inertia = m * self.g * v["spacing"]**2 * period**2 / (16 * math.pi**2 * v["length"])
            partials = {"mass": inertia/m, "elapsed": 2*inertia/elapsed, "spacing": 2*inertia/v["spacing"], "length": -inertia/v["length"]}
        else:
            # About the pivot. Shift to the object's CG only AFTER rig subtraction.
            inertia = m * self.g * v["height"] * period**2 / (4 * math.pi**2)
            partials = {"mass": inertia/m, "elapsed": 2*inertia/elapsed, "height": inertia/v["height"]}
        gradient = combine((1, {self.doc["gravity"]: inertia/self.g}), *((derivative, {run[key]: 1.0}) for key, derivative in partials.items()))
        return inertia, gradient, v, period

    def experiment(self, exp):
        fields(exp, ("id", "axis", "method", "loaded", "tare", "notes"), ("plank",), "experiment")
        nonempty(exp["id"], "experiment ID")
        nonempty(exp["notes"], "experiment notes")
        if exp["axis"] not in ("Ixx", "Iyy", "Izz") or exp["method"] not in ("bifilar", "compound"):
            raise ValueError("unsupported axis or method")
        method = exp["method"]
        jl, dl, vl, tl = self.run(exp["loaded"], method)
        mass = vl["mass"]
        dm = {exp["loaded"]["mass"]: 1.0}
        inertia, gradient = jl, dl
        first_moment = mass * vl.get("height", 0.0)
        dq = {}
        if method == "compound":
            dq = combine((vl["height"], dm), (mass, {exp["loaded"]["height"]: 1.0}))
        result = {"id": exp["id"], "axis": exp["axis"], "method": method, "notes": exp["notes"], "loaded_period_s": tl,
                  "loaded_axis_inertia": self.estimate(jl, dl, "kg*m^2"), "tare_axis_inertia": None}
        if exp["tare"] is not None:
            jt, dt, vt, tt = self.run(exp["tare"], method)
            if method == "bifilar" and any(vl[key] != vt[key] for key in ("spacing", "length")):
                raise ValueError("bifilar tare must use the same spacing and wire length")
            mass -= vt["mass"]
            dm = combine((1, dm), (-1, {exp["tare"]["mass"]: 1.0}))
            inertia -= jt
            gradient = combine((1, gradient), (-1, dt))
            if method == "compound":
                first_moment -= vt["mass"] * vt["height"]
                dq = combine((1, dq), (-vt["height"], {exp["tare"]["mass"]: 1.0}), (-vt["mass"], {exp["tare"]["height"]: 1.0}))
            result.update(tare_period_s=tt, tare_axis_inertia=self.estimate(jt, dt, "kg*m^2"))
        if mass <= 0:
            raise ValueError("loaded mass must exceed tare mass")
        result["net_swing_axis_inertia"] = self.estimate(inertia, gradient, "kg*m^2")
        if method == "compound":
            if first_moment <= 0:
                raise ValueError("object CG must be below the pivot")
            h = first_moment / mass
            inertia -= first_moment**2 / mass
            gradient = combine((1, gradient), (-2*h, dq), (h*h, dm))
            result["object_cg_below_pivot"] = self.estimate(h, combine((1/mass, dq), (-h/mass, dm)), "m")
        if inertia <= 0:
            raise ValueError("nonpositive object inertia: check geometry, timing and tare")
        result["object_mass"] = self.estimate(mass, dm, "kg")
        result["cg_estimate_definition"] = (
            "Net pivot result minus rigid-mass parallel-axis term; added-air axis transfer unresolved"
            if method == "compound" else "Net swing-axis result; object CG assumed on the swing axis"
        )
        result["effective_cg_inertia"] = self.estimate(inertia, gradient, "kg*m^2")
        # At a stationary height sensitivity a first-order zero is not zero physical uncertainty.
        result["stationary_height_warning"] = False
        if method == "compound" and exp["tare"] is None:
            key = exp["loaded"]["height"]
            u_h = self.quantities[key]["u"]
            result["stationary_height_warning"] = u_h > 0 and abs(gradient[key]) <= mass*u_h
        result["uncertainty_reaches_zero"] = result["effective_cg_inertia"]["u"] >= inertia
        if "plank" in exp:
            plank = exp["plank"]
            fields(plank, ("dimension_a", "dimension_b", "source"), where="uniform plank")
            nonempty(plank["source"], "plank source")
            a, b = (self.ref(plank[key], "m") for key in ("dimension_a", "dimension_b"))
            scale = (a*a + b*b)/12
            theory = mass * scale
            dg = combine((scale, dm), (mass*a/6, {plank["dimension_a"]: 1.0}), (mass*b/6, {plank["dimension_b"]: 1.0}))
            discrepancy = (inertia-theory)/theory
            result["plank"] = {"source": plank["source"], "theory_cg_inertia": self.estimate(theory, dg, "kg*m^2"),
                               "relative_difference": self.estimate(discrepancy, combine((1/theory, gradient), (-inertia/theory**2, dg)), "1"),
                               "within_3_percent_nominal": abs(discrepancy) <= 0.03}
        return result

    def report(self):
        experiments = self.doc["experiments"]
        if not isinstance(experiments, list) or not experiments:
            raise ValueError("experiments must be a nonempty array")
        results = [self.experiment(exp) for exp in experiments]
        if len({r["id"] for r in results}) != len(results):
            raise ValueError("duplicate experiment ID")
        return {"format": "openrc-swing-result v1", "evidence": self.doc["evidence"], "configuration": self.doc["configuration"],
                "limitations": LIMITATIONS, "quantities": self.quantities, "experiments": results}


def reduce_bytes(raw):
    try:
        report = Reduction(load(raw)).report()
        report["input_sha256"] = hashlib.sha256(raw).hexdigest()
        report["reducer_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        # Refuse nonfinite derived values even in nested diagnostic fields.
        json.dumps(report, allow_nan=False)
        return report
    except (OverflowError, ZeroDivisionError) as exc:
        raise ValueError("numeric range exceeded during reduction") from exc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="swing-test JSON (see README and synthetic.json)")
    args = parser.parse_args()
    try:
        output = json.dumps(reduce_bytes(args.input.read_bytes()), indent=2, sort_keys=True, allow_nan=False)
    except (ValueError, OSError) as exc:
        print(f"swing reduction failed: {exc}", file=sys.stderr)
        return 1
    print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
