# AS-00: Ugly Stik reference review

**Status: Source and consumer audit complete, 2026-10-11; physical calibration gates remain open.** These findings supplement the [fleet comparison](physics-audit.md). They do not authorize a physical retune or change the model team's geometry.

## What the current reference represents

The [authored aircraft](../../../../app/data/aircraft/jensen_ugly_stik_60.json) represents a virtual balanced Jensen 60-class glow build. It is the catalog default and source donor for some other generators, but is not measured ground truth for those aircraft. Its 1.524 m span, 0.464515 m² area and 0.3048 m coefficient chord agree within source rounding. Inventory CG is 0.1209 m aft of LE. The source's 39.4% CG annotation is consistent with the approximately 12.07 in plan-reading chord; the simulator's 12 in coefficient chord gives 39.67%. Do not silently substitute one reference length for the other.

| System | Current input and consumer | Evidence limit / disposition |
| --- | --- | --- |
| Mass and CG | 20-component inventory, 2.885 kg; the last component is 0.284058291 kg virtual balancing mass. Loader derives CG and full six-entry inertia; rigid-body, trim and rotor-carrier calculations consume them. | The balancing component is about 9.85% of total mass. Its aft location strongly affects pitch/yaw inertia. This is neither measured ballast nor a hardware prescription. Preserve it until an actual assembly is weighed and balanced. |
| Inertia | Diagonal entries approximately 0.1154, 0.3871, 0.4841 kg·m²; off-diagonal entries are also consumed. | Jyy is 2.11 times the shared scaled UltraStick reference and emits a warning. The reference is not a target to tune toward. Measure the installed assembly and uncertainty before changing the tensor. |
| Attached aero | CLa 4.58/rad, Cma −0.723/rad and Clp −0.4496/rad are examples of borrowed UltraStick25e derivatives. Local surfaces/induced calibration reproduce the global oracle; several rate derivatives were later derived for this Stik. | Geometric similarity is an approximation, especially across Reynolds number, mass distribution and control hardware. The donor is not independent flight identification. |
| Stall | CLmax 1.1, CLmin −0.8, 6° blend width and sideslip blend 15–25°; shared local/full-envelope equations consume them. | CL limits and blend ranges are estimates. The approximately 9 m/s predicted 1-g stall is a consequence of the model, not a measured validation point. Validate positive/negative stall and recovery separately. |
| Controls | Aileron/elevator/rudder 20/20/25°; 0.14 s neutral-to-full servo time; shared command mapping, servo integration and actual model hinges consume them. | Throws are not published Jensen settings; servo/linkage response is estimated. The 170-check fleet hinge proof establishes sign/travel consistency, not real control effectiveness. |
| Propeller map | APC 12×6 nominal diameter uses borrowed UIUC APC Sport 11×6 Ct/Cp data; thrust and power use the declared diameter and standard n, J conventions. | The measured static point is around 5,954 RPM and the dynamic series around 6,000 RPM; the modeled static maximum is 11,149 RPM. The 0–0.373 J interval is interpolated without measurements. This is a different propeller and operating envelope, explicitly labeled borrowed. |
| Engine | O.S. MAX-61FX reference power 1,397.4 W at 16,000 RPM; running model targets 2,800–11,149 RPM with 0.25 s lag. | Brochure power is reference evidence; no shaft torque balance is enabled on Stik. In-flight unloading is absent from this approximation. Bench thrust/RPM and throttle-step data are needed. |
| Rotor inertia | 0.00035 kg·m² drives gyroscopic/acceleration coupling. | Its source estimates a 37 g propeller plus spinner/crankshaft, while the component inventory records a 46 g propeller. Reconcile the installed component and inertia measurement; do not equate total-aircraft box inertia with shaft polar inertia or automatically substitute a rod formula. |
| Gear | Mains 560 N/m each, nose 440 N/m, damping 18.6/18.6/16.5 N·s/m, travel 0.12 m; rudder-linked nose steering 20°. | Stiffness/damping were chosen for a plausible soft contact and the 240 Hz explicit solver. They are not measured wire-leg/foam-tire curves. Preserve the integrator bounds when fitting drop/rollout data. |
| Tire/field | Aircraft Crr 0.04, friction 0.8, peak slip 6°, breakaway 1.25; field multipliers are separate. | Several anchors come from full-size tire models, not RC grass measurements. Concurrent GP profiles add separately labeled radius/spin estimates; all current Stik wheels remain unbraked. |

## Datum check resolves a stale gear warning

The [visual geometry source](../../../../assets/aircraft/ugly-stik-60/geometry.json) has wing LE at visual Z = −0.115 m and shaft at Y = −0.005 m. `AirplaneBuilder.datum()` uses those exact values. Converting a visual wheel centre to aircraft LE coordinates requires subtracting these offsets, not comparing raw visual Z with aircraft x.

| Wheel | Visual bottom converted to aircraft LE (m) | Aircraft contact (m) | Interpretation |
| --- | --- | --- | --- |
| Main left/right | x = 0.100 − (−0.115) = 0.215; y = ±0.18; z = −0.220 − 0.0381 − (−0.005) = −0.2531 | [0.215, ±0.18, −0.2581] | Longitudinal/lateral locations agree. Physics bottom is 5 mm lower. |
| Nose | x = −0.251276 − (−0.115) = −0.136276; y = 0; z = −0.220 − 0.034925 − (−0.005) = −0.249925 | [−0.136, 0, −0.2549] | x differs by 0.276 mm; physics bottom is 4.975 mm lower. |

The historical contact-source note says visual main axle x = 0.10 m is ahead of CG. That compares different datums; it is not true of the current rendered placement. The mains are 94.1 mm aft of CG and the nose about 257 mm ahead. The static tricycle footprint is coherent. The retained source note is historical evidence, not a current geometric assertion. The approximately 5 mm vertical difference is real and remains an explicit model/physics-owner calibration item; changing wheel contacts changes equilibrium and crash geometry and requires coordinated before/after ground evidence. AS makes no numerical contact correction.

The aerodynamic reference z = 0.07 m is also an estimated force reference, not a promise that the mesh wing mid-plane uses that exact ordinate. Force-reference and visible-surface points have different meanings; a future change must preserve the force/moment transfer convention.

## Follow-up measurements, in order

1. Record an actual assembly configuration, component/total masses, CG and three-axis inertia, including fuel state and installed propeller. Resolve virtual ballast and the 37/46 g rotor-source discrepancy.
2. Measure installed propeller static/dynamic thrust and RPM coverage, then engine throttle steps. Replace borrowed curves only with a declared coefficient convention and range.
3. Measure physical control travel/linkage response; identify attached derivatives with held-out maneuvers, then positive/negative stall and recovery.
4. Reconcile model/contact datums with the model owner, then fit gear drops, unpowered coast-down, low-speed steering and breakaway on the actual field surface. Do not hide tire or contact errors in aerodynamic coefficients.

Primary methods/data references: [NASA small-UAV inertia measurement](https://ntrs.nasa.gov/api/citations/20170000461/downloads/20170000461.pdf), [UIUC propeller data and definitions](https://m-selig.ae.illinois.edu/props/propDB.html), and the quantity-level plan/manufacturer/derivation sources in the aircraft JSON. These sources guide measurement and interpretation; none measures this complete virtual build.
