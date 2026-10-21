#!/usr/bin/env python3
"""EX-14f: fit the Glow propeller surrogate's section to measured APC Sport data.

The 12-annulus surrogate (app/physics/glow/propeller.gd, mirrored by calibration_report.annular_prop_performance)
with a symmetric section reaches zero thrust at the geometric pitch ratio and absorbs too little static power. Measured
APC Sport propellers keep thrust to about 1.4x their pitch ratio. A cambered section's zero-lift angle restores that.
This tool fits the chord ratio c/D and the zero-lift angle to the measured UIUC APC Sport 11x6 knots that the Stik data
file already carries (UIUC vol. 1 apcsp_11x6_static_rd0488 and apcsp_11x6_rd0495_6000, about 6,000 rpm), keeping the
installation's section slope, profile drag and loss coefficient. It also reports the static figure of merit and the
least margin over the ideal actuator-disk power in forward flow. Deterministic grid plus refinement; no measured
12x6 Sport map exists in the repository, so applying the 11x6 fit to a 12x6 is a same-family c/D transfer.

    python3 research/glow-engines/fit_section.py           # writes research/glow-engines/section_fits.json
    python3 research/glow-engines/fit_section.py --check   # fails if section_fits.json is stale
"""
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from calibration_report import annular_prop_performance  # noqa: E402

SOURCE = ROOT / "app/data/aircraft/jensen_ugly_stik_60.json"
OUT = Path(__file__).resolve().with_name("section_fits.json")
IN = 0.0254
DIAMETER, PITCH = 11 * IN, 6 * IN            # the measured APC Sport 11x6
SECTION = {"lift_slope_per_rad": 5.5, "cd0": 0.022, "induced_drag": 0.06, "blades": 2.0}  # installation constants
RPM, RHO = 6000.0, 1.225
CT_SCALE, CP_SCALE = 0.1, 0.05               # normalizers: errors are compared at the coefficients' own scale


def coefficients(j, chord_over_d, zero_lift, diameter=DIAMETER, pitch=PITCH):
    n = RPM / 60.0
    section = dict(SECTION, zero_lift_angle_rad=zero_lift)
    r = annular_prop_performance(RPM, j * n * diameter, diameter, pitch, chord_over_d * diameter, RHO, section)
    return r["thrust_n"] / (RHO * n * n * diameter ** 4), r["shaft_power_w"] / (RHO * n ** 3 * diameter ** 5)


def interp(table, j):
    for (j0, c0), (j1, c1) in zip(table, table[1:]):
        if j0 <= j <= j1:
            return c0 + (c1 - c0) * (j - j0) / (j1 - j0)
    raise ValueError("J outside the measured knots")


def main():
    prop = json.loads(SOURCE.read_text(encoding="utf-8"))["propulsion"]["propeller"]
    ct, cp = prop["ct_table"]["value"], prop["cp_table"]["value"]
    knots = sorted({row[0] for row in ct} | {row[0] for row in cp})

    def cost(c_d, a0):
        return sum(((coefficients(j, c_d, a0)[0] - interp(ct, j)) / CT_SCALE) ** 2
                   + ((coefficients(j, c_d, a0)[1] - interp(cp, j)) / CP_SCALE) ** 2 for j in knots)

    best = min((cost(0.02 + 0.002 * i, -math.radians(0.25 * k)), 0.02 + 0.002 * i, -math.radians(0.25 * k))
               for i in range(31) for k in range(41))
    step_c, step_a = 0.002, math.radians(0.25)
    for _ in range(12):  # coordinate refinement around the grid optimum
        step_c, step_a = step_c / 2, step_a / 2
        _, c_d, a0 = best
        best = min([best] + [(cost(c_d + dc, a0 + da), c_d + dc, a0 + da)
                             for dc in (-step_c, 0.0, step_c) for da in (-step_a, 0.0, step_a) if a0 + da <= 0.0])
    e, c_d, a0 = best
    _, flat_c, _ = min((cost(0.02 + 0.002 * i, 0.0), 0.02 + 0.002 * i, 0.0) for i in range(31))
    rows = []
    for j in knots:
        cts, cps = coefficients(j, c_d, a0)
        rows.append({"J": j, "ct_measured": interp(ct, j), "ct_fit": cts, "cp_measured": interp(cp, j), "cp_fit": cps})
    ct0, cp0 = coefficients(0.0, c_d, a0)
    # Least shaft-power margin over the ideal actuator-disk power for positive forward thrust (NITRO-02 asks >= 5 %),
    # on the 12x6 the fit is applied to, from static to the zero-thrust advance ratio.
    margins = []
    d12, p12 = 12 * IN, 6 * IN
    for k in range(0, 76):
        j = 0.01 * k
        n = RPM / 60.0
        v = j * n * d12
        r = annular_prop_performance(RPM, v, d12, p12, c_d * d12, RHO, dict(SECTION, zero_lift_angle_rad=a0))
        if r["thrust_n"] <= 0.0:
            break
        area = math.pi * d12 ** 2 / 4
        ideal = 0.5 * r["thrust_n"] * (v + math.sqrt(v * v + 2 * r["thrust_n"] / (RHO * area)))
        margins.append(r["shaft_power_w"] / ideal - 1.0)
    out = {
        "generator": "research/glow-engines/fit_section.py",
        "apc_sport_11x6_uiuc": {
            "measured_source": prop["ct_table"]["source"],
            "data_file": SOURCE.relative_to(ROOT).as_posix(),
            "section_constants": SECTION,
            "chord_over_diameter": c_d,
            "zero_lift_angle_rad": a0,
            "zero_lift_angle_deg": math.degrees(a0),
            "normalized_rms": math.sqrt(e / len(knots) / 2),
            "symmetric_section_best_chord_over_diameter": flat_c,
            "symmetric_section_normalized_rms": math.sqrt(min(cost(flat_c, 0.0), 1e99) / len(knots) / 2),
            "static_figure_of_merit": ct0 * math.sqrt(2 * ct0 / math.pi) / cp0,
            "least_power_margin_over_ideal_on_12x6": min(margins),
            "rows": rows,
        },
    }
    text = json.dumps(out, indent=2) + "\n"
    if "--check" in sys.argv:
        if not OUT.exists():
            print(f"stale: {OUT}")
            return 1
        old = json.loads(OUT.read_text())
        ok = json.dumps(old, sort_keys=True) == json.dumps(json.loads(text), sort_keys=True)
        print("current" if ok else f"stale: {OUT}")
        return 0 if ok else 1
    OUT.write_text(text)
    f = out["apc_sport_11x6_uiuc"]
    print(f"c/D {c_d:.5f}, zero-lift {math.degrees(a0):.3f} deg, rms {f['normalized_rms']:.4f} "
          f"(symmetric best {f['symmetric_section_normalized_rms']:.3f}), static FM {f['static_figure_of_merit']:.3f}, "
          f"least margin over ideal {100 * f['least_power_margin_over_ideal_on_12x6']:.1f} %")
    return 0


if __name__ == "__main__":
    sys.exit(main())
