# 03 — Propeller aerodynamics, slipstream and propwash

**Status:** research knowledge base, initially observed 2026-10-06; current implementation status reconciled against the project audit dated 2026-10-06. **Serves:** ROADMAP E0b (propwash on the tail), G1 (propeller table ingestion), M5 "swirl and wing-wash", 3D aerobatics (hover, torque roll), P-51 4-blade BEM table ([derive_physics.py](../../../research/p51/p51-05/derive_physics.py)), Extra EX-06 thrust axis. **Read with:** [ROADMAP E0b/G1, plan review #3 item 4](../../../ROADMAP.md), [RESEARCH.md: electric propulsion, APC/UIUC comparison, plan review #3 propwash](../../../RESEARCH.md), [propulsion.gd](../../../app/physics/propulsion.gd), [aero.gd](../../../app/physics/aero.gd), doc 02 (wing aerodynamics) and doc 05 (engine and shaft) in this folder.

## Summary

- **The "≈35× at 5 m/s" claim is correct as ideal momentum theory** and has a closed form: q_wash/q∞ = 1 + T/(A·q∞) = **1 + 8·Ct/(π·J²)**. At the data file's fixed 11,149 rpm (T0 41.25 N at rest, T 38.37 N at 5 m/s), it gives 35.3× at 5 m/s, 8.9× at 10 m/s, 4.2× at 15 m/s and 1.9× at 25 m/s at full throttle; in level flight (thrust = drag) it gives 1.30× at 15 m/s and 1.28× at 25 m/s. E0b's "≤ 1.3× at cruise" holds only for level-flight thrust, not full throttle.
- **It is an upper bound.** Measured jets diffuse: at the Stik's tail (3.7 D behind the disc) Khan's fitted model gives a centreline speed of 1.39·v_i, not 2·v_i, and Selig (FS One) uses ≈1·v_i at hover. On the axis, the realistic ratio at 5 m/s is **12–20×**, not 35×. The stab is also only ≈37 % washed (span), the fin ≈64 % (height).
- **Static (V = 0, full throttle):** ideal far-wake q = T/A = 565 Pa (30.4 m/s). The elevator then gives 1.6–6.3 N·m and the rudder 1.8–7.2 N·m, depending on the wake-speed factor (0.5–1.0 of the ideal). Lifting the nose wheel needs 2.66 N·m, so whether a held Stik can raise its nose at full power is a **cheap owner test** that pins the factor.
- **Swirl is not small.** If all of the torque leaves as angular momentum, the static swirl at the tail is ≈15° (12.6° at 5 m/s, 8.4° at 15 m/s). On a fully washed fin, that much swirl yaws about as hard as full rudder. Real airframes straighten part of it: Selig and Khan model the net roll as ≈40 % of the propeller torque. The swirl factor must be calibrated, and the plans' 2° right thrust on the Extra (≈0.6 N·m at full power) is a design-side hint of its size.
- **P-factor and propeller normal force are small on the .60s.** A blade-element estimate for a 12×6 at 11,000 rpm, 15 m/s and α 10° gives 0.11 N·m of left yaw and 0.30 N of normal force (≈1.5 % of full rudder). For the P-51's 4-blade 26×12 at 5,751 rpm it gives 2.3 N·m and 3.0 N. **Near hover, the jet ("ram drag") normal force dominates**: ṁ·V_cross ≈ 1.36 N per m/s of crossflow for the 12×6, about 18× the blade-element value. It is what damps hover drift.
- **The wash lag is 41–67 ms (10–16 ticks)**, much shorter than the 0.25 s rpm lag, so it matters only with a fast shaft model. The hover damping it causes is already captured geometrically once the wash is added before `v + ω×r` (Selig eq. 24).
- **Propeller data:** the Stik's table is the **measured APC Sport 11×6 at ≤ 6,259 rpm, applied to a 12×6 at 11,149 rpm**, i.e. extrapolated in rpm and size. UIUC Vol. 4 has a measured **APC 12×6E** (thin electric, a different blade) up to 7,547 rpm static and 6,044 rpm in the tunnel. Its Ct at J ≈ 0.35 rises 50 % from 3,040 to 6,044 rpm, so rpm (Reynolds) must stay a table dimension. Its zero-thrust J is ≈0.63, against 0.77 in our table.
- **Ingestion traps found in the files:** UIUC run files repeat their last row up to 8 times (`apce_12x6_0635od_6044.txt`), have no rows between J = 0 and J ≈ 0.11–0.33, and give only slightly negative Ct. APC PER3 files are computed by a vortex method (they under-predict Cp by ≈13 % on the 11×6) and block scripted downloads (HTTP 403).
- **E0b2 now places the Stik's hub 0.414176 m ahead of the CG** (`thrust_line_offset` [-0.414176,0,0], aft/right/up). The shaft height is zero in the physics datum. This is derived from estimated visual installation, not measured hardware; axial loads and flight fingerprints are unchanged. [Hub/neutral-tail handoff](../propwash/E0b2/README.md). The historical baseline below used the CG as the thrust point.
- **Current status:** the optional P-51 shaft, thrust-axis, propeller normal-force/P-factor and tail-slipstream implementation is committed (`P51-06`, `P51-12`; see [P-51 plan](../../P51-PLAN.md) and [current source](../../../app/physics/slipstream.gd)). Its generated aircraft data declares the shaft and slipstream. This is experimental P-51 support, not validation of the Stik path: the Stik still has no slipstream data and its idle/dead-stick propeller behavior remains unvalidated. The P-51 wake is currently an idealized top-hat, has no reverse-flow fade or transport lag, and omits the propeller jet-crossflow normal-force term. Shaft rpm advances once per tick outside the RK stages; see [doc 01](01-numerics-architecture-performance.md) and [audit finding T1](../project-audit-2026-10-06/physics.md#t1--the-full-flight-session-is-split-order-time-dependent-rk-stage-loads-are-not-wired-through).

**E0b1 verification (2026-10-07):** the existing production `wake()` passes independent momentum, pressure and continuity checks over 144 positive-thrust cases; the 35.338× / 1.2996× operating points are reproduced. [Evidence and limitations](../propwash/E0b1/README.md). This verifies ideal theory; it does not enable or calibrate Stik propwash.

**E0b3a compatibility (2026-10-07):** the loader now accepts combined wing-downwash and tail-slipstream data. Both free and washed horizontal-tail passes use E0a2's free slope, elevator effectiveness and the same held wing CL. [Tests and model limits](../propwash/E0b3a/README.md). The shared angular downwash is a quasi-steady approximation; Stik data remains unconfigured. E0b3b still owns bounded geometry, smooth edges and reverse-flow fade.

## Original baseline observed at HEAD 69dc9bc (historical)

The following table describes the pre-P-51-extension code at that revision. It remains useful for the Stik's default path, but is not a description of every current aircraft.

| Item | File | State |
| --- | --- | --- |
| Thrust/torque | [propulsion.gd](../../../app/physics/propulsion.gd) | Ct(J), Cp(J) piecewise-linear. J < 0 uses the J = 0 row. Beyond the table, linear extrapolation floored at Ct −0.1 and Cp 0. rpm is a first-order lag (τ 0.25 s) toward a throttle-mapped target. There is no rpm dimension in the tables |
| Thrust line | `propulsion.propeller.thrust_line_offset` = [0,0,0] | Thrust acts at the CG. Hub at x_LE −0.293 m (from `ugly_stik_geometry.gd`: `equipment.prop_z` −0.408 with the wing LE at −0.115) = **0.414 m ahead of the CG** |
| Tail | [aero.gd](../../../app/physics/aero.gd) `_local_loads` | H and V tail are local surfaces in **free-stream** flow `v + ω×r`, used only when the blend weight is > 0. At small angles, `_global_loads` (the borrowed UltraStick25e oracle) carries everything |
| Gyro | [dynamics.gd](../../../app/physics/dynamics.gd) | Rotor angular momentum J_p·ω_p along +x (3.5e-4 kg·m², estimated) |
| Missing from the baseline path | — | Propwash for the Stik, wash lag, windmill/stopped-prop behavior at low rpm, rpm-dependent tables and trace out-of-range flags |

**Baseline consequence for E0b:** propwash added only to `_local_loads` would vanish at small angles (blend 0). At V ≈ 0 with wash, the tail angles become small, so the oracle takes over and the oracle's q∞ is ≈0. Taxi and take-off authority would stay zero. The P-51 extension uses an increment outside the blend; the same principle remains relevant when the Stik path is implemented.

## Current P-51 extension (committed; experimental)

- `app/physics/slipstream.gd` computes a momentum-theory wake, contraction, data-scaled wash and swirl; it intersects the wake with tail pieces and adds the washed-minus-free tail-load increment. The P-51 data opt in; absent data leaves other aircraft unchanged.
- `app/physics/propulsion.gd` supports the optional shaft balance, thrust-axis angles, normal force and P-factor. The P-51 generated JSON declares those fields and the slipstream geometry.
- The session still advances shaft rpm in `_pre_step` from the current body velocity, without wind, and holds it across the rigid-body RK stages. The current full-session refinement probe therefore shows first-order convergence. The `−dh/dt` rotor-acceleration reaction is still absent. These are integration/fidelity follow-ups; G2's target is specified in [doc 05](05-propulsion-engines-motors.md).
- Do not transfer the P-51 implementation's status to the Stik: no current Stik JSON opts into slipstream, and the owner nose-lift/taxi checks remain open.

## Theory and models

### Momentum theory (actuator disc; McCormick ch. 6, Glauert)

With axial inflow u, disc area A = πR², thrust T and density ρ:

```
v_i   = ½(−u + √(u² + 2T/(ρA)))          induced velocity at the disc
V_far = u + 2v_i = √(u² + 2T/(ρA))        far wake (fully contracted)
r_far = R·√((u+v_i)/(u+2v_i))             → R/√2 = 0.707R at u = 0
q_far = q∞ + T/A                          (total-pressure jump = disc loading)
q_far/q∞ = 1 + T/(A·q∞) = 1 + 8Ct/(πJ²)   (with T = Ct ρn²D⁴, J = u/nD)
Static: v_i = √(T/(2ρA)) = √(2/π)·nD·√Ct = 0.798·nD·√Ct   (Deters eq. 11; Khan eq. 5.3)
Axial development on the axis: V(x) = u + v_i(1 + x/√(R²+x²))  (≈ 1.99 v_i at x = 3.7D)
```

Validity: inviscid, uniform loading, no swirl losses. It is a good near-field model (to the efflux plane, ≈0.5–0.8 D behind the disc). In the far field it overpredicts, because the jet diffuses. It fails in the vortex-ring and turbulent-wake states (u < 0 with T > 0). JSBSim uses the same v_i formula, signed for T or u < 0 ([FGPropeller.cpp](https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/propulsion/FGPropeller.cpp)).

### Verification of plan review #3 item 4 (python, data-file values)

```python
rho,D=1.225,0.3048; A=3.14159265*D*D/4; n=11149/60     # data: max_rpm_static 11149 (derived)
ct=[[0,.113],[.373,.0796],[.414,.0725],[.457,.0633]]   # ct_table head (borrowed, UIUC 11x6)
T=lambda V: interp(ct,V/(n*D))*rho*n*n*D**4            # T(0)=41.25 N
vi=lambda V,T: .5*(-V+(V*V+2*T/(rho*A))**.5)
ratio=lambda V,T: ((V+2*vi(V,T))/V)**2                 # = 1 + T/(A*0.5*rho*V^2)
```

| Case | T (N) | v_i (m/s) | V_far (m/s) | q∞ (Pa) | q_far (Pa) | ratio | r_far/R |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Static, full | 41.25 | 15.19 | 30.38 | 0 | 565 | ∞ | 0.707 |
| 5 m/s, full | 38.37 | 12.36 | 29.72 | 15.3 | 541 | **35.3** | 0.764 |
| 10 m/s, full | 35.48 | 9.95 | 29.90 | 61.2 | 548 | 8.9 | 0.817 |
| 15 m/s, full | 32.59 | 7.95 | 30.89 | 137.8 | 585 | 4.2 | 0.862 |
| 25 m/s, full | 24.33 | 4.60 | 34.20 | 382.8 | 716 | 1.9 | 0.930 |
| 15 m/s, level (T = D) | 3.01 | 1.05 | 17.10 | 137.8 | 179 | **1.30** | 0.969 |
| 25 m/s, level (T = D) | 7.79 | 1.64 | 28.27 | 382.8 | 490 | **1.28** | 0.971 |

Disc loading T/A = 565 N/m². The A = 0.0730 m² is the full disc; the hub/spinner is ignored. Level-flight drag uses the data polar (CD0 0.0434, k 0.0815, CL_minD 0.23, m 2.885 kg). Full-throttle rows keep rpm fixed at 11,149 (no unloading; see "Engine–prop coupling").

**Realistic tail values (Stik, 5 m/s, full throttle), with the wake-speed factor k_w (V_tail = V + k_w·v_i):** k_w 1.0 (Selig hover) → 12.1×; 1.39 (Khan at 3.7 D) → 19.7×; 2.0 (ideal) → 35.3×. The measured efflux is lower than ideal: Khan fits V0 = 1.46·nD·√Ct (a0 1.46 < 1.59) for a 10×4.5. Marine jets give 1.33 (Hamill, via Khan).

### Slipstream structure (measured)

| Fact | Value | Source |
| --- | --- | --- |
| Static wake contracts to the efflux plane, then expands | d0 = 1.528R (0.764D), R0 = 0.74R; zone of flow establishment ends at d0 + 4.25D0 | Khan 2016 (10×4.5 at 5,425 rpm, hot-wire; rms error 12–15 % on other props) |
| Peak velocity migrates inward | peak at ≈75 % R near the disc, 50 % at 0.5–1D, 25 % at 2D, on the axis by 3D | Deters et al. 2015 (static, 5×4.3, 4.2×2) |
| Advancing flow | contracts by 0.5D, then nearly constant width to 3D (furthest measured); profile shape depends on blade planform | Deters et al. 2015 |
| Swirl persists | still present at 3D in advancing flow; measured 8D downstream by others | Deters 2015, citing Pannell & Jones |
| Hub/motor deficit | tractor centreline 3 m/s vs pusher 11 m/s (same thrust, x/D 0.5) | Khan, citing ref. 87 |
| Strip discontinuity | a surface partly in the wash sheds trailing vortices: downwash inside the jet, upwash outside (outboard stall earlier) | Chadha, Pomeroy & Selig 2016 (CFD) |
| Static axial velocity scales with tip speed | u/V_T = √(2Ct/π³) | Deters 2015 eq. 12 |

**Khan's far-field model (static, SI):** for d0 ≤ d_s ≤ d0 + 1.7D0, V_max = V0(1.24 − 0.0765ξ), R_max = R_max,0(1 − 0.1294ξ) and V = V_max·exp(−((r − R_max)/(0.8839R_max,0 + 0.1326(d_s − d0 − R0)))²), with ξ = (d_s − d0)/D0 and R_max,0 = 0.67(R0 − R_hub). Two more bands follow (eqs. 5.18–5.23); the established-flow band is V = V0(0.89 − 0.04ξ)·exp(−(r/(0.241(d_s − d0)))²). For forward flight, Khan feeds Ct(J) into the same static equations. **Applied to the Stik (static, 41 N):** V0 27.8 m/s. At the stab (3.72D) the centreline speed is 21.1 m/s (q 272 Pa = 48 % of T/A) and the jet half-width is ≈0.21 m (Gaussian). ∫q·dy over the stab semispan is 35 Pa·m, against 57 Pa·m for the top-hat momentum jet (**62 %**).

### Swirl

Euler's turbine equation: all shaft torque leaves as angular-momentum flux, Q = ṁ·(V_θ·r)_mean with ṁ = ρA(u + v_i). Under uniform circulation (V_θ ∝ 1/r) at 0.7 r_far:

| Case (Stik 12×6) | Q (N·m) | ṁ (kg/s) | V_θ in the wake (m/s) | Swirl angle at the tail |
| --- | --- | --- | --- | --- |
| Static | 0.834 | 1.36 | 8.1 | 15.0° |
| 5 m/s full | 0.842 | 1.55 | 6.7 | 12.6° |
| 15 m/s full | 0.857 | 2.05 | 4.5 | 8.4° |

These are upper bounds: wing, fuselage and cowl recover part of the swirl (the "40 % of torque" net roll in Selig 2010 and Khan 2016). X-Plane 11.40 tracks swirl as an angle that is constant along the stream tube, set from the propeller's efficiency and drag by energy conservation ([X-Plane dev blog 2019](https://developer.x-plane.com/2019/09/experimental-flight-model-changes-in-x-plane-11-40/)). Direction: a clockwise prop (from behind) coils the wake clockwise. A fin above the axis then sees flow from the left, which yaws the nose **left**. The swirl also gives upwash on the left wing root and downwash on the right, which rolls **right** against the torque reaction (Selig 2010). Inverted, the fin-induced yaw reverses.

### Off-axis propeller loads

- **P-factor (yaw from asymmetric disc loading) and normal force N_p:** Ribner (NACA TR-819, 1945) derived the side-force derivatives. McCormick's closed forms (Selig 2010, eqs. 4–6) use solidity σ, mean section lift and q. JSBSim instead **moves the thrust point** in proportion to the inflow angle (`p_factor` × angle, LGPL source).
- **Blade-element estimate (this study, quasi-steady, uniform Glauert inflow, generic section; derived ±30–50 %):**

| Propeller | V (m/s), α | T (N) | N_p (N, ⟂ shaft, in the lift direction) | P-factor yaw (N·m, left) | Equivalent thrust offset |
| --- | --- | --- | --- | --- | --- |
| 12×6, 2-blade, 11,000 rpm | 10, 10° | 31.4 | 0.18 | 0.080 | 2.5 mm |
| same | 10, 20° | 32.0 | 0.34 | 0.158 | 4.9 mm |
| same | 15, 10° | 25.9 | 0.30 | 0.113 | 4.4 mm |
| same | 25, 10° | 13.4 | 0.58 | 0.157 | 11.8 mm |
| 26×12, 4-blade, 5,751 rpm | 15, 10° | 236.5 | 2.99 | 2.31 | 9.8 mm |
| same | 25, 10° | 137.5 | 5.49 | 3.45 | 25 mm |

  In the committed P-51 table's normalization, k_N = N_p/(ρn²D⁴·α) is approximately **0.02·J** for the 12×6 and **0.035·J** for the 4-blade 26×12 per radian (derived). N_p acts at the hub, ahead of the CG, so it is **destabilizing** in pitch and yaw (it acts like a forward fin). For the Stik at 15 m/s that is 0.30 N × 0.41 m = 0.12 N·m.
- **Jet normal force near hover:** N_j = k_j·ρA·w0·V_cross, with w0 = √(T/2ρA) and k_j ≈ 0.8 (smooth cowl) to ≈1.0 (cruciform foamie), empirical (Selig 2010, eqs. 13–16). For the 12×6, ρAw0 = 1.36 kg/s, so a 2 m/s hover drift gives ≈2.2–2.7 N (≈9 % of the weight), acting as damping. Selig blends the blade term (eq. 4) and the jet term as a weighted sum "not exceeding the maximum of either", washing the blade term out near hover.
- **Propeller rate damping:** M = k_d·(ρ/2)·Ω²R⁵·atan(q/Ω), with k_d ≈ 2π·π·σ (Selig eqs. 10–12). For the 12×6 at hover (σ 0.08–0.12, estimated) at q = 3 rad/s: 0.28–0.42 N·m.
- **Gyroscopic:** already in `dynamics.gd`. Selig's eqs. 8–9 are the same term.

### Operating states and four-quadrant data

| State | Condition (axial u, thrust T) | Model |
| --- | --- | --- |
| Normal working | u ≥ 0, T > 0 | momentum + tables |
| Vortex ring | −2v_i ≲ u < 0, T > 0 (tail slide, steep descent at power) | momentum invalid; Khan holds the J = 0 coefficients (as our `coefficient()` does) and **suppresses the wash at the surfaces when u < −0.2·v_i0** (eq. 5.2); Selig: torque then dominates and gives an uncontrollable left roll |
| Turbulent wake | stronger reverse flow | disc behaves like a bluff plate |
| Windmill brake | u ≫ nD·pitch, T < 0, Q < 0 | momentum valid again (wake expands); Ct < 0 and Cp < 0 |

**Four-quadrant form (marine practice, e.g. Wageningen B-series; textbook, not fetched here):** β = atan2(u, 0.7πnD), C_T* = T/(½ρ(u² + (0.7πnD)²)·πD²/4), and likewise C_Q*. It is defined for every (u, n), including n = 0 (a stopped prop, β = 90°) and u < 0. It converts as **Ct = C_T*·(π/8)(J² + 0.49π²)**. It removes the n → 0 division and the crude J < 0 rule. QPROP (Drela, GPL) handles negative thrust and torque consistently (windmills, MTP design); its formulation document was fetched. A BEM run (as in the P-51 script) can fill the branches; measured UIUC data reach only Ct ≈ −0.007.

### Propeller data sources

| Source | Nature | Coverage relevant here | Caveats |
| --- | --- | --- | --- |
| UIUC Vol. 1 (Brandt 2005; Brandt & Selig 2011) | measured, wind tunnel | APC Sport 7–11 in (11×6 used now); **no 12×6 Sport** | run files are J-sweeps at fixed rpm (≈3,000–7,000); static file is an rpm sweep; corrected data supersede the thesis |
| UIUC Vol. 2 (Deters) | measured | small props, 2009–2015 | Re effects |
| UIUC Vol. 3–4 (Dantsker, 2020–2022) | measured | Vol. 4: 17 APC Thin Electric 12–21 in, incl. **12×6E, 12×8E** | "true measured diameter" used in coefficients; trailing duplicate rows; no data for J < 0.11–0.33 |
| APC PER3_*.dat | **computed** (proprietary vortex/BEM, header `v2022-0915`) | rows per rpm block; columns V(mph), J, Pe, Ct, Cp, PWR(hp), torque (in-lbf), thrust (lbf), PWR(W), torque (N·m), thrust (N), THR/PWR (g/W), Mach, Reyn, FOM (from the GPL MATLAB parser `readAPCperf.m`) | 11×6 check: Ct ±6–14 %, Cp −13 % vs UIUC ([compare_static_propeller.py](../../../research/compare_static_propeller.py)); Cloudflare blocks scripts; no stated redistribution licence |
| BEM (QPROP, JavaProp, our P-51 script) | derived | any J, n, windmill branch | needs blade geometry and section polars; generic sections are ±15–30 % |

**Measured rpm dependence (UIUC 12×6E, fetched 2026-10-06):** static Ct rises from 0.0963 at 2,520 rpm to 0.1055 at 7,547 rpm (+9.5 %). In the tunnel, Ct at J ≈ 0.35 is 0.0440 at 3,040 rpm, 0.0528 at 5,007 and 0.0658 at 6,044 (J 0.36). Zero thrust moves from J 0.60 to 0.63. Cp is nearly flat with J up to ≈0.35 (static 0.0327 → 0.0345 at J 0.33). The Sport 11×6 table (borrowed) shows the same rise: Cp 0.0471 → 0.0489 at J 0.373.

## Engine–prop coupling (propeller side only; the engine side is doc 05)

- At a fixed engine torque, the steady rpm follows n ∝ Cp^(−½). With the Stik table, Cp(J) is flat-to-rising up to J ≈ 0.37 (≈21 m/s at 11,149 rpm), so **in-flight unloading is small in the sport envelope**: about +3 % rpm at 25 m/s (Cp 0.0446) and +14 % at J 0.55. It is larger for high-pitch props (whose zero-thrust J is larger) and for any prop at high speed. RC lore of "unloading by several hundred rpm" was not verified here.
- Without a shaft model, the D5 code keeps rpm at the throttle target. Full-throttle thrust at speed is therefore slightly **under**-predicted at high J, and windmilling at idle is set by the Ct floor. The D8a finding (L/D 5.9 with an idle prop) comes from Ct −0.1 at J ≈ 1.05 (2,800 rpm, 15 m/s): 2.3 N of drag, against 3.0 N of airframe drag. That is plausible for a braking prop but **unvalidated**: G1 needs the BEM braking branch.
- A stopped engine currently gives **zero** propeller load (`rpm < 1`). A stopped two-blade prop has some drag; the four-quadrant form gives it for free.

## Implementation options and trade-offs

| Option | What it gives | Cost (est.) | Risk | Verdict |
| --- | --- | --- | --- | --- |
| A. Constant tail q multiplier η_t(throttle) | static authority | trivial | wrong at every other condition; not passive | reject |
| B. Momentum top-hat + increment on local tail law (committed experimentally for P-51) | authority at V = 0, correct trend with V and T, oracle intact | Current implementation evaluates wash geometry and two surface loads per immersed piece for each load evaluation | overpredicts at hover (k_w = 2); sharp jet edge; swirl calibration | **candidate base for Stik E0b, pending its proof** |
| C. B + Selig k_w(m) (two parameters k_s, k_f, linear in m = V∞/V_disc) | hover ≈1·v_i, cruise → ≈2·v_i | +2 flops | constants from a figure only (unverified values) | candidate; compare against simpler factors and measurements |
| D. B + Khan diffusion (Gaussian, three bands) | measured radial/axial decay, 12–15 % rms | ≈20 flops + exp per piece | fitted on one 10×4.5 (static, tractor) | later (M5) or offline to set k_w |
| E. Per-strip wash on the wing root + swirl roll | power-on lift, torque compensation | split the inner wing strip | interacts with the doc 02 strip layout | M5 |
| F. Vortex/BEM wake at runtime | everything | ≫ budget | — | offline only |
| Tables: Ct, Cp (J) 1-D (now) → (J, rpm) 2-D → four-quadrant (β) | Re effects; windmill/reverse | bilinear lookup ≈ 2× current | data gaps | 2-D in G1; β-form in G1c |

**Recommendation for this repo:**
1. **Keep the increment law** (`F(local tail law, v + Δv_wash) − F(same, v)`) outside the oracle blend. It reproduces the oracle exactly when the wash is zero (engine stopped), works at V = 0 and stays continuous across the blend.
2. **Wake speed:** Δv = k_w(m)·v_i with m = u/(u + v_i) (Selig eq. 19). The P-51 data already use two `wash_factor` endpoints, estimated from the same hover/cruise model. Reuse that meaning for the Stik only after checking its geometry and conditions; do not add a second schema for the same factor without measured evidence.
3. **Radius:** keep momentum contraction with a C¹ taper (cosine over ±15 % of r_s) instead of a hard edge. Clamp the expansion when T < 0.
4. **Reverse flow:** fade the wash to 0 between u = −0.1·v_i0 and −0.2·v_i0 (Khan eq. 5.2). Without it, a tail slide gets a full static wash on the fin.
5. **Lag:** if a wash-transport state is added, define it through H8 and evaluate it consistently with RK-stage time/state when coupled to the airplane. Do not freeze state-dependent wake geometry for a whole tick by default. The wash direction stays body-fixed, so hover damping comes from `v + ω×r` (Selig eq. 24 is reproduced).
6. **Swirl:** the P-51 implementation has a data-scaled `swirl_factor`; estimate its plausible range from torque and wake evidence, then test sensitivity and seek owner observations. The earlier 50%-of-rudder cap is a proposed bound, not a measured universal limit.
7. **Normal force:** the k_N(J) table (blade term) **plus** the jet term k_j·ṁ·V_cross, blended as in Selig. It acts at the **hub**; E0b2 now supplies the geometry-derived point 0.414176 m ahead of the CG. Normal-force modelling remains a later step.
8. **Oracle consistency:** the borrowed UltraStick25e derivatives carry no provenance note in `AeroOpenFlight.xml` (fetched @ b020511). If they were identified in powered cruise, they already contain cruise wash, and the increment double-counts it. Expected size: washed fraction 0.37 × (1.30 − 1) ≈ **+11 % tail effectiveness at 15 m/s level**. Measure it with `linearize.gd` (wash on/off). If it exceeds 10 %, subtract a reference wash: increment relative to the wash at the trim thrust of the identification condition. This is unverified, so decide after measuring.

**Effect on trim:** the model predicts that at level cruise the wash adds ≈+11 % to the stab's force at the trim tail angle, so the trim elevator shifts slightly and Cmα grows slightly. A power change at low speed changes pitch trim; its sign follows the stab's trim lift. The trim solver already calls the shared `Dynamics`. If a transport lag is later added, initialize it at steady state for trim (Δv_lag = Δv).

## Godot / GDScript notes

- Everything stays in `PackedFloat64Array` and `float` (64-bit), with no `Vector3`/`Basis`; `app/test.sh` guards this. The committed implementation follows this representation.
- **Hot path:** current `slipstream.gd` uses lambdas (`area_of.call(...)`) and Dictionaries per piece per load evaluation. These may cost more than flat typed arrays; profile before changing the representation. Keep state-dependent thrust, wake and surface evaluation at RK stages so the result follows stage state. The audit measured 408/370 µs/tick for Stik, 448/457 Extra, 1,256/1,187 P-51 and 412/404 Avanti (trimmed / α=15°) on a shared host under concurrent audit load. Those totals do not isolate slipstream cost; E0b/G1 proofs should report per-aircraft and per-regime deltas.
- Determinism: pure functions of the state + held auxiliary states. `sqrt`/`exp` are deterministic on the same build. Opt-in data keeps the existing golden flights bit-identical. Turning wash on for the Stik is a deliberate physics change that **re-records** the goldens (`tests/record_golden.gd`).
- No wash-transport lag is implemented yet. When added, specify whether it is sampled or continuously coupled under H8 and retain the 30/60/144 fps equivalence check.

## Reusable libraries, tools, code and datasets

| Name | What it gives us | License | Link | How to use here |
| --- | --- | --- | --- | --- |
| UIUC Propeller Data Site, Vol. 1–4 | measured Ct, Cp (J, rpm), static sweeps; 11×6 Sport, 12×6E, 12×8E | none stated (cite) | [propDB](https://m-selig.ae.illinois.edu/props/propDB.html) | G1 source of truth; store sha256 and the true diameter; do not bundle raw files until terms are clear |
| APC PER3 files | computed tables for every APC prop incl. 12×6 Sport, 26×12 | none stated | [APC performance data](https://www.apcprop.com/technical-information/performance-data/) (403 to scripts) | cross-check only; label *manufacturer-predicted* |
| readAPCperf.m | PER3 column layout (fixed 12-char fields, rpm blocks) | GPL-3.0 | [GitHub](https://github.com/dciliberti/read-APC-prop-perfo-data) | read the format; write our own parser (MIT project: don't copy) |
| QPROP/QMIL (Drela) | BEM/vortex analysis incl. windmill, motor coupling | GPL | [QPROP](https://web.mit.edu/drela/Public/web/qprop/) | offline table generator, run as a separate tool; outputs are data |
| JavaProp (Hepperle) | BEM design/analysis | freeware (terms not read) | [JavaProp](https://www.mh-aerotools.de/airfoils/javaprop.htm) | offline cross-check |
| JSBSim FGPropeller | v_i with sign handling; P-factor as thrust-point shift; Ct·Mach and Ct·rpm factor tables | LGPL-2.1+ | [source](https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/propulsion/FGPropeller.cpp) | read only; idea: separate Re correction table indexed by rpm |
| Khan 2016 thesis | slipstream equations and coefficients, 4-state thruster logic | thesis (cite) | [McGill](https://mcgill.scholaris.ca/items/56b70b0e-1f76-48ba-b973-d3b841d659ed) | k_w calibration; reverse-flow cut |
| Selig 2010 | complete RC-sim prop/wash recipe (FS One) | paper (cite) | [PDF](https://m-selig.web.engr.illinois.edu/pubs/Selig-2010-AIAA-2010-7638-PropAeroSim.pdf) | k_w(m), jet normal force, damping, lag |
| PicaSim | momentum wash with lag, swirl, radial falloff | non-commercial (read, don't copy) | via [RESEARCH.md](../../../RESEARCH.md) | design reference |
| YASim | analytic λ-curve propeller; **no fixed-wing propwash** (only rotor downwash in `Model.cpp`) | GPL | [Model.cpp](https://github.com/FlightGear/flightgear/blob/next/src/FDM/YASim/Model.cpp) | nothing to reuse |
| P-51 BEM in repo | induced-velocity BEM, Prandtl tip loss, windmill branch | MIT (ours) | [derive_physics.py](../../../research/p51/p51-05/derive_physics.py) | generalize into a shared offline tool for G1c |

## Parameters and data

| Quantity | Typical value | Unit | Kind | Source |
| --- | --- | --- | --- | --- |
| Stik static thrust | 41.25 | N | derived | Ct0 0.113 (UIUC 11×6 borrowed) at 11,149 rpm (power balance) |
| Disc loading T/A, 12×6 static | 565 | N/m² | derived | above |
| Static v_i / far wake | 15.2 / 30.4 | m/s | derived | momentum |
| T/W: Stik / Extra / P-51 | 1.46 / 1.25 / 1.79 | 1 | derived | data masses 2.885, 3.364, 18.21 kg |
| Hover rpm (Stik, J = 0) | ≈9,230 | rpm | derived | 11,149·√(1/1.46) |
| Prop hub ahead of CG (Stik) | 0.414 | m | derived | geometry `prop_z` vs wing LE, plan CG |
| Prop → stab / fin distance | 1.134 / 1.154 (3.7–3.8 D) | m | derived | data tail positions |
| Washed stab span, static / cruise | 37 % / 52 % | — | derived | r_far 0.108 / 0.148 m, stab 4.1 cm below the axis, semispan 0.273 m |
| Washed fin height, static / cruise | 64 % / 83 % | — | derived | fin root 2.6 cm below the axis, height 0.209 m |
| k_w at hover (tail) | 1.0–1.4 | ×v_i | borrowed | Selig 2010 (FS One); Khan fit at 3.7D |
| k_w in cruise | → <2 | ×v_i | borrowed | Selig 2010 Fig. 5 (values read from a figure: unverified) |
| Efflux coefficient a0 | 1.46 (ideal 1.59) | — | measured (10×4.5) | Khan 2016 |
| Swirl angle at tail, static (upper bound) | 15 | deg | derived | Euler, uniform circulation |
| Net roll with swirl recovery | ≈40 % of torque | — | borrowed | Selig 2010; Khan 2016 |
| Wash lag prop → tail | 41–67 | ms | derived | x/(u + 1.8v_i) |
| Jet normal-force factor k_j | 0.8–1.0 | — | borrowed (empirical) | Selig 2010 |
| k_N (blade normal force) 12×6 / 26×12 4-blade | ≈0.02·J / ≈0.035·J | 1/rad | derived (BEM ±50 %) | this study |
| P-factor equivalent offset | 2–12 (12×6), 10–25 (26×12) | mm | derived | this study |
| Extra right thrust | 2 (≈0.6 N·m at 41 N if the hub is 0.41 m ahead of the CG, assumed as on the Stik) | deg | manual (plans); moment derived | EXTRA-300-PLAN |
| UIUC 12×6E static Ct / Cp | 0.096–0.105 / 0.032–0.034 | — | measured | Vol. 4 `apce_12x6_static_0629od.txt` (sha256 e392a17a…) |
| UIUC 12×6E zero-thrust J | 0.60–0.63 | — | measured | Vol. 4 run files |
| Giant scale (26×12 4-blade) static T | 319 | N | derived (BEM) | P-51 derivation |

## Validation

**Verification (known answers, automated):**
1. `wake(V=0)`: V_far = √(2T/ρA) to 1e-12, r_far = R/√2, q_far = T/A.
2. Ratio at 5 m/s and 41 N data: 35.3 ± 0.1 (k_w = 2). Mutation: drop the factor 2 in 2T/(ρA) → fails.
3. Engine stopped (rpm < 1) → increment exactly zero, goldens bit-identical. Wash data absent → bit-identical.
4. V = 0, full throttle, full up elevator → nose-up My > 0; full right rudder → nose-right Mz > 0. Mutation: flip the increment sign → fails.
5. Swirl sign: CW prop, V = 0, controls neutral → left yaw and right roll from the wash. Inverted → the fin yaw reverses.
6. Reverse flow u = −0.3·v_i0 → no wash at the tail.
7. Lag: throttle step at V = 0 → tail moment reaches 63 % at τ ± 1 tick; identical at 30/60/144 fps.
8. Linearization at 15 m/s level with wash on: Cmα, Cmq, Cnβ, Cnr within +12 % of the oracle (the double-count bound); the modes test stays in its bands.
9. G1 ingestion: every file row is reproduced exactly at its knots; duplicate rows are removed; out-of-range queries raise counters.

**Independent validation (real RC behaviour; owner and data):**
- **Static thrust and rpm:** tachometer (or a phone audio spectrum: blade-pass frequency = 2·rpm/60) and a luggage scale on the Stik's .61 with the 12×6. The data's 11,149 rpm and 41 N (4.2 kgf) are derived, not measured. RC-community static numbers were **not found in this pass** (search budget exhausted): open.
- **Nose-lift test (tricycle Stik):** helper holds the wingtips, full throttle, full up elevator. If the nose wheel lifts, the tail moment is > 2.66 N·m, which needs k_w ≳ 1.3 (top-hat) or more with diffusion. Record a video.
- **Taxi steering:** turning radius at idle vs a throttle blip, on mown grass (E3 surfaces). The rudder in wash plus the nose wheel are both modelled; with the nose wheel lifted (taildragger P-51), only the rudder is.
- **Take-off swing:** required right rudder at full power at 5–10 m/s (pilot rating). Use it to bound `swirl_factor`.
- **Hover (Extra, 3D-style):** throttle setting to hold a hover; torque roll rate with neutral aileron. Selig/Khan: the net roll is ≈40 % of the torque.
- **Datasets:** Khan's slipstream profiles (thesis figures 5.8–5.12: digitize), Deters 2015 (x/D 0.5–3), UIUC 12×6E runs (G1), and the P-51 BEM vs DA-120 static numbers (the 31 kg for a 28×10 at 6,550 rpm is a forum snippet only).

## Pitfalls and risks

1. **Wash added inside the oracle blend does nothing at small angles.** The committed P-51 code adds an increment outside the blend; preserve that property in the Stik implementation.
2. **Ideal k_w = 2 at hover gives too much authority** (≈2–4× the moment). Mitigation: k_w(m) with k_s ≈ 1.0–1.4; owner nose-lift test.
3. **Swirl overpowers the rudder** with the ideal swirl and a fully washed fin. Mitigation: bounded `swirl_factor`, evidence-based bound in a test.
4. **Double-counting the cruise wash** in the borrowed derivatives. Mitigation: measure with linearize; reference-wash subtraction if > 10 %.
5. **Tail slides and vortex ring:** a static wash in reverse flow gives phantom authority. Mitigation: Khan's cut-off with a smooth fade.
6. **Hard jet edge → C⁰ loads**, which add stiffness and chatter as the wake moves across the fin in yaw oscillations. Mitigation: cosine taper.
7. **Extrapolation in rpm:** the tables are measured at ≤ 6,259 rpm, used at 11,149. The Re trend (+9.5 % static Ct over the measured range) suggests the high-rpm Ct is ≥ the table. Mitigation: a 2-D table with the rpm range flagged; the highest-rpm curve is held beyond its range and logged.
8. **Trailing duplicate rows and gaps in UIUC files** break monotonic-J interpolation. Mitigation: loader de-duplication and a strict monotonicity check, with a test using the real file.
9. **Windmill drag from the Ct floor (−0.1)** drives the glide (L/D 8.5 → 5.9). Mitigation: BEM braking branch, β-form tables, a glide test with a measured idle rpm.
10. **Applying Stik normal force at the CG** would lose its destabilizing moment. E0b2 has corrected the hub datum; future normal-force work must use it.
11. **Cost over budget** (24 extra surface evaluations per tick). Mitigation: per-tick wake geometry in `pre_step`, flat arrays, a bench in the proof.
12. **P-51 and main-line work share `propulsion.gd`/`aero.gd`.** The P-51 extension is committed and registered; keep Stik E0b/G1/G2 changes coordinated with the physics owners and add separate proofs for the Stik path.

## Proposed roadmap steps

| Proposed ID | Step | Proof | Depends on |
| --- | --- | --- | --- |
| E0b1 | Verify the committed `wake()` implementation and generalize it for the Stik (momentum, contraction, ratio closed form) | Tests 1–2 above; mutation fails | — |
| E0b2 | Geometry-derived Stik hub from the estimated visual installation; neutral tail footprints | Current completion/proof is in [ROADMAP](../../../ROADMAP.md) and the [E0b2 report](../propwash/E0b2/README.md) | E0b1 |
| E0b3 | Implement and validate the tail increment for the Stik, using the committed P-51 path as a reference; opt-in per aircraft, with C¹ jet edge and reverse-flow fade | Tests 3–6; per-aircraft µs/tick delta reported | E0b2 |
| E0b4 | Validate or adapt the existing two-endpoint `wash_factor` for the Stik using Khan/Selig; opt in only for that aircraft | Static tail centreline 1.0–1.4·v_i; linearize at 15 m/s within +12 % (test 8) | E0b3 |
| E0b5 | Add wash-transport state under H8; choose sampled or continuous integration from its coupling and measured lag model | Transport-delay and frame-rate tests; no first-order split in the coupled path | E0b3, H8 |
| E0b6 | Represent swirl using torque/wake-informed parameters; retain explicit uncertainty and sensitivity | Correct sign and bounded response; compare against theory and observations without imposing a universal 50% rudder cap | E0b4 |
| E0b7 | Owner field checks: nose-lift, taxi blip, take-off swing, static rpm/thrust | Video + numbers in a research note; label observations as measured behavior and keep fitted model parameters labeled fitted/estimated | E0b4–6, owner |
| G1a | Table schema Ct, Cp (J, rpm) with per-run provenance (file, sha256, true D, kind) | Loader reproduces every file row at its knot; duplicate rows removed (UIUC 12×6E file) | — |
| G1b | Out-of-range flags (J gap, J > max, rpm outside) in the trace | Counters fire on crafted queries; zero in a normal golden flight log except the known rpm extrapolation | G1a |
| G1c | Shared offline BEM tool (from the P-51 script) → four-quadrant β tables; Stik 12×6 from APC geometry | Within ±10 % Ct, ±15 % Cp of UIUC 11×6 and 12×6E at matched rpm; windmill branch present | G1a |
| G1d | Windmill/stopped-prop drag from G1c | Idle glide L/D vs the owner's dead-stick observation; stopped prop ≠ 0 drag | G1c, G2 |
| G1e | Propeller normal force + P-factor (blade k_N(J) + jet term), at the hub | Sign tests; magnitudes within ±30 % of this note's BEM table; hover drift damping test | G1c, E0b2 |
| M5-prop-1 | Wing-root wash (inner strip split) + swirl roll recovery | Net static roll ≈ 40 % of torque (±15 %); oracle unchanged at zero wash | E0b6, doc 02 strips |
| M5-prop-2 | 3D hover: torque roll, hover damping, VRS in tail slides | Hover held by a scripted controller at T/W ≥ 1; tail-slide trace shows the wash cut-off | G1e, M5-prop-1 |
| M5-prop-3 | Khan diffusion profile (Gaussian bands) replacing the top-hat | Reproduces Khan's 10×4.5 profiles within 15 % rms | E0b4 |

## Decisions to take now

| Decision | Why now | Recommendation |
| --- | --- | --- |
| Increment law outside the oracle blend | Determines where E0b lives; inside the blend it is inert at small angles | **Yes**; the committed P-51 code demonstrates the pattern |
| Wake-speed data for the Stik | The P-51 schema already has two `wash_factor` endpoints; avoid duplicate fields | Reuse those endpoints only if the same physical definition fits the Stik; keep them estimated until measured |
| Hub position for the Stik | E0b2 now derives and cross-checks it, preserving the existing field meaning | Use that point for future wash/normal-force work; see the [E0b2 report](../propwash/E0b2/README.md) |
| Table dimensionality | UIUC data show strong rpm dependence; the Stik runs far beyond the measured rpm | **(J, rpm) 2-D in G1a**, with a β-form path for G1c |
| Opt-in until owner validation | Keeps the Stik goldens and handling stable for Gate 2 | **Opt-in**; Stik switches on at E0b7 with re-recorded goldens |
| Ownership of the committed P-51 implementation | P-51 and Stik work share physics files | **P-51 track owns its data/model; coordinate shared-code changes with the physics line.** E0b3 validates the Stik adaptation rather than re-landing P-51 code |

## Sources

1. Selig, M. S., "Modeling Propeller Aerodynamics and Slipstream Effects on Small UAVs in Realtime," AIAA 2010-7938 (file name 7638), 2010. https://m-selig.web.engr.illinois.edu/pubs/Selig-2010-AIAA-2010-7638-PropAeroSim.pdf — fetched (full text).
2. Selig, M. S., "Modeling Full-Envelope Aerodynamics of Small UAVs in Realtime," AIAA 2010-7635. https://m-selig.web.engr.illinois.edu/pubs/Selig-2010-AIAA-2010-7635-FullEnvelopeAeroSim.pdf — search result only.
3. Selig, M. S., "Real-Time Flight Simulation of Highly Maneuverable Unmanned Aerial Vehicles," J. Aircraft 51(6), 2014. https://m-selig.web.engr.illinois.edu/pubs/Selig-2014-JofAC-FlightSim-FINAL.pdf — search result only (summarized in RESEARCH.md).
4. Khan, W., "Dynamics Modeling of Agile Fixed-Wing Unmanned Aerial Vehicles," PhD thesis, McGill, 2016. https://mcgill.scholaris.ca/items/56b70b0e-1f76-48ba-b973-d3b841d659ed — fetched (ch. 4–5).
5. Khan, W., Nahon, M., "Development and Validation of a Propeller Slipstream Model for Unmanned Aerial Vehicles," J. Aircraft 52(6):1985–1994, 2015, doi:10.2514/1.C033118 — search result only.
6. Deters, R. W., Ananda, G. K., Selig, M. S., "Slipstream Measurements of Small-Scale Propellers at Low Reynolds Numbers," AIAA 2015-2265. https://m-selig.ae.illinois.edu/pubs/DetersAnandaSelig-2015-AIAA-2015-2265-LRN-PropSlipstream.pdf — fetched.
7. Chadha, S. A., Pomeroy, B. W., Selig, M. S., "Computational Study of a Lifting Surface in Propeller Slipstreams," AIAA 2016-3132. https://m-selig.web.engr.illinois.edu/pubs/ChadhaPomeroySelig-2016-AIAA-Paper-2016-3132-LiftingSurfaces-in-PropSlipstreams.pdf — fetched (abstract).
8. Ananda, G. K., Deters, R. W., Selig, M. S., "Propeller-Induced Flow Effects on a Low-Reynolds-Number Wing," AIAA J., 2018, doi:10.2514/1.J056667 — via RESEARCH.md (fetched there).
9. UIUC Propeller Data Site, main page. https://m-selig.ae.illinois.edu/props/propDB.html — fetched.
10. UIUC Propeller Data Site, Volume 1 (Brandt 2005 MS thesis; corrected data). https://m-selig.ae.illinois.edu/props/volume-1/propDB-volume-1.html — fetched.
11. UIUC Propeller Data Site, Volume 4 (Dantsker), incl. `apce_12x6_static_0629od.txt`, `apce_12x6_0630od_3040.txt`, `apce_12x6_0632od_5007.txt`, `apce_12x6_0635od_6044.txt`. https://m-selig.ae.illinois.edu/props/volume-4/propDB-volume-4.html — fetched (data files downloaded, sha256 prefixes e392a17a, 9c4a5f79, ceca8efe, 7e969b70).
12. Brandt, J. B., Selig, M. S., "Propeller Performance Data at Low Reynolds Numbers," AIAA 2011-1255 — cited on the UIUC site; not fetched.
13. APC Propellers, "Performance Data" (method: proprietary vortex-based analysis). https://www.apcprop.com/technical-information/performance-data/ — HTTP 403 now; inspected 2026-10-05 per RESEARCH.md.
14. Ciliberti, D., read-APC-prop-perfo-data (MATLAB, GPL-3.0). https://github.com/dciliberti/read-APC-prop-perfo-data — fetched (format, licence).
15. Drela, M., "QPROP Formulation," MIT, 2006. https://web.mit.edu/drela/Public/web/qprop/qprop_theory.pdf — fetched.
16. Drela, M., QPROP/QMIL project page (GPL). https://web.mit.edu/drela/Public/web/qprop/ — via RESEARCH.md.
17. Hepperle, M., JavaProp. https://www.mh-aerotools.de/airfoils/javaprop.htm — fetched (frame page only; terms not read).
18. JSBSim, `FGPropeller.cpp` (LGPL). https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/propulsion/FGPropeller.cpp — fetched.
19. JSBSim class reference, FGPropeller. https://jsbsim.sourceforge.net/JSBSim/classJSBSim_1_1FGPropeller.html — search result only.
20. FlightGear YASim `Model.cpp`, `Propeller.cpp` (GPL). https://github.com/FlightGear/flightgear/blob/next/src/FDM/YASim/Model.cpp — fetched (raw).
21. Laminar Research, "Experimental flight model changes in X-Plane 11.40," 2019. https://developer.x-plane.com/2019/09/experimental-flight-model-changes-in-x-plane-11-40/ — fetched.
22. Laminar Research, "X-Plane 11 propeller modeling," 2017. https://developer.x-plane.com/2017/01/x-plane-11-propeller-modeling/ — search result only.
23. Ribner, H. S., "Formulas for Propellers in Yaw and Charts of the Side-Force Derivative," NACA TR-819, 1945. https://ntrs.nasa.gov/citations/19930091896 — fetched (record).
24. Leng, Y., Jardin, T., Moschetta, J.-M., et al., "Experimental Analysis of Propeller Forces and Moments at High Angle of Incidence," HAL hal-01979061. https://hal.archives-ouvertes.fr/hal-01979061 — search result only (page blocked).
25. McCormick, B. W., *Aerodynamics, Aeronautics, and Flight Mechanics*, 2nd ed., Wiley, 1995 (ch. 6 momentum/propeller; normal force and P-factor eqs. as quoted by source 1) — not fetched.
26. Phillips, W. F., *Mechanics of Flight*, 2nd ed., Wiley, 2010 (propeller chapter) — not fetched.
27. Veldhuis, L. L. M., "Propeller Wing Aerodynamic Interference," PhD thesis, TU Delft, 2005 (contraction within a few diameters; cited by source 1) — not fetched.
28. UASLab OpenFlightSim, UltraStick25e `AeroOpenFlight.xml` @ b020511 (MIT). https://github.com/UASLab/OpenFlightSim/blob/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/aircraft/UltraStick25e/AeroOpenFlight.xml — fetched (no provenance note in the file).
29. Ron Jensen, JSBSim propeller NaN fix for induced velocity (FlightGear mirror commit). https://git.nayala.duckdns.org/fly/flightgear/commit/58e79013e3c1d412d8e1f8adc0c39a400484c5ae — search result only.
30. Wageningen B-series four-quadrant propeller representation (van Lammeren et al., 1969; MARIN) — textbook knowledge, not fetched; **unverified here**.
31. Repository: [RESEARCH.md](../../../RESEARCH.md) (APC/UIUC comparison, plan review #3 propwash, CRRCSim/PicaSim/YASim source reads), [compare_static_propeller.py](../../../research/compare_static_propeller.py), [P-51 derivation](../../../research/p51/p51-05/derivation.md), [jensen_ugly_stik_60.json](../../../app/data/aircraft/jensen_ugly_stik_60.json), [EXTRA-300-PLAN](../../EXTRA-300-PLAN.md) — read.

Calculations in this note (momentum table, Khan profile at the Stik's tail, swirl, lag, blade-element P-factor and normal force, static authority) were run with python3 in the session scratchpad. The formulas and inputs are given above so that they can be re-derived; the BEM uses the P-51 script's generic section, chord scaled ×1.4 to match the 12×6's static Ct 0.113.
