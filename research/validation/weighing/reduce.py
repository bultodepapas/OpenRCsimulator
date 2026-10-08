#!/usr/bin/env python3
"""VAL-5a: level-aircraft weighing reduction; standard library only."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

FORMAT = "openrc-weighing v1"
KINDS = ("measured", "estimated", "derived", "manual", "synthetic")
LIMITATIONS = [
    "Level body forward/right axes; vertical CG is unobservable from this weighing.",
    "Static aircraft, all vertical reactions measured, no other forces or restraints.",
    "First-order standard uncertainties (k=1), not confidence intervals or worst-case bounds.",
    "Reading and local position errors are independent; scale gains are shared by gross/tare.",
    "Common scale gain and datum shifts are fully correlated across supports; other correlations are excluded.",
    "Unquantified leveling, buoyancy, drift and configuration errors are excluded.",
    "Reduction verifies statics; it does not validate scales, setup, aircraft data or flight fidelity.",
]


def fields(obj, expected, where):
    if not isinstance(obj, dict) or obj.keys() != set(expected):
        raise ValueError(f"{where}: expected exactly {', '.join(expected)}")


def text(value, where):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{where}: expected nonempty text")
    return value


def number(value, where):
    if type(value) not in (int, float):
        raise ValueError(f"{where}: expected a finite number")
    try:
        result = float(value)
    except OverflowError:
        raise ValueError(f"{where}: number exceeds float64 range") from None
    if not math.isfinite(result):
        raise ValueError(f"{where}: expected a finite number")
    return result


def quantity(obj, unit, where, evidence, nonnegative=False, zero=False):
    fields(obj, ("value", "unit", "u", "kind", "source"), where)
    value = number(obj["value"], where)
    u = number(obj["u"], f"{where}.u")
    if obj["unit"] != unit or u < 0:
        raise ValueError(f"{where}: expected unit {unit} and nonnegative standard uncertainty u")
    if obj["kind"] not in KINDS or (evidence == "measured" and obj["kind"] == "synthetic"):
        raise ValueError(f"{where}: invalid evidence kind")
    text(obj["source"], f"{where}.source")
    if (nonnegative and value < 0) or (zero and value != 0):
        raise ValueError(f"{where}: expected {'zero nominal error' if zero else 'nonnegative value'}")
    return value, u


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load(raw):
    def bad_constant(value):
        raise ValueError(f"nonfinite JSON constant: {value}")
    return json.loads(raw, object_pairs_hook=unique_object, parse_constant=bad_constant)


def reduce_weighing(doc):
    fields(doc, ("format", "evidence", "aircraft", "configuration", "datum", "setup",
                 "common_scale_gain", "datum_x", "datum_y", "supports"), "input")
    if doc["format"] != FORMAT or doc["evidence"] not in ("synthetic", "measured"):
        raise ValueError("unsupported format or evidence (synthetic/measured required)")
    evidence = doc["evidence"]
    for name in ("aircraft", "configuration", "datum"):
        text(doc[name], name)
    fields(doc["setup"], ("level", "all_loads_on_scales", "notes"), "setup")
    for name in ("level", "all_loads_on_scales"):
        if doc["setup"][name] is not True:
            raise ValueError(f"setup.{name}: must be true for this reduction")
    text(doc["setup"]["notes"], "setup.notes")
    common = {}
    for name, unit in (("common_scale_gain", "1"), ("datum_x", "m"), ("datum_y", "m")):
        common[name] = quantity(doc[name], unit, name, evidence, zero=True)[1]
    if not isinstance(doc["supports"], list) or len(doc["supports"]) < 3:
        raise ValueError("supports: at least three non-collinear supports required")
    supports, ids = [], set()
    for i, item in enumerate(doc["supports"]):
        where = f"supports[{i}]"
        fields(item, ("id", "gross", "tare", "x", "y", "scale_gain"), where)
        ident = text(item["id"], f"{where}.id")
        if ident in ids:
            raise ValueError(f"duplicate support ID: {ident}")
        ids.add(ident)
        values = {}
        for key, unit in (("gross", "kg"), ("tare", "kg"), ("x", "m"),
                          ("y", "m"), ("scale_gain", "1")):
            values[key] = quantity(item[key], unit, f"{where}.{key}", evidence,
                                   nonnegative=key in ("gross", "tare"), zero=key == "scale_gain")
        net = values["gross"][0] - values["tare"][0]
        if net < 0:
            raise ValueError(f"{where}: tare exceeds gross")
        supports.append((ident, net, values))
    mass = math.fsum(s[1] for s in supports)
    if not math.isfinite(mass) or mass <= 0:
        raise ValueError("total net mass must be finite and positive")
    # Normalize coordinates before the area check to avoid squared-distance overflow.
    xs = [s[2]["x"][0] for s in supports]
    ys = [s[2]["y"][0] for s in supports]
    span = max(max(xs) - min(xs), max(ys) - min(ys))
    if not math.isfinite(span) or span == 0:
        raise ValueError("support geometry is degenerate or out of range")
    points = [((x - xs[0]) / span, (y - ys[0]) / span) for x, y in zip(xs, ys)]
    if not any(abs(ax * by - ay * bx) > 1e-12
               for ax, ay in points[1:] for bx, by in points[1:]):
        raise ValueError("supports are collinear or numerically indistinguishable")
    weights = [s[1] / mass for s in supports]
    cg = [math.fsum(w * v for w, v in zip(weights, coords)) for coords in (xs, ys)]
    # Each vector is one independent standard-error contribution to [mass, x_CG, y_CG].
    terms = []
    for (ident, net, values), w in zip(supports, weights):
        dx = (values["x"][0] - cg[0]) / mass
        dy = (values["y"][0] - cg[1]) / mass
        for key, sign in (("gross", 1), ("tare", -1)):
            u = values[key][1] * sign
            terms.append((f"{ident}.{key}", [u, dx * u, dy * u]))
        u = net * values["scale_gain"][1]
        terms.append((f"{ident}.scale_gain", [u, dx * u, dy * u]))
        terms.append((f"{ident}.x", [0.0, w * values["x"][1], 0.0]))
        terms.append((f"{ident}.y", [0.0, 0.0, w * values["y"][1]]))
    terms.extend([
        ("common_scale_gain", [mass * common["common_scale_gain"], 0.0, 0.0]),
        ("datum_x", [0.0, common["datum_x"], 0.0]),
        ("datum_y", [0.0, 0.0, common["datum_y"]]),
    ])
    covariance = [[math.fsum(t[i] * t[j] for _, t in terms) for j in range(3)] for i in range(3)]
    if any(not math.isfinite(v) for v in [*cg, *(v for row in covariance for v in row)]):
        raise ValueError("derived result exceeds float64 range")
    uncertainty = [math.sqrt(covariance[i][i]) for i in range(3)]
    warnings = []
    # The global gain cancels exactly from CG; only local load errors make its
    # denominator uncertain. Do not diagnose CG linearization from global gain.
    local_mass_u = math.hypot(*(t[0] for name, t in terms if name != "common_scale_gain"))
    if local_mass_u / mass > 0.1:
        warnings.append("Local-load relative standard uncertainty exceeds 10% (tool diagnostic); linearized CG uncertainty may be unreliable.")
    if any(s[1] == 0 for s in supports):
        warnings.append("A support has zero net load; confirm contact and repeat the weighing.")
    return {
        "format": "openrc-weighing-result v1", "evidence": evidence,
        "input": doc,
        "results": {key: {"value": value, "unit": unit, "u": u, "kind": "derived"}
                    for key, value, unit, u in zip(("mass", "cg_x", "cg_y"), [mass, *cg],
                                                   ("kg", "m", "m"), uncertainty)},
        "covariance": {"order": ["mass_kg", "cg_x_m", "cg_y_m"], "matrix": covariance},
        "standard_error_contributions": {name: vec for name, vec in terms},
        "net_loads_kg": {s[0]: s[1] for s in supports},
        "warnings": warnings, "limitations": LIMITATIONS,
    }


def report(raw):
    result = reduce_weighing(load(raw))
    result["input_sha256"] = hashlib.sha256(raw).hexdigest()
    result["reducer_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    return json.dumps(result, indent=2, allow_nan=False) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, help="write JSON report (default: stdout)")
    args = parser.parse_args()
    try:
        if args.output and (args.output.resolve() == args.input.resolve()
                            or (args.output.exists() and args.output.samefile(args.input))):
            raise ValueError("output must not overwrite the input")
        rendered = report(args.input.read_bytes())
        if args.output:
            args.output.write_text(rendered, encoding="utf-8")
        else:
            sys.stdout.write(rendered)
    except (OSError, ValueError, OverflowError, RecursionError) as exc:
        print(f"weighing: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
