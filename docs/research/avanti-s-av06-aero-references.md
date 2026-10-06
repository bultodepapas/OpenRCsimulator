# Avanti S: textbook aerodynamic references (AV-06)

2026-10-06 · AV-06 research · **Reference values and ranges for the clean wing, flaps, drag, inertia, ground and speeds of a 2.0 m, 11–12 kg sport/pattern turbine jet. No Avanti-specific aero data exists in public sources; every number below comes from generic sections, NACA/DATCOM methods or other aircraft.**

Geometry used where a number is scaled to the Avanti: S 0.702 m², b 2.00 m, AR 5.70, λ ≈ 0.46, Λ_LE 20.7° (→ Λ_c/4 ≈ 17.4°, Λ_c/2 ≈ 13.9°), flap chord ≈ 0.31 c, flaps from 18 % to 53 % of the semi-span (flapped-area ratio S_flapped/S ≈ 0.39). All from the visual blockout [geometry.json](../../assets/aircraft/avanti-s-a200/geometry.json): **estimated, not measured**. The airfoil is unknown.

Labels: **measured** (wind tunnel or flight), **textbook** (published method, chart or table; chart reads ±0.05), **estimate** (derived here or a guess with stated inputs).

## 1. Section data, thick symmetric airfoils

Speed range 15–70 m/s gives Re ≈ 4×10⁵ at the MAC near stall (2.4×10⁵ at the tip) and up to 2×10⁶ at the root at top speed.

| Quantity | Value | Unit | Label | Source |
| --- | --- | --- | --- | --- |
| c_l,max NACA 0012, Re 0.36 / 0.70 / 1.0 / 2.0 ×10⁶ | 0.98 @10° / 1.07 @11° / 1.12 @12° / 1.22 @13° | – | textbook (Sandia hybrid: PROFILE code pre-stall, wind tunnel post-stall) | [S1] Table 2 |
| c_l,max NACA 0015, same Re | 0.96 @11° / 1.05 @12° / 1.10 @12–13° / 1.20 @14° | – | textbook (same) | [S1] Table 3 |
| c_l,max NACA 0018, same Re | 0.93 @12° / 1.03 @13° / 1.08 @13–14° / 1.18 @14–15° | – | textbook (same) | [S1] Table 4 |
| Post-peak drop 2° past c_l,max, Re 1×10⁶ | 0012: 1.12→0.71 (abrupt); 0015: 1.10→1.01; 0018: 1.08→1.06 | – | textbook (same) | [S1] |
| Post-peak drop at Re 0.36×10⁶ | 0012: 0.98→0.48 in 2°; 0015: 0.96→0.93; 0018: 0.93→0.91 | – | textbook (same) | [S1] |
| c_l,max NACA 0012, wind tunnel, Re 0.36–0.70×10⁶ | ≈1.0 (+), −1.08 (−) | – | measured | [S1] text, Fig. 4 |
| NACA 0015 vs 0012H | "c_l,max slightly less … but stall is less abrupt and occurs at a slightly greater angle" | – | measured | [S1] text |
| Lift slope, linear range (all three) | 0.110 | /deg | textbook | [S1] Tables 2–4 |
| c_d,min Re 1×10⁶: 0012 / 0015 / 0018 | 0.0065 / 0.0074 / 0.0082 | – | textbook (smooth, computed) | [S1] |
| c_d,min Re 0.36×10⁶: 0012 / 0015 / 0018 | 0.0079 / 0.0091 / 0.0101 | – | textbook (same) | [S1] |
| Upper ordinate at 1.25 % chord: 0012 / 0015 / 0018 | 1.89 / 2.37 / 2.84 | % c | textbook (NACA 4-digit formula) | [S3] Table I |
| Stall type at Re ≈ 1×10⁶ (Gault correlation) | 0012 (1.89 %): leading-edge or combined band → abrupt. 0015/0018 (≥2.37 %): trailing-edge stall → rounded peak | – | measured (correlation of ~110 airfoils) | [S3] Fig. 1 |
| Stall types defined | trailing-edge: "gradual … well-rounded lift-curve peak"; leading-edge: "abrupt, often large, decrease in lift after maximum lift" | – | measured | [S3], [S2] |

Not found: published polars for "pattern" airfoils, NACA 63A-0xx at Re < 2×10⁶, or the Hawk root section. 6-series sections have a smaller leading-edge ordinate than 00xx at equal thickness ([S3] Table I), so they lean toward leading-edge stall.

## 2. Plain flaps (20° and 50°)

| Quantity | Value | Unit | Label | Source |
| --- | --- | --- | --- | --- |
| Section Δc_l,max base, split & plain, 25 % chord, at reference angle (60°) | ≈0.9 at t/c 12 %; ≈1.1 at 15 %; ≈1.45 at 18 % | – | textbook (chart read) | [T1] Fig. 8.11 (DATCOM) |
| k1, flap chord 30 % vs 25 % | ≈1.05 | – | textbook (chart read) | [T1] Fig. 8.12 |
| k2, split & plain: 20° / 50° | ≈0.5 / ≈0.92 | – | textbook (chart read) | [T1] Fig. 8.13 |
| K_Λ = (1 − 0.08 cos²Λ_c/4) cos^¾ Λ_c/4 at 17.4° | 0.895 | – | textbook | [T1] Fig. 8.19 |
| Wing ΔC_L,max = Δc_l,max · (S_flapped/S) · K_Λ, flaps 20° | 0.16–0.20 | – | estimate (DATCOM, t/c 12–15 %) | [T1] |
| Same, flaps 50° | 0.30–0.37 | – | estimate | [T1] |
| Raymer/Franchini: Δc_l,max plain flap 0.9; wing ΔC_L,max = 0.92 Δc_l,max (S_fw/S) cos³Λ_c/4 | 0.28 (full deflection) | – | textbook | [T2] |
| AR-6 wing, NACA 23012, full-span 0.20 c sealed plain flap, Re 6.1×10⁵: C_L,max at 0/15/30/45/60° | 1.13 / ≈1.43 / ≈1.67 / ≈1.9 / 2.00 | – | measured (figure read; 2.000 tabulated) | [M1] Fig. 20, Table I |
| Same wing: ΔC_L at α = 0, 15/30/45/60° | ≈0.45 / 0.67 / 0.82 / 0.97 | – | measured (figure read) | [M1] Fig. 20 |
| Same wing: stall angle with flaps | ≈15–16° at every deflection | deg | measured (figure read) | [M1] Fig. 20 |
| Same wing: Cm,c/4 at mid C_L, 0/15/30/45–60° | ≈−0.01 / −0.14 / −0.18 / −0.22 to −0.24 | – | measured (figure read) | [M1] Fig. 21 |
| NACA 23021 (21 %): ΔC_L,max plain / split at optimum | 1.017 / 1.193 | – | measured | [M1] Table I |
| Avanti ΔC_L at fixed α: 20° / 50° (= [M1] × S_flapped/S × τ ratio 0.66/0.55) | ≈0.25 / ≈0.41 | – | estimate | [M1] scaled |
| Avanti ΔCm (wing, about c/4) from the flap alone: 20° / 50° | ≈−0.06 / ≈−0.09 (nose-down) | – | estimate ([M1] × 0.39 × ~1.1) | [M1] scaled |
| Net trim change in the real airplane | nose-UP: manual mixes elevator **down** 8 % at 20° and 20 % at 50° | – | measured (manufacturer setup) | [A1], control throws |
| Flap drag ΔC_D = 1.7 (c_f/c)^1.38 (S_f/S) sin²δ, plain/split; c_f/c 0.30, S_f/S 0.39 | 0.015 (20°), 0.074 (50°) | – | textbook (McCormick 1995, via [T5]) | [T5] |
| Cross-check, Raymer ΔC_D0 = 0.0144 (c_f/c)(S_flapped/S)(δ − 10°), plain | 0.017 (20°), 0.067 (50°) | – | textbook (quoted from memory, not re-verified online) | Raymer, Aircraft Design |

Two independent routes (DATCOM chart build-up and the measured 23012 data scaled by area) agree on ΔC_L,max within 0.05. ΔC_L at fixed α exceeds ΔC_L,max, so the stall angle drops with flaps (by roughly 1–3°, estimate).

## 3. Swept, tapered wing

| Quantity | Value | Unit | Label | Source |
| --- | --- | --- | --- | --- |
| C_L,max/c_l,max, untwisted tapered wing, Λ_LE 20°, Δy ≥ 2.5 (0012: Δy = 26 t/c = 3.1) | ≈0.84–0.86 (0.90 at Λ = 0) | – | textbook (chart read; Δy beyond chart, nearest curve) | [T1] Fig. 8.9, Table 8.1 (DATCOM) |
| Swept-wing rule for round-nosed sections | C_L,max,swept = C_L,max,unswept · cos Λ_c/4 (= 0.954) | – | textbook | [T1] |
| Lift slope (DATCOM/Helmbold), A 5.7, Λ_c/2 13.9°, κ 0.95–1.0 | 4.21–4.36 (0.074–0.076 /deg) | /rad | textbook formula | [T3] |
| Wing pitch-up (Shortal–Maggin) boundary at Λ_c/4 ≈ 17° | boundary at A ≳ 7; A 5.7 lies below → no wing pitch-up expected | – | measured (correlation chart) | [M2] Fig. 1 |
| Taper effect on pitch-up | lower λ worsens pitch-up (tail-off Cm, A 4, Λ 45°) | – | measured | [M2] Fig. 2 |
| Oswald e, Nita–Scholz (e_theo 0.92 × k_e,F 0.96 × k_e,D0 0.87 jet / 0.80 GA) | 0.71–0.77 | – | textbook method | [T4] |
| Oswald e, Raymer straight-wing formula 1.78(1 − 0.045A^0.68) − 0.64 | 0.88 (upper bound; swept formula only valid Λ_LE > 30°) | – | textbook | [T4] |
| e with flaps/gear down vs cruise | e_T/O = 0.70 vs e_CR = 0.85 (ratio 0.82) | – | textbook rule | [T6] |

Tip stall: the taper ratio near 0.46 and Λ_c/4 ≈ 17° are moderate; tip Re is ~55 % of MAC Re, so the tip section reaches c_l,max first at low speed (estimate from [S1] Re trend). No washout data for the Avanti.

## 4. Drag build-up

| Quantity | Value | Unit | Label | Source |
| --- | --- | --- | --- | --- |
| Component build-up, fully turbulent Cf = 0.455/(log Re)^2.58, Raymer form factors, blockout areas (wing S_exp 0.58, stab 0.14, fin 0.18, fuselage S_wet 1.35 m², l/d 7.7) | wing 0.0088, stab 0.0023, fin 0.0026, fuselage 0.0067–0.0081; sum 0.020–0.022 | – | estimate | this report (blockout + Raymer method) |
| Same + 10–25 % for intakes, exhaust, canopy, hinge gaps, protuberances | 0.022–0.027 | – | estimate | same |
| Measured C_D0, 5 kg / 2.5 m propeller UAV (FliTePlat): tunnel / automated glide | 0.0327 / 0.0357 | – | measured (other class) | [M3] |
| Landing-gear D/q per frontal area: wheel and tire 0.25, round strut 0.30, streamline strut 0.05, faired wheel 0.13 | – | – | textbook (Raymer table, quoted from memory, not re-verified online) | Raymer, Aircraft Design |
| Gear-down ΔC_D0, three 60–75 mm wheels and three 8 mm struts, ×1.2–1.5 interference and open wells | 0.004–0.008 | – | estimate | this report |
| Intake spillage, bypass-tube loss | no public data found; ram drag is in the AV-05 turbine model | – | – | — |

## 5. Ground handling

| Quantity | Value | Unit | Label | Source |
| --- | --- | --- | --- | --- |
| Rolling coefficient, dry concrete/asphalt | 0.02–0.05 | – | textbook (Raymer table via search summary) | Raymer, Aircraft Design |
| Rolling, hard turf / firm dirt / soft turf / wet grass | 0.05 / 0.04 / 0.07 / 0.08 | – | textbook (same) | same |
| Braking coefficient, dry pavement / hard turf / soft turf | 0.3–0.5 / 0.4 / 0.2 | – | textbook (same) | same |
| Repository values now in use | pavement C_rr 0.04 (×2 of JSBSim C172 for a 76 mm wheel); grass strip 0.05–0.10, rough 0.30 | – | estimate / borrowed (FlightGear) | [ground-friction-e2](ground-friction-e2.md), [ground-surfaces-e3a](ground-surfaces-e3a.md) |
| Nose-wheel steering throw, Avanti brakes | not found in public sources | – | – | — |

## 6. Speeds

| Quantity | Value | Unit | Label | Source |
| --- | --- | --- | --- | --- |
| Avanti S A200 tested speed | "tested until 250 km/h" (69 m/s); faster flight is advised against | km/h | measured (manufacturer statement) | [A1] |
| Typical RC jet stall speed | "30–35 mph" (13.4–15.6 m/s) | mph | estimate (manufacturer guidance, BVM) | [M4] |
| Gear down / first flap notch | gear at 70–80 mph; flaps 15–20° after slowing to ~90 mph; full 35–45° | mph | estimate (BVM) | [M4] |
| Flaps up after takeoff | ≥70 mph, before 100 mph; gear/flaps at 150+ mph "will likely cause structural damage" | mph | estimate (BVM) | [M4] |
| Avanti V_s (W/S 154–168 N/m², 11–12 kg): clean (C_L,max 0.85) / flap 20° (1.03) / flap 50° (1.18) | 17.2–17.9 / 15.6–16.3 / 14.6–15.2 | m/s | estimate (this report) | §1–3 |
| Lift-off 1.2 V_s,20 / approach 1.3 V_s,50 | 18.7–19.6 / 19.0–19.8 | m/s | estimate | same |
| Parasite drag at 69 m/s with C_D0 0.026 | 53 N (P100 static: 100 N) | N | estimate | [turbine research](avanti-s-turbine-research.md) |
| Measured GPS top speed, takeoff or approach speeds of a 10–15 kg turbine jet | not found | – | – | — |

## 7. Inertia sanity range

| Quantity | Value | Unit | Label | Source |
| --- | --- | --- | --- | --- |
| NASA GTM T2 (5.5 % twin-turbine subscale, b 2.09 m, l 2.59 m, S 0.548 m², m 1.5416 slug = 22.5 kg): I_xx / I_yy / I_zz / I_xz | 1.799 / 5.768 / 7.395 / 0.163 (1.327 / 4.254 / 5.454 / 0.120 slug·ft²) | kg·m² | textbook-class (published GTM simulation constants; measurement method not stated) | [M5] Table 1 |
| Same aircraft, another paper | takeoff mass 26.19 kg with the same I_yy 5.768 kg·m² | kg | textbook-class (same) | [M6], [M7] |
| GTM non-dimensional radii R_x = 2k_x/b, R_y = 2k_y/l, R_z = 2k_z/((b+l)/2) at 22.5 kg | 0.271 / 0.391 / 0.490 | – | derived from [M5] | — |
| Jet fighter radii (Raymer, as quoted) | 0.23 / 0.38 / 0.52 | – | textbook | [T7] Table 12.1 |
| Avanti 11–12 kg, b 2.00, l 2.22 m: I_xx / I_yy / I_zz | 0.58–0.88 / 1.96–2.26 / 2.94–3.61 | kg·m² | estimate (both radii sets) | this report |
| Bifilar pendulum repeatability, 2 tests on a turbine-demonstrator subscale (TUM DeFStaR) | I_xx 2.77 vs 2.41; deviation from CAD target −7.8 % / +7.1 % / −13.2 % | kg·m² | measured | [M8] Table 3 |

The GTM carries its engines under the wings, so its R_x is high for a single-turbine fuselage jet; expect the Avanti's I_xx near the low end (0.55–0.75).

## Recommended starting set

| Item | Value | Confidence |
| --- | --- | --- |
| C_L,max clean / flap 20° / flap 50° | 0.85 / 1.03 / 1.18 | low–medium (airfoil unknown; ±0.10) |
| Stall | trailing-edge (gentle, rounded) if t/c ≥ 15 %; abrupt if ≈12 %; tip first at low Re | medium for the rule, low for this wing |
| C_L,α wing | 4.3 /rad | medium |
| C_D0 clean, gear up / gear-down increment | 0.026 (range 0.020–0.033) / +0.006 (0.004–0.008) | low |
| Flap ΔC_D0 20° / 50° | 0.016 / 0.070 | medium (two textbook methods agree) |
| Flap ΔCm (wing) 20° / 50°; net trim | −0.06 / −0.09; net nose-up per manual mix | low |
| Oswald e clean / flaps down | 0.75 / 0.62 | medium |
| Inertia 11.5 kg | I_xx 0.55–0.90, I_yy 1.9–2.3, I_zz 2.9–3.6 kg·m² | sanity window only |
| Rolling / braking (pavement) | 0.03–0.04 / 0.3–0.5 | medium (textbook, full scale) |
| Speeds | V_s 15–18 m/s, lift-off ≈19 m/s, approach ≈19–20 m/s, tested max 69 m/s | low (derived) except the 69 m/s limit |

## What this does not prove

- No number here is measured on an Avanti S. Area, taper, sweep, flap span and chord come from a visual blockout; the airfoil and its thickness are unknown, and they move C_L,max and stall abruptness more than any other input.
- The Sandia section tables are smooth-model, low-turbulence values; pre-stall points are computed. Balsa/film wings with hinge gaps and turbulators can differ by ±0.1 in c_l,max.
- The flap data come from a full-span, sealed, rectangular AR-6 wing at Re 6×10⁵; partial-span, gapped flaps on a swept wing will do less. Chart reads carry ±0.05.
- The C_D0 build-up assumes fully turbulent flow and a guessed 10–25 % for intakes and gaps; the only measured small-UAV C_D0 is a propeller aircraft.
- Two items are quoted from Raymer from memory or a search summary (gear-component D/q, rolling/braking table, Raymer flap-drag constant); verify against the book before treating them as more than textbook-class.
- The derived speeds only check internal consistency (W/S, C_L,max); no GPS or radar data of a comparable turbine jet were found. The inertia window brackets, it does not replace, a component inventory.

## Sources

- [S1] Sheldahl, R. E., Klimas, P. C., *Aerodynamic Characteristics of Seven Symmetrical Airfoil Sections Through 180-Degree Angle of Attack…*, SAND80-2114, Sandia, 1981. https://digital.library.unt.edu/ark:/67531/metadc1191254/m2/1/high_res_d/6548367.pdf
- [S2] McCullough, G. B., Gault, D. E., *Examples of Three Representative Types of Airfoil-Section Stall at Low Speed*, NACA TN 2502, 1951. https://ntrs.nasa.gov/citations/19930083422
- [S3] Gault, D. E., *A Correlation of Low-Speed, Airfoil-Section Stalling Characteristics with Reynolds Number and Airfoil Geometry*, NACA TN 3963, 1957. https://ntrs.nasa.gov/citations/19930084707
- [M1] Wenzinger, C. J., *Wind-Tunnel Investigation of Ordinary and Split Flaps on Airfoils of Different Profile*, NACA Report 554, 1936. https://ntrs.nasa.gov/api/citations/19930091629/downloads/19930091629.pdf
- [M2] Polhamus, E. C., Hallissy, J. M., *Effect of Airplane Configuration on Static Stability at Subsonic and Transonic Speeds*, NACA RM L56A09a, 1956 (Shortal–Maggin boundary). https://ntrs.nasa.gov/api/citations/19930089302/downloads/19930089302.pdf
- [M3] *Experimental evaluation of the drag curves of small fixed wing UAVs*, The Aeronautical Journal (Cambridge). https://www.cambridge.org/core/journals/aeronautical-journal/article/experimental-evaluation-of-the-drag-curves-of-small-fixed-wing-uavs/453B48240E5861B1360B9D33288C5C88
- [M4] BVM Jets, *Air Speed Limits for Flaps and Landing Gear*. https://www.bvmjets.com/Safety/AirSpeedLimits.htm
- [M5] Grauer, J. A., Morelli, E. A., *Dynamic Modeling Accuracy Dependence on Errors in Sensor Measurements, Mass Properties, and Aircraft Geometry*, AIAA/NASA. https://ntrs.nasa.gov/api/citations/20130003198/downloads/20130003198.pdf
- [M6] *Nonlinear Trajectory-Based Region of Attraction Estimation for Aircraft Dynamics Analysis* (GTM constants, Table 2). https://arxiv.org/pdf/2106.08850
- [M7] *Evaluating the Effects of Control Surfaces Failure on the GTM* (GTM-T2 properties, Table 1). https://arxiv.org/pdf/1905.09794
- [M8] Scheufele, B., Koeberle, S. J., Hornung, M., *Design, Implementation and Flight Testing of a Subscale Demonstrator for Assessing the Stall Behaviour of a Large Swept-Wing Research UAV*, DLRK 2021. https://www.dglr.de/publikationen/2022/550035.pdf
- [T1] Scholz, D., *Aircraft Design, Ch. 8: High Lift Systems and Maximum Lift Coefficients* (reproduces DATCOM 1978 charts). https://www.fzt.haw-hamburg.de/pers/Scholz/HOOU/AircraftDesign_8_HighLift.pdf
- [T2] Arnedo, *Fundamentals of Aerospace Engineering*, §3.4.3 Increase in CLmax. https://eng.libretexts.org/Bookshelves/Aerospace_Engineering/Fundamentals_of_Aerospace_Engineering_(Arnedo)/03%3A_Aerodynamics/3.04%3A_High-lift_devices/3.4.03%3A_Increase_in_CLmax
- [T3] *Lift Coefficient Prediction Versus Angle of Attack: A Polynomial Representation Based on a VLM-DATCOM Hybrid Model*, JAFM (DATCOM lift-slope formula). https://www.jafmonline.net/article_2970.html
- [T4] Nita, M., Scholz, D., *Estimating the Oswald Factor from Basic Aircraft Geometrical Parameters*, DLRK 2012. https://www.fzt.haw-hamburg.de/pers/Scholz/OPerA/OPerA_PUB_DLRK_12-09-10.pdf
- [T5] McCormick, B. W., *Aerodynamics, Aeronautics and Flight Mechanics*, 1995, flap-drag formula as quoted in https://www.physicsforums.com/threads/how-much-do-these-type-of-flaps-increase-drag.387359/post-2629715
- [T6] Scholz, D., *Drag Estimation* (lecture notes, e_T/O and e_CR). https://www.fzt.haw-hamburg.de/pers/Scholz/materialFM1/DragEstimation.pdf
- [T7] Nuyn, A., *YA-94: A Conceptual Approach to Designing a New Close Air Support Aircraft*, SJSU 2022, Table 12.1 (citing Raymer). https://www.sjsu.edu/ae/docs/project-thesis/Alex.Nuyn-Su22.pdf
- [A1] SebArt, *Avanti S Jet 2.2m ARF manual (introduction)*. https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf
- Raymer, D. P., *Aircraft Design: A Conceptual Approach* (AIAA): landing-gear component drag, takeoff friction and flap-drag tables, cited from memory/search summaries as marked.
