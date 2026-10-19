#!/usr/bin/env python3
"""BAT-05: generate cell templates and pack class files from fit_results.json (BAT-04 formats §1–§2).

Usage:
  python3 -I research/battery/bat-05/build_batteries.py            write app/data/batteries/{cells,packs}/*.json
  python3 -I research/battery/bat-05/build_batteries.py --check    regenerate in memory, compare bytes, exit 1 on any
                                                                    difference; verify input sha256 when the
                                                                    gitignored references/ folder is present

Generated files are never edited by hand. Evidence: docs/research/battery/BAT-05/README.md.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))  # research/battery: the independent reference law
import ecm_reference as ecm  # noqa: E402

FIT_RESULTS = HERE / "fit_results.json"
CELL_DIR = REPO / "app" / "data" / "batteries" / "cells"
PACK_DIR = REPO / "app" / "data" / "batteries" / "packs"
REFERENCES = REPO / "references" / "battery-energy"
GENERATOR = "research/battery/bat-05/build_batteries.py"
FIT_REPORT = "docs/research/battery/BAT-05/README.md"
LIPO_ID = "lipo-bak503562-galeotti-v1"
HG2_ID = "liion-lg-hg2-kollmeyer-v1"

GALEOTTI_DOI = "Galeotti et al. 2023 LiPo dataset (Mendeley Data doi:10.17632/stcppt2r68.1, CC BY 4.0)"
KOLLMEYER_DOI = "Kollmeyer et al. LG 18650HG2 dataset (Mendeley Data doi:10.17632/b5mj79w5w9.2, CC BY 4.0)"
BAK_SPEC = ("BAK/Dubilier 'Specification of Li-polymer Rechargeable Battery, Model No. LP-503562-1S-3' "
            "(file 20120102, ed. 1.0, 2012)")
LG_SPEC = "LG Chem product specification INR18650HG2 (PS-HG2-Rev5, 2017-03-31)"
STEINHARDT = ("Steinhardt et al. 2022, J. Power Sources 522:230829 (doi:10.1016/j.jpowsour.2021.230829), "
              "meta-analysis of whole-cell heat capacity")

# LiPo class resistance anchor (per cell, at 50 % SOC and 298.15 K), scaled ∝ 1/capacity.
ANCHOR_R0_OHM = 0.005
ANCHOR_CAPACITY_AH = 3.2
ANCHOR_SOURCE = (
    "Class anchor R0 = 5.0 mOhm per cell at 3.2 Ah (50 % SOC, 298.15 K), scaled by 3.2 Ah / rated capacity "
    "(same cell design family, R ∝ 1/Q). Anchor estimated from: Bauersfeld & Scaramuzza 2022 (arXiv 2109.04741, "
    "IEEE RA-L 7(2):2953, Table I R_min = 4.5 mOhm per cell, 1.8 Ah 4S racing pack); Di Nisio et al. 2023 "
    "(Sensors 23:6937, doi:10.3390/s23156937: 20.68 mOhm for a 4S 10 Ah pack = 5.2 mOhm per cell); PX4 battery "
    "docs ('a typical value for LiPo batteries is 5mOhm per cell'). Never derived from the C label.")

# LiPo class geometry/mass anchor: the Timber 4S 3200 pack.
TIMBER_MASS_KG = 0.33
TIMBER_MASS_SOURCE = ("EFL105250B manual (E-flite Turbo Timber Evolution): flying weight with 4S 3200 mAh battery "
                      "2190 g minus without battery 1860 g = 0.33 kg")
TIMBER_BOX_M = (0.14, 0.043, 0.032)
TIMBER_BOX_SOURCE = ("TT-07 Timber inventory battery_main aligned box estimate, "
                     "app/data/aircraft/turbo_lumber_evolution.json")

LIPO_CLASSES = (
    # id, series, capacity_ah, c_rating
    ("lipo-3s1p-2200-25c-class", 3, 2.2, 25),
    ("lipo-4s1p-2200-30c-class", 4, 2.2, 30),
    ("lipo-4s1p-3200-30c-class", 4, 3.2, 30),
    ("lipo-4s1p-5000-30c-class", 4, 5.0, 30),
    ("lipo-6s1p-2200-30c-class", 6, 2.2, 30),
    ("lipo-6s1p-5000-30c-class", 6, 5.0, 30),
)
HG2_PACKS = (("liion-4s1p-3000-hg2", 4, 1), ("liion-4s2p-6000-hg2", 4, 2))

# Thermal correlation inputs (Incropera & DeWitt, Fundamentals of Heat and Mass Transfer).
H_NATURAL = 5.0          # W/(m²·K); Table 1.1 free convection of gases 2–25 W/(m²·K)
AIR_K = 0.0263           # W/(m·K), air at 300 K (Table A.4)
AIR_NU = 15.89e-6        # m²/s
AIR_PR = 0.707
HG2_CELL_MASS_KG = 0.048              # LG spec Rev 5: weight max 48.0 g
HG2_CELL_DIAMETER_M = 0.0185          # LG spec Rev 5: diameter max 18.5 mm
HG2_CELL_LENGTH_M = 0.0652            # LG spec Rev 5: height max 65.2 mm
HG2_ALLOWANCE_PER_CELL_KG = 0.006     # nickel strip, insulation ring, shrink wrap (estimated)
HG2_ALLOWANCE_PACK_KG = 0.015         # main leads, connector, balance lead (estimated)
HG2_STRIP_OHM = 0.0012                # one series joint: nickel 0.15 x 8 mm, 20 mm long, rho 6.99e-8 ohm·m (estimated)
LEADS_OHM = 0.002                     # 2 x 10 cm 12 AWG (≈1.0 mOhm) plus an XT60-class connector pair (estimated)


def q(value, unit: str, kind: str, source: str) -> dict:
    return {"value": value, "unit": unit, "kind": kind, "source": source}


def r12(x):
    """Round floats to 12 significant digits (recursively)."""
    if isinstance(x, float):
        return float(f"{x:.12g}")
    if isinstance(x, dict):
        return {k: r12(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [r12(v) for v in x]
    return x


def dumps(obj: dict) -> bytes:
    return (json.dumps(r12(obj), indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# ---------------------------------------------------------------------------------------------
# Cell templates (§1)
# ---------------------------------------------------------------------------------------------

def _rc(tables: dict, r_kind: str, r_source: str, tau_kind: str, tau_source: str) -> list:
    return [{"r_ohm": q(b["r"], "ohm", r_kind, r_source), "tau_s": q(b["tau"], "s", tau_kind, tau_source)}
            for b in tables["rc"]]


def lipo_template(fit: dict) -> dict:
    lp, li = fit["lipo"], fit["liion"]
    t = lp["tables"]
    cell = lp["cell"]
    def shapes_values(entry: dict) -> bool:   # files that determine template values (held-out runs excluded)
        folder, name = entry["file"].split("/")
        return folder.startswith(cell) and (name.startswith("1_0_") or
                                            name in ("0_0_1_stddischarge.csv", "2_0_stressdischarge.csv"))
    inputs = [e for e in fit["inputs"]["lipo"] if shapes_values(e)]
    inputs += [e for e in fit["inputs"]["liion"] if e["file"].endswith(("_HPPC.csv", "_C20DisCh.csv"))]
    ea = li["arrhenius"]
    used = t["ea_used"]
    k = len(t["rc"])
    ea_text = "; ".join([f"R0 Ea = {ea['r0']['ea_j_per_mol']:.0f} J/mol"] +
                        [f"branch {b + 1} uses HG2 {used[f'branch{b + 1}'].upper()} Ea = "
                         f"{ea[used[f'branch{b + 1}']]['ea_j_per_mol']:.0f} J/mol" for b in range(k)])
    fit_src = (f"BAT-05 fit ({lp['chosen']}) of cell {cell} cycle 0 of the {GALEOTTI_DOI}: 1 A partial-discharge "
               f"ladder (1_0_*_pardisch.csv, 300 s rests) and 3 A stress discharge 2_0, 25 °C")
    return {
        "format": ecm.CELL_FORMAT,
        "id": LIPO_ID,
        "display_name": "BAK LP-503562 1.1 Ah LiPo pouch cell (Galeotti dataset fit)",
        "chemistry": "lipo",
        "tier": "A",
        "generator": GENERATOR,
        "provenance": {"fit_report": FIT_REPORT, "inputs": inputs},
        "reference_capacity_ah": q(lp["reference_capacity_ah"], "Ah", "measured",
                                   f"{GALEOTTI_DOI}, cell {cell} 0_0_1_stddischarge.csv: charge extracted at 1 A "
                                   "after CC-CV charge (1 A to 4.2 V, CV to 0.2 A) down to 2.75 V, 25 °C"),
        "soc_knots": q(t["soc_knots"], "1", "derived",
                       "BAT-05 knot grid; SOC 0 = the 1 A reference discharge reaching 2.75 V, SOC 1 = full charge"),
        "temperature_knots_k": q(t["temperature_knots_k"], "K", "derived",
                                 "BAT-05 knot grid shared with the HG2 template; LiPo data exist only at 298.15 K"),
        "ocv_v": q(t["ocv"], "V", "derived",
                   fit_src + "; OCV nondecreasing by construction; every temperature row copies the 298.15 K row "
                   "(no LiPo temperature data; entropic OCV change neglected)"),
        "r0_ohm": q(t["r0"], "ohm", "borrowed",
                    fit_src + "; 298.15 K row fitted (R0 at the 0.43 s first sample, includes the cell's protection "
                    f"circuit if fitted); other rows scaled by HG2 Arrhenius factors ({ea_text})"),
        "rc_branches": _rc(t, "borrowed",
                           fit_src + f"; 298.15 K row fitted; other rows scaled by HG2 Arrhenius factors ({ea_text})",
                           "derived", fit_src + "; one SOC-independent time constant per branch, kept at every "
                           "temperature (temperature dependence of tau not identified)"),
        "specific_heat_j_per_kg_k": q(1168.0, "J/(kg·K)", "estimated",
                                      f"{STEINHARDT}: median of mid-range values for pouch cells 1168 J/(kg·K) "
                                      "(pouch range 860–1380); not measured for this cell"),
        "limits": {
            "v_max": q(4.2, "V", "manual", f"{BAK_SPEC}: charging voltage 4.20 ± 0.05 V; dataset CC-CV to 4.2 V"),
            "v_cutoff": q(2.75, "V", "manual", f"{BAK_SPEC}: discharge cut-off voltage 2.75 V; dataset discharges "
                                                  "end at 2.75 V (template data floor)"),
            "v_damage_floor": q(2.5, "V", "manual", f"{BAK_SPEC}: protection board over-discharge detection "
                                                       "2.500 V typ (2.438–2.562 V)"),
            "t_min_k": q(253.15, "K", "manual", f"{BAK_SPEC}: discharge temperature -20 °C to +60 °C"),
            "t_max_k": q(333.15, "K", "manual", f"{BAK_SPEC}: discharge temperature -20 °C to +60 °C"),
        },
    }


def hg2_template(fit: dict) -> dict:
    li = fit["liion"]
    t = li["tables"]
    inputs = [e for e in fit["inputs"]["liion"] if e["file"].endswith(("_HPPC.csv", "_C20DisCh.csv"))]
    k = li["chosen_branches"]
    ea = li["arrhenius"]
    th = li["thermal"]
    hppc = (f"{KOLLMEYER_DOI}: HPPC tests 585/575/549/555 at 0/10/25/40 °C chamber, one LG HG2 cell; "
            "rows at the knot temperatures shifted from the measured mean cell temperature with the fitted "
            "Arrhenius activation energy")
    ea_text = ", ".join(f"{name.upper()} {v['ea_j_per_mol']:.0f} J/mol" for name, v in ea.items())
    return {
        "format": ecm.CELL_FORMAT,
        "id": HG2_ID,
        "display_name": "LG INR18650HG2 3.0 Ah Li-ion cell (Kollmeyer dataset fit)",
        "chemistry": "liion",
        "tier": "A",
        "generator": GENERATOR,
        "provenance": {"fit_report": FIT_REPORT, "inputs": inputs},
        "reference_capacity_ah": q(li["reference_capacity_ah"], "Ah", "measured",
                                   f"{KOLLMEYER_DOI}, 549_C20DisCh.csv step 22: C/20 (0.15 A) discharge from full "
                                   "charge to 2.8 V at 25 °C (LG nominal 3.0 Ah to 2.0 V)"),
        "soc_knots": q(t["soc_knots"], "1", "derived",
                       "BAT-05 knot grid; SOC 0 = the C/20 reference discharge reaching 2.8 V, SOC 1 = full charge"),
        "temperature_knots_k": q(t["temperature_knots_k"], "K", "derived",
                                 "chamber set points of the Kollmeyer tests 585/575/549/555"),
        "ocv_v": q(t["ocv"], "V", "derived",
                   f"{KOLLMEYER_DOI}: C/20 discharge (<id>_C20DisCh.csv) per temperature, SOC normalised by that "
                   "test's own C/20 capacity, plus I·(R0 + sum R_k) from the HPPC fit, isotonic (nondecreasing)"),
        "r0_ohm": q(t["r0"], "ohm", "derived",
                    hppc + "; R0 = median of current-onset and current-interruption voltage steps (0.1 s sampling) "
                    f"of the full-length 1C–6C discharge pulses at each HPPC SOC level (Ea: {ea_text})"),
        "rc_branches": _rc(t, "derived",
                           hppc + f"; {k} RC branch(es) fitted per HPPC SOC level (0.9 A SOC step, 1 h rest and pulse "
                           "block on a 0.1 s grid) with R0 fixed and the time constant(s) fixed at the median over "
                           "levels with SOC >= 0.1", "derived",
                           hppc + "; median per temperature of per-level free fits (SOC-independent)"),
        "specific_heat_j_per_kg_k": q(912.0, "J/(kg·K)", "estimated",
                                      f"{STEINHARDT}: median of mid-range values for cylindrical cells 912 J/(kg·K); "
                                      "Maleki et al. 1999 (J. Electrochem. Soc. 146:947) measured 960–1040 J/(kg·K) "
                                      "on an 18650. Not identifiable from the dataset: the 2C temperature rise gives "
                                      f"C_th = {th['c_th_j_per_k']:.0f} J/K (test fixture with soldered leads, "
                                      f"not the {HG2_CELL_MASS_KG * 1000:.0f} g cell)"),
        "limits": {
            "v_max": q(4.2, "V", "manual", f"{LG_SPEC}: max. charge voltage 4.20 ± 0.05 V"),
            "v_cutoff": q(2.8, "V", "derived",
                          f"template data floor: every {KOLLMEYER_DOI} discharge ends at 2.8 V; the {LG_SPEC} "
                          "end voltage is 2.0 V (2.5 V in Rev 0), outside the data"),
            "v_damage_floor": q(2.0, "V", "manual", f"{LG_SPEC}: standard discharge end voltage (cut-off) 2.0 V"),
            "t_min_k": q(253.15, "K", "manual", f"{LG_SPEC}: operating temperature, discharge -20 to 75 °C"),
            "t_max_k": q(348.15, "K", "manual", f"{LG_SPEC}: operating temperature, discharge -20 to 75 °C"),
        },
    }


# ---------------------------------------------------------------------------------------------
# Packs (§2)
# ---------------------------------------------------------------------------------------------

def heat_transfer(dims: list, dims_kind: str) -> dict:
    length, width, height = dims
    area = 2.0 * (length * width + length * height + width * height)
    still = H_NATURAL * area
    forced = area * 0.664 * AIR_K * AIR_PR ** (1.0 / 3.0) / math.sqrt(AIR_NU * length)
    return {
        "still_air_w_per_k": q(still, "W/K", "estimated",
                               f"h_nat·A with h_nat = 5 W/(m²·K) (Incropera & DeWitt, Fundamentals of Heat and Mass "
                               f"Transfer, Table 1.1: free convection of gases 2–25 W/(m²·K)) and A = {area:.6f} m² "
                               f"from the {dims_kind} box"),
        "forced_w_per_k_per_sqrt_mps": q(forced, "W/(K·(m/s)^0.5)", "derived",
                                         "A·0.664·k·Pr^(1/3)/sqrt(ν·L): laminar flat-plate average Nusselt number "
                                         "Nu_L = 0.664·Re_L^0.5·Pr^(1/3) (Incropera & DeWitt eq. 7.30) with air at "
                                         "300 K k = 0.0263 W/(m·K), ν = 15.89e-6 m²/s, Pr = 0.707 (Table A.4), "
                                         f"L = pack length {length:.4f} m; installation airflow not included"),
    }


def lipo_pack(pack_id: str, series: int, capacity_ah: float, c_rating: int, template: dict, template_sha: str) -> dict:
    ref_ah = template["reference_capacity_ah"]["value"]
    pack_tables = ecm.normalize(_probe_pack(template, series, capacity_ah), template)
    r0_t = ecm.lookup(pack_tables.r0, 0.5, 298.15)          # template R0 (unscaled) at 50 % SOC, 298.15 K
    scale = ANCHOR_R0_OHM * ANCHOR_CAPACITY_AH / (ref_ah * r0_t)
    ratio = (series * capacity_ah) / (4 * ANCHOR_CAPACITY_AH)
    timber = pack_id == "lipo-4s1p-3200-30c-class"
    mass = TIMBER_MASS_KG if timber else TIMBER_MASS_KG * ratio
    cell_scale = (capacity_ah / ANCHOR_CAPACITY_AH) ** (1.0 / 3.0)
    dims = list(TIMBER_BOX_M) if timber else [TIMBER_BOX_M[0] * cell_scale, TIMBER_BOX_M[1] * cell_scale,
                                               TIMBER_BOX_M[2] * cell_scale * series / 4.0]
    capacity_source = ("EFL105250B manual: recommended battery 14.8V 3200mAh 30C 4S LiPo; class label capacity"
                       if timber else f"class label capacity {capacity_ah * 1000:.0f} mAh (class definition)")
    return {
        "format": ecm.PACK_FORMAT,
        "id": pack_id,
        "display_name": f"{series}S {capacity_ah * 1000:.0f} mAh LiPo ({c_rating}C class)",
        "class_note": ("Class estimate, not an identified product: the BAK LP-503562 cell shape (Galeotti fit) "
                       "with resistance set by a literature per-cell anchor; mass and box scaled from the Timber "
                       "4S 3200 anchor. Tier A shape, class-level magnitudes."),
        "chemistry": "lipo",
        "cell_template": {"id": template["id"], "sha256": template_sha},
        "series": series,
        "parallel": 1,
        "rated_capacity_ah": q(capacity_ah, "Ah", "manual", capacity_source),
        "resistance_scale": q(scale, "1", "estimated",
                              ANCHOR_SOURCE + f" resistance_scale = 5.0 mOhm·3.2 Ah / (reference capacity "
                              f"{ref_ah:.6g} Ah · template R0(0.5, 298.15 K) {r0_t * 1000:.6g} mOhm); the RC branches "
                              "scale by the same factor"),
        "interconnect_resistance_ohm": q(LEADS_OHM, "ohm", "estimated",
                                         "2 x 10 cm 12 AWG leads (5.2 mOhm/m, about 1.0 mOhm) plus an XT60-class "
                                         "connector pair (0.5–1 mOhm); balance taps carry no load current"),
        "mass_kg": q(mass, "kg", "derived",
                     TIMBER_MASS_SOURCE if timber else
                     f"{TIMBER_MASS_SOURCE}, scaled by series·capacity {series}·{capacity_ah:g} Ah / (4·3.2 Ah) "
                     "(same cell family and packaging)"),
        "dimensions_m": q(dims, "m", "estimated",
                          TIMBER_BOX_SOURCE if timber else
                          f"{TIMBER_BOX_SOURCE}, scaled: cell length and width by (Q/3.2 Ah)^(1/3), stack height by "
                          "(series/4)·(Q/3.2 Ah)^(1/3) (cell volume ∝ capacity, stacked cells)"),
        "heat_transfer": heat_transfer(dims, "Timber anchor" if timber else "scaled class"),
        "label": {"c_rating_continuous": c_rating, "c_rating_burst": None,
                  "source": "class label, informative only; never a resistance or a current limit"},
    }


def hg2_pack(pack_id: str, series: int, parallel: int, template: dict, template_sha: str) -> dict:
    ref_ah = template["reference_capacity_ah"]["value"]
    cells = series * parallel
    mass = cells * (HG2_CELL_MASS_KG + HG2_ALLOWANCE_PER_CELL_KG) + HG2_ALLOWANCE_PACK_KG
    dims = [series * HG2_CELL_DIAMETER_M + 0.003, HG2_CELL_LENGTH_M + 0.003, parallel * HG2_CELL_DIAMETER_M + 0.0025]
    wiring = (series - 1) * HG2_STRIP_OHM / parallel + LEADS_OHM
    return {
        "format": ecm.PACK_FORMAT,
        "id": pack_id,
        "display_name": f"{series}S{parallel}P LG HG2 Li-ion ({3000 * parallel} mAh nominal)",
        "class_note": ("Identified cell (LG INR18650HG2, Kollmeyer dataset fit); pack assembly (interconnects, wrap, "
                       "leads) and box are estimates. Each parallel group is one equivalent cell."),
        "chemistry": "liion",
        "cell_template": {"id": template["id"], "sha256": template_sha},
        "series": series,
        "parallel": parallel,
        "rated_capacity_ah": q(ref_ah * parallel, "Ah", "measured",
                               f"{parallel} x template reference capacity {ref_ah:.6g} Ah ({KOLLMEYER_DOI}, C/20 to "
                               "2.8 V at 25 °C); LG nominal 3.0 Ah per cell to 2.0 V"),
        "resistance_scale": q(1.0, "1", "derived",
                              "real cell: template resistances apply unscaled; the capacity normalisation "
                              "reference/rated = 1/parallel gives the parallel-group resistance"),
        "interconnect_resistance_ohm": q(wiring, "ohm", "estimated",
                                         f"{series - 1} series nickel-strip joints (0.15 x 8 mm, 20 mm, about 1.2 "
                                         f"mOhm each) / {parallel} parallel strip(s) plus 2 mOhm leads and XT60-class "
                                         "connector"),
        "mass_kg": q(mass, "kg", "estimated",
                     f"{cells} x 48.0 g cell ({LG_SPEC}: weight max 48.0 g; a retailer weighed 44.86 g) + {cells} x 6 g "
                     "strip/insulation/wrap + 15 g leads, connector and balance lead (allowances estimated)"),
        "dimensions_m": q(dims, "m", "estimated",
                          f"{series} cells side by side x {parallel} layer(s), cell 18.5 mm x 65.2 mm max ({LG_SPEC}) "
                          "plus 2.5–3 mm wrap"),
        "heat_transfer": heat_transfer(dims, "estimated"),
        "label": {"c_rating_continuous": 20.0 / 3.0, "c_rating_burst": None,
                  "source": f"{LG_SPEC}: max. continuous discharge 20 A per cell / 3.0 Ah nominal; informative only"},
    }


def _probe_pack(template: dict, series: int, capacity_ah: float) -> dict:
    pack = ecm.single_cell_pack(template)
    pack["series"] = series
    pack["rated_capacity_ah"] = q(capacity_ah, "Ah", "derived", "probe")
    return pack


# ---------------------------------------------------------------------------------------------
# Build, check
# ---------------------------------------------------------------------------------------------

def build(fit: dict) -> dict:
    """Return {path: bytes} for every generated file."""
    out = {}
    lipo = r12(lipo_template(fit))
    hg2 = r12(hg2_template(fit))
    lipo_bytes, hg2_bytes = dumps(lipo), dumps(hg2)
    out[CELL_DIR / f"{LIPO_ID}.json"] = lipo_bytes
    out[CELL_DIR / f"{HG2_ID}.json"] = hg2_bytes
    for pack_id, series, cap, c_rating in LIPO_CLASSES:
        out[PACK_DIR / f"{pack_id}.json"] = dumps(lipo_pack(pack_id, series, cap, c_rating, lipo, sha256(lipo_bytes)))
    for pack_id, series, parallel in HG2_PACKS:
        out[PACK_DIR / f"{pack_id}.json"] = dumps(hg2_pack(pack_id, series, parallel, hg2, sha256(hg2_bytes)))
    validate(out)
    return out


def validate(files: dict) -> None:
    """Every pack must normalise in the independent reference; LiPo classes must hit the resistance anchor."""
    cells = {json.loads(b)["id"]: json.loads(b) for p, b in files.items() if p.parent == CELL_DIR}
    for path, data in files.items():
        if path.parent != PACK_DIR:
            continue
        pack = json.loads(data)
        template = cells[pack["cell_template"]["id"]]
        tb = dumps(template)
        if sha256(tb) != pack["cell_template"]["sha256"]:
            raise SystemExit(f"{path.name}: template pin mismatch")
        norm = ecm.normalize(pack, template)
        if pack["chemistry"] == "lipo":
            r0 = norm.resistance_factor * ecm.lookup(norm.r0, 0.5, 298.15)
            expected = ANCHOR_R0_OHM * ANCHOR_CAPACITY_AH / pack["rated_capacity_ah"]["value"]
            if abs(r0 / expected - 1.0) > 1e-9:
                raise SystemExit(f"{path.name}: R0 anchor {r0} != {expected}")
        if pack["id"] == "lipo-4s1p-3200-30c-class" and pack["mass_kg"]["value"] != TIMBER_MASS_KG:
            raise SystemExit("Timber class pack mass must be exactly 0.33 kg")


def check_inputs(fit: dict) -> list:
    """Verify input sha256 of the fit against the local references (if present). Returns problems."""
    if not REFERENCES.is_dir():
        print("references/battery-energy not present: input hash check skipped (fit_results consistency only)")
        return []
    problems = []
    g_dir = REFERENCES / "galeotti-lipo-dataset"
    k_dir = REFERENCES / "kollmeyer-hg2-dataset"
    g_fetched = {(e["folder"], e["file"]): e["sha256"] for e in json.loads((g_dir / "fetched.json").read_text())}
    k_fetched = {e["local"]: e["sha256"] for e in json.loads((k_dir / "fetched.json").read_text())}
    for e in fit["inputs"]["lipo"]:
        folder, name = e["file"].split("/")
        path = g_dir / folder[:8] / name
        if g_fetched.get((folder, name)) != e["sha256"]:
            problems.append(f"{e['file']}: sha256 differs from fetched.json")
        elif not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != e["sha256"]:
            problems.append(f"{e['file']}: local file missing or changed")
    for e in fit["inputs"]["liion"]:
        path = k_dir / e["file"]
        if k_fetched.get(e["file"]) != e["sha256"]:
            problems.append(f"{e['file']}: sha256 differs from fetched.json")
        elif not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != e["sha256"]:
            problems.append(f"{e['file']}: local file missing or changed")
    n = len(fit["inputs"]["lipo"]) + len(fit["inputs"]["liion"])
    print(f"input hashes: {n - len(problems)}/{n} match fetched.json and the local files")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="compare generated bytes with the files on disk")
    args = ap.parse_args()
    fit = json.loads(FIT_RESULTS.read_text(encoding="utf-8"))
    files = build(fit)
    if args.check:
        problems = check_inputs(fit)
        for path, data in sorted(files.items()):
            if not path.is_file():
                problems.append(f"missing {path.relative_to(REPO)}")
            elif path.read_bytes() != data:
                problems.append(f"differs: {path.relative_to(REPO)}")
        expected = {p.name for p in files}
        for folder in (CELL_DIR, PACK_DIR):
            for extra in sorted(folder.glob("*.json")) if folder.is_dir() else []:
                if extra.name not in expected:
                    problems.append(f"not generated: {extra.relative_to(REPO)}")
        for p in problems:
            print("FAIL", p)
        print("check: OK" if not problems else f"check: {len(problems)} problem(s)")
        return 1 if problems else 0
    for path, data in sorted(files.items()):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        print(f"{sha256(data)}  {path.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
