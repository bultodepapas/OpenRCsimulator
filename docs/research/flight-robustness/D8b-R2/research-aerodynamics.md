# D8b-R2 A01–A06 — aerodynamic evidence for the Jensen Ugly Stik pull-up

2026-10-11 · **Status: research synthesis; physical-aircraft measurements and the proposed follow-up tests remain open.** This note supports D8b-R2d/e in the [pull-up plan](../../../UGLY-STIK-PULLUP-PLAN.md). It uses the Jensen 60-inch model identity, current simulation code and data, the completed D8b-R2 diagnosis, and the separate synthetic sweep in [supplement.json](supplement.json). It does not select new aircraft coefficients.

## A01 — Identify the exact airframe and its evidence

**Question.** Which Ugly Stik does this model represent, and which wing, CG, and control facts belong to that exact variant?

**Verified findings.** The target is the 60-inch “Jensen Das Ugly Stik,” with a .61 glow reference build. Outerzone oz1253 credits Phil Kraft and Jensen; keep it distinct from the 62-inch Grid Leaks oz5175 and later Stik derivatives. The Jensen title block and local data give 720 square inches, a 60-inch span, and an engine range of .45–.61. The simulator's .61 build is one configuration in that range; the plan does not specify installed engine or ready-to-fly mass. See the [oz1253 Jensen plan](https://outerzone.co.uk/plan_details.asp?ID=1253) and separate [oz5175 Grid Leaks entry](https://outerzone.co.uk/plan_details.asp?ID=5175).

The drawing shows a wing section but gives no standard airfoil name or coordinates. The local review calls it semi-symmetric with a flatter lower surface aft of the spar; that is a visual reading, not evidence for a named NACA or Great Planes section. The plan and kit inserts show linkages but give no numerical throws. Simulated throws (20° aileron/elevator, 25° rudder) and 0.14 s servo travel are estimates in [jensen_ugly_stik_60.json](../../../../app/data/aircraft/jensen_ugly_stik_60.json), not Jensen specifications.

The marked CG reads 4.76 inches aft of the leading edge (39.4% of the 12.07-inch chord), with about ±0.03 inch scan-reading uncertainty. The plan prints no distance or range; its kit note calls the mark a starting point dependent on build weight. Inventory includes a virtual balancing mass, not measured hardware or a ballast recommendation. Neither it nor the mark validates the inertia tensor.

**Change to the plan.** Use oz1253 as the geometry identity. Record CG as an uncertain scan measurement; keep installed CG, weight, inertia, throws, and servo timing as configuration-specific unknowns or estimates. Label inherited UltraStick 25e derivatives as borrowed, never as Jensen measurements.

**Limits and confidence.** High confidence in identity/span/area; medium in the scan-derived CG and visual section reading; low in flight inferences from estimated mass and controls. An older geometry note says no numeric CG read was found; the JSON cites a later image measurement. Treat it as an analyst read, not a printed setting.

## A02 — Reynolds number and a matching section polar

**Question.** Is the present stall curve supported by aerodynamic data for the Jensen section at its operating Reynolds number?

**Verified findings.** The current estimated envelope uses whole-aircraft CLmax 1.1, CLmin −0.8, and 6° stall-blend width. CLmax is the midpoint of an assumed 1.0–1.2 for a “semi-symmetric Jensen section” near Re 300,000; baseline CLa comes from an UltraStick 25e. No named section or Jensen lift/drag/moment polar is established locally.

For the 0.3048 m chord and standard-air ν≈1.5×10⁻⁵ m²/s, freestream Re is about 0.30M at 15 m/s, 0.51M at 25 m/s, and 0.61M at 30 m/s. Local rotation, temperature, roughness, and build variation are omitted. UIUC summarizes its model-aircraft-relevant low-speed data at about Re 60,000–500,000, with lift/drag and pitching moment in later volumes. This covers much, but not all, of the scenario range. Use data only if a tested contour matches the traced Jensen section: [test catalog](https://m-selig.ae.illinois.edu/uiuc_lsat.html), [scope FAQ](https://m-selig.ae.illinois.edu/ads_faq.html).

**Change to the plan.** Trace root/tip sections from scale-checked oz1253 ribs, recording thickness, camber, leading edge, and uncertainty. Find a tested contour match and compare static CL/CD and available CM across relevant Re and documented surface conditions. If no section or polar covers the contour/Re range, use nearby polars as bounds and plan a Jensen-like section test. Keep 2-D data distinct from finite-wing and aircraft CLmax.

**Limits and confidence.** High confidence the envelope lacks Jensen-matched validation; medium in the freestream Re estimate; low that an unmatched catalog polar represents a built RC wing. No UIUC polar has been selected or fitted.

## A03 — Load factor, accelerated stall, and loop geometry

**Question.** Can the 25 m/s pull-up reach stall or autorotation even though its entry speed is well above the model’s 1-g stall speed?

**Verified findings.** Yes, as a physical possibility. The FAA describes accelerated stalls as stalls at speeds above the +1-g stall speed when a maneuver raises load factor. From lift balance, if CLmax is unchanged, the corresponding stall-speed relation is Vstall(n) = Vstall(1g)√n. At the bottom of an ideal vertical loop of radius R, the required positive load factor is n = 1 + V²/(gR); this follows from centripetal acceleration and is not a command-to-path guarantee. The [FAA Airplane Flying Handbook, Chapter 5](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/06_afh_ch5.pdf) explicitly covers accelerated stalls during pull-ups and other abrupt flight-path changes.

The plan's model-derived 1-g reference is 9.51 m/s. At 25 m/s the same lift limit conditionally implies n≈(25/9.51)²=6.91, using estimated mass, area, density, and CLmax. This is not measured load, structural/safe limit, or proof the reproduction reached 6.91 g. That test holds full elevator and measures angle/roll; it neither prescribes loop radius nor regulates load.

**Change to the plan.** Log normal acceleration/weight, airspeed, path curvature, pitch rate, strip angles/loads, elevator command/deflection, and stall timing. Repeat fixed entry states with recorded input ramp, hold, release, and recovery. Compare onset with the section polar and wing load; report load factor and radius separately. Define a loop by input and entry energy; full elevator alone does not prescribe a circle.

**Limits and confidence.** High confidence in the load-factor relationship and the possibility of an accelerated stall. Low confidence in the Jensen’s actual onset, attainable n, structural margin, or loop radius because neither its structure nor its aerodynamic polar has been measured. The proposed load-telemetry and radius comparison have not yet been run.

## A04 — Post-stall lift slope and roll autorotation gain

**Question.** Is positive roll feedback after stall physically possible, and does the current magnitude follow evidence for this aircraft?

**Verified findings.** Roll rate changes local incidence by approximately py/V at each spanwise station. Below stall, positive lift slope normally opposes roll; when post-stall lift slope reverses, the differential lift can propel roll. NASA TP-1589 explicitly analyzes this autorotation mechanism and measures roll damping/cross derivatives on a general-aviation configuration, including forced-oscillation tests at Re 0.55 million. It also used an outdoor RC model and a full-scale airplane; leading-edge changes altered stall/spin behavior, with an outboard change improving lateral stability and spin resistance. This validates the mechanism and configuration sensitivity, not a Jensen-specific derivative. See the [NASA TP-1589 report](https://ntrs.nasa.gov/api/citations/19800004771/downloads/19800004771.pdf).

The local D8b-R2 derivative sweep is synthetic model evidence. In a new 25 m/s, neutral-surface, zero-base-rate scan, the stall-width helper was re-solved to the same CLmax = 1.1 while the model’s peak frozen-state dMx/dp changed:

| Stall-blend width | Peak dMx/dp (N·m per rad/s) | Actual total-aircraft CL peak |
| ---: | ---: | ---: |
| 4° | 17.131 | 1.1022 |
| 6° | 11.121 | 1.1051 |
| 8° | 8.085 | 1.1091 |
| 10° | 6.234 | 1.1141 |
| 12° | 4.977 | 1.1199 |

Every tested width retained a positive maximum derivative. The scan shows that a scalar lift peak does not determine roll-feedback gain: the assumed post-stall transition strongly changes it. The derivative is a local finite perturbation with other state variables frozen, not a complete aircraft eigenvalue or maneuver response. The scan and its source fingerprints are in [supplement.json](supplement.json) and [supplement-manifest.json](supplement-manifest.json).

**Change to the plan.** Keep stall slope, onset, and width unresolved until matched section data or a physical flight identification bounds them. Compare the section’s post-stall CL(α) slope with per-strip and integrated dMx/dp over the measured angle and rate history. Add mirrored perturbations and recovery histories, then evaluate the complete coupled response. Do not suppress positive roll feedback merely to remove the reproduced departure; retain autorotation wherever independent data support it.

**Limits and confidence.** High confidence that the current simulator’s frozen-state roll derivative is highly sensitive to its estimated transition width, and high confidence that NASA demonstrates configuration-dependent stall/spin effects. Low confidence in the physical Jensen gain or in any candidate width. None of the widths in this sensitivity scan is recommended.

## A05 — Spanwise separation and induced-flow consistency

**Question.** Does the current strip discretization and attached-flow induced map remain consistent as parts of the wing separate?

**Verified findings.** The current local wing model computes strip flow using body velocity plus angular-rate contributions. It applies an induced-angle matrix to the attached lift component, then blends toward a flat-plate law using the geometric strip angle. The matrix is generated from a planar, unswept Weissinger model and is solved to match the inherited airplane lift slope and zero-angle lift; it is not a fit to Jensen wing-force data. The active wing uses three equal-area strips per side. These assumptions and their attached-flow validation are described in the [D11d induced-flow report](../../aero-consistency/D11d/README.md) and implemented by [aero.gd](../../../../app/physics/aero.gd) and [aircraft_data.gd](../../../../app/physics/aircraft_data.gd).

The D8b-R2 supplement regenerated the induced map while refining from 3 to 6, 12, and 24 strips per side, holding the attached total lift slope fixed. Peak frozen-state dMx/dp fell from 11.121 to 10.357, 9.794, and 9.471 N·m per rad/s, but stayed positive. The same sweep reports a total-aircraft wind-axis CL peak near 1.1051. This is evidence of resolution sensitivity with recalibration, not evidence that more strips produce the right separated-wing physics. It also leaves a contract question: the helper CLmax remains near 1.10 while the total-aircraft peak is about 1.105 in the baseline sweep and varies with stall width. Keep helper, wing-only and whole-aircraft definitions separate before calling this a defect. See [E01–E02 methods and results](research-experiments.md).

The attached induced map and the per-strip separation law answer different questions. The former models linear circulation coupling; the latter applies one estimated stall curve without measured spanwise progression. A three-strip-per-side wing cannot resolve a fine progression of leading-edge separation, and a linear map is not a validated post-stall wake solution. This is a validation limit, not a confirmed code bug.

**Change to the plan.** Repeat both the recalibrated sweep and, once supported section data exist, a refinement with the section polar held fixed. Log geometric/induced angles, strip CL, separation weight, and per-strip forces/moments. Compare with an independent lifting-surface calculation within its attached-flow validity and with spanwise tuft, pressure, or force evidence for separation on a Jensen-like wing. Test which separation-angle convention matches evidence; require numerical convergence in both regimes before changing production resolution. Numerical convergence alone cannot validate separated-flow physics.

**Limits and confidence.** High confidence in the code path and supplement’s sensitivity results. Low confidence in whether the modeled separation front, nonlinear induction, or integrated peak CL matches the Jensen wing. This note’s proposed refinement/physical comparison beyond the parent’s synthetic sweep has not been performed.

## A06 — Dynamic stall versus quasi-steady response at pitch and roll rate

**Question.** Is instantaneous strip lift adequate during the rapid pull-up and departure, or does the wing need a history-dependent separation state?

**Verified findings.** The current load path in [aero.gd](../../../../app/physics/aero.gd) includes instantaneous rate effects: p, q, and r change local strip velocities and angles. It then evaluates wing stall weight and force from those angles, with no wing-separation memory. Existing lagged wing lift for tail downwash is separate; it delays tail flow and does not provide a dynamic wing polar.

Unsteady-airfoil experiments show why this distinction can matter. NASA TP-1100 measured a pitching NACA 0012 at Re = 2.5 million and reported history-dependent loads through dynamic stall; those data are at much higher Reynolds number and on a different section than the Jensen wing, so they establish hysteresis as a mechanism rather than a calibration target. The [NASA TP-1100 report](https://ntrs.nasa.gov/api/citations/19780009057/downloads/19780009057.pdf) documents those conditions. The [OpenFAST AeroDyn documentation](https://github.com/OpenFAST/OpenFAST/blob/main/docs/source/user/aerodyn/input.rst#unsteady-airfoil-aerodynamics-options) exposes several unsteady models but says their parameterization depends on airfoil and Reynolds number and recommends comparing load hysteresis in isolated test cases. It is a wind-turbine code base, and not a drop-in RC airplane stall law.

**Change to the plan.** From the recorded maneuver, calculate dimensionless pitch and roll rates, qc/(2V) and pb/(2V), using instantaneous V. For a section or wing with a matched Jensen contour, Re, and surface condition, compare a slow static polar with controlled pitch ramps and oscillations spanning those rates. Record force and moment versus angle on both increasing and decreasing sweeps. Only if the measured histories depart materially from the quasi-steady curve should D8b-R2e add a bounded, continuous-time wing separation state. Fit on one history and check the state against held-out ramp and recovery cases; do not copy NACA 0012 or AeroDyn time constants.

**Limits and confidence.** High confidence that the current wing law is quasi-steady and that published dynamic stall can exhibit hysteresis. Medium confidence that the reproduced high-rate pull needs a dynamic check because its roll rate rises sharply. Low confidence that dynamic stall explains the Jensen symptom or what lag parameter is appropriate. The scale-matched unsteady test and any candidate state remain unperformed.

## Research disposition

The strongest current evidence is about model sensitivity: stall width and spanwise discretization materially alter the frozen-state roll derivative while preserving the model’s scalar lift helper. The outside research supports testing accelerated load, spanwise separation, and rate history, but supplies no Jensen-specific numerical replacement. The next evidence should therefore identify the plan-matched section, build configuration, and time-resolved loads before the estimated stall law is retuned. The D8b-R2 diagnosis and the new sweep remain synthetic; physical validation is still open.
