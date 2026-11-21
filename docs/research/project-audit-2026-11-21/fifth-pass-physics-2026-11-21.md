# A36 R5 — actuator feasibility, event geometry, thermal stability and control loads

**Review date:** 2026-11-21. **Reviewed source:** `136b32e585dc84293b81fc036a81530a04da5397` on the existing [audit branch](https://github.com/bultodepapas/OpenRCsimulator/tree/audit/physics-math-aero-2026-11-21). Application source is unchanged from the previously qualified A36 runtime commit `d2bf10025b74764b424f1d0e72193b3e14281a0e`. This batch adds research, executable witnesses and evidence corrections; it implements no production fix and does not supersede the original A36 PDF/ZIP.

The strongest new connection is between **an accepted subsystem interface and the mathematical assumptions of its consumer**: clamped servo commands versus applied blade pitch; a trajectory's distance from its chord versus its gate-plane intersection; individually admitted battery parameters versus explicit-integrator stiffness; and two aerodynamic paths claiming related induced-lift behavior. Each entry below includes a counterexample, a competing explanation, repair choices and outstanding qualification.

## Findings and scope

| ID | Finding | Evidence established | Priority / owner |
| --- | --- | --- | --- |
| **R5-F01** | Helicopter airborne cyclic trim is added after swash travel limits; the applied angle combination can lie outside the declared instantaneous linkage's feasible set | Stock X-Cell data, real session setup and accepted 240 Hz reference tick; separately evaluated initial component stage; independent inverse-mixer oracle | **P2**, [helicopter plan](../../plans/helicopter.md); a specific trim-coupling extension to existing actuator work |
| **R5-F02** | The race's chord deviation allowance is used as a gate-plane allowance without accounting for the crossing angle | Actual track preparation, crossing, director and suffix validator on an analytic constant-acceleration piece; 10 witness assertions and independent geometry | **P2**, existing FPV race path-policy owner; conditional curved-path evidence defect |
| **R5-F03** | Custom battery thermal stiffness is absent from the launch-time step guard | Complete custom-data admission, flight setup, warm checkpoint restore and accepted reference tick; independent RK4 calculation and ambient-start positive-heat witness | **P2**, [battery realism plan](../../plans/battery-realism.md); custom-data numerical-domain defect |
| **R5-G01** | Attached/global and local strip paths apply ground effect differently to differential aileron loading | Stock Stik admission and public/component loads; independent strip algebra and signed/neutral controls | **P2 investigation**, [M5-GE-1](../ground-effect/M5-GE-1/README.md); internal consistency/calibration gap |

These priorities concern supported behavior and qualification work. They are not measured crash rates, handling severity or a claim that the shipped battery catalog is unstable.

## Reproducible evidence

The [portable reproducer](probes/reproduce_fifth_pass.py) reconstructs **439 real source/data/resource dependencies** from the pinned Git commit: the existing [432-file integration manifest](integration-manifest.json), plus five race source/test files and two battery data files. It verifies every baseline blob and fixture SHA-256, preserves the manifest's 20 explicit LF-to-CRLF data conversions, and verifies the official Linux x86-64 engine's SHA-256. There are **no production stubs**. Only the three declared synthetic battery JSON files are changed inside the generated fixture; repository application files remain untouched.

```bash
python3 docs/research/project-audit-2026-11-21/probes/reproduce_fifth_pass.py \
  --repo-root /absolute/path/to/OpenRCsimulator \
  --godot /absolute/path/to/Godot_v4.8-beta2_linux.x86_64 \
  --out /absolute/path/to/new-r5-output
```

The output directory must not exist. The script preserves the checked runner's testqueue/pool admission behavior, isolates user settings, imports the project, executes six entrypoints, then requires three independent Python oracles. **Godot completion markers alone do not prove the helicopter or ground-effect discrepancies**; their mandatory oracles assert the observed disagreement. The numerical oracle independently checks the race intersection and the thermal amplification/refinement. The [evidence record](fifth-pass-evidence.json) embeds checked reports, complete small engine logs, oracle output, source identities and generated-data hashes.

| Executed check | Result and actual scope |
| --- | --- |
| Clean isolated project import | Passed; real dependencies, no complete-app/rendered qualification |
| [Helicopter probe](probes/fifth_pass_helicopter_trim.gd) + [servo oracle](probes/fifth_pass_servo_oracle.py) | Passed; accepted session tick and infeasible applied angle triple |
| [Race probe](probes/fifth_pass_race_curve.gd) + [numerical oracle](probes/fifth_pass_numerical_oracle.py) | 10 assertions passed; analytic curve versus actual production director |
| [Thermal probe](probes/fifth_pass_thermal_stiffness.gd) + numerical oracle | 15 assertions passed; custom-data admission, checkpoint, startup and diagnostic refinement |
| [Ground-effect probe](probes/fifth_pass_ground_effect.gd) + [strip oracle](probes/fifth_pass_ground_effect_oracle.py) | Passed; nine component cases, independent signed/neutral checks at zero angle of attack |
| Unchanged `test_race_gate_crossing.gd` | **19 checks passed** |
| Unchanged `test_race_director.gd` | **33 checks passed** |

All seven checked invocations completed with **zero engine errors and warnings** using Godot `4.8.beta2.official.cafc17a19`, SHA-256 `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`. Independent review strengthened explicit assertions for the ground-effect discrepancy and the helicopter's trim/derivative comparison; the published evidence comes from a fresh reconstruction using those final oracles. The original A36 413-check record remains separate and was not rerun here. Native execution, full application CI, rendered/piloted flight and physical calibration are separate gates.

## R5-F01 — cyclic trim bypasses the instantaneous swash feasibility constraint

### Trace and witness

[Air-start trim](https://github.com/bultodepapas/OpenRCsimulator/blob/136b32e585dc84293b81fc036a81530a04da5397/app/physics/rotorcraft/trim.gd#L108) supplies cyclic feed-forward, installed by [the helicopter session](https://github.com/bultodepapas/OpenRCsimulator/blob/136b32e585dc84293b81fc036a81530a04da5397/app/sim/helicopter_flight_session.gd#L714). [Electronics.fast_evaluate](https://github.com/bultodepapas/OpenRCsimulator/blob/136b32e585dc84293b81fc036a81530a04da5397/app/physics/rotorcraft/electronics.gd#L186) mixes the pilot axes, clamps each servo target to `[-1,1]`, unmixes through the linkage, and **then adds cyclic trim**. Independently limiting the resulting cyclic axes does not enforce the combined three-servo constraint.

The stock X-Cell JSON has SHA-256 `29b4cbc6ff258c18839589b1eacd88968b58bc691dd61502177bb741c0c1da04`. The real session starts airborne at NED `[12,4,-3]` m above flat ground at zero, in normal mode with trainer enabled and rotor speed `167.749173686879 rad/s`. Centered cyclic and collective input `+1` give:

| Quantity | Observed value |
| --- | --- |
| Bounded instantaneous swash targets | `[1, 1, 1]` |
| Collective pitch sent to rotor | `0.22 rad` |
| Forward / right cyclic sent to rotor | `−0.000390410174688138`, `+0.00180194001566469 rad` |
| Blade angles implied by those three targets | `[0.22, 0, 0] rad` |
| Servo positions required by the applied angle triple | `[0.993493163755, 1.029262181950, 0.977244654295]` |
| Excess above rear-right upper travel | **0.029262181950 normalized units**, 2.9262% of the positive unit limit |
| Reference tick | `0 -> 1`, accepted, no fault |

These are the model's instantaneous target positions, not separately integrated or measured physical servos. `servo_travel_limited=false` is not itself a defective diagnostic: the original `[1,1,1]` targets sit exactly at the limits and require no clipping. The issue is the subsequent angle modification.

### Independent proof and challenged interpretation

For the [120-degree swash map](https://github.com/bultodepapas/OpenRCsimulator/blob/136b32e585dc84293b81fc036a81530a04da5397/app/physics/rotorcraft/swash.gd#L73), let normalized collective and cyclic axes be `c,l,r`:

\[
s_f=c+l,\qquad s_{rr}=c-\tfrac12l+\tfrac{\sqrt3}{2}r,
\qquad s_{rl}=c-\tfrac12l-\tfrac{\sqrt3}{2}r.
\]

Their mean is `c`. The stock gains are 0.22 rad/unit collective and 0.06 rad/unit for each cyclic axis. At collective 0.22 rad, `c=1`. If each servo is bounded above by one and their mean is one, **all three must equal one**, forcing both cyclic components to zero. The logged nonzero cyclic pair is therefore outside this linkage's feasible set; this conclusion does not depend on a chosen servo-lag model or a physical flight estimate.

The separate initial-stage [flight-dynamics evaluation](https://github.com/bultodepapas/OpenRCsimulator/blob/136b32e585dc84293b81fc036a81530a04da5397/app/physics/rotorcraft/flight_dynamics.gd#L172) confirms the rotor consumes these harmonics. With computed trim, flap rates are approximately `[0,0] rad/s`; zeroing only the two cyclic biases gives `[-0.013876778260,-0.064048335970] rad/s`. These are **component derivatives evaluated at the initial state**, not a derivative extracted from the accepted tick. The accepted tick separately establishes session reachability.

An interpretation of trim as an independent pitch actuator would need an explicit additional mechanism and limits; none is represented in the examined swash map. At hover collective the biased triple can remain feasible, while the reported targets still fail to represent it. The high-collective witness is stronger because no bounded target triple can produce it. Existing HELI actuator work already owns achieved-servo dynamics; this entry adds a specific trim-bias feasibility case and does not count missing servo lag as a new discovery. The [native control source](https://github.com/bultodepapas/OpenRCsimulator/blob/136b32e585dc84293b81fc036a81530a04da5397/research/native-kernel/src/nk_helicopter_controls.hpp#L130) has the same ordering, but no native binary was executed.

### Repair choices and acceptance

1. Add trim in normalized control space **before** the mixer/travel constraints, then derive every applied angle and the corresponding telemetry from that same bounded result. Establish collective/cyclic priority and requalify the hover trim solution under saturation.
2. Use a constrained servo-space allocator with declared priorities and feedback of achieved axes to any controller that requires anti-windup. If a separate pitch mechanism is intended, model and bound it explicitly.

Separately clamping final collective and cyclic angles cannot enforce the coupled feasible set. Acceptance should cover zero trim, the existing feasible hover, both trim signs, combined cyclic, both collective limits, trainer/direct modes and mode changes; then accepted 240 Hz flight, diagnostic refinement, actual reference/native agreement, rollback/checkpoint/replay and any required law identity change. No crash, visible handling severity or real-helicopter error has been measured.

## R5-F02 — distance from a chord is not the same uncertainty as its plane intersection

### Trace and constructed production call

[Gate crossing](https://github.com/bultodepapas/OpenRCsimulator/blob/136b32e585dc84293b81fc036a81530a04da5397/app/sim/race/gate_crossing.gd#L22) calculates `epsilon = A*h^2/8`, then uses it unchanged in both aperture coordinates. [RaceDirector._score](https://github.com/bultodepapas/OpenRCsimulator/blob/136b32e585dc84293b81fc036a81530a04da5397/app/sim/race/race_director.gd#L280) declares that allowance as in-plane uncertainty, with `A=250 m/s²`, a 240 Hz step and a minimum normal chord speed of 1 m/s. The literal straight-chord classification is implemented consistently. The defect is in the **conditional interpretation of that allowance as curved-path evidence**, even when the acceleration envelope genuinely holds.

The probe prepares the existing four-gate square test document through the real `Track.load_document/prepare` API. For the first gate, half-width `w=1.5 m`, use normal coordinate `x`, aperture coordinate `y`, step `h=1/240 s`, normal chord speed `v_n=2 m/s`, tangential speed `v_u=40 m/s` and constant normal acceleration `a=40 m/s²`:

\[
x(t)=-v_nh/2+(v_n-ah/2)t+\tfrac12at^2,\qquad
y(t)=w-0.001+v_u(t-h/2).
\]

The actual normal speed remains between 1.9167 and 2.0833 m/s, above the grazing cutoff throughout. Acceleration is constantly 40, below 250 throughout. This avoids relying on endpoint acceleration estimates to hide an unbounded interior spike.

| Quantity | Result |
| --- | ---: |
| Maximum same-time curve-to-chord deviation | **0.086806 mm** |
| Existing allowance `250*h²/8` | **0.542535 mm** |
| Chord aperture coordinate | **1.499000 m**, classified inside |
| True plane-crossing time | **0.00212671728943 s** |
| True aperture coordinate at that time | **1.50073535824405 m**, outside by 0.735358 mm |
| Error between the two plane intersections | **1.735358 mm** |
| Real director output | One `race_gate` event; resulting suffix passes validation |

The existing **19 gate and 33 director checks still pass**. Their success does not test this angle-dependent projection property.

### Why the allowance grows

Write the continuous path as a chord plus residual, `P(t)=C(t)+r(t)`, and let `t_c` be the chord's plane-crossing time. At the continuous crossing `t_*`, the plane equation gives

\[
t_*-t_c=-r_n(t_*)/v_n.
\]

The difference in aperture coordinate is consequently

\[
\Delta u=r_u-(v_u/v_n)r_n,
\qquad |\Delta u|\le\epsilon\sqrt{1+(v_u/v_n)^2}.
\]

The same derivation applies to the other aperture axis. A full in-plane norm bound uses `epsilon*sqrt(1+||v_t||²/v_n²)`. This is a conditional geometric bound, not a measured flight error. A full acceleration-norm bound supplies a same-time vector residual bound; the source instead states chord-normal acceleration, for which the perpendicular residual is sufficient because the projection annihilates the residual component parallel to the chord. The witness satisfies the stronger full-vector condition. The factor `A*h²/8` itself follows from the linear interpolation remainder; [NIST DLMF §3.3](https://dlmf.nist.gov/3.3) provides the underlying interpolation-error formula.

For the witness the conservatively projected allowance is **10.864249 mm**, so the present chord point should be **unresolved** under that stronger curved-path policy. Zero tangential speed reduces the formula to the existing allowance; a truly straight path has zero actual residual. An endpoint `Δv/h` guard alone cannot establish a pointwise acceleration bound, and this correction would not prove the absence of cross-and-return paths or multiple roots.

### Repair choices and acceptance

1. Retain chord scoring with explicitly projected per-gate/per-axis bounds, declared acceleration qualifications and conservative handling near grazing. Account for crossing-time uncertainty in gate/terminal event ordering as well as aperture position. Version the path policy and recorded identity if results change.
2. Locate plane events on a qualified within-step trajectory representation, carrying its interpolation/error bounds into aperture and ordering decisions. [SUNDIALS' rootfinding discussion](https://sundials.readthedocs.io/en/v7.7.0/cvodes/Mathematics_link.html#rootfinding) is a numerical-method reference, not a proposal to replace the existing kernel or proof that sign changes detect every root.

Required tests include tangential/normal speed ratios, both aperture edges, rotations, straight and curved controls, grazing, crossing near step endpoints, multiple gate order and physical terminal ties, refinement and replay. Keep the 240 Hz transaction/event owner. The witness calls the production director with a constructed piece; it **does not integrate an FPV plant, install a gate collision world, or establish an actual flown false award**. A physical trajectory near the frame could have a collision outcome. The demonstrated defect is narrower and mathematical.

## R5-F03 — independently admissible battery parameters create an omitted fast thermal mode

### Admission-to-integrator trace

[BatteryData](https://github.com/bultodepapas/OpenRCsimulator/blob/136b32e585dc84293b81fc036a81530a04da5397/app/physics/battery/battery_data.gd#L87) accepts pack mass down to 0.001 kg, specific heat down to 100 J/(kg K), and still/forced heat-transfer coefficients up to 1000 in their respective units. It derives thermal capacity `C_th=m*c_p`. [PackEcm](https://github.com/bultodepapas/OpenRCsimulator/blob/136b32e585dc84293b81fc036a81530a04da5397/app/physics/battery/pack_ecm.gd#L187) integrates

\[
C_{th}\dot T=Q_{cell}-H(T-T_a),\qquad
H=H_{still}+H_{forced}\sqrt{v_{cool}}.
\]

The [launch guard](https://github.com/bultodepapas/OpenRCsimulator/blob/136b32e585dc84293b81fc036a81530a04da5397/app/sim/flight_session.gd#L467) includes motor, charge/OCV, RC and voltage-filter rates. `_pack_step_ratio` omits `H/C_th` and states that thermal time constants are minutes. That is reasonable for the examined stock packs; it does not follow from the admitted custom-data ranges.

### Fully admitted numerical witness

The generated fixture starts with the stock Turbo Lumber 4S pack aircraft and its referenced pack/cell files. It sets mass to **0.01 kg**, specific heat to **100 J/(kg K)**, still-air conductance to **1000 W/K**, forced conductance to zero and auxiliary current initially to zero. Repeating each table's warm row across temperature removes temperature-dependent electrical feedback for this diagnostic; SOC dependence remains. Nested content hashes and provenance are updated.

A **0.32 kg inert ballast** at the original battery's identical position and dimensions preserves total inventory mass, CG and box inertia. An earlier attempt changed battery mass without ballast and was correctly refused by the aircraft CG check; that was a fixture failure, not a product defect. No validator is bypassed. This manufactured 10 g pack retaining the original electrical capacity is **not a claim of plausible battery hardware**; it tests the numerical domain the custom loader and launch path actually admit.

The complete aircraft loader and `FlightSession.setup` succeed. With the motor disabled, zero pack current and an admitted warm checkpoint `T=T_a+0.1 K`, a real reference tick advances `0 -> 1` without fault. Here `C_th=1 J/K`, `tau=C_th/H=0.001 s` and `h/tau=4.1666667`, while the guard's reported **pack contribution** is only `0.0419669055034`. The combined motor-plus-pack guard also passes setup; the logged contribution is not the combined ratio.

For the isolated cooling equation `theta'=−theta/tau`, classical RK4 multiplies the temperature excess by

\[
R(z)=1+z+z^2/2+z^3/6+z^4/24,\qquad z=-h/\tau.
\]

The production step yields **`R=6.01623585390947`**; exact cooling gives **`exp(z)=0.0155038535990093`**. The accepted state is therefore `288.751623585391 K`, versus the exact `288.151550385360 K`, from initial `288.25 K` and ambient `288.15 K`. Passive cooling amplifies the warm disturbance more than sixfold.

A second case does **not** inject temperature or restore a checkpoint: fresh setup starts exactly at ambient, the motor is off and auxiliary current is 0.3 A. Initial cell heat is positive, `0.00133843649645 W`, yet an accepted tick moves temperature to **`288.149993286087 K`**, below ambient by about **6.714 microkelvin**. Positive Joule/RC heating and a fixed ambient cannot produce that result from ambient under the stated continuous thermal law. The small magnitude is useful as a sign invariant, not a claim of a large observed stock thermal effect.

### Refinement, alternatives and limits

Diagnostic runs use the same warm start and the same elapsed physical time `1/240 s`:

| Diagnostic rate | Accepted steps | Remaining temperature excess |
| ---: | ---: | ---: |
| 240 Hz | 1 | 0.601623585391 K |
| 480 Hz | 2 | 0.0132992810393 K |
| 960 Hz | 4 | 0.00170864055428 K |
| 1920 Hz | 8 | 0.00155652616132 K |
| Exact continuous cooling | — | 0.00155038535990 K |

Every diagnostic tick is accepted, and the independent oracle reproduces each scalar RK4 result. These altered rates are **manufactured diagnostic runs**, not supported replacement product settings; the production contract remains 240 Hz. The shipped pack data have much slower thermal responses. No stock-pack instability is demonstrated. Existing RC time-constant admission is present; this is not a general claim that the launch guard lacks all electrical stiffness checks.

Repair choices are to **restrict custom-data admission to the supported thermal domain**, with a justified cooling-speed envelope, or **integrate the thermal subsystem with a qualified stable/accurate method**, such as appropriate substepping or a consistent exponential/implicit treatment. A single `H/C_th` bound addresses the isolated linear mode only; temperature-dependent OCV/resistance, RC heat and other coupling require their own stability and accuracy treatment. Any method must preserve accepted-state/energy accounting, resource events, rollback, checkpoint and replay semantics. Verify fresh-start and warm/cold disturbances, heat positivity, forced cooling across the supported speed envelope, extreme admitted tables, boundary events, refinement and actual native eligibility/parity.

## R5-G01 — ground effect changes local aileron authority but not the attached oracle's

### Observed internal difference

The stock Jensen Ugly Stik JSON, SHA-256 `5635e7f7b2a44bdfc7db5ad2646c74654af42944133bc39a91a0908bac887b66`, passes the production aircraft loader. At 15 m/s, density 1.225 kg/m³, level attitude, zero angular rates, zero angle of attack and CG height 0.4 m, use right aileron `+2°`, left `−2°` and zero elevator/rudder. The model's 20° throw makes this a 10% roll-control case. The public selector's local-flow weight is zero.

| Path | Free-air roll moment | Near-ground roll moment |
| --- | ---: | ---: |
| Public `Aero.loads` / attached global path | −0.56054504117601 N m | −0.56054504117601 N m |
| Local strip path | −0.56054504117601 N m | −0.63844911174621 N m |

The local increment is **−0.07790407057020 N m**, a 13.8979% change relative to its free-air magnitude. Neutral controls give zero roll and reversing the ailerons reverses each result. The probe also records 3° and 6° angle of attack and the selector in all nine cases; the independent signed/neutral oracle assertions apply to the zero-angle case. The reported difference is not caused by an unnoticed public-path switch.

### Source explanation and independent check

[The attached/global expression](https://github.com/bultodepapas/OpenRCsimulator/blob/136b32e585dc84293b81fc036a81530a04da5397/app/physics/aero.gd#L164) adds ground-effect wing lift using uniform angle of attack and strip row sums, with no differential-aileron incidence in that increment. The [_wing_flow](https://github.com/bultodepapas/OpenRCsimulator/blob/136b32e585dc84293b81fc036a81530a04da5397/app/physics/aero.gd#L293) and [local-load expressions](https://github.com/bultodepapas/OpenRCsimulator/blob/136b32e585dc84293b81fc036a81530a04da5397/app/physics/aero.gd#L500) include actual strip incidence, including aileron deflection, before reducing induced angle.

For strip stations `y_i`, induced map `E_ij`, ground factors `sigma_i`, lift slope `a_0`, aileron effectiveness `tau_a` and deflection `delta`, the symmetric attached-state difference is independently

\[
\Delta M_x=-\frac{qS}{n}a_0\tau_a\delta
\sum_i y_i(1-\sigma_i)
\left[\operatorname{sgn}(y_i)-\sum_j E_{ij}\operatorname{sgn}(y_j)\right].
\]

The probe emits the complete six-by-six induced map and station factors; the Python oracle evaluates this expression from those numbers, reproducing the observed increment within **`2.71e-15 N m`**. It also requires nonzero local/public disagreement and signed/neutral controls. This is independent point-moment algebra, not independent experimental calibration.

### Competing interpretation, repair choices and acceptance

[M5-GE-1](../ground-effect/M5-GE-1/README.md) says the attached oracle applies the same increments, but the code describes a uniform-alpha expression and retains an empirically anchored global control derivative. A separate control calibration may be intentional. Consequently this entry is a **model consistency and contract gap**, not proof that real Stik rolling moment is wrong by 13.9%. The local path is another model, not physical ground truth. [Native aero source](https://github.com/bultodepapas/OpenRCsimulator/blob/136b32e585dc84293b81fc036a81530a04da5397/research/native-kernel/src/nk_aero.hpp#L645) mirrors the global structure; native was not executed.

One repair is to apply a consistent control-sensitive ground-effect increment in the attached oracle and native counterpart, retaining the declared free-air control calibration. Another is to explicitly document and qualify different near-ground control laws and their blend if that is the intended empirical model. **Do not simply multiply a control coefficient by 1.139 based on this one diagnostic.** Validate height/span, signed roll input, angle of attack, bank and transition-weight combinations; preserve zero-control and free-air limits; check moment continuity through path blending and compare with source-matched finite-wing/physical data. A complete accepted 240 Hz session, replay and actual native parity remain untested here. Existing ground-effect tests cover trim increments and bank response; this adds the missing differential-control interaction.

## Corrections and rejected hypotheses

- **R3-F01 is narrowed.** Positive speed-based current during a zero-command rotor rundown is source-confirmed, with the earlier 1.009759 A / 8.294661 A examples unchanged. The source calls the coast *unpowered* specifically when the pack is open. Zero command on a connected pack does not by itself establish electrical disconnection or rule out active braking/auxiliary draw. The [R3 report](third-pass-physics-2026-11-21.md) now calls this an unresolved ESC/shaft-power coupling gap, conditional on intended coast policy, and retains the ID for continuity.
- **R4-O01 is deduplicated into A6 O5.** Prepared spatial-wind geometry was already investigated in the [A6 audit](../../../external%20Audits/developer-audit-remediation-2026-11-06.md). Its unguarded prototype timed about 247.53 -> 225.00 microseconds per stage, but failed a stale-NaN refusal control and omitted required invalidation cost. R4's 9,600 samples/s is an illustrative arithmetic count, not a new optimization, actual workload count, upper bound or qualified speedup. The [R4 entry](fourth-pass-physics-2026-11-21.md) now points back to that evidence.
- **Helicopter static-friction double counting was rejected.** The relevant correction already occurs before geared coupling. Missing actuator dynamics, the collective HUD issue and rotorcraft atmosphere restrictions remain owned by prior work; this report adds the specific post-limit trim counterexample only.
- **Thermal fixture rejection was respected.** The first mass-only change violated CG and correctly failed. Balanced inert ballast repaired the manufactured data instead of bypassing admission. No RC-guard omission or stock-pack instability is asserted.
- **Prior fixture limits are retained.** The helper's early helicopter run used four unused scenery stubs; the published clean reconstruction supersedes that evidence with real dependencies. The early fixed-wing run used a source-identical subset; the published run uses the complete shared fixture. Neither is a complete application or physical-flight qualification.

## Follow-up decisions

| Work item | Concrete next action | Gate before promotion |
| --- | --- | --- |
| R5-F01 | Put trim and linkage limits under one control-allocation contract | Feasible angle/servo roundtrip, trim/control saturation matrix, accepted trajectory and native/replay qualification |
| R5-F02 | Decide and version the chord evidence policy; propagate geometry and time uncertainty | Analytic counterexample becomes unresolved or correctly located; ordered events, collision-aware plant cases and replay |
| R5-F03 | Declare a supported thermal domain or a qualified coupled integration method | Complete custom admission, passive cooling/positive heat invariants, forced-cooling bounds and refined accepted flight |
| R5-G01 | Resolve whether the two paths should share control-sensitive ground effect | Explicit owner decision, cross-path/blend properties and independent physical calibration |
| A6 O5 / R4-O01 | Revisit prepared immutable geometry with correct invalidation | Preserve invalid-model refusal; measure complete workloads and target-host cost before speedup claims |

The branch retains every earlier finding and its evidence level. R5 contributes **three bounded findings and one consistency/calibration gap**, plus corrections that reduce overclaiming and duplicate counts. It does not declare the physics solved or the outstanding production/native/physical gates complete.
