# Seventh pass: drone control domains, numerical admission and rotor work

**Reviewed source:** `5a93c105be0736d23f52ac9b46812b3a5e358233`. **Date:** 21 November 2026. This continues the existing [A36 research branch](README.md), the [drone implementation plan](../../plans/drone-racing.md), and their established owners. R7 changes research, evidence and diagnostic probes; it does not implement a new controller or aerodynamic law.

Three parallel reviews covered the electrical plant, controls/input, and an independent challenge of prior ownership, physical interpretation and reachability. The integrating review investigated numerical admission, reconstructed a separate source-pinned fixture, and reran the selected evidence. Earlier alarming-looking candidates were narrowed when their assumptions did not survive those checks.

## Results and evidence boundaries

| Item | Result | Status and scope |
| --- | --- | --- |
| **R7-F01** | A constructed BETAFLIGHT profile with expo 200 passes import and session admission; positive half stick commands **−75°/s**, and the simulated body responds in that direction | **P2 conditional input-domain defect.** Programmatic importer → real input adapter → stock-data session; synthetic gamepad/keys. No currently completed player import UI or conforming firmware dump claim |
| **R7-F02** | A custom motor resistance of **0.001 Ω** passes the strict file loader and normal pad setup, but the zero-throttle arming tick fails under the production integration policy | **P2 conditional numerical-admission defect.** The failure rolls back correctly. Identical initial frame/control sample succeeds with diagnostic 4/8/16-piece plant refinement. Stock motor succeeds |
| **R7-G01** | Independent 55° Euler roll/pitch bounds permit a **70.792520° desired thrust-axis tilt** at full diagonal input; the stock reference session reaches **72.422756°** transiently | **Contract/design question, not a new confirmed cone-limit violation.** Clarify whether `max_tilt` means each Euler component or the resultant tilt |
| **R2-L02, evidence upgrade** | A stock pad-start throttle tape reaches positive modeled rotor-to-vehicle aerodynamic power: **+16.115813 W at tick 98** and **+89.386116 W after the throttle reduction at tick 746** | Existing static/inflow limitation, now quantified in accepted reference flight. Full motor/body/rotor work accounting closes; this is not observed spontaneous whole-vehicle energy growth |
| **Existing FPV/03 relative-rate approximation, evidence upgrade** | A constructed, accepted near-stop frame yields thrust with an instantaneously stationary rotor; reversing its rotation relative to still air gives **+16.125875 μW** rotational aerodynamic work | Existing declared approximation, not another finding ID. No normal pad-flight reachability; the full vehicle still loses kinetic energy |
| **R2-F01 reachability correction** | The current drone session builds reference-atmosphere weather and exposes only steady wind speed/direction | The previous standard-column/density arithmetic remains a component/environment counterfactual; legal start altitude alone does not expose it in the player drone route |

The [evidence record](seventh-pass-evidence.json), [dependency supplement](seventh-pass-extra-sources.json), [single reconstruction command](probes/reproduce_seventh_pass.py), and [independent scalar/vector oracles](probes/seventh_pass_oracles.py) retain the distinct scopes. A passing observation probe means the reported behavior was reproduced, including an expected rejected tick; it does not mean that behavior is repaired.

## R7-F01 — Oversized Betaflight expo reverses partial-stick commands

### Source and mathematical cause

[Rates admission](https://github.com/bultodepapas/OpenRCsimulator/blob/5a93c105be0736d23f52ac9b46812b3a5e358233/app/physics/multirotor/rates.gd#L39-L48) bounds ACTUAL expo to 0–100 but deliberately leaves BETAFLIGHT expo without an upper bound. The [complete CLI importer](https://github.com/bultodepapas/OpenRCsimulator/blob/5a93c105be0736d23f52ac9b46812b3a5e358233/app/physics/multirotor/rates.gd#L384-L396) uses that validator and returns the profile. The [session](https://github.com/bultodepapas/OpenRCsimulator/blob/5a93c105be0736d23f52ac9b46812b3a5e358233/app/sim/multirotor/session.gd#L220-L225) accepts its `rates` option through the same validation.

For the tested `rc_rate=100`, `srate=0`, and a nonbinding cap, the [implemented rate law](https://github.com/bultodepapas/OpenRCsimulator/blob/5a93c105be0736d23f52ac9b46812b3a5e358233/app/physics/multirotor/rates.gd#L182-L192) reduces to

\[
\omega_{\rm cmd}(x)=200x\left[(1-e)+e|x|^3\right]\quad\text{degrees/s},\qquad e=\frac{\mathrm{expo}}{100}.
\]

At expo 200, `e=2`. For `x=+0.5`, the bracket is −0.75, giving **−75°/s**. At `x=−0.5` it gives +75°/s; at full positive stick it gives +200°/s. Thus the error can hide behind a correct full-stick endpoint. More generally, any `e>1` reverses direction for

\[
0<|x|<\left(1-\frac{1}{e}\right)^{1/3}.
\]

For `e=2`, this interval extends to approximately 0.793701 of full stick. A symmetric output magnitude cap preserves the wrong sign and cannot repair the mapping.

Betaflight's official [4.5 CLI reference](https://betaflight.com/docs/wiki/guides/archive/Betaflight-4.5-CLI-commands) gives roll, pitch and yaw expo a range of **0–100**. The external document is for the 4.5 family; an exact 4.5.2 source-tag fetch was unavailable in this review. No claim of independently inspecting that firmware tag is made. The numerical sign failure is independently demonstrated in OpenRC's own accepted law.

### Actual reproduction

[seventh_pass_rates.gd](probes/seventh_pass_rates.gd) constructs an explicitly synthetic complete 4.5.2 CLI block, imports it, and passes the returned profile to the real session. It uses unchanged stock quad data and the production input adapter, with synthetic gamepad axis observations, synthetic verification, and keyboard arm/mode events. It selects the supported full-throttle option, starts on flat fixture ground, switches to Acro, climbs for 240 ticks, and holds the measured half-stick input for another 240 ticks. All four sessions accept **482 ticks**, stay armed, and report no crash/fault.

| Roll expo | Actual pre-expo pilot input | Controller setpoint | Body roll rate after 1 s of that input |
| ---: | ---: | ---: | ---: |
| 0 | +0.5 | +100°/s | +65.850°/s |
| 100 | +0.5 | +12.5°/s | +7.657°/s |
| 200 | +0.5 | **−75°/s** | **−48.206°/s** |
| 200 | −0.5 | **+75°/s** | **+48.206°/s** |

These body rates are transient observations, not settled tracking values. Direct rate evaluation and sampled controller output agree; the adapter supplies pre-expo values, and the controller applies the mapping once. ACTUAL expo 200 and an incomplete CLI block are refused as negative controls. The malformed BETAFLIGHT profile's full-stick endpoint remains positive.

**Reachability limit:** the profile text is impossible as a conforming dump under the cited range. It is supplied through the importer/programmatic session path; the documented rate-import/settings UI is unfinished. This is not a reversal in the stock ACTUAL profile, a physical-gamepad demonstration, or proof of firmware flight-feel equivalence. Acro uses these mapped roll/pitch rates; Angle replaces roll/pitch with attitude-loop targets, while yaw remains rate-controlled.

### Repair choices and acceptance

Prefer one shared explicit expo domain, enforced both for stored/programmatic profiles and imported CLI text. Reject unsupported values with axis-specific errors; preserve the reason instead of silently clipping. Pin the intended compatibility range to the supported firmware/version contract. If deliberately nonstandard curves remain useful for research, give them a distinct identity and define their allowed monotonicity/direction behavior.

Acceptance should cover every axis, expo 0/100 and refused 101/200, positive and negative small/half/full inputs, parser error reporting, session refusal without disturbing the current flight, and profile/replay identity. Keep normal valid curves unchanged. The repair also needs a decision for existing saved profiles whose previously accepted range would become invalid.

## R7-F02 — Custom motor dynamics are admitted beyond the production step policy

### Accepted model, rejected arming tick

The [strict loader](https://github.com/bultodepapas/OpenRCsimulator/blob/5a93c105be0736d23f52ac9b46812b3a5e358233/app/physics/multirotor_data.gd#L465-L483) admits positive electrical resistance without linking it to shaft inertia, motor KV or the integration interval. The common physical invariants and loaded-hover solve check important physical conditions, but not this dynamic resolution. The [parked stiffness estimate](https://github.com/bultodepapas/OpenRCsimulator/blob/5a93c105be0736d23f52ac9b46812b3a5e358233/app/physics/multirotor/controlled_plant.gd#L237-L280) is for contact modes; the [production substep policy](https://github.com/bultodepapas/OpenRCsimulator/blob/5a93c105be0736d23f52ac9b46812b3a5e358233/app/physics/multirotor/controlled_plant.gd#L723-L744) does not add an electrical response bound.

The current activity passes its fixed catalog path; this custom file is admitted through the session’s `data_path` API. “Normal pad setup” describes the start/tape, not an observed player custom-file selection UI.

The new synthetic file differs from the stock document only in `powertrain.resistance.value` (**0.13292831966559807 Ω → 0.001 Ω**) and its honest `kind`/`source` annotation. All other numerical data remain exact. It retains baseline fit/derived annotations; those are not newly calibrated motor evidence. The loader independently admits the supplied physical model and recomputes the hover quantities it consumes. No real 5-inch motor with this resistance is asserted.

[seventh_pass_motor_admission.gd](probes/seventh_pass_motor_admission.gd) loads the complete new file, prepares a normal flat-pad session at SOC 0.5, resumes, and accepts one ready OFF tick. A zero-throttle ON input then gives:

| Configuration | Arming tick | State afterward |
| --- | --- | --- |
| Stock resistance, production policy | Accepted | Tick 2, armed, no fault |
| Custom resistance, production policy: two parked pieces | **Rejected** | Tick 1, disarmed; last valid frame and tape preserved |
| Custom resistance, diagnostic 4/8/16 plant pieces | Accepted | Tick 2, armed, two total controller samples, no fault |

The production refusal is `multirotor kernel: step rejected: RK joint stage evaluation is nonfinite or malformed`. That is an application-level rejected tick inside a clean diagnostic invocation, not a Godot engine error. The kernel's rollback is a **working safeguard**. The admission gap is that a model accepted for this ordinary start/arming path immediately reaches an unusable numerical trajectory.

Only the arming interval is refined. Every comparison starts from the **same serialized post-OFF frame** and produces the **same held motor commands**. The 240 Hz controller is never resampled inside a refined interval. For the custom model, the maximum shaft-endpoint difference falls from **6.281808 rad/s** between 4 and 8 pieces to **0.014513 rad/s** between 8 and 16. The stock comparison falls from approximately **7.09×10⁻⁷** to **4.35×10⁻⁸ rad/s**. This localizes the failure to integration resolution and its interactions; 16 pieces are diagnostic instrumentation, not an implemented or comprehensively qualified fix.

### Independent local stiffness check

A separate synthetic airborne stage perturbs an equal-duty **same-spin pair** oppositely, so its first-order common-bus voltage and shared axial reaction cancel. At positive shaft speed, outside the friction regularization, that pair's differential rate has

\[
\lambda=-\frac{1/(R_mK_V^2)+2k_Q\Omega}{J}.
\]

The final probe uses duty 0.3, SOC 0.5 and `Ω=929.268985 rad/s`, and explicitly verifies positive current in all four motors. It compares the actual derivative difference with the independent formula. The results are approximately `hλ=−0.106176` for stock and **`hλ=−11.760231`** for the custom motor at `h=1/240 s`.

The scalar RK4 amplification polynomial is

\[
R(z)=1+z+z^2/2+z^3/6+z^4/24.
\]

At the custom value it amplifies the local decaying mode instead of approximating `exp(z)`. This is a **separate local diagnostic**, not a derivation of the exact pad-start failure: pad arming starts near zero speed, includes nonlinear friction/contact, and uses two pieces. Common-mode electrical response is also changed by the shared battery; the isolated-motor time constant cannot be applied indiscriminately to every mode. The earlier drone research already required configuration-specific step qualification; the new result is a concrete accepted file and reproducible ordinary arming failure.

### Repair choices and acceptance

One option is to restrict admission to a justified, validated motor/bus/contact response envelope for the supported integration policy. Another is to add a qualified stiff-subsystem treatment or plant refinement policy while preserving the single sampled controller event, shared-bus solution, signed braking, charge bounds and transaction ownership. A simple `R_m J K_V²` rule is only a starting estimate: differential/common modes, torque slope, friction, body coupling and electrical active-set changes need coverage.

Do not merely increase the substep ceiling or accept invalid intermediate stages. The current kernel caps this interface at 16 pieces; larger requested counts are correctly refused. Acceptance must include zero-speed arming, idle, throttle changes, low/full SOC, braking/reversal, contact transitions, simultaneous resource events and rollback. Compare refinement with identical control sampling and retain stock behavior. Requalify law/solver and replay identity if integration semantics change. No stock instability, real-motor failure or native result is claimed here.

## R7-G01 — Define what the Angle maximum limits

The stock setting is named `controller.angle.max_tilt` and equals 55°. The [outer loop](https://github.com/bultodepapas/OpenRCsimulator/blob/5a93c105be0736d23f52ac9b46812b3a5e358233/app/physics/multirotor/flight_controller.gd#L447-L463) independently assigns Euler roll and pitch to stick fraction times that number. For roll `φ` and pitch `θ`, the desired body-up inclination `γ` obeys

\[
\cos\gamma=\cos\phi\cos\theta.
\]

Thus `(1,0)` requests 55° total tilt; `(√0.5,√0.5)` requests **52.712266°**; `(1,1)` requests **70.792520°**. Neither quaternion normalization nor the separate rate clamps turns these independent Euler bounds into a cone.

[seventh_pass_angle.gd](probes/seventh_pass_angle.gd) uses stock data, normal pad setup and the real keyboard adapter with synthetic callbacks. It selects the supported full-throttle option, arms at low throttle, raises throttle for one second, then holds the axes for 1.5 s. All three cases accept **602 ticks** in Angle mode without crash/fault. The final accepted quaternions give **56.609403°**, **54.371050°** and **72.422756°**, respectively. The fractional diagonal is a manufactured mathematical control; simultaneous full axes model two held keys. No physical keyboard or rendered activity was exercised.

The distinction is about the **desired target**, not a guarantee that instantaneous actual attitude never exceeds a number. Even the single-axis case has transient tracking overshoot. No conclusive contract was found stating that this scalar must bound the resultant cone rather than each Euler component. Therefore this remains a documented design/terminology question, not another confirmed bug or a safety-limit violation. It is separate from R2-F02's near-vertical heading discontinuity.

If the intention is a cone, construct/project a tilt-vector target with an explicit radial input policy and test all stick azimuths, headings, boundaries and transitions. If independent axes are intended, name and document those limits and the 70.79° corner. Either choice needs a separate tracking/overshoot requirement and continuity tests; do not silently change the feel of recorded input tapes or imply Betaflight equivalence.

## R2-L02 evidence upgrade — Static rotor work during an accepted climb

### Flight and physical interpretation

The [electric rotor stage](https://github.com/bultodepapas/OpenRCsimulator/blob/5a93c105be0736d23f52ac9b46812b3a5e358233/app/physics/multirotor/controlled_plant.gd#L421-L474) uses static quadratic thrust/torque and linear hub-plane drag. Axial inflow, wake energy and dynamic propeller maps are already explicitly excluded in the [FPV research contract](https://github.com/bultodepapas/OpenRCsimulator/blob/5a93c105be0736d23f52ac9b46812b3a5e358233/FPV/03_FLIGHT_DYNAMICS_AND_RESEARCH.md#L224-L228). R7 supplies a numerical consequence and stronger reachability evidence for that existing limitation.

[seventh_pass_rotor_energy.gd](probes/seventh_pass_rotor_energy.gd) starts the unmodified stock quad on a flat pad, in calm air at reference density **1.225 kg/m³**, full SOC. Its synthetic session tape contains one ready OFF tick, one zero-throttle arm ON tick, **700 full-throttle ticks**, then **900 ticks at throttle 0.05**. All **1,602 ticks** accept. Selected snapshots remain armed, and the full tape has no crash/fault. This is a production-code headless session in an isolated fixture, not the full visible application, a physical controller or the club-field scenery.

For a steady, isolated propulsive rotor in still air, useful thrust power `TV` is supplied by shaft power `QΩ`, with additional energy going into the wake. [NASA's momentum-theory derivation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/propeller-thrust/) explains the pressure/work and velocity balance; its [vertical-climb efficiency discussion](https://ntrs.nasa.gov/api/citations/20260001346/downloads/Vertical%20climb%20TM%20addendum%20dateadd.pdf) distinguishes useful power from rotor input. Those references support a consistency check, not calibration of this small FPV propeller. A real unsteady wake can exchange stored energy; the current static model contains no such state.

At **tick 98**, the stock model has 34.7379 m/s velocity along its upward body axis and is 6.133 m above the fixture. Thrust work is **2,355.9153 W**, compared with **2,339.7991 W** of modeled aerodynamic shaft absorption. The summed rotor-air mechanical port is already **+16.115813 W**, including hub-arm work and in-plane drag. These are transient, high-advance-ratio states outside the static bench calibration, even though the session accepts them. The variable named `ascent` in the probe is **upward body-axis speed**, not a generic world-vertical climb rate.

### Full ledger and negative conclusion

The independent oracle includes body translation, locked-body rotation, four relative shaft energies and their cross terms:

\[
E_{\rm mech}=\tfrac12m|v|^2+\tfrac12\boldsymbol\omega^TI_L\boldsymbol\omega
+\tfrac12\sum_iJ_i\Omega_i^2-r\sum_i s_iJ_i\Omega_i.
\]

Gravity is explicitly set to zero in this instantaneous derivative diagnostic, so the table concerns gravity-excluded kinetic work. Rotor-air work includes thrust at each moving hub, in-plane drag and `−Q_i(Ω_i−s_i r)`; motor internal work remains `K_t I_i Ω_i`. The Python oracle recomputes these contributions from the printed state/derivatives and unchanged stock constants.

| Instantaneous power, W | Tick 98, first observed positive rotor-air port | Tick 702, last full-throttle tick | Tick 746, after throttle reduction |
| --- | ---: | ---: | ---: |
| Rotor thrust work | +2,355.9153 | +4,654.1019 | +99.4950 |
| Rotor-air port, including torque and hub drag | **+16.1158** | **+2,406.6758** | **+89.3861** |
| Body aerodynamic drag | −513.5063 | −4,291.1010 | −2,086.1201 |
| Electromagnetic motor work | +2,397.2430 | +2,303.8326 | +9.0158 |
| Internal shaft friction | −58.8098 | −58.0253 | −9.5677 |
| Complete gravity-excluded kinetic derivative | +1,841.0427 | **+361.3821** | **−1,997.2858** |

The complete derivative equals rotor-air work plus body drag, motor work and shaft friction; thrust is already included in the rotor-air row and is not added twice. The ledger closes within the declared **10⁻⁷ W** verification tolerance. In particular, at tick 746 the apparent positive rotor-air contribution coexists with substantial whole-vehicle kinetic loss. **No spontaneous whole-vehicle energy growth is demonstrated.** At tick 702 the motors are powered, so positive total kinetic work is not itself an error. The concern is extending a memoryless static propulsive law into a regime where its own thrust/torque ports imply energy returned from the air without a modeled source or wake state.

Repair alternatives are an explicit supported axial-flow domain with diagnostics/refusal, or jointly consistent thrust/torque/drag laws identified over advance ratio and signed flow. An ideal disk-power bound can help screen a positive-propulsive branch but is not a replacement for finite-propeller measurements, descent/reversal treatment or transient inflow qualification. Do not clip a residual or add an arbitrary guessed term and claim physical fidelity. Acceptance needs hover and advancing flow, climb/chop/descent, wind-relative hub velocities, density/reference provenance, electrical/rotor/body power, and fixed-sample step refinement. This is an evidence upgrade to R2-L02, not a new count.

## Existing relative-rate approximation — Constructed near-stop evidence

The repository already [states the distinction](https://github.com/bultodepapas/OpenRCsimulator/blob/5a93c105be0736d23f52ac9b46812b3a5e358233/FPV/03_FLIGHT_DYNAMICS_AND_RESEARCH.md#L106-L134): the shaft state `Ω` is relative to the body. For thrust axis `a=(0,0,−1)` and spin sign `s`, the signed axial spin relative to nonrotating air is `Ω_air=Ω−sr`. The current aerodynamic law substitutes the relative shaft rate. This is **previously documented**, not a newly discovered independent defect.

The same rotor probe creates three admitted full-frame kernel resets in a stock-data research-air-start session. One `s=+1` rotor has `Ω=10 rad/s`, the other relative shaft speeds are zero, and CG velocity cancels the selected hub's yaw sweep. Each reset and one subsequent 240 Hz session tick are accepted.

| Body yaw, rad/s | Selected rotor `Ω_air`, rad/s | Modeled selected thrust, N | Rotational aerodynamic power, W | Whole gravity-excluded kinetic derivative, W |
| ---: | ---: | ---: | ---: | ---: |
| 0 | +10 | 0.000154729920 | −0.000016125875 | −0.014821236860 |
| 10 | 0 | 0.000154729920 | approximately 0 | −0.020356348658 |
| 20 | −10 | 0.000154729920 | +0.000016125875 | −0.059198886489 |

Zero yaw is the dissipative negative control. At yaw 10, the chosen rotor and hub are instantaneously still relative to the undisturbed air but receive nonzero static thrust. At yaw 20, the rotational aerodynamic term changes sign. The full four-rotor/body work identity still closes, and the total remains negative. The numerical effect is deliberately small; this near-stop construction is not an ordinary high-RPM flight, and reachability from a normal pad start remains unproven. Equal speeds on balanced opposite-spin rotors also cancel the yaw terms in their summed rotational power, so a positive individual port must never be generalized without the full ledger.

A future correction must keep motor back-EMF and motor internal work on the **relative** shaft coordinate while explicitly defining the aerodynamic air-relative convention and its supported sign domain. Refusal/diagnostics are a possible first boundary; a signed blade-flow law needs independent validation. Retest mixed spin senses, zero yaw, near stop, turtle/reversal, body/rotor momentum, work, integration and replay. This construction alone does not determine a correct reverse-thrust law.

## R2-F01 reachability correction

The [current session weather construction](https://github.com/bultodepapas/OpenRCsimulator/blob/5a93c105be0736d23f52ac9b46812b3a5e358233/app/sim/multirotor/session.gd#L226-L247) starts from `WindSettings.defaults()` and alters wind speed and direction. No drone Conditions/custom-density/standard-column installation route was established. Its research air start can be placed as high as 500 m while reference density stays constant.

The earlier R2 source observation still stands: body drag consumes stage density, but rotor coefficients do not. However, R2's altitude/density table is a **controlled atmosphere counterfactual**, not evidence that the current player drone loses the wrong amount of lift with altitude. Installing a different environment on a component is not the same as demonstrating an admitted session/UI route. The acceptance plan must first connect and identify the intended atmosphere option, then qualify coefficient reference density, motor/bus equilibrium and wind-relative loads. The existing report and ledger now link this qualification correction.

## Verification, reproduction and remaining gates

The [reproducer](probes/reproduce_seventh_pass.py) reconstructs **459 real dependency files** from the reviewed Git commit: the existing 432-file base manifest plus 27 exact new sources. The base's recorded CRLF byte policy is honored. No production stubs, stock-file modifications or full-app project substitution are hidden: the harness has a minimal explicit 240 Hz project, and creates one labeled custom motor JSON beside the stock resources.

Run from a checkout containing the reviewed Git objects and the pinned official engine:

```bash
python3 docs/research/project-audit-2026-11-21/probes/reproduce_seventh_pass.py \
  --repo-root /absolute/path/to/OpenRCsimulator \
  --godot /absolute/path/to/Godot_v4.8-beta2_linux.x86_64 \
  --out /absolute/path/to/a/new/r7-output
```

The engine SHA-256 is `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`; stock quad JSON SHA-256 is `82f1ff64a572e8afd23c1cf84e824ee784bf7d04d5635ac18792001c3dbeeb62`. The checked runner records command, completion marker, timeout, exit, diagnostics and log identity. The final evidence preserves all small probe logs, source/probe identities, the manufactured input hash, and independent oracle output; all dependency bytes are checked again after execution. The GDScript framed callbacks and reference RK4 are the exercised path. Native or physical-device qualification is not inferred from a hard-coded label or a prior CI job.

Four new diagnostic probes contain **80 observation checks**. The selected unchanged rate, electrical-bus, physical-admission and pack-charge suites pass **115/32/28/9 checks**, respectively (**184 total**), as separate baseline checks. All nine checked invocations (import plus eight scripts) pass with zero engine errors/warnings. The independent Python program checks **17 equation/ledger cases**, including signs, quaternion tilt, identical sampled commands, local motor derivatives and complete body/rotor power. Exact replay would not replace these independent checks.

Exploratory fixtures with incorrect diagnostic provenance, wrong probe labels/oracles, invalid requests for more than 16 pieces, or formatting errors were rejected or discarded before the final reconstruction. No failed/incomplete exploratory run supports the published conclusions. The local host had no configured pool/queue; the checked runner retained admission ownership. These headless reference results do not qualify complete application rendering, physical flight, target performance or all permitted custom parameters.

The reviewed R6 head's CI completed with failure while MetalFX source controls passed; [the retained snapshot](seventh-pass-ci-snapshot.json) records that status without pretending the new local drone probes repair it. Full PR CI, target/native qualification where applicable and physical/pilot acceptance remain open. No R7 performance gain is measured. A promising engineering direction is to make refinement respond to identified electrical/contact modes, but any speed or accuracy benefit requires measurement and a supported error/domain policy.

**Priority:** close the two input/numerical admission defects first; clarify the Angle target contract; then qualify an axial/near-stop rotor envelope with coherent power accounting. Preserve the already repaired November 16 findings, the existing bounded-regeneration policy, and all negative controls. Inflow, wake interactions, ground effect, ESC current limits, motor thermal behavior and sensor realism remain explicit research work, not newly counted omissions.
