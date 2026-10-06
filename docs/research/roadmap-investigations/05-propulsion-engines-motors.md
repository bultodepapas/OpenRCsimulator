# 05 — Propulsion systems: glow and gas engines, electric motors with ESC and battery, and turbines

**Status:** research knowledge base, 2026-10-06. **Serves:** ROADMAP M4 (G1–G4, PT4), the Avanti S turbine branch (AV-05, AV-10 in [AVANTI-S-PLAN](../../AVANTI-S-PLAN.md)), the P-51's 120 cc gas engine ([P51-PLAN](../../P51-PLAN.md), P51-06), engine smoke ([SMOKE-PLAN](../../SMOKE-PLAN.md)), and a proposed electric track (none in the roadmap today). **Read with:** [ROADMAP M4](../../../ROADMAP.md), [RESEARCH.md: Electric propulsion](../../../RESEARCH.md#electric-propulsion-distinguish-the-components-and-their-evidence), [avanti-s-turbine-research.md](../avanti-s-turbine-research.md), [ugly-stik-engine-v5.md](../ugly-stik-engine-v5.md) (visual only, no specs), [propulsion.gd](../../../app/physics/propulsion.gd).

## Summary

- **One equation unifies every propeller power plant:** `I_rot·dω/dt = Q_source(ω, throttle, state) − Q_prop(ω, V) − Q_friction(ω)`. Glow, gas and electric differ only in `Q_source`; a turbine replaces shaft + propeller by a spool lag and a direct thrust `F = ṁ(V_e − V_0)`.
- **Shaft dynamics are slow enough for the 240 Hz tick.** Derived for the repo's own data: .61 + APC 12×6 has τ_shaft ≈ 0.25 s at full power, ≈ 1 s at idle; DA-120 + 26×12 four-blade ≈ 0.2–0.28 s; a .60-class electric setup ≈ 30 ms. dt/τ ≤ 0.14 everywhere, but use a linearly implicit update anyway (light electric rotors approach dt/τ ≈ 1).
- **A shaft-balance slice is already in the working tree, uncommitted** (P51-06 "G2 first slice", AV-05 turbine draft, 2026-10-06). It is a good base. It misses: the airframe reaction to rotor acceleration (`−dh/dt`), wind in the inflow, a windmilling/stopped-propeller branch, and an implicit update.
- **Torque reaction bug-in-waiting:** the airframe feels the *engine* torque (crankcase), not the *propeller* torque. During a throttle punch they differ by `I_rot·dω/dt`; for the .61 it is 0.83 vs 0.05 N·m at the first tick. `rigid_body.gd` has no `dh/dt` term, so the punch-out torque roll is delayed by the spool time.
- **Propeller tables stop where the interesting dead-stick physics starts.** UIUC 11×6 data end at J 0.79 (Ct −0.003); the windmilling branch (J ≈ 0.8–1.5) and the stopped-propeller drag are missing. `J = V/(nD)` is singular at n → 0, so the code zeroes everything below 1 rpm: a stopped propeller has no drag and cannot be started turning by the air.
- **Glow engines:** O.S. publishes one point (61FX: 1.9 PS at 16,000 rpm); no public torque curves were found. The O.S. manual documents the behaviour a game can use: rich "four-stroking", lean cut-out on throttle-up, rich flooding after prolonged idle, plug temperature tracking rpm (manual-level evidence).
- **Fuel matters for mass:** a 350 cc glow tank is ~0.30 kg, 11 % of the Ugly Stik's 2.6 kg; the Avanti carries proportionally more kerosene. Derived glow burn ≈ 30–55 mL/min at 1 kW, so ~7 min at full throttle, 12–15 min mixed. DA-100 burns 71 g/min at 6,000 rpm (manufacturer, compiled).
- **Electric is the three-constant Drela model** (`Kv, R, I0`) plus an averaged ESC (`V_m = duty·V_batt`, `I_batt = duty·I_m`) and a one-RC Thevenin LiPo. Every piece is closed-form and costs a few µs per tick. A .60-class example is worked out: 6S, 400 Kv, 14 in prop gives ~1.2 kW, 49 N static, ~11 min at 40 % mean power. All motor resistances are estimates.
- **ESC behaviour that changes the flight comes from a manufacturer manual (Hobbywing Skywalker V2):** soft LVC ramps to 60 % power in 3 s (or a hard cut); cutoff at 2.8/3.0/3.4 V per cell; start-up ramp 200/500/800 ms; signal loss cuts after 0.25 s; thermal derating above 120 °C; brake 60/90/100 %.
- **Turbines respond in seconds, asymmetrically.** Derived from the P100-RX model identified by L'Erario et al.: idle→max ≈ 3 s, max→idle 90 % ≈ 1.9 s. JSBSim's default schedule gives 2.0 s up and 0.6 s down. Ram drag `ṁ·V` costs 14 % of static thrust at 60 m/s.
- **Decide now:** `pre_step` must receive the air-relative state; engine discrete states and energy stores must live in `aux`, so traces and goldens replay them; propulsion v2 must be a list of power plants, each a source → shaft → propeller with a typed `source.kind`.

## Where the code stands

**Committed (HEAD 69dc9bc):**

| Piece | File | Fact |
| --- | --- | --- |
| rpm model | [propulsion.gd](../../../app/physics/propulsion.gd) `rpm_step` | First-order lag to `idle + θ·(max_static − idle)`, exact exponential, τ from data (0.25 s Stik and Extra; 0.6 s P-51) |
| Thrust/torque | `loads` | Ct(J), Cp(J) piecewise-linear; J < 0 → J = 0 row; extrapolation floors Ct −0.1, Cp 0; below 1 rpm all zero |
| Reaction | `loads` | `Mx = −Q_prop` (clockwise prop from behind rolls left) + `r × T` |
| Gyroscopics | [dynamics.gd](../../../app/physics/dynamics.gd), [rigid_body.gd](../../../app/physics/rigid_body.gd) | `h = I_rot·ω` along +x; `ω̇ = J⁻¹(M − ω × (Jω + h))`; **no `−dh/dt` term** |
| Aux state | [flight_session.gd](../../../app/sim/flight_session.gd) `_pre_step` | `aux = [rpm, servo_roll, servo_pitch, servo_yaw]`; advanced once per tick, held over the 4 RK4 stages; `pre_step(aux, inputs, dt)` gets **no state** |
| Engine state | `engine_running` (session bool) | Not in `aux`: traces and goldens see it only through the start mode (glide = stopped) |
| Trim | [trim.gd](../../../app/physics/trim.gd) | rpm = `target_rpm(throttle)` (independent of airspeed) |
| Data | `app/data/aircraft/*.json` | Stik and Extra: O.S. 61FX 1397 W @ 16,000 rpm (manual), static max 11,149 rpm (derived, constant-torque assumption), idle 2,800 (estimated), APC Sport 11×6 UIUC tables applied to a 12×6, I_rot 3.5e-4 kg·m² (estimated). P-51: DA-120 8,725 W @ 6,900 (manual), static 5,751 rpm (derived), BEM tables, I_rot 0.0131 kg·m² (estimated) |
| Sound | [engine_sound.gd](../../../app/render/engine_sound.gd) | Additive buzz at `rpm/60` with 6 harmonics, 22,050 Hz `AudioStreamGenerator`, amplitude ∝ rpm/max |
| Smoke | [SMOKE-PLAN](../../SMOKE-PLAN.md) | Plans to read `aux[AUX_RPM]` and `engine_running` from `sim.stepped`; rpm is only a stand-in for mixture |
| Trace | [trace.gd](../../../app/sim/trace.gd) | `openrc-trace v3` logs `engine_rpm` |

**Uncommitted, in the working tree on 2026-10-06 (other tracks, P51-06/P51-12/AV-05):** `propulsion.gd` gains an optional `engine.shaft` = { full-throttle brake `power_curve` [[rpm, W]…], `friction_torque` [N·m, N·m/krpm], `idle_power`, `peak_indicated_power` }. Engine torque `Q = min(Q_full_ind(n), P_adm/ω) − Q_f` with `P_adm = P_idle + θ·(P_peak − P_idle)`. The shaft is stepped by explicit Euler; a bisection `steady_rpm` serves the trim. Cp < 0 (windmilling) is allowed only with a shaft. Also added: thrust axis angles and a propeller normal force. `turbine.gd` adds a governor lag, accel/decel limits, `F = k·F_static(N)·σ − ṁ(N)·σ·u` and a fuel-flow table without mass change. The session's `_pre_step` reads `sim.state` body velocity, so the inflow ignores wind. **Treat these as in-flight work:** this document comments on them but does not assume they land unchanged.

**Missing:** windmill/stopped branch and low-n formulation; `−dh/dt`; engine start/stop states; throttle servo slew (surfaces have servos, the throttle does not); carburettor nonlinearity; fuel/battery state, mass and CG change; electric chain; multi-engine; sound driven by load; validation against any measured rpm trace.

## Theory and models

### 1. Shaft dynamics (all propeller power plants)

```
I_rot · dω/dt = Q_src(ω, θ, s) − Q_prop(ω, V_a) − Q_f(ω)
Q_prop = Cp(J)·ρ·n²·D⁵/(2π),  T = Ct(J)·ρ·n²·D⁴,  J = V_a/(nD),  n = ω/2π
I_rot = I_prop + I_spinner + I_crank(or rotor bell) [+ gear: I_motor·G²]
```

- **Operating point stability:** `∂Q_prop/∂ω − ∂Q_src/∂ω > 0`. Static prop: `∂Q_prop/∂ω = 2Q/ω`. Linearised time constant `τ = I_rot / (∂Q_prop/∂ω + ∂Q_f/∂ω − ∂Q_src/∂ω)`.
- **Derived τ for repo data** (python, flat source torque, static Cp0):

| Setup | rpm | Q_prop (N·m) | τ_shaft | dt/τ at 240 Hz |
| --- | --- | --- | --- | --- |
| .61 + 12×6, I 3.5e-4 | 2,800 idle | 0.053 | 0.98 s | 0.004 |
| same | 11,149 static | 0.834 | 0.245 s | 0.017 |
| DA-120 + 26×12×4, I 0.0131 | 5,751 static | 14.1 | 0.28 s (0.21 s with the P-51 file's falling torque) | 0.015 |
| 6S 400 Kv + 14 in electric (estimated R) | 8,950 | ~1.2 | 0.030 s | 0.14 |

- **Throttle punch (derived, .61, flat WOT torque, instant carb):** idle→50 % of the rpm span in 0.23 s, 90 % in 0.67 s, 95 % in 0.84 s. The constant 0.25 s lag in the data reaches 95 % in 0.75 s, so the right size, but the shape differs: the lag starts fastest at idle, while the shaft is torque-limited (near-linear ramp) and then settles.
- **Reaction torque on the airframe.** Newton on the rotor gives `Q_src − Q_prop − Q_f = I_rot·ω̇_r`. The crankcase/stator receives `−Q_src` (plus `+Q_f` back). The air receives the propeller's torque. Total moment on airframe+rotor about the shaft = `−Q_prop` (aero), and `d(h)/dt` is the part that spins the rotor up. The rigid-body equation needs either `M = −Q_prop` together with `−ḣ` on the left, or `M = −(Q_src − Q_f)` without it. The repo carries `h` but not `ḣ`. **Add `−ḣ ≈ −I_rot(ω_{k+1} − ω_k)/dt · axis`, held over the tick.** The reaction is then correct on the first tick of a punch (.61: 0.83 N·m instead of 0.05 N·m; P-51: ~14 N·m step).
- **In-flight unloading (derived, .61 + 12×6, flat torque at static WOT value):** rpm 11,149 (0 m/s) → 10,950 (20 m/s; the UIUC Cp rises 0→J 0.37) → 11,344 (25) → 11,957 (30) → 12,662 (35 m/s, +14 %). A dive at 40–50 m/s overspeeds further; the current lag model holds rpm constant in a dive.
- **Windmilling dead engine.** With `Q_src = 0` the prop settles where `Cp(J)·ρn²D⁵/2π = −Q_f(ω)`, i.e. slightly beyond the Ct = 0 point. The 12×6 zero-thrust point J ≈ 0.776 means a frictionless windmill at 2,537 rpm at 10 m/s and 3,805 rpm at 15 m/s. If the break-away (friction + compression) torque exceeds the aero torque available at J → ∞, the prop stops. This is the D8a finding (glide L/D 5.9 vs 8.46) seen from the physics side: the tables need a windmill branch.
- **Low-n formulation (removes the J singularity):** write `T = (Ct/J²)·ρV²D²` and `Q = (Cp/J³)·ρV²D³/2π` for n·D < V/J_max. Equivalently tabulate in `φ = atan(V/(0.7πnD))` (the "four-quadrant" / β-angle form used in marine propeller data, unverified here for RC data) so a stopped prop (φ = 90°) has finite drag and torque.

### 2. Glow 2-stroke (.40–.61) and gas (20–120 cc)

**Fidelity levels for `Q_src`:**

| Level | Model | Inputs | Use |
| --- | --- | --- | --- |
| L0 (today) | rpm lag to a throttle-mapped target | idle, max_static, τ | Ship v0 |
| L1 (uncommitted slice) | WOT brake-power curve + friction + throttle-admitted power cap: `Q = min(Q_wot,ind(ω), P_adm(θ)/ω) − Q_f(ω)` | power curve, friction, idle/peak indicated power | G2 |
| L2 | + throttle servo slew, barrel airflow map, combustion lag τ_c ≈ 2–5 revolutions (estimated), engine states (off/cranking/running/stalling) | carb geometry (estimated), starter torque | G2 + gameplay |
| L3 | + mixture/plug-heat/flood states, fuel flow from BSFC, temperature | tuning parameters (estimated) | Realism option |

- **The L1 power cap is physically motivated.** At small throttle openings the orifice limits air mass flow per second. Trapped mass per cycle is then ∝ 1/n, torque ∝ 1/ω and power is roughly constant. This is stable against a propeller and gives a sensible part-throttle unloading. At large openings the engine's own breathing (`Q_wot(ω)`) limits it. (Reasoning; not validated against an RC dyno.)
- **Torque curve shape.** Manufacturers publish one point: O.S. 61FX 1.9 PS @ 16,000 rpm; O.S. 55AX 1.75 PS @ 16,000, practical 2,000–17,000 rpm; DA-120 11.7 hp, 1,300–6,900 rpm; DLE-120 12 hp @ 7,500 rpm. No public torque curves were found. Kass et al. (SAE 2014-01-1673, 4 cc glow two-stroke) measured peak torque at 3,000–3,500 rpm over a 2,000–7,000 rpm wide-open-throttle test. That range is below such an engine's usual operating rpm, so it shows a broad torque curve but constrains the shape near peak power only weakly.
  - The two shapes in the repo disagree. The Stik's `max_rpm_static` assumes constant torque. The P-51 script uses `P = P_peak·x(2 − x)`, i.e. torque `∝ (2 − x)`, which is **twice the peak-power torque at zero rpm**; it is labelled "flat-torque" but is not. Choose one documented shape, label it estimated, and sweep it in sensitivity: static rpm, spool-up time and unloading all depend on it.
- **Carburettor:** a rotary barrel's open area vs rotation is a two-circle lens, `A/A₀ = (2/π)(acos x − x√(1−x²))`, with x the normalised offset (geometry; real barrels also translate axially for mixture). Airflow, and so torque, rises steeply in the first half of the opening and saturates. Pilots counter it with radio throttle curves. Model it as a data table `admitted_fraction(θ)`; default linear until measured.
- **Mixture behaviour (O.S. FX manual, manual-level evidence):** needle too rich → engine "fires like a four-stroke … ignition … at every fourth stroke". The manual's two-stroke/four-stroke note change is the tuning cue. Mixture-control-valve too rich → "slow to pick up and produces an excess of exhaust smoke"; excessively rich → "rpm may drop suddenly or the engine may stop", which "may also be initiated by excessively prolonged idling". Too lean → "a marked lack of exhaust smoke and a tendency for the engine to cut out when the throttle is opened". The plug: "under reduced load, allowing higher rpm, the plug becomes hotter … at reduced rpm, the plug becomes cooler and ignition is retarded"; "engine tends to cut out when idling" is listed as a worn-plug symptom.
- **Dead-stick causes worth simulating (L3, estimated dynamics):** (a) idle below a stall rpm (JSBSim FGPiston stops below 0.8·idle); (b) flood: a state accumulating at idle when the mixture is rich, cleared at high rpm; (c) plug cool-down: a plug-heat state relaxing toward f(rpm, load); a long idle descent at high airspeed (windmill-driven, low load) cools it; (d) lean cut on a fast throttle opening (lag between air and fuel); (e) fuel exhaustion. Default the whole realism layer **off**.
- **Fuel consumption (derived):** small glow engines show brake thermal efficiency 4–17.5 % (7.45 cc, IITM; search result only). Effective LHV of 10 % nitro / 18 % oil fuel ≈ 0.72·19.9 + 0.10·11.3 ≈ 15.5 MJ/kg (textbook LHVs, estimated blend). At 1.0 kW shaft that gives 26–49 g/min (30–57 mL/min at ~0.85 kg/L, estimated). The 350 cc (12 oz) tank O.S. suggests for the 61FX then lasts ~7 min at WOT and ~12–15 min in mixed flight. Gas: DA-100 71 g/min at 6,000 rpm (barnardmicrosystems compilation of DA data). If at rated 9.8 hp, BSFC ≈ 580 g/kWh (derived). Scaled to the DA-120 by rated power ≈ 85 g/min (derived).
- **Engine start (gameplay, L2):** glow plug energised (1.5 V, O.S. manual) or gas ignition (DA "Safe Start"); starter torque `Q_st = Q_st0(1 − ω/ω_st)` (JSBSim FGPiston form, ω_st = 2·idle); catches above a light-off rpm. A scenario feature (runway start, E3b), not flight-model work. Tuned pipes (a resonant power bump) are out of scope.
- **Sound inputs:** 2-stroke single firing frequency `f = rpm/60`. 120 cc twins: DA/DLE opposed twins are commonly described as firing together (then f = rpm/60). **Unverified**, and it changes the note. Derived: .61 47 Hz idle, 186 Hz static, ~233 Hz in a dive at 14,000 rpm; DA-120 22 Hz idle, 96 Hz static. Blade-passing frequency `rpm/60·B` (B = 2 or 4) is the second voice.

### 3. Electric: motor, ESC, battery

**Motor (Drela, first order, fetched):** `Q_m = (i − i₀)/K_Q`, `v = Ω/K_V + i·R`, so `i(Ω, v) = (v − Ω/K_V)/R`, `η = (1 − i₀/i)·(K_V/K_Q)/(1 + iRK_V/Ω)`; K_V in rad/s/V; K_Q = K_V by energy conservation. Measurement: R with a milliohmmeter (average over shaft positions); i₀ at no load near operating rpm; K_V = Ω/(v − i₀R).
**Second order (fetched):** `R = R₀(1 + αΔT)` with α_Cu = 0.0042 /°C, or `R(i) = R₀ + R₂i²`; `i₀(Ω) = i₀₀ + i₀₁Ω + i₀₂Ω²` (bearings, laminar and turbulent windage); back-EMF `v_m = (1 + τΩ)Ω/K_V` (magnetic lag).

**ESC (averaged model, L1):** `v_m = d·V_batt`, `I_batt = d·I_m` (power balance minus switching losses, folded into R_esc ~mΩ, estimated). d = throttle after the ESC's start-up ramp. Behaviour from the Hobbywing Skywalker V2 manual (rev 2025-08-14, fetched):

| Feature | Options / numbers |
| --- | --- |
| Throttle range | default 1,100–1,940 µs; calibrate |
| LVC threshold | off / 2.8 / 3.0 / 3.4 V per cell × detected cells ("3.7 V/cell" auto rule) |
| LVC type | soft: output reduced to 60 % in 3 s; hard: immediate cut |
| Start-up ramp 0→100 % | normal / soft / very soft ≈ 200 / 500 / 800 ms |
| Brake | disabled / normal (60 / 90 / 100 % force) / reverse |
| Timing | 5° / 15° / 25° |
| Thermal | above 120 °C gradual reduction to ~60 % (soft) |
| Signal loss | > 0.25 s → output cut; resumes on signal |
| Active freewheeling (DEO) | on/off (synchronous rectification) |

- Brake off → the prop windmills (motor back-EMF below V_batt draws nothing); brake on → shorted phases give a large stopping torque (folding props on gliders).
- In a steep dive the unloaded motor approaches no-load rpm `K_V·V`, so electric power plants self-limit overspeed, unlike glow. When the prop drives the motor beyond `K_V·d·V_batt`, active freewheeling can regenerate; magnitude unverified.
- Governor mode (helicopters) and timing effects on K_V are out of scope.

**Battery (LiPo):**

| Level | Model |
| --- | --- |
| B0 | constant V (ideal) |
| B1 | `V = N_s·OCV(SOC) − I·R_pack`, `dSOC/dt = −I/(3600·C_Ah)` (RESEARCH.md proposal; CRRCSim uses exactly this with a relative `U_0rel` table, `R_I`, `U_off`) |
| B2 | + one RC branch (Peukert-like capacity loss then emerges from R₀ and the cutoff; IR: retail 6S packs claim 1.2–5 mΩ/cell, use 3–5 mΩ estimated): `U̇_c = −U_c/(R₁C₁) + I/C₁`, `V = OCV − U_c − R₀I` (Bauersfeld & Scaramuzza 2022, OTC model, validated on 10 packs 4S1P–6S4P at 5–70 C) |
| B3 | + `R₀(T)`, temperature state, cell imbalance, ageing |

- Bauersfeld & Scaramuzza: `OCV` cubic in consumed energy, `R₀ = max(b₀ + b₁P̄ + b₂C, R_min)` with R_min 4.5 mΩ, τ_RC 3.3 s. The power-driven load requires solving `V = ½(U₀ − U_c + √((U₀ − U_c)² − 4R₀P))` (no real root = collapse → brown-out/cut). Their coefficient table is fetched, but the units of E_cell are not stated unambiguously in the text: **verify before use**.

**Worked .60-class electric equivalent (derived with python; motor R and i₀ estimated):** E-flite Power 60 class, 400 Kv (manufacturer: up to 1,200 W, 6–10 lb 60-size airframes). 6S, R_m 0.030 Ω, i₀ 2.0 A, R_esc 2 mΩ, 6 × 4 mΩ pack, fresh OCV 25.2 V. Propeller coefficients borrowed from the repo's APC 11×6 tables (same P/D 0.5; APC "E" props differ).

| Prop | rpm | I (A) | V_batt (V) | Shaft power (W) | Battery power (W) | Static T (N) | η_motor+wiring |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 14 in | 8,946 | 50.6 | 24.0 | 1,087 | 1,214 | 49.2 | 0.90 |
| 16 in | 8,236 | 82.3 | 23.2 | 1,654 | 1,912 | 71.1 | 0.87 (exceeds the motor's 1,200 W) |

- 14 in at 40 % mean battery power and 80 % usable of 5 Ah × 22.2 V gives ~11 min (4.4 min at WOT). Motor copper loss at WOT ≈ 77 W; i₀ loss ≈ 48 W. Compare the .61: 41 N static from the repo data.
- The electric mass budget differs: pack ~0.75–0.85 kg (unverified typical) vs ~0.5 kg engine + 0.3 kg fuel. An electric variant is a new mass inventory, not a propulsion swap.
- **Thermal (L2):** `C_th·dT/dt = I²R(T) + i₀·v − (T − T_amb)/R_th`; R_th depends on airflow (∝ 1/(a + b·V)). All numbers estimated; the gameplay effect is power fade and ESC derating.
- **Electric sound:** prop BPF `rpm/60·B` dominates. Commutation whine at `rpm/60·p` (p pole pairs, e.g. 7 for a 14-pole outrunner); ESC switching tone at the PWM frequency. Both lack values verified here.

### 4. Turbines (Avanti S, P100-RX)

- **Thrust:** `F = ṁ(V_e − V_0)` (NASA Glenn, simplified, p_e ≈ p_0). P100-RX max ṁ 0.23 kg/s, V_e 434.7 m/s → 100 N static (repo doc, JetCat catalog). Constant-ṁ ram drag (derived): 93 N at 30 m/s, 86 N at 60, 82 N at 80 m/s. Real ṁ rises somewhat with ram pressure (not modelled; unverified magnitude).
- **Spool:** throttle → ECU N demand → `dN/dt = clamp((N_d − N)/τ_gov, −R_dec(N), R_acc(N))` (the uncommitted `turbine.gd`). It is a sound structure: the ECU schedules acceleration to avoid flameout/over-temperature and limits deceleration to avoid starving the flame ("acceleration/deceleration delay" in ECU settings; Model Airplane News, search result only).
- **Timing evidence:**
  - L'Erario et al. identified a second-order nonlinear thrust model for the P100-RX (throttle range 25–100 %, MAE 3.9 N). Simulating their EKF parameters (u in %, consistent: 87 N steady at 100 %): **25→100 % step: 10 % at 0.7 s, 63 % at 2.6 s, ~74 N at 3.0 s; 100→25 %: 63 % at 0.75 s, 90 % at 1.9 s.** Beyond ~3 s the up-step diverges, because the polynomial terms extrapolate outside the identification data. Use the timing, not the model.
  - JSBSim FGTurbine default (BPR 0): N2 rate `= 30/(1 + 3(1−n)³ + (1−σ))` %/s up and `90/(…)` down, so 60→99 % N2 in 1.96 s, 100→61 % in 0.63 s (derived). These are full-size-tuned defaults.
  - Pilot report: ~5 s idle→full for a Wren MW54 (search result only).
  - JetCat's manual describes the response settings qualitatively only (repo doc). **Spool times remain estimated (≈ 2–4 s up, 1–2 s down) with a sensitivity sweep.**
- **Fuel:** P100-RX 80 / 390 mL/min idle/max (0.064 / 0.312 kg/min). JSBSim instead uses `ṁ_f = TSFC·F` with an idle floor. Prefer the table on N.
- **ECU states (gameplay):** OFF → START (glow/kero ignition, starter) → IDLE → RUN; fault states: FLAMEOUT (too-fast throttle in the real ECU is prevented by the schedule; fuel starvation), COOLDOWN. JSBSim: `tpOff/tpRun/tpSpinUp/tpStart/tpStall/tpSeize/tpTrim`; light-off requires N2 > 15 %. No windmill relight for RC turbines (ECU-controlled start only; reasoning, unverified).
- **Gyroscopics:** P100 rotor inertia unknown (repo doc). With a typical 1–2e-5 kg·m² class rotor (unverified) at 154,000 rpm, h ≈ 0.16–0.32 N·m·s, comparable to the .61's 0.41. Keep `rotor_inertia` as estimated data with a zero default.

### 5. Reference simulators (what they model)

| Sim | Source model | Shaft | Notes for us |
| --- | --- | --- | --- |
| JSBSim FGPiston | indicated HP from fuel flow/ISFC × mixture efficiency; FMEP static 46,500 Pa + dynamic 18,400 Pa·(mean piston speed); `StaticFriction_HP` 1.5; starter `0.4·maxHP`, `k = 1 − rpm/starter_rpm`; running if spark ∧ fuel ∧ rpm > 0.8·idle | FGPropeller: explicit Euler `RPM += (P_avail/ω)/Ixx/2π·dt`; clamp ≥ 0 | Subset worth copying: starter law, stop rule, friction as a function of rpm. Skip manifold pressure, magnetos, BSFC-by-mixture |
| JSBSim FGElectric | `P = P_max·throttle`, rpm-independent; no battery | same | Too simple; Drela is better |
| JSBSim FGTurbine | `Seek()` rate-limited N1/N2 with spool-up/down schedules; `F = F_idle + (F_mil − F_idle)·N2norm²`; windmill N from q̄ | — | LGPL 2.1: read, do not copy |
| CRRCSim | battery `U = U₀(C) − R_I·I` with `U_0rel` table, cutoff; shaft `J`, brake flag (folding props, `n_fold`); DC motor `I = (U − ωk_M)/R_I`, `M = k_M(I − I₀)`; gearing `i`; Hepperle prop formulas; `SimpleThrust` legacy | integrated by total J | Closest to what we need for electric; GPL-2 |
| PX4 gazebo motor model | first-order speed filter with separate `timeConstantUp/Down`; thrust scaled by `1 − V∥/V_max` | lag | Apache-2.0; up/down asymmetry idea only |
| ArduPilot ICE | `ICE_IDLE_RPM` idle governor, `ICE_REDLINE_RPM`, starter retries `ICE_STRT_MX_RTRY`, `ICE_RPM_THRESH` running detection | — | Real autopilot behaviour of RC gas engines; no SITL engine physics documented |
| RealFlight, PicaSim | Not documented publicly (RealFlight edit fields not found; PicaSim engine model not inspected) | — | Unverified; do not cite as reference behaviour |

## Implementation options and trade-offs

| Option | Pros | Cons | Verdict |
| --- | --- | --- | --- |
| A. Keep rpm lag (L0) | Bit-stable, trivial | No unloading, no windmill, no overspeed, wrong torque transient | Keep for aircraft without `shaft` data |
| B. ω in `aux`, explicit Euler per tick (uncommitted slice) | Small change, deterministic | Unstable if dt/τ > 2 (light electric rotors), inflow from the start-of-tick state | Acceptable now; upgrade to C |
| **C. ω in `aux`, linearly implicit (Rosenbrock-Euler) update: `ω₊ = ω + dt·f/(1 − dt·∂f/∂ω)`, ∂f/∂ω by one finite difference** | Unconditionally stable for the stable operating point; 2 extra torque evaluations; keeps operator splitting | O(dt) splitting error (negligible: τ ≫ dt) | **Recommended** |
| D. ω as a 14th RK4 state | Fully coupled, 4th order | Changes `RB.SIZE`, every golden, linearize.gd, recorder; engine logic (states, cutoffs) inside RK stages is messy | Not now |
| E. Electric: solve motor current in closed form each evaluation (B1 battery) | Exact for L1, cheap | Needs `V_batt` from aux (held over the tick) | Recommended |
| F. Full ESC/FOC simulation | — | µs timescales, no flight effect | Never |

**Recommendation for this repo:**
1. Promote the uncommitted shaft slice to option C, with the inflow from the **air-relative** velocity: `pre_step(aux, inputs, dt, state, wind)`.
2. Add `−ḣ` to the rigid-body moment from the tick's Δω.
3. Add the windmill/stopped branch.
4. Then build the electric chain as a second `Q_src` (Drela L1 + averaged ESC + B1 battery), and the realism layers later.

**Unified architecture (proposal):**

```
inputs (throttle channel) ─► actuator (throttle servo slew / ESC ramp / ECU schedule)
   └► SOURCE.kind ∈ {glow, gas, electric, turbine}
        glow/gas: Q_src(ω, θ_eff, flags) ; consumes fuel tank
        electric: Q_m(ω, d, V_batt) ; draws battery (SOC, U_c, T_motor)
        turbine : N_dot(N, demand) ; F(N, V) ; consumes fuel tank
   └► SHAFT (prop plants): ω state, I_rot, gear, friction, brake
   └► PROPELLER: Ct/Cp(J or φ), normal force, slipstream hook (E0b), rotation sense
   └► LOADS: F, M (incl. −Q_reaction, −ḣ), h for gyroscopics
   └► TELEMETRY (read-only): rpm, load = Q_src/Q_src,max, throttle, running state,
        fuel/SOC, temperatures, firing & BPF frequencies → sound, smoke, HUD, trace
```

**Per-power-plant aux block (float64, replayed and traced):** `[ω or N, θ_actuator, state_code, fuel_kg | SOC, U_c, T_motor, plug_heat, flood]`, with unused slots fixed at 0. Discrete states are encoded as float codes and change only in `pre_step` (deterministic). `engine_running` moves from the session bool into `state_code`.

**Mass properties (G4):** update mass, CG and inertia once per tick in `pre_step` from the tank/battery inventory and hold them over RK4. The state origin is the CG, so a CG shift Δc requires shifting the position state by `R·Δc` in the same tick. That is mm-scale; document it so render interpolation does not see a jump.

**Multi-engine:** `propulsion.powerplants[]` from v2 on, each with its own offset/axis/rotation/aux block and a throttle channel map (twins: same channel; differential-thrust option later).

## Godot / GDScript notes

- All of the above is scalar float64 arithmetic. Keep it in `PackedFloat64Array`/`float`, no `Vector3` (repo rule, enforced by `app/test.sh`). Use `M.exp_` (the repo's own exponential), not `exp`, where determinism across platforms matters, as `rpm_step` already does.
- **Cost:**
  - Option C: 3 propeller-torque and 3 source-torque evaluations per tick ≈ 3 Ct/Cp table walks. Order 10–20 µs in GDScript (estimated from the existing per-tick budget of ~510 µs for the whole model), against the 500 µs rule-7 budget, which is already exceeded on the dev VM.
  - Move the table lookup to a precomputed uniform-J grid (O(1) index) when profiling shows it.
  - `steady_rpm` bisection (80 iterations) runs only in trim.
  - Dictionaries in the hot path (`prop.shaft.power_curve`) cost hash lookups: cache typed locals per tick.
- **Audio:** Godot's `AudioStreamGenerator` docs say it "is best used from C# or from a compiled language via GDExtension" and recommend 11,025 or 22,050 Hz from GDScript (the repo uses 22,050). G3's richer synthesis (load-dependent spectra, several voices, Doppler) is the most likely GDScript hotspot. Budget it per frame, or synthesise via `AudioStreamPlayer` pitch-shifted loops of recorded samples (licensed, provenance per SMOKE-PLAN rules). The pause behaviour learned in UI-02 (`stream_paused`) still applies.
- **Determinism:** engine events (stop, LVC, flameout) must depend only on aux/state/inputs, never on wall-clock or `_process`. Smoke and sound read telemetry from `sim.stepped`, as SMOKE-PLAN already prescribes.

## Reusable libraries, tools, code and datasets

| Name | What it gives us | License | Link | How to use here |
| --- | --- | --- | --- | --- |
| UIUC Propeller Data Site | Measured Ct, Cp vs J and static sweeps, APC/others, true diameters | Terms not established (RESEARCH.md) | [propDB](https://m-selig.ae.illinois.edu/props/propDB.html) | Offline import with SHA-256 (as today); do not redistribute files until terms are clear |
| APC performance files | Computed Ct/Cp/T/P vs V and rpm for every APC prop | Proprietary terms unclear | [APC performance data](https://www.apcprop.com/technical-information/performance-data/) | Cross-check UIUC; source for E props and the windmill region (computed, label "borrowed computed") |
| QPROP/QMIL (Drela) | Prop + motor operating points, BEM with induced flow; motor models 1 and 2 | GPL | [QPROP](https://web.mit.edu/drela/Public/web/qprop/) | Offline tool only: generate tables, never link into the MIT app |
| Drela motor theory notes | Equations for L1/L2 electric | Public notes | [motor1](https://web.mit.edu/drela/Public/web/qprop/motor1_theory.pdf), [motor2](https://web.mit.edu/drela/Public/web/qprop/motor2_theory.pdf) | Implement from the equations (math is not copyrightable) |
| JSBSim FGPiston/FGPropeller/FGTurbine/FGElectric | Reference structures, defaults | LGPL-2.1 | [jsbsim src/models/propulsion](https://github.com/JSBSim-Team/jsbsim/tree/master/src/models/propulsion) | Read for structure; re-derive, do not copy code |
| CRRCSim power model docs | Battery/shaft/motor/gear/prop XML schema for RC | GPL-2 | [power_propulsion.html](https://sources.debian.org/data/main/c/crrcsim/0.9.13-3.2/documentation/power_propulsion/power_propulsion.html) | Schema ideas (brake flag, fold rpm, U_0rel table) |
| PX4 gazebo motor model | Up/down speed time constants | Apache-2.0 | [gazebo_motor_model.cpp](https://raw.githubusercontent.com/PX4/PX4-SITL_gazebo-classic/main/src/gazebo_motor_model.cpp) | Pattern only |
| Tyto Robotics (RCbenchmark) database | Community static tests: V, I, rpm, thrust, torque, efficiencies | Site terms (not checked) | [database guide](https://www.tytorobotics.com/blogs/articles/how-to-use-the-database-for-drone-motors-propellers-and-escs) | Validation points for G-E1 (static operating point) |
| Bauersfeld & Scaramuzza battery model | OTC LiPo model + fitted coefficients | arXiv paper | [arXiv 2109.04741](https://arxiv.org/pdf/2109.04741) | B2 structure; verify units |
| PyBaMM Thevenin | Reference ECM with thermal | BSD-3 (PyBaMM; via RESEARCH.md) | [PyBaMM repository](https://github.com/pybamm-team/PyBaMM) (equivalent-circuit Thevenin model; the old file path is a 404 on 2026-10-06) | Offline cross-check of B2 |
| L'Erario et al. jet model | Identified P100-RX thrust dynamics | arXiv paper | [arXiv 1909.13296](https://arxiv.org/abs/1909.13296) | Timing targets for AV-05 spool (derived numbers above) |
| eCalc, MotoCalc | Commercial electric calculators | Proprietary | not fetched | Reference sanity check only; never ingest outputs as data |
| BLHeli | Open ESC firmware docs | GPL-3 (via RESEARCH.md) | [BLHeli SiLabs README](https://github.com/bitdump/BLHeli/blob/master/SiLabs/README.md) | Behaviour lookup (brake, timing), no code |

## Parameters and data

| Quantity | Typical RC value | Unit | Kind | Source |
| --- | --- | --- | --- | --- |
| O.S. 61FX power | 1.9 PS @ 16,000 rpm (1,397 W) | W | manual | O.S. catalog via repo data |
| O.S. 55AX power, range | 1.75 PS @ 16,000; 2,000–17,000 | PS, rpm | manual (retailer copy) | falcon.com.kw (search result) |
| 61FX props | 12×6–8, 13×6–7 | in | manual | O.S. FX manual |
| 61FX tank | 350 cc (12 oz) | mL | manual | O.S. FX manual |
| Glow fuel nitro | 5–20 % preferred | % | manual | O.S. FX manual |
| .61 idle | 2,500–3,000 | rpm | estimated | repo data |
| .61 static rpm on 12×6 | 11,149 | rpm | derived (constant-torque assumption) | repo data; **measure** |
| .61 rotor inertia (prop+spinner+crank) | 3.5e-4 | kg·m² | estimated | repo data |
| DA-120 | 11.7 hp; 1,300–6,900 rpm; 2.25 kg | hp, rpm, kg | manual | desertaircraft.com |
| DA-120 props | 2-bl 27×11…29×10; 3-bl 26×12, 27×12 (tuned pipes) | in | manual | desertaircraft.com |
| DLE-120 | 12 hp @ 7,500; 2.895 kg; static thrust 9.5 kg @ 100 m (another copy says 26.5 kg) | hp, kg | manual (inconsistent) | macgregor.co.uk; search result |
| DA-100L | 9.8 hp; 1,200–6,200 rpm | hp, rpm | manual | desertaircraft.com |
| DA-100 fuel | 71 g/min @ 6,000 rpm (≈2.5 oz/min) | g/min | manual (compiled) | barnardmicrosystems.com |
| Gas BSFC | ≈580 | g/kWh | derived | from DA-100 numbers |
| Glow BTE | 4–17.5 | % | measured (7.45 cc) | IITM / SAE 2006-32-0056 (search result) |
| Glow burn at 1 kW | 30–57 | mL/min | derived | this doc |
| 120 cc rotor inertia (4-bl 26×12) | 0.0131 | kg·m² | estimated | repo data |
| Starter torque (JSBSim default) | 0.4·maxHP-equivalent; ω_st = 2·idle | — | borrowed | FGPiston |
| Electric .60: motor Kv | 400 | rpm/V | manual | E-flite Power 60 page |
| Motor R, i₀ (4120-class) | 0.02–0.04; 1.5–2.5 | Ω; A | estimated | this doc; **measure or take a datasheet** |
| Outrunner bell inertia (4120-class) | ~5e-5 | kg·m² | estimated | thin ring 0.1 kg at r 22 mm |
| LiPo cell IR (sport 5 Ah) | 3–5 | mΩ | estimated | retailer claims 1.2–5 mΩ (search results) |
| LiPo R_min, τ_RC | 4.5 mΩ; 3.3 s | mΩ; s | measured (fit) | Bauersfeld & Scaramuzza 2022 |
| LVC per cell | 2.8 / 3.0 / 3.4 | V | manual | Hobbywing Skywalker V2 |
| Soft LVC | 60 % power in 3 s | —, s | manual | Hobbywing |
| ESC start ramp | 200 / 500 / 800 | ms | manual | Hobbywing |
| ESC signal-loss cut | 0.25 | s | manual | Hobbywing |
| ESC thermal derate | > 120 °C to ~60 % | °C | manual | Hobbywing |
| Cu resistance tempco | 0.0042 | 1/°C | textbook | Drela motor2 |
| P100-RX idle/max | 44,000 / 154,000 rpm; 2 / 100 N; 80 / 390 mL/min | — | manual | JetCat 2017 catalog (repo doc) |
| P100-RX ṁ, V_e | 0.23 kg/s; 1,565 km/h | — | manual | JetCat (repo doc) |
| P100-RX throttle range (ECU) | 25–100 % | % | measured setup | L'Erario et al. |
| P100-RX spool up / down (90 %) | ≈3 / ≈1.9 | s | derived | L'Erario et al. model |
| Turbine spool (JSBSim default) | 2.0 up / 0.6 down | s | derived | FGTurbine defaults |

## Validation

**Verification (known answers, headless):**
1. Shaft step converges to `steady_rpm` (bisection) within 0.1 rpm at 0, 15, 30 m/s, for every throttle in 0.1 steps.
2. Free run-down with `Q_src = 0`, `Q_f = 0`, V = 0: `ω(t) = ω₀/(1 + kω₀t)` with `k = Cp₀ρD⁵/(8π³I)`. Match within 1e-4 relative after 5 s, at 30/60/144 fps (frame-rate independence).
3. Punch test: at tick 1 after full throttle from idle, the airframe roll moment equals `−(Q_src − Q_f)` within 1 % (requires `−ḣ`). **Mutation:** removing `−ḣ` must fail it.
4. Unloading: rpm at 35 m/s exceeds static rpm (shaft data) by ≥ 10 % for the 12×6 data. Mutation: freezing J at 0 fails.
5. Windmill: engine off at 15 m/s settles on the J where `Q_prop = −Q_f`; with friction 0 the J equals the Ct = 0 point ± table resolution.
6. Electric L1: no-load ω = K_V(V − i₀R); stall current V/R; maximum shaft power at ω ≈ ω₀/2; η from Drela eq. (7) matches the simulated `Q·Ω/(V·I)`.
7. Battery B1/B2: constant-current discharge reaches cutoff at `C/I` minus the R-drop correction (analytic); RC step response time constant τ_RC within 1 %. Soft LVC: power at 60 % ± 1 % after 3 s.
8. Turbine: spool up/down times equal the integral of the schedule; idle-to-max monotone; thrust at V = 0 equals the table.
9. Goldens: aircraft without the new data blocks replay bit-for-bit (the uncommitted slice already designs for "absent = D5 behaviour").

**Independent validation against real RC behaviour:**
- **Phone-audio tachometer (cheapest, owner can do it):** record a throttle step at the field and compute a spectrogram; firing frequency = rpm/60 (2-stroke single) gives rpm(t). That yields static rpm, idle rpm, step response, and in-flight unloading on a fly-by (correct for Doppler: average approach/recede). Compare static rpm with the derived 11,149 for the .61 + 12×6.
- **EdgeTX telemetry** (RPM sensor, current/voltage sensor on electric) gives rpm vs airspeed, and voltage sag and mAh vs time for flight-time validation.
- **Static thrust:** a luggage scale behind the model. Manufacturer thrust claims are inconsistent (DLE-120: 9.5 kg vs 26.5 kg) and are not validation data.
- **Electric static point:** compare G-E1 against a Tyto/RCbenchmark test of a similar motor/prop (±10 % current and thrust), or the owner's wattmeter.
- **Turbine:** spool times against the L'Erario-derived ≈3 s / ≈1.9 s and any JetCat ECU log.
- **PT4 pilot judgement (record per item):**
  - throttle response lag (idle → climb) feels right;
  - idle is reliable (no unintended dead stick with the realism layer off);
  - rpm audibly rises in a dive and sags in a climb;
  - torque roll on a punch;
  - dead-stick glide with a windmilling prop is plausible;
  - sound pitch and timbre;
  - the electric version's "instant" response and LVC fade are recognisable.

## Pitfalls and risks

1. **Missing `−ḣ`** delays the punch torque by the spool time. Mitigation: verification test 3 plus its mutation.
2. **J singularity and the 1 rpm cut-off:** a stopped prop has no drag and cannot be turned by the air. Mitigation: low-n (V-based) coefficients or a φ-table, plus a stopped-prop drag coefficient (estimated, labelled).
3. **Tables end before windmilling** (UIUC 11×6 at J 0.79). The P-51 BEM `cp_table` is exactly 0 for J ≥ 0.6, i.e. the windmill torque is clipped. Mitigation: extend the BEM script's output below Cp = 0; cross-check with APC computed files; label "derived".
4. **Explicit shaft step on stiff motors** (dt/τ → 1–2 for light, low-R, high-Kv setups). Mitigation: option C.
5. **Inflow from ground-relative velocity** (the uncommitted `_pre_step` uses `sim.state` and calm air) gives a wrong J in wind. Mitigation: pass the air-relative velocity, the same as `_loads`.
6. **Torque-curve shape decides static rpm and spool time**, and the repo has two undocumented shapes (one mislabelled). Mitigation: one documented estimated shape per engine class; a sensitivity sweep row in `research/sensitivity/`.
7. **Multiple or unstable equilibria** if `Q_src` rises with ω faster than `Q_prop` (a steep power curve, tuned-pipe bump). The bisection in `steady_rpm` assumes a single root. Mitigation: a loader check `dQ_src/dω < dQ_prop/dω` along the static curve; trim warns otherwise.
8. **ESC current ≠ battery current:** treating them as equal over-drains the battery at part throttle (factor 1/d). Mitigation: `I_batt = d·I_m` + test.
9. **Identified turbine polynomial diverges** outside its data (shown above). Mitigation: use only for timing targets.
10. **Fuel/battery mass changes break goldens and trim.** Mitigation: G4 off by default for existing goldens; new goldens record with it on; mass update only in `pre_step`.
11. **Audio synthesis cost in GDScript** (Godot docs warn). Mitigation: per-voice sample budget, sample-based voices, measure in `bench_physics`-like audio bench.
12. **Realism features frustrate** (random dead sticks). Mitigation: deterministic causes only (no RNG), a realism toggle, HUD hints ("engine rich at idle").
13. **Manufacturer numbers mix revisions and conditions** (P100-RX 2011 vs 2017; DLE thrust). Mitigation: one named revision per data file, as AV-00 did.
14. **Twin firing order unverified** (DA/DLE-120) changes sound and torque pulsation. Mitigation: label estimated; owner recording.

## Proposed roadmap steps

| Proposed ID | Step | Proof | Depends on |
| --- | --- | --- | --- |
| G1a | Propeller table hygiene: report out-of-range J per flight (counter in trace header); document the extrapolation floors per file | Unit tests on the file's own rows; a 40 m/s dive trace reports out-of-range ticks | — |
| G1b | Windmill and stopped branch: V-based coefficients for n·D < V/J_max, a stopped-prop drag coefficient, tables extended to Cp < 0 (BEM/APC, labelled) | Dead-stick glide L/D with stopped vs windmilling prop vs D8a's 8.46 (no-prop) — ordered and within the band set beforehand | G1a |
| G2a | Shaft balance (land the uncommitted P51-06 slice) for the Stik/Extra/P-51 with an air-relative inflow; `pre_step` receives state and wind | Throttle-step trace + unloading test (verification 1, 4); goldens of data without `shaft` bit-identical | — |
| G2b | Linearly implicit shaft update (option C) | Stability test with a synthetic rotor at dt/τ = 3 passes; verification 2 at 30/60/144 fps | G2a |
| G2c | Rotor-acceleration reaction `−ḣ` | Verification 3 plus its mutation | G2a |
| G2d | Throttle actuator: throttle servo slew + `admitted_fraction(θ)` table + combustion delay (estimated) | Step trace vs the owner's phone-audio tach (rpm(t) within a band set beforehand) | G2a |
| G2e | Engine states in aux (OFF / CRANKING / RUNNING), stop below 0.8·idle (JSBSim rule), starter law; `engine_running` retired | Scripted scenario: idle trimmed below the stall rpm stops within 2 s and stays stopped; trace logs the state | G2a, G1b |
| G2f | Realism layer (off by default): flood at rich idle, plug-heat cool-down, lean cut on fast throttle | Unit tests on each state; with the toggle off, goldens unchanged | G2e |
| G3a | Sound from telemetry: firing frequency, BPF, load-dependent harmonics; voices for glow single, gas twin | Headless FFT: peak at rpm/60 ± 1 bin at three rpm; owner check | G2a |
| G3b | Electric and turbine voices (BPF + whine; turbine tone at N/60 + broadband) | FFT peaks; owner check | G3a, G-E1, AV-05 |
| G4a | Fuel tank state + burn map (glow: BTE-based; gas: g/min table; turbine: mL/min table), engine stops at empty | Burn-out time at WOT within 5 % of the hand calculation | G2e |
| G4b | Time-varying mass, CG and inertia from tank/battery inventory (once per tick) | Trim drift trace over a tank (G4 proof) + CG shift vs hand calc | G4a |
| G5 | Multi-engine readiness: `powerplants[]`, per-plant aux block, twin test aircraft | Counter-rotating twin: net reaction torque 0 ± 1e-12; single engine-out yaw sign | G2a |
| G-E1 | Electric L1: Drela 3-constant motor + averaged ESC (d = throttle) + ideal battery; data schema `source.kind = "electric"` | Verification 6; an electric Stik variant trims and flies the handling test | G2b |
| G-E2 | Battery B1→B2: OCV(SOC), R₀, one RC, SOC in aux; brown-out when no real root | Verification 7; voltage-sag trace on a throttle punch | G-E1 |
| G-E3 | ESC behaviours: start ramp, LVC soft/hard, brake vs freewheel, signal-loss cut 0.25 s, arming | Unit test per mode; brake → stopped-prop glide | G-E2, G1b |
| G-E4 | Thermal: winding temperature with R(T), ESC derate | Sustained-WOT trace plateaus; derate at threshold | G-E2 |
| G-E5 | Static operating point validation vs measured data (Tyto test or owner wattmeter) | Table: current and thrust within ±10 % | G-E1 |
| G-E6 | Flight-time validation vs owner telemetry (mAh used per minute of a pattern) | Within ±15 % | G-E2, G4b |
| AV-05a | Turbine spool timing targets: accel/decel schedules fitted to ≈3 s up / ≈1.9 s down (sensitivity 2–5 s) | Verification 8 + sensitivity table | AV-05 |
| AV-05b | ECU states: OFF/START/IDLE/RUN/COOLDOWN, fuel-out flameout | Scripted scenario traces | AV-05a, G4a |
| PT4 | Playtest with the PT4 checklist above | Owner's scored checklist | G2a–G3a |

## Decisions to take now

1. **`pre_step` contract:** pass the start-of-tick rigid-body state and the wind (air-relative inflow). Otherwise G2, propwash (E0b) and smoke will each read `sim.state` their own way. *Recommended: change the Callable signature once, now.*
2. **Where ω lives:** aux with a linearly implicit update (option C), not in the RK4 state. *Revisit only if coupling errors show in a measured test.*
3. **Engine and energy states in aux** (state code, fuel, SOC, U_c, temperatures) so traces, goldens and replays capture them. *Recommended; retire the `engine_running` bool.*
4. **Propulsion data v2 = `powerplants[]`**, each `{source{kind: glow|gas|electric|turbine, …}, shaft, propeller|null, tank|battery ref, offset, axis, rotation}` plus top-level `tanks[]`/`batteries[]` with positions. The uncommitted `kind: glow_prop|turbine` single object can map onto it, but adopting the list before more files are generated avoids a second migration. v1 files keep loading through a legacy mapping; every number keeps `{value, unit, kind, source}`.
5. **Telemetry struct as the only interface for sound, smoke and HUD** (read-only, produced once per tick). *Recommended; never let audio pull from physics internals.*
6. **Realism toggles are deterministic and off by default** (no RNG in failure causes). *Owner decision on default difficulty.*
7. **Electric track ownership and priority:** most pilots fly electric. *Owner decision: whether G-E1 starts before G3/G4 or after PT4.*
8. **Measurement plan:** owner records a throttle-step audio clip of the real .61 (and the fly-by) to settle static rpm, spool time and unloading. *Cheapest decisive data; ask now.*

## Sources

1. O.S. Engines, "50SX / 40-46-61-91FX instruction manual" (incl. needle/mixture diagrams, glowplug, props, tank), n.d., https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/manual/50sx_40-91fx.pdf, fetched (pdftotext).
2. Desert Aircraft, "DA-120", 2026, https://www.desertaircraft.com/products/da-120, fetched.
3. Desert Aircraft, "DA-100L", 2026, https://www.desertaircraft.com/products/da-100l, fetched.
4. Desert Aircraft, "DA-170", 2026, https://www.desertaircraft.com/collections/all/products/da-170, fetched.
5. J.D. MacGregor, "DLE-120 Two-Stroke Petrol Engine", n.d., https://www.macgregor.co.uk/dleengine/dle120.htm, fetched.
6. Barnard Microsystems, "Two stroke engines" (compiled DA fuel data), n.d., https://barnardmicrosystems.com/UAV/engines/2_stroke.html, fetched.
7. Falcon Hobby, "OS MAX-55AX" specs, n.d., https://falcon.com.kw/os-max-55ax.html, search result only.
8. Kass M.D. et al., "Experimental evaluation of a 4-cc glow-ignition single-cylinder two-stroke engine", SAE 2014-01-1673, https://impact.ornl.gov/en/publications/experimental-evaluation-of-a-4-cc-glow-ignition-single-cylinder-t/, fetched (abstract).
9. "Performance Evaluation of a Mini I.C. Engine", SAE 2006-32-0056 (7.45 cc glow, BTE 4–17.5 %), https://saemobilus.sae.org/papers/performance-evaluation-a-mini-ic-engine-2006-32-0056, search result only.
10. M. Drela, "First-Order DC Electric Motor Model", MIT, 2007, https://web.mit.edu/drela/Public/web/qprop/motor1_theory.pdf, fetched.
11. M. Drela, "Second-Order DC Electric Motor Model", MIT, 2006, https://web.mit.edu/drela/Public/web/qprop/motor2_theory.pdf, fetched.
12. M. Drela, "QPROP/QMIL" (GPL), https://web.mit.edu/drela/Public/web/qprop/, fetched.
13. Hobbywing, "Skywalker V2 ESC user manual" (rev. 250814), 2025, https://www.hobbywing.com/en/uploads/file/20250930/64b726be7a56c9f415385f77683cdc46.pdf, fetched (pdftotext).
14. L. Bauersfeld, D. Scaramuzza, "Range, Endurance, and Optimal Speed Estimates for Multicopters", IEEE RA-L 2022, https://arxiv.org/pdf/2109.04741, fetched.
15. Horizon Hobby, "E-flite Power 60 Brushless Outrunner Motor, 400Kv", https://www.horizonhobby.com/product/power-60-brushless-outrunner-motor-400kv/EFLM4060A.html, fetched.
16. Grepow, "What is the internal resistance of a drone battery", https://www.grepow.com/blog/what-is-the-internal-resistance-of-a-drone-battery.html, search result only.
17. Tyto Robotics, "Database of Drone Motors, Propellers & ESCs", https://www.tytorobotics.com/blogs/articles/how-to-use-the-database-for-drone-motors-propellers-and-escs, search result only.
18. JSBSim Team, FGPiston.cpp, https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/propulsion/FGPiston.cpp, fetched.
19. JSBSim Team, FGPropeller.cpp, https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/propulsion/FGPropeller.cpp, fetched.
20. JSBSim Team, FGTurbine.cpp and FGTurbine.h (LGPL), https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/propulsion/FGTurbine.cpp, https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/propulsion/FGTurbine.h, fetched.
21. JSBSim Team, FGElectric.cpp, https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/propulsion/FGElectric.cpp, fetched.
22. FlightGear wiki, "JSBSim Engines", https://wiki.flightgear.org/JSBSim_Engines, search result only (HTTP 403 on fetch).
23. CRRCSim 0.9.13, "Power/propulsion documentation", https://sources.debian.org/data/main/c/crrcsim/0.9.13-3.2/documentation/power_propulsion/power_propulsion.html, fetched.
24. PX4, gazebo_motor_model.cpp (Apache-2.0), https://raw.githubusercontent.com/PX4/PX4-SITL_gazebo-classic/main/src/gazebo_motor_model.cpp, fetched.
25. ArduPilot, "Internal Combustion Engine", https://ardupilot.org/plane/docs/common-ice.html, fetched.
26. G. L'Erario et al., "Modeling, Identification and Control of Model Jet Engines for Jet Powered Robotics", IEEE RA-L 2020, https://arxiv.org/abs/1909.13296, fetched (PDF text).
27. G. Cican, "Experimental Transient Process Analysis of Micro-Turbojet Aviation Engines…", Energies 17(6) 1366, 2024, https://ideas.repec.org/a/gam/jeners/v17y2024i6p1366-d1355730.html, fetched (abstract).
28. Model Airplane News, turbine throttle response article, https://www.modelairplanenews.com/?p=265540, search result only.
29. Stunt Hanger forum, "What does 'unload in the air' mean", https://stunthanger.com/smf/engine-set-up-tips/what-does-'unload-in-the-air'-mean, search result only.
30. Godot Engine docs, "AudioStreamGenerator" (stable), https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html, fetched.
31. JetCat, catalog 2017 and RX manual 2011 (P100-RX figures), via [avanti-s-turbine-research.md](../avanti-s-turbine-research.md), fetched there.
32. NASA Glenn, "Thrust equation", https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/, via the repo's turbine research, fetched there.
33. UIUC Propeller Data Site; APC performance data; PyBaMM Thevenin; BLHeli: as cited in [RESEARCH.md](../../../RESEARCH.md#electric-propulsion-distinguish-the-components-and-their-evidence), fetched there.
