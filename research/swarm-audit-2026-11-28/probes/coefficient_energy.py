"""Read checked-out aircraft records and audit their shared tabulated J interval.

Usage: python3 coefficient_energy.py /path/to/OpenRCsimulator
The calculation uses only the Python standard library and writes JSON to stdout.
"""
import argparse
import json
import math
from pathlib import Path


def coefficient(table, advance):
    for (left, left_value), (right, right_value) in zip(table, table[1:]):
        if left <= advance <= right:
            return left_value + (right_value - left_value) * (advance - left) / (right - left)
    raise ValueError(f"outside tabulated domain J={advance}")


def lowest_margin(thrust, power):
    lower = max(thrust[0][0], power[0][0], 0.0)
    upper = min(thrust[-1][0], power[-1][0])
    knots = sorted({x for x, _ in thrust + power if lower <= x <= upper} | {lower, upper})
    values = []
    for lo, hi in zip(knots, knots[1:]):
        ct_lo = coefficient(thrust, lo)
        ct_hi = coefficient(thrust, hi)
        cp_lo = coefficient(power, lo)
        cp_hi = coefficient(power, hi)
        ct_slope = (ct_hi - ct_lo) / (hi - lo)
        cp_slope = (cp_hi - cp_lo) / (hi - lo)
        # d(Cp - J Ct)/dJ at lo and quadratic curvature on this merged interval.
        derivative = cp_slope - ct_lo - lo * ct_slope
        candidates = [lo, hi]
        if ct_slope != 0:
            stationary = lo + derivative / (2.0 * ct_slope)
            if lo < stationary < hi:
                candidates.append(stationary)
        for advance in candidates:
            values.append((coefficient(power, advance) - advance * coefficient(thrust, advance), advance))
    margin, advance = min(values)
    return {"margin_cp_minus_jct": margin, "advance_ratio": advance, "upper_advance_ratio": upper}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", type=Path)
    args = parser.parse_args()
    data_root = args.repo / "app/data"
    margins = {}
    lag_lengths = {}
    for path in sorted((data_root / "aircraft").glob("*.json")):
        record = json.loads(path.read_text())
        reference = record.get("reference", {})
        tail = record.get("aero", {}).get("surfaces", {}).get("horizontal", {})
        if "downwash_gradient" in tail:
            assert (reference["wing_area"]["unit"], reference["wing_span"]["unit"], tail["position"]["unit"]) == ("m2", "m", "m")
            lag_lengths[path.stem] = (tail["position"]["value"][0]
                                      - 0.25 * reference["wing_area"]["value"] / reference["wing_span"]["value"])
        model = record.get("propulsion", {})
        propeller = model.get("propeller", {})
        if "ct_table" not in propeller or "glow_installation" in model.get("engine", {}):
            continue
        margins[path.stem] = lowest_margin(propeller["ct_table"]["value"], propeller["cp_table"]["value"])
    stock = json.loads((data_root / "aircraft/turbo_lumber_evolution.json").read_text())["propulsion"]["propeller"]
    advance = 0.501
    diameter = stock["diameter"]["value"]
    ct = coefficient(stock["ct_table"]["value"], advance)
    cp_stock = coefficient(stock["cp_table"]["value"], advance)
    cp_custom = 0.0200
    rps = 100.0
    density = 1.225
    power_scale = density * rps ** 3 * diameter ** 5
    output_power = advance * ct * power_scale
    creator = json.loads((data_root / "creator/power-electric-4s-800kv-apc12x6-estimated-v1.json").read_text())
    prop = creator["propeller"]
    ct0 = prop["ct_table"]["value"][0][1]
    cp0 = prop["cp_table"]["value"][0][1]
    fm = math.sqrt(2.0 / math.pi) * ct0 ** 1.5 / cp0
    importer_fm = ct0 ** 1.5 / (cp0 * math.sqrt(2.0 / math.pi))
    result = {
        "stock_transport": {"records": len(lag_lengths), "minimum_m": min(lag_lengths.values()), "maximum_m": max(lag_lengths.values())},
        "stock_tabulated_records": margins,
        "turbo_lumber_synthetic_knot": {"advance_ratio": advance, "ct": ct, "stock_cp": cp_stock, "custom_cp": cp_custom,
            "rps": rps, "diameter_m": diameter, "air_density_kg_m3": density, "forward_speed_mps": advance*rps*diameter,
            "thrust_power_w": output_power, "custom_shaft_power_w": cp_custom*power_scale, "stock_shaft_power_w": cp_stock*power_scale,
            "custom_efficiency": advance*ct/cp_custom},
        "phoenix_unity_scale": {"ct0": ct0, "cp0": cp0, "fm": fm, "importer_fm": importer_fm,
            "applied_cp_scale": max(1.0, importer_fm/0.8)}}
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
