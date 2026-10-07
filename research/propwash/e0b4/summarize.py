#!/usr/bin/env python3
"""Generate readable ranges from the verified E0b4 evidence."""
import json
from check_results import ROOT, DEFAULT, validate

data = json.loads(DEFAULT.read_text())
validate(data)
baseline = {r["name"]: r for r in data["baseline"]}
lines = ["# E0b4 — numerical sensitivity tables", "",
         "**Status: generated numerical evidence; not calibrated flight data.**",
         "Regenerate with python3 research/propwash/e0b4/summarize.py. Source: [results.json](results.json).",
         "Ranges are extrema of the stated finite grid, not statistical confidence bounds or continuous-domain bounds.", "",
         "## Fixed operating points", "",
         "| Condition | Speed m/s | Throttle | RPM | Alpha ° |",
         "| --- | ---: | ---: | ---: | ---: |"]
for name, row in baseline.items():
    lines.append(f"| {name} | {row['speed_m_s']:.0f} | {row['throttle']:.4f} | {row['rpm']:.2f} | {row['alpha_deg']:.4f} |")

def span(values, scale=1, places=3):
    values = list(values)
    return f"{min(values)*scale:.{places}f}…{max(values)*scale:.{places}f}"

lines += ["", "## Occupancy and pressure proxy", "",
          "Fractions use neutral geometric area; pressure averages use the unchanged aerodynamic area. These are load-occupancy weights and area-weighted pressure proxies, not measured coverage or force multipliers.",
          "", "| Condition | H occupancy % | V occupancy % | Centre q / q∞ | H mean q proxy (Pa) | V mean q proxy (Pa) |",
          "| --- | ---: | ---: | ---: | ---: | ---: |"]
for name in baseline:
    rows = [next(r for r in c["conditions"] if r["name"] == name) for c in data["cases"]]
    h = span((r["coverage"]["horizontal"]["geometric_fraction"] for r in rows),100,2)
    v = span((r["coverage"]["vertical"]["geometric_fraction"] for r in rows),100,2)
    qr = "undefined at V=0" if rows[0]["speed_m_s"] == 0 else span(r["centre_q_ratio"] for r in rows)
    qh = span((r["coverage"]["horizontal"]["mean_q_proxy_Pa"] for r in rows),places=2)
    qv = span((r["coverage"]["vertical"]["mean_q_proxy_Pa"] for r in rows),places=2)
    lines.append(f"| {name} | {h} | {v} | {qr} | {qh} | {qv} |")

lines += ["", "## Aerodynamic derivatives at the no-wash 15 m/s trim", "",
          "Same state, controls and frozen RPM on/off. Aerodynamic + tail-wash loads only; propulsion/gravity omitted here. Cma is quasi-static; Cma_held freezes the downwash lag-state input. Rates use q·c/(2V), r·b/(2V); angles/controls use radians. Percentage change is 100·(on/off−1), meaningful only with the same sign/definition.",
          "", "| Coefficient | Off | On range | Change % | Selig figure-typical endpoints change % |",
          "| --- | ---: | ---: | ---: | ---: |"]
typical = next(r for r in data["source_typical"]["conditions"] if r["name"] == "baseline_trim_15")
rows = [next(r for r in c["conditions"] if r["name"] == "baseline_trim_15") for c in data["cases"]]
for key, off in baseline["baseline_trim_15"]["derivatives"].items():
    values = [r["derivatives"][key] for r in rows]
    change = span((100*(v/off-1) for v in values),places=2)
    figure = 100*(typical["derivatives"][key]/off-1)
    lines.append(f"| {key} | {off:.6f} | {span(values,places=6)} | {change} | {figure:.2f} |")

lines += ["", "## Untrimmed low-speed alpha partials", "",
          "5 m/s, alpha=beta=0, neutral controls, full RPM. These are different partials of a lagged system, not dynamic-stability conclusions.",
          "", "| Partial | Off | On range |", "| --- | ---: | ---: |"]
rows = [next(r for r in c["conditions"] if r["name"] == "axial_full_5") for c in data["cases"]]
for key in ["Cma", "Cma_held"]:
    lines.append(f"| {key} | {baseline['axial_full_5']['derivatives'][key]:.6f} | {span((r['derivatives'][key] for r in rows),places=6)} |")

lines += ["", "## Static full-RPM controls", "",
          "Extrema across 17 sampled deflections within each control's actual throw and across the 81 grid points. Not proven continuous-control extrema. Positive body My is nose-up; positive Mz is nose-right. Each control is varied alone.",
          "", "| Control moment | Current law (N·m) | Lag CL input forced to zero (N·m) |",
          "| --- | ---: | ---: |"]
for ctrl in ["elevator", "rudder"]:
    def values(field):
        return [p["moment_Nm"] for c in data["cases"] for p in c[field][ctrl]]
    lines.append(f"| {ctrl} | {span(values('static_controls'))} | {span(values('static_controls_zero_cl'))} |")
ref = data["static_reference"]
lines += ["", f"At V=0, CL_wing={ref['wing_cl_at_zero_speed']:.8f}=CL_wing0. The E0a2 intercept cancels: the neutral effective tail angle is {ref['neutral_effective_angle_rad']:.8f} rad. Forcing the CL input to zero without re-deriving incidence changes it to {ref['forced_zero_cl_angle_rad']:.8f} rad. This perturbation is **not** a physically corrected no-downwash model.", "",
          "## Full-model retrimmed modes", "",
          "Nine wash endpoint pairs × three speeds; edge=0.15 and drift=0.543 only. Full Dynamics, propulsion and the existing downwash lag included, wash transport absent. Existing block-projected modal analysis; cross-axis coupling is not diagonalized.",
          "", "| Speed m/s | Short-period ζ off | Short-period ζ on | Dutch-roll ζ off | Dutch-roll ζ on | Signed spiral e-fold time on (s) |",
          "| --- | ---: | ---: | ---: | ---: | ---: |"]
for b in data["baseline_modes"]:
    speed=b["speed_m_s"]
    rows=[r for r in data["retrimmed_modes"] if r["speed_m_s"]==speed]
    lines.append(f"| {speed:.0f} | {b['short_period']['zeta']:.4f} | {span((r['short_period']['zeta'] for r in rows),places=4)} | {b['dutch_roll']['zeta']:.4f} | {span((r['dutch_roll']['zeta'] for r in rows),places=4)} | {span(r['spiral_tau'] for r in rows)} |")
lines += ["", "Negative spiral time means divergence in this modal convention; damping of the oscillatory modes alone is not a whole-aircraft stability claim.", "",
          f"Finite-difference h→h/2 worst normalized change: {data['worst_normalized_derivative_refinement']:.8g}, normalized by max(1, |refined coefficient|).", ""]
(ROOT/"docs/research/propwash/E0b4/tables.md").write_text("\n".join(lines))
print("E0b4: wrote tables.md from verified results")
