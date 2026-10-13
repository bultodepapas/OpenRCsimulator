# DR-01: FPV drone racing research record

**Date:** 2026-10-13. **Scope:** evidence for the [drone racing plan](../../../plans/drone-racing.md). It covers identified multirotor models and datasets, small-propeller data, motor/ESC/battery sources, flight-controller behaviour, racing formats and timing, FPV cameras and view rendering, VFX/audio facts for the pinned Godot 4.7.2 Compatibility renderer, input conventions, existing simulators, and a map of the code seams in this repository on this date.

Sources are marked by how they were used: **[F]** fetched and read, **[S]** found by search and not opened, **[U]** unverified claim. Numbers carry their evidence: **[M]** measured, **[MS]** manufacturer-stated, **[D]** firmware default read in the Betaflight master source on 2026-10-13, **[E]** estimated or derived here. Values marked *derived* were recomputed with [`research/drone-racing/dr-01/derived_checks.py`](../../../../research/drone-racing/dr-01/derived_checks.py); the output is under [Derived checks](#derived-checks). Nothing here is a measurement of a real aircraft by this project. The primary PDFs read during this research (FAI F9U 2019, Intaratep 2016, Cabell 2016, MultiGP UTT 1, Faessler 2018, Agilicious, NeuroBEM, Bauersfeld 2022, Drela 2007) were downloaded to the session scratchpad and are **not** committed: their redistribution rights were not checked.

Bibliography A (physics, data, firmware) is cited as [A*n*]; bibliography B (racing, timing, presentation, input) as [B*n*].

## 1. Identified multirotor models and data

### 1.1 The canonical model

Mahony, Kumar and Corke's tutorial [A1, F] is the standard reference: per-rotor thrust T_i = c_T·ω_i², reaction torque Q_i = c_Q·ω_i², and an in-plane "H-force" from blade flapping and induced drag, lumped as a force linear in body-relative velocity. Bangura and Mahony [A2, S] showed that static c_T/c_Q become invalid in aggressive manoeuvres and proposed an implicit momentum-theory thrust model with vortex-ring switching. Leishman [A4] supplies forward-flight inflow (Glauert), descent/VRS physics and the Cheeseman–Bennett ground-effect form.

### 1.2 Rotor drag on racing hardware (Faessler, Franchi, Scaramuzza 2018) [A5, F]

Equations as published: v̇ = −g·z_W + c·z_B − R·D·Rᵀ·v; ω̇ = J⁻¹(τ − ω×Jω − τ_g − A·Rᵀv − B·ω); c = c_cmd + k_h·v_h², D = diag(d_x, d_y, d_z) in s⁻¹ (mass-normalized). Identified on a 610 g, thrust-to-weight 4, 6-inch FPV quad [M]: d_x = 0.544 s⁻¹, d_y = 0.386 s⁻¹ (circle); 0.491/0.236 s⁻¹ (lemniscate); d_z ≈ 0 did not help; A and B neglected. These are the best public starting values for a 5-inch quad's lumped rotor drag, and the small-μ check for the plan's H-force.

### 1.3 Agilicious (Foehn et al. 2022) [A6, F]

| Item | Value | Evidence |
| --- | --- | --- |
| Frame, motors, props | Armattan Chameleon 6"; Hobbywing XRotor 2306 2400 KV (758 W); Azure SFP 5148 tri-blade | [MS] |
| Static thrust | 4 × 9.5 N continuous | [MS/M] |
| Pack, ESC | 1800 mAh 120C 4S; Hobbywing XRotor 60 A DShot | [MS] |
| Motor model | first-order lag, **τ = 39.1 ms** on an ATI Mini-40 load cell | [M] |
| Command-to-force latency | Betaflight 40.15 ms; agiNuttx 35 ms; offboard link > 75 ms | [M] |
| Simulator | 1 kHz; selectable *Quadratic* (T = c_t·ω²) or *BEM* rotor model | — |

### 1.4 NeuroBEM (Bauersfeld et al. 2021) [A7, F] and its dataset [A85, F]

Same airframe class: 752 g, 33 N maximum static thrust, thrust-to-weight 4.5, XRotor 2306, 5-inch tri-blade. Motor first-order lag **τ_Ω = 33 ms** from a step response [M]. Dataset: 96 flights, 1 h 15 min, up to 65 km/h, 29 columns (position, quaternion, velocity, acceleration, ω, ω̇, **four motor speeds and their derivatives, battery voltage**), mass 0.772 kg, J = diag(0.0025, 0.0021, 0.0043) kg·m², 400 Hz (onboard 1 kHz), raw Vicon bags and Betaflight blackbox files.

Table II (RMSE on unseen flights, 1.8 M samples) [M]:

| Model | Force RMSE | Torque RMSE |
| --- | --- | --- |
| no aerodynamics | 7.96 N | 0.029 N·m |
| quadratic fit (c_t·ω², linear drag) | 1.486 N (in-plane 1.536 N) | 0.087 N·m |
| blade-element momentum | 0.982 N | 0.074 N·m |
| polynomial grey-box | 0.606 N | 0.022 N·m |
| BEM + neural network | 0.335 N | 0.012 N·m |

The quadratic model's error is dominated by in-plane force and torque: what a pilot feels in high-speed turns. This table is the plan's held-out acceptance reference (DR-38).

### 1.5 Swift (Kaufmann et al. 2023) [A8, F] and human latency [A9, F]

870 g, 35 N, thrust-to-weight 4.1, T-Motor Velox 2306, 5-inch tri-blade, Betaflight + BLHeli_32. Model: lift c_l·Ω², drag torque c_d·Ω², first-order motor lag; body torque with thrust moments, **yaw torque from motor acceleration** and −ω×Jω; a grey-box polynomial aerodynamic model in body velocity and mean-squared motor speed fitted from motion-capture flights; steady-state motor speed a polynomial of battery voltage and command, identified from Betaflight logs; P_mot ∝ Ω³. The simulated Betaflight PID and ESC reproduce motor commands to < 1 % [M]. Swift's sensorimotor latency is 40 ms against 220 ms for expert humans (21 pilots, eye tracking) [A9, M].

### 1.6 Typical magnitudes

- From a 5-inch bench point (HQ 5x4x3 on a 2306.6/2550 KV: 449 g at 18,900 rpm [A10, M]): c_t ≈ 4.4 N/(1979 rad/s)² ≈ 1.1 × 10⁻⁶ N·s²/rad² [E from M].
- κ = c_q/c_t must be identified: Crazyflie 4.5 × 10⁻³ m [A11, M]; no public 5-inch value [E 0.01–0.02 m].
- Motor time constants: 33–39 ms on 2306/5-inch tri-blade [A6, A7, M]; 65–73 ms on Crazyflie [A11, M].
- Rotor inertia: J_r ≈ 10⁻⁵ kg·m² [A8 context, E]; the derived checks use 7 × 10⁻⁶ (prop ≈ 5 × 10⁻⁶ plus bell ≈ 2 × 10⁻⁶, estimated).

## 2. Rotor models and the fidelity ladder

| Level | States | What it captures | Verdict at 240 Hz |
| --- | --- | --- | --- |
| Quadratic c_t·ω², c_q·ω² | 0 | hover and near-hover; nothing of speed | Static-point oracle only |
| + linear rotor drag D·v [A5] | 0 | first-order deceleration, pitch-up with speed as a lumped force | Small-μ check |
| Blade-element + momentum with quasi-static Glauert inflow, Johnson VRS/windmill branches, Cheeseman–Bennett ground effect [A4, A2, HELI-01 §4] | 0 (inflow quasi-static) | climb/descent asymmetry, thrust loss at speed, VRS, ground cushion, torque rise at full throttle | **Required core** (plan §4.3) |
| + H-force and hub moment from blade asymmetry [A4] | 0 | the nose-up and slow-down on stick release at speed | Required core |
| BEMT tables from measured chord/pitch and Re ≈ 10⁵ polars [A6 BEM, A21] | 0 | radial loading, high-J behaviour | Deferred behind a capability |
| Polynomial grey-box or BEM + NN [A7, A8] | 0 | rotor–frame interaction | Not a physics model; comparison only |

**Time step.** Inflow time constant 0.849/(4·λ·Ω) is ≈ 2 ms at hover (λ_h = 0.105, Ω = 1,034 rad/s, *derived*), below the 4.17 ms tick, so inflow is quasi-static (fixed-pass iteration). Motor electromechanical constant τ = R_m·J/k_t² is 16–40 ms for the motors in the derived checks, dt/τ = 0.10–0.26, non-stiff for RK4 (stable to |λ·dt| < 2.79); the loader's conservative explicit-step ratio of 0.25 ([flight_session.gd:16](../../../../app/sim/flight_session.gd#L16)) is a qualified envelope, not a stability limit, and the plan qualifies the quad's ratio per configuration (DR-09). The rotor turns 0.7–2.1 revolutions per tick, so per-blade marching is meaningless here and rejected.

## 3. Small-propeller aerodynamic data

| Source | What exists | Gap |
| --- | --- | --- |
| UIUC propeller database vol. 1 (Brandt) [A14, F] | 7–19 in props, static and wind-tunnel C_T, C_P vs J | nothing ≤ 6 in |
| UIUC vol. 2 (Deters) [A15, F] | ≈ 40 props ≤ 6 in including 5-inch three-blade (DA4022/DA4052 5x3.75, NR640, Micro Invent 5x4), GWS 5x4.3; static and J sweeps | 4,000–7,500 rpm; no FPV brands; Reynolds far below racing speeds |
| Brandt & Selig 2011 [A16, F] | low-Re propeller performance method | — |
| Tyto/RCbenchmark database [A17, F] | > 900 user-uploaded tests (71 motors, 115 props): thrust, torque, rpm, V, I, efficiencies | static only |
| miniquadtestbench [A10, F] | HX711 static stand, 4 ms logger: thrust/current/voltage/rpm at 100/75/50/25 % and idle; 2306/2207 motors on HQ, DAL, Gemfan, Lumenier 5-inch tri-blades (HQ v1s 5x4x3: 1,228 g, ≈ 479 W) | no torque, no forward flight |
| APC data files [A18, F] | every APC prop including 5-inch E/EP: C_T, C_P vs J at many rpm | **computed** (vortex theory + NASA TAIR airfoil code), not measured; not reproduced by QBlade users [A19] |
| Shetty & Selig 2011 [A20, F] | 26 props in descent, J −0.8…0 (VRS) | 9–11 in only |

Conclusion: static thrust/current/rpm for racing motor–prop pairs is measured [A10, A17]; torque at racing rpm is rare; **no public forward-flight (advance-ratio) data exists for 5-inch racing props at racing Reynolds and Mach numbers**. The only dynamic validation at this scale is whole-vehicle flight data [A7, A21]. Thin high-pitch 5-inch props (Cyclone 5051, RaceKraft 5051, Avan) stalled or fluttered under static load with lower thrust at equal rpm, qualitatively [A69, F].

## 4. Flight-controller behaviour

### 4.1 Rate curves (Betaflight `rc.c`, read in the master source) [A33, F]

Input x ∈ [−1, 1] after deadband; output in deg/s, clamped to ±1,998.

- **Actual** (default since 4.3): expof = |x|·(x⁵·e + x·(1−e)); centre = rcRates·10; stickMovement = max(0, rates·10 − centre); rate = x·centre + stickMovement·expof.
- **Betaflight**: x ← x·|x|³·e + x·(1−e); rcRate = rcRates/100 (+14.54·(rcRate−2) above 2); rate = 200·rcRate·x / clamp(1 − |x|·rates/100, 0.01, 1).
- **Raceflight**: rate = 10·rcRates·x·(1 + |x|·rates·0.01).
- **KISS**: rate = 2000·[1/clamp(1 − |x|·rates/100)]·(x³·e + x·(1−e))·rcRates/1000.
- **Quick**: rcRate = 2·rcRates; maxDPS = max(10·rates, rcRate); superFactor = (maxDPS/rcRate − 1)/(maxDPS/rcRate); rate = curve·rcRate/clamp(1 − |x|·superFactor).

Defaults [A34, D]: ACTUAL, rcRates 7 (70 deg/s centre), rates 67 (670 deg/s max), expo 0; so `set roll_rc_rate = 7` and `set roll_srate = 67` mean 70 and 670 deg/s [B48, B49]. Racers fly ≈ 550–650 deg/s near-linear, freestyle 850–1,200 deg/s; the maximum rate is capped by motor authority, not the curve [A35, F]. `dump rates` / `diff rates` export the text block to import [B50, F]. Curves at example points are tabulated under [Derived checks](#derived-checks).

### 4.2 PID loop, terms and filters (defaults in master) [A36, A37, A41–A44, D]

- Roll P/I/D/F 45/80/30/120; pitch 47/84/34/125; yaw 45/80/0/120; D_max 40/46/0 (gain 0, advance 35); anti-gravity gain 80 (cutoff 5 Hz); I-term relax RP/SETPOINT, cutoff 15; throttle boost 5 (cutoff 15 Hz); TPA mode D, 65 % at full throttle above 1350 µs; feed-forward 2-point averaging, smoothing 65, jitter 7, boost 15, max-rate-limit 90; angle_limit 60°, horizon_limit 135, level PID 50/75; `pid_at_min_throttle` on (air-mode semantics), `airModeActivateThreshold` 25.
- Loop: 8 kHz PID (125 µs) locked to the gyro rate on MPU6000-class gyros, 3.2 kHz on BMI270 [A38, A39]; 4 kHz advised on F4 with RPM filtering [A40]; DShot is sent at the end of each PID iteration [A27].
- Filters: gyro LPF1 dynamic PT1 250→500 Hz, LPF2 PT1 500 Hz; D-term LPF1 dynamic PT1 75→150 Hz, LPF2 PT1 150 Hz; dynamic notch 3 notches, Q 300, 100–600 Hz via SDFT; RPM filter 3 harmonics, Q 500, min 100 Hz. PT2 adds ≈ 60 % delay over PT1, PT3 ≈ 2× [A45]. All of these cutoffs lie above the 120 Hz Nyquist frequency of a 240 Hz controller: the plan replaces them by one-tick equivalents and says so in the data.
- Mixer: `mixer_type` LEGACY default; DYNAMIC behaves linearly when one axis saturates [A31, A46]. Dynamic D (4.3+) raises D during prop-wash [A47]; the tuning guide ties low D to "propwash oscillations in vertical descents" [A48].
- Motor defaults [A28, D]: DSHOT600, `motor_idle` 5.5 %, 14 poles (7 pole pairs), `motor_kv` 1960, dynamic idle off (3,000–4,000 rpm recommended on 5-inch [A29]), `motor_output_limit` 100 %, `vbat_sag_compensation` 0 [A25]; `thrust_linear` 0–150, default 0, exists because thrust is not linear in duty [A25, A26]. Crash-flip reverses only the commanded pair by DShot command [A30]; `crashflip_motor_percent` default 0 [A31].
- Modes [B52, F]: ARM (0), FLIP OVER AFTER CRASH (35, needs DShot), BEEPER ON, PREARM, PARALYZE. Stick arming is the default and is disabled when a switch arms; throttle below `min_check` allows arming; motors idle when armed [B51, F].
- DShot [A27, F]: 16-bit frame, 11-bit value (0 disarm, 1–47 commands, 48–2047 throttle), 150/300/600 kbit/s; bidirectional mode returns eRPM ≈ 30 µs after the frame; mechanical rpm = eRPM/(poles/2).

### 4.3 Latency chain

| Link | Figure | Evidence |
| --- | --- | --- |
| RC link | ExpressLRS 2.4 GHz LoRa 50/150/250/500 Hz, FLRC F500/F1000, D250/D500; 900 MHz ≤ 200 Hz [A49, B58]; "as low as 5 ms at 500 Hz" [A51]; packet interval 1–2 ms [E]; RC smoothing auto factor 30 [A37] | no independent oscilloscope measurement found [U] |
| Controller and motor | 40 ms command-to-force under Betaflight on the reference quad, dominated by the 39 ms motor constant | [A6, M] |
| Video, glass to glass | HDZero's white paper separates pixel and frame latency: analog ≈ 2/18.7 ms; HDZero 60 fps 3/19.6 ms, 90 fps 3/14.1 ms [A52, MS]; DJI O3 30 ms at 1080p/100 fps (Goggles 2), < 28 ms (V2) [A53, MS]; Walksnail 22 ms average [A54, MS]; independent high-speed-camera tests: HDZero ≈ 30 ms full frame, DJI V1 30–42 ms, Walksnail 30–60 ms, analog ≤ 19 ms [A55, A56, M] | |
| Goggle display lag | 23–55 ms by model | [A56, M] |
| Human | 220 ms visuomotor | [A9, M] |

## 5. Racing formats, rules and track elements

### 5.1 MultiGP [B1, B2, F]

Classes: **Open** — max 305 mm motor-to-motor, 4.35 V/cell, 800 g AUW, 25 sq ft gate (5 ft × 5 ft = 1.52 m). **Pro Spec (7 in)** — Pro Spec frame, 6S ≤ 2200 mAh, stator ≤ 2808, 7×4×3 props, 1200 g, 7 ft × 6 ft gate, LEDs required. **Whoop** — 65 mm ducted, 1S, 31 mm props, 30 in × 30 in gate. **Micro** — 3S, 1404 motors, 3.1 in props, 40 in × 48 in gate. **Freedom Spec (5 in)** — any 2207-class motor, 6S, 533 g minimum, firmware-enforced 18,000 rpm limit. **Mega** — 12 ft × 12 ft gate. VTX ≤ 25 mW. A "Spec 4S" class is no longer listed; a retailer names the T-Motor F40III 2306/2400 KV as a formerly approved Spec motor, so "Spec 4S" is historical.

Obstacles: 5×5 gate (vinyl mesh on PVC); double-gate tower; ladder (three stacked, elevated); tower (gate elevated 5 ft). Championship 7×6 set: gate; tower elevated 6 ft; ladder and topless ladder; dive gate elevated 15 ft with a slight entry angle; launch gate (panels face the ground); Split-S gate (up-and-over, flags 1.5 ft behind and beside); Offset-90. Hurdle 5 ft × 10 ft; "super hurdle" wall behind the start line. Gate + flag: side panel ≥ 5 ft tall, ≥ 1 ft wide. Tunnels are not on the page.

**Universal Time Trial** [B4, F]: five gates, no flags, fits inside a football field, standard 5×5 gates, counter-clockwise, fastest single lap, transponder timing recommended; a missed gate must be turned around for. UTT #7 (Tiny Whoop) uses five 19 in gates [B5].

**Global Qualifier** [B3, B6, B8, B12, F]: 10 gates and 5 flags, ranked by the fastest three consecutive laps; the 2020 setup guide stakes a grid from a triangle of 87.3/72.1/49.2 ft with stakes at 98.4 and 147.6 ft, positions measured from the left leg of each gate as entered (26.6, 22, 15, 30, 45 m: a 45 × 30 m base grid, *derived*); format: fixed 2-minute timer, 5–10 rounds, fastest three consecutive laps, the last lap counts if finished after the timer. "Race starts on the tone, timing starts at the start/finish gate"; "no arming unless on the field" [B11]. The 2025 track/build guide caps gates at 7 ft × 6 ft and flags at ≥ 8 ft, starts the lap at the first gate, with leg-to-leg distances such as 64, 57.6 and 72 ft [B7]. The full MultiGP rulebook (Google Doc) could not be fetched: ground-start, heat size and rejoin wording are [U]. The GQ gate coordinates are image-only [U].

Lap times: 2019 GQ fastest lap 10.069 s, best official 3-lap 35.715 s (11.4/12.9/11.5 s) [B10]; 2023 GQ second place 28.417 s for 3 laps [B9]. Speeds: "over 80 mph" (2016) and "exceeding 100 mph" (2026) [B13, B14]; DRL's league racer tops out at 85 mph [B20].

### 5.2 FAI F9U (Sporting Code Section 4, Vol. F9, 2019) [B15, F]

Weight ≤ 1 kg; motor axes within a 330 mm circle; battery ≤ 25.5 V (6S); motor tilt ≤ 15°; propellers ≤ 6 in, full-metal forbidden; VTX ≤ 25 mW. Circuit: 3D volume with start line, obstacles, finish line; ≥ 250 m total including all laps along the optimum centreline. Start: models side by side (0.5–1 m apart) or inverted-V; "Arm your quads", about 3 s later a brief sound signal, **no countdown**. Qualification ≥ 3 rounds, scored as fastest time for N laps or the average of the 3 best laps. Missed obstacle: lap not validated, may be re-attempted; a collision during the re-attempt disqualifies; a circuit cut must be rejoined with sufficient urgency. Crash: resume if able, otherwise motors off until race end. Software anti-turtle and level modes permitted. Obstacles must contrast with the background and be visible at 30 m on a standard FPV camera; crossed obstacles need ≥ 1.5 m free diameter, avoided ones ≥ 2.5 m. The 2025 World Games rules and the 2026 edition keep the same core limits per search snippets [B16, S].

### 5.3 DRL and DCL [B17–B22, F/S]

DRL Racer4: 2510/1250 KV motors, 7×4×3 props, 5S 70C, > 16 lb thrust, ≈ 1000 LEDs, 0–80 mph in under a second. Course pieces (Atomic, 2021–22): modular triangle/square/pentagon/hexagon gates on truss towers and a 12 ft LED finish gate. DRL SIM Tryouts: a week-long time-trial qualifier circuit. DCL 2016: 5-inch, 32 LEDs, 4S; 2018: 6-inch, ≥ 325 mm diagonal, COB LEDs, ≈ 800 g with ≈ 5 kg thrust.

## 6. Secondary aerodynamics

- **Frame drag.** Bauersfeld models f_body = −½·c_body·ρ·|A·v|·v with a per-axis area vector [A21, F]; no published CdA for a 5-inch racing frame. Faessler's lumped d_x,y ≈ 0.4–0.5 s⁻¹ [A5] and NeuroBEM's 1.5 N in-plane error of the quadratic model at 65 km/h [A7] bound the total. A CdA of 0.01–0.03 m² gives 2.5–7 N at 20 m/s [E].
- **Prop-wash / VRS.** v_h = √(T/2ρA) [A57]; a 650 g quad with four 5-inch discs gives v_h ≈ 7.0–7.2 m/s [E]. Small-rotor experiments: peak thrust loss and fluctuation at 1.2–1.3 v_h descent [A58]; a quadcopter becomes susceptible above ≈ 0.5 v_h [A59]; a neighbouring rotor advances VRS onset by ≈ 0.2 in descent ratio [A60]; Shetty & Selig give time-resolved thrust in descent for 9–11 in props [A20]. Bauersfeld's BEM includes an empirical VRS inflow model [A21]. Johnson's normalized VRS model and breakpoints are recorded in [HELI-01 §4](../../helicopter/HELI-01/README.md#4-ground-effect-vrs-and-autorotation).
- **Ground effect.** Cheeseman–Bennett T_IGE/T_OGE = 1/(1 − (R/4z)²) [A4; form confirmed in A61]. Sánchez-Cuevas et al. 2017 measured quad and octorotor thrust rising as the ground is approached and fitted a semi-empirical C–B variant including partial ground effect [A62, S; abstract only, full text paywalled]. Conyers 2018 found quadrotor augmentation non-monotonic with height and declared C–B inapplicable to multirotors [A63, S]. Closest to FPV scale: Lee et al. 2026, 102 mm rotor on a 2207 motor at 14,200 rpm: **+33 % at h/R = 0.5** (the C–B value, *derived*), ≈ 0 for h/R ≥ 2, and rotor–rotor interaction losses up to 13 % at h/R = 1 [A64, M]. gym-pybullet-drones uses G = k_G·k_F·(r_P/4h)²·Ω² [A65].
- **Dirty air.** Another quad's downwash: Gaussian wake with (r_P/4Δz)² scaling [A65]; PIV/force data on Crazyflie pairs [A66, A67]. No gate-wake data [E].
- **Gyroscopic and motor-inertia effects.** Included as τ_g in [A5] and as motor-acceleration yaw torque in [A8]; often neglected [A68]. With J_r ≈ 10⁻⁵ kg·m² and Ω̇ ≈ 2,500 rad/s in 0.035 s, J_r·Ω̇ ≈ 0.7 N·m per rotor transient, the size of control torques [E].
- **Saturation.** Mixer clipping, air mode, `motor_output_limit`, TPA and the rate cap [A31, A35, A36, A46].
- **Climb/descent asymmetry** arises from inflow-aware blade-element models [A6, A7]; a quadratic c_t model cannot produce it.

## 7. Motor, ESC and battery

- **Three-constant BLDC model** (Drela 2007) [A22, F]: Q_m = (i − i₀)/K_Q, v = Ω/K_V + i·R, K_Q = K_V in rad/s/V. Bauersfeld & Scaramuzza measured 44 motor–prop pairs: 70–85 % efficiency for recommended pairings, P_mot = Ω·(Q + m₀) + I²R; a 6-inch prop stalls a 2400 KV motor at high speed [A21, M]. The model ignores switching, timing, demag protection and PWM frequency.
- **ESC.** BLHeli_32 documents demag compensation, a 24 kHz default PWM with a variable-frequency option, sine start-up [A23, F]; AM32 advertises linear throttle, variable PWM and bidirectional DShot [A24, F]. Betaflight treats the DShot value as voltage duty [A25]. Whether a given ESC brakes the motor against the pack when the command drops (complementary PWM) is documented per firmware and is **[U]** for the specific units; the plan makes the ESC kind a declared field.
- **Battery.** Bauersfeld's one-time-constant Thevenin model [A21, M]: OCV polynomial with a₀ = 4.2 V, R_min = 4.5 mΩ/cell, τ_RC = 3.3 s, Peukert-type capacity loss, per-cell RMSE 43 mV (1.3 %), validated on a 4S 1.8 Ah pack at 100–800 W. Community internal resistance for fresh racing packs 2–6 mΩ/cell, rising with age [A32, weak]. At 100 A on 4S with 12–18 mΩ the sag is 1.2–1.8 V [E]. "C" ratings are manufacturer claims; Agilicious reports 110 A peak on a 1800 mAh 120C pack [A6]. No public measured OCV–SOC table for racing packs was found.

## 8. VFX and audio

### 8.1 Rendering facts (Godot 4.7.2 Compatibility)

- `GPUParticles3D` runs in Compatibility (added to the OpenGL3 renderer in November 2022) with box/sphere/heightfield collision, attractors and sorting, without 3D SDF collision, trails or `emit_particle()` [B42, B44, B39, F]; `CPUParticles3D` is the fallback [B43]. 4.3 declared Compatibility feature-complete with glow, MSAA, reflection probes and LightmapGI [B45]. No CompositorEffects, SSR, SDFGI or volumetric fog [B39]. Further project facts (per-instance transparency ignored, back faces lit by winding, headless dummy particle storage) are in [HELI-01 §7](../../helicopter/HELI-01/README.md#7-vfx-and-rendering-on-godot-472-compatibility).
- `Camera3D.fov` default 75° on the kept axis; with KEEP_HEIGHT 75° vertical is 107.5° horizontal at 16:9 [B37]; the setter rejects ≥ 180° [B38]. 120° horizontal at 16:9 is 88.5° vertical, 137° is 110° (*derived*). `hint_screen_texture` copies the screen after the opaque pass [B40]; the documented full-screen-quad post-process works in Compatibility [B41]; Pannini renders 150°+ naturally where rectilinear fails beyond ≈ 70° [B46].
- **Prop disc.** Freedom Spec caps motors at 18,000 rpm [B2]; a 1750 KV label measured 1840 KV on the bench [B69] (≈ 41,000 rpm no-load at 22.2 V, *calc*); a filtering guide quotes ≈ 26,000 rpm loaded for 2400 KV/6S and a 600 Hz dynamic-notch ceiling [B68, weak]. Race props run 18–35 krpm: 900–1,750 Hz blade-passing for tri-blades, 5–10 revolutions per 60 fps frame. Always a disc.
- **LEDs.** DRL ≈ 1000 LEDs [B17]; Pro Spec requires LEDs [B2]; DCL COB LEDs [B21]; gates must be visible at 30 m on an FPV camera [B15]. Emissive materials plus glow; avoid per-gate lights (per-mesh light limit in Compatibility) [B39].
- **Crash.** Betaflight flip-over-after-crash (mode 35, DShot) and PARALYZE [B52]; FAI: resume if able, otherwise motors off [B15].

### 8.2 Audio

- Cabell, McSwain, Grosveld 2016 (NASA Langley flyovers) [B54, F]: multicopter spectra "dominated by tones at harmonics of the blade passage frequency"; higher harmonics sometimes exceed the BPF; a Phantom 2 hover at ≈ 6 m measured 69 dBA (hexacopter 72); four distinct BPF lines near 200 Hz, one per rotor, which split in forward flight (rear rotors faster); prominent harmonics at 500–1,000 Hz dominate the A-weighted level; motor tones up to 5 kHz; LAmax at a 15 m flyover 63 dBA (quad), 68 (hex), 72 (model airplane).
- Intaratep et al. 2016 (Phantom II, microphone at 1.51 m) [B55, F]: at 3,840 rpm shaft 64 Hz and BPF 128 Hz, BPF peaks ≈ 45 dB sustained to the 4th harmonic; tones dominate to ≈ 6 kHz; motor noise at 600–6,000 Hz with unloaded-motor tones at 832 and 2,240 Hz; a broadband hump above 600 Hz ≈ 10 dB over the floor, rolling off after 6 kHz; 2 → 4 rotors adds 3–8 dB to tones and 6–8 dB broadband; OASPL ≈ 70 dBA at take-off thrust and ≈ 80 dBA at maximum.
- NASA isolated-rotor tests: up to 8 dB between rotors, motors significant [B56, S]; nearby airframe surfaces add BPF-harmonic tones [B57, S].
- Racing-quad scaling (*derived*): 14-pole motor (Betaflight default `motor_poles` 14 [B53]) → 7 pole pairs; at 25,000 rpm tri-blade: shaft 417 Hz, BPF 1,250 Hz, electrical 2,917 Hz; at 35,000: 583/1,750/4,083 Hz.
- Synthesis recipe: per motor, shaft tone plus BPF harmonic stack (first four sustained, decaying above), an electrical tone, a 600–6,000 Hz broadband hump, per-motor detune, +6–8 dB broadband for four rotors; levels ≈ 70–80 dBA at 1.5 m, ≈ 63 dBA at 15 m. In goggles the pilot hears the quad through the air from the pilot's position (no onboard microphone feed): one ground-listener mix for both views.

## 9. Input

- **Radio conventions** [B51, B52, B62, F]: stick arming is the default; a switch disables it; throttle below `min_check` allows arming; motors idle when armed; racing throttle gimbals are non-centering (sold with "throttle tension" instead of a centring spring). A sim must read the raw 0…1 axis with min/max calibration and no centre dead-band.
- **EdgeTX USB joystick** [B60, B61, F]: the mixer runs at 1,000 Hz in joystick mode with RF off; Classic mapping ch1–3 → X/Y/Z, ch4–6 rotations, ch7 dial, ch8 slider, ch9–32 → buttons 1–24; button modes Normal/Pulse/SWEmu/Delta with 2–8 positions; VID 1209 / PID 4F54, 8 axes at 11 bits, 24 buttons; on Linux evdev ch7 is ABS_THROTTLE. The USB report interval is not documented [U]; measure with `evhz`.
- **ExpressLRS** [B58, B59, F]: packet rates in §4.3; ≥ 333 Hz needs > 400 kbaud, F1000 needs 1.87 Mbaud.
- **Rates import**: `diff rates` / `dump rates` text [B50]; formulas in §4.1.

## 10. FPV camera, view and OSD

- **Cameras** [B27–B29, F]: RunCam Phoenix 2: 1/2 in CMOS, 2.1 mm, "FOV 155° (4:3)", 4:3/16:9 and PAL/NTSC switchable, 1000TVL. Caddx Ratel 2: 1/1.8 in, 2.1 mm, 165° (axis unstated), 8 ms latency. DJI O4 Air Unit Pro: 1/1.3 in, 155°, 12 mm equivalent; O4: 1/2 in, 117.6°; 1080p up to 100 fps; 15/20 ms in racing mode. Marketed 155–165° values are diagonal fisheye-type figures; a rectilinear 2.1 mm lens on a 1/3 in sensor would be ≈ 110° diagonal (*calc*). The camera plan quotes two RunCam 2.1 mm lenses as H128°/V91°/D165° and H115°/V83°/D150° ([camera-views §5.3](../../../plans/camera-views.md#53-onboard--fpv-v3)).
- **Tilt** [B33, F]: beginners 15–25°, freestyle 30–45°, racing 40/45–60°, "top racers often 50° or more"; steeper tilt means more throttle to hold the horizon and faster flight.
- **Goggles** [B30–B32, F]: DJI Goggles 3: 44° per screen, 1920×1080, 100 Hz; Goggles 2: 51°; Skyzone SKY04X and Fatshark HDO2: 46°, 1280×960.
- **What sims do** [B34–B36, F]: Velocidrone exposes a horizontal FOV of 65–137° ("usually 115–127°"), camera angle (≈ 30° typical), a VTX noise slider with Random or Distance (noise grows with distance from start, low altitude, occlusion), fisheye yes/no, a costly True Lens mode with 2.1/2.3/2.5 mm lenses, motion blur levels and a Betaflight flight-controller option with PID/rate profiles. Liftoff users recommend FOV ≥ 138 ("real camera ≥ 142° in 4:3", props visible at the edges) and call the fisheye option useless; its developers admitted fisheye produced black corners and that FOV ignored lens distortion (2017); analog noise toggles with C. Both are effectively rectilinear with a wide slider.
- **Betaflight OSD** [B47, F]: grid PAL 30 × 16, NTSC 30 × 13, HD 53 × 20 (MSP DisplayPort); three OSD profiles; three timer alarms; a Warnings element aggregating error sources; common elements: battery voltage/average cell, mAh drawn, current, RSSI/link quality, flight timer, flight mode, crosshair, craft name, throttle, VTX channel.

## 11. Timing systems and race logic

- **RSSI timers** [B23–B25, F]: RotorHazard nodes switch to "Crossing" when RSSI ≥ EnterAt and back to "Clear" below ExitAt (hysteresis); the lap timestamp is the strongest filtered RSSI inside the crossing window; adaptive calibration learns thresholds from marshalled races; suggested capture distances 1.5–3 m (EnterAt) and 6–9 m (ExitAt); thresholds lowered at race start; a Minimum Lap Time highlights or discards early passes. ImmersionRC LapRF detects the VTX energy with gate-shaped antenna beams, 10–600 mW, 8 pilots precise/16 reduced. IR transponders (I-Lap) are detected at 6 m in sun/10 m shade with a 7-digit ID [B26].
- **Start sequence** [B24, B15, B11]: RotorHazard prestage tones each second (3-2-1-Go), minimum staging time, random staging 0–5 s (hides the clock and shows "Ready"), one beep on crossing entered, two on exit. FAI: "Arm your quads", ≈ 3 s, single tone, explicitly no countdown. MultiGP GQ: race starts on the tone.
- **Results logic** [B24, B12]: RotorHazard win conditions: Most Laps in Fastest Time, Most Laps Only (with overtime), First to X Laps, Fastest Lap, Fastest 3 Consecutive Laps; clock modes Fixed Time with grace period or No Time Limit; first-crossing modes Hole Shot (first crossing starts lap 1), First Lap (first crossing ends lap 1), Staggered Start. GQ: fastest three consecutive laps in a fixed 2-minute window. Ghost racing exists as Velocidrone's Nemesis mode [B63].
- **Sim detection volume** [E from B1, B2, B15]: an oriented rectangle the size of the opening with a direction check; FAI's ≥ 1.5 m free diameter is the lower bound of any gate.

## 12. Existing simulators and open implementations

| Simulator | Advertised physics | Evidence |
| --- | --- | --- |
| Velocidrone [A70, A71] | proprietary physics; "real aerodynamics calculations for prop thrusts, NACA curves"; battery V/I; "real ESC code for throttle ramping", braking; motor current, KV, coil resistance, torque; frame drag; Betaflight-style PID and rate profiles | marketing; no FC-in-the-loop confirmed |
| Liftoff [A72–A74] | Physics 3.0 thrust from "tens of thousands" lab points; 4.0 drag from an aerodynamic profile at 42 angles, lift; ground effect; 6.0 motor power limits; left Unity's built-in physics (2022) | developer blog |
| DRL Simulator [A75] | "one-to-one physics with data from real-life drones", Racer4 | store page |
| Uncrashed [A76] | "settings based on real values"; gravity/air-friction/prop-efficiency sliders | store page |
| TRYP FPV [A77] | "PID loop-based flight simulation", "digital twin" calibration claim | store page |
| FPV.SkyDive (Orqa) [A78] | "realistic physics", rate calibration | store page |
| FPV Freerider [A79] | ground-effect simulation (2018), rates in deg/s | changelog |

No quantitative fidelity study of any commercial simulator was found; reviews are opinion [A80, A81]. Research simulators: Flightmare [A12] (first-order thrust lag, diagonal rotor drag, RK4), RotorS [A13, F] (k_n·ω², air drag −|ω|·k_d·v_⊥, rolling moment, first-order up/down filter; PX4's Gazebo motor plugin descends from it), gym-pybullet-drones [A65] (k_F, k_T, Σω-scaled drag, ground effect, downwash), Agilicious [A6]. **Betaflight SITL** [A82, F]: `make TARGET=SITL`, Gazebo over UDP 9002/9003 (flight-dynamics in, motors out), RealFlight bridge; SITL Forge [A83] and SimITL [A84] wrap the real firmware in the loop. All firmware and sims listed under GPL (Betaflight, INAV, ArduPilot, RotorS derivatives where applicable) are study-only for this MIT application: implement from published equations and documentation; never copy code.

## 13. Code seams on 2026-10-13

These are line references to the working tree on this date, re-checked after the concurrent CAM-02, SM-03/04, CR-01d and TT-11 changes landed; verify them before editing.

| Seam | Today | Multirotor need |
| --- | --- | --- |
| Body state | [`physics/rigid_body.gd:13-20`](../../../../app/physics/rigid_body.gd#L13), 13 values; `RB.derivative :77` takes a summed rotor momentum `h` | Reusable unchanged |
| Extra states | [`sim/simulation.gd`](../../../../app/sim/simulation.gd): `inputs` hard-sized to 4 (`:24`); `step :151`; `pre_step.call :172` advances `aux` once per tick; joint `continuous_evaluate.call :180,227` returns `{loads, derivative, rotor_momentum}`; optional event-bounded `continuous_step.call :239`; `post_step.call :251` for scenery collision | Four rotor speeds + pack in `continuous`; controller in `aux`; arm/mode/race in `modes` |
| Coupled-shaft template | [`sim/flight_session.gd`](../../../../app/sim/flight_session.gd): `BATTERY_LAYOUT :12`, `ELECTRIC_MAX_STEP_RATIO :16`, `_electric_step_supported :79-99`, `AUX_LAYOUT :252`, `set_collision_world :467`, `_prepare_aircraft :584` (trims level at `:611`), `_configure_continuous_callbacks :663`, `_physics_process :907`, `touches_ground :958`, `_resolve_collision_step :972`, `_crash :1018`, `reset :1032`, `_reset_airborne_start :1067`, `_reset_selected_runway_start :1118`, `rates_active :1236`, `flown_commands :1243`, `_wash_loads :1280`, `_wheel_evaluate :1318`, `_settled_continuous :1377`, `_rotor_index :1397`, `_coupled_rpm :1428`, `_coupled_response :1451` (single-rotor torque balance + `RotorCoupling.response`), `_coupled_evaluate :1546`, `_append_battery_rates :1561`, `_electric_step :1578`, `_deflections :1628`, `_pre_step :1646`, `trace_meta :1793`, `checkpoint :1944`, `restore_checkpoint :2004`; `sim.modes = [engine_running, rng_state]` (`:186-188`, `:348`); `CRASH_HOLD_S 1.5` (`:307`); replay classes [`tests/replay_policy.gd:8`](../../../../app/tests/replay_policy.gd#L8) | Same nine touch points, N rotors |
| Runway start | `RUNWAY_AIRCRAFT_IDS := ["jensen-das-ugly-stik-60", "turbo-lumber-evolution"]` (`flight_session.gd:236`, TT-11); [`physics/ground_start.gd:43`](../../../../app/physics/ground_start.gd#L43) Newton static solve on gear | Pad start on legs generalizing the static solve |
| Force assembly | [`physics/dynamics.gd`](../../../../app/physics/dynamics.gd): `rotor_momentum :18` (one axis), `_components_from_air :79` (`Aero.loads` + one `Propulsion.loads` + optional `Slipstream.loads`); [`physics/propulsion.gd`](../../../../app/physics/propulsion.gd): `coefficient :34` (J ≤ table[0] → static value), `source_kind :66`, `is_electric :73`, `has_rotor_dynamics :78`, `thrust_torque :504`, `loads :519` (turbine dispatch `:521`), `_tilted_loads :538` | One multirotor evaluate; N rotor loads; J < 0 branch |
| Gyroscopics | [`physics/rotor_coupling.gd:13`](../../../../app/physics/rotor_coupling.gd#L13): single axis, single inertia | N signed parallel rotors |
| Electric motor | [`physics/electric_motor.gd:27`](../../../../app/physics/electric_motor.gd#L27) `_evaluate_validated`: `I = max(0,(d·V−E)/Rm)` when duty > 0 (one-quadrant); `Q = kt·I − kt·I0`; battery current = duty·I | `synchronous` kind (signed current) |
| Battery | [`physics/electric_supply.gd`](../../../../app/physics/electric_supply.gd): `evaluate :17`, single-motor closed form `:88-93`, `_interpolate_ocv :199` (piecewise-linear OCV(SOC)), series R_pack, auxiliary current | Shared-bus solve for N motors |
| Loader | [`physics/aircraft_data.gd`](../../../../app/physics/aircraft_data.gd): `validate_and_derive :141`, `_validate_legacy :173`; wing area 0.05–3 m² and span 0.3–4 m (`:181-182`); `start.level_speed` 5–60 m/s (`:205`); stable-airplane signs (`:38`, `:241`); `_landing_gear :332`; `_propulsion :794`; `thrust_angles` ±10° (`:835`, `:905`); "gears and reverse sense are unsupported" (`:859`); `_electric_propulsion :860`; `_turbine :1193`; `_controls :1272` with required `max_throw` (`:1276-1280`); `_crash_hull :1529`; `_crash_hull_components :1559` (CR-01d). Contract: [`physics/aircraft_contract.gd:139`](../../../../app/physics/aircraft_contract.gd#L139) `_validate_relations`; enums in [`data/schema/aircraft-contract-v2.json`](../../../../app/data/schema/aircraft-contract-v2.json); schema generated by `research/aircraft-standardization/build_schema.py` | Separate multirotor derive path |
| Trim | [`physics/trim.gd:60-62`](../../../../app/physics/trim.gd#L60): `level`/`glide` only, V > 0; `solve_linear :285`; [`tests/test_trim_integrity.gd:53`](../../../../app/tests/test_trim_integrity.gd#L53) refuses `hover` | Hover equilibrium (closed form) |
| Input | [`input/rc_input.gd`](../../../../app/input/rc_input.gd): `SmokeAux` (`:14`), `AXES 10` (`:15`), `ARM_THROTTLE 0.05` (`:17`), AETR `DEFAULT_PROFILE :22`, `GAMEPAD_PROFILE :33`, `on_button :139`, `poll(read_axis, dt, read_button) :153` (one auxiliary axis/button binding for the smoke pump, `:160-162`), `normalize_throttle :180`, `throttle_position :201`, `sticks :209`; [`input/smoke_aux.gd`](../../../../app/input/smoke_aux.gd) (SM-03/04); [`input/keyboard.gd:9`](../../../../app/input/keyboard.gd#L9) `read_raw`; [`input/commands.gd`](../../../../app/input/commands.gd): `step_commands :27`, `expo :39`, `shape_sticks :47`, `surface_deflections_deg :71` | No-centre throttle; named switch mapping generalizing the smoke binding; `modes` for arm/mode |
| Ground | [`physics/ground_contact.gd:73,179`](../../../../app/physics/ground_contact.gd#L73): spring-damper + tyre friction (`loads`) + anchors (`anchor_step`); without a gear module every hull touch is terminal (`flight_session.gd:958`); four zero-steer contacts pass the topology check | Isotropic leg friction |
| Crash | `flight_session.gd:907-1026` detection, collision resolution and `_crash`; [`render/crash/director.gd`](../../../../app/render/crash/director.gd): `configure :27`, `_start :69`, labels read at `:92`, `component_for :150-166` (CR-01d label, span-region fallback), `reset :199`; [`severity.gd:4-10`](../../../../app/render/crash/severity.gd#L4) cuts 0.5/2.5/25/150 J/kg; [`physics/impact_snapshot.gd`](../../../../app/physics/impact_snapshot.gd), [`hull_crossing.gd`](../../../../app/physics/hull_crossing.gd); [`tests/test_crash_hull_labels.gd`](../../../../app/tests/test_crash_hull_labels.gd) (untracked on this date) | Disc ring; labels; disarm; respawn |
| Scenery collision | [`scenery/collision_world.gd`](../../../../app/scenery/collision_world.gd): `FORMAT "openrc-collision-world v1"` (`:13`), `CELL_SIZE_M 32` (`:14`), `build :26`, `nearby :72`, `_add_box_at_down :475`, `_add_capsule :496`, `_proxy_is_valid :573`; [`scenery/collision_setup.gd:12`](../../../../app/scenery/collision_setup.gd#L12); [`sim/scenery_collision.gd`](../../../../app/sim/scenery_collision.gd): thresholds `:19-21` (`soft_foliage_impulse` 22 m/s, `frangible_impulse` 12, `light_airframe_impulse` 14; `hard_terminal` always), `contacts :62`, `first_hit :171`, `apply_response :251`, terminal rule `:318-322`, kernels `_segment_box :354`, `_segment_capsule :408` | Gate proxies; `race_frangible`; separate plane-crossing detector |
| Catalog | [`app_state/aircraft_catalog.gd:20-64`](../../../../app/app_state/aircraft_catalog.gd#L20) `ENTRIES` (flyable/experimental/preview); builder matched by ID in [`render/airplane.gd:35`](../../../../app/render/airplane.gd#L35) `build`, datum `:60` | PREVIEW first |
| Render and camera | [`render/frames.gd`](../../../../app/render/frames.gd); [`main.gd`](../../../../app/main.gd): `CameraRig` preload (`:16`, CAM-02), `--view` (`:261`), `PropellerBlur.attach` (`:414`), `crash_auto_restart = false` (`:470`), prop phase from `sim.aux[0]` (`:529-531`), `EngineSound.update` (`:535`), smoke `advance` (`:579`), keys R/C/Z (`:749`, `:758`, `:781`), `PilotCamera.create` and `_rig = CameraRig.new` (`:1056-1057`), `_render_pose :1091` applying one `propeller.rotation.z` (`:1094`); [`render/camera/camera_rig.gd`](../../../../app/render/camera/camera_rig.gd) `VIEWS = ["pilot", "chase", "orbit", "closeup"]` (`:16`; untracked on this date), [`render/pilot_camera.gd:54-58`](../../../../app/render/pilot_camera.gd#L54) `aim` with the inspect branch; builders return `{root, propeller, hinges, aircraft_id, has_propeller}` ([`render/airplane.gd:3-8`](../../../../app/render/airplane.gd#L3)); blur [`render/propeller_blur.gd`](../../../../app/render/propeller_blur.gd) `attach :58`, reads `aux[0]` at `:458` | N propellers; per-rotor telemetry; `fpv` view in the rig; OSD |
| Overlays | [`render/overlays/overlay_manager.gd:206`](../../../../app/render/overlays/overlay_manager.gd#L206) `snapshot` reads `aux[0]`; `telemetry.gd`, `transmitter.gd`, `flight_data.gd`, `warnings_bar.gd`, `wind.gd` | OSD overlay; race HUD |
| Audio | [`audio/flight_audio.gd`](../../../../app/audio/flight_audio.gd) `configure :17`, `snapshot :39` (`aux[0]` at `:46`); [`audio/soundscape.gd`](../../../../app/audio/soundscape.gd) `MAX_VOICES 14` (`:10`), kind → `motor_electric`, `motor_turbine` or `motor_combustion` (`:50`), one motor/prop/airframe voice (`:51-53`) | Four motor voices |
| Tests and tools | `test.sh`: generator `--check`s, float64 guard over `sim/` and `physics/`, every `tests/test_*.gd` as a SceneTree script with a 60 s timeout, per-catalog trace runs; goldens [`tests/golden_flights.gd`](../../../../app/tests/golden_flights.gd) (`openrc-golden v1`; record and replay refuse a coupled shaft at `:29` and `:73`), recorder `tests/record_golden.gd`; trace [`sim/trace.gd:11`](../../../../app/sim/trace.gd#L11) `FORMAT "openrc-trace v3"` with extensions to v8; benches [`tests/bench_physics.gd:31`](../../../../app/tests/bench_physics.gd#L31) (500 µs budget), `bench_regimes.gd`, `bench_wind.gd`, `benchmark_landscape_collision.gd` | Golden format for coupled tails; `MR_COLUMNS`; `bench_multirotor.gd` |
| Budgets | Tick ≤ 500 µs (Gate P open); Stik 200–445 µs ([H15](../../simulation-state/H15/README.md)); electric Stik with battery 558–562 µs on the EL2a-P1 host ([EL2a-P1](../../propulsion/EL2a-P1/README.md)); local strips 2.3–3.6 µs per element ([H12](../../simulation-state/H12/README.md)) | Closed-form four-rotor model under the Stik's cost |

## 14. Validation datasets

| Dataset | Content | Rates | Use |
| --- | --- | --- | --- |
| NeuroBEM [A7, A85] | 96 flights, 1 h 15 min, ≤ 65 km/h; position, quaternion, velocity, acceleration, ω, ω̇, four motor speeds and derivatives, battery voltage; mass 0.772 kg, J = diag(0.0025, 0.0021, 0.0043) | 400 Hz (onboard 1 kHz) | DR-38 held-out force/torque replay |
| Blackbird (MIT) [A86] | 168–176 flights, 10 h, 0.5–13.8 m/s, motor speeds, IMU, mocap, images | 100 Hz IMU, ≈ 190 Hz motor rpm, 360 Hz mocap | secondary |
| UZH-FPV [A87] | 27 sequences, > 10 km, human-piloted; cameras, IMU, laser ground truth; 2023 Split-S to 100 km/h | — | trajectories only (no motor/battery) |
| Swift race data [A8] | mocap of human-vs-AI races (Zenodo 10.5281/zenodo.7955278) | — | lap-time anchors |
| Betaflight blackbox [A88, A38] | gyro, setpoint, P/I/D/F, rcCommand, motors, vbat, current, acc, eRPM via debug modes; `blackbox_sample_rate` default 1/4 (2 kHz); decoders in blackbox-tools | 8 kHz ÷ 1…16 | DR-40 owner data |

## Derived checks

Output of `python3 -I research/drone-racing/dr-01/derived_checks.py` (ρ = 1.225 kg/m³, g = 9.81 m/s²; every input is a typical/estimated value stated in the script):

```
R=64.8 mm  A=131.79 cm2/rotor  T_hover=1.59 N/rotor  disc loading=121 N/m2  v_h=7.0 m/s
Ct_static=0.171 (T_max 14.7 N at 30000 rpm)  T/W=9.2  hover rpm=9874 (0.33 of max)
rpm   9874: blade-pass    494 Hz, commutation   1152 Hz, rev/tick 0.69, rev/frame(60 fps) 2.74, tip speed 67 m/s (M 0.20)
rpm  20000: blade-pass   1000 Hz, commutation   2333 Hz, rev/tick 1.39, rev/frame(60 fps) 5.56, tip speed 136 m/s (M 0.40)
rpm  30000: blade-pass   1500 Hz, commutation   3500 Hz, rev/tick 2.08, rev/frame(60 fps) 8.33, tip speed 203 m/s (M 0.59)
theta(0.75R)=19.7 deg, theta(tip)=15.0 deg for 4.3 in helical pitch
Re(0.75R, 25 kRPM, c=14 mm)=1.21e+05
hover: Q=9.6 mN m, I=3.5 A/motor (14 A pack), back-EMF 4.03 V, duty 0.28 at 15.2 V
full: Q=89 mN m, I=24 A/motor (95 A pack), P_elec 1448 W, pack sag 1.14 V at 12 mOhm
J=7.0e-06 kg m2, cq=9.01e-09 N m s2, motor time constant about hover ~25.8 ms (dt/tau=0.16)
explicit-step ratio dt*kt^2/(Rm*J) (flight_session.gd ELECTRIC_MAX_STEP_RATIO = 0.25):
  2306 2450KV Rm 0.06 J 7e-6: ratio=0.15, tau_em=27.6 ms
  2306 2450KV Rm 0.04 J 7e-6: ratio=0.23, tau_em=18.4 ms
  2207 1750KV Rm 0.09 J 7e-6: ratio=0.20, tau_em=21.2 ms
  2306 2450KV Rm 0.06 J 4e-6: ratio=0.26, tau_em=15.8 ms
  2306 2450KV Rm 0.06 J 1e-5: ratio=0.11, tau_em=39.5 ms
lambda_h=0.105; inflow time constant 0.849/(4 lambda Omega)=1.96 ms (quasi-static at dt=4.17 ms)
ground effect z=0.05 m (z/R=0.77): T_IGE/T_OGE=1.12
ground effect z=0.08 m (z/R=1.24): T_IGE/T_OGE=1.04
ground effect z=0.15 m (z/R=2.32): T_IGE/T_OGE=1.01
ground effect z=0.30 m (z/R=4.63): T_IGE/T_OGE=1.00
VRS window (Johnson -0.45..-1.5 v_h): 3.2..10.5 m/s descent at low forward speed
V=10 m/s: J=V/(nD) at 25 kRPM=0.19, mu=V/(Omega R)=0.06, frame drag 0.7 N (0.12 g)
V=25 m/s: J=V/(nD) at 25 kRPM=0.46, mu=V/(Omega R)=0.15, frame drag 4.6 N (0.72 g)
V=44 m/s: J=V/(nD) at 25 kRPM=0.82, mu=V/(Omega R)=0.26, frame drag 14.2 N (2.23 g)
one tick at 30 m/s = 12.5 cm (sub-tick gate-plane interpolation needed for ms timing)
X-frame lever 77.8 mm; roll moment from +-1.6 N per pair = 249 mN m; with Ixx 2.5e-3 kg m2: 100 rad/s2 (5704 deg/s2)
differential rpm +-3000: net rotor momentum 4.40 mN m s; precession at 1000 deg/s = 76.8 mN m
audio at 25000 rpm: shaft 417 Hz, blade-pass 1250 Hz, electrical 2917 Hz
audio at 35000 rpm: shaft 583 Hz, blade-pass 1750 Hz, electrical 4083 Hz
stick   actual(70/670/0.54)  actual(70/670/0, firmware default)  betaflight(1.0/0.70/0)
0.10        10 deg/s        13 deg/s        22 deg/s
0.25        35 deg/s        55 deg/s        61 deg/s
0.50       109 deg/s       185 deg/s       154 deg/s
0.75       265 deg/s       390 deg/s       316 deg/s
1.00       670 deg/s       670 deg/s       667 deg/s
prop disc coverage N c/(2 pi r) for c=14 mm: at 0.7R 15 %, at 0.2R 52 %
120 deg horizontal FOV at 16:9 -> vertical 88.5 deg; 137 deg -> 110.0 deg
```

Reading: hover sits at a third of maximum rpm with thrust-to-weight ≈ 9 (race build); the motor constant of 16–40 ms brackets the identified 33–39 ms; the inflow constant is below the tick; the rotor turns 0.7–2.1 revolutions per tick and 3–8 per frame; the Cheeseman–Bennett value at z/R = 0.5 is the measured +33 %; VRS is reachable in a 3–10 m/s vertical descent; frame drag reaches ≈ 2 g at 44 m/s for a 0.012 m² area; the Actual-rates default is 670 deg/s at full stick with 70 deg/s centre sensitivity.

## Bibliography A: physics, data and firmware

1. Mahony, Kumar, Corke (2012). Multirotor aerial vehicles. IEEE RAM 19(3). https://doi.org/10.1109/MRA.2012.2206474 [F]
2. Bangura, Mahony (2012). Nonlinear dynamic modeling for high performance control of a quadrotor. ACRA. https://researchportalplus.anu.edu.au/en/publications/nonlinear-dynamic-modeling-for-high-performance-control-of-a-quad/ [S]
3. Kai et al. (2017). Nonlinear feedback control of quadrotors exploiting first-order drag effects. https://hal.science/hal-01544740 [S; author list unverified, page bot-blocked]
4. Leishman (2006). Principles of Helicopter Aerodynamics, 2nd ed. Cambridge UP. [not fetched]
5. Faessler, Franchi, Scaramuzza (2018). Differential flatness of quadrotor dynamics subject to rotor drag. RA-L 3(2). https://arxiv.org/abs/1712.02402 [F]
6. Foehn et al. (2022). Agilicious. Science Robotics 7(67). https://arxiv.org/abs/2307.06100 [F]
7. Bauersfeld et al. (2021). NeuroBEM. RSS. https://arxiv.org/abs/2106.08015 [F]
8. Kaufmann et al. (2023). Champion-level drone racing using deep reinforcement learning. Nature 620. https://pmc.ncbi.nlm.nih.gov/articles/PMC10468397/ [F]
9. Pfeiffer, Scaramuzza (2021). Human-piloted drone racing. RA-L 6(2). https://arxiv.org/abs/2103.04672 [F]
10. Harrell. Mini Quad Test Bench motor data. https://www.miniquadtestbench.com/assets/components/motordata/motorinfo.php?uid=282 [F]
11. Eschmann et al. (2024). System identification of quadrotors subject to motor delays. https://arxiv.org/abs/2404.07837 [S]
12. Song et al. (2020). Flightmare. https://arxiv.org/abs/2009.00563 [S]
13. Furrer et al. (2016). RotorS motor plugin. https://github.com/ethz-asl/rotors_simulator/blob/master/rotors_gazebo_plugins/src/gazebo_motor_model.cpp [F]
14. UIUC Propeller Data Site, vol. 1. https://m-selig.ae.illinois.edu/props/volume-1/propDB-volume-1.html [F]
15. UIUC Propeller Data Site, vol. 2. https://m-selig.ae.illinois.edu/props/volume-2/propDB-volume-2.html [F]
16. Brandt, Selig (2011). AIAA 2011-1255. https://m-selig.web.engr.illinois.edu/pubs/BrandtSelig-2011-AIAA-2011-1255-LRN-Propellers.pdf [F]
17. Tyto Robotics database guide. https://www.tytorobotics.com/blogs/articles/how-to-use-the-database-for-drone-motors-propellers-and-escs [F]
18. APC Propellers, engineering design process. https://www.apcprop.com/?p=231 [F]
19. QBlade forum, validation of APC data. https://qblade.org/qblade-forum/topic/validation-of-apc-propeller-performance-data/ [S]
20. Shetty, Selig (2011). AIAA 2011-1254. https://m-selig.web.engr.illinois.edu/pubs/ShettySelig-2011-AIAA-2011-1254-LRN-VSR-Props.pdf [F]
21. Bauersfeld, Scaramuzza (2022). Range, endurance, and optimal speed estimates for multicopters. RA-L 7(2). https://arxiv.org/abs/2109.04741 [F]
22. Drela (2007). First-order DC electric motor model. http://web.mit.edu/drela/Public/web/qprop/motor1_theory.pdf [F]
23. BLHeli_32 manual Rev32.x. https://git.bertfpv.com/englebert/BLHeli/raw/branch/master/BLHeli_32%20ARM/BLHeli_32%20manual%20ARM%20Rev32.x.pdf [F]
24. AM32 firmware. https://github.com/am32-firmware/AM32 [F]
25. Betaflight PID Tuning Tab. https://betaflight.com/docs/wiki/app/pid-tuning-tab [F]
26. Betaflight 4.2 Tuning Notes. https://betaflight.com/docs/wiki/tuning/4-2-Tuning-Notes [F]
27. Betaflight DShot. https://betaflight.com/docs/wiki/guides/current/Dshot [F]
28. Betaflight pg/motor.c (master, 2026-10-13). https://raw.githubusercontent.com/betaflight/betaflight/master/src/main/pg/motor.c [F]
29. Betaflight Dynamic Idle. https://betaflight.com/docs/wiki/guides/current/Dynamic-Idle [F]
30. Liang. Turtle mode setup. https://oscarliang.com/setup-turtle-mode-flip-over-after-crash/ [S]
31. Betaflight flight/mixer_init.c. https://raw.githubusercontent.com/betaflight/betaflight/master/src/main/flight/mixer_init.c [F]
32. UAVmodel blog, LiPo internal resistance (community, unverified). https://blog.uavmodel.com/lipo-battery-internal-resistance-testing/ [S]
33. Betaflight fc/rc.c. https://raw.githubusercontent.com/betaflight/betaflight/master/src/main/fc/rc.c [F]
34. Betaflight fc/controlrate_profile.c. https://raw.githubusercontent.com/betaflight/betaflight/master/src/main/fc/controlrate_profile.c [F]
35. Betaflight Rate Calculator. https://betaflight.com/docs/wiki/guides/current/Rate-Calculator [F]
36. Betaflight flight/pid.c, pid.h. https://raw.githubusercontent.com/betaflight/betaflight/master/src/main/flight/pid.c [F]
37. Betaflight pg/rx.c. https://raw.githubusercontent.com/betaflight/betaflight/master/src/main/pg/rx.c [F]
38. Betaflight Blackbox logging and usage. https://betaflight.com/docs/wiki/guides/current/Black-Box-logging-and-usage [F]
39. Betaflight Configuration Tab. https://betaflight.com/docs/wiki/app/configuration-tab [F]
40. Betaflight 4.3 Tuning Notes. https://betaflight.com/docs/wiki/tuning/4-3-Tuning-Notes [F]
41. Betaflight sensors/gyro.h. https://raw.githubusercontent.com/betaflight/betaflight/master/src/main/sensors/gyro.h [F]
42. Betaflight pg/dyn_notch.c. https://raw.githubusercontent.com/betaflight/betaflight/master/src/main/pg/dyn_notch.c [F]
43. Betaflight flight/dyn_notch_filter.c. https://raw.githubusercontent.com/betaflight/betaflight/master/src/main/flight/dyn_notch_filter.c [F]
44. Betaflight pg/rpm_filter.c. https://raw.githubusercontent.com/betaflight/betaflight/master/src/main/pg/rpm_filter.c [F]
45. See A40.
46. Betaflight Mixer. https://betaflight.com/docs/wiki/guides/current/Mixer [F]
47. Betaflight Dynamic D. https://betaflight.com/docs/wiki/guides/current/Dynamic-D [F]
48. Betaflight PID Tuning Guide. https://betaflight.com/docs/wiki/guides/current/PID-Tuning-Guide [F]
49. ExpressLRS Lua docs. https://www.expresslrs.org/quick-start/transmitters/lua-howto/ [F]
50. ExpressLRS README. https://github.com/ExpressLRS/ExpressLRS [F]
51. Hackaday (2021). ExpressLRS. https://hackaday.com/2021/01/19/expresslrs-open-source-low-latency-long-range-rc-protocol/ [S]
52. Divimath/HDZero (2022). Latency analysis, analog vs HDZero. https://www.helicomicro.com/wp-content/uploads/2022/09/WhitePaper-LatencyAnalysis-AnalogvsHDZero.pdf [F]
53. DJI (2022). O3 Air Unit launch. https://www.dji.com/newsroom/news/dji-launches-o3-air-unit [F]
54. GetFPV, Walksnail Avatar HD VTX. https://www.getfpv.com/walksnail-avatar-hd-vtx.html [S]
55. fpv24 (2023). HD FPV comparison. https://www.fpv24.com/en/blog/118/hd-fpv-comparison [S]
56. IntoFPV threads on photodiode latency tests. https://intofpv.com/archive/index.php/thread-22188.html [S]
57. Talwar et al. (2019). Quadcopter descent avoiding VRS. https://arxiv.org/abs/1909.09069 [S]
58. Early onset prediction for rotors in VRS (2020). https://www.researchgate.net/publication/345142311 [S]
59. VRS descent experiments with a quadcopter (2025). https://www.sciencedirect.com/science/article/pii/S1877750325000055 [S]
60. VRS for side-by-side propellers (2026). Phys. Fluids 38. https://pubs.aip.org/aip/pof/article/38/3/035136/3384014 [S]
61. Hoverflie (2026), Cheeseman–Bennett form. https://arxiv.org/abs/2608.06707 [S]
62. Sánchez-Cuevas, Heredia, Ollero (2017). Int. J. Aerosp. Eng. 2017:1823056. https://idus.us.es/handle/11441/94910 [S; full text paywalled]
63. Conyers (2018). PhD thesis, U. Denver. https://digitalcommons.du.edu/etd/1570 [S]
64. Lee et al. (2026). Twin-rotor ground effect. JFM 1031:A42. https://www.cambridge.org/core/product/B57E828030CE5C29E4315DF0F05D96D8/core-reader [F]
65. Panerati et al. (2021). gym-pybullet-drones. IROS. https://arxiv.org/abs/2103.02142 [F]
66. Downwash interactions on multi-quadrotor systems (2025). https://arxiv.org/abs/2507.09463 [S]
67. APS DFD abstract, quadrotor downwash. https://archive.aps.org/dfd/2024/a30/5 [S]
68. Robot swarm paper neglecting the gyroscopic term (2024). https://arxiv.org/abs/2401.13103 [S]
69. Harrell. Note about new props. https://miniquadtestbench.com/note-about-new-props.html [F]
70. Velocidrone features. https://velocidrone.com/features [F]
71. Apollomaniacs, Velocidrone settings. https://apollomaniacs.com/ipod/howto_ar_drone_velocidrone_tuning_en.htm [F]
72. Liftoff, Simulated forces. https://www.liftoff-game.com/node/151 [F]
73. Liftoff, Physics 4.0. https://www.liftoff-game.com/node/102 [F]
74. GamingOnLinux (2022). Liftoff physics update. https://gamingonlinux.com/2022/01/liftoff-fpv-drone-racing-gets-a-huge-physics-update-new-racing-environment [S]
75. DRL Simulator, Steam. https://store.steampowered.com/app/641780/ [S]
76. Uncrashed, Steam. https://store.steampowered.com/app/1682970/ [S]
77. TRYP FPV, Steam. https://store.steampowered.com/app/1881200/ [S]
78. FPV.SkyDive, Steam. https://store.steampowered.com/app/1278060/ [S]
79. FPV Freerider. https://fpv-freerider.itch.io/fpv-freerider [S]
80. GetFPV (2019). Velocidrone review. https://www.getfpv.com/learn/?p=5338 [S]
81. DroneDJ (2021). Best FPV simulators. https://dronedj.com/2021/05/09/best-fpv-drone-simulators-in-2021/ [S]
82. Betaflight SITL. https://betaflight.com/docs/development/SITL [F]
83. SITL Forge, Steam. https://store.steampowered.com/app/4533290/ [S]
84. SimITL. https://gitee.com/BlueBuger/SimITL [S]
85. NeuroBEM dataset readme. https://download.ifi.uzh.ch/rpg/NeuroBEM/Readme.md [F]
86. Antonini et al. (2020). Blackbird dataset. https://arxiv.org/abs/1810.01987 [S]
87. Delmerico et al. (2019). UZH-FPV. https://fpv.ifi.uzh.ch/ [S]
88. Betaflight Blackbox internals. https://betaflight.com/docs/development/Blackbox-Internals [F]

## Bibliography B: racing, timing, presentation and input

1. MultiGP, Drone Race Course Obstacles. https://dev.multigp.com/multigp-drone-race-course-obstacles/ [F]
2. MultiGP, Race Class Specifications (2026). https://www.multigp.com/?p=99 [F]
3. MultiGP, 2020 Global Qualifier track diagram and setup. https://www.multigp.com/?p=47327 [F]
4. MultiGP, Universal Time Trial Track 1 rules (2015/2017). https://www.multigp.com/wp-content/uploads/2017/05/MultiGP-universal-time-trial-track1.pdf [F]
5. MultiGP, UTT #7 Tiny Whoop (2017). https://www.multigp.com/wp-content/uploads/2017/12/MultiGP-universal-time-trial-7-tiny-whutt.pdf [F]
6. MultiGP, 2019 Season Rules Released. https://www.multigp.com/?p=43415 [F]
7. MultiGP, 2025 Track & Build Guide. https://multigp.com/?p=77444 [F]
8. MultiGP, 2020 GQ track announcement. https://multigp.com/?p=47242 [F]
9. MultiGP, Road to Champ 2023 & GQ results. https://www.multigp.com/?p=62808 [F]
10. MultiGP, 2019 GQ leaderboard news. https://www.multigp.com/?p=44062 and https://www.multigp.com/?p=44483 [F]
11. MultiGP event page, GQ format (2022). https://dev.multigp.com/races/view/?race=23691 [F]
12. MultiGP Toolkit docs, Running Races (2025). https://multigp-toolkit.readthedocs.io/latest/usage/running/index.html [F]
13. AMA blog, MultiGP 2026 International Open. https://amablog.modelaircraft.org/blog/multigp-drone-racing-announces-2026-international-open/ [S]
14. MultiGP, 2016 Championship video. https://www.multigp.com/?p=242 [S]
15. FAI, Sporting Code Section 4 Vol. F9 Drone Sport, class F9U (2019). https://www.fai.org/sites/default/files/ciam/wcup_drones/sc4_vol_f9_dronesport_19-3_0.pdf [F]
16. FAI, TWG 2025 Drone Racing Sporting Rules v3. https://ciam.fai.org/sites/default/files/ciam/wcup_drones/twg_2025_drone_racing_sporting_rules_v3.pdf ; SC4 Vol. F9 2026. https://new.fai.org/sites/default/files/document/file/SC4_volume_CIAM_F9_Drone_sports_2026.pdf [S]
17. sUAS News (2019). DRL launches Racer4. https://www.suasnews.com/2019/08/drone-racing-league-launches-drl-racer4-the-next-generation-racing-drone/ [F]
18. Tom's Guide (2020). DRL Racer4 Street. https://www.tomsguide.com/news/drone-racing-league-racer4-street [S]
19. Atomic Design, DRL course pieces (2022). https://www.atomicdesign.tv/?p=3887 [S]
20. TechCrunch (2017). DRL RacerX Guinness record. https://techcrunch.com/?p=1514850 [S]
21. DCL, The history of the DCL racing drone. https://dronechampionsleague.com/the-history-of-the-dcl-racing-drone/ [F]
22. The Drone Girl (2023). DRL SIM Tryouts. https://www.thedronegirl.com/2023/06/30/2023-drl-sim-tryout/ [S]
23. RotorHazard, Tuning Parameters. https://github.com/RotorHazard/RotorHazard/blob/main/doc/Tuning%20Parameters.md [F]
24. RotorHazard, User Guide. https://github.com/RotorHazard/RotorHazard/blob/main/doc/User%20Guide.md [F]
25. GetFPV, ImmersionRC LapRF 8-Way. https://www.getfpv.com/electronics/fpv-racing-timing-systems/immersionrc-laprf-8-way-personal-race-timing-system.html [S]
26. GetFPV, I-Lap Drone Transponder. https://www.getfpv.com/i-lap-drone-transponder.html [S]
27. RunCam, Phoenix 2. https://shop.runcam.com/runcam-phoenix-2/ [F]
28. GetFPV, Caddx Ratel 2. https://www.getfpv.com/caddx-ratel-2-micro-starlight-1200tvl-low-latency-fpv-camera.html [F]
29. DJI, O4 Air Unit specs. https://www.dji.com/o4-air-unit/specs [F]
30. DJI, Goggles 3 specs. https://www.dji.com/goggles-3/specs [F]
31. FlyingTech, DJI Goggles 2 (51° FOV). https://www.flyingtech.co.uk/product/dji-goggles-2 [S]
32. Oscar Liang, Skyzone SKY04X review. https://oscarliang.com/skyzone-sky04x/ [S]
33. Unmanned Tech, FPV Drone Camera Angle. https://www.unmannedtechshop.co.uk/blogs/knowledge-base/fpv-drone-camera-angle-how-tilt-affects-flight [F]
34. Apollomaniacs, VelociDrone settings explained. https://www.apollomaniacs.com/ipod/howto_ar_drone_velocidrone_tuning_en.htm [F]
35. Steam, Liftoff FOV discussion. https://steamcommunity.com/app/410340/discussions/0/3729575905270663228 [F]
36. Steam, Liftoff fisheye/noise discussions. https://steamcommunity.com/app/410340/discussions/0/1496741765128458084 and https://steamcommunity.com/app/410340/discussions/0/312265256995088965 [F]
37. Godot docs, Camera3D. https://docs.godotengine.org/en/stable/classes/class_camera3d.html [F]
38. Godot source, scene/3d/camera_3d.cpp. https://raw.githubusercontent.com/godotengine/godot/master/scene/3d/camera_3d.cpp [F]
39. Godot docs, Overview of renderers. https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html [F]
40. Godot docs, Screen-reading shaders. https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html [F]
41. Godot docs, Advanced post-processing. https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html [F]
42. Godot docs, GPUParticles3D. https://docs.godotengine.org/en/stable/classes/class_gpuparticles3d.html [F]
43. Godot docs, Particle systems (3D). https://docs.godotengine.org/en/stable/tutorials/3d/particles/index.html [F]
44. clayjohn, commit "Add GPUParticles to the OpenGL3 renderer" (2022, mirror). https://git.objectionable.solutions/Sara/behaviour-tree-test/commits/commit/fc37fd7b9813486174dce96fcf200ff87def623d/scene/2d/gpu_particles_2d.cpp [S]
45. Godot, 4.3 release notes. https://godotengine.org/releases/4.3/ [F]
46. Sharpless, Postle, German (2010). Pannini: a new projection for rendering wide-angle perspective images. https://diglib.eg.org/handle/10.2312/COMPAESTH.COMPAESTH10.009-016 [S]
47. Betaflight docs, OSD tab. https://betaflight.com/docs/wiki/app/osd-tab [F]
48. Betaflight docs, Rate Calculator. https://betaflight.com/docs/wiki/guides/current/Rate-Calculator [F]
49. Betaflight source, src/main/fc/rc.c. https://raw.githubusercontent.com/betaflight/betaflight/master/src/main/fc/rc.c [F]
50. Betaflight docs, Profiles (dump/diff rates). https://betaflight.com/docs/wiki/guides/current/Profiles [F]
51. Betaflight docs, Controls. https://betaflight.com/docs/wiki/guides/current/Controls [F]
52. Betaflight docs, Modes. https://betaflight.com/docs/wiki/guides/current/Modes [F]
53. Betaflight docs, DSHOT RPM Filtering. https://betaflight.com/docs/wiki/guides/current/DSHOT-RPM-Filtering [F]
54. Cabell, McSwain, Grosveld (2016). Measured Noise from Small Unmanned Aerial Vehicles. NOISE-CON 2016. https://ntrs.nasa.gov/api/citations/20160010139/downloads/20160010139.pdf [F]
55. Intaratep et al. (2016). Full-Scale Small Quadcopter Noise. AIAA 2016-2873. https://www.bu.edu/ufmal/files/2016/07/aiaa-2016-2873.pdf [F]
56. Zawodny, Boyd, Burley (2016). Acoustic characterization of small-scale rotary-wing UAS components. https://ntrs.nasa.gov/citations/20160009054 [S]
57. Zawodny, Boyd (2017). Rotor-airframe interaction noise. https://ntrs.nasa.gov/citations/20180001470 [S]
58. ExpressLRS docs, Lua script how-to (packet rates). https://www.expresslrs.org/quick-start/transmitters/lua-howto/ [F]
59. ExpressLRS docs, Radio preparation. https://www.expresslrs.org/quick-start/transmitters/tx-prep/ [F]
60. EdgeTX manual, USB Joystick. https://manual.edgetx.org/color-radios/model-settings/model-setup/usb-joystick [F]
61. EdgeTX manual, Joystick mapping information for game developers. https://manual.edgetx.org/edgetx-how-to/joystick-mapping-information-for-game-developers [F]
62. GetFPV, RadioMaster AG01 gimbal set (self-centering + throttle). https://www.getfpv.com/radios/radio-controllers/radiomaster-radios/radiomaster-accessories/radiomaster-tx16s-cnc-ag01-hall-gimbal-set-of-2-w-self-centering-throttle.html [S]
63. VelociDrone, Features. https://velocidrone.com/features [F]
64. SteamDB, Liftoff Track Builder patch notes (2025). https://steamdb.info/patchnotes/19470331 [S]
65. Steam, DRL Simulator map-editor thread (2018). https://steamcommunity.com/app/641780/discussions/0/1760230157497017423/ [S]
66. Univ. of Leicester (2019). Top speed of a racing drone. https://journals.le.ac.uk/index.php/pst/article/view/3338 [S]
67. MultiGP, UTT #6 FURY (2017). https://multigp.com/?p=17939 [S]
68. Zbotic, Betaflight RPM filter guide (2025, weak). https://zbotic.in/betaflight-rpm-filter-eliminate-motor-noise-for-smooth-fpv-flying/ [S]
69. MiniQuadTestBench, T-Motor F60 Pro II 1750KV. https://miniquadtestbench.com/t-motor-f60-proii-1750kv.html [F]
70. Oscar Liang, FPV drone rates and expo explained (2024). https://oscarliang.com/rates/ [S]
