# HELI-01: RC helicopter research record

**Date:** 2026-10-13. **Scope:** evidence for the [helicopter plan](../../../plans/helicopter.md). It covers rotorcraft flight dynamics literature, RC-specific behaviour, candidate reference aircraft, open implementations, VFX/audio techniques for the pinned Godot 4.7.2 Compatibility renderer, and a map of the code seams in this repository on this date.

Sources are marked: **[F]** fetched and read, **[S]** found by search and not opened, **[U]** unverified claim. Numbers marked *derived* were recomputed for this record; the commands are under [Derived checks](#derived-checks). Nothing here is a measurement of a real aircraft by this project.

## 1. Identified small-scale helicopter models

### 1.1 MIT X-Cell .60 SE (Gavrilets, Mettler, Feron) [1, F]

This is a 17-state nonlinear model: rigid body (quaternion), first-order tip-path-plane (TPP) flapping a1/b1, rotor speed Ω and a governor integral. The authors integrated it with RK4 at 0.01 s. They validated it against flight data up to advance ratio µ < 0.15 (≈ 20 m/s), including negative rotor loading and high angular rates.

The aircraft had a flybar. Its effect is lumped into the rotor time constant (τe ≈ 0.1 s) and a flap-back attenuation Kµ.

| Parameter | Value | Evidence in the source |
| --- | --- | --- |
| m | 8.2 kg | measured; **includes avionics** |
| Ixx / Iyy / Izz | 0.18 / 0.34 / 0.28 kg·m² | measured (torsional pendulum) |
| Kβ hub torsional stiffness | 54 N·m/rad | identified (step responses) |
| γ_fb flybar Lock number | 0.8 | estimated |
| B_δlat, A_δlon | 4.2 rad/rad | identified; scaled with (Ω/Ω_nom)² |
| Kµ flap-back scaling | 0.2 | identified from trim |
| Ω_nom | 167 rad/s (1595 rpm) | measured |
| R_mr / c_mr | 0.775 m / 0.058 m | measured |
| a_mr | 5.5 /rad | borrowed (Harris) |
| C_D0 | 0.024 | estimated |
| C_Tmax | 0.0055 | estimated |
| I_β,mr | 0.038 kg·m² | measured |
| R_tr / c_tr | 0.13 m / 0.029 m | measured |
| a_tr / C_Tmax,tr | 5.0 /rad / 0.05 | estimated |
| n_tr tail/main gear ratio | 4.66 | measured |
| n_es engine/main gear ratio | 9.0 | measured |
| S_vf, CLα_vf, ε_vf,tr | 0.012 m², 2.0 /rad, 0.2 | as published |
| S_ht, CLα_ht | 0.01 m², 3.0 /rad | as published |
| P_eng,max | 2000 W | as published |
| Governor Kp / Ki | 0.01 s/rad / 0.02 /rad | derived from an rpm step test |
| S_x / S_y / S_z fuselage drag areas | 0.1 / 0.22 / 0.15 m² | S_x from −10° pitch at 14.5 m/s; S_y and S_z = 2.2 and 1.5 × S_x |
| h_mr; l_tr, h_tr; l_ht | 0.235 m; 0.91 m, 0.08 m; 0.71 m | as published |
| Limits δlat, δlon, δcol, δr | 0.096, 0.096, 0.183, 0.38 rad | as published |
| Swash servo (Futaba S9402) | lead-lag × 2nd order, ωn 36 rad/s, ζ 0.5 | identified |
| Tail servo (S9450) | ≈ 7 Hz, ζ 0.6 | identified |
| Governor 100 rpm step | ζ 0.63, ωn 1.3 rad/s | measured (engine sound, wavelet analysis) |

Model features to reproduce:

- Hub moments: L = (Kβ + T·h_mr)·b1, M = (Kβ + T·h_mr)·a1. Kβ is about 74 % of the X-Cell's control moment (54 against T·h ≈ 19 N·m/rad, *derived*).
- Inflow: Padfield's Newton iteration with η_w ≈ 0.9, kept away from the VRS singularity by a lower bound.
- Tail-rotor wake intensity K_λ ramps from 0 to 1.5 between geometric tangent limits. Fin blockage f_t = 1 − ¾·S_vf/(πR_tr²).
- Rotor speed: I_rot·Ω̇ = Q_e − Q_mr − n_tr·Q_tr − Q_loss. The PI governor has anti-windup.
- Finding: underestimating C_D0 over-predicts rotor speed in windmilling flight.

Companion identification: Mettler, Dever and Feron, JGCD 27(3) 2004 [2b, S]. The identified table itself was not accessible.

### 1.2 Yamaha R-50 hybrid model with stabilizer bar (Mettler, Tischler, Kanade) [2, F]

- Rotor 3.07 m, 89 rad/s, effective hinge offset ≈ 3 %.
- Flapping:
  - rotor: τf·ḃ = −b − τf·p + Ba·a + Blat·(δlat + Kd·d) + Blon·δlon
  - flybar: τs·ḋ = −d − τs·p + Dlat·δlat
- Hover: τf = 0.046 s and τs = 0.34 s (theory 0.053 and 0.36, from τ = 16/(γ_eff·Ω), γ_eff = γ/(1 + aσ/(16λ))).
- Lb = 166.1 /s², Ma = 82.57 /s², Zw = −0.614 /s, Nr = −4.13 /s.
- Cruise: τf = 0.035 s, τs = 0.26 s.
- Roll/flap mode √Lb = 12.9 rad/s; pitch/flap mode √Ma = 9.1 rad/s.
- Froude-scaling table: the R-50 has five revolutions of non-dimensional flap time constant.

### 1.3 Blade 360CFX flybarless (Walker and Tischler, VFS Forum 77, 2021) [3, F]

This is the most relevant flybarless identification found.

- Rotor 0.81 m, 1.41 kg, Ω = 230 rad/s.
- Measured inertias Ixx/Iyy/Izz = 0.0583/0.0377/0.0835 kg·m².
- A quasi-steady 6-DOF model fails. The criterion is τf² ≪ 1/Lβ1s, which does not hold, so a **hybrid flapping model is required**.
- τf = 0.0353 s, Lβ1s = −5115 /s², Mβ1c = −797 /s², cross-flap terms ≈ ±1.0.
- Zw = −0.59, Zcol = −22.3, Nr = −2.0, Nped = 63.0, Ncol = −32.5.
- Input delays 37–46 ms.
- Modes: lateral/flap 78 rad/s at ζ 0.21; longitudinal/flap 25.8 rad/s at ζ 0.46.
- Flap stiffness: −Lβ1s·Ixx = m·h·g + n_b·Mβ·Ω²·e/2 + n_b·Kβ/2.
- Roll flap stiffness |Lβ1s| by Froude scale: R-50 589, Raptor 50 647, 360CFX 5115. **A flybarless rotor is about 8× stiffer in roll than a flybarred one at the same scale.**

### 1.4 Heffley and Mnich, NASA CR-177476 (1988) [4, F]

The "minimum-complexity" design goals are:

- first-order flapping and momentum-theory inflow
- realistic power over the envelope
- rearward and sideward flight without α/β singularities (quadratic force forms)
- dihedral, the hover cubic and the hover-to-forward transition
- optional rpm variation and a correct power-off glide

Thrust–inflow loop, iterated five times (an air-mass-relative form):

- w_r = w_a + (a1 + i_s)u_a − b1·v_a
- w_b = w_r + ⅔ΩR(θ0 + ¾θtw)
- T = (w_b − v_i)·ρΩR·a·b·c·R/4
- v̂² = u² + v² + w_r(w_r − 2v_i)
- v_i² = √((v̂²/2)² + (T/2ρπR²)²) − v̂²/2

Other elements:

- Flap lag τ = 16/(γΩ).
- Dihedral db1/dv = −da1/du = (2/ΩR)(8C_T/(aσ) + √(C_T/2)).
- Off-axis hub moments are left out until data supports them.
- Tail rotor uses the same loop without flapping. Fuselage is a three-axis quadratic drag form.
- Extensions: exponential ground-effect factor, a 10–15 rad/s collective-to-thrust inflow lag, and a 2nd-order engine/governor.
- An effective control lag of ≈ 0.1 s is the pilot-relevant flapping feature.

### 1.5 Other sources

- Chen, NASA TM-78575 [5, S]: first-order TPP with hinge offset, spring, Lock number and pitch-flap coupling, K_c ≈ 8(νβ² − 1)/γ with νβ² = 1 + 3e/2R + Kβ/(I_β·Ω²).
- Taamallah, NLR-TP-2011-230 [6, F]: 18.5 kg flybarless model.
  - R 0.944 m, Ω 151.8 rad/s, Kβ 271 N·m/rad, lag damper 24.4 N·m·s/rad, NACA 0012, collective −3…10°, cyclic ±7°.
  - Model: 24 states with per-blade flap/lag plus 3-state Pitt-Peters with a VRS correction, checked against FLIGHTLAB (trim deviation ≤ 0.75°).
  - Steady autorotation: 10.5 m/s at −45° and 13.3 m/s at −30°. A 25 % mass change moves autorotation speed by only 4 %.
- Bhandari and Colgren: the paper is about a **Raptor 50**, AIAA MST 2006 [S]; no "Raptor 90" paper exists.
- Textbooks [not fetched]: Padfield, *Helicopter Flight Dynamics*; Johnson, *Rotorcraft Aeromechanics*; Leishman, *Principles of Helicopter Aerodynamics*; Bramwell; Tischler and Remple, *Aircraft and Rotorcraft System Identification*.

## 2. Fidelity ladder and time step

| Level | Added states | What it captures | Verdict at 240 Hz |
| --- | --- | --- | --- |
| (a) Momentum + quasi-static inflow (Heffley/Padfield iteration) | 0 | Hover/climb power, translational lift, heave damping Zw/Zcol, collective→yaw torque, flap-back with ∂a1/∂µ | Required core |
| (b) First-order TPP flapping a1, b1 (+ flybar c, d) | 2 (+2) | Control lag, the rotor–fuselage coupled mode, hub-spring moments, dihedral, flybar lagged-rate feedback | Required core |
| (d) Inflow dynamics: 1-state λ0, or 3-state Pitt-Peters M = diag(8/3π, 16/45π, 16/45π) [7] | 1 or 3 | Thrust overshoot on collective punches; λ1c/λ1s add the transverse-flow effect | 1-state first; 3-state later |
| (c′) Disk-quadrature blade element (loads at one instant over Nψ × Nr using current a0/a1/b1/λ) | 0 | Retreating-blade stall, reverse flow, high-µ behaviour without time aliasing | Later, cost-gated |
| (c) Per-blade azimuth time-marching | 2–4 per blade | 2/rev vibration, explicit transverse flow | **Rejected** (below) |
| (e) Peters-He finite state | 6–15+ | Radial inflow shape | Not better than Pitt-Peters for flight dynamics [6] |

**Stiffness.** RK4 is stable for real |λ·dt| < 2.79 and up to about 2.83 on the imaginary axis. At dt = 1/240 s:

| Case | τ | dt/τ or ω·dt |
| --- | --- | --- |
| X-Cell bare-rotor flap | 25.8 ms (*derived*) | dt/τ = 0.16 |
| 700-class flybarless flap | ≈ 19 ms (γ ≈ 4, estimated) | dt/τ = 0.22 |
| X-Cell inflow | 39 ms (*derived*) | non-stiff |
| Coupled flybarless rotor–body mode | up to 78 rad/s | ω·dt = 0.33 |

Levels (a), (b) and (d) are non-stiff.

**Per-blade aliasing.** At 240 Hz the rotor turns about 40° per step (X-Cell, *derived*), 50° (700 class at 2000 rpm) or 75° (450 class at 3000 rpm). Consequences:

- The rotating-frame flap frequency νβΩ ≈ 200–350 rad/s gives ω·dt ≈ 0.8–1.5. RK4 stays stable but corrupts the 90° gyroscopic phase that defines cyclic response.
- The n/rev loads of a two-blade rotor alias into steady bias. For example, 2/rev at 3600 rpm equals the 120 Hz Nyquist frequency.
- Johnson integrated at 5.4° per step [8]. The equivalent here would be 0.8–1.8 kHz substeps.

## 3. RC-specific behaviour

- **Flybarless (FBL) units.** Each axis is a rate loop (feed-forward plus PI/PID). The tail is a heading-hold gyro with collective/cyclic torque precompensation. Rescue and attitude modes exist in commercial units (BEASTX documents bail-out rescue with and without collective) [9, S].
  - Typical mechanical cyclic is ±10°; this is forum guidance [S].
  - 3D collective is about ±12–14° [U]; read it from the reference aircraft's manual.
  - FBL loop rates of 1–4 kHz are [U]. A 240 Hz discrete controller with a servo model is the simulation choice.
- **Flybar.** Use τs ≈ 16/(γ_fb·Ω) with Bell/Hiller mixing (Mettler), or lump it into τe (Gavrilets).
- **Drive.** Gear ratios:

  | Aircraft | Main | Tail |
  | --- | --- | --- |
  | X-Cell | n_es 9.0 | 4.66 |
  | T-Rex 700X | 8.46 [S] | 4.37 / 4.43 / 4.73 (retailers conflict) [S] |
  | ilGoblin Competizione | — | 4.9–5.1 [S] |

  Other drive elements:
  - A one-way bearing lets the rotor overrun the engine.
  - Throttle hold gives Q_e = 0.
  - Idle-up selects a flat throttle curve or a governor setpoint.
  - ArduPilot's governor is documented as proportional + droop compensator + throttle-curve feed-forward, with a fault fallback after 0.5 s [10, S].
- **Tail blowout.** The tail is thrust-capped at C_Tmax,tr·f_t·ρ(Ω_tr·R_tr)²πR_tr². Blowout happens when the heading-hold demand exceeds that cap.
- **Vortex ring state at RC scale.** v_h is only ≈ 3–4.2 m/s, so VRS onset (Vz/v_h ≈ −0.45 to −1.5 [8]) sits at **1.5–6 m/s descent**. Vertical descents and tic-tocs reach it routinely, so it belongs in the core.
- **3D flight.** Blades and collective are symmetric, so thrust laws must be sign-symmetric. Express ground effect and VRS in the thrust-normal frame. Gavrilets clips C_T at ±C_Tmax and reports 15 % less roll rate inverted.
- **Reynolds number at 0.75R** (*derived*):

  | Aircraft | Re |
  | --- | --- |
  | 360CFX | 1.4e5 |
  | 450 class | 1.8e5 |
  | X-Cell | 3.8e5 |
  | 700 class | 5.3e5 |

  For NACA 0012/0015 data through ±180°, use Sheldahl and Klimas SAND80-2114 [11, S].
- **Hover power.** RC rotors run at C_T/σ ≈ 0.015–0.05 with a figure of merit of only ≈ 0.13–0.30. Profile power dominates, so **C_d0 is a first-class parameter**: momentum theory alone under-predicts hover power by 3–5×.

## 4. Ground effect, VRS and autorotation

- **Cheeseman–Bennett** (ARC R&M 3021, quoted in [12, F]): T_IGE/T_OGE = 1/[1 − (R/4z)²/(1 + (V/v)²)]. It is reliable only for z/R > 0.6.
- **Hayden** (AHS 1976, via [12]): k_G = 0.9926 + 0.03794(2R/z)², applied as λ_IGE = λ_OGE/k_G. Clamp at z/R ≥ 0.5.
  - An RC helicopter sitting on skids has z/R ≈ 0.45–0.6 (700X hub ≈ 0.35 m, estimated), so ground effect is strong at lift-off.
- **Johnson VRS model**, NASA/TP-2005-213477 [8, F]. All velocities are normalized by v_h; it was built for real-time use.
  - Baseline: Vz + v = Vz(aVz² − b + cVx²) with a = 0.373, b = 0.991, c = 0.598, inside 1.5Vx² + (2Vz+3)² < 1.
  - Full-model breakpoints (Table 4): VzA −1.5, VzB −2.1, VxC 0.75, VzD −0.2, VzN −0.45, (Vz+v)N 0.85, VzX −1.5, (Vz+v)X 1.25, VzE −2.0, VxM 0.95.
  - Composition: v = κ(v_base + f·Δv_vrs), with κ ≈ 1.10–1.15 in hover.
  - Transient lag: τ = τ_rev·2π/Ω; 14 revolutions in one validation case, ≈ 0.4–0.5 s at RC rotor speed.
- **Leishman's empirical descent polynomial**: the coefficients −1.125, −1.372, −1.718, −0.655 are **[U]**. Prefer Johnson's model.
- **Windmill brake** (Vz < −2v_h): v = −Vz/2 − √((Vz/2)² − v_h²).
  - Autorotation then follows from Q(θ0, λ, Ω) = 0 with a rotor-speed state and a C_d(α) profile law. No special mode is needed.
- **Measured RC autorotation descent rates: none found** in the public literature.
  - ArduPilot SITL uses 5.3 m/s as its autorotation reference.
  - Taamallah's model gives ≈ 6.7–7.4 m/s sink (18.5 kg).
- **Interactions:**
  - fuselage download Z_fus = −½ρS_z(w_a + V_imr)·V∞
  - stabilizer w_ht = w_a + l_ht·q − K_λ·V_imr
  - tail rotor in main-rotor wake per Gavrilets' K_λ

## 5. Candidate reference aircraft

| Aircraft | Rotor Ø | Head speed | Mass | Data quality |
| --- | --- | --- | --- | --- |
| **X-Cell .60 SE (MIT)** [1] | 1.55 m | 1595 rpm | 8.2 kg instrumented | Complete physical table, flight validation, identification companion |
| Align T-Rex 700X [13, S] | 1.582 m (tail 281 mm) | ≈ 1800–2100 [U] | 5.1–5.3 kg | Retail specs only; ratios conflict |
| Align T-Rex 450 Pro V2 [14, S] | 0.71 m | ≈ 3000 [U] | ≈ 0.64 kg | Retail only |
| SAB Goblin 700 Competition [15, S] | 1.568 m | [U] | 3.62 kg dry | Retail only |
| Hughes 500E 1:6 (Vario) [16, S] | ≈ 1.68 m | ≤ 1600 | ≈ 7.5 kg | Retail only |
| Blade 360CFX [3] | 0.81 m | 2200 | 1.41 kg | Identified flybarless dynamics |

Only the X-Cell has a numerically complete published parameter set. A modern flybarless 700 class would need every number except retail geometry to be estimated, then checked against the 360CFX, R-50 and Taamallah structure.

## 6. Open implementations

| Project | License | Model | Use here |
| --- | --- | --- | --- |
| ArduPilot SITL `SIM_Helicopter.cpp` [17, F] | GPL-3 | Thrust ∝ coll·rpm²; first-order TPP with τ 0.068 s and fixed Lb1s/Ma1s; gas engine with clutch; 50 ms servo delay; a `blade360` frame from Walker | Study only; identified-linear, not aerodynamic |
| JSBSim `FGRotor` [18, F] | LGPL-2 | Quasi-static coning/flapping; one lagged inflow state; exponential ground effect (clamped 0.5–1); FGTransmission clutch/freewheel | Study only |
| FlightGear YASim `Rotor.cpp` [19, F] | GPL-2 | Azimuth "rotorparts"; ad hoc translational lift ×1.3; VRS factor hard-coded to 1 | Counter-example |
| HELI-X [20, F] | Closed | Claims translational lift, stall, ground effect, dynamic stall, VRS, paddle dynamics, head stiffness; no equations published | Feature checklist only |
| neXt, RealFlight | Closed | No technical documentation found | — |
| PX4, Gazebo RotorS | BSD-3 / ASL-2 | No single-rotor helicopter physics | — |

Do not copy GPL code into the MIT application; implement from the published equations.

## 7. VFX and rendering on Godot 4.7.2 Compatibility

These facts were verified against the `4.7.2-stable` source [21, F] unless marked otherwise.

- **GPU particles.** `GPUParticles3D` runs in Compatibility with transform feedback, not compute.
  - Supported: box, sphere and heightfield collision; box and sphere attractors; turbulence (costly on iGPUs [22]).
  - **Unsupported:** trails, sub-emitters, `emit_particle()`, 3D SDF collision and vector-field attractors.
  - Limits: 32 colliders and 32 attractors.
- **Sorting.** View-depth sorting runs on the CPU from a buffer two frames old.
- **Seeding.** `seed` and `use_fixed_seed` exist from 4.4.
- **Defaults.** `fixed_fps` 30 and `interpolate` true.
- **Headless.** `--headless` uses dummy particle storage, so particles do not simulate. llvmpipe is GL 4.5 conformant, so captures under xvfb do simulate.
- **CPUParticles3D.** Point-shape emission uses the global `Math::rand()`, so seed it explicitly.
- **Depth texture.** Any material reading `hint_depth_texture` (including `proximity_fade`) adds one full-screen depth blit after the opaque pass.
- **Instancing.** There is no automatic instancing in Compatibility; use MultiMesh.
- **Global uniforms.** They must exist in Project Settings before shaders compile [23].
- **Project facts** (recorded by the VQ-05 and smoke tracks):
  - per-instance `transparency` is ignored, so fades need alpha material copies
  - back faces are lit by winding
  - no Visual Profiler
  - `TIME` is forbidden in shaders by `test.sh`; use `sim_clock`

**Rotor visual aliasing** (*derived*):

| Rotor speed | Rotation per 60 fps frame | Apparent motion of a two-blade rotor (180° symmetric) |
| --- | --- | --- |
| 1595 rpm | 159.5° | Slow backward rotation |
| 1800 rpm | 180° | Frozen |
| 2100 rpm | 210° | Slow forward rotation |

At speed, the time-averaged coverage at radius r is N·c/(2πr): ≈ 2.7 % at 0.7 m and ≈ 13 % at 0.15 m for 60 mm chords. A real disc is nearly transparent except at the root and the tip markings.

Industry references:
- X-Plane: RPM-indexed disc textures, view-angle front/side alpha, optional side billboard [24].
- MSFS 2024: shader accumulation of the blade mesh, coning from animation, and shadow casting disabled on the spinning mesh [25].
- Users still report strobing in MSFS [26].

**Rotor wash physics.**

- Hover outwash is a radial wall jet [27, 28]:
  - peak mean outwash at r/R ≈ 1.7–1.8 whatever the height, at ≈ 1.7–2.1 v_h
  - high-velocity layer within ≈ 0.15 R of the ground
  - stagnation under the hub at r/D ≈ 0.2–0.33
  - model-scale profiles collapse onto CH-47D data with Glauert wall-jet scaling
  - the far-field decay ≈ r^−1.1 is **[U]**
- Entrainment thresholds:
  - dust and sand u*t ≈ 0.20–0.29 m/s [29]
  - water ripples u* ≈ 0.02 m/s [30], so ripples reach much farther than dust
  - small rotors over water show dimpling, splashing and penetration regimes [31]
- Brownout mechanisms (vortex-induced uplift, saltation) [32, 33].

**Scale (derived and estimated).**

| Aircraft | Disc loading | v_h | Peak outwash |
| --- | --- | --- | --- |
| 700X | ≈ 26 N/m² | ≈ 3.3 m/s | ≈ 6 m/s at ≈ 1.4 m |
| X-Cell | 42.6 N/m² | 4.2 m/s | — |

- With wall-jet skin friction u* ≈ 0.05–0.07 U **[U]**, loose dry dust lifts within ≈ 1.5 D when the hub is below ≈ 1 D.
- Expected extents: grass ripples to ≈ 2–3 D, water ripples farther, spray only for h/D ≲ 0.5 (estimated).

**Lesson from DCS and MSFS 2024 user reports [34, 35].** Dust that persists at flat pitch reads as wrong. Drive every wash effect from simulated thrust, height and surface, never from rpm alone.

**Grass.** An analytic radial field through global uniforms is enough for one aircraft [36]. A SubViewport interaction map pays only with many interactors. In GLES3, MultiMesh `MODEL_MATRIX[3]` already includes the instance transform [21].

## 8. Audio

| Source | X-Cell value (*derived*) | Notes |
| --- | --- | --- |
| Main-rotor blade-passage frequency (BPF) | 53.2 Hz (2 blades × 1595 rpm) | Thickness noise in-plane (tip Mach ≈ 0.38); loading noise below the disc |
| Tail BPF | 247.7 Hz (× 4.66) | |
| Engine | ≈ 14 350 rpm (× 9.0), one firing per revolution ≈ 239 Hz | |

- **Blade–vortex interaction ("slap").** Expected in partial-power descent, flares and turns [37]. For RC, key it to Vz/v_h and inflow.
- **Small-rotor acoustics.** Up to 8 dB OASPL difference at equal thrust, and motors contribute [38]. Controller rpm activity makes the noise time-varying [39]. FW-H theory overview [40].
- **Synthesis.**
  - Additive BPF harmonics with per-blade amplitude/phase modulation for the "wop" [41].
  - Separate tail, gear and engine/motor layers.
  - Physical propeller synthesis scores below recordings in listening tests [42].
- **Godot.**
  - `AudioStreamGenerator` is best fed from native code; from GDScript use ≤ 22 050 Hz [43].
  - This project computes Doppler manually and loops sampled assets (AUD-01…05).

## 9. Code seams on 2026-10-13

These are line references to the working tree on this date; verify them before editing.

| Seam | Today | Helicopter need |
| --- | --- | --- |
| Body state | `physics/rigid_body.gd:13-20`, 13 values; `RB.derivative` accepts a summed rotor momentum `h` | Reusable unchanged |
| Extra states | `sim/simulation.gd`: `aux` (tick-held), `modes` (discrete), `continuous` (RK-stage, joint `{loads, derivative, rotor_momentum}`) | Ω, a1, b1, λ0 continuous; servo, governor and gyro integrators in aux; flight modes in `modes` |
| Template | Coupled shaft rpm: layout `flight_session.gd:1256`, response `:1328-1401`, aux mirror `:1315`, reset `:944-993`, checkpoint `:1820-1870`, restore `:1875-1963`, trace meta `:1669-1815`, replay class `tests/replay_policy.gd:8-18` | Same nine steps |
| Inputs | 4 wide everywhere (`simulation.gd:24`, trace, goldens, calibration) | Keep 4 sticks; add modes |
| Load assembly | Hand-written in 3 places (`_wash_loads` `:1157`, `_wheel_evaluate` `:1195`, `_coupled_response` `:1351`); no contributor interface | One rotorcraft evaluate callback |
| Gyroscopics | `physics/rotor_coupling.gd`: single unit axis, Ω ≥ 0 | Geared main + tail: b = I_m·a_m + n·I_t·a_t, I_eff = I_m + n²I_t |
| Loader | v2 down-converted to v1 (`aircraft_data.gd:156-166`); wing reference, 32 stable-airplane derivatives, tails and a ±10° thrust axis required | Separate rotorcraft derive path |
| Trim | `physics/trim.gd`: level/glide only, V > 0, flight refused if trim fails | Hover and forward rotorcraft trim |
| Ground | Point contacts with a rolling-tyre law; anchors; `ground_start.gd` Stik-only | Isotropic skid friction law; pad start |
| Crash | Hull points terminal; no rotor-disc check; component guess uses wing span | Disc-clearance blade strike; rotorcraft components |
| Air | Wind uniform in space; `air_data.gd` CG-only | Element flow v + ω×r is enough for now |
| Catalog | `app_state/aircraft_catalog.gd:20-63`; PREVIEW refuses Fly (Timber) | Preview first, then experimental |
| Render | `main.gd:912` spins `propeller.rotation.z` from `aux[0]`; `render/propeller_blur.gd` flat disc, `BLUR_START_HZ` 12, `BLUR_FULL_HZ` 48 | Rotor disc with coning/TPP; tail rotor with ratio |
| Particles | Only `CPUParticles3D` in `render/crash/effects.gd` (556 particles); no `GPUParticles3D`; smoke SM-00 probe not started | First flight-time particles |
| Grass | `render/near_grass.gdshader` global `wind_vec`, `sim_clock`; no local source | Downwash global uniform |
| Audio | `audio/soundscape.gd` `MAX_VOICES` 14; prop pitch rpm/6000 × blades/2 | Rotor, tail and engine layers |
| HUD | `render/overlays/telemetry.gd`; O5 `rpm` from `aux[0]` | Head speed, collective, governor, modes, VRS/tail warnings |
| Budgets | Tick ≤ 500 µs (Gate P open); Stik ticks 200–445 µs; local strips ≈ 2.3–3.6 µs per element evaluation (H12); P-51 733–880 µs fails | Rotor kernel must cost about one `Aero.loads` call |

## Derived checks

These values were computed with Python 3 from the X-Cell table, ρ = 1.225 kg/m³, g = 9.81 m/s²:

| Quantity | Value |
| --- | --- |
| Lock number γ = ρ·c·a·R⁴/I_β | 3.71 |
| Flap time constant τf = 16/(γΩ) | 25.8 ms |
| Hover thrust T | 80.4 N |
| Disc loading | 42.6 N/m² |
| v_h | 4.17 m/s |
| Ideal hover power | 336 W |
| Rotor–fuselage mode √((T·h + Kβ)/I) | roll 20.1 rad/s, pitch 14.6 rad/s |
| Solidity σ | 0.0476 |
| C_T | 0.00208 |
| C_T/σ | 0.044 |
| λ_h | 0.032 |
| Inflow time constant τλ = 0.849/(4λΩ) | 39 ms |
| Tip speed | 129 m/s (M 0.38) |
| Hover torque (κ 1.15, C_D0 0.024) | 6.6 N·m |
| Hover power | 1.10 kW (FM ≈ 0.30) |
| Rotor travel per 240 Hz step | 39.9° |
| Re at 0.75R (μ 1.81e-5) | 3.8e5 |

For the 700X at 5.2 kg and R 0.791 m: disc loading 26.0 N/m², v_h 3.25 m/s.

## Bibliography

1. Gavrilets, Mettler, Feron, *Dynamic Model for a Miniature Aerobatic Helicopter* (AIAA 2001-4333 lineage). http://www.israelbarrientos.org/personal/simulador_files/helimodel_gavrilet.pdf [F]. Thesis: https://dspace.mit.edu/handle/1721.1/17609 [S].
2. Mettler, Tischler, Kanade, CMU-RI-TR-00-03 (2000). https://www.ri.cmu.edu/pub_files/pub2/mettler_bernard_2000_1/mettler_bernard_2000_1.pdf [F]. 2b: Mettler, Dever, Feron, JGCD 27(3):466–478, 2004. https://experts.umn.edu/en/publications/scaling-effects-and-dynamic-characteristics-of-miniature-rotorcra/ [S].
3. Walker and Tischler, *Identification and Control Design of a Sub-Scale Flybarless Helicopter*, VFS Forum 77 (2021). https://phones.sjsu.edu/researchfoundation/docs/VFS_2021_Walker.pdf [F].
4. Heffley and Mnich, NASA CR-177476 (1988). https://ntrs.nasa.gov/citations/19880020435 [F].
5. Chen, NASA TM-78575 (1979). https://ntrs.nasa.gov/citations/19790015806 [S].
6. Taamallah, NLR-TP-2011-230. https://reports.nlr.nl/items/5cc73288-4c7a-491e-b458-c43081d1deee/full [F].
7. Pitt and Peters, Vertica 5(1) 1981. https://dspace-erf.nlr.nl/items/5cf68982-a820-491e-97b4-588410e280a4/full [S]; matrix summary https://bladead.readthedocs.io/en/latest/src/background/pitt_peters.html [F].
8. Johnson, NASA/TP-2005-213477. https://rotorcraft.arc.nasa.gov/Publications/files/Johnson%20TP-2005-213477.pdf [F].
9. BEASTX Microbeast PLUS wiki. https://wiki.beastx.com/index.php/Manuals:MB_Plus:Preliminary_steps_2 [S].
10. ArduPilot internal RSC governor. https://ardupilot.org/copter/docs/traditional-helicopter-internal-rsc-governor.html [S].
11. Sheldahl and Klimas, SAND80-2114. https://digital.library.unt.edu/ark:/67531/metadc1191254/m2/1/high_res_d/6548367.pdf [S].
12. Khromov and Rand, ICAS 2008. https://icas.org/ICAS_ARCHIVE/ICAS2008/PAPERS/085.PDF [F].
13. T-Rex 700X. https://www.air-rc.com/aircraft/Align_T-Rex-700X_TR700X [S].
14. T-Rex 450 Pro V2. https://www.air-rc.com/aircraft/Align_T-REX-450-Pro-V2_TRX450PROV2 [S].
15. SAB Goblin 700 Competition. https://goblin-helicopter.com/products/sab-goblin-700-competition-yellow-blue-with-main-and-tail-blades [S].
16. Vario Hughes 500E. https://www.vario-helicopter.biz/be/Fuselages/Hughes-500E-1-6-Fuselage-kit::200655.html [S].
17. ArduPilot `SIM_Helicopter.cpp`. https://github.com/ArduPilot/ardupilot/blob/master/libraries/SITL/SIM_Helicopter.cpp [F].
18. JSBSim propulsion models. https://github.com/JSBSim-Team/jsbsim/tree/master/src/models/propulsion [F].
19. FlightGear YASim `Rotor.cpp`. https://github.com/FlightGear/flightgear/blob/next/src/FDM/YASim/Rotor.cpp [F].
20. HELI-X physics. https://www.heli-x.info/cms/physics/ [F].
21. Godot 4.7.2 source: `drivers/gles3/storage/particles_storage.cpp`, `rasterizer_scene_gles3.cpp`, `scene/3d/cpu_particles_3d.cpp`, `servers/rendering/dummy/storage/particles_storage.h`. https://github.com/godotengine/godot/tree/4.7.2-stable [F].
22. Godot docs, particle turbulence. https://docs.godotengine.org/en/stable/tutorials/3d/particles/turbulence.html [F].
23. Godot docs, shading language (global uniforms). https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html [F].
24. X-Plane, custom prop discs. https://developer.x-plane.com/article/custom-prop-discs/ [F].
25. MSFS 2024 SDK, propellers and blades. https://docs.flightsimulator.com/msfs2024/retail/models-and-textures/modeling/aircraft/airframe/propellers-turbines-and-blades/index.md [F].
26. MSFS forum, rotor blur strobing. https://forums.flightsimulator.com/t/helicopter-rotor-blur-and-shadow-strobing/556821 [S].
27. Tanner et al., rotorcraft outwash in ground effect, AHS 2015. https://ntrs.nasa.gov/api/citations/20160006428/downloads/20160006428.pdf [F].
28. Ramasamy and Yamauchi, JAHS 62 (2017). https://rotorcraft.arc.nasa.gov/Publications/files/Yamauchi_AHS_Journal_Jan_2017.pdf [F].
29. Kok et al., physics of wind-blown sand and dust. https://arxiv.org/pdf/1201.4353 [F].
30. Kahma and Donelan, JFM 192 (1988). https://data-ww3.ifremer.fr/BIB/Kahma_Donelan_JFM1988.pdf [S].
31. Bai et al., Drones 8(9):469 (2024). https://www.mdpi.com/2504-446X/8/9/469 [F].
32. Phillips and Brown, J. Aircraft 46(4) 2009. https://strathprints.strath.ac.uk/27438/ [S].
33. Sydney, UMD thesis 2011. https://drum.lib.umd.edu/handle/1903/12535 [S].
34. DCS forum, downwash dust effects. https://forum.dcs.world/topic/332140-new-downwash-dust-effects [S].
35. MSFS devsupport, downwash should depend on collective. https://devsupport.flightsimulator.com/t/helicopter-downwash-effect-on-vegetation-should-be-collective-dependent/17452 [S].
36. Bittner, grass interaction in Godot. https://hexaquo.at/pages/grass-rendering-series-part-3-animating-and-interacting-with-grass-in-godot/ [F].
37. UH-1 impulsive noise, DTIC ADA025979. https://apps.dtic.mil/sti/pdfs/ADA025979.pdf [S].
38. Zawodny et al., NASA 2016. https://ntrs.nasa.gov/citations/20160009054 [S].
39. Cabell, McSwain, Grosveld, NASA 2016. https://ntrs.nasa.gov/citations/20160010139 [S].
40. Brentner and Farassat, Prog. Aerosp. Sci. 39 (2003). https://ntrs.nasa.gov/citations/20040085745 [S].
41. Farnell, *Designing Sound*, Practical 25: Helicopter. https://mitp-content-server.mit.edu/books/content/sectbyfn/books_pres_0/8375/designing_sound.zip/practical25.html [S].
42. Selfridge, Moffat, Reiss (2017). https://napier-repository.worktribe.com/output/3011204/physically-derived-sound-synthesis-model-of-a-propeller [S].
43. Godot `AudioStreamGenerator`. https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html [F].
