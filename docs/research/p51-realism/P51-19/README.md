# P51-19: pitch trim calibrated to the full-size XP-51 trim curves

2026-10-14 · Revision 1 · **Status: data correction implemented and software-verified; RC flight acceptance remains open.** Prefix: P51-19. [Plan](../../../P51-REALISM-PLAN.md) · [Tools](../../../../research/p51/p51-19/README.md)

## Finding

The P-51 needed 6.5° of up elevator to fly level at its 25 m/s start: 44 % of the high-rate throw, leaving only 56 % for nose-down. P51-07 and P51-15 recorded this as a rigging question for owner review. The coefficients are nondimensional on scaled full-size geometry, so the model predicts the same trim for the full-size airplane. NACA flew that airplane.

The XP-51 flying-qualities report (White, Hoover and Garris, NACA MR L-566, April 1943, [NTRS 19930092575](https://ntrs.nasa.gov/citations/19930092575)), Figure 10, gives the elevator angle for trim with the tab at 0, at CG 24.5 % and 29.2 % MAC, in glide and cruise. At 29.2 % the airplane trims with about 0° from 100 to 240 mph. At the same CL and CG, the runtime trim solver needed 4–5° more up elevator in every glide condition. The trim **gradient** agreed (4.5 vs 4.8°/CL at 24.5 %); the error was a constant zero-lift moment, ΔCm0 ≈ +0.064.

## Sign of the stabilizer setting

The report lists the stabilizer "normal setting (relative to longitudinal axis) 2°" and the wing root incidence 1°, both unsigned. NACA ACR 4K02 ([NTRS 19930092458](https://ntrs.nasa.gov/citations/19930092458), P-51B) states: "The stabilizer incidence was set at 1° instead of the normal 2° … in order to reduce the elevator angle required for trim at high Mach numbers." Reducing the setting lowers the up-elevator demand only if the setting is leading-edge up. The model's +2° sign is therefore correct. Secondhand forum values (−2° on early B/C/D, ½° after metal elevators) are unsourced and were not used.

## Correction

The tail's flow angle at zero body α is calibrated with one lumped term, the same method P51-05 used for the neutral point (K_fus, Table II of the same report). The generator solves the runtime's attached-oracle glide equilibrium, with r × F from the ARP to the CG, and fits a least-squares fit to the six glide points at CL ≤ 0.75 (attached oracle, α < 8°) and both CGs. It removes the gear-down drag, because the XP-51 flew with its gear up. The stabilizer stays at +2°. The correction is −2.30° at the tail and lumps fuselage and wing-root flow at the tail, plus any airframe zero-lift moment the textbook terms miss.

| Quantity | Before | After |
| --- | ---: | ---: |
| `aero.surfaces.horizontal.incidence` (effective, rad) | 0.041173 | −0.030504 |
| `Cm0` about the ARP | −0.066816 | −0.002601 |
| `CL0` | 0.121565 | 0.097099 |
| Glide elevator RMS vs NACA (6 fitted points) | 4.10° | 0.27° |

These are the only numeric changes. Mass, CG, inertia, neutral point, static margin, lift slope, control power, propulsion and gear are unchanged. The point-by-point table is in the [derivation](../../../../research/p51/p51-05/derivation.md#p51-19-trim-against-the-full-size-xp-51-naca-mr-l-566-fig-10-glide-tab-0-gear-up). Points above CL 0.75 are reported only: full-size CLmax at Re 13×10⁶ exceeds the model's 1.02, so the two curves cannot match near stall.

## Runtime evidence

Godot 4.7.2 official, native Windows, 240 Hz unless stated. XP-51 values are linear interpolations between the digitized points. The working tree contained another track's uncommitted edits to `app/physics/slipstream.gd`, `app/sim/flight_session.gd` and `app/sim/simulation.gd`. Baseline and candidate ran on that same tree, with only the P-51 JSON changed; the hashes are in the identity files. Absolute values therefore differ from the P51-15 reports.

[`trim_probe.gd`](../../../../research/p51/p51-19/trim_probe.gd) ([baseline](baseline-trim-probe.txt), [candidate](candidate-trim-probe.txt)), elevator up in degrees at nominal CL:

| CG | CL | Glide, before → after | XP-51 glide | Level (powered), before → after | XP-51 cruise |
| --- | --- | ---: | ---: | ---: | ---: |
| 24.5 % | 0.25 | 5.12 → 1.03 | ≈0.8 | 6.41 → 2.30 | ≈0.5 |
| 24.5 % | 0.40 | 5.98 → 1.89 | ≈1.6 | 7.17 → 3.06 | ≈1.2 |
| 27 % | 0.40 | 5.26 → 1.18 | — | 6.55 → 2.44 | — |
| 29.2 % | 0.30 | 4.42 → 0.33 | ≈−0.1 | 5.79 → 1.68 | ≈−0.15 |
| 29.2 % | 0.55 | 4.89 → 0.80 | ≈0.6 | 6.25 → 2.14 | ≈0 |

The [P51-15 probes](../../../../research/p51/p51-15/README.md) compared baseline with candidate ([summary](compare-240.md)). All 34 airborne and 5 ground cases completed at 240 and 480 Hz with no crash or fault, and ground numerics and lifecycle checks passed. Level trims keep α within 0.01°; trim throttle falls by 1–2 % because the trim drag is lower. The trim stick command at 25 m/s falls from 0.437 to 0.163. Inverted hands-off flight now needs 0.9° of down elevator instead of 3.2° up. Nonlinear cases change as expected: a lower effective tail incidence lets full up elevator reach a higher angle of attack. The full-up pulse peak goes from 17.7° to 20.7° and the idle stall entry from 18.9° to 21.5°. Takeoff and landing events change by less than 1 %.

## Test outcomes

The P-51 tests were run on a clean `HEAD` worktree (`5e9dae16`) with the baseline and candidate data ([logs](tests/); working-tree identity in [identity.txt](identity.txt)):

| Check | Baseline | Candidate | Reading |
| --- | --- | --- | --- |
| `test_p51_handling` inside loop, 0.7 stick from 27 m/s, 360° within 8 s | **fails**, 307° | **fails**, 347° | Already failing at `HEAD`; not caused here. The stick is added to the trim, so baseline flew it at the clipped full-up command (P51-15 documents the clipping). |
| `test_p51_ground` lift-off 1.05–1.5 Vs | **fails**, 25.2 m/s | **fails**, 25.3 m/s | Already failing at `HEAD`; not caused here. |
| `test_p51_envelope` power-off stall recovery < 80 m | 65 m | **83 m** | Caused by this change. Every other envelope check changes by less than 1 %. |

Without the spurious nose-down moment, full up elevator reaches a deeper stall (α 21.5° instead of 18.9°), as in the XP-51, whose elevator had about 8° in hand beyond the stall (Section I-D of the report). The scripted recovery's altitude loss depends little on the push: 82–90 m for absolute −0.4 or −0.6 and stick-relative −0.4 or −0.6, except 75 m for absolute −0.6. The 80 m band is a P51-08 software band with no external source. It was neither widened nor met by retuning the stimulus; the owner decides. All other affected native tests pass, except two unrelated failures that also occur at `HEAD` (HX700 energy classification, Avanti wheel state).

## Limits and open items

- **Power effect sign.** With power the model needs about 1.2° more up elevator than in glide; the full-size airplane needed 0.3–1.8° less. The RC installation differs: 1.75° kit down-thrust, CG 71 mm below the thrust line, gear-down drag, and a four-blade fixed-pitch propeller instead of a three-blade constant-speed one. It was not calibrated. Measured RC trim with and without power would decide it.
- XP-51 (Allison, 1° washout), not P-51D. The wing and tail planforms are the same family; NAA later changed the D's tail settings, and those values are not established.
- Figure readings are ±0.3° and ±3 mph; airspeed is taken as equivalent airspeed.
- Geometric scaling does not establish Reynolds similarity or the RC model's trim. A built model's rigging can differ by more than this correction.
- No `.orfl` baseline exists: the `--trace` route exits before the flight logger starts, and no pilot was available. The 8 s hands-off trace and the probe reports are the retained baselines.
