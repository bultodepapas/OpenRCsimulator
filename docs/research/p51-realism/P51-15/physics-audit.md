# P51-15: P-51D physics audit and inventory correction

2026-10-12 · Revision 1 · **Status: bounded audit and inventory correction complete; model flight validation remains open.** Prefix: P51-15.

## Result

The shared loader computes the full aircraft inertia tensor from the component inventory: `AircraftData._validate_legacy()` builds mass-position-size parts, `AircraftData.inertia_about()` applies box and parallel-axis terms, and `Dynamics.evaluate()` uses the result in `RB.derivative()`. P-51 loads pass through shared local/global Aero and Propulsion paths. The graph identified these paths, but some retrieved snippets were stale; source reads and the independent oracle are authoritative.

P51-05 represented paired servos and main gear as centerline boxes extending through the space between the sides. The revised inventory separates aileron and flap servos at their geometry-derived control midpoints and main gear at ±half the geometry track, with a small estimated envelope for each item. The source inventory says the elevator servos are “in the stab roots”; their centers remain an inferred ±0.15 m, preserving the former 0.30 m pair-box half-width instead of moving them to the tail half-span midpoint. The actual elevator mounting stations are unmeasured. All pair masses, locations, and local envelope dimensions remain `estimated`.

The runtime-order full tensor changes from `[3.412230, 6.817989, 9.496622, 0, -0.269807, 0]` to `[3.861834, 6.817989, 9.946226, 0, -0.269807, 0]` kg·m². This is +0.449604 kg·m² in roll and yaw-axis moments: +13.18% Jxx and +4.73% Jzz. Jyy, products of inertia, 21.5 kg inventory mass, and CG `[0.177763, 0, -0.071146]` m are unchanged within JSON quantization. These are reference-build estimates, not measured moments of inertia.

The full tensor now appears in the generator's derivation table. The independent oracle uses geometry, point/box-mass equations, and the old merged-box widths to calculate expected ΔJxx/ΔJzz; it checks unchanged mass/CG and physics sentinels, then validates tensor positivity and the principal-moment triangle inequality using the full Jxz-coupled eigenvalues.

## Provenance corrections

The generated data now reports the implemented Oswald factor `e = 0.75`, the UIUC NAA 45-100 camber-line basis for `Cm0`, and the actual Schrenk plus Reynolds-dependent NACA TN 1945 section basis for `CL_max`. Throws are labeled as estimated values taken directly from the Hangar 9 Mustang 1.50 high-rate angles; the previous millimetre-to-angle conversion description was false. The 0.18 s control-response value is explicitly a normalized full modeled throw assumption; servo no-load speed cannot determine surface rate without the selected servo, voltage, load, horns, and linkage ratio. The report no longer equates rudder control trim with the full-size fixed fin offset, and scripted flight checks are no longer described as physical measurements.

## Remaining flight-model limits, ranked by impact

1. **Retracts remain down.** The drag build-up includes a 0.020 m² gear-down equivalent-area term before the common 1.1 excrescence factor—about 36% of the modeled zero-lift drag at the 25 m/s reference point. The 1/4-scale model has retracts, but the runtime capability is `locked_down_taildragger`; gear state, doors, and retract drag are absent. This directly affects cruise speed, climb, and glide. Do not remove that drag from the current gear-down state without adding a supported gear state.
2. **Engine and four-blade propeller are not identified.** The BEM prop table is fitted to manufacturer-simulated 26×12 two- and three-blade data (6.5% RMS) and predicts the four-blade case. The DA-120 torque shape is generic and scaled to one 28×10 static-RPM anchor. Throttle transients, static thrust, climb, windmilling drag, and power-on stall asymmetry remain sensitive to these estimates.
3. **Yaw stability omits a body contribution.** The generator computes an estimated destabilizing fuselage term `Cnb_body = -0.02325` but leaves it out; the model's `Cnb = +0.13949` is the fin contribution required by the shared surface-consistency rule. Applying the estimate would reduce this static derivative by about 17%, but the DATCOM term is itself approximate and needs a supported fuselage-side-force path before any correction.
4. **Stall/spin behavior is approximate.** P-51 stall uses three equal-area strips, Reynolds-dependent section limits (the 3×10⁵ endpoint is extrapolated), and a static smooth post-stall blend. The scripted stall test prescribes recovery inputs; it does not establish an unforced spin entry, autorotation, or recovery envelope for a built model.
5. **Rigging, CG, control response, and fuel state are reference-build assumptions.** The 27% MAC target is a kit placeholder; full-size rigging currently requires about 6.1° up elevator near 25 m/s and remains pending pilot review. Throws are borrowed from another model size. The fixed half-tank inventory has no burn state, so the estimated 0.37 kg forward fuel mass and its CG/inertia effect remain constant through flight. These need plans, installation data, or model measurements; this step does not retune them.
6. **Tail wash is partial.** Only tail pieces receive the estimated wash/swirl model; wing wash and near-static propeller jet normal force are absent. Flaps and retract dynamics are also not simulated.

## Proof and limits

From the repository root:

```powershell
python research/p51/p51-05/derive_physics.py
python research/p51/p51-05/derive_physics.py --check
python research/p51/p51-15/test_inventory.py
```

The generator check reports both outputs current. The oracle reports `mass 21.499999 kg`, CG `+0.177763 / -0.071146 m`, Jxx `3.861834`, Jyy `6.817989`, Jzz `9.946226 kg·m²`, and ΔJxx/ΔJzz `+0.449604 kg·m²`. These checks prove inventory math and provenance. Separate [airborne](airborne-results.md) and [ground/lifecycle](ground-results.md) engine runs assess numerical behavior; none substitutes for measured physical validation.
