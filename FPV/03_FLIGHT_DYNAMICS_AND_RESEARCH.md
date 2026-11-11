# FPV flight dynamics and research specification

**Settings follow-up:** [07](07_BETAFLIGHT_INAV_SETTINGS_RESEARCH.md) compares current BF 2026.6.2 and INAV 9.1.0 settings; [08](08_SETTINGS_SCHEMA_IMPORT_AND_TESTS.md) owns their typed import/capability contract. The 4.5.2 rate-math baseline below remains separate. Current BF throttle has different curve/lookup semantics; [09](09_SETTINGS_EVIDENCE_AND_REFERENCE_PROBE.md) records a scoped extracted-source probe. Firmware PID values are not SI gains, and current firmware filter cutoffs cannot be applied to the 240 Hz stream without qualification.

**Investigation:** 2026-11-11. Repository source checked at `7bff78490f9af5c1664f47c8ba865a92b3430920`. Owning steps: DR-02/03/05/06/07/08/09/12/21/38…40. This file supplies the physical/control specification behind [01](01_FPV_MASTER_PLAN.md) and [02](02_ENGINEERING_CONTRACTS.md). Numbers called *computed* below are calculations on stated assumptions, not hardware validations. Manufacturer-reported data is attributed to its publisher. No apparatus was independently tested. The 20 executed synthetic reference cases, complete code and results are in [06](06_SOURCE_AUDIT_AND_EVIDENCE.md); proposed implementation tests are in [05](05_VALIDATION_AND_IMPLEMENTATION_BACKLOG.md).

## 1. Versioned Actual-rate contract (DR-08)

**Source pin:** Betaflight **4.5.2**, commit [`024f8e13d4e642eb6a380308685b9ea3aa3ef1a2`](https://github.com/betaflight/betaflight/commit/024f8e13d4e642eb6a380308685b9ea3aa3ef1a2), specifically [`src/main/fc/rc.c`](https://github.com/betaflight/betaflight/blob/024f8e13d4e642eb6a380308685b9ea3aa3ef1a2/src/main/fc/rc.c), [`controlrate_profile.c`](https://github.com/betaflight/betaflight/blob/024f8e13d4e642eb6a380308685b9ea3aa3ef1a2/src/main/fc/controlrate_profile.c), [`controlrate_profile.h`](https://github.com/betaflight/betaflight/blob/024f8e13d4e642eb6a380308685b9ea3aa3ef1a2/src/main/fc/controlrate_profile.h), [`src/main/cli/settings.c`](https://github.com/betaflight/betaflight/blob/024f8e13d4e642eb6a380308685b9ea3aa3ef1a2/src/main/cli/settings.c), and [`src/main/config/config.c`](https://github.com/betaflight/betaflight/blob/024f8e13d4e642eb6a380308685b9ea3aa3ef1a2/src/main/config/config.c). Accessed 2026-11-11 through GitHub's source-file and commit APIs. This is a specific compatibility target, not a claim about all releases. GPL terms apply to the firmware source; use an independently implemented mathematical specification and resolve distribution obligations before any source port or bundled comparator.

At one axis, let signed, calibrated and already-deadbanded normalized deflection be `x ∈ [-1,1]`. For raw CLI values `rc_rate`, `srate`, and `expo` on that axis, set `C = 10*rc_rate` deg/s, `M = 10*srate` deg/s, `e = expo/100` and `L = rate_limit` deg/s. Calculate:

```text
a = max(0, M - C)
curve_dps = C*x + a * abs(x) * (e*x^5 + (1-e)*x)
setpoint_rad_s = clamp(curve_dps, -L, L) * pi/180
```

Here `C` is the center slope in degrees/s per unit stick; `M` gives the full-stick rate only if `M >= C` and the separate cap does not bind. When `M < C`, the difference is floored at zero and the uncapped full-stick rate is `C`; the cap then applies. **`expo=0` is generally not a linear response** because the second term is `a*x*abs(x)`. Firmware computes the expression with single precision; the simulator's double precision should match it within a declared numerical tolerance, not bit for bit. Per-axis limits must be preserved. The Actual profile limits code uses up to 200 for `rc_rate` and `srate`, and 100 for expo; distinguish persisted firmware values from CLI validity constraints rather than silently clamping malformed imports.

The per-axis fields are `roll_rc_rate`, `pitch_rc_rate`, `yaw_rc_rate`, their `_srate` and `_expo` counterparts, and `roll_rate_limit`, `pitch_rate_limit`, `yaw_rate_limit`; `rates_type = ACTUAL` determines their meaning. Pin the selected profile number, source firmware version, raw fields, transformed values and hash. Handle a full dump and explicit selected rate profile deterministically. A `diff` may omit version-specific defaults: either reconstruct from the exact pinned version's defaults and identify this explicitly, or refuse an incomplete import. Do not accidentally apply fields from another `rateprofile` block. Report unsupported RC deadband, smoothing, camera-angle mix, PID and throttle behavior. A minimal rates-only slice may reject incompatible non-default throttle fields instead of pretending they were imported. Applying a calibrated-input deadband twice changes the center curve.

**Computed reference vectors** for `C=200`, `M=670` deg/s, `e=0.58`, `L >= 670`:

| x | −1 | −0.75 | −0.5 | −0.25 | 0 | 0.25 | 0.5 | 0.75 | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| deg/s | −670 | −309.554443359 | −153.609375 | −62.404052734 | 0 | 62.404052734 | 153.609375 | 309.554443359 | 670 |

Test odd symmetry, center slope, grid points, `expo=0` and 1, M<C, M=C, all three axis settings, cap below M and cap above M, malformed/non-finite fields and `diff`/profile ambiguity. For example `C=200,M=670,e=0,x=.5` gives `217.5 deg/s`, not 335. `C=200,M=100,x=.5` gives `100 deg/s`; `L=500` clips a 670 deg/s endpoint to 500. Formula and lookup-vector tests prove the imported mapping only; receiver processing, stick filtering, PID, feedforward and motor behavior remain separate.

### Second supported family: the pinned Betaflight curve

The same pinned `rc.c` defines the distinct Betaflight family. Let `r=rc_rate/100`, `s=srate/100`, `e=expo/100`, with raw input `x` and `b=abs(x)`. The mathematical mapping is:

```text
r_eff = r + 14.54*(r-2) if r > 2, else r
x_expo = x*b^3*e + x*(1-e)
curve_dps = 200*r_eff*x_expo / clamp(1-b*s, 0.01, 1)
setpoint_rad_s = clamp(curve_dps, -rate_limit, rate_limit) * pi/180
```

The denominator uses the original `b`, not the shaped `abs(x_expo)`. `s=0` reduces to the source's no-super-rate branch. For `r=1,s=0.7,e=0`, positive stick positions 0.25/0.5/0.75/1 produce approximately 60.606061/153.846154/315.789474/666.666667 deg/s before the separate cap. These are derived reference values, not additional executed application tests. Add full signed vectors, `r=2`/above-2 cases, cap and denominator-bound cases before claiming this family supported. Actual fields and Betaflight fields have different meanings and source constraints; importing one as the other is a visible error.

Support is exact-version scoped: an unknown firmware version/type receives a clear unsupported or explicitly partial import result. A rates-only import does not copy receiver smoothing, camera-angle roll/yaw mixing, PID/feedforward, throttle law, motor limits or ESC behavior. Preserve raw import bytes, selected rate profile and a report of accepted/refused/ignored settings. Do not advertise firmware flight-feel equivalence from curve agreement.

## 2. Controller and bounded allocation (DR-07, DR-21)

Reference mode semantics are documented by [Betaflight Modes](https://betaflight.com/docs/wiki/guides/current/Modes), [Mixer](https://betaflight.com/docs/wiki/guides/current/Mixer) and [Rate Calculator](https://betaflight.com/docs/wiki/guides/current/Rate-Calculator), all accessed 2026-11-11. Those documentation pages are mutable, so preserve a dated capture at implementation intake. Acro commands body angular rate and zero stick targets zero angular rate. Angle uses roll/pitch attitude-to-rate control; yaw remains a rate command. Airmode is a mixer/authority policy while armed, not an arming mechanism, and may increase collective above the requested low throttle. These semantics do not establish Betaflight PID or filtering equivalence.

A reproducible first controller can use `e = omega_target - omega_measured` in FRD rad/s and a per-axis torque request `tau_req = Kp*e + I - Kd*filtered(d omega_measured/dt) + FF`, with explicit SI units, sample period, initial filter state, FF law and output limits. Derivative on measurement avoids a setpoint derivative kick; any FF based on a setpoint derivative is a separate declared path. Pin all state and scheduling into the checkpoint and update once per controller sample, never once per RK stage. Use an ideal simulated gyro/attitude initially only if that sensor idealization is explicit. Angle may form a bounded desired tilt, compute a sign-consistent body-frame orientation error, cap the generated roll/pitch rate targets and leave yaw under the Acro rate curve. Define behavior at inverted/near-vertical attitude and shortest-rotation tie cases; avoid unqualified Euler-angle differencing through its singularity. Verify mode switches, arbitrary starting attitude and no yaw setpoint step on a level command. This is a proposed simulator controller, not a source-derived Betaflight implementation.

For fixed parallel rotors and the existing rotor order, a **steady quadratic-law allocation model** is:

```text
f_i = T_i = k_T,i * Omega_i^2 >= 0 ; k_T,i > 0
Q_i = k_Q,i * Omega_i^2 ; kappa_i = k_Q,i/k_T,i   [m]
# This finite coefficient ratio also applies at Omega_i = 0.
# Variable curves require a declared finite limit or explicit zero-thrust branch.
r_i = (x_i, y_i, 0)  [m] ; s_i in {-1,+1}
w = [sum(T), tau_roll, tau_pitch, tau_yaw]^T
B[:,i] = [1, -y_i, x_i, s_i*kappa_i]^T
w ≈ B f
```

This uses the plan's `a=(0,0,-1)` thrust axis and external aerodynamic yaw convention, and the approximation assumes constant static `Q/T`. At changing RPM the actual yaw torque also contains rotor acceleration; `B f` is an allocation target/prediction, not an instantaneous force sensor or a complete dynamic plant. The motor's feasible thrust range depends on its electrical/prop map and the *common* bus; define inverse mapping and saturation diagnostics. A fixed motor limit is a starting bound, not proof all four simultaneously achieve it under sag.

One deterministic, inspectable baseline is a bounded four-variable least-squares allocator `min ||W(Bf-w_req)||²`, `f_min <= f <= f_max`, with stated row normalizations and weights, rank/conditioning checks, deterministic tie-breaking and an optional defined small penalty for changing motor requests. Enumerating 3^4 = 81 lower/free/upper active sets is a useful **independent reference solver**. A production solver can use a cheaper bounded method only after objective/feasibility/tie parity and cost are demonstrated. Record the requested and allocated wrench, bounds, residual and any motor/pack output limitation. Normalize force and moment rows by declared characteristic scales before weighting, so changing N·m to another unit cannot silently change priorities. Decide and document relative priorities among collective, roll/pitch and yaw, especially at full throttle and low voltage. Weighted objectives permit tradeoffs; they are not mathematically the same as a strict lexicographic priority. Validate the choice against practical maneuvers before freezing it.

**Computed sign oracle:** use four hubs `(-.1,+.1)`, `(+.1,+.1)`, `(-.1,-.1)`, `(+.1,-.1)` m, spins `[-1,+1,+1,-1]`, common `kappa=.01 m`. The target `w=[4,.08,.04,.008]` in N and N·m is exactly produced in the unconstrained static model by `[.5,1.1,1.3,1.1]` N. This checks ordering, axes and all moment signs. It is a synthetic test, not aircraft data.

For intuition and a separate simple airmode test, let normalized additive corrections be `[-.2,-.2,+.2,+.2]`, `u_min=.05`, `u_max=1`, requested collective `.02`. The closest feasible collective shift holding all corrections unchanged is `.25`, yielding `[.05,.05,.45,.45]`. If the correction spread exceeds the available motor range, no collective shift alone works: invoke and test the chosen bounded priority rule. Disarm forces zero drive irrespective of this idle floor; the motor state coasts or brakes under its declared law.

For anti-windup, a transparent candidate is per-axis back calculation, in the same torque units as the allocator:

```text
tau_req,k = P_k + I_k + D_k + FF_k
f_alloc,k = bounded_allocate(tau_req,k, collective_k, bounds_k)
tau_alloc,k = moment_rows(B*f_alloc,k)
I_(k+1) = clamp(I_k + T_s*(Ki*e_k + Kaw*(tau_alloc,k-tau_req,k)), -Imax, Imax)
```

Here `Kaw` has units 1/s when I is torque. `tau_alloc` is the saturation-limited *command* in the same coordinates as `tau_req`, including actual command/bus feasibility limits where those are modeled. Do not use measured instantaneous motor torque as this residual without intentionally designing a tracking anti-windup controller: ordinary motor lag would otherwise look like saturation and change the loop even when no actuator limit binds. Choose nonnegative bounded gains with a stability/response test, and specify integral reset/freeze at disarm, holds, crashes and mode switches. Tests cover each motor/axis saturation, unwind direction, asymmetric bounds, prolonged saturation followed by release, low voltage, yaw sacrifice, arming idle and that the allocator never changes outputs while disarmed. Compare requested vs allocated vs physically produced moments in logs.

## 3. Sampling is a quantitative hypothesis, not a frequency label (DR-09, DR-21)

At 240 Hz, `T_s=4.1666666667 ms`; the Nyquist frequency is 120 Hz. A filter cutoff strictly below Nyquist is only a necessary condition. A continuous-time zero-order hold has frequency response `H(f)=exp(-j*pi*f*T_s)*sin(pi*f*T_s)/(pi*f*T_s)`. These **computed** hold-only effects exclude gyro filtering, ESC/motor delay and numerical integration:

| Hz | Hold phase | Hold magnitude | Extra one-full-tick delay phase |
| --- | --- | --- | --- |
| 20 | −15° | −0.10 dB | −30° |
| 40 | −30° | −0.40 dB | −60° |
| 60 | −45° | −0.91 dB | −90° |
| 80 | −60° | −1.65 dB | −120° |

Thus an added full-tick delay substantially alters a fast loop; do not call it a filter. A zero-order hold has its own frequency response even when the command is applied immediately at the sample. Sensor and controller phase, exact update order, time stamps, possible transport delay, aliasing and closed-loop dynamics must be included in the qualification. The table makes no claim about a real racing quad's bandwidth.

For a simple, explicitly identified low-pass, one possible discrete update is `alpha=1-exp(-2*pi*f_c*T_s)`, `y_k=y_(k-1)+alpha*(x_k-y_(k-1))`. This is an exact pole mapping from a continuous first-order model; its actual discrete −3 dB point is not exactly `f_c`, particularly close to Nyquist. Derivative memory, startup value, signal sampling and reset behavior need tests; never copy an above-Nyquist firmware cutoff and claim equivalence. Other digital filter choices need their own documented coefficients and response.

Run **two independent comparisons**, with the reference model itself refined sufficiently that its results stop moving materially:

1. Plant integration: hold the exact same controller samples and zero-order-held commands at times `k/240`; compare plant integration steps `1/240`, `1/480`, `1/960` s. Separate smooth regimes from stop/contact events. Changing only plant substeps does not create more feedback samples.
2. Closed loop: compare the 240-Hz controller against otherwise equivalent 960-Hz and, if needed, 1920-Hz controllers, on a sufficiently refined plant; 960/1920 are integer multiples of 240 and avoid phase drift. At each physical sample obtain a new state; never recompute faster on stale feedback. Use the same continuous command-tape timing and initial conditions; specify how input edges align and test phase offsets. Compare roll/pitch/yaw step and doublet responses, oscillation decay, frequency response/phase in the selected maneuver band, saturation/recovery and low-voltage cases. Predeclare rise/settling/overshoot bands and what counts as non-settling. The active plan's 15%/20%/5-percentage-point screen is a proposed engineering threshold, not empirical validation.

If the 240-Hz loop fails, stop promotion and collaborate with the shared-kernel owner on a generic transactional sampled-event scheduler. Do not simulate a 960-Hz controller by repeatedly using the same 240-Hz sensor snapshot and do not perform controller updates from rendering callbacks. The 39.1 ms first-order response reported for Agilicious is a load-cell fit on a particular setup, not a universal motor constant: [Foehn et al., 2022](https://rpg.ifi.uzh.ch/docs/ScienceRobotics22_Foehn.pdf), accessed 2026-11-11. Do not add it again as a separate generic latency.

## 4. Coupled body/rotor momentum and work (DR-06)

Assumptions: fixed body-axis bearings, axisymmetric spinning assemblies, `I_L` the total locked-rotor inertia about the CG, and each rotor's relative spin coordinate `Omega_i >= 0` about `s_i*a_i`; `s_i=+1` means CCW viewed along the thrust axis from above. Let `h=Σ s_i J_i Omega_i a_i`. All propulsive aerodynamics, thrust-arm effects and contacts contribute to external moment `tau_ext` about the CG; include the air's shaft reaction `−s_i Q_aero,i a_i` **once** in that external moment. `Q_motor` is an internal motor-on-rotor torque, positive in the rotor's nominal spin direction, and `Q_aero` opposes that relative rotation for the simple motoring branch. Let `alpha = dot(omega_body)`.

```text
I_L alpha = tau_ext - omega × (I_L omega + h) - Σ s_i J_i dot(Omega_i) a_i
J_i dot(Omega_i) = Q_motor,i - Q_aero,i - s_i J_i (a_i · alpha)
```

Substitution gives a small deterministic 3×3 stage solve:

```text
I_effective = I_L - Σ J_i a_i a_i^T
I_effective alpha = tau_ext - omega × (I_L omega + h)
                    - Σ s_i (Q_motor,i - Q_aero,i) a_i
dot(Omega_i) = (Q_motor,i - Q_aero,i)/J_i - s_i (a_i · alpha)
```

Prove `I_effective` positive definite for accepted data. For parallel body-fixed axes, it may be prepared once. Use the pure stage evaluator to solve for `alpha` and rotor derivatives together; supply the existing rigid-body evaluator a corrected moment `tau_ext - Σ s_i J_i dot(Omega_i) a_i` so its `I_L^-1 [moment-omega×(I_L*omega+h)]` reproduces the same alpha. This can be vehicle-side math; the shared kernel needs no drone-specific branch. Preserve stage-pure inputs and checkpointed sampled output. Do not stack the acceleration moment once in rotor loads and again in the rigid-body solver. The simple first-order lab fixture is a separately identified approximation; its specified speed derivative does not automatically enforce this motor torque equation.

`Omega_i` here is the rotor speed **relative to the body**, as a shaft encoder or motor model would use. Against a nonrotating ambient-fluid reference, the rotor's absolute axial spin is `Omega_abs,i = Omega_i + s_i*(a_i · omega_body)`. A propeller aerodynamic law that substitutes relative RPM alone therefore neglects body rotation; make that an explicit small-body-rate approximation, or evaluate the law at a well-defined absolute/air-relative rotor speed. A static bench with stationary body cannot distinguish these conventions. Define and test the law's valid sign/domain near rotor stop, rather than silently squaring an invalid reversed absolute spin; a complete blade-level flow model would also need transverse body rotation and local air motion.

The rotational kinetic energy implied by the convention is:

```text
E_rot = 0.5*omega^T I_L omega + omega · h + 0.5*Σ J_i Omega_i^2
```

For motor work use the **relative** shaft speed: `P_motor_mech=Σ Q_motor,i Omega_i`. Drag and applied external power must be accounted consistently at their actual points of application and against fluid/world velocity; wind can transfer energy. Motor power must not be counted again as an external body torque. Comparing only the signs of yaw is inadequate.

**Computed motor-work/conservation oracle:** one rotor, `a=(0,0,-1)`, `s=+1`, `I_L,zz=.002 kg m²`, `J=.00001 kg m²`, `Omega=1000 rad/s`, `omega=0`, `Q_motor=.1 N m`, `Q_aero=0`, no other external torque. At that instant, `alpha_z=+50.2512562814 rad/s²`, `dot(Omega)=10050.2512563 rad/s²`, and `I_L,zz*alpha_z - J*dot(Omega)=0`. The initial rotational-energy derivative is exactly `Q_motor*Omega=100 W`: omitting `omega·h` yields a spurious extra 0.5025 W. Test angular momentum in the inertial frame over time, including nonzero roll/pitch/yaw and asymmetric rotors, and test stage solutions against this independent oracle. A test using the same algebra on both sides is insufficient.

Current source behavior at the frozen commit: `multirotor/rotor.gd` adds aerodynamic yaw and `spin*J*omega_dot` and `rigid_body.gd` adds gyroscopic momentum; the fixture computes `omega_dot` from a first-order speed law before body acceleration is known. That supports the existing sign fixture but does not by itself demonstrate the coupled electromechanical/work identities above. Retain the lab law under its existing identity until a separately identified law passes the stronger tests.

## 5. Four ESC loads on one pack (DR-05)

The checked [`electric_motor.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/electric_motor.gd) and [`electric_supply.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/electric_supply.gd) implement a one-quadrant averaged DC equivalent and a **single-load** analytical supply. The repository also has a richer [BAT pack model](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/battery/pack_ecm.gd), again with a single-motor coupling. The four-motor adapter must share one bus solve rather than call a single-load pack solve four times. The preferred initial product law is an explicitly identified extension of the simpler EL model below; BAT polarization/thermal/supervisor adaptation is a separate state-layout decision, not silently absent existing functionality.

```text
E_i = Omega_i / Kvi_rad_per_s_per_V   ;   Kti = 1/Kvi_rad_per_s_per_V
I_i = max(0, (d_i*Vbus-E_i)/R_i)       for d_i > 0 and enabled, else 0
Ipack = Iaux + Σ d_i*I_i
Vbus = Voc(SOC) - Rp*Ipack
dSOC/dt = -Ipack/(3600*C_Ah)
```

`I_i` is an equivalent motor-side current, not physical phase RMS or automatically the measured pack current. Here `d_i` is an **effective bridge duty** in this model, not a promise that a DShot number or throttle percentage equals duty. Current and battery accounting assume a lossless ideal bridge; to model ESC loss, state its voltage/current and dissipated-power law separately. The current implementation has shaft loss torque `Kt*I0` and handles stopped/coast branches; preserve its energy and stop conventions. The form does not model motor phase inductance, timing, ESC current limit, regeneration, or dynamic battery polarization.

At every RK stage identify the active set `S={i | enabled && d_i*Vbus > E_i}` and solve:

```text
Vbus = (Voc - Rp*Iaux + Rp*Σ_(i in S) d_i*E_i/R_i)
       / (1 + Rp*Σ_(i in S) d_i^2/R_i)
```

Check active-set inequalities against that same Vbus, finite positive bus, individual current domain and a fixed equality convention. Four loads permit exhaustive 16-set or sorted-threshold solving; use a deterministic numerical tie policy and bounded work. Stopped disabled loads have no motor current while a declared pack-side auxiliary current may remain. Treat simultaneous rotor stop and depleted-pack events through the existing generic event/whole-tick protocol without evaluating invalid negative-speed stages; checkpoint the pack exactly once.

Define chemical-energy reference consistently with the charge model, `Echem(z)=3600*C_Ah*integral_0^z Voc(q)dq`, yielding `-dEchem/dt=Voc*Ipack`. Then `Voc*Ipack = Vbus*Ipack + Rp*Ipack^2`, and `Vbus*Ipack = Vbus*Iaux + Σ Vbus*d_i*I_i`; each motor bridge input equals electromagnetic conversion plus copper loss under the stated equivalent. Rotor/airframe mechanical work and friction/prop losses complete the accounting. Pack **terminal** energy alone is not chemical energy and pack I²R loss is not ESC heat. Integrate state and energy residual over the whole accepted trajectory and report numerical tolerances before viewing results.

**Computed four-load stage oracle** for `Voc=24 V`, `Rp=.05 ohm`, `Iaux=.2 A`, four identical enabled loads `d=.5`, `E=8 V`, `R=.1 ohm`, ideal bridge: `Vbus=21.3266666667 V`, each `I_i=26.6333333333 A`, and `Ipack=53.4666666667 A`. Pack OCV output is `1283.2 W`, `I²R` loss `142.9342222 W`, terminal power `1140.2657778 W`. Auxiliary consumes `4.2653333 W`; each bridge receives `284.0001111 W`, split into `213.0666667 W` electromagnetic conversion plus `70.9334444 W` copper loss before modeled shaft loss. One load under these same assumptions gives `Vbus=23.1022222222 V`, so solving four independent one-load supplies is observably wrong. Also test mixed active/coast states, zero duty, unequal motor R/KV, zero Rp, SOC boundary, changing load and branch-threshold continuity. These values are invented test parameters, not an identified battery.

## 6. Real datasets and what they do—and do not—identify (DR-02, DR-05, DR-38/40)

The manufacturer's [F50 2150 KV/F5146 static table](https://www.ligpower.com/product/f50-5inch-racing-drone-motor.html), accessed 2026-11-11, is a useful comparison source because it reports RPM and rounded torque as well as thrust and electrical input:

| Reported command | Voltage | Current | RPM | Thrust | Displayed torque |
| --- | --- | --- | --- | --- | --- |
| 50% | 23.88 V | 10.97 A | 22,194 | 824 g | 0.08 N·m |
| 100% | 23.28 V | 52.52 A | 35,042 | 2,136 g | 0.22 N·m |

Using standard gravity, these thrusts are 8.0806796 and 20.9470044 N; the computed `T/Omega²` values are approximately `1.4959583e-6` and `1.5555605e-6`. The displayed torque is coarse, and the low-command displayed zero is not proof of zero shaft torque. Treat the table as vendor-reported, reference-only static evidence, without independent instrumentation/uncertainty qualification. It cannot identify rotor inertia, transient/braking response, installed drag or propwash. Capture source bytes/hash and rights at intake.

The separate official [F5146 specification](https://www.t-hobby.com/products/t-motor-f5146-drone-propeller) states **5.1-inch** nominal diameter (129.54 mm) and 4.6-inch pitch, and recommends motors below 2100 KV. That recommendation conflicts with the 2150 KV tested pairing. Resolve the exact assembly and this contradiction before product selection. This is a 5-inch-class research prior, not a measured 5.0-inch/127-mm propeller or a validated product build.

The authors' [UIUC Propeller Database Volume 2, version 1](https://m-selig.ae.illinois.edu/props/volume-2/propDB-volume-2.html) is a primary source for thrust/power coefficients against advance ratio and static RPM sweeps; its notes say power coefficient derives from measured torque and speed, and use true, sometimes non-nominal diameters. Its small 5-inch-class examples are not automatically this racing prop's high-RPM envelope. The [NeuroBEM dataset README](https://rpg.ifi.uzh.ch/neuro_bem/Readme.html) describes 400-Hz processed kinematics, individual motor speeds/derivatives and voltage on its own research vehicle, body FLU and world z-up. It is a separate flight-reconstruction dataset, not a simultaneous validation of the F50 assembly. The [Agilicious paper](https://rpg.ifi.uzh.ch/docs/ScienceRobotics22_Foehn.pdf) gives an independently researched full-system example, again a separate aircraft/configuration. All sources accessed 2026-11-11; retain publisher version, dates, file hashes, field definitions, units and redistribution decisions before bundling.

For NeuroBEM use `C_FRD_FLU=diag(1,-1,-1)` on body vectors; use the explicitly established dataset world-to-NED transform on world vectors and both left/right basis transforms on attitude. A world frame described only as z-up does **not** identify its north/east axes; do not assume them. Split by complete flight/maneuver segments before fitting to avoid adjacent-sample leakage; record filters, timing offsets, discarded gaps, mass/inertia assumptions and independent ground truth. Reconstructed force/torque have correlated measurement and numerical-differentiation uncertainties. Freeze candidate/prior parameters and report residuals per speed/attitude/voltage/descent regime; a software match or another aircraft's flight data cannot validate the product build.

## 7. Remaining decisions and stop conditions

- Freeze exact build, 5.0-vs-5.1-inch decision, fixed motor/prop identity, inertias, ESC law, pack/OCV/resistance/current limits and source redistribution before calling any assembly identified. The F50 source is useful but incomplete; measured selected-build tests remain DR-40.
- Choose the objective/priority and actual actuator-feasibility policy for control allocation; demonstrate performance and stability under common-bus sag, not just box bounds at a nominal voltage.
- Use acceptance gates before extrapolating 240-Hz behavior, high-speed aerodynamics or an imported rates profile to real firmware. Separate computed, vendor-reported, borrowed, estimated and physically validated evidence.

## 8. Geometry and asset intake already narrowed

### Fixture clearance calculation

For the current square-X fixture, diagonal motor spacing is 152 mm and the adjacent spacing is `152/sqrt(2)=107.4802307404 mm`. With coplanar circular prop envelopes:

| Nominal prop | Diameter | Adjacent signed clearance in the lab fixture | Zero-gap square-X diagonal minimum |
| --- | --- | --- | --- |
| 5.0 inch | 127.00 mm | −19.5197692596 mm | 179.6051224214 mm |
| 5.1 inch | 129.54 mm | −22.0597692596 mm | 183.1972248698 mm |

Negative clearance means overlapping envelopes. The minimum column has **zero** gap and is not a design allowance. For a required coplanar separation margin `g`, the square-X check is `L_diag >= sqrt(2)*(D+g)`; actual non-square/staggered frames need their full geometric check. The runtime fixture's mass/thrust and borrowed estimates do not make this geometry a physical racer. These numbers are included in the executed oracle suite.

### Download-first asset candidate

The OpenRacer repository is now pinned for intake at [`15477b200a569dad9d4107e77fdb7cac5acfffd9`](https://github.com/OpenRacer/OpenRacer/tree/15477b200a569dad9d4107e77fdb7cac5acfffd9). Its [README](https://github.com/OpenRacer/OpenRacer/blob/15477b200a569dad9d4107e77fdb7cac5acfffd9/README.md) identifies the carbon designs as 5-inch unless otherwise specified and provides frame/canopy construction information. The inspected root [LICENSE](https://github.com/OpenRacer/OpenRacer/blob/15477b200a569dad9d4107e77fdb7cac5acfffd9/LICENSE) contains GPL version 3; its Git blob ID is `f288702d2fa16d3cdf0035b15a9fcbc552cd88e7`. This records observed source metadata, not a completed per-file redistribution review.

The pinned `cad/` listing includes Carbon, AnalogPro, AnalogSharpClassic, AnalogSmoothClassic, DjiO3, DjiO4, DjiVista, HDzero_Race2, HDzero_Race3, Fusion360, Accessories and SharkCanopies. Select **one compatible carbon/canopy variant** and all missing motors/props/electronics as an explicit inventory. A frame design is not a complete measured aircraft or a ready-made Godot asset. Do not silently combine differently scaled variants.

Intake must still download the selected source files, record per-file SHA-256 and license/attribution/redistribution decisions, inspect units and actual motor holes/hubs/camera placement, and produce a reproducible CAD-to-GLB conversion. No assembled GLB, exact mass inventory or complete commercial-component license audit is claimed completed in this review.

### Required asset adapter receipt

| Field group | Required evidence |
| --- | --- |
| Source | Original URL/author, immutable commit or release, exact selected filenames and hashes, license text/version, modification and redistribution decisions |
| Conversion | Pinned free converter/Blender/tool versions, arguments, source-unit scale, axis transform, triangulation/material handling, output GLB hash |
| Assembly | One chosen variant; four stable hub/spin mappings; component provenance; missing parts explicitly listed |
| Runtime | Mesh/hull/CG/camera agreement, prop/frame clearances, four independent rotor pivots, stopped/blur states, bounded materials/textures/LOD and native 1080p inspection |

Use the repository's existing asset pipeline and downloaded parts wherever suitable. Conversion/adaptation is legitimate necessary work; a visually plausible procedural substitute cannot establish the selected physical configuration. Physical parameters derive from inventory/measurements, not from material colors or polygon volume without validated material/construction assumptions.

## 9. Choosing the first product law without inventing evidence

The baseline product law is intentionally transparent: fixed-axis quadratic/static prop loads within a declared experimental domain, explicit rotor/body coupling, four motors on one one-quadrant common-bus pack, admitted ground/contact behavior and simulator-owned sampled control. Mark unmeasured motor/drag/inertia parameters as estimates, record uncertainty/sensitivity and qualify software behavior. Do not tune maximum speed, thrust ratio or flight time to a guessed target and label the resulting numbers measured.

For a static coefficient fit, use one named prop/motor/test condition, converted RPM/thrust/torque/voltage consistently, report the selected fitting range and method, and hold out rows or a separate sweep. Preserve displayed precision and source inconsistencies. A torque coefficient cannot be inferred uniquely from thrust alone. Distinguish raw command from effective bridge duty and measured motor-side/pack current. Inverting a static thrust map provides a command target, not guaranteed instantaneous thrust during motor lag or pack sag.

Advanced prop loads add axial/oblique flow, in-plane force/hub moment and an appropriately qualified shared inflow law only when an independent comparison demonstrates benefit. Maintain distinct law IDs and domain checks. A helicopter mean-inflow/VRS law is useful shared research, but it does not itself reproduce multicopter wake interaction or turbulent propwash. Body-rate-relative rotor speed and true air-relative rotation also diverge near stop; the approximation and any reverse-flow/rotation handling must be explicit. Do not add a second ground-effect multiplier or invented shake to disguise missing wake physics.

The physical campaign and held-out acceptance rules in [05](05_VALIDATION_AND_IMPLEMENTATION_BACKLOG.md) close these gaps. Until then, the honest product description is an experimental FPV racer with identified modeling limits.
