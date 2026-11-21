# A36 R6 — propeller power, flap/wake consistency and tailless admission

**Date:** 2026-11-21. **Reviewed source:** `f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac`. This continues the [existing audit branch](https://github.com/bultodepapas/OpenRCsimulator/tree/audit/physics-math-aero-2026-11-21) and its [research index](README.md). R6 adds research, reproducible evidence and repair options; it changes no production physics, native implementation, original PDF/ZIP or main-branch source.

Three parallel reviews traced propulsion, wind/frames and prior evidence; the integrating review examined flap/wake composition and independently checked the arithmetic. Candidates were checked against capability admission and earlier audits before promotion. This round establishes two bounded consistency gaps and upgrades the existing **R4-F01** from a source-only concern to complete-loader and actual setup-path evidence. It does not count the upgrade as a new defect.

## Findings and evidence boundaries

| ID | Result | Scope and priority |
| --- | --- | --- |
| **R4-F01, evidence upgrade** | A fully admitted synthetic tailless/tractor/vertical-wake configuration reaches an unconditional horizontal-tail lookup; the component and normal setup emit engine errors | **P1** custom-configuration runtime failure. The matched no-wake control accepts a reference tick. No stock X8 failure, accepted wake-enabled tick or native/swirl execution is claimed |
| **R6-G01** | An admitted custom electric propeller table supplies **54.237530 W** of forward thrust work while absorbing **41.715561 W** at its shaft at a clean axial operating point | **P2** custom-data consistency/hardening gap, extending a known NITRO power-consistency class. A second fixture reaches the same class of discrepancy at ordinary trim; stock control passes the matched point |
| **R6-G02** | All three stock flap-equipped models give different drag/pitch loads for static `NAN` wake and the explicitly settled flapped wake at the same state | **P2** internal static/dynamic contract gap. Stock data, component/shared `Dynamics` calls and a conditional algebra oracle; no measured flight-error or ordinary clean-start failure claim |

The [single portable reproducer](probes/reproduce_sixth_pass.py) reconstructs **442 real dependencies** from the reviewed Git objects, applies the recorded checkout-byte rules and generates five explicitly synthetic input files beside unchanged stock inputs. There are no production stubs. The [retained evidence](sixth-pass-evidence.json) contains the exact probe hashes, input identities, checked reports, full small logs and independent oracle output. The [CI snapshot](sixth-pass-ci-snapshot.json) has a separate scope and must not be confused with the focused research checks.

## R4-F01 upgrade — admitted tailless wake fails during setup

### Admission is now demonstrated

The [R4 report](fourth-pass-physics-2026-11-21.md#r4-f01--tailless-plus-vertical-fin-propwash-a-missing-dictionary-key-at-the-powered-stage) traced an intentionally absent horizontal surface into unsafe wake lookups, but did not execute a complete admitted aircraft. R6 closes that particular evidence gap.

The [fixture generator](probes/sixth_pass_fixtures.py) starts from the stock X8 numerical airframe and a Stik-type legacy glow tractor. It explicitly labels the retained motor/battery/ESC inventory as a synthetic fixed-mass surrogate, selects `single_tractor`/`prescribed_fuel`, and declares one **0.020 m² vertical-fin wake piece**. It is a numerical domain witness, not a proposed real X8 installation. Both shared module classification and `AircraftData.load_file` accept it without errors or warnings; the derived surface dictionary contains `tailless` and `vertical`, and deliberately omits `horizontal`.

The matched no-wake control differs only in its research ID and removal of `propulsion.propeller.slipstream`. It also passes admission, completes normal reference trim, and advances **tick 0 → 1** with no fault. An electric-propeller-plus-wake control is correctly refused as an unsupported field; the result does not depend on ignoring that refusal.

### Actual failure chain

The shared load route is:

1. The v2 loader and `_prepare_aircraft_before_trim` admit the custom configuration.
2. `FlightSession.setup` invokes trim, which calls `Dynamics` and the nonempty slipstream installation.
3. [Slipstream.stage_loads](https://github.com/bultodepapas/OpenRCsimulator/blob/f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac/app/physics/slipstream.gd#L110-L121) reads `surfaces.horizontal.has("free_slope")` before evaluating the vertical piece.
4. Godot reports a missing `horizontal` key at line 117. The returned empty array then causes downstream load/trim errors; setup returns nonflyable at tick 0 with `trimmed starting condition is invalid: no valid trim`.

The isolated component witness uses air-relative velocity `[12, 0.5, 0] m/s`, **5,000 rpm**, thrust **4.416120899 N**, wake increment **3.224218650 m/s**, and immersed vertical area **0.020 m²**. The unchanged component emits one script error and returns an empty array. The setup invocation emits that error and a bounded cascade, **10 engine diagnostics in total**. In both cases the child Godot process exits 0; the checked runner correctly returns wrapper exit 1 with reason `engine_error`. A zero process exit is therefore not evidence of success.

At zero RPM the same admitted model returns six zero wake loads without an error. A separate in-memory diagnostic adds an empty horizontal dictionary and the same powered component returns a finite, nonzero vertical-wake wrench. That diagnostic is **not an admitted model, a proposed production fix or a calibrated result**; it only helps isolate the missing-key cause.

The [swirl source](https://github.com/bultodepapas/OpenRCsimulator/blob/f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac/app/physics/swirl_loads.gd#L30-L44) contains a similar unguarded lookup, but this fixture sets swirl to zero. The [native wake presence guard](https://github.com/bultodepapas/OpenRCsimulator/blob/f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac/research/native-kernel/src/nk_wake.hpp#L502-L512) remains source evidence only. R6 does not claim to have executed either branch.

### Repair choices and acceptance

If vertical-only propwash on a tailless tractor is intended to be supported, guard horizontal-tail presence before resolving its downwash and keep vertical-piece forces independent of a nonexistent surface. Audit the sibling swirl route at the same time. If the combination is deliberately unsupported, reject it at the shared capability boundary with an actionable error before trim. Adding a dummy horizontal surface to aircraft data would obscure the actual configuration and is not the proposed repair.

Acceptance should cover full admission, nonzero-RPM vertical-only loads, zero-RPM behavior, no-wake parity, ordinary setup, checked zero-diagnostic execution and actual reference/native selection where applicable. Preserve failure atomicity, source identities and checkpoint/replay policy. The existing **R4-F02 duplicate-piece overlap question remains source/arithmetic evidence**; this experiment does not establish its complete-aircraft admission or close it.

## R6-G01 — independent Ct/Cp curves can admit impossible propeller power

### What is new in this evidence

[NITRO-01](../glow-engines/NITRO-01/README.md) already reported a synthetic map violating `J*Ct <= Cp`, and [NITRO-02](../glow-engines/NITRO-02/README.md#momentum-bound-correction) added a stronger ideal-disk check for a different glow-propeller law. R6 extends that known class to complete custom **electric aircraft data, the shared tabulated law and reference-session acceptance**. It does not claim that the inequality itself is a new discovery.

The [aircraft contract](../../AIRCRAFT_CONTRACT.md#scope-and-authority) explicitly distinguishes a valid file from a realistic aircraft. Consequently this finding is a concrete hardening opportunity: the authoring/launch policy currently allows a physically inconsistent estimated map in the tested powered domain. It is not evidence that the loader promised experimental calibration or that shipped electric propeller data is generally invalid.

### Source connection

[AircraftData](https://github.com/bultodepapas/OpenRCsimulator/blob/f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac/app/physics/aircraft_data.gd#L1332-L1386) validates the two ordered coefficient tables independently, enforces coefficient ranges and positive static Ct/Cp, and forwards both to the runtime. The inspected electric path applies no joint power-consistency condition over advance ratio. [Propulsion.thrust_torque](https://github.com/bultodepapas/OpenRCsimulator/blob/f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac/app/physics/propulsion.gd#L652-L665) evaluates thrust and torque from those independently interpolated curves at the same RPM, density and axial inflow. [The coupled flight stage](https://github.com/bultodepapas/OpenRCsimulator/blob/f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac/app/sim/flight_session.gd#L5011-L5048) uses the matching rotor torque and body loads.

For the usual coefficient convention,

\[
n=\mathrm{RPM}/60,\qquad J=\frac{V}{nD},\qquad
T=\rho n^2D^4C_T,\qquad P_{\mathrm{shaft}}=Q\Omega=\rho n^3D^5C_P.
\]

For a steady isolated propulsor in uniform axial inflow, with positive thrust, absorbed shaft power and no independent wake-energy input, useful thrust work is `TV`, so a necessary condition is

\[
\eta=\frac{TV}{Q\Omega}=\frac{JC_T}{C_P}\leq 1.
\]

The definitions and efficiency relation agree with [MIT's propeller-performance derivation](https://web.mit.edu/16.unified/www/SPRING/propulsion/notes/node86.html) and the [UIUC coefficient reference](https://m-selig.ae.illinois.edu/props/propDB.html). For a uniform axial ideal disk, the stronger minimum is `Pideal = T(V + sqrt(V² + 2T/(rho*A)))/2`, with `A = pi*D²/4`; [NASA's momentum derivation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/propeller-thrust/) states the assumptions. Passing either necessary check would still not validate a real propeller.

### Minimal admitted witness and stock control

The first fixture changes one stock Turbo Lumber Cp value at **J = 0.655**, from **0.038 to 0.020**, and relabels that quantity's provenance as synthetic/estimated. Ct, motor, supply, geometry and every other quantity remain unchanged. The point is inside the authored table, with positive coefficients and positive RPM; it does not exercise stopped-propeller behavior or extrapolation.

| Quantity | Synthetic single-knot witness | Unchanged stock at the same point |
| --- | ---: | ---: |
| Density | 1.225 kg/m³ | Same |
| Propeller diameter | 0.2794 m | Same |
| RPM | 6,000 | Same |
| Shaft-aligned airspeed | 18.3007 m/s | Same |
| Thrust | 2.963686095 N | Same |
| Shaft power `QΩ` | **41.715561462 W** | **79.259566778 W** |
| Useful thrust work `TV` | **54.237530124 W** | Same |
| Ideal axial-disk minimum | **57.263800128 W** | Same |
| `TV / QΩ` | **1.300175** | Approximately 0.6843 |

The complete custom file passes v2 admission and reference-session setup. The minimized operating point is constructed explicitly, accepted by restoration into a fresh session, and advances one **240 Hz reference tick**. The stock comparison is a pointwise control, not certification of its entire map.

A second fixture changes **24 nonstatic Cp entries** by the recorded generator formula while retaining the stock Ct curve. It reaches the discrepancy through **ordinary setup and its own normal trim**, without checkpoint injection. At the initial stage, RPM is **4,398.639388918**, axial speed **13.083226999 m/s**, thrust **1.727164587 N**, and shaft power **18.075888915 W**, while thrust work is **22.596886356 W**. Its first reference tick is accepted. Body rates are zero; the airflow also has about **0.6256 m/s transverse speed**, so the clean shaft-aligned fixture above is the primary ideal-disk witness.

These numbers diagnose the reported initial component/stage points. Tick acceptance is separately observed; no integrated excess-energy total or long trajectory has been measured. Rotor acceleration does not create an additional uncounted input to this comparison: `Qprop*Omega` already measures the aerodynamic shaft-port work, whether the motor or stored rotor energy funds it. The quasi-steady table has no independent transient wake-energy reservoir in this witness. Neither native behavior nor real-aircraft efficiency is established.

### Why checking only table rows is insufficient

Separate linear interpolation introduces an additional implementation requirement for a repair. The [independent oracle](probes/sixth_pass_oracles.py) constructs these two endpoints:

| J | Ct | Cp | Ideal-disk minimum Cp |
| ---: | ---: | ---: | ---: |
| 0.2 | 0.0050 | 0.00108 | 0.001074088383 |
| 0.8 | 0.0035 | 0.00282 | 0.002809714537 |

Both endpoints pass even the stronger bound. Halfway between them, at `J = 0.5`, linear interpolation gives `Ct = 0.00425` and `Cp = 0.00195`, whereas `J*Ct = 0.002125`: the interior violates the weaker useful-work bound. This is validator-design arithmetic, not another complete-aircraft finding.

On each interval, write `Ct = aJ+b` and `Cp = cJ+d`. Then `Cp−J*Ct = −aJ²+(c−b)J+d`; checking endpoints and an interior stationary point, when present, certifies this necessary inequality for that interval. Merge differing Ct/Cp knot sets before applying the calculation. A stronger nonlinear ideal-disk constraint needs its own justified interval or runtime qualification.

### Repair choices and acceptance

Choose an explicit authoring/launch policy: report a clear consistency diagnostic, or refuse supported forward powered points that violate necessary bounds beyond a documented numerical/measurement tolerance. Reuse the existing owner for joint Ct/Cp validation; keep thrust and torque coupled through runtime and derived propulsion cards. Avoid silently clipping one output or inventing extra shaft/battery power.

Required cases include static flow, exact and near-boundary equality, failing knots, passing knots with a failing interior, unequal knot sets, valid catalog controls, finite/overflow behavior, and a deliberate policy for reverse flow, negative thrust, negative Cp and extrapolation. If the runtime law changes, qualify source/law identities, reset/rollback, checkpoint/replay and actual native parity. Measured thrust and torque for matching diameter, RPM, inflow and Reynolds regime remain necessary for physical calibration.

## R6-G02 — static flap loads differ from the settled dynamic wake

### Reproduced stock-data difference

[Dynamics](https://github.com/bultodepapas/OpenRCsimulator/blob/f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac/app/physics/dynamics.gd#L28-L38) describes `NAN` downwash as the quasi-static route. The existing [downwash tests](https://github.com/bultodepapas/OpenRCsimulator/blob/f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac/app/tests/test_downwash_lag.gd#L159-L178) check instantaneous-source equality on separate clean local/global paths. The [spatial-wind flap test](https://github.com/bultodepapas/OpenRCsimulator/blob/f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac/app/tests/test_spatial_wind_aerodynamics.gd#L575-L595) explicitly permits different public baselines while checking the spatial differential. Thus the difference is test-noted; its static/dynamic contract and calibration consequence remain unqualified.

R6 compares the public `Aero.loads` twice at the same stock model, state, controls, density and environment: once with `NAN`, and once with `Aero.wing_wake_velocity` evaluated from that exact flapped state. With airspeed **20 m/s**, density **1.225 kg/m³**, **10° flap**, zero body angle of attack/sideslip/rates, neutral primary controls and no ground effect:

| Stock model | Settled minus static `Fx` | Settled minus static `My` |
| --- | ---: | ---: |
| F4U Corsair 250 | **+0.040968958424 N** | **−0.006499375728 N·m** |
| P-51D Mustang 120 | **+0.153920850289 N** | **−0.024361977487 N·m** |
| Vantage Jet / Avanti source model | **+0.039783204755 N** | **−0.002377840273 N·m** |

The positive `Fx` difference means less drag in the settled finite-wake call in these particular cases. Lift agrees to floating-point precision. The difference propagates unchanged through shared `Dynamics.loads` at zero RPM. Complete stock-data admission succeeds in all three cases.

The probe covers **24 cases and 225 assertions**, including 10/20/30 m/s scaling, zero flap, a small flap approaching zero, a fully local-flow case, a nonzero-alpha case and ground effect. Zero flap and fully local selection recover equality. The independent Python calculation checks **15 attached/free-air cases**, including selector and linear-tail assumptions, and matches the force/moment difference to approximately **3.5e−15** in the recorded scalar component comparisons. That number measures agreement between the specified algebra and runtime, not physical accuracy.

### Where the difference enters

For active flaps, [Aero.loads](https://github.com/bultodepapas/OpenRCsimulator/blob/f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac/app/physics/aero.gd#L968-L987) combines a clean global baseline, a subtracted clean local baseline and flapped local loads. With `NAN`, clean and flapped local evaluations resolve their own wing-wake sources. With an explicit settled flapped source, all three evaluations receive that one source.

The [global lag correction](https://github.com/bultodepapas/OpenRCsimulator/blob/f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac/app/physics/aero.gd#L201-L214) changes lift and pitch. The [local tail law](https://github.com/bultodepapas/OpenRCsimulator/blob/f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac/app/physics/aero.gd#L752-L769) also changes the tail drag terms. In the zero-alpha attached examples the lift corrections cancel between the two routes, while the tail drag difference does not.

Let `Wc` and `Wf` be the reported clean and flapped wing-wake inputs. With tail incidence `i`, free slope `a`, downwash gain `kε` and speed `V`, the conditional oracle uses

\[
\alpha_h(W)=i-\operatorname{atan2}(k_\epsilon W,V),\quad
C_{Lh}=a\alpha_h,\quad
C_{Dh}=C_{D0h}+k_hC_{Lh}^{2}+C_{D90h}\sin^2\alpha_h.
\]

For the asserted linear-tail and zero-blend domain,

\[
\Delta F_x=\tfrac12\rho V^2S_h\,[C_{Dh}(W_f)-C_{Dh}(W_c)],
\qquad \Delta M_y=r_{h,z}\Delta F_x.
\]

The oracle derives drag and the force-arm identity independently of the production tail helper. Its wing wakes are **inputs**, so it does not independently validate wing circulation or real flap aerodynamics.

### Practical consequence and repair choices

Static flap-on research is a real consumer: [the P51-11 flap probe](https://github.com/bultodepapas/OpenRCsimulator/blob/f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac/research/p51/p51-11/flap_probe.gd#L31-L43) supplies flap deflection to `Dynamics.evaluate` without a finite wake. A static tuning or equilibrium result from that route need not have exactly the same loads when transferred to the explicitly settled dynamic representation. Historical calibration outputs were not rerun here and must not be reassigned these current numbers.

Ordinary `FlightSession` airborne/runway reset starts with zero flap; this experiment does **not** demonstrate a stock flap-on startup failure. Nor does a small internal drag difference establish a measured handling error. The effect is distinct from the already documented P-51 flap pitch-sign issue and from R5-G01's ground-effect/aileron difference.

One repair approach is to make tail/wake ownership explicit in the flap increment: evaluate a clean equilibrium baseline once, then apply one complete physical tail change, including drag and its moment arm, for the actual wake. Another is to align the global wake correction with the same complete tail-force differential used locally. Either choice must prevent double subtraction, preserve the clean calibration and make `NAN` versus explicitly settled wake equivalent under the chosen contract. Merely choosing one existing route as correct would not establish its physical accuracy. A deliberate approximation is also possible, but it needs documented semantics and a quantified calibration/trim consequence.

Acceptance should cover zero and finite flap, settled and transient wakes, mixed elevator/aileron inputs, signed flow, speed scaling, ground effect, the global/local blend seam and spatial continuation. Check whole forces and moments, including drag arms, rather than only CL or a matched spatial differential. Any changed law needs replay/identity qualification and reference/native agreement before promotion.

## Negative controls and remaining opportunities

- **Wind frames and sampling:** the unchanged spatial-wind contract, spatial-field, tailless-spatial and airship-dynamics entrypoints pass **176 + 155 + 121 + 50 = 502 checks** in the isolated fixture. The inspected rigid-point airflow and rotating Galilean boost controls support their stated contracts; they do not certify every aircraft, full flight or arbitrary atmosphere.
- **Capability combinations matter:** tailless ground effect is explicitly refused, so the suspected swept-wing/ground-height mismatch is not an admitted failure. Helicopter spatial/OU/vertical-atmosphere modes and airship spatial atmosphere are also outside the admitted paths inspected. The ground-vehicle wind omission is already owned by the wind plan.
- **Flap/polar interaction:** the loader rejects `stall_shift_fraction` combined with a tabulated wing polar. The apparent ignored-option bug is therefore excluded, not added as a finding. The plain-flap moment ratio and integrated strip-area coverage did not yield a new arithmetic defect in this review.
- **Ground effect and propwash:** the existing ground-effect report explicitly leaves the slipstream tail increment unchanged with height. That is a declared modeling limit, not another hidden bug established here.
- **Energy and mass ownership:** rotor shaft-port work, co-moving fuel efflux and fixed-datum/live-CG transforms must remain separate budgets. No extra `−dW/dt` force or generic missing fuel-mass claim is justified by this review. The finite-fuel Vantage adapter already updates mass/CG/inertia; Nitro truck and prescribed-source gaps retain their own earlier scope.

Further useful qualification is the combined case of finite-fuel/live-CG dynamics, nontrivial attitude/rates and spatial point-flow propulsion with one independently closed force/moment/shaft ledger. Mixed flap/aileron/ground-effect inputs through the production spatial continuation also deserve a matched comparison. These are verification opportunities, not demonstrated new defects or performance measurements. R6 claims no CPU/FPS gain.

## Reproduction and acceptance record

Run from a checkout containing the reviewed objects, using a new output directory:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 docs/research/project-audit-2026-11-21/probes/reproduce_sixth_pass.py \
  --repo-root /absolute/path/to/OpenRCsimulator \
  --godot /absolute/path/to/Godot_v4.8-beta2_linux.x86_64 \
  --out /absolute/path/to/new-r6-output
```

The engine is **4.8.beta2.official.cafc17a19**, Linux x86-64, SHA-256 `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`. The reproducer verifies the historical base-manifest hash and every Git blob/fixture hash, isolates user settings, preserves host-admission variables, and invokes the repository checked runner. Both propulsion sessions explicitly choose and report `gdscript_reference`. The tailless session probes also record the selected backend and input identity.

The final run includes **11 clean checked invocations** (import plus ten scripts), **two exact expected checked failures**, and the independent scalar oracle program. The expected failures are retained as failures in their reports; the reproduction succeeds only if their messages, counts, child/wrapper exits and required markers match exactly. It also verifies the accepted no-wake tick, refused wake setup and unchanged dependency bytes. Independent review checked the final claims, all 11 retained probe/helper hashes, base-manifest and extra-dependency identities, checked-runner identity and embedded engine-log hashes, with no blocking finding. This is an isolated real-dependency fixture, not a complete application import, rendered test, native run or flight calibration.

### Separate CI qualification

The previously published R5 head's [CI run 44915227344](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44915227344) has completed with **failure**, while [MetalFX source controls 44915227353](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44915227353) passed. The [snapshot](sixth-pass-ci-snapshot.json) records the returned job summaries and two inspected logs. The integration log reports stale Cmq/CLq/Cnr provenance and bare trigonometric calls outside `math3d`; the sampled unit shard refuses companion behavior-source identities. Other failed shards were not fully triaged in R6. These observations update the existing release/CI qualification queue, not the count of physical defects.

Several native/source and visual CI jobs passed at that earlier head, but they do not execute or qualify these new research scenarios. Full CI, native/rendered behavior where affected, target-hardware performance and physical/pilot acceptance remain separate gates. The draft PR must retain those distinctions when a later research commit starts new CI.
