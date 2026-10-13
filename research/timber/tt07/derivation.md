# TT-07 Timber configuration

2026-10-12. Generator: `derive_physics.py`; authored estimates: `inputs.json`; geometry: `assets/aircraft/turbo-lumber-evolution/geometry.json`. Run the generator, `sensitivity.py`, their `--check` modes and `test_derive.py` from the repository root. The generated aircraft is an experimental reference configuration, not a measured build.

## Configuration and frames

The B-reference loadout uses the manual's 1.555 m span, 2.190 kg loaded mass, 60 mm longitudinal CG and 800 Kv motor, a nominal 14.8 V fixed bus and an 11-inch propeller. The imported r1 mesh's measured area is 0.328223 m². Flaps stay neutral; slats, floats and receiver assists are absent. The bus does not model SOC, sag, thermal protection or ESC current limiting.

D0 is the model datum, not the wing mid-plane. Structural `[aft,right,up]` equals model `[Z,X,Y]`. The aerodynamic reference is the wing quarter chord at its measured height, extrapolated across the fuselage using the measured dihedral. Tail pressure centres use measured planforms. The thrust arm is the imported hub minus the derived inventory CG; down/right thrust are the imported 2°/2° angles. Wheel contacts are the imported centres minus their radii. Rendering and flight therefore use the same datum without copying render vectors into simulation state.

## Inventory and controls

Component masses, envelopes and vertical/lateral stations are estimates; longitudinal stations start from the author's r1 ledger. The ledger is not treated as the aircraft's mass. The 0.330 kg battery is the manual loaded-minus-empty difference. A declared virtual 0.250 kg residual at −0.2209984 m reconciles the inventory to 2.190 kg and 60 mm CG. It is not measured ballast. The inventory yields CG `[0.06,0,-0.0021757991]` m and full body-FRD inertia `[0.0942774360,0.1465091939,0.2204864286,0,-0.0003242920,0]` kg·m². Each aligned box contributes its intrinsic tensor and parallel-axis term. The loaded rotor must also leave a positive carrier tensor.

Throws solve `theta = 2 asin(d/(2r))` at the TT-02 assumed manual measurement stations, using the imported hinge-to-trailing-edge radius. The manual's 33/20/30 mm high rates produce approximately 34.475°/17.806°/18.150°. Servo full-throw time is an assumed 0.14 s. The authored approximate 22° range does not silently clamp the manual aileron throw; the existing builder drives the same physical angle as the simulation. Flaps are explicitly `not_simulated`.

## Aerodynamic estimate

Helmbold finite-wing lift slope is `2 pi kappa AR/(2+sqrt(4+AR²))`. The wing uses estimated section factor 0.9. Horizontal/vertical areas and arms come from the imported planforms. Downwash is the provisional elliptic estimate `2 a_w/(pi AR)`; horizontal pressure ratio is 0.9. A measured configuration would replace these assumptions. Thin-airfoil flap effectiveness and a gap/large-deflection factor 0.8 provide control derivatives; strip integration uses the measured aileron span. Tail-volume force/arm expressions supply pitch and yaw derivatives. The fin's linked CYdr/Cndr/Cldr/Cnb exactly obey the loader's force-arm consistency rule.

The estimated cambered section's zero-lift angle is −0.035 rad and its pitching couple is −0.035. The supported `wing_section_cm_ac` module applies that couple to the local wing; Cm0 carries it in the oracle. Drag is an assumed skin/form coefficient 0.025 plus exposed gear drag area 0.004 m² and excrescence area 0.002 m², divided by wing area; CD0 is 0.0432803. Induced drag uses estimated Oswald efficiency 0.8. Control drag, body side force, high-wing dihedral increment, tail limits and adverse yaw remain identified estimates.

Clean peak lift 1.6 yields a nominal 1-g stall speed of 8.17118 m/s. Airborne start is 1.6 times that speed: 13.07389 m/s. These are model estimates, not flight measurements. The current local/attached solver, post-stall blend and coupled electric shaft remain the production physics; no aircraft-specific force kernel or hidden handling gain is added.

## Propeller and motor evidence

The reviewed [UIUC database](https://m-selig.ae.illinois.edu/props/propDB.html) supplies no matched EFL5962 three-blade map used here. The selected source is [APC Sport 11×7, Volume 1](https://m-selig.ae.illinois.edu/props/volume-1/propDB-volume-1.html), borrowed for the 11×7.3 three-blade reference. Exact source URLs and SHA-256 values are retained in the two adjacent manifests. Original bytes and G1a1 importer reports are local under `references/timber/uiuc/`; the repository retains the selected numerical knots in `inputs.json`, not the raw third-party files.

The static knot is the 6,170 rpm row (Ct 0.1204, Cp 0.0538). Tunnel knots use the 6,002 rpm run label, with no per-row RPM. The J=0 to J=0.373 bridge is linear and unmeasured. The runtime saturates outside the last J=0.876 knot. Coefficient-reference diameter, blade count, pitch, Reynolds number and installation mismatch remain unresolved. Ct/Cp multipliers are explicitly varied independently in `sensitivity.md`; no three-blade correction is silently fitted.

Equivalent winding resistance 0.08 Ω, no-load friction current 1.2 A and rotor inertia 0.00024 kg·m² are estimates. The ideal motoring law gives approximately 9,400 rpm and 38.13 A at full-throttle static equilibrium. This is not a current ceiling: spool transients exceed the 70 A hardware rating in the unconstrained ideal ESC model. Positive Cp and bearing friction stop the rotor when the source is disabled; this map provides no driven windmilling torque.

## Ground and uncertainty

Total contact stiffness is `m (0.09 × 240)²`; the split follows actual static load fractions in the tilted support plane. Tail load fraction is approximately 0.1240. Contact damping ratio is 0.3 under the loader's per-contact `m/3` convention, maximum compression 0.08 m, and steering −30° at the tail for positive right rudder. Wheel radii come from the mesh; inertias and tyre/friction coefficients are estimates. Hull points include wing/tail extrema, fuselage bottoms and the rotating propeller's lower envelope, excluding wheels.

`sensitivity.md` varies every declared estimate. Manual total mass and longitudinal CG remain fixed through the virtual balance, including the ±76.6 mm nose-station experiment. It does not bound each unidentified component's true uncertainty. Static support, stable trim, repeatability and software checks do not establish the measured landing, stall, aerobatic or STOL envelope.
