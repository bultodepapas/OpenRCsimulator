# NITRO-61FX — O.S. MAX-61FX research dossier

2026-10-14 · **Status: implemented as proposed, with one change.** `build_profiles.py` generates `os_max_61fx_candidate`, and `build_installations.py` generates `stik_61fx_2t.json` and the catalog aircraft `stik-glow-61fx-2t` (experimental). The change: the profile adds an explicitly inferred tail knot at 20,000 rpm (torque 0.45 × 9.95/8.93 N·m, delivery 0.85, trapping 0.66). Without it, a full-throttle dive on the APC 12×6 unloaded past the 17,000 rpm support and faulted the simulation at 36 m/s. With the tail the same 6 s dive peaks at 18,391 rpm, without a fault. 17,000 rpm stays the manufacturer limit that telemetry flags, as the FS-64V's inferred 15,000 rpm tail already does. Steady full-throttle rpm: 12,550 / 12,847 / 14,158 / 16,168 / 18,090 at 0 / 10 / 20 / 30 / 40 m/s. Runway takeoff and prop-strike gate: `test_prop_strike.gd`. The MAX-61FX is the engine named by the default [Jensen Das Ugly Stik 60](../../../../app/data/aircraft/jensen_ugly_stik_60.json). This dossier mirrors the ten areas and evidence discipline of the [MAX-55AX dossier](../NITRO-2T/README.md) and the [active plan](../../../plans/RC_NITRO_ENGINE_REALISM_PLAN.md). Every candidate profile remains owned by [`build_profiles.py`](../../../../research/glow-engines/build_profiles.py) and every installation by [`build_installations.py`](../../../../research/glow-engines/build_installations.py).

Evidence kinds follow the aircraft contract: `manual` (manufacturer), `measured` (instrumented test by the named source), `borrowed` (another article/engine/prop), `estimated`, `derived`. The plan's rule applies: forum anecdotes can identify a question, but cannot close a numerical gate.

## Identity and baseline configuration

| Item | Value | Kind | Source |
| --- | --- | --- | --- |
| Model / code | O.S. MAX-61FX, code 17750; ABC (non-ringed) crankcase-scavenged 2T glow, naturally aspirated | manual | [O.S. JP catalog 17750](https://www.os-engines.co.jp/line_up/engine/air/aircraft/catalog/17750.htm); [manual](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/manual/50sx_40-91fx.pdf) |
| Production status | "現在この機種は販売いたしておりません" (no longer sold) | manual | JP catalog 17750 |
| Successor | MAX-65AX is presented "61FXの後継機種として" (as the 61FX successor) | manual | [O.S. 65AX page](https://www.os-engines.co.jp/line_up/engine/air/aircraft/catalog/Responsive/65la_16520_16521/index.html) |
| Displacement | 9.95 cm³ (0.607 cu in) | manual | catalog; manual PDF p. 21 (printed p. 41) |
| Bore × stroke | 24.0 mm × 22.0 mm; π/4·24²·22 = 9.9526 cm³, consistent with the stated 9.95 cm³ | manual / derived | same |
| Rated output | 1.9 PS at 16,000 rpm = **1,397.447625 W**; torque at that speed **0.834040 N·m** | manual / derived | same; PS × 735.49875 W |
| Practical speed range | 2,000–17,000 rpm | manual | catalog EN/JP; manual PDF p. 21 |
| Mass | 550 g (19.42 oz), engine | manual | catalog EN/JP; manual PDF p. 21 |
| Carburetor | Type 60C (code 27783000), rear needle valve plus mixture-control screw | manual | catalog JP; manual PDF p. 8 |
| Silencer | E-4010 (code 26028000); optional T-4010 tuned silencer | manual | manual PDF pp. 4, 19–20 |
| Plug | O.S. No.8 supplied; Nos. 8, A5 and A3 recommended | manual | manual PDF pp. 7, 9 |
| Crankshaft thread | UNF 5/16-24 | manual | manual PDF p. 21 drawing |
| Overall dimensions | height 100.5 mm; lug width 61 mm (43 mm inside); 66.5 + 29.1 mm length from drive washer datum | manual | manual PDF p. 21 drawing |
| Suggested tank | approx. 350 cm³ (12 oz) | manual | manual PDF pp. 7, 9 |
| Fuel | 5–20 % nitromethane preferable; **at least 18 %** lubricant by volume (castor, synthetic or blend) | manual | manual PDF p. 8 |
| Sport propellers | 12×6–8, 13×6–7; "Suggested size … 12X6 (50SX, 61FX)" | manual | manual PDF pp. 8, 9 |
| Silencer mass | E-4010 not published. Sibling **E-4010A: 156 g** | manual (E-4010A only) | O.S. 65AX page |

The 65AX (code 16520/16521) is a different engine: 10.63 cm³, 24.0 × 23.5 mm, 1.75 PS at 16,000 rpm, 497 g, sport props 12×6, 13×6–7, 14×6 ([O.S. 16520](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/catalog/16520.htm)). A dealer states it has "the same construction dimensions as the classic OS MAX 61FX" ([Lindinger](https://www.lindinger.at/en/AIRPLANES/GAS-GLOW-POWERPLANTS/Engines/OS-MAX-65-AX-WITH-SILENCER/90242)); that is a dealer claim about installation dimensions, not O.S. data and not evidence of equal performance. No 65AX value is used below.

### Source register

Downloaded 2026-10-14 into a scratch directory and treated as untrusted data; text read with `pdftotext`. Page numbers are PDF pages.

| Document | Identity | SHA-256 |
| --- | --- | --- |
| O.S. Japan manual `50sx_40-91fx.pdf`, MAX-50SX/40/46/61/91FX, 22 A4 pages (two printed pages each), created 2011-06-22 | [os-engines.co.jp](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/manual/50sx_40-91fx.pdf), linked from the EN catalog page | `c7562fb37bfcc5d082a0c1322d0f303d89968e5042aebd8de976ae846313198e` |
| Hobbico/O.S. US manual `50sx-40-46-61-91fx-manual.pdf`, 43 pages, created 2002-01-08 | [manuals.hobbico.com](http://manuals.hobbico.com/osm/50sx-40-46-61-91fx-manual.pdf) | `31d59067ed7a89902ace9095f2b93e85c2b7acba7bfef21620ea848f7b876a9e` |
| O.S. 17750 exploded view and parts list, 1 page, created 2003-06-13 | [os-engines.co.jp pdf/17750.pdf](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/pdf/17750.pdf) | `0c563ada4157a8181a6913fae72a508d5bd2d428d65666d88d888c80faa361ee` |
| O.S. EN catalog page 17750 (HTML, as retrieved) | [EN 17750](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/catalog/17750.htm) | `6b2dc3a97c977f75fbe63adb96a9b76d708461a324cf205f98dc908f37eafd6b` |
| O.S. JP catalog page 17750 (HTML, Shift-JIS, as retrieved) | [JP 17750](https://www.os-engines.co.jp/line_up/engine/air/aircraft/catalog/17750.htm) | `b47e92fd15cefb886187dd1ea6cd96b90d1fac7c711f29014dd5d5f88d1b787a` |
| Motion RC LP12060 page (HTML, as retrieved) | [Motion RC](https://motionrc.com/products/apc-12x6-gas-propeller-lp12060) | `0d4e39ceba40ef7a98ff9b1e3b6c4095ae136e21970acf8965cc585eb6b9e1c7` |

HTML hashes identify the retrieved bytes only; dynamic pages change. Not retrievable on 2026-10-14: apcprop.com (HTTP 403, Cloudflare, as already recorded in [DECISIONS](../../../DECISIONS.md)), rcuniverse.com threads (HTTP 403), journals.sagepub.com (HTTP 403), web.archive.org (blocked/429).

### Recorded conflicts (not averaged)

| Topic | Values | Resolution |
| --- | --- | --- |
| Rated power unit | EN catalog "1.9ps/1.87hp"; O.S. JP manual "1.9 ps / 1.93 hp"; Hobbico manual "1.9 bhp"; AMain "1.90 @ 16,000" | 1.9 PS is the common manufacturer value. 1.9 PS = 1.874 mechanical hp, so the EN catalog is arithmetically consistent and "1.93 hp" and "1.9 bhp" are not. Use 1.9 PS. |
| Independent power | Dave Gierke, *Model Airplane News*, May 2003 ".61 shootout", torque beams, stock muffler: **1.24 hp at 13,000 rpm peak** (924.7 W, 0.679 N·m) | **Secondhand only**: from search-engine excerpts of RCU threads ([1](https://www.rcuniverse.com/forum/glow-engines-114/3199487-best-prop-correct-spinner-size-os-61-fx.html), [2](https://www.rcuniverse.com/forum/glow-engines-114/1638558-os-61-fx-proper-rpms.html), [3](https://www.rcuniverse.com/forum/glow-engines-114/658065-model-airplane-news-60-engine-comparison.html)); the article and threads were not read. If confirmed, it is a `measured` installed-muffler peak 34 % below the rating and 3,000 rpm lower. |
| Plug wording | O.S. JP: No.8 "supplied"; Hobbico: No.8 "fitted to the engine" | Same plug. Wording only. |
| Mass with silencer | 550 g engine (all O.S. sources); AMain "19.4" with no unit or muffler scope | 550 g is the bare engine. The E-4010 mass is unknown. |
| Prop bore | 61FX shaft 5/16-24 (manual); Motion RC lists APC LP12060 shaft diameter 6.35 mm / 0.25 in | The prop needs a 5/16 in (7.94 mm) bore. This is a fit question. APC's own page could not be read. |

### Published static-rpm observations

None is a manufacturer or instrumented measurement. All come from search-engine excerpts of RCU threads that returned HTTP 403, so poster, date and exact thread are **unverified**. Kind: anecdote, not usable as a calibration anchor.

| Prop | Reported rpm | Stated conditions |
| --- | ---: | --- |
| APC 12×6 | 11,500 | 15 % fuel, stock muffler |
| APC 12×6 | "about 12K" | none |
| APC 12×6 | 10,400 | 15 % nitro, restrictive Pitts muffler |
| APC 11×7 | 12,600; MA 11×7 12,800; "about 13K" | 15 % fuel, stock muffler |
| APC 13×4 | 11,000–12,000 | "not fully tuned"; 20 % fuel |
| APC 12.25×3.75 | 13,100; 14,000 after Tower muffler and porting | modified exhaust |

A *Model Aviation* Seawind .60 article mentions an O.S. .61FX option. It also says "two-stroke installations can use a 12x6 two-blade APC". It gives no rpm ([MA 2008/07](https://library.modelaviation.com/article/plane-talk-great-planes-seawind-60-arf-200807)). No APC or Master Airscrew test sheet for this engine was found.

## Ten-area record

### 1. Torque and power

Only **1.9 PS at 16,000 rpm** is anchored by the manufacturer: 0.834040 N·m at that speed and nowhere else. The 1.24 hp at 13,000 rpm Gierke figure is the only reported independent measurement. It is secondhand and conflicts strongly (above). Rated BMEP is 2π·Q/V = **526.7 kPa**, against 525.1 kPa for the MAX-55AX rating (+0.31 %). That near equality is the only justification used below for scaling the 55AX torque hypothesis by displacement. It is a similarity assumption, not a measured curve. The current legacy Stik model assumes engine power is linear in rpm below the rating. That is also an estimate.

### 2. Throttle response

Dias, Violato & Martins, "Dynamic model of a two-stroke glow engine from experimental data", *Proc. IMechE Part G* 226(12):1502–1512, 2011 ([DOI 10.1177/0954410011426371](https://doi.org/10.1177/0954410011426371); metadata confirmed via Crossref). They used a thrust/rpm test bed, a hobby servo and output-error identification of servo + engine models in series. The [NITRO-2T dossier](../NITRO-2T/README.md#2-throttle-response) records the engine as a **MAX-61FX**, an APC 13×4 and 10 % nitro. It also records a first-order engine model near `550/(s+4)`, **τ ≈ 0.25 s**, identified around 7,000–11,000 rpm. The full text was not re-read in this pass (publisher HTTP 403). Kind: `measured` for that installation and prop. It is the only engine-specific transient evidence. The Stik's current `lag_time_constant` 0.25 s is labelled `estimated`. It matches this figure but does not cite it.

### 3. Combustion dynamics

One opportunity per revolution: **33.3–283.3 Hz** over 2,000–17,000 rpm, 266.7 Hz at rating. The manual describes the "four-cycle" (rich, missing) to "two-cycle" transition during running-in (PDF p. 10). It gives no misfire boundary or cycle variation. Nothing engine-specific beyond the 55AX dossier.

### 4. Propeller compatibility

The O.S. range is 12×6–8 and 13×6–7, and 12×6 is the single "suggested size". The current Stik prop, **APC 12×6 Sport LP12060**, is therefore the manufacturer-suggested size. Its mass is 1.62 oz = **45.926 g** (APC as already cited in the Stik inventory; Motion RC 45.9 g). The APC glow/Sport ceiling is 190,000/12 = **15,833 rpm** ([APC rule](https://www.apcprop.com/technical-information/rpm-limits/), as used by `build_installations.py`, not re-read). That ceiling lies below the 16,000 rpm rating knot and the 17,000 rpm practical limit. The bore must be opened to 5/16 in. No measured 12×6 Sport coefficients exist in the repository. The Stik uses UIUC's measured APC Sport 11×6, scaled, which is borrowed data.

### 5. Fuel consumption

There are no MAX-61FX flow measurements. The current O.S. 40–91FX manual says a 350 cc tank "will allow 12–13 minute flights" on the 61FX, which implies about 27–29 ml/min at mixed throttle ([FUEL-00 §6.2](../../fuel-systems/FUEL-00/README.md#62-consumption); manufacturer statement, not a full-throttle flow). The candidate (below) delivers **38.8 ml/min at its 10,976 rpm static UIUC-law root**, 46.0 ml/min at 12,550 rpm and 58.1 ml/min at 16,000 rpm, equal to the runtime law in `two_stroke.gd`. That is 9.0, 7.6 and 6.0 min per 350 cm³ at full throttle. These are model outputs. The 65AX manual's "10–12 minutes" ([initial notebook](../../initial-notebook.md)) is another engine at mixed throttle, so it is context only.

**Correction, 2026-10-19 (FUEL-01c).** This section previously gave 29.5 / 35.0 / 43.0 ml/min and 11.9 / 10.0 / 8.1 min. `calibration_report.evaluate` metered premix on the *trapped* air, while the runtime meters it on the *delivered* air; trapping limits only the burned charge. The mirror now matches the runtime, and its new regression test detects the old formula. Burned fuel, torque and power were unaffected.

### 6. Idle and stalling

The manual gives no idle rpm. Its idle chart (PDF p. 12) sets the "lowest possible r.p.m. with steady idling". It also describes rich idling as unstable rpm and smoke, and lean idling as cutting out when the throttle opens. The practical lower limit is **2,000 rpm**. The Stik's 2,800 rpm `idle_rpm` is an estimate inside that range. The MAX-55AX 1,800 rpm field observation does not transfer.

### 7. Temperature and cooling

No MAX-61FX data. The manual says only that ABC engines are fitted tight at TDC when cold and reach running clearance when hot (PDF p. 4), and warns against lean running.

### 8. Sound and vibration

Kinematic lines: firing 33.3–283.3 Hz; two-blade blade-pass 66.7–566.7 Hz over the practical range. At the 10,976–12,550 rpm static candidates these are 183–209 Hz and 366–418 Hz. There are no calibrated levels, and no measured mount vibration.

### 9. Aircraft dynamics

Geometric pitch speed for the 12×6 is `rpm × 6 / 1056` mph: 62.4, 65.3 and 71.3 mph at 10,976, 11,500 and 12,550 rpm. That is not airspeed or thrust. No 61FX flight telemetry was found.

### 10. Configuration and provenance

The baseline is a stock MAX-61FX with the E-4010 silencer, No.8 plug, 60C carburetor, APC 12×6 Sport reamed to 5/16 in, and 10/18 % nitro/oil fuel inside the manual's bounds. The Stik inventory cites "O.S. catalog 17750 (RESEARCH.md)". `RESEARCH.md` no longer exists at the repository root. The text now lives in the [initial notebook](../../initial-notebook.md), so the provenance path has drifted. Changing that path belongs to the aircraft owner.

## Proposed candidate profile

Proposed id `os_max_61fx_candidate`; `format openrc-glow-engine v1`, `manufacturer O.S. Engines`, `model MAX-61FX`, `family glow_2t`, `status candidate`, `feed naturally_aspirated`, `oil_model inert`. RPM knots are the 55AX grid `[0, 2000, 4000, 7000, 10000, 13000, 16000, 17000]`. That grid is justified because the 61FX shares the 2,000–17,000 rpm practical range and the 16,000 rpm rating. `k = 9.95/8.93 = 1.1142217` is the displacement ratio. "55AX rule" means the build_profiles.py formula reused unchanged.

| Field | Proposed value | Kind | Provenance / derivation |
| --- | --- | --- | --- |
| `displacement_m3` | 9.95e-6 | derived | catalog 17750; cm³ × 1e-6 |
| `bore_m` | 0.024 | manual | catalog 17750; manual PDF p. 21 |
| `stroke_m` | 0.022 | manual | same |
| `rod_to_crank_radius_ratio` | 3.5 | estimated | 55AX rule; no 61FX rod length published (part 29505000, no dimension) |
| `reciprocating_mass_kg` | 0.01375 | estimated | 55AX rule: 2.5 % of 550 g manual mass |
| `mechanical_torque_nm` | `k·(0.008 + 2e-6·rpm)` → 0.008914 … 0.044569 at 16,000, 0.046797 at 17,000 | estimated | 55AX friction law scaled by displacement (constant-FMEP assumption) |
| `combustion_efficiency` | same as 55AX | estimated | mixture law; not engine-specific |
| `delivery_ratio` | same as 55AX | estimated | no 61FX port timing or crankcase data |
| `trapping_efficiency` | same as 55AX | estimated | same |
| `scavenge_pressure_pa` | same as 55AX (2000 + 0.4·rpm) | estimated | same |
| WOT brake-torque hypothesis (generator input `q`) | `[0, 0.20056, 0.33427, 0.57940, 0.77996, 0.86909, 0.834040, 0.77996]` N·m | estimated; rated knot derived | 55AX knots × k; 16,000 knot = 1.9 PS / ω exactly. Justified only by equal rated BMEP (±0.3 %) |
| `indicated_efficiency` | `[0.006001, 0.094851, 0.120713, 0.161481, 0.178030, 0.185711, 0.188891, 0.190487]` | derived | build_profiles inversion; equals the 55AX curve except the rated knot (0.18835 → 0.188891), because every loss scales by k |
| `fuel.*` (9 fields) | same as 55AX: 10 % nitro, 18 % oil, AIAA Table 1 properties | borrowed | the 10/18 blend lies inside the 61FX manual bounds (5–20 % nitro, ≥18 % oil, PDF p. 8) |
| `operation.max_rpm` | 17000 | estimated | last knot (55AX rule) |
| `operation.rated_rpm` | 16000 | manual | catalog 17750 |
| `operation.rated_power_w` | 1397.447625 | derived | 1.9 PS × 735.49875 |
| `operation.reference_dry_density_kg_m3` | 1.225 | estimated | 55AX rule |
| `operation.nominal_mixture` | 1.15 | estimated | 55AX rule |
| `operation.recommended_max_rpm` | 17000 | manual | practical range upper limit |

Resulting candidate brake output (mean-cycle reconstruction via `calibration_report.evaluate`): 42.0 W @ 2,000; 424.7 W @ 7,000; 816.8 W @ 10,000; **1,183.1 W @ 13,000**; 1,397.4 W @ 16,000; 1,388.5 W @ 17,000. The 13,000 rpm value is 28 % above the secondhand Gierke peak (924.7 W). If that article is confirmed, the profile owner should decide whether a muffler-installed variant is needed. It is recorded, not blended.

To generate this, `build_profiles.py` needs a model-keyed table. Today `candidate()` and `outputs()` key one engine per family. The owner of that file would add this.

### Static-rpm cross-check with the APC 12×6 (sea-level ρ = 1.225 kg/m³)

| Method | Static rpm | Thrust | Note |
| --- | ---: | ---: | --- |
| Legacy Stik: linear power, Cp 0.0471 | 11,148 | — | reproduces the JSON's `max_rpm_static` 11,149 (derived) |
| Candidate curve + Stik UIUC 11×6 Cp/Ct tables | **10,976** | 40.0 N | borrowed coefficients; Cp is linear between J = 0 and 0.373 (unmeasured), so rpm falls to 10,850/10,726 at 10/20 m/s |
| Candidate + annular surrogate, 55AX-transferred chord 21.136 mm, 2T section (5.5/rad, cd0 0.022, induced 0.06) | **12,550** | 56.1 N | momentum screen accepted (1.131) |
| Anecdotes (unverified) | 10,400–12,000 | — | see table above |

The surrogate with the transferred chord has stable roots at 12,550 / 12,847 / 14,158 / **16,168 rpm** at 0/10/20/30 m/s. The 30 m/s root exceeds the APC 15,833 rpm ceiling, so the cap/telemetry flag must stay. Fitting the chord to the UIUC static root needs 26.114 mm, and that static point **fails** the 5 % actuator-disk screen (1.018). Fitting it to the 11,500 rpm anecdote needs 24.244 mm, which passes (1.056) and gives 11,500 / 11,860 / 13,516 / 15,657 rpm. That is shown only as a sensitivity: a forum anecdote cannot anchor it.

## Proposed installation

Build `max61fx_apc_sport_12x6` → `stik_61fx_2t.json` and `stik_glow_61fx_2t.json`. It keeps the Stik's current prop size and the O.S. suggested size. An alternate, `_apc_13x6`, stays in the O.S. range with ceiling 14,615 rpm, chord 22.898 mm and no 61FX observation.

| Field | Proposed | Kind | Basis |
| --- | --- | --- | --- |
| `profile` | `res://data/glow/os_max_61fx_candidate.json` | — | above |
| lifecycle `settings` and `thermal` | 55AX 2T values unchanged | estimated | no 61FX data; scaling heat capacity by mass (550/404 → 190.6 J/K) is a sensitivity, not proposed |
| `propeller.max_rpm` | 15,833.3 | derived | APC 190,000/12 |
| `diameter_m`, `pitch_m` | 0.3048, 0.1524 | estimated (nominal) | APC 12×6 |
| `chord_m` | 0.0211364 | estimated | transferred c/D from the 55AX 12×7 O.S. observation. This is a different engine and pitch. The surrogate predicts 12,550 rpm static, above every 61FX indication |
| `blades`, `lift_slope`, `cd0`, `induced_drag` | 2, 5.5, 0.022, 0.06 | estimated | 2T rule; passes the momentum screen with this chord |
| inventory engine mass | 0.550 kg | manual | catalog 17750 |
| inventory silencer | E-4010, 0.150 kg | estimated | current Stik value; sibling E-4010A 156 g (manual) |
| inventory prop | APC Sport LP12060 12×6, 0.0459262 kg | manual | 1.62 oz × 0.028349523125 kg/oz |
| `crank_polar` | 2e-5 kg·m² | estimated | 2T rule |
| `engine.max_rpm_static` | replace the 2T hard-coded 13,000 with the computed static root | derived | legacy field |
| `engine.idle_rpm` | 2,800 | estimated | inside the manual's 2,000 rpm practical lower limit |

Required builder changes, for the owner of `build_installations.py`, not made here:

1. The 2T branch hard-codes 55AX engine (0.404 kg) and silencer (0.121 kg) masses.
2. The `two and diameter_in == 12` branch would give a 12×6 the **LP12070 mass and URL**. The builder needs a per-SKU table.
3. Profile and tag selection is keyed by family, not model.

## Evidence still required

| Evidence | Status |
| --- | --- |
| Primary text of Gierke, MAN May 2003 (torque/hp vs rpm, fuel, muffler, props) | Not acquired; highest-value public source |
| Tach-measured static rpm of the actual 61FX + APC 12×6 (reamed), fuel, plug, muffler, temperature, pressure | Not acquired; it would replace the transferred chord |
| Measured APC 12×6 Sport Ct/Cp (or APC PER3 file) | Not acquired (apcprop.com 403) |
| Full text of Dias et al. (servo/engine split, rpm range, fuel) | Metadata only this pass |
| E-4010 mass; weighed engine + silencer | Not acquired |
| Throttle steps, idle/stall boundary, flow, head temperature, sound, vibration, flight telemetry | Not acquired |

The numbers above come from an in-memory probe that imports `build_profiles.py` and `calibration_report.py` unchanged. It applies the table's formulas and writes nothing. The probe is not committed. Regenerate through the owners' generators once they adopt a profile.
