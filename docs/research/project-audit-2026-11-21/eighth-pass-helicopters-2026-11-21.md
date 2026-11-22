# Eighth pass: helicopter contact stability, controls and rotor consistency

Date: **2026-11-21**. Reviewed source: **`c1eb426900e594c20d095120c149386305afdd4d`**. This is the helicopter continuation of [A36](README.md), on `audit/physics-math-aero-2026-11-21` and draft [PR #17](https://github.com/bultodepapas/OpenRCsimulator/pull/17).

**Result: one new conditional numerical-admission defect, one arming-contract gap, and two evidence upgrades to existing rotor-model limitations.** This batch adds research, executable observation probes and independent mathematical checks. It changes no production equation, aircraft preset, controller, runtime or native implementation.

The [helicopter guide](../../HELICOPTER.md) distinguishes the current **advanced articulated HX-700 laboratory/inspector target** from the **historical playable X-Cell reference**. The HX-700 candidate refuses playable-session admission and retains six open release gates. These experiments use the historical stock `xcell_60_research.json` and its reference session. Neither the historical visuals nor shared mean-rotor equations transfer physical qualification to the HX-700.

## Findings and evidence boundary

| Item | Classification | Strongest evidence | Practical meaning |
| --- | --- | --- | --- |
| **R8-F01** | New conditional defect; proposed P2 | Full custom-data loading, normal pad reset, accepted 240 Hz reference ticks, stage refinement and independent contact eigenmode | Skid stability admission omits geometry-dependent rotational stiffness/damping. Admitted wider skids can amplify a mode that should decay. |
| **R8-G01** | Contract gap; existing HELI-20/H06 boundary | Stock accepted input tapes and rearm/hold-release transactions, independent swash arithmetic | The one-degree guard reads premix collective; trainer feedback and clipped servos can give greater postmix collective. The intended guard quantity must be resolved. |
| **HELI-05 continuation** | Existing approximation quantified; no new defect ID | Constructed full 19-state Flight evaluator and complete geared kinetic-power ledger | Tilting thrust changes body work while shaft-frame torque and inflow remain unchanged in this closure. |
| **HELI-06 continuation** | Existing linearization/reconstruction quantified; no new defect ID | Unsaturated component controls, signed closure calculation, downstream fin loads, separate matched session-stage/reset/tick | Near-zero tail thrust can coexist with substantial reconstructed wake; the effect reaches the fin. |

The [retained evidence](eighth-pass-evidence.json), [portable reproducer](probes/reproduce_eighth_pass.py) and [independent oracle entry point](probes/eighth_pass_oracles.py) are the executable record. A passing observation probe demonstrates the documented current behavior; it does not mean the reported issue has been repaired.

## Runtime connections traced

The session maps conditioned roll/pitch/yaw/collective to electronics, whose trainer feedback and three-servo swash produce the stage's collective and cyclic commands. Main flapping and induced velocity are continuous states; the tail receives main-wake geometry and supplies its own reconstructed wake to the fin. The drive, both rotor torques and geared inertias enter the coupled body/shaft solve. Wind is sampled at the stage's position and time. Skid normal forces and tangential bristles feed the same body derivatives, with a helicopter-owned integration policy handling stopped-shaft events and endpoint reconciliation.

This matters because a locally reasonable formula can fail at a boundary: mass-only contact admission cannot bound a geometry-dependent roll mode; a premix control readout need not equal a clipped swash output; a tilted force direction and a shaft-frame inflow law need a shared power interpretation. The tests below follow those connections instead of inferring whole-flight behavior from an isolated equation.

## R8-F01 — skid admission omits rotational contact stiffness

### Source and admission

The [rotorcraft reader](https://github.com/bultodepapas/OpenRCsimulator/blob/c1eb426900e594c20d095120c149386305afdd4d/app/physics/rotorcraft_data.gd#L106-L118) validates four skid positions, positive coefficients and finite reach. Its numerical guard accepts

\[
\frac{\sqrt{4k/m}}{240}\leq0.5,
\qquad \frac{4c}{240m}\leq1.
\]

These depend on vehicle mass and per-contact spring/damper coefficients, but not the contact lever arms or body inertia. The [contact law](https://github.com/bultodepapas/OpenRCsimulator/blob/c1eb426900e594c20d095120c149386305afdd4d/app/physics/rotorcraft/skid_contact.gd#L46-L116) applies those forces at the authored points, so the resulting angular stiffness and damping do depend on geometry.

The manufactured input preserves stock mass `8.2 kg`, locked inertia `diag(0.18, 0.34, 0.28) kg m²`, `k=10000 N/m`, `c=190 N s/m`, fore/aft coordinates `±0.0974 m` and vertical arm `h=0.1098 m`. **The only physical values changed are the four lateral skid coordinates**, from `±0.0858 m` to `±0.5 m` or `±1.0 m`. The point quantity's `kind` and `source` are also changed to label the manufactured geometry honestly. No measured hardware or recalibrated mass distribution is claimed.

Both variants pass the full reader and normal field/pad setup. Their reaches are `0.521097687579 m` and `1.010714005048 m`; both fit the authored `1.25 m` envelope and `6 m × 6 m` pad. Both retain the same guard ratios, `0.291012623237` and `0.386178861789`. This is programmatic custom-file admission, not a demonstrated custom-helicopter selection UI.

### Independent contact calculation

At the level, stopped-rotor, four-contact equilibrium, each normal force is `20.1036325 N` and compression is `0.00201036325 m`. The relevant smooth mode includes roll **and** lateral bristle motion; using only a normal-spring oscillator would omit an active coupling.

Let `φ` denote roll, `p=φ̇`, `v` the inertial CG lateral velocity along the level body's rightward axis, and `b` the common lateral bristle displacement. For symmetric lateral positions `±y`, the first-order equations are

\[
\begin{aligned}
\dot\phi&=p,\\
J_x\dot p&=(mgh-4ky^2)\phi-(4cy^2+4ch^2)p+4chv+4khb,\\
m\dot v&=4chp-4cv-4kb,\\
\dot b&=v-hp.
\end{aligned}
\]

They retain the normal-force lever change, contact damping, and tangential spring/damper forces. At the stationary zero-wind origin, airframe drag is higher order and the held stopped shaft has no first-order response in this roll mode. The resulting characteristic equation is

\[
(m\lambda^2+4c\lambda+4k)
(J_x\lambda^2+4cy^2\lambda+4ky^2-mgh)
+4mh^2\lambda^2(k+c\lambda)=0.
\]

The Python oracle brackets and solves this polynomial from the stock parameters and changed geometry. It does not take the logged eigenvalue as its answer. For classical RK4, a scalar mode has amplification

\[
R_4(z)=1+z+z^2/2+z^3/6+z^4/24,\qquad z=\lambda/240.
\]

| Half-width `y` | Fast eigenvalue `/s` | `λ/240` | Predicted one-tick gain | Observed accepted one-tick gain |
| --- | ---: | ---: | ---: | ---: |
| `0.5 m` | −1055.74704193 | −4.39894600802 | 7.69139201509 | 7.69139192216 |
| `1.0 m` | −4220.96938650 | −17.5873724437 | 3217.90312295 | 3217.90312533 |

Both fast roots are decaying continuous modes but lie outside RK4's stable negative-real interval. For `y=0.5 m`, the exact linear mode would retain about **0.01229** of its amplitude after one tick; the accepted integration instead multiplies it by about **7.69**.

### Accepted sessions and matched controls

The [skid probe](probes/eighth_pass_skid_admission.gd) uses two distinct experiments.

**Constructed calm mode.** After real custom loading and ground reset, a detached simulation reset installs a tiny roll eigenvector: `φ=10⁻⁸ rad` for `y=0.5 m`, or `10⁻¹⁰ rad` for `y=1 m`. Yaw is explicitly zero so lateral velocity and all four eastward bristles use the same frame. The rotor remains stopped and held. Each production tick is accepted without fault or crash. In all recorded first-tick refinement stages, every normal force remains positive, traction stays below its Coulomb cap, and there is no rotor-stop event. This isolates the smooth numerical mode from contact switching.

The smallest normal force in the one-piece half-width mode is about `20.0893 N`; maximum traction/cap ratio is `0.0004872`. At one metre the corresponding values are `20.0069 N` and `0.0015511`. These are far from unilateral loss of contact or friction saturation. A separate one-metre custom helicopter starts and ends essentially at rest after 48 accepted ticks in calm air; that negative control records endpoints rather than every intermediate pose.

**Ordinary ground start in wind.** The second experiment injects no state perturbation. It loads the default field, selects ground start, configures `3 m/s` steady wind from `45°`, resets normally and advances 48 ticks without pilot input or arming. The authored pad heading remains `90°`. Stock and half-width custom starts share the identical initial state, wind and commands.

| Ordinary ground-start quantity | Stock skid geometry | `±0.5 m` geometry |
| --- | ---: | ---: |
| First accepted tick roll rate `p` | 0.000486395587 rad/s | 0.000326233290 rad/s |
| Same first interval, 64-piece diagnostic `p` | 0.000486154018 rad/s | 0.000159083418 rad/s |
| Tick 4 `p` | 0.003916918501 rad/s | 0.075607780362 rad/s |
| Tick 48 `p` | −0.000878414498 rad/s | 0.243495155661 rad/s |
| Accepted ticks, no fault/crash | 48 | 48 |

The wider-skid trajectory develops alternating roll rates, with contact clipping in later ticks. Its maximum roll displacement remains only about `0.04965°` over this short trace; the stock value is about `0.03029°`. The evidence establishes erroneous numerical response, not a demonstrated visible crash, stock-aircraft instability or a real helicopter handling prediction.

### What the refinement establishes

The diagnostic calls the real session stage and existing helicopter adapter for `1, 8, 16, 32, 64` equal pieces over the **same 1/240 s interval**, with unchanged held input and simulation clock. It does not resample the controller faster or modify `model.substeps`.

The unsplit result matches the actual accepted body/contact endpoint within `10⁻¹³`, excluding the two stopped-rotor heading-memory entries that the session intentionally reconciles at the endpoint. With zero rotor speed, those entries have no rotor-force effect here. First-tick wind refinements remain loaded, unsaturated and event-free. For the half-width case, successive roll-rate differences shrink from about `1.36×10⁻⁹` to `6.68×10⁻¹¹` to `3.71×10⁻¹² rad/s` across the last refinements. The calm half-width 64-piece roll is `1.229030278×10⁻¹⁰ rad`, agreeing with decay. The one-metre fine result is near the floating-point floor; the oracle uses an absolute bound there.

An exploratory one-metre **wind** case was excluded from this clean modal comparison because its one-piece diagnostic triggered a stopped-rotor event. It cannot be described solely by this smooth RK4 amplification calculation. This narrowing does not affect the accepted calm one-metre or ordinary half-width wind witnesses.

### Repair options and gates

The smallest correction is a conservative admission bound that includes the coupled translational, rotational and bristle modes using actual contact geometry and locked inertia. A more general option is supported refinement or another stable contact treatment inside the helicopter's existing integration ownership. Geometry-dependent quantities could be prepared once during admission; there is no measured performance result for that proposal.

Simply attaching a generic substep callback is insufficient: [Simulation rejects multiple contact substeps when a custom step policy owns the tick](https://github.com/bultodepapas/OpenRCsimulator/blob/c1eb426900e594c20d095120c149386305afdd4d/app/sim/simulation.gd#L544-L575). A solver change must preserve accepted 240 Hz input sampling, rotor stop/heading reconciliation, event order, atomic failure/rollback, dry-friction caps and checkpoint/backend identities. Acceptance should include both manufactured cases, stock controls, signed/asymmetric geometry, all contact modes, near-cap transitions, step refinement and actual-native parity. Physical skid parameters require separate identification.

## R8-G01 — decide which collective the one-degree arming rule means

The [session guard](https://github.com/bultodepapas/OpenRCsimulator/blob/c1eb426900e594c20d095120c149386305afdd4d/app/sim/helicopter_flight_session.gd#L1097-L1115) uses the premix collective accessor. The [electronics stage](https://github.com/bultodepapas/OpenRCsimulator/blob/c1eb426900e594c20d095120c149386305afdd4d/app/physics/rotorcraft/electronics.gd#L171-L195) adds trainer feedback before swash travel is clipped. Clipping destroys the zero-sum property of cyclic mixing, so the mean servo output can differ from premix collective even with centered pilot cyclic.

HELI-20 describes a one-degree zero-blade-pitch condition, but its [H06 record](../helicopter/HELI-20/README.md#accepted-collective-display-heli-20-h06-2026-11-08) explicitly retains the premix accessor for arming after correcting the HUD. This is a documented boundary that now has an executable counterexample, not evidence that the accessor was accidentally restored.

The [arming probe](probes/eighth_pass_arming.gd) uses stock data and the actual session. The reconstructed collective is

\[
\theta_{\rm mean}=0.22\frac{s_1+s_2+s_3}{3}\quad\text{radians},
\]

where each `sᵢ` is the clipped servo position. Independent arithmetic also checks the unbounded mean, the authored collective curve and linkage limits.

| Experiment | Premix | Postmix sent to rotor | Action evidence |
| --- | ---: | ---: | --- |
| Accepted constructed reset with body rates `p=−3`, `q=+3 rad/s` | +0.9° | +1.837925461° | Disarm/rearm/hold release, then accepted tick |
| 67-tick direct cyclic tape, then centered cyclic with trainer | +0.9° | +1.023006420° | Same between-tick action batch; tick 68 accepted |
| Opposite signed 355-tick tape | −0.9° | −1.023049148° | Same between-tick action batch; tick 356 accepted |
| 181-tick tape followed by six-tick action spacing | +0.9° | +1.340337633° at rearm | Rearm at tick 187; release after six more ticks; accepted through tick 199 |

For the spaced case, the clipped servos are `[0.6917489147904, −1, 0.627250695943436]`. The rearm frame has approximately `57.33°` roll and `13.56°` pitch. At that same state, direct cyclic produces `+0.9°`; the constructed case also has a stationary-trainer negative control at `+0.9°`. The servo limit is causal, not a radians/degrees conversion error.

All tapes use scripted session commands and trainer changes at 100 m initial altitude. Six ticks are 25 ms. A longer exploratory 50 ms disarmed gap settled to the premix value, so persistence and ordinary human timing are not established. The record does not exercise a physical radio, selection UI, ordinary pad start, achieved servo dynamics or a consequential motor-start load. Arming also retains hold until explicitly released; the probe does not omit that second action.

**Decision needed:** if arming enforces a pilot-stick pickup rule, name premix collective explicitly and explain its relationship to the displayed postmix value. If it enforces the collective being commanded to the rotor, use a fresh same-state postmix result, fail closed if unavailable, and define how clipped trainer feedback is handled. This is distinct from [R5-F01](fifth-pass-physics-2026-11-21.md), where trim is added outside the already limited cyclic feasible set, and from the repaired H06 HUD presentation.

After choosing the contract, verify both signs, trainer/direct states, saturation transitions, pause/loss/hold transitions, failed evaluations and input timing. Do not label the current observation a proven physical hazardous start or count it as another swash-trim bug.

## HELI-05 continuation — tilted rotor work versus shaft-frame closure

The [main-rotor law](https://github.com/bultodepapas/OpenRCsimulator/blob/c1eb426900e594c20d095120c149386305afdd4d/app/physics/rotorcraft/main_rotor.gd#L144-L174) derives thrust/torque from shaft/body flow and applies thrust along the flapped normal. The [stage](https://github.com/bultodepapas/OpenRCsimulator/blob/c1eb426900e594c20d095120c149386305afdd4d/app/physics/rotorcraft/main_rotor_stage.gd#L70-L89) uses the same shaft-frame approximation for mean inflow. [HELI-05](../helicopter/HELI-05/README.md) already says exact tilted-plane projection needs separate qualification. R8 quantifies a consequence without inventing a new owner or claiming energy creation.

The [rotor probe](probes/eighth_pass_rotor_consistency.gd) evaluates stock components and the complete 19-state Flight model at zero wind, level attitude, zero body angular rate, `u=15 m/s`, `Ω=167 rad/s`, no contact and disabled ground effect. Collective is `0.06974 rad`. An independent shaft-aligned momentum solve sets `vi=1.348392451805 m/s`; separate constructed cyclic biases make longitudinal flap derivative zero at `a₁=0, −0.12, +0.12 rad`, with `b₁=0`. These are instantaneous constructed inputs, not complete trimmed flight or accepted session maneuvers.

| Quantity | Flat | Forward tilt `a₁=−0.12` | Aft tilt `a₁=+0.12` |
| --- | ---: | ---: | ---: |
| Main thrust | 93.880325867 N | Same | Same |
| Main shaft load | 865.297808798 W | Same | Same |
| Reflected tail shaft load | 43.643515543 W | Same | Same |
| Net main-shaft drive power | 1231.1908 W | Same | Same |
| Main-thrust work on translating body | 0 W | +168.579315458 W | −168.579315458 W |
| Full coupled kinetic-energy derivative | +114.697187905 W | +283.276503362 W | −53.882127553 W |

The work difference is `15 T sin(0.12)`. Both the reported `μ≈0.115897` and flap magnitude lie within the code's nominal indicators; those indicators do not identify the physical model at these constructed states.

The independent ledger retains the geared cross term. For body velocity `v`, body rate `ω`, shaft speed `Ω`, locked inertia `J`, coupling vector `b` and spin inertia `Iₛ`,

\[
K=\tfrac12m\lVert v\rVert^2+\tfrac12\omega^TJ\omega
+\Omega b^T\omega+\tfrac12 I_s\Omega^2.
\]

At these zero-body-rate instants,

\[
\dot K=m\,v\cdot\dot v+\Omega(I_s\dot\Omega+b\cdot\dot\omega).
\]

The raw states, all derivatives, component loads, drive and coupled inertia are retained in `ENERGY_LEDGER` records. Independent reconstruction agrees with the component power sum within `2×10⁻¹² W`. At the flat state the translational term is `−207.552287754 W` and the spin/coupling term is `+322.249475659 W`. Thus omission of shaft acceleration or body/shaft coupling does not explain the tilt-dependent result.

**Interpretation:** the closure changes propulsive body work without changing the shaft draw that accompanies it. This motivates a joint flow/thrust/torque review. The example is powered, the ledger closes, and it contains no measured wake or actuator energy. It does not prove that exactly `168.58 W` must be added to shaft demand, or that total helicopter energy is created. A different consistent rotor closure can redistribute induced, profile, in-plane and hub/actuator work.

Repair choices are an explicit supported-envelope diagnostic or a versioned derivation of tilted-plane flow, inflow target, force direction, torque and hub/actuator work together. Acceptance needs signed tilt and flow sweeps, wind/frame transformations, hover/climb/descent, saturation and stop transitions, full body/shaft accounting, native/replay parity and measured thrust/shaft-power data. A unilateral power clamp is not a derivation.

## HELI-06 continuation — tail thrust and reconstructed wake disagree under a stated closure

The [tail law](https://github.com/bultodepapas/OpenRCsimulator/blob/c1eb426900e594c20d095120c149386305afdd4d/app/physics/rotorcraft/tail_rotor.gd#L68-L142) uses local trim derivatives in a global through-origin thrust expression, then reconstructs induced velocity from thrust and pitch. [HELI-06](../helicopter/HELI-06/README.md) already records this extrapolation and the approximate wake reconstruction. The primary [Gavrilets–Mettler–Feron paper](https://users.encs.concordia.ca/~bwgordon/mit_heli_report.pdf), §4.6 Eqs. 43–50, explicitly linearizes around trim and reconstructs the wake; this is not a newly discovered transcription error. Its §4.1.1 also limits the momentum model's applicability, particularly in vortex-ring flow.

### Unsaturated component witness and fin consequence

At main `Ω=167 rad/s`, tail ratio `4.66` and radius `0.13 m`, tip speed is `101.1686 m/s`. With body air velocity `(0, −5, 0) m/s`, zero body rates and main induced state `4.2 m/s`, set tail collective to `+0.0370668369435 rad`. Tail in-plane advance ratio is zero; the main-wake exposure factor is zero in this case.

The linearized thrust is essentially zero (`C_T≈4.34×10⁻¹⁹`), below its cap, while reconstructed tail induced velocity is **−2.5 m/s**. About `28.6923 W` of tail profile shaft power remains; this is not an unpowered rotor.

The same stage passes 20% of that wake to the vertical fin. Its lateral relative velocity becomes `−4.5 m/s`, versus `−5 m/s` in a matched zero-exposure counterfactual. The [aerodynamic stage](https://github.com/bultodepapas/OpenRCsimulator/blob/c1eb426900e594c20d095120c149386305afdd4d/app/physics/rotorcraft/aerodynamic_stage.gd#L115-L127) and [airframe](https://github.com/bultodepapas/OpenRCsimulator/blob/c1eb426900e594c20d095120c149386305afdd4d/app/physics/rotorcraft/airframe.gd#L208-L241) carry that difference into loads:

| Fin quantity | Model wake exposure `0.2` | Counterfactual exposure `0` | Difference |
| --- | ---: | ---: | ---: |
| Side force | +0.1488375 N | +0.18375 N | −0.0349125 N, or −19% |
| Yaw moment | −0.135442125 N m | −0.1672125 N m | +0.031770375 N m |

The counterfactual isolates the modeled wake contribution; it is not a measured no-wake airframe. Zero normal speed/zero pitch gives zero wake; reversing normal speed and pitch reverses wake; removing fin exposure leaves the rotor's thrust and induced velocity unchanged.

### Independent closure check and its limits

Under the stated steady signed uniform-disk relation,

\[
C_T=2\eta\lambda\sqrt{\mu^2+(\lambda-\mu_z)^2},
\]

the code's `μ=0` local derivative ratio yields `θ=−3μ_z/4` at zero thrust, while its reconstruction gives `λ=μ_z/2`. For zero `C_T`, the multiplied algebraic relation permits `λ=0` or the degenerate zero-through-flow root `λ=μ_z`; the paper's divided form is singular at the latter. The reconstructed half-flow value is neither root.

With stock tail `η=0.9`, the residual is **+0.001099160321** in `C_T`, or **+0.7316867465 N equivalent unblocked scale**. This is a consistency residual under the named model assumptions, not a measured missing force and not a theorem that a real zero-net-thrust rotor has no local wake. The source approximation's accuracy away from its trim point remains unmeasured.

### Separate accepted session witness

A second construction uses the real stock session's hover trim, sets lateral body velocity to `−19.3 m/s`, main speed to `167 rad/s`, `a₁=b₁=0`, main `vi=4.2 m/s`, heading/body rates zero and yaw integrator `−0.15`. The required yaw stick is approximately `−0.997940766391`, within the admitted range, giving tail collective `0.143077990602 rad`. The moderate `−5 m/s` component state is not presented as this session state: the session's trim/controller bounds require a different construction.

The probe records actual session weather, sampled wind, terrain-relative height, contact loads, power scale, input, backend and aircraft hash. It evaluates those same inputs with diagnostics, compares the full derivative to the real session stage after prepared-reset commit, then advances one accepted tick. Tail thrust is about `9.59×10⁻¹⁶ N` and reconstructed wake is `−9.65 m/s` at the matched initial stage. This confirms code-path admission, not a demonstrated pilot trajectory. The main `μ≈0.149121` indicator does not qualify this tail-flow regime.

Repair choices are to diagnose/refuse unsupported extrapolation or derive signed thrust and wake consistently over an explicit supported domain, with branch handling and possibly a dynamic tail-wake state. Do not force every instantaneous zero-thrust crossing to erase wake if transient wake memory is introduced. Test signed pitch/sideflow sweeps, zero thrust, zero exposure, fin force and moment, conditional momentum residuals, degenerate/vortex-ring/windmill regimes, shaft work and measured data. Preserve separate H02 low-RPM and WNEW-03 wake-seam coverage; this unsaturated example does not cross that seam.

## Deduplication and rejected promotions

- R5-F01 already owns cyclic trim outside the post-limit feasible set. The arming question concerns which collective quantity the guard promises.
- H01 retains the powered ground-heading issue; its stopped-rotor subset is already repaired. The calm contact test deliberately excludes powered heading dynamics.
- H02/A20 low-RPM law overlap and WNEW-03/04 wake/sideflow seams remain existing limitations. They are not new R8 defect counts.
- A manufactured excessive shaft-inertia candidate passed reader construction but was rejected during reset/preflight. That is an earlier-admission hardening opportunity, not an accepted-flight defect, and is not promoted here.
- Achieved servo lag, freewheel/separate shaft speed, fuel inventory, detailed wake and HX-700 identification remain declared work. Listing them again would not make them newly discovered bugs.
- Existing H03/H05 collision/lake fixes, H04 consent, H06 display, H07 trim refusal and A30 reset transaction work were checked as ownership boundaries, not reported as absent.

## Reproduction and verification

The [reproducer](probes/reproduce_eighth_pass.py) reconstructs **438 real source/data dependencies** from the reviewed Git commit: the existing 432-file [manifest](integration-manifest.json) plus six unchanged helicopter test/dependency scripts in the [R8 supplement](eighth-pass-extra-sources.json). It preserves each recorded Git blob, byte hash and checkout line-ending policy, creates a minimal 240 Hz project, and introduces no production stubs. Synthetic geometry is generated outside the repository from the exact stock JSON.

Use an installed pinned Godot binary and a new output directory:

```sh
python3 docs/research/project-audit-2026-11-21/probes/reproduce_eighth_pass.py \
  --repo-root /absolute/path/to/OpenRCsimulator \
  --godot /absolute/path/to/Godot_v4.8-beta2_linux.x86_64 \
  --out /absolute/path/to/new-r8-evidence
```

The engine is `4.8.beta2.official.cafc17a19`, SHA256 `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`. Stock X-Cell input SHA256 is `29b4cbc6ff258c18839589b1eacd88968b58bc691dd61502177bb741c0c1da04`. The checked runner uses isolated XDG locations and preserves pool/queue admission variables. The observed host had no configured pool and queue admission was inactive; this does not authorize bypassing admission on another host.

The fresh portable run passed **nine checked jobs**, all with zero warnings/errors: import, three observation probes and five unchanged helicopter suites. The observation probes contain **140 checks** (70 skid admission, 22 arming, 48 rotor consistency). Existing suites contain **276 checks** (51 swash, 23 geared coupling, 15 skid bristles, 162 tail rotor and 25 main-rotor stage). All 438 source/data files remained byte-identical after execution.

All three independent standard-library Python oracles passed: 197 skid assertions reconstruct the contact mode and refinements; four arming cases reconstruct curve/linkage/clipping arithmetic and transaction timing; 465 rotor assertions reconstruct coefficients, complete geared power ledgers and the matched session stage. These are mathematical/evidence checks, not three additional physical experiments. The entry point also binds logged aircraft hashes to actual stock/custom bytes and checks authored pad geometry and friction against fixture data.

The [published evidence](eighth-pass-evidence.json) retains full small engine logs, completion markers, result fields, numerical frames, source/probe hashes and oracle output. Host paths and capture/time metadata are removed by its stated publication policy; raw evidence SHA256 is `f266e969bf48bea6067a383572c27a319c3e1f97ef60931931aecff444edf9bb`. The three new engine-log SHA256 values are `d4843efb9ef22f10e68edb92f1c0b7f01b7804cda3ff729a9442badf1ac1686f` (skid), `f75a9f3e710c90157352335178151addc77075116399f6f5b458b270a55392df` (arming), and `92c9f635265a310aa8e3cb041bfd619e9f5af1b655990ab86b2ba2f528c3616e` (rotor). The original PDF/ZIP remain untouched.

The source-frozen probes are mathematical diagnostics on the GDScript reference backend. Native parity, physical validation, pilot input, rendered UI, recorded replay, long flight stability and target-hardware performance have not been qualified by these experiments. The [CI snapshot](eighth-pass-ci-snapshot.json) records no PR-triggered runs returned for reviewed `c1eb426` by the first-page connector query. Prior-head required CI remains recorded as failed in [R7's snapshot](seventh-pass-ci-snapshot.json). The empty current query is not a successful required gate. Draft PR #17 remains separate from main, which has advanced independently.

## Recommended correction order

First close the geometric contact-admission hole, preserving the stock control and fixed-clock transaction. Resolve the arming contract next; its implementation choice should follow the promised quantity. Then address thrust/inflow/torque/wake consistency as coordinated HELI-05/06 model work with measured calibration and native/replay gates. This order avoids interpreting a numerically unstable contact response as an aerodynamic tuning problem, and gives future HX-700 work clearer reusable boundaries.
