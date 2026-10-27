# EM-31 — Wing-loss and knife-edge recovery feasibility

**Date:** 2026-10-27. **Scope:** can an aircraft in the current fleet keep controlled flight, and arrive survivably, after losing (a) the outer 30–50 % of one semispan or (b) one complete wing panel? Which model capabilities must exist before the simulator can show that outcome honestly? **Method:** independent physics study. It used the generated aircraft JSON, each aircraft's own propulsion law, a Weissinger lifting line over the remaining planform, and a knife-edge force balance with three fuselage side-force laws. A strip-mask probe ran on a disposable app copy. No runtime or aircraft data were changed. **This is analysis, not physical validation.** It informs [EM-20…24](../../../plans/failure-mode.md#10-wing-separation-and-continued-damaged-flight).

Tools: [`research/failure-mode/em31/`](../../../../research/failure-mode/em31/). `python3 -I wingloss.py > tables.md` regenerates the full tables, which were checked byte-identical from the repository location. Its input `part_throttle.csv` comes from the existing [`part_throttle_probe.gd`](../../../../research/flight-dynamics/power-climb/part_throttle_probe.gd). `strip_mask_probe.gd` plus `strip_mask_probe.patch` reproduce the masked-strip probe, but only on a disposable app copy.

## Verdict

| Aircraft | (a) outer 30–50 % lost | (b) full panel lost | Dominant limit |
|---|---|---|---|
| Ugly Stik / 61FX | Feasible above V_min 12–26 m/s; marginal at 50 % | Marginal at best: hover only, and it torque-rolls | Ailerons span almost the whole panel; 0.08 m² side area |
| Extra 300S | Feasible, 13–20 m/s | Not feasible | Static T/W 0.86 |
| P-51D / F4U | Feasible with flaps, 17–29 m/s | Not feasible; controlled flight marginal | 0.7 m lift arm, about 113 mm lateral CG shift, one gear leg lost, torque |
| Avanti S | Feasible, 21–31 m/s | Not feasible | T/W 0.74 |
| Timber | Feasible to marginal | Not feasible | Thrust; small fin |
| Skywalker X8 | Marginal at 30 %; not feasible beyond | Not feasible | Tailless static margin 7.6 → about 0 % (30 %) → about −3 % MAC (50 %); no rudder |

- **Case (a).** A wings-level trim with full aileron exists on every conventional aircraft above V_min, which is 1.1–3 × the power-off stall speed. Thrust exceeds drag at V_min by 12–155 N. A fast, flat arrival is physically plausible. With a clockwise propeller, losing the left side raises V_min by 0.5–15 m/s, most on the warbirds.
- **Case (b).** No fleet aircraft has a credible survivable arrival.
  - Knife-edge with the remaining wing near zero lift depends almost entirely on the fuselage side-force law. The repository's D10-R3 law holds the P-51, F4U and Avanti level. The measured body-alone bound of Letko and Williams gives a 3–47 m/s sink for every aircraft.
  - Prop-hang descent needs damaged T/W ≥ about 1.3; only the Stiks, P-51 and F4U have it. None has aileron area in the propeller wash, so every hover would torque-roll.
- **Real cases.** The two documented RC one-wing landings ([EM-00 R15/R16](../EM-00/README.md#r15--original-account-of-an-rc-one-wing-landing)) were flown by expert pilots on high-T/W aerobatic models. No fleet aircraft combines large side area, a large rudder and T/W well above 1.

## Key numbers

| Aircraft | W (N) | Static T (N), T/W | Full-panel mass lost | Lateral CG shift, full panel (mm) | Time to 90° bank, 1 g, no input (s) |
|---|---|---|---|---|---|
| Stik | 28.2 | 41.3, 1.46 | 8.4 % | 37 | 0.38 |
| Stik 61FX | 29.7 | 56.1, 1.89 (measured 41.6 N, so about 1.4) | 8.0 % | 35 | — |
| Extra | 37.5 | 32.1, 0.86 | 7.6 % | 34 | — |
| P-51 | 214.5 | 235, 1.10 | 15.4 % | 114 | 0.53 |
| F4U | 214.5 | 275, 1.28 | 15.1 % | 112 | — |
| Avanti | 124.9 | 92, 0.74 | 9.1 % | 45 | — |
| Timber | 21.5 | 22.0, 1.03 | 9.6 % | 45 | — |
| X8 | 30.7 | 34.8, 1.13 | 10.6 % | 68 | — |

- Across the fleet, a full-panel loss at 1 g reaches 90° of bank in 0.27–0.64 s, with steady roll rates of 145–396 °/s. At 3 g it takes 0.12–0.23 s.
- Roll inertia roughly halves. New products of inertia appear: the X8's Jxy turns its x–y principal axes by 41°.
- The full tables, including per-case V_min, knife-edge sink under each side-force law and inertia tensors, are in `tables.md`.

## The current model would show a false recovery

The probe masked strips in `aero.gd`'s local law. `Aero.loads()` still returned intact lift and **zero rolling moment** at α 2–6°, whether a third, two thirds or all of one wing was masked. The coefficient oracle that cruise uses ignores the mask. Other false-recovery sources:

- The intact downwash map: its asymmetry is 5–15 % too small.
- Stub ailerons that keep their full authority.
- Contacts and gear left on the missing panel.
- The Stik's borrowed oracle side-force coefficient.

False-impossibility sources:

- Four aircraft have no fuselage side force.
- Uniform aileron effectiveness cannot shift lift inboard.
- Only 3 strips per side, so the smallest representable loss is a third of the area (33–42 % of the semispan).

## Capabilities required before wing separation can ship

1. A damaged topology uses the local model only, or an oracle regenerated from the damaged local model (`aero.gd` oracle path).
2. At least about 8 removable strips per side, or a strip clipped at an arbitrary cut. Each strip needs its own chord, station, dihedral, and aileron/flap coverage and effectiveness.
3. The induced-flow (downwash) map rebuilt for the remaining wing at the event.
4. The dihedral term and tail downwash split per panel.
5. A sourced fuselage side force for every conventional aircraft, plus a vertical crossflow term at the correct point of action (EX-14 open item).
6. Dry-part removal with the full inertia tensor for every aircraft, via the variable-mass, fixed-datum law. That law exists today only for finite fuel. Velocity transfer is `v_new = v_O + ω×Δr` without an impulse.
7. Contacts and gear removed with the section (AS-13).
8. Propeller wash over the wing strips.
9. A propeller law for descent and large inflow angles, or an explicit refusal outside its domain.
10. A sourced post-stall wing polar for every aircraft; only the Extra and Avanti have one today.

Already adequate: gyroscopic coupling, torque reaction, tail slipstream, per-strip ground effect and the 240 Hz RK4 integration.

## Acceptance checks proposed for EM-20…24

1. **Topology regression.** On a damaged airplane, `loads()` at α 2° returns the local-law rolling moment, not the intact one.
2. **Damaged-wing aerodynamics.** Lift and centroid agree with `wingloss.py` and AVL 3.52 within ±10 %. NASA's damaged-transport data ([NTRS 20080034656](https://ntrs.nasa.gov/citations/20080034656)) check the trend only.
3. **Mass transaction.**
   - Retained plus detached momentum is conserved to round-off, and the retained inertia is positive definite.
   - The Stik reproduces −0.243 kg, +37 mm lateral CG and Jxx 0.116 → 0.060 kg·m².
4. **Session trim sweep.** At V_min ± 10 %, results agree with the V_min table within 15 %, including the left/right asymmetry. The Stik and Extra show no wings-level trim after a full-panel loss.
5. **Fuselage side force.** Accepted per aircraft inside the [Letko–Williams, D10-R3] band, with the intact knife-edge sink consistent, before any knife-edge claim. One instrumented owner knife-edge pass would settle the law.
6. **Honesty gates.**
   - The damaged Stik's hover torque-rolls.
   - The X8 at 50 % loss diverges in pitch.
   - The Extra and Avanti cannot hover.
   - Results outside these bands are reported as outside the validated envelope, never rescued.

## Limits

- The lifting line is planar and unswept, and ignores fuselage carry-over.
- The knife-edge budget ignores net fin force.
- Several inputs are estimates: side areas for the Stik, Timber and X8; aileron spans for the P-51 and Timber; the X8 pitch numbers.
- The F4U and X8 have no FT-05 flight-test run.
- The 61FX Stik's model thrust is about 35 % above the measured value.

Against the simulator's own intact knife-edge (FT-05/EX-14g), the budget agrees for the Extra, Avanti and Timber. It does not agree for the Stik, which relies on the borrowed oracle CYβ, or the P-51, which has no body side force in its local law.
