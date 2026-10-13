# NITRO-2T — O.S. MAX-55AX inferred calibration dossier

2026-10-13 · **Status: quantified candidate inference; physical calibration, held-out validation and pilot acceptance remain open.** This dossier addresses all ten research areas in [the active plan](../../../plans/RC_NITRO_ENGINE_REALISM_PLAN.md). The generated [candidate profile](../../../../app/data/glow/os_max_55ax_candidate.json) remains owned by [`build_profiles.py`](../../../../research/glow-engines/build_profiles.py); do not edit it here. The companion [inference report](calibration_report.json) is regenerated from the profile by [`calibration_report.py`](../../../../research/glow-engines/calibration_report.py).

## Identity and baseline configuration

The baseline is O.S. MAX-55AX, product 15612, single-cylinder, naturally aspirated, crankcase-scavenged two-stroke glow ignition, 8.93 cm³, 23.0 mm bore × 21.5 mm stroke, Type 40K carburetor and supplied No.8 plug. O.S. publishes 1.7 PS at 16,000 RPM, practical engine speed 2,000–17,000 RPM, sport propeller sizes 12×7–8 and 13×6–7 inches, and 404 g bare engine mass ([O.S. product page](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/catalog/15612.htm)). The current candidate treats the rating as 1,250.347875 W and derives 0.7463 N·m at that exact speed. The rating is one constraint; it does not locate the torque peak or provide an engine map.

The included baseline exhaust is the stock O.S. silencer. Mass sources do not align perfectly: an archived O.S. catalogue lists 404 g engine + 120 g E-3070 silencer (=524 g); AIAA 2016-5011 lists its MAX-55AX test article as 404 g without and 525 g with muffler; the older O.S. launch page reports 542 g for an earlier launch configuration and 1.75 PS. Use **525 g as the research test-assembly reference with a 524–542 g source envelope**, identify the actual replacement muffler, then weigh the installed assembly. Do not label the legacy 542 g / 1.75 PS entry as the current 15612 hardware. See [O.S. archived catalogue](https://www.os-engines.co.jp/catalog_j/archive/pdf/vol_17.pdf), [AIAA paper](https://doi.org/10.2514/6.2016-5011), and [2006 launch record](https://www.os-engines.co.jp/english/2006autumn/max55ax.html).

| Build ID | Recommended prop and identified product | Direct fit / applicable cap | Evidence and use |
| --- | --- | --- | --- |
| `max55ax_apc_sport_12x7` | APC Sport LP12070, 12×7, 1/4-in (6.35 mm) shaft bore, 1.52 oz / **43.091 g** | Matches the MAX-55AX 1/4-28 prop nut. APC glow/Sport suggested maximum is 190,000/diameter = **15,833 RPM**. | O.S. field article tested exactly APC 12×7, No.8 plug, NITRO-X Standard Red (15-18), 3 °C: 10,330 RPM peak and 1,800 RPM idle. It is a single configuration/condition, not a torque map or a guaranteed idle ([O.S. article](https://www.os-engines.co.jp/web_content/202102/index1.html); [APC LP12070](https://www.apcprop.com/product/12x7/); [APC limits](https://www.apcprop.com/technical-information/rpm-limits/)). |
| `max55ax_apc_sport_13x6` | APC Sport LP13060, 13×6, 1/4-in (6.35 mm) shaft bore, 1.69 oz / **47.911 g** | Matches the 1/4-28 prop nut. APC suggested maximum is **14,615 RPM**. | O.S. lists 13×6 in its recommended sport range. No retrieved MAX-55AX run or propeller coefficient curve uses this combination ([APC LP13060](https://www.apcprop.com/product/13x6/)). |

O.S. cautions that same-size propellers differ by maker and recommends practical experimentation. APC limits are manufacturer safety ceilings, not preferred operating RPM or proof of engine/airframe suitability. Both selected APC ceilings are below the MAX-55AX 16,000-RPM power-rating knot; the engine rating remains a standalone constraint and must not override a propeller's lower speed ceiling. The APC pages describe propeller geometry/weight, not measured load coefficients for this engine.

The inference report includes a deliberately conditional **single-point chord fit** for the O.S. 10,330-RPM APC 12×7 observation. With the live candidate engine curve, the fitted torque is **0.70858259936 N·m**. At the report's **1.225 kg/m³ reference density** (the O.S. article gives 3 °C but no barometric pressure), the 12-annulus surrogate's guessed 25 mm uniform chord produces 0.83810634 N·m; scaling only chord gives **0.84545668× / 21.1364169 mm** and a zero residual by construction. This is an RPM-only conditional parameter fit, not measured engine torque or recovered APC blade geometry. For the unobserved APC 13×6, the same fitted chord/diameter ratio gives **22.8977850 mm**. The report's 19.21–23.80 mm single-point sensitivity span varies assumed section coefficients/density only; it is not a confidence interval or a bound on the actual propeller.

The paired operating predictions use the live candidate torque curves and the runtime's 12-annulus uniform-chord, no-induced-velocity propeller law. Each is full admission at the shown **axial-flow scenario speed**, not a measured flight condition. The sensitivity spans combine deliberately adverse/favorable curve, density and section cases; they are not statistical uncertainty intervals. The report excludes positive-thrust roots that fail its 5% screening margin over ideal actuator-disk power, distinguishing impossible loads from insufficient margin. See the [momentum-bound correction](../NITRO-02/README.md#momentum-bound-correction). The 12×7 static point is constrained to the O.S. observation by chord fitting; its accepted coefficients and nominal predictions are unchanged by that audit.

| Propeller | Axial speed | Candidate equilibrium RPM (scenario span) | Surrogate thrust |
| --- | ---: | ---: | ---: |
| APC 12×7 | 0 m/s | 10,330 (10,330 by construction) | 41.4 N |
| APC 12×7 | 10 m/s | 10,413 (10,413–10,801) | 32.0 N |
| APC 12×7 | 20 m/s | 11,865 (11,366–12,572) | 27.6 N |
| APC 12×7 | 30 m/s | 13,918 (13,515–14,562) | 24.1 N |
| APC 13×6 | 0 m/s | 9,651 (9,651–9,754) | 43.4 N |
| APC 13×6 | 10 m/s | 10,323 (10,323–11,174) | 33.1 N |
| APC 13×6 | 20 m/s | 12,323 (11,735–13,380) | 27.9 N |
| APC 13×6 | 30 m/s | 14,711 (14,304–15,615) | 21.6 N |

The 12×7 is the recommended **experimental installed default** because it is the only MAX-55AX prop with an O.S.-published RPM observation; the 21.136 mm chord remains an inferred surrogate input. Keep the 13×6 as an alternate build, not the default. Its nominal 30 m/s scenario exceeds APC's 14,615-RPM suggested ceiling, so any installed variant must retain that cap/telemetry flag. These outputs do not justify changing the engine torque knots: the 12×7 RPM point does not identify shaft torque independently of the assumed propeller law.

## Ten-area calibration record

### 1. Torque and power

The profile provides a numerical full-admission torque/power hypothesis at each generated RPM knot; `calibration_report.json` recalculates it from the actual current profile, cycle work, scavenging and losses. It reports the rated-power residual, candidate maxima, delivered fuel and a local sensitivity sweep. Only **1.7 PS @ 16,000 RPM** is manufacturer-anchored. Candidate intermediate points and torque-peak location are model-generated, with no confidence interval. The report's exact rated-point residual is a source/data/math identity check, not a fit residual against engine observations.

AIAA 2016-5011 independently tested a MAX-55AX in a small hybrid system using a load-cell alternator cradle and optical shaft tach. The usable MAX-55AX throttle coverage was limited to about **15% (idle) through 40% of its full control range** by the regulator. Its discussion says measured torque for both tested engines increased through about 150 W and then approached 0.35 N·m; those system-operating points are useful part-load context, not the MAX-55AX's WOT curve. Tests were at **78.2 kPa / 291.3 K**, around 10,930 ft density altitude, and are not sea-level corrections. Raw per-point values are not digitized into this profile and no AIAA residual is claimed ([AIAA 2016-5011](https://doi.org/10.2514/6.2016-5011)).

### 2. Throttle response

There is no synchronized MAX-55AX command/barrel/RPM step record in the inspected manufacturer material. A published MAX-61FX experiment, with an APC 13×4 and 10% nitro fuel, estimated a first-order engine transfer function near `550/(s+4)`, or **τ≈0.25 s**, after identifying the servo separately; the identified comparison was around 7,000–11,000 RPM. It is a useful two-stroke family prior, not a MAX-55AX measurement ([Dias, Violato & Martins, DOI 10.1177/0954410011426371](https://doi.org/10.1177/0954410011426371)). Use **0.10–0.60 s** only as an exploratory response/charge-transport sensitivity bracket around that analogue. The installed `GlowLifecycle` adds servo, air-admission and fuel-transport lag states, but the configured constants are inferred engineering assumptions, not fitted MAX-55AX rise/fall times. The separate mean-cycle profile remains a steady source model; prop/engine inertia and load balance still govern the coupled shaft response.

### 3. Combustion dynamics

One cylinder has one nominal 360° combustion opportunity per revolution: `f = RPM/60`, or **33.3–283.3 Hz** over the manufacturer's practical 2,000–17,000 RPM range; at the rated speed the order is **266.7 Hz**. O.S. describes rich two-stroke four-stroking as firing once every fourth piston stroke instead of every second, which means a successful-fire fraction near **0.5** in that described condition. It remains a ported 360° mechanical cycle; missed events do not make it a true 4T. The mean-cycle profile accepts an external firing fraction. The integrated lifecycle tracks phase/opportunities and applies an assumed smooth firing fraction versus mixture and temperature, but no MAX-55AX misfire boundary, crank-angle pressure trace, cycle variation or plug feedback was measured to set those laws. The 0.99 cm³ two-stroke experimental paper reports serious cyclic variation at micro scale; its scale is not a MAX-55AX calibration ([Shang et al., DOI 10.1177/0036850420935731](https://doi.org/10.1177/0036850420935731)).

### 4. Propeller compatibility

The two identified APC Sport combinations above are within O.S.'s diameter/pitch recommendation and have documented 1/4-in bores. APC's glow/Sport ceiling is calculated separately for each prop. The 12×7 test provides one RPM observation; the 13×6 does not. Neither prop has engine-specific APC `Ct/Cp`, static-thrust, rotating-inertia or advancing-flow data in this dossier. Use measured prop coefficients or a labeled surrogate and report the supported advance-ratio/Reynolds domain. Do not infer thrust from pitch speed. Geometric still-air pitch-speed references are `RPM × pitch / 1056` mph: at the O.S.-reported 10,330-RPM 12×7 test point, **68.4 mph**; at the same illustrative RPM with 13×6, **58.7 mph**. These are not airspeed, thrust or flight performance.

### 5. Fuel consumption

The manufacturer manual's fuel paragraph identifies MAX-46AXII despite the 55AX cover and specification; its minimum-oil/nitro text is retained as an applicability conflict in [NITRO-00](../NITRO-00/README.md). The O.S. field observation used NITRO-X Standard Red “15-18”, but did not weigh consumption. The candidate uses a **72/10/18 volume-percent methanol/nitromethane/castor blend**, inert oil, and AIAA Table 1 component properties as a research basis. The profile compiler converts volume to mass and uses a combustible-component AFR/LHV; see the report for calculated mixture density and mass fraction. AIAA directly weighed its tank on a force balance in one-minute steady periods. It reports approximate linear fits of **2T flow = 0.46x + 28.60 mg/s**, `R²=0.96`, versus ESC electrical demand `x` in watts. This is an installed-hybrid/ESC-axis regression, with castor-oil LHV uncertainty—not a brake-power map, direct MAX55 flight-flow curve, or transferable endurance estimate. No MAX-55AX idle/cruise/WOT flow calibration or usable tank/endurance run is available here.

### 6. Idle and stalling

The current O.S. practical range begins at 2,000 RPM. O.S.'s single 12×7 field sample reports **1,800 RPM idle at 3 °C**, so the **1,800–3,000 RPM** warm-idle search bracket is only an exploration range, not a stable-idle specification. The installed lifecycle now has start/stop requests, a minimum-start threshold and mixture/temperature-dependent firing and stall transitions. Those thresholds are candidate settings, not MAX-55AX tests; manual text describes excessively rich unstable firing/smoke and lean cutout during throttle opening but gives no repeatable mixture/RPM boundary. No stall rate or failure probability is fitted.

### 7. Temperature and cooling

The only quantitative adjacent test found measured approximately **160–200 °C cylinder-head temperature** at full load on a much smaller **0.99 cm³** two-stroke glow engine. Sensor position and scaling prevent treating that as a MAX-55AX limit. Use **120–240 °C at a declared head-surface sensor** only as a broad logger/model search bracket pending measurements; it is not a safe operating band, target or seizure threshold. The installed lifecycle calls a scalar thermal energy model with combustion heat, mechanical loss, premix evaporation and airspeed-dependent cooling, and uses temperature in its inferred firing law. This reduced-order component is integrated in software, but its head/case partition, heat capacity, cooling and transient response are not MAX-55AX fits. O.S. documents qualitative danger from over-lean running but provides no numeric temperature boundary.

### 8. Sound and vibration

Nominal single-cylinder exhaust/event order is 1/rev: **33.3–283.3 Hz** in the practical range and 266.7 Hz at rated speed; rich four-stroking can put successful events near half this rate. A two-blade prop's blade-pass frequency is `2×RPM/60`, or **66.7–566.7 Hz** across that same range. These are kinematic lines, not spectral amplitudes. O.S. describes the older Power Box silencer as noise-reducing, but gives no transferable absolute dBA or calibrated 1/3-octave response. The runtime voice synthesizes firing and propeller orders with authored timbre; these cues are software presentation, not recording-derived levels or acoustic validation. NIST's model-airplane sound method uses multiple positions 1 m from the engine and records below the propeller; it informs a future measurement setup, not MAX-55AX levels ([NIST IR 75-693](https://doi.org/10.6028/NBS.IR.75-693)). No tach-synchronized MAX-55AX physical audio/vibration measurement exists in this dossier.

### 9. Aircraft dynamics

Use the candidate's shaft output and an identified propeller load in the coupled shaft/body equations. The AIAA engine test used an alternator and electrical load rather than the two recommended flight props; it does not validate climb or thrust. The only retrieved MAX-55AX aircraft observation is the O.S. CAVALIER field configuration in the 12×7 article, without synchronized flight telemetry. Propeller pitch speeds above are strictly geometric. Takeoff, acceleration, climb, cruise, torque reaction, gyroscopic response, engine-out glide and windmilling remain unvalidated; no advantage over a 4T is inferred.

### 10. Configuration and provenance

The versioned machine-readable [dossier JSON](dossier.json) records model identity, stock exhaust, plug, carburetor, fuel basis, masses, exact propeller SKUs, RPM limits, source links and the open-evidence gates. The standalone profile is `openrc-glow-engine v1`, `glow_2t`, `candidate`; its input quantities declare unit, evidence kind and source. Installed experimental builds add a separate lifecycle configuration for transients, fuel inventory/transport and scalar temperature state. Those settings are implemented candidate behavior and remain inferred, not measured. This document keeps official rated values (`manual`), AIAA/adjacent-engine measurements (`measured`, when describing those source tests), borrowed fuel properties, and unmeasured/derived profile hypotheses distinct. The profile and report hashes are generated from the current files; regenerate only after the profile owner completes edits.

## Cross-family checks and evidence boundary

Saito FA-82B's published prop range and approximately 35 cm³/min at 10,000 RPM are useful reminders that fuel rate depends on its own engine/prop/load setup; it is a larger **four-stroke** and does not calibrate this engine. YS FZ115S/DZ170 use boosted charge and model-specific fuel-feed systems; their pressure/idle advice does not define this naturally aspirated 2T. ENYA SS35EX TN is another two-stroke comparison, but its 5.52 cm³ scale, rating and tuning remain specific to ENYA. Source details and conflicts are in [NITRO-00](../NITRO-00/README.md); no cross-brand torque, fuel, temperature or sound curve is imported.

The automated inference report checks data/math consistency, reconstructs the manufacturer rated knot, displays candidate torque/power/fuel knots and varies selected inferred coefficients one at a time. Those sensitivity deltas are **not confidence bounds**. Software verification is separate from: (1) empirical MAX-55AX calibration, (2) whole-run/prop held-out validation, and (3) experienced-pilot comparison. None of these three physical gates has passed.

| Evidence still required | Current status |
| --- | --- |
| At least 8 matched shaft torque/RPM points spanning the supported band; throttle/mixture sweeps; documented test fuel/exhaust/plug/props/atmosphere | Not acquired. AIAA part-load data are limited to its hybrid test envelope; the MAX-55AX 16k rating is a single manufacturer point. |
| Two prop load curves including APC 12×7 and 13×6 `Ct/Cp`, RPM, J, Reynolds, thrust, torque and inertia | Not acquired for these exact engine/prop pairs. |
| Bidirectional command/barrel/RPM transients, measured servo, rich/lean repeatability and sustaining warm idle/stall boundaries | Not acquired. |
| Weighed fuel flow by speed/load/mixture, depletion/endurance; installed head/case temperature/cooling/heat soak | Not acquired. |
| Tach-synchronized sound and vibration; identified 3-axis installation; held-out flight telemetry; experienced pilot assessment | Not acquired. |

Run `python research/glow-engines/calibration_report.py --write` after candidate-profile edits settle, then `python -m unittest discover -s research/glow-engines -p test_profiles.py`. The report is auditable numerical inference, not closure of NITRO-2T-03 or NITRO-2T-04.
