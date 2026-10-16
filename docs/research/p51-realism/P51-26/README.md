# P51-26: powered directional stiffness — slipstream quadrature and propeller sidewash

2026-10-16 · Revision 2 · **Status: implemented in the runtime as the P-51's opt-in `propeller_sidewash` slipstream law. Powered rudder per sideslip is now a smooth 0.62–0.68 °/° (was 0.52–0.89), against the P-51D's 0.46–0.55.** Revision 1 (2026-10-15) diagnosed two defects in the shared legacy slipstream path and left a candidate for the slipstream owner; it is kept below. Prefix: P51-26. [Plan](../../../P51-REALISM-PLAN.md) · [Tools](../../../../research/p51/p51-26/README.md)

## Runtime implementation — 2026-10-16

Godot 4.7.2 official, native Windows, 240 Hz; base commit `1516cb77` with the P51-22 test-pilot corrections. Logs and probe output: [runtime-20261016](runtime-20261016/).

`propulsion.propeller.slipstream.propeller_sidewash` (value 1, Ribner's published relation) selects the law on the legacy pieces; without it the legacy centroid arithmetic is unchanged, and `test_slipstream_scalar.gd` still matches its frozen oracle in 10001 comparisons. The P51-05 generator writes the field; the v1 schema source, the contract and the loader reject it with smooth profiles or axial transport. Each immersed piece is split at the swirl-core crossings and the jet centre. Every segment gets its exact area and centroid and its chord-weighted five-point Gauss mean swirl. The jet crossflow follows Ribner's eq. (8) in both planes; without a normal-force table only the h(a) term remains. The tail law inside the segments is an allocation-free copy of `Aero._tail_surface_from_flow` (equal to 0 relative error in the test).

| Quantity (level flight unless stated) | HEAD `1516cb77` | Implemented | Reference |
| --- | --- | --- | --- |
| Rudder per sideslip, ±1° / ±2°, 20 m/s | 0.520 / 0.777 | 0.678 / 0.645 | P-51D 0.46 at 103 mph, 0.55 at 200 mph (RM L6J25) |
| Same, 25.7 / 28.6 / 35 / 45 m/s (±1°) | 0.892 / 0.757 / 0.664 / 0.617 | 0.642 / 0.639 / 0.632 / 0.631 | as above |
| Glide (stopped propeller), all speeds | 0.546–0.552 | unchanged | 0.55 |
| Power-on minus glide elevator, 22–45 m/s | −0.79 to −0.82° | −0.41 to −0.52° | XP-51: +0.3 to +1.8° (MR L-566 Fig. 10) |
| Takeoff run without rudder, heading after 3 s | −57.7° | −30.6° | manuals: strong left swing |
| Takeoff with the heading pilot: right rudder, heading error | 0.48, 7.4° | 0.32, 5.1° | — |
| α-held loop: pitch max, \|β\| max | 81°, 9.6° | 90°, 6.2° | gate > 80°, < 10° |

Convergence ([probe](../../../../research/p51/p51-26/convergence_probe.gd)): against 256 subdivisions per segment, the slipstream yaw per sideslip is within 1.05 % at 18 m/s and 0.19 % at 45 m/s, falling about 3× per halving. The legacy centroid is off by up to 120 %. `test_slipstream_sidewash.gd` checks ≤ 1.5 % and ≥ 2.5× convergence; it first used 1 %, which was set before measuring and missed by 0.05 %. The zero-flow limit is unique to 5e-8 N, N·m from eight directions; Ribner's g and h stay within 1.0–1.21; the term vanishes without crossflow. All P-51 checks pass: 14 ground, 18 handling, 17 envelope.

**Cost.** `Slipstream.loads` takes 87 µs against 46 µs for the centroid law ([breakdown](../../../../research/p51/p51-26/cost_breakdown.gd)); the P-51 tick rises from 1189 to 1392–1415 µs (+18 %; 1628–1655 µs before the allocation-free tail law). The 500 µs target remains open for this aircraft (P51-18). **Still open:** powered rudder per sideslip remains ≈ 0.1 °/° above the P-51D, and the power-on trim change keeps the wrong sign at half its former size; P51-26's caveats on the estimated 1° right thrust and the unshielded free vortex apply. These are not calibrated away.

## Question

After [P51-25](../P51-25/README.md), rudder per sideslip is 0.55 °/° in a glide, the P-51D's value. In level flight it is 0.68–1.0 °/° and highest at low speed. RM L6J25 measured 0.55 at climb power and 0.46 at its highest-power point (103 mph).

## Finding 1: centroid swirl quadrature on the legacy tail law

[`deriv_probe.gd`](../../../../research/p51/p51-25/deriv_probe.gd) shows where the slipstream's directional term at 28.6 m/s comes from:
- **Swirl:** Cnβ +0.030 of the total +0.042.
- **Axial wash:** +0.011.

Removing the estimated 1° right thrust angle drops the swirl part to +0.0003. The legacy path (the P-51 is the only aircraft with a slipstream, and its shaft is not axial, so it cannot use the smooth E0b3b/E0b6 route) evaluates the free-vortex swirl, Γ/r with a 0.3R solid core, at one area-centroid point per tail piece. The side-thrust offset and the sideslip drift move the jet a few centimetres relative to the fin. Near the core kink, that point value changes erratically. E0b6 had already identified this centroid swirl error for the smooth route; this is its size on the P-51's legacy path.

[`strip_swirl_probe.gd`](../../../../research/p51/p51-26/strip_swirl_probe.gd) evaluates the same law over the immersed span. With one strip it reproduces `Slipstream.loads` exactly (difference 0). Slipstream contribution in level flight, per radian ([output](quadrature.txt)):

| Speed | Cnβ, runtime (centroid) | Cnβ, 1024 strips | Cnβ, piecewise candidate | Clβ, 1024 strips / piecewise |
| --- | ---: | ---: | ---: | ---: |
| 20 m/s | 0.0164 | 0.0309 | 0.0309 | −0.0085 / −0.0076 |
| 25.7 m/s | 0.0581 | 0.0271 | 0.0270 | −0.0074 / −0.0069 |
| 28.6 m/s | 0.0416 | 0.0268 | 0.0267 | −0.0073 / −0.0069 |
| 35 m/s | 0.0302 | 0.0258 | 0.0258 | −0.0068 / −0.0065 |
| 45 m/s | 0.0245 | 0.0254 | 0.0254 | −0.0065 / −0.0063 |

The integrated law is smooth in speed. The centroid value is wrong by up to ×2.15 in either direction. Rudder-power terms are unaffected (Cndr agrees within 0.3 %). Five-point Gauss-Legendre split at the span line's core crossings matches 1024 strips within 0.1 %. The **piecewise candidate** splits the immersed span at the core crossings and the jet centre and evaluates the tail law once per segment (≤ 4) with that segment's Gauss-averaged swirl. It is within 0.5 % for Cnβ and within 3–10 % for the slipstream Clβ (≤ 1.3 % of the airplane's Clβ). A single evaluation with the span-mean swirl keeps Cnβ within 2 % but loses the swirl roll couple (35–45 % of the slipstream Clβ).

## Finding 2: the jet has no propeller sidewash

A yawed propeller's normal force N is the air's crossflow momentum, so the slipstream reaching the fin carries less crossflow than the free stream. The legacy law adds the wash along the shaft and leaves the crossflow unchanged.

Ribner gives the far-wake sidewash of a yawed propeller as dσ/dψ = A + B·C′Y′ψ ([NACA ARR L4I12a, eq. 8](sources/ribner-l4i12a-p12-sidewash.png), [NTRS 19930092551](https://ntrs.nasa.gov/citations/19930092551)), with A = 2a(1+2a)/[1+(1+2a)²] and B = 1/(2[1+(1+2a)²]). Converted to the jet crossflow:

v_c,jet = h(a)·v_c + ½·g(a)·N/ṁ, with h = (1+2a)(2+2a)/[1+(1+2a)²] and g = 2(1+a)(1+2a)/[1+(1+2a)²].

- **h(a):** 1.0–1.2 for every a. This is Ribner's correction to wash-along-the-axis.
- **g(a):** 1.0–1.2 for every a. With ṁ floored like the swirl's, the term stays bounded at static thrust.
- **N:** taken from the existing `normal_force` table, so the term adds no new parameter.

**Rejected first form.** Subtracting (A + B·C′Y′ψ)(1+2a)·v_c from the crossflow gave a powered rudder per sideslip of 0.53–0.57, an apparently perfect match ([output](sideslip-rejected-double-counted-ribner.txt)). It double-counted the A term, which the axial wash already represents, and it diverges toward static thrust. The near-perfect agreement was the warning sign.

## Flight consequences (disposable copies of `app/`)

[Patch: piecewise quadrature + Ribner sidewash](../../../../research/p51/p51-26/candidate-piecewise-ribner.patch); [mean-swirl variant](../../../../research/p51/p51-26/candidate-mean-swirl-on-top.patch).

| Rudder per sideslip, level, 20 / 25.7 / 28.6 / 35 / 45 m/s | Result |
| --- | --- |
| [Runtime](sideslip-runtime.txt) | — / 1.005 / 0.850 / 0.739 / 0.680 |
| [Dense quadrature only](sideslip-dense-quadrature-only.txt) | — / 0.686 / 0.694 / 0.695 / 0.698 |
| [+ Ribner normal-force term only](sideslip-dense-plus-normal-force-only.txt) | — / 0.633 / 0.640 / 0.644 / 0.649 |
| [+ full Ribner eq. (8)](sideslip-dense-plus-full-ribner.txt) | — / 0.715 / 0.718 / 0.714 / 0.716 |
| [**Piecewise candidate + full Ribner**](sideslip-candidate-piecewise.txt) | **0.738 / 0.716 / 0.719 / 0.715 / 0.716** |
| [Mean-swirl candidate + full Ribner](sideslip-candidate-mean-swirl.txt) | 0.729 / 0.707 / 0.711 / 0.708 / 0.710 |
| P-51D, RM L6J25 (climb power) | 0.46 at 103 mph, 0.55 at 200 mph |

Glide values are unchanged (0.546–0.552) because a stopped propeller has no slipstream. The full Ribner relation is kept as the candidate because it is the published, experimentally compared form, not because it is closest to the target. The excess over 0.55 changes from +0.13…+0.45 (erratic, largest at low speed) to a nearly constant +0.16…+0.19. At 45 m/s the candidate is slightly stiffer than the runtime: the centroid error was not one-signed.

**Trim:** the power-on minus glide elevator goes from −1.11…−1.13° ([runtime](trim-runtime.txt)) to −0.62…−0.76° ([candidate](trim-candidate.txt)), where negative means more up elevator with power. The XP-51 needed 0.3–1.8° *less* up elevator with power (MR L-566 Fig. 10, as in [P51-19](../P51-19/README.md)). The candidate moves the right way but does not reverse the sign. The RC installation still differs: 1.75° downthrust, CG 71 mm below the thrust line, fixed-pitch four-blade propeller.

## Cost

Best-of-7 `Slipstream.loads` at a powered sideslipping state, interleaved on the shared host ([output](cost.txt)):

| Variant | µs per call | Per tick (4 RK stages) |
| --- | ---: | ---: |
| Runtime | 93–108 | 374–433 |
| Mean-swirl candidate | 149–161 | 598–645 |
| Piecewise candidate | 201–211 | 804–845 |
| Dense 5-point Gauss on every segment | ≈ 330 | ≈ 1,330 |

None fits the open 500 µs whole-tick target, which the P-51 already exceeds (P51-18, E0b6p). The candidate code is plain GDScript with array allocations and has not been optimized.

## Recommendation (for the physics / propwash owner)

1. Replace the legacy centroid swirl with the piecewise quadrature, or extend the smooth E0b6 route to non-axial shafts, under the E0b6p cost gate. The error is a numerical defect of the current law, not a modelling choice.
2. Add Ribner's sidewash as an opt-in, provenanced slipstream term. It has no new parameter.
3. Then re-check the P-51: powered rudder per sideslip (about 0.72 expected), power-on trim and the P51-15 probes.

The remaining ≈ +0.17 °/° is not explained. The integrated swirl term (Cnβ ≈ +0.015) exists only because of the estimated 1° right thrust, and the free vortex runs to the fin root with no fuselage shielding. Both are unvalidated. Do not calibrate it away.

## Limits

Steady, linear sideslip derivatives on the runtime equations; no flight log. Ribner's relation is for an isolated propeller far behind the disc; the P-51 fin is about three diameters aft and partly shielded by the fuselage. The swirl strength, core and `k_w/2` attenuation are unmeasured E0b model choices. RM L6J25 slopes are approximate.
