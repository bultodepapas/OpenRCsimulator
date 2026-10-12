# AV-14 airframe and generated-physics audit

2026-10-12 · Scope: original SebArt Avanti S Jet 2.2 m ARF (A200) with P100-RX, flaps and gear up. Read-only audit against the checked-in AV-06 source, generated v2 aircraft, and runtime loader. Geometry calculations below verify the implementation against its own estimated source geometry; they do not calibrate that geometry to a physical aircraft.

## Source chain and limits

`assets/aircraft/avanti-s-a200/geometry.json` supplies the photo-fitted visual blockout. `research/avanti-s/av06/inputs.json` supplies sourced nominal values plus explicitly estimated aero and inventory inputs. `research/avanti-s/av06/derive_physics.py` combines them to generate `app/data/aircraft/sebart_avanti_s_a200.json` and the AV-06 derivation report. Separately, `assets/aircraft/avanti-s-a200/compile_geometry.py` compiles visual geometry for rendering; that path does not generate flight physics. The v2 loader in `app/physics/aircraft_data.gd` consumes generated inventory, sums its mass and moments, checks it against `balance.plan_cg`, and derives inertia from the component boxes and parallel-axis terms (`validate_and_derive()` and `inertia_about()`). Thus an inventory centroid or box-size change affects runtime mass properties even when the flight CG target is unchanged.

The manufacturer identifies this A200 as 200 cm span, 222 cm length, and 10.5 kg dry with P100. The official manual provides control throws and CG choices, but no published planform, airfoil, tail area, measured mass distribution, inertia, stall polar, or fuel-state qualifier for its CG values. The blockout planforms and most equipment locations are therefore estimates. Do not combine data for the 2.1 m Krill A200 FC, Avanti XS, EDF, or P100-RX-BL with this model.

## Ranked findings

### P1 — Tail exposed-area denominator uses height instead of span

In `research/avanti-s/av06/derive_physics.py`, `strips()` returns `(y, le_z, chord, height, dy)`. The area expression near line 340 repeats `_` in `for _, _, c, _, dy` and then tests `_ >= root_y`; Python binds the last `_` to `height`, so the condition is height ≥ 0.05 m. The following first-moment expressions correctly test `y >= root_y`. The denominator consequently includes the strip from the centerline to the exposed tail root while its numerators exclude that strip.

Direct integration of the existing piecewise-linear tail blockout gives these per-side results:

| Quantity | Current calculation | Consistent exposed panel (`y >= 0.05 m`) |
| --- | ---: | ---: |
| Planform area | 0.082380 m² | 0.070380 m² |
| Spanwise area centroid | 0.187059 m | 0.218953 m |
| Longitudinal centroid, 45% chord | 0.866774 m | 1.014561 m |

The area is overstated by 17.05% relative to the exposed-panel value, and the mismatched denominator pulls the reported centroid 147.788 mm forward and 31.894 mm inward. This is a concrete source-code defect, although the resulting corrected area and centroid remain conditional on the estimated blockout geometry and 45%-chord mass-placement rule.

**Narrow correction:** unpack strip fields as named values and apply the same `y >= root_y` selection to area and both first moments. Search found no other conditional filter using a repeated `_` placeholder in this generator. Regenerating with this correction and the existing rebalance procedure changes virtual tail ballast from 0.396299 to 0.345089 kg and flight mass from 11.756299 to 11.705089 kg; the algorithm pins CG at 0.240 m. If the existing ballast were physically retained instead of regenerated, the corrected component positions would move the inventory CG aft by about 3.75 mm. With the rebalance, generated inertia changes from `[0.620508, 2.440370, 2.968171, 0, -0.026904, 0]` to `[0.624352, 2.464196, 2.995857, 0, -0.029766, 0]` kg·m², in `[Jxx, Jyy, Jzz, Jxy, Jxz, Jyz]` order. The runtime loader uses these derived component positions and sizes, so this is not only a report-label correction.

### P1 — Mean-aerodynamic-chord leading edge is chord-squared weighted

`planform()` correctly computes MAC length as `∫c²dy / ∫cdy`, but computes its leading-edge station as `∫x_LE c²dy / ∫c²dy`. The standard geometric MAC leading edge is `∫x_LE cdy / ∫cdy`; the chord-squared weight belongs to MAC length. This follows the section “Mean Aerodynamic Chord” in Mason, *Applied Computational Aerodynamics*, Appendix A, p. A-28: [Virginia Tech PDF](https://archive.aoe.vt.edu/mason/Mason_f/CAtxtAppA.pdf). NASA NDARC describes mean aerodynamic-center location as lift-weighted; for constant strip lift coefficient, area weighting is consistent, while actual Avanti swept-wing loading remains an unvalidated model assumption: [NASA TP-2009-215402, Appendix 7, pp. 128–130](https://rotorcraft.arc.nasa.gov/Publications/files/Johnson_1085_TN21612_NASA%20TP-2009-215402-app7.pdf).

An independent trapezoid check uses the generator's equivalent wing chords, root 0.459054 m and tip 0.243221 m, half-span 1 m, with the blockout leading-edge slope 0.325 m/m. The area-weighted span station is `h(Cr + 2Ct) / (3(Cr + Ct)) = 0.448778 m`, giving `x_LE,MAC = 0.145853 m` for a root leading edge at zero. The old chord-squared weighting gives span station 0.400682 m and leading edge 0.130222 m, 15.631 mm forward. Integrating the actual piecewise source stations moves wing MAC-LE from 0.102368 to 0.118267 m (+15.899 mm); wing xAC from 0.192990 to 0.208889 m; and tail MAC-LE from 0.909994 to 0.918069 m.

The neutral-point anchor intentionally remains fixed at the estimated 0.260 m CG / 3% MAC condition, so the current calculation still reports NP 0.270875 m and 8.517% static margin at the 0.240 m CG after this geometry formula is corrected. The corrected MAC stations do move reference locations and pitch derivatives; they do not validate the aerodynamic center. **Narrow correction:** use area weights for MAC-LE, retain chord-squared weights for MAC length, and preserve the existing anchor with its estimated provenance.

### P2 — Inventory inertia models paired servos as continuous spanwise bars

The inputs identify two aileron servos at estimated `y = ±0.75 m` and two flap servos at estimated `y = ±0.35 m`, but serialize each pair as one component centered at `y=0` with a box spanning both locations. The runtime box-inertia formula treats mass as uniform over that span. For the stated pair locations as point-mass centers, the aileron pair's spanwise parallel-axis term would be 0.073125 kg·m², while its current 1.5 m uniform box contributes 0.024375 kg·m²; for the flap pair the corresponding terms are 0.018375 and 0.006125 kg·m². Actual local servo dimensions add small intrinsic terms and the locations themselves are estimates, so these are model-distribution comparisons, not measured corrections. Symmetric splitting would leave CG unchanged but increase lateral-axis inertia.

**Narrow follow-up:** if AV-15 retains these estimated center stations, serialize each servo as a localized component at its paired `±y` station, retaining its pair mass and current estimated longitudinal/vertical stations. Keep locations explicitly estimated and do not invent mounting offsets. This makes the inertia approximation consistent with the inventory's stated locations; it does not improve physical validation. Battery/electronics balancing likewise places two 0.45 kg groups at one shared, limit-clamped station to meet the manual CG, so the resultant CG is a build scenario rather than a measured build or independently predicted loading.

### P2 — The 240 mm CG has no manufacturer fuel-condition claim

The original SebArt A200 manual lists 250 mm recommended, 240 mm for jet beginners, and 260 mm for unlimited 3D, and says to move the turbine battery to balance. It does not qualify those CG positions as empty-, half-, or full-tank measurements. The input's half-tank fraction (1.28 kg for the declared 3.2 l tank and 0.80 kg/l) is explicitly a selected in-air scenario; it is not a manufacturer-prescribed loading condition. The separate Krill A200 FC manual's landing-fuel/full-tank guidance belongs to a different 2.1 m airframe and is not evidence for SebArt's A200.

The generated 0.240 m target is therefore correctly sourced as a manual CG choice, but the coincident 50% fuel state is a simulator scenario. **Narrow correction:** keep those provenance statements separate in reports and scenario definitions; do not change tank fraction or CG target absent an A200 loading reference or measured balance record.

### P2 — Predicted maximum level speed exceeds the manufacturer's tested-speed guidance

The AV-06 model estimates a 73.4 m/s (264 km/h) full-thrust level equilibrium. The original A200 manual says tested up to 250 km/h and does not recommend faster operation because of its lightweight structure and large control surfaces. These are different quantities: the calculated equilibrium is not a demonstrated safe speed or an operational envelope. It is also not a runtime speed cap in the generated aircraft JSON.

**Narrow correction:** keep the model's equilibrium output distinct from the manufacturer's 250 km/h tested/advised ceiling in research and validation records. Do not tune drag or impose an uncontracted runtime limiter merely to force numerical agreement. Any later safety envelope must have its own explicit source and consumer.

### P2 — Aero, stall and drag values remain estimates; the drag build-up merits reconciliation

The blockout yields `S = 0.702275 m²` and `b = 2.00 m`; only span is manual, while area, taper, sweep and tail dimensions are photo-fit estimates. The `CL_max = 0.85`, four-degree stall blend, spanwise incidence offsets, lift slopes, Oswald factor, flap effectiveness, and drag build-up are modeled from generic airfoil/DATCOM sources or qualitative owner reports. No A200 airfoil drawing, polar, stall-speed test, glide polar or GPS speed measurement was found. They do not justify numeric “realism tuning.”

The current drag build-up yields `CD0 = 0.035151`, above the AV-06 aero-reference report's 0.026 recommendation and 0.020–0.033 range. Review traced the difference to non-matching bases: the earlier range uses different component geometry/areas and omits some item drag area and the current 1.15 excrescence multiplier. The implemented build-up also retains a fixed Raymer wing-form-factor Mach multiplier evaluated at M=0.34 even though the start-speed condition is about Mach 0.09, laminar fractions of 0.15 on wing/tails and 0.05 on fuselage, and a tail form factor of 1.12. These are assumptions, not a local-Re/Mach fit. **Narrow correction:** expose those assumptions and the component drag areas in the generated derivation report, while retaining the current numeric coefficient absent comparable A200 drag evidence. Do not tune to the historical range or 250 km/h.

### No throw/differential/unit defect found

The original SebArt manual specifies high-rate aileron 30° up / 25° down, elevator ±30°, and rudder ±30°. The AV-06 inputs preserve those throws as degrees, and the generated v2 controls use `deg`; servo full-throw time is serialized in seconds. The `0.11 s` value is explicitly estimated from a DS8411 0.15 s/60° catalog/retailer figure scaled to roughly 45° servo travel, not a measured installed response. The manual's transmitter dual-rate/expo settings are not additional physical throw or aero data. No unit conversion or differential correction is justified by this audit.

## Primary references

- SebArt, [Avanti S Jet 2.2m ARF manual (intro)](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf): original A200 dimensions, dry mass, balance guidance, throws and tested-speed warning.
- Virginia Tech, Mason, [Applied Computational Aerodynamics, Appendix A](https://archive.aoe.vt.edu/mason/Mason_f/CAtxtAppA.pdf): geometric MAC and leading-edge integration.
- NASA, Johnson, [NDARC Appendix 7](https://rotorcraft.arc.nasa.gov/Publications/files/Johnson_1085_TN21612_NASA%20TP-2009-215402-app7.pdf): geometric MAC versus lift-weighted aerodynamic-center definition.
- AV-06 in-repository estimates and provenance: `research/avanti-s/av06/inputs.json`, `research/avanti-s/av06/derivation.md`, `docs/research/avanti-s-av06-airframe-data.md`, and `docs/research/avanti-s-av06-aero-references.md`.

No generator, application code, generated data, tests, or engine runs were changed or performed for this audit.
