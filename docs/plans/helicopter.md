# Helicopter plan: a realistic RC helicopter

**Date:** 2026-10-14. **Status:** the experimental helicopter is playable through Home → Fly and the direct route. A generated X-Cell reference preset, coupled body/main/tail mechanics, trainer and heading controller, terrain-aware hover trim, skids, ground-strike stop and native checkpoint/trace lifecycle are integrated. The supplied HX-700 Blender source supplies the visual. The new articulated source is reviewed under HELI-25b; its integration is planned in §8.1.1. [Current controls and limits](../HELICOPTER.md); [HELI-16 software evidence](../research/helicopter/HELI-16/README.md). Physical validation, automatic C/M event localization, separate engine/freewheel and servo states, full scenery contact, environmental VFX/audio and H15 performance remain open.
**Prefix:** HELI-00…HELI-36, registered in the [track registry](../README.md#tracks-plans-and-step-ids). `H1…H15` (Phase H) is a different namespace.
**Owner:** helicopter track, under the main line's acceptance; owns the shared inflow law consumed by the drone track.
**Owns:**
- `app/physics/rotorcraft/` and `app/physics/rotorcraft_data.gd`
- `app/data/aircraft/xcell_60_research.json` (generated) and `app/data/schema/openrc-rotorcraft-v2.schema.json`
- `app/sim/helicopter_flight_session.gd`, `app/sim/rotorcraft_recorder.gd`, `app/helicopter_main.*`
- `app/aircraft/<heli>_*.gd` and `assets/aircraft/<heli-id>/`
- `app/render/rotor/`
- `app/tests/test_heli_*.gd`, `app/tests/bench_rotorcraft.gd`
- `research/helicopter/` and `docs/research/helicopter/`

**Coordinated, not owned:**

| Owner | Files |
| --- | --- |
| Main line | `app/sim/simulation.gd`, `app/sim/flight_session.gd`, `app/sim/trace.gd`, `app/main.gd`, `app/tests/replay_policy.gd`, golden flights, `app/input/` |
| Ground track | `app/physics/ground_contact.gd` |
| Catalog / menu track | `app/app_state/aircraft_catalog.gd`, `app/ui/`, `app/i18n/es.po` |
| Stik model track | `app/render/airplane.gd` |
| Landscape / visual | `app/render/near_grass.*`, `app/render/ground.gdshader`, `app/project.godot` (global shader uniforms) |
| Smoke track | SM-00/SM-01 |
| Audio track | `app/audio/` |
| Flight-overlays track | `app/render/overlays/` |
| Crash track | `app/render/crash/`, CR-01d hull labels |
| Aircraft standardization | [AIRCRAFT_CONTRACT](../../AIRCRAFT_CONTRACT.md) |

**Evidence:** [HELI-01 research record](../research/helicopter/HELI-01/README.md) holds the sources, parameter tables, derived numbers and the seam map with line references.

**Goal.** Fly one RC helicopter whose physics comes from published, identified data. Hover, translational lift, flap-back, ground effect, vortex ring state, tail authority limits and autorotation must emerge from the equations, not from scripted effects. Present it so a pilot standing at the field reads it as a real model helicopter:

- a rotor disc that never strobes
- downwash that bends the grass in proportion to thrust and height
- a sound that follows rotor load

The airplanes must not change: every existing golden flight, trace and capture stays byte-identical.

## 1. Why this is a scope decision

[DECISIONS](../../DECISIONS.md) opens with "Build an RC airplane simulator". The [data-pipeline investigation](../research/roadmap-investigations/09-aircraft-data-pipeline.md) placed helicopters out of scope and reserved `"vehicle": "rotorcraft"`.

A helicopter is a second vehicle class. It is not a fifth airplane:

- different controls (collective, cyclic, tail pitch, flight modes)
- a different power chain (governed rotor speed, freewheel)
- onboard electronics (gyro or flybarless unit)
- a different trim (hover)
- a different contact (skids)
- a different crash cause (blade strike)

The owner authorized implementation on 2026-10-13; the scope extension and shared-kernel order are recorded in [DECISIONS](../../DECISIONS.md). The first playable route pairs X-Cell reference physics with the supplied HX-700 visual and explicitly estimated trainer/drive settings. It starts in a solved airborne hover. A ground spool-up lifecycle remains a separate step.

What makes it tractable now:

- The float64 RK4 core already carries arbitrary continuous states, tick-held auxiliary state, discrete modes and gyroscopic rotor momentum.
- The v2 contract culture (every number with unit, kind and source) fits identified rotorcraft data well.
- The coupled-shaft work (G2a/G2b) is a direct template for rotor speed.

## 2. Starting architecture (2026-10-13)

The seam audit below describes the tree before helicopter integration. Current implemented behavior belongs to [HELICOPTER](../HELICOPTER.md); the remaining acceptance work is listed in §9. Published equations and software checks do not establish that the HX-700 visual has X-Cell physical properties.

Line references are recorded in [HELI-01 §9](../research/helicopter/HELI-01/README.md#9-code-seams-on-2026-10-13); verify them before editing.

| # | Finding | Where | Consequence |
| --- | --- | --- | --- |
| F1 | **The rigid body and integrator are vehicle-neutral.** 13 body states. `RB.derivative` already takes a summed rotor momentum `h`. RK4 is generic over array length. | [rigid_body.gd](../../app/physics/rigid_body.gd), [integrator.gd](../../app/physics/integrator.gd) | No core rewrite. |
| F2 | **There are three tiers of extra state.** `aux` is sampled once per tick and held through the RK stages. `modes` is discrete integer state. `continuous` is integrated inside RK4 with a joint `{loads, derivative, rotor_momentum}` callback. | [simulation.gd](../../app/sim/simulation.gd) | Rotor speed, flapping and inflow go in `continuous`. Servos, governor and gyro go in `aux`. Flight modes go in `modes`. |
| F3 | **The coupled shaft rpm is a complete template for a new continuous state.** It covers layout, derivative, aux mirror, reset, checkpoint format, restore whitelist, trace metadata and replay class. | [flight_session.gd](../../app/sim/flight_session.gd) `_settled_continuous`, `_coupled_response`, `checkpoint`, `restore_checkpoint`, `trace_meta`; [replay_policy.gd](../../app/tests/replay_policy.gd) | Follow the same nine touch points (HELI-17). |
| F4 | **Inputs are four channels end to end.** `var inputs := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])`, plus the trace `cmd_*` columns, golden format and radio calibration steps. | [simulation.gd:24](../../app/sim/simulation.gd#L24), [rc_calibration.gd](../../app/input/rc_calibration.gd), [trace.gd](../../app/sim/trace.gd) | A helicopter also has four sticks; keep the width (D6). Flight-mode switches become `modes`. |
| F5 | **There is no load-contributor interface.** Aero + propulsion + slipstream + ground are summed by hand in three session callbacks. | [dynamics.gd](../../app/physics/dynamics.gd) `_components_from_air`; `flight_session.gd` `_wash_loads`, `_wheel_evaluate`, `_coupled_response` | Add **one** rotorcraft evaluate callback beside them; do not refactor the airplane paths. |
| F6 | **Gyroscopic coupling is single-axis and single-rotor.** | [rotor_coupling.gd](../../app/physics/rotor_coupling.gd) | Generalize to a geared main + tail rotor with one degree of freedom (§4.8). |
| F7 | **The loader is airplane-only.** v2 is down-converted to v1. It requires a wing reference, 32 stable-airplane derivatives with sign checks, a tail and fin, and a thrust axis within ±10° ([aircraft_data.gd:829](../../app/physics/aircraft_data.gd#L829)). | [aircraft_data.gd](../../app/physics/aircraft_data.gd), [aircraft_contract.gd](../../app/physics/aircraft_contract.gd) | A separate rotorcraft derive path that reuses the quantity, inventory, inertia and identity kernels (D5). |
| F8 | **Trim is forward flight only.** Modes are `level`/`glide`, V > 0 is required, and session preparation refuses flight if trim fails. | [trim.gd](../../app/physics/trim.gd), `FlightSession._prepare_aircraft` | Hover and forward rotorcraft trim (HELI-18). |
| F9 | **Contacts use a rolling-tyre law with anchors.** Ground start is Stik-only (`RUNWAY_AIRCRAFT_ID`). | [ground_contact.gd](../../app/physics/ground_contact.gd), [ground_start.gd](../../app/physics/ground_start.gd), [flight_session.gd:234](../../app/sim/flight_session.gd#L234) | Isotropic skid friction and a pad start (HELI-19, HELI-20). |
| F10 | **Crash is terminal on any hull point.** There is no rotor-disc check. The component guess uses wing span. | `flight_session.gd`, [director.gd](../../app/render/crash/director.gd) | Disc-clearance blade strike (HELI-21) and rotorcraft components (HELI-33). |
| F11 | **Render, audio and HUD read `aux[0]` as one propeller rpm.** `main.gd` spins `_airplane.propeller.rotation.z`. The blur draws a flat disc that cross-fades between 12 and 48 blade passings per second. | [main.gd:912](../../app/main.gd#L912), [propeller_blur.gd](../../app/render/propeller_blur.gd), [soundscape.gd](../../app/audio/soundscape.gd), [overlay_manager.gd](../../app/render/overlays/overlay_manager.gd) | Rotor telemetry needs its own published state; the disc needs coning, TPP tilt and coverage (HELI-26). |
| F12 | **There are no flight-time particles and no local ground disturbance.** The only particles are crash `CPUParticles3D` (556). No `GPUParticles3D` exists. Smoke SM-00 (Compatibility probe) and SM-01 (exhaust anchor) are not started. Near grass reacts only to the global `wind_vec`, within 30 m of the pilot, and not on runway or mown surfaces. | [effects.gd](../../app/render/crash/effects.gd), [SMOKE-PLAN](../SMOKE-PLAN.md), [near_grass.gd](../../app/render/near_grass.gd) | Rotor wash is new work; the pad's surface decides what can react (§8.3). |
| F13 | **Performance budget.** A tick must stay ≤ 500 µs (Gate P open). The Stik measures 200–445 µs per tick. Local strips cost ≈ 2.3–3.6 µs per element evaluation. The P-51 fails at 733–880 µs. A distributed GDScript quadrature cost 1.2–1.6 ms per evaluation. | [H15](../research/simulation-state/H15/README.md), [H12](../research/simulation-state/H12/README.md) | The rotor model must cost about one `Aero.loads` call per stage. Per-blade element marching is excluded (§4.1). |
| F14 | **The catalog supports a PREVIEW entry** with `data=""` that refuses Fly (Timber). | [aircraft_catalog.gd](../../app/app_state/aircraft_catalog.gd) | Ship the visual helicopter as PREVIEW before its physics (HELI-25). |

## 3. Reference aircraft and data policy

**Recommendation (D2): the MIT Miniature Aircraft X-Cell .60 SE, as flown and identified by Gavrilets, Mettler and Feron.** It is the only RC helicopter with a numerically complete published parameter set:

- measured mass and inertias
- identified hub stiffness, measured blade inertia and rotor and tail geometry
- empennage and fuselage drag areas
- gear ratios and engine power
- governor gains identified from an rpm step
- servo transfer functions

It also has nonlinear validation against flight data up to µ < 0.15 and a CIFER identification companion. It is also a .60 nitro, the owner's preferred class. Every alternative (Align T-Rex 700X, SAB Goblin 700) has retail geometry only: its stiffness, inertias, time constants and profile drag would all be estimates.

Consequences to state honestly:

| Item | Fact | Policy |
| --- | --- | --- |
| Configuration | 8.2 kg **instrumented** (avionics on board); flybar head | Fly the validated configuration first, named as such (D3). A stock variant re-estimates m and J and is labelled `estimated`. |
| Head | Bell-Hiller flybar lumped into a first-order rotor (τe ≈ 0.1 s, Kµ 0.2) | The electric HX-700 is the current second-aircraft candidate (HELI-36a). Walker/Tischler 360CFX/R-50 work informs model structure; its identified gains/stiffness do not identify this 700-class head. |
| Validity | µ < 0.15 (≈ 20 m/s), as published | The data file declares the qualified envelope; telemetry warns beyond it. |
| Estimated inputs | a_mr borrowed (5.5); C_D0 0.024, C_Tmax, tail a/C_Tmax and γ_fb estimated | Kinds copied verbatim from the paper into `kind`/`source`. |
| Missing | Visual geometry of the actual airframe; tail-gyro details | A visual asset from photos and drawings with provenance (HELI-25); gyro gains `estimated` until a source is read (HELI-02). |

Derived reference values used by tests are listed in [HELI-01 Derived checks](../research/helicopter/HELI-01/README.md#derived-checks):

- Lock number 3.71
- flap time constant τf 25.8 ms
- hover induced velocity v_h 4.17 m/s
- inflow time constant τλ 39 ms
- hover torque ≈ 6.6 N·m and hover power ≈ 1.1 kW (figure of merit ≈ 0.30)
- rotor–fuselage modes 20.1 rad/s (roll) and 14.6 rad/s (pitch)

## 4. Physics architecture

### 4.1 Fidelity choice

The core combines three levels from [HELI-01 §2](../research/helicopter/HELI-01/README.md#2-fidelity-ladder-and-time-step):

- (a) momentum-theory thrust and inflow
- (b) first-order tip-path-plane (TPP) flapping with a hub spring
- (d) one dynamic-inflow state, with Johnson's VRS law and Hayden ground effect

This is the Gavrilets/Heffley–Mnich model family, the one validated for this aircraft.

- **Accepted:** all three levels are non-stiff at 240 Hz RK4.
  - Flap dt/τ = 0.16.
  - Inflow dt/τ = 0.11.
  - The fastest coupled body–rotor mode for any planned aircraft is ω·dt = 0.33, against RK4's ≈ 2.8 stability bound.
- **Rejected: per-blade azimuth time-marching.**
  - The rotor turns ≈ 40° per 240 Hz tick, and 50–75° on modern heads.
  - That corrupts the 90° gyroscopic phase that defines cyclic response and aliases 2/rev loads into steady bias.
  - Doing it right needs 0.8–1.8 kHz substeps, which the 500 µs budget cannot afford in GDScript.
- **Deferred, behind capabilities:**
  - 3-state Pitt-Peters (transverse-flow effect)
  - disk-quadrature blade element (retreating-blade stall at high µ)
  - Leishman–Beddoes dynamic stall
  - Each is admitted only with its own known-answer test and cost measurement.

### 4.2 Frames, signs and units

Body FRD at the inventory CG and NED world, per [AIRCRAFT_CONTRACT](../../AIRCRAFT_CONTRACT.md#coordinates-signs-and-units). Structural positions are in the datum frame `[x_aft, y_right, z_up]`; the rotorcraft datum is the main-rotor shaft axis at the skid plane.

Rotor quantities:

| Symbol | Meaning |
| --- | --- |
| Ω ≥ 0 | Main-rotor speed, rad/s |
| `rotation_sense` ±1 | Explicit data field (clockwise from above is +1) |
| a1 > 0 | TPP tilted aft: thrust tilts aft, nose-up moment |
| b1 > 0 | TPP tilted right: right-roll moment |
| θ0 | Root-extrapolated collective pitch in the blade-element formula; swash θ75 converts as θ0 = θ75 − 0.75·θtw |
| A1, B1 | Lateral and longitudinal cyclic blade pitch |
| θ_tr | Tail-rotor pitch |

All angles are radians internally; data files use the contract's exact units. The kernel tests pin the signs:

- forward cyclic tilts the disc forward and gives a nose-down moment
- a positive body pitch rate makes the disc lag aft relative to the body (ȧ1 = −q …)
- the main-rotor reaction torque yaws the fuselage opposite to `rotation_sense`
- the tail-rotor thrust sign cancels that yaw at trim

### 4.3 Main-rotor thrust and inflow

The air velocity at the hub is the CG air velocity plus ω × r_hub. It is resolved in the shaft frame, giving the advance ratio µ (in-plane) and µz (along the shaft), normalized by ΩR.

**Main thrust** (Gavrilets §4.1.1, Eqs. 5/6, untwisted X-Cell blades):

    C_T = (aσ/2)·[θ75(1/3 + µ²/2) + (µz − λ0)/2]
    C_T ← clamp(C_T, −C_Tmax, +C_Tmax)                              (published hard saturation)
    T   = C_T·ρ·πR²·(ΩR)²

The primary paper says the main blades have no twist, so θ75 = θ0. It omits cyclic/rate terms on thrust as second order in its µ < 0.15 range. HELI-05 follows that choice. A future twisted-blade model must derive its pitch datum and radial moments separately. `µz = -climb/(ΩR)` maps the shaft-relative air velocity to HELI-04's positive-climb convention.

**Dimensional inflow state vi** (continuous, selected first-order approximation):

    τ·v̇i = vi_target − vi,     τ = 0.849R / (4·max(V_eff, V_floor))
    V_eff = √(V_cross² + (vi + V_climb)²)
    λ0 = vi/(ΩR)               diagnostic/conversion only while Ω > 0

- The stage's current vi enters C_T once, then its actual T drives the Johnson equilibrium target. [HELI-05a](../research/helicopter/HELI-05/README.md#joint-main-rotor-stage) performs this joint evaluation without a persistent query cache or thrust fixed-point iteration.
- The dimensional state retains residual wake when the disc becomes inactive, and never divides state by Ω at stop. V_floor is an explicit model parameter in m/s. The original HELI-04 ratio helper remains a research compatibility path.
- The time law extends Gavrilets' hover Eq. 1; it is not a physically validated transient Johnson/Pitt-Peters model. [HELI-04-R1](../research/helicopter/HELI-04-R1/README.md) records its scope and the known-event integration procedure.
- κ ≈ 1.10–1.15 is a Johnson target loss field. Gavrilets' η_w ≈ 0.9 belongs to his original momentum iteration and is not applied a second time to the chosen Johnson target.

**Vortex ring and windmill-brake states** (Johnson NASA/TP-2005-213477):

- Inside Johnson's region, `λ_target` comes from his normalized inflow curve, built from cubic segments through the published Table 4 breakpoints. VRS instability factor f ∈ [0, 1] is a data field; start at 1.
- Beyond Vz < −2v_h, the windmill-brake momentum branch takes over.
- Everything is expressed relative to the thrust vector, so inverted descent uses the same curve.
- At RC scale VRS begins at 1.5–6 m/s descent. That is reachable in normal flying, so this branch is core, not decoration.
- **Source-law gate:** literal Table 3 has C/M crossflow jumps. [HELI-04-R1](../research/helicopter/HELI-04-R1/README.md) shows that raw 240 Hz RK4 misses the 1e-3 m/s fixture tolerance; exact known-event splits plus bounded local refinement pass. The session still needs automatic state-dependent detection and complete-load cost qualification. No undocumented smoothing or flight-ready claim is permitted.

**Ground effect** (Hayden near-hover correction): λ ← λ·0.9926/k_G with k_G = 0.9926 + 0.03794·(2R/z)². Normalizing the empirical intercept preserves unity at infinite clearance; this convention is explicit in the reference and GDScript kernel.

- z is the hub height above the terrain under the hub, measured along the thrust axis and clamped at z/R ≥ 0.5.
- The session already supplies the terrain height (`GroundTerrain.sample_validated`).
- The standalone API uses `height_over_radius = -1` to disable it. A nonnegative value means the caller established that the downstream wake meets terrain; the sign of body-axis thrust cannot establish that geometry during inverted flight. Full reflected forward-flight flow is deferred.
- Cheeseman–Bennett is an independent check in tests.
- Ground effect is strong on the pad: an X-Cell on skids is at z/R ≈ 0.5–0.6.

**Translational lift** emerges from µ in the momentum relation. **Flap-back and blowback** come from the flapping terms below. **Neither is a separate effect.**

### 4.4 Flapping (first-order TPP, hybrid form)

    ȧ1 = −q + [−a1 − A_lon·δforward + (∂a1/∂µ)·µx + (∂a1/∂µz)·µz]/τe
    ḃ1 = −p + [−b1 + B_lat·δright + (∂a1/∂µ)·µy]/τe

- **X-Cell (flybar lumped):** τe = 16/(γ_fb·Ω) and gains B_lat = A_lon = 4.2·(Ω/Ω_nom)².
- **Flybarless:** τf = 16/(γ_eff·Ω) with γ_eff = γ/(1 + aσ/(16λ)).
- Flap-back: ∂a1/∂µ = 2·Kµ·(4θ0/3 − λ0).
- Eq. 26 makes the substituted lateral-flow term positive. Body p/q already have units rad/s and remain outside the angle/τ bracket. Cross-coupling is omitted by the X-Cell source; it enters only with separately matched data.
- The axial derivative follows Eq. 27 with total µ and explicit inferred `sign(u)` for backward flow. Its algebraic domain µ < √2 is distinct from the identified µ < 0.15 and |a1|/|b1| < 10° flags.
- Cyclic inputs are blade-pitch angles produced by the swashplate (§4.9), not stick values.

### 4.5 Hub forces and moments

- **Thrust direction.** Thrust acts along the exact TPP normal `n = normalize(−sin a1, sin b1, −cos a1·cos b1)`, not a small-angle form, so loops and inverted flight stay valid. It is applied at r_hub; the moment is r_hub × F.
- **Hub spring moment.** Add L_s = K_eff·b1 and M_s = K_eff·a1, with K_eff = n_b·Kβ/2 + n_b·Mβ·Ω²·e/2. The X-Cell data gives Kβ = 54 N·m/rad directly. Its spring is ≈ 74 % of the cyclic moment, so the hub term is not optional.
- **Main-rotor torque:**

      Q_mr = ρπR³(ΩR)²·[C_T·(λ0 − µz) + (σ·C_D0/8)·(1 + 7µ²/3)]

  - It is applied about the shaft with sign −`rotation_sense`.
  - HELI-05 follows constant C_D0 and 7/3 from Gavrilets Eqs. 11/12. A pitch-dependent profile-drag law is a separate extension requiring data; it is not silently imported into this reference.
  - At Ω = 0 the azimuth-averaged disc is inactive: zero rotor loads/spring moments/flap rates and no λ/µ conversion. Parked individual-blade mechanics are excluded; the separate dimensional wake can still decay.
- **Fuselage/empennage loads (HELI-06b).** Use explicit AIR-velocity increments at each center of pressure: `vrel = vCG,air + ω×r − vwake`. Fuselage force is `F_i = −½ρS_i vrel,i |vrel|`. This retains the source magnitude form and corrects its inconsistent wake/force signs through an explicitly named passive extension. A downward wake produces downward fuselage download. [Source and passivity audit](../research/helicopter/HELI-06b/README.md); no α/β or zero-speed divisions.

### 4.6 Tail rotor, fin and stabilizer

- **Tail rotor.** Momentum theory without flapping at Ω_tr = n_tr·Ω.
  - HELI-06a follows Gavrilets §4.6's **locally linearized** thrust model. The paper explicitly avoids direct thrust/inflow iteration because it can fail in the tail's own wake. At each in-plane advance ratio, solve only the positive zero-normal-flow trim with a monotone residual and bounded safeguarded solver, then derive the local collective/normal-flow slopes. Apply Eq. 47 to actual collective (including its trim offset), cap CT, and reconstruct vi with Eq. 50. There is no arbitrary five-pass convergence claim.
  - The explicit wake-efficiency parameter transfers Eq. 4's main-rotor η to this tail trim calculation; the source gives no tail-specific η. η=1 recovers the printed hover derivatives in Eqs. 9/10. This inference and Eq. 47's lack of an affine trim intercept are recorded in [HELI-06](../research/helicopter/HELI-06/README.md).
  - Quasi-static tail response is a source-model approximation, not a result established by its lag being near dt. Sideways VRS, transient authority and tail-flow timestep sensitivity remain qualification gates; no Johnson tail extension is silently applied.
  - Inflow uses µz,tr = (v_a − l_tr·r + h_tr·p)/(Ω_tr·R_tr), including the main-rotor wake intensity K_λ (Gavrilets geometric ramp 0 → 1.5).
  - Thrust is capped at C_Tmax,tr·f_t·ρ(Ω_tr·R_tr)²·πR_tr², with fin blockage f_t = 1 − ¾·S_vf/(πR_tr²). **Tail blowout and authority loss at drooping rpm emerge from this cap.**
- **Fin and horizontal stabilizer.** HELI-06b normal forces oppose local relative normal velocity and use the source magnitude forms with dynamic-pressure caps; all moments use the full CP arm once. The printed positive horizontal-force sign would inject relative-flow energy in FRD and is not used. Local relative work is nonpositive, while moving wakes can supply positive body work.
- **Joint prescribed-speed aerodynamics (HELI-06c).** Evaluate main-hub point flow, main rotor/inflow, tail and airframe once per RK stage. The named shaft-aligned wake approximation uses main vi on the fuselage, the tail's Kλ·vi on both tail surfaces, and explicit tail-wake exposure ε·vi,tr on the fin. Density, main radius and fin blockage/load area must agree across prepared contexts. No stage load or flow is reused across calls. Full drive/body coupling and spatial/inverted wake qualification remain open.

### 4.7 Drive train, engine and governor

    I_Ω·Ω̇ + b·ω̇ = η_g·n_es·Q_e − Q_mr − n_tr·Q_tr − Q_loss(Ω)
    I_Ω   = I_mr + n_tr²·I_tr (+ n_es²·I_eng while engaged)

| Element | Phase 1 (X-Cell, as published) | Later |
| --- | --- | --- |
| Engine | Published airborne power approximation is the reference; startup needs an explicit finite available-torque limit plus power limit, with delivered power Q_e Ω_e. No P/Ω singularity or arbitrary RPM floor. Required torque/starter data remain open. | Reuse the shaft `engine_torque` curve (idle/peak power, friction) once matched data exist. A stopped nitro engine is not self-starting. |
| Clutch / freewheel | One-speed proxy: Q_e ≥ 0; hold sets drive torque to zero with declared lumped inertia. This does not claim actual engine disengagement. Include engine momentum if engine inertia remains coupled. | A second shaft state (engine Ω_e) with clutch slip, overrun/freewheel and engagement events, using the [event-bracket](../../app/physics/event_bracket.gd) pattern. |
| Governor | **Discrete** PI at 240 Hz in `aux`, with anti-windup and throttle-curve feed-forward. Kp 0.01 s/rad, Ki 0.02 /rad (derived from the published rpm step). | ESC governor for an electric aircraft, on the existing motor/supply laws with an ESC kind `governor`. |
| Autorotation | Emerges from Q_mr(θ0, λ, Ω) = 0 with Ω as a state and the C_d(α̂) law. No mode switch. | — |

**Gyroscopics.** Generalize `RotorCoupling.response` from one unit axis to a geared rotor vector, keeping the exact simultaneous solve:

- b = I_mr·a_mr + n_tr·I_tr·a_tr (+ n_es·I_eng·a_eng when engine inertia is coupled); axes include each shaft's spin sense
- denominator I_Ω − bᵀJ⁻¹b
- momentum h = Ω·b

The airplane call path keeps its existing arithmetic, with a byte-identity test.

[HELI-07/08 audit](../research/helicopter/HELI-07/README.md) records the simultaneous solve, existing aerodynamic torque ownership, full angular-energy test and remaining startup/freewheel/low-RPM gates. Do not add a second engine reaction to kernel moments already containing aerodynamic shaft torque.

### 4.8 State inventory

The implemented experimental state is body13 plus `[Omega,a1,b1,vi,heading_reference,yaw_integral]`, with one RPM mirror in `aux`. Normal/idle-up, trainer and zero-drive settings are checkpointed session controls. The expanded discrete hardware inventory below is a future target; its servo and separate-engine states are not in the current flight.

| Tier | Entries | Notes |
| --- | --- | --- |
| Body (existing) | 13 | Unchanged |
| `continuous` (RK stages) | Ω, a1, b1, vi (4); later +λ1c, λ1s, the flybar c/d pair, Ω_e | HELI-05a evaluates the three-state main disc/wake stage; complete drive/tail joint payload and rotor momentum remain HELI-16/17 |
| `aux` (tick-held) | 4 servo positions (3 swash + tail); governor integral; gyro heading-hold integral and reference; telemetry mirrors (rpm, collective) | Sampled once per tick, like a real 240 Hz controller output |
| `modes` (discrete) | `flight_mode` (normal / idle-up / hold); `electronics_mode` (rate / heading-hold / self-level where the hardware supports it) | Tick-transactional |

Real onboard controllers run at 1–4 kHz [U] and sample sensors discretely. Modelling the gyro and governor as discrete 240 Hz controllers in `aux` is faithful to that structure. It also keeps RK stages free of controller discontinuities.

### 4.9 Control chain (what the pilot moves → what the blade sees)

The current trainer uses authored estimated curves and controller gains, continuous heading/rate feedback and instantaneous limited swash geometry. The full servo-lag/hardware chain below remains the target for identified controller work.

    sticks (4) ─► flight-mode curves ─► electronics (gyro / FBL / flybar-lumped) ─► CCPM mixer ─► servo rate & lag ─► swash geometry ─► θ0, A1, B1, θ_tr
                  (pitch curve, throttle curve, idle-up, hold)                          (120° eCCPM)    (per servo)

- **Curves.** Pitch and throttle curves are 5-point tables per flight mode, as on a real transmitter.
  - The simulator owns them because radios in USB-joystick mode send raw sticks.
  - Defaults come from the reference manual; the owner can edit them later (UI is out of scope here).
- **CCPM mixing happens before the servos**, and rate limits apply **per servo**, not per axis. A large collective plus cyclic command therefore saturates the way a real swash does.
- **Swash geometry** maps servo travel to blade pitch through declared linkage ratios. Phase 1 uses linear ratios with declared limits (X-Cell: 5.5° cyclic, 10.5° collective).
  - The pure swash's pitch harmonics and the identified main-rotor logical cyclic inputs have different conventions. Pin the mechanical/azimuth phasing from aircraft data before connecting them; HELI-05 does not establish that mapping.
- **Servo dynamics.** The existing rate limit, plus an optional first-order lag fitted to the published S9402/S9450 responses (data fields). A full second-order servo state is deferred.
- **Tail gyro.** Heading-hold PI on yaw rate, with collective/cyclic torque precompensation feed-forward. Gains are `estimated` until a source is found (HELI-02).

### 4.10 Ground, pad and blade strike

- **Skids.** Each skid tube gets front and rear contact points (four in total; the gear topology checks pass with two ahead and two aft of the CG). They use a new **isotropic regularized Coulomb** contact mode:
  - the friction circle is not tied to a heading
  - stiction anchors are reused
  - there is no rolling resistance

  This is a contract `gear` capability `skids` owned with the ground track. Dynamic rollover (pivoting on one skid under lateral drift and cyclic) is a required emergent test, not a special case.
- **Pad start.** A static solve on the skids, generalizing `ground_start.gd`. Engine at idle or hold engaged, rotor stopped, then a spool-up lifecycle: the governor soft-start ramp (data field) brings the head to speed.
  - The airborne trimmed-hover start remains for tests and as a menu option.
- **Blade strike.**
  - The terminal hull keeps fuselage, boom and skid points.
  - A **rotor-disc clearance ring** adds 16 points on the main TPP circle (moving with a1/b1 and coning) and 8 on the tail-rotor circle. They are checked against terrain and scenery proxies each tick while Ω > Ω_min.
  - A crossing ends the flight with cause `main_rotor_strike` or `tail_rotor_strike`.
  - Ground resonance is not representable (no lead-lag degree of freedom) and is a declared non-goal.

### 4.11 Trim and linearization

- **Hover and forward trim.**
  - Unknowns: [θ0, A1, B1, θ_tr, θ, φ] plus the rotor states [a1, b1, λ0].
  - Residual: the six body accelerations plus the three rotor-state derivatives.
  - Ω is held at the governor setpoint, and engine power is an output.
  - The trim reuses the Newton/finite-difference-Jacobian skeleton and `solve_linear` from [trim.gd](../../app/physics/trim.gd) in a separate module, so airplane trim is untouched.
  - It produces the collective/power "bucket" over V = 0…20 m/s for model comparison.
- **Linearization** reuses [linearize.gd](../../app/physics/linearize.gd), with a rotorcraft mode classifier:
  - heave subsidence
  - yaw
  - coupled rotor–fuselage roll and pitch
  - the low-frequency hover cubic

### 4.12 Cost budget

| Item | Budget (H15 host, median) |
| --- | --- |
| Rotorcraft loads, 4 evaluations per tick | ≤ 150 µs |
| Whole tick, hover on the pad with contacts | ≤ 400 µs |
| Whole tick, any regime | ≤ 500 µs (Gate P rule) |

- Main rotor, tail rotor, fuselage and empennage are closed-form: an estimated 150–300 scalar operations per evaluation.
- The kernel is benchmarked **before** integration (HELI-09).
- The playable research route is an explicit experimental slice; it does not meet the proposed cost gate. [Prepared-context profiling](../research/helicopter/HELI-09/README.md) preserves equations while reducing repeated validation. Hardware acceptance remains open.
- The rotor ring check runs once per tick, not per stage.
- Scalarize from the start, following H3/H12: no per-call arrays and trigonometry through `math3d` (H6 guard).

### 4.13 Non-goals

Out of scope for this plan:

- per-blade azimuth marching
- lead-lag and ground resonance
- flexible blades
- multi-blade scale heads (later variant)
- coaxial, tandem and multirotor vehicles
- CFD or vortex-particle wash
- brownout dust physics
- water landing
- fuel burn and changing mass
- structural or flyable damage
- autopilot and auto-hover

A real flybarless self-level or rescue mode is **not** an autopilot. It is in scope only when the modelled hardware has it (D7).

## 5. Data contract

**Implemented:** `openrc-aircraft v2`, `vehicle: "rotorcraft"`, with the dedicated closed [rotorcraft schema](../../app/data/schema/openrc-rotorcraft-v2.schema.json) and reader. The earlier sibling-v1 proposal is superseded by the [current contract boundary](../../AIRCRAFT_CONTRACT.md#experimental-rotorcraft-boundary). Do not route it through the conventional-airplane loader.

Every physical quantity retains `{value, unit, kind, source}` and strict unit/domain/unknown-key checks. The current X-Cell reader admits one explicit capability set and aggregate source mass/inertia. Complete component inventory, installed servo topology, identified electric powertrain and new hardware capabilities require explicit schema/reader extensions before use. Preserve existing airplane and X-Cell behavior when adding those branches.

The following is a future module sketch, not the current JSON schema; its richer inventory, governor, freewheel and actuator blocks need their own consumers and tests:

    vehicle: "rotorcraft"
    capabilities: { controls: "ccpm120_flybar_lumped", gear: "skids", propulsion_layout: "single_main_tail_rotor",
                    energy: "prescribed_fuel", damage: "terminal_hull_rotor_disc", electronics: "tail_heading_hold" }
    main_rotor:   { radius, chord, blades, lift_slope, profile_drag{cd0,d1,d2}, ct_max, twist, flap_inertia,
                    hub_stiffness, hinge_offset, lock_flybar?, cyclic_gain{lat,lon}, flapback_scaling, hub_position,
                    rotation_sense, inflow{kappa, eta_w, vrs_factor}, ground_effect{law:"hayden"} }
    tail_rotor:   { radius, chord, blades, lift_slope, ct_max, gear_ratio, hub_position, fin_blockage, wake_geometry }
    drive:        { rotor_inertia, engine_gear_ratio, efficiency, loss_torque, freewheel: true }
    engine:       { kind: "power_source", max_power, ... }   governor: { kp, ki, setpoints_by_mode, soft_start }
    controls:     { swash{type:"ccpm120", servo_full_throw_time, lag, limits{collective, cyclic, tail}},
                    curves{normal, idle_up, hold}{pitch[5], throttle[5]}, gyro{kp, ki, precomp} }
    airframe:     { drag_areas[x,y,z], fin{area, lift_slope, position}, stabilizer{area, lift_slope, position} }
    skids, crash_hull, inventory, balance, start{pad, hover}

- The generator is `research/helicopter/xcell/derive.py`. It emits the JSON from a source table that cites Gavrilets Table 1 row by row, and has a `--check` mode, as the P-51 and Extra generators do.
- The JSON is never hand-edited.

## 6. Session integration

**Implemented route:** a separate `HelicopterFlightSession` uses the existing `Simulation` owner and a joint body derivative plus six continuous derivatives. `AppRoot` selects it for the explicit rotorcraft catalog ID. Native checkpoints bind exact preset bytes, weather, controls and state; `RotorcraftRecorder` declares its own 32-column diagnostic CSV. The airplane session and airplane trace layout retain their own contracts. The earlier proposed shared-session seam and trace columns below describe future consolidation, not the current interface.

- **One seam in `FlightSession`.** When `model.vehicle == "rotorcraft"`, `_configure_continuous_callbacks` selects `_rotorcraft_evaluate`. That callback returns the joint `{loads, derivative, rotor_momentum}` from `physics/rotorcraft/loads.gd` plus `Ground.evaluate`.
  - Every airplane path stays as it is.
- **Proof of non-interference** at every integration step:
  - all existing goldens, `check_trimmed_flight` traces and 30/60/144 fps determinism checks are byte-identical
  - `test.sh` is green
- **New state classes:**
  - a checkpoint format bump with a rotorcraft law string
  - restore whitelist entries
  - a trace column group `HELI_COLUMNS`: `rotor_rpm, collective_deg, cyc_lat_deg, cyc_lon_deg, tail_pitch_deg, a1, b1, lambda0, thrust_n, q_main_nm, gov_out, flight_mode, z_over_r, vz_over_vh`
  - a new `metadata_schema` version and an `input_semantics` field (`airplane_aetr` or `heli_aetc`)
  - `replay_policy` classes for every new aux entry
- **Helicopter goldens:** `hover_hold`, `collective_step`, `lat_cyclic_doublet`, `pedal_step`, `autorotation_entry`.
  - They are recorded only after the model-to-paper comparison passes.
  - They are re-recorded only for an explained physics change.

## 7. Input and controls

- **Four sticks, same width (D6).** The heli maps `[roll, pitch, yaw, throttle]` to `[lateral cyclic, longitudinal cyclic, tail, collective stick]`. The throttle is derived from the throttle curve and governor.
- **Flight-mode switches** are discrete `modes` entries:
  - keyboard keys (proposed: `1` normal, `2` idle-up, `H` hold toggle; key clash check with HUD `H`, so the final choice is in HELI-14)
  - gamepad buttons
  - radio switch channels, through a new optional switch-mapping step in calibration (RcInput reads no switches today)
- **Arming policy for a heli:** hold engaged **or** collective stick low at connect, with throttle hold forcing Q_e = 0. Failsafe engages hold.
- **Shaping.** Rates and expo apply to cyclic and tail as today (D6e). The collective is shaped only by its pitch curve.
- **Keyboard flying.** A keyboard cannot fly a helicopter realistically. The plan does not fake it.
  - It offers the electronics modes the modelled hardware actually has.
  - An optional, clearly labelled "trainer electronics" self-level mode is available if the owner accepts it (D7).
  - The recommended devices are gamepad and radio.

## 8. Presentation, VFX and audio

### 8.1 Visual model

- **Source (D9), selected by the owner.** The installed visual comes from [`HX-700_Helicoptero_RC.blend`](../../Helicopter%203d%20acrobatic/HX-700_Helicoptero_RC.blend) and its embedded `generar_hx700.py`/`LEEME`. The adjacent supplied PDF is an IlGoblin Piuma Competizione SG779 assembly manual used as a class-700 dimension/spec reference. The [HELI-25 audit](../research/helicopter/HELI-25/README.md) owns that source's hashes, measurements and export bindings. The articulated replacement delivered on 2026-10-14 is reviewed in [HELI-25b](../research/helicopter/HELI-25b/README.md); §8.1.1 owns its integration. Reuse the supplied models and preserve their source files.
- **Identity and scale.** HX-700 is a procedural flybarless 700-class visual design; the identified flight reference is the instrumented flybar X-Cell .60 SE. These are different configurations. Preserve the authored HX-700 scale and identity. A research preview may show the supplied model, but attaching X-Cell flight behavior requires an explicit research-surrogate label and measured alignment; a qualified HX-700 needs its own physical inventory and electronics. Do not derive inertia, CG, aerodynamic coefficients or gearing from appearance or render drivers.
- **Coordinates and regeneration.** Source metres use +X nose, +Y left and +Z up. Its structural adapter is `[-x,-y,z]`; body FRD is `[x,-y,-z]` after subtracting an established CG. Both are proper rotations. Preserve the source file, root and authored pivots; export through the source pipeline with an aircraft-only selection. Native Godot binding, package provenance, draw/triangle budgets and source/export freshness must pass before runtime integration.
- **Node contract** (registered with the model owners):
  - The root stays `airplane`, so existing consumers keep working.
  - `propeller` maps to the **main-rotor mast mount**, with local +Z on the shaft.
  - New keys: `tail_rotor`, `skid_left`, `skid_right`, plus capability-dependent `swashplate`, `flybar` and servo-arm `*_hinge` nodes. The HX-700 has no flybar; do not add one to make its hierarchy resemble the X-Cell.
  - The installed adapter binds `Pivote_Rotor_Principal` and `Pivote_Rotor_Cola`. The earlier source's `velocidad_rotor`/4.6× scripted drivers are presentation animation; simulator telemetry owns runtime animation. The new source provides swash/servo links, but their runtime export and blade-pitch bindings still require the work in §8.1.1.
- **Spin.** `main.gd` spins the tail rotor at n_tr·Ω through a new, read-only rotor telemetry accessor, not `aux[0]` guesses.
- **Swashplate and blade pitch** are animated from servo state, following the rule that one servo state drives physics and visuals.

### 8.1.1 Articulated HX-700 delivery integration

**2026-10-14:** the owner supplied `NEW HELI/HX-700_Helicoptero_RC_1.blend`. [HELI-25b](../research/helicopter/HELI-25b/README.md) owns its immutable source identity, 26 pose probes, static-export limitations and inspection images. This section owns the remaining implementation plan. The existing flyable trainer stays available throughout.

**Contract first.** Add a versioned rotorcraft construction profile/sidecar through the AS model-binding pipeline, with a strict reader before installing the new asset. Keep existing conventional manifest readers valid. Proposed binding roles are main/tail shaft, fixed/rotating swash, four actuator outputs, each blade's feather frame, tail slider/yoke/bellcrank, and nine linkage endpoint pairs. Each binding needs a stable semantic ID, source-node reference, parent, local rest transform, axis/pivot frame, sign, SI limits and source hash. Physical component/actuator IDs and replaceable Blender names are different identities. Record attachment coordinates in their actual local rest frames; do not reinterpret construction-world JSON points as already-local pivots.

The new source declares no `openrc_section` properties. Extend the rotorcraft section vocabulary/collector with CR before tagging rotor/head/boom/skid/canopy/battery groups; do not borrow incompatible wing/propeller categories or enable damage merely by separating meshes. The current Timber handoff is useful for export discipline, not a helicopter topology specification.

| Order / owning steps | Deliverable | Acceptance before advancing |
| --- | --- | --- |
| 1 · HELI-25b | Source/rig review | Delivered: pinned source, inventory, poses and a disposable static export. No runtime asset replaced. |
| 2 · HELI-25c, AS-09/10/13 | Neutral game export and generated binding profile | Detach demonstration actions; preserve evaluated neutral pose. Export required anchors or encode their local frames. No cameras, force arrows or mixer/telemetry controllers in the flight asset. Verify every required binding, rest matrix, axis, handedness and all material/image dependencies in native Godot and a fresh packaged export. Missing/duplicate bindings block activation. |
| 3 · HELI-13a/15a, D6-SAV-02/03/07 | Pure four-actuator and deterministic linkage kernels | Distinguish pilot demand, controller target, travel/rate-limited target and achieved angle. Three swash actuators plus tail feed a float64 forward-kinematic model. Prove rate/first-order response with refinement and analytic step/ramp checks before live coupling. Do not execute Blender drivers as flight physics. |
| 4 · HELI-17a | Coupled state, interpolation, checkpoint and trace update | Version the four achieved actuator states and fixed-step shaft phase coherently; only now feed achieved collective/cyclic/tail output into aero and visuals. Settle achieved actuator state in hover trim. Reset, pause, mode changes, radio loss, recording and atomic restore cover the whole layout. Keep historical readers explicit. Repeated variable-RPM flights at 30/60/144 fps reproduce servo/blade pose as well as body state. |
| 5 · HELI-26a | Mechanical display and rotor blur | Fixed mast/gearbox remain fixed; rotating inner swash follows the shaft while outer swash does not spin. Feather blades once, avoiding grip/blade double rotation. Tail slider does not spin; yoke spins/slides. Flap/disc orientation is separate from feather pitch. Extend cached blur for articulated frames or use a declared phase-averaged disc; measure profiles offline for this exact source. |
| 6 · HELI-23/25c/26a | Game detail tiers and performance | Preserve the detailed master. Group static parts only across compatible material/motion/section boundaries; keep all joints. Reduce hidden bolts, bearing internals and gear teeth for flight view, retaining detail in inspection view. Record triangles, surfaces, draw calls, GPU/CPU and joint-update cost; defer off-screen visual updates only. Never lower physics sampling with camera distance. The H15-host Gate P performance target remains open. |
| 7 · HELI-36a, EL owners | Separate electric HX-700 configuration | Author component masses/CG/inertia, rotor/blade data, motor/ESC/pack/BEC, gearing/losses and controller evidence. Add electric drive/freewheel only through validated laws and consistent signed momentum. Software-qualified estimated configuration may fly as experimental; physical/pilot qualification remains explicit. Never retune X-Cell silently. |

**Servo and linkage rules.** Reuse the shared actuator/catalog work; a 40 mm servo body does not identify a Savox/Futaba model. Record BEC rail voltage and loaded rate/torque evidence: 12S motor voltage is not servo supply voltage. Convert manufacturer seconds/60° to the declared installation travel; keep subtrim, direction, endpoints and geometry in the installation. Do not add catalog servo mass on top of an aggregate body that already includes servos. Model deadband/backlash or voltage/load effects only with an authored law and separate evidence.

Use nominal inverse kinematics to obtain actuator targets, then achieved actuator positions and actual link lengths for forward kinematics. Check each loop's reachability and residual, servo stops, assembly branch and continuity through full travel. Reject out-of-range authoring, including the +100 mm cyclic-rod negative control against its ±3 mm source limit, independently of Blender's alert/lock flags. Never turn an invalid `acos` into a plausible pose by clamping without reporting it. Do not use Stretch To as a physical rod law. Fit a bounded analytic/harmonic mapping, or qualify a bounded solver, before putting nonlinear mechanics inside every RK stage; fixed arbitrary pass counts are not a convergence guarantee. Blender pose samples are cross-tool oracle data, supplemented by independent lengths, transformations and residual checks. Use the standalone servo kernel as a reference; do not call its full-tick state updater four times inside RK stages. The selected continuous or sampled actuator law needs explicit state/held-target semantics.

**Phase and aero rules.** Resolve the source's 53.13° swash phase against the flight model's cyclic/dynamic convention using signed blade-angle samples over a revolution; do not add another generic 90° precession. Separate mechanical feather pitch, `a1/b1` disc flap and coning. The existing mean-rotor law has no coning/elastic-blade state, so omit or clearly qualify such visual approximation. If achieved geometric blade pitch feeds the mean aero law, derive its collective and first harmonics without aliasing a 2100 rpm rotor through a 240 Hz instantaneous blade sample. A per-blade unsteady aero model requires its own timestep/cost qualification.

Integrate phase from accepted shaft-speed history at fixed ticks/stages, not render `dt` or final RPM multiplied by elapsed time; interpolate the unwrapped phase correctly. Geared tail phase and offsets must match the selected drive. Motor-side slip/coast phase requires a separate qualified engine/motor/freewheel model; the Blender demonstration is not proof of that dynamics.

**Two configuration tracks.** First qualify the new model in an isolated mechanical preview. Any intermediate use on X-Cell remains explicitly a research surrogate and must resolve radius/pivot/contact alignment without scaling the whole articulated mechanism. Its 4.66 tail ratio cannot simultaneously depict the source's 4.923077 tooth-exact transmission; keep incompatible transmission demonstrations disabled or explicitly illustrative. The preferred faithful endpoint is the separate electric HX-700 profile (5.2 kg / 2100 rpm are currently source declarations, not measurements). Source aerodynamic/governor telemetry never overrides flight state or coefficients.

**Required fixtures:** neutral; collective ±; cyclic ± and combined ring limits over 0/90/180/270° and a dense phase sweep; positive/negative tail; travel/rate saturation; per-servo subtrim; rod and head tracking offsets; invalid/unreachable loops; fixed mast/gearbox; independent instances; pause/reset/replay; physical-radio disconnect/mode transitions; variable-RPM capture and 30/60/144 fps pose identity; low/high-RPM blur; source/package dependency failures. Physics-changing actuator integration gets new explained rotorcraft evidence while preserving legacy-plane goldens. No blanket all-axis 0.001° claim: the source has measurable phase-dependent mean-pitch coupling.

### 8.2 Rotor disc that never strobes

Facts that drive the design:

| Fact | Consequence |
| --- | --- |
| At 1595 rpm the rotor turns 159.5° per 60 fps frame | A phase-true two-blade mesh appears to turn slowly **backward** |
| At 1800 rpm it turns 180° per frame | It appears **frozen** |
| Time-averaged blade coverage is N·c/(2πr): ≈ 2.7 % at 0.7 m, ≈ 13 % near the root | A real disc at speed is nearly transparent |

- **Geometry.** A shallow cone in the TPP frame, driven every frame by rotor telemetry: coning, a1/b1 tilt and rotation sense. Each frame:
  1. compute the angular sweep Δθ = Ω·Δt_frame
  2. evaluate an **analytic angular box filter** in the fragment shader: each blade's occupancy of the polar angle φ over the exposure window
  3. converge to the coverage profile c(r)·N/(2πr) when Δθ ≥ 2π/N
- **Materials.** Tip and root colour bands come from the blade materials, measured as in VQ-05's polar rasterization.
- **Cross-fade** between the solid blade mesh and the disc is driven by **Δθ per frame**, not by blade-passing frequency alone. The VQ-05 12/48 Hz thresholds are re-derived and the choice recorded.
  - Full blades below ≈ 20° per frame; full disc above ≈ 90° per frame. These are estimates to tune against captures.
- **Compatibility rules** (VQ-05 probe facts):
  - alpha-blended material copies; never `GeometryInstance3D.transparency`
  - `cull_disabled`, `depth_draw_never`, shadows off on the disc
  - `sorting_offset` against wash particles
  - alpha raised toward edge-on views (X-Plane practice)
- **Tail rotor** at ≈ 7,400 rpm is always a disc.
- **Rotor shadow.**
  - The sun shadow of the disc is coverage-weighted and faint.
  - The pilot-aid "vertical" projected shadow includes the disc outline, because hover height is judged by shadow.
  - The projected-shadow skip rule for `propeller` must not hide the fuselage.
- **Proof:**
  - a pure-function test showing the coverage integral is independent of frame phase at 30, 60 and 144 fps
  - an rpm sweep capture at 0, 300, 600, 900, 1200 and 1595 rpm from front, side, top and edge-on
  - a frame-sequence capture showing no apparent rotation at 1595 and 1800 rpm

### 8.3 Rotor-wash field, grass and water

`render/rotor/wash_field.gd` is pure and headless-testable. Its inputs, read from simulation telemetry and converted at the render boundary, are:

- thrust T
- v_h = √(|T|/2ρA)
- hub position and TPP normal
- height above terrain z
- surface kind under the hub

From those it publishes global shader uniforms (`rotor_wash_center`, `rotor_wash_params`):

- **Wall jet.** Stagnation under the hub at r/D ≈ 0.2–0.3, peak U_pk ≈ 1.8·v_h·f(z/D) at r ≈ 1.75R, decay ≈ (r/r_pk)^−1.1 [U] to ≈ 3D. The footprint is displaced by the wake skew in forward flight.
- **Zero thrust gives zero wash.** Flat pitch on the ground does not blow the grass. This is the DCS/MSFS lesson.

The uniforms must be declared in `project.godot` (Compatibility requires it before shader compilation). That is a shared file, coordinated with the landscape/visual owners.

Consumers:

| Consumer | Behaviour | Owner coordination |
| --- | --- | --- |
| Near grass (`near_grass.gdshader`, 30 m around the pilot, rough only) | Vertex bend ∝ dynamic pressure q(r) = ½ρU², radial; flutter frequency rising with U; per-revolution gust at the blade-passing frequency folded below Nyquist | Landscape/visual |
| Mown / runway turf (`ground.gdshader`) | Near grass is not planted on runway or mown. A pad there shows a moving sheen and ripple ring in the turf shader. | Landscape/visual |
| Water (none exists in the field today) | Ripple ring where u* > 0.02 m/s; spray only for z/D < 0.5. Deferred until a water surface exists. | — |
| Windsock / flags (`motion.gdshader`) | Respond if inside the field | Scenery |

**Pad placement decides the look (D10).** On the default field the honest effects are grass ripple and clippings. Dust needs a dirt or sand surface that does not exist yet: do not invent dust on grass.

### 8.4 Particles

This is the first flight-time `GPUParticles3D` in the app.

- **Dependency:** the smoke track's SM-00 Compatibility probe (or a joint HELI/SM probe) must confirm, on the pinned engine:
  - emission, heightfield collision and seed behaviour
  - cost on llvmpipe and on the owner's Windows host
- Known Compatibility limits: no trails, no sub-emitters, no `emit_particle()`, no SDF collision, and CPU depth sorting from a buffer two frames old.

| Emitter | Driven by | Look | Budget (estimate, to measure) |
| --- | --- | --- | --- |
| Grass clippings / leaf bits | U_pk > threshold, z/D < 1.5, surface rough or mown | Ring sheet from r ≈ 1.2–2R; short arcs with gravity and damping; heightfield collider following the aircraft (≈ 8 m) | ≤ 150 |
| Light dust (dirt or gravel surfaces only) | u* > u*t (≈ 0.2–0.3 m/s), surface table | Ring sheet + roll-up at r ≈ 2–3R; flipbook billboards; `distance_fade` | ≤ 600 |
| Nitro exhaust | Throttle and load; needs the SM-01 anchor | Blue-grey puffs, 50–150 particles, 0.5–0.8 s life | ≤ 150 |
| Blade-strike debris | Crash director | Tangential at Ω×r | Crash budget |

- **Level of detail by camera distance:**
  - < 30 m: full
  - 30–80 m: half counts, larger sprites, no leaves
  - > 80 m: grass bend and one ground-ring decal only
- `amount_ratio` scales emission for look, not cost. Real savings come from switching emitters off by tier.
- Prewarm emitters at flight start to avoid the first-use shader-compile hitch.
- **Determinism:**
  - `use_fixed_seed`
  - `fixed_fps = 60`, `interpolate = false`
  - an explicit `preprocess`
  - captures through the existing route, accounting for the smoke finding that `--capture` loses particle history (prewarm, or step the renderer)
- **Budget for all rotorcraft VFX** (disc + wash uniforms + particles):
  - ≤ 1.5 ms p95 added frame time at 720p on the owner's host
  - ≤ 2,000 live particles
  - ≤ 6 emitters
  - ≤ +12 draw calls
  - The VM proves pixels and repeatability, not performance.

### 8.5 Camera and HUD

- **Camera.**
  - Hover happens 5–20 m from the pilot.
  - Auto-zoom uses the rotor diameter as the span. A "pad" pilot preset keeps the aircraft at a readable size.
  - The vertical shadow aid is the default for the heli.
  - The Home preview shows the aircraft on the pad with blades still, not banked in the air.
- **HUD** (flight-overlays track):
  - O1/O5 fields: head speed, collective °, governor output, flight mode, electronics mode.
  - O3 warnings:
    - LOW HEAD SPEED and OVERSPEED (bands from data)
    - VRS: Vz/v_h inside Johnson's region with low Vx/v_h
    - TAIL LIMIT: tail thrust at its cap for more than 0.3 s
    - HOLD
  - Thresholds are display aids awaiting pilot review, as in the existing overlays.

### 8.6 Audio

Coordinated with the audio track. `MAX_VOICES` and the index constants change.

| Layer | Source frequency (X-Cell, derived) | Modulation |
| --- | --- | --- |
| Main rotor | Blade-passing 53.2 Hz + harmonics | Load (C_T/σ), observer azimuth "wop" per blade, tip Mach |
| Blade slap (BVI) | Impulsive at blade-passing frequency | Vz/v_h and inflow near the BVI/VRS region; flares and descending turns |
| Tail rotor | 247.7 Hz | Tail thrust magnitude |
| Nitro engine | ≈ 239 Hz firing at 14,350 rpm | Throttle, governor, load; bog on punches |
| Drive / wind-down | Gear whine; coast-down after hold | Ω |

- Existing manual Doppler and canopy screening are reused.
- Assets come from the existing seeded generator (`tools/audio/generate.py`) or rpm-pitched loops.
- A GDScript `AudioStreamGenerator` runs at ≤ 22,050 Hz, if used at all.

### 8.7 Crash

Coordinated with the crash track and its CR-01d semantic hull labels.

- **Hull labels:** `main_rotor`, `tail_rotor`, `tail_boom`, `skid`.
- **Causes:** main-rotor strike, tail-rotor strike, dynamic rollover, VRS descent, tail blowout, low head speed.
- **Wreck groups:** blades, boom, skids. Blade debris inherits Ω×r.
- **Component estimate:** must not use the wing span for a helicopter.

## 9. Steps

Each step is one small working change with its proof. A step that touches a coordinated file states the owner's acceptance.

### Phase 0: decision and reference

| ID | Work | Proof / status |
| --- | --- | --- |
| HELI-00 | Scope extension, registry and ROADMAP pointer | Done, owner authorization 2026-10-13 and DECISIONS row. Reference direction D2–D6 selected for kernel work; D7/D9/D10 and aircraft-specific hardware choices remain open. |
| HELI-01 | Research record: sources, parameters, derived values, seam map | [HELI-01](../research/helicopter/HELI-01/README.md) / done |
| HELI-02 | Read the remaining primary sources in full: Gavrilets thesis (tail gyro, servo, governor details), Mettler 2004 identified table, Johnson Table 4 and the cubic segments, Padfield inflow and cyclic C_T terms, the X-Cell manual (pitch curves, travel) | Partial: Gavrilets main-rotor §§4.1.1–3/Eqs. 1–27 checked against rendered pages, resolving no twist, hard clamp, drag law and rate/sign terms ([HELI-05](../research/helicopter/HELI-05/README.md)); Johnson/Hayden checked in HELI-04. Remaining thesis/manual/control/drive details and [U] items stay open. |
| HELI-03 | **Offline reference model** `research/helicopter/reference/` (Python, stdlib + pinned NumPy): §4 equations, hover/forward trim, linearization, scripted time responses | Reproduces the paper's hover operating point and published figures (digitized, with provenance); emits oracle CSVs for GDScript known-answer tests |
| HELI-03a | Independent stdlib steady mean-inflow reference and generated known-answer JSON | Implemented with tests and `make_oracle.py --check`; [HELI-04 evidence](../research/helicopter/HELI-04/README.md). Full HELI-03 trim/response model remains open. |

### Phase 1: pure physics kernels (no session changes)

| ID | Work | Proof / status |
| --- | --- | --- |
| HELI-04 | `rotorcraft/inflow.gd`: momentum branches, Johnson VRS law, windmill brake, Hayden ground effect, λ0 derivative | Standalone implementation verified against HELI-03a, Table 4, momentum residuals, axial continuity, ground-effect cross-check and signed symmetry. [Evidence](../research/helicopter/HELI-04/README.md). **Integration gate open:** C/M crossflow jumps, dynamic-flow refinement and full-evaluation cost. |
| HELI-04-R1 | `rotorcraft/dynamic_inflow.gd`: dimensional vi derivative, residual decay and stage effective flow; known-event RK4 qualification | Python dense/convolution reference, native tests and explicit raw-240 failure; bounded local known-event procedure passes 1e-3 m/s. [Evidence](../research/helicopter/HELI-04-R1/README.md). Automatic session detector and physical transient validation open. |
| HELI-05 | `rotorcraft/main_rotor.gd`: untwisted two-blade C_T hard clamp, first-order flap rates, exact-normal force, hub spring/arm and constant-C_D0 torque | Standalone kernel implemented; source/math anchors, separate bare/flybar lags, p/q units, signed loads and independent oracle. [Evidence](../research/helicopter/HELI-05/README.md). Full-flight qualification and aircraft authoring open. |
| HELI-05a | `rotorcraft/main_rotor_stage.gd`: joint main-rotor loads and [a1,b1,vi] derivatives | Fixed-body, fixed-speed stand settles to an independent hover quadratic and cyclic targets under RK4. [Evidence](../research/helicopter/HELI-05/README.md#joint-main-rotor-stage). Not complete trim, tail/airframe/drive or a flight session. |
| HELI-06 | Tail and airframe component suite: source-linearized tail, wake ramp, blocked thrust cap and passive fuselage/fin/stabilizer extension | Standalone kernels and a prescribed-speed aerodynamic stand delivered under HELI-06a–c; full physical/transient/component qualification remains open. No fixed-pass tail iteration. |
| HELI-06a | `rotorcraft/tail_rotor.gd`: bounded coefficient-trim solve, actual-pitch/normal-flow thrust, cap/blockage, Eq. 50 inflow and profile/induced torque | Standalone source/math anchors and independent oracle; [HELI-06 evidence](../research/helicopter/HELI-06/README.md). No tail-controller, drive, sideways-VRS or flight qualification. |
| HELI-06b | `rotorcraft/airframe.gd`: passive local-flow fuselage/fin/stabilizer loads, full CP rates/moments, force caps and work diagnostics | [Source conflicts, independent reference and passivity evidence](../research/helicopter/HELI-06b/README.md). Wake velocities explicit; no hidden aircraft data or wake closure. |
| HELI-06c | `rotorcraft/aerodynamic_stage.gd`: same-stage main/tail/airframe evaluation and explicit source-style shaft wake approximation | [Fixed-body stand](../research/helicopter/HELI-06b/README.md#joint-aerodynamic-stage). Not body flight, drivetrain, complete trim or session integration. |
| HELI-07 | Torque/power-capped one-speed drive and proportional governor | Kernel verified on Windows/Linux; actual-preset hover has finite torque/power reserve. [Evidence](../research/helicopter/HELI-07/README.md). Engine inertia is excluded because its signed axis is unknown; separate engine/freewheel and startup calibration remain open. |
| HELI-08 | Geared gyroscopic coupling (b-vector form) isolated from the airplane path | Simultaneous shaft/body response, angular-energy/momentum and signed-axis/gearing checks implemented; [evidence](../research/helicopter/HELI-08/README.md). No duplicate aerodynamic/drive reaction. |
| HELI-09 | Per-call aerodynamic/full-flight and whole-tick cost | Prepared-context redesign verified without changing equations; [development diagnostic](../research/helicopter/HELI-09/README.md). The ≤37 µs/full evaluation and H15 whole-tick targets are unmet/open; the experimental flight does not claim performance acceptance. |
| HELI-09a | Isolated equilibrium-inflow cost diagnostic `research/helicopter/bench_inflow.gd` | Measured on the Windows Ryzen 5900X host; [HELI-04 evidence](../research/helicopter/HELI-04/README.md). This does not close HELI-09 or the whole-tick budget. |
| HELI-09b | Isolated joint main-disc/wake stage cost `research/helicopter/bench_main_stage.gd` | [HELI-05 measurements](../research/helicopter/HELI-05/README.md#heli-09b-isolated-stage-cost): compact payload verified, VRS cost still leaves insufficient full-load margin. Complete profiling/redesign before session integration; HELI-09 open. |
| HELI-09c | Isolated source-linearized tail cost `research/helicopter/bench_tail_rotor.gd` | [HELI-06 measurements](../research/helicopter/HELI-06/README.md#heli-09c-isolated-tail-cost): ~21–24 µs median batch means on the development host; no complete-load or H15 acceptance. |
| HELI-09d | Joint aerodynamic stage cost `research/helicopter/bench_aerodynamic_stage.gd` | [HELI-06b measurements](../research/helicopter/HELI-06b/README.md#heli-09d-joint-stage-cost): ~103–125 µs median batch means before drive/body/control, exceeding the proposal. Profile/redesign before flight integration; HELI-09 open. |

### Phase 2: data

| ID | Work | Proof / status |
| --- | --- | --- |
| HELI-10 | Dedicated strict rotorcraft reader/schema using `openrc-aircraft v2` quantity conventions | Implemented: rejects unknown fields, missing evidence, dimensions, invalid modules, signed-axis/gearing mismatch and contact stiffness. Aggregate source inertia is explicit; full component inventory remains open. |
| HELI-11 | X-Cell source/estimate table and generator `research/helicopter/xcell/derive.py --check` → `app/data/aircraft/xcell_60_research.json` | Implemented with four independent authoring checks and freshness in `test.sh`; every quantity carries its evidence kind. |
| HELI-12 | Contract text: rotorcraft section in AIRCRAFT_CONTRACT (with the AS owner) | Reviewed diff |

### Phase 3: controls and electronics

| ID | Work | Proof / status |
| --- | --- | --- |
| HELI-13 | `rotorcraft/swash.gd`: curves per flight mode, 120° CCPM mixer, per-servo rate and lag, linkage ratios, limits | Pure kernel done: 46 checks for curves, mixer inverse, per-servo saturation/rate/lag and linkage. [Evidence](../research/helicopter/HELI-13/README.md). No aircraft curves, azimuth phasing or session control integration qualified yet. |
| HELI-14 | Four sticks, keyboard modes, calibrated radio/gamepad and explicit resume | Integrated: gamepad hover baseline, physical-radio low-stick arming, disconnect pause, calibration/reset and vehicle-specific controls/help. Optional radio mode switches and a physical hold/failsafe model remain open. |
| HELI-15 | Continuous tail heading/rate PI and trainer feedback through real tail/cyclic controls | Kernel and actual-preset hover/pilot responses verified. Gains are estimates; physical controller calibration and servo lag integration remain open. |

### Phase 4: session integration

| ID | Work | Proof / status |
| --- | --- | --- |
| HELI-16 | Joint flight callback in a dedicated rotorcraft session, common Simulation and Home/direct route | Implemented; [software checks and regression evidence](../research/helicopter/HELI-16/README.md). |
| HELI-17 | Six extra continuous states, reset, native checkpoint, separate rotorcraft recorder and metadata | Implemented with byte-identical replay and rejected checkpoint/CSV negative cases; cadence evidence in HELI-16. |
| HELI-18 | Full coupled, ground-stationary hover trim including candidate-specific ground effect | Implemented and checked with the actual preset and steady wind. Forward trim, bucket curve and source-response comparison remain open. |
| HELI-19 | Four float64 spring/damper skid points and regularized Coulomb friction | Flat-field pilot-compensated landing verified. Slope, static-anchor and dynamic-rollover qualification remain open. |
| HELI-20 | Pad start, spool-up lifecycle, idle-up and hold transitions | Spool-up trace; lift-off in ground effect; hold → coast-down |
| HELI-21 | Analytic full-disc main/tail ground clearance and terminal causes | Tilted-ground strike and restart verified. This is an instantaneous ground envelope; swept scenery/tree collision remains open. |
| HELI-22 | Linearization and rotorcraft mode classifier | Eigenvalues vs HELI-03 within 1e-6 relative |
| HELI-23 | Integrated cost (Gate P rule) and long-run stability (10 min of hover, autorotation, pirouettes) | p50/p95 per regime; no nonfinite state; no sticky fault |

### Phase 5: presentation

Steps HELI-25…27 can start in parallel with Phase 1 because their file boundaries are disjoint.

| ID | Work | Proof / status |
| --- | --- | --- |
| HELI-24 | Model-to-paper comparison: digitized Gavrilets heave, axial roll and pitch-pulse responses (held-out), and the governor step (calibration) | Report in `docs/research/helicopter/HELI-24/`; tolerances §10 |
| HELI-25 | Supplied Blender visual, reproducible static GLB/profile pipeline, adapter and playable catalog entry | Implemented; [HELI-25 provenance and verification](../research/helicopter/HELI-25/README.md). Source identity, physical calibration and distribution provenance remain separate gates. |
| HELI-25a | Audit and reuse the supplied HX-700 `.blend`, embedded generator and adjacent reference PDF | [Source audit, runtime bindings and captures](../research/helicopter/HELI-25/README.md) delivered with a playable catalog entry. Source-only regeneration reproduces GLB/profile hashes and leaves the `.blend` unchanged. Physical identity, articulation, distribution provenance and presentation budgets remain open. |
| HELI-25b | Review the delivered articulated HX-700 revision | [Source, 26 pose probes and static-export inspection](../research/helicopter/HELI-25b/README.md) complete; integration order in §8.1.1. |
| HELI-25c | Game export, semantic rig bindings and source/package admission | Planned; all required anchors, rest transforms and resource proofs pass before selecting the new visual. |
| HELI-26 | Rotor disc: analytic coverage shader, cone with coning/TPP, cross-fade by Δθ per frame, tail disc, rotor shadow | Phase-independence test; rpm and view sweep captures; frame-sequence aliasing capture |
| HELI-27 | Rotor-wash field (pure) and global uniforms; near-grass and turf response | Headless known answers (peak 1.75R; zero thrust → zero wash); captures at z/D = 0.3, 1, 2; cost |
| HELI-28 | Particles: Compatibility probe (with SM-00), clippings and dust emitters, level-of-detail tiers, determinism settings | Probe report; captures; VFX p95 on the owner's host |
| HELI-29 | Audio layers | Spectrum checks of blade-passing frequencies; listening review by the owner |
| HELI-30 | HUD fields and warnings; camera pad preset; Home pad preview; es strings | Overlay fixtures per warning; 720p captures en/es |
| HELI-31 | **Catalog EXPERIMENTAL**: Fly enabled with the "experimental" warning | Every route trims and flies; export smoke loads the heli |
| HELI-32 | Nitro exhaust (after SM-01 anchor) | Capture; cost |
| HELI-33 | Crash semantics (with CR-01d) | Fixtures per cause; wreck groups |

### Phase 6: acceptance and growth

| ID | Work | Proof / status |
| --- | --- | --- |
| HELI-34 | Owner flight session (Gate HELI-P, §10) | Ratings and traces in `docs/research/helicopter/HELI-34/` |
| HELI-35 | Physical data, if the owner or a contributor has a helicopter: hover power and rpm (ESC or engine telemetry), autorotation descent rate (baro/GPS), weight/CG/swing inertia via the VAL-5/6 reducers | Measurements with uncertainty; held-out comparison |
| HELI-36 | Second aircraft: independently authored flybarless electric 700 class; later richer inflow/blade aero behind capabilities | HX-700 is the current candidate under HELI-36a. 360CFX/R-50 sources inform architecture, not transferred calibration. |
| HELI-36a | Electric HX-700 configuration matching the new visual | Planned under §8.1.1; component inventory, electric drive, BEC/servo evidence, FBL identification and qualification stay separate from X-Cell. |

**Parallel lanes** (one agent per lane, each with disjoint files):

| Lane | Steps | Files |
| --- | --- | --- |
| A | HELI-03 | `research/helicopter/` |
| B | HELI-04…09 | `app/physics/rotorcraft/` |
| C | HELI-25 | `assets/aircraft/<heli>/`, `app/aircraft/<heli>_*` |
| D | HELI-26/27 | `app/render/rotor/` |

Integration steps (HELI-16/17) are serialized with the main line.

## 10. Acceptance

| Level | Criterion |
| --- | --- |
| Software verification | Kernel known answers (§9). The GDScript model equals the independent HELI-03 model within 1e-6 relative over 5 s of scripted inputs. Airplanes byte-identical. 30/60/144 fps determinism. `test.sh` green. |
| Model-to-paper (held-out) | Hover torque within ±15 % of the paper's operating point. Digitized time responses: peak rates within ±20 %, timing within 0.05 s. Rotor–fuselage modes within ±15 % of the paper-derived 20.1/14.6 rad/s (bare-spring form) or the identified values where they apply. The governor step is calibration, not validation. |
| Emergent behaviour (scripted fixtures) | Each must appear with its declared cause: translational lift (power drop with speed), flap-back (nose-up without cyclic as speed rises), ground-effect power reduction below z/R ≈ 1, VRS (sink increase and roughness at 1.5–6 m/s descent with low forward speed, recovered by forward cyclic), tail blowout at the tail thrust cap, autorotation (Ω sustained with hold, sink within 5–10 m/s pending data), dynamic rollover on the skids. |
| Performance | ≤ 150 µs rotorcraft loads per tick and ≤ 500 µs whole tick (H15 host, median). VFX ≤ 1.5 ms p95 at 720p on the owner's host. 60 fps p95 maintained. |
| Gate HELI-P (pilot) | The owner, and ideally an experienced RC helicopter pilot, flies with a radio: 60 s hover in a 2 m box; pirouettes; forward circuit; a stop; an autorotation landing. Per-axis ratings −2…+2 against a real model, readability at 5–50 m, and disc/wash/sound realism notes. |
| Physical validation | Only HELI-35 measurements count. Software checks and paper comparisons do not establish physical realism for any built aircraft. |

## 11. Decisions for the owner

| ID | Question | Recommendation |
| --- | --- | --- |
| D1 | Admit helicopters as a second vehicle class? | **Yes**, as an isolated track whose integration must keep airplanes byte-identical |
| D2 | Reference aircraft | **X-Cell .60 SE (MIT configuration)**: the only complete, validated data. Alternative: a modern 700-class flybarless electric with estimated data. |
| D3 | Mass configuration | **As identified (8.2 kg, instrumented)** first; a stock variant later, labelled estimated |
| D4 | Head type first | **Flybar lumped** (matches the data); flybarless with the second aircraft |
| D5 | Data format | **Implemented:** `openrc-aircraft v2`, `vehicle: "rotorcraft"`, dedicated closed schema/reader (§5). Versioned actuator/construction extensions precede HX-700 adoption. |
| D6 | Input layout | **Keep four sticks**; flight/electronics modes in `modes`; simulator-owned curves |
| D7 | Beginner aid | Offer the self-level only as labelled "trainer electronics", off by default. No invented autopilot. |
| D8 | Prefix and ownership | `HELI-`; the owned/coordinated paths in the header |
| D9 | Visual asset source | **Selected 2026-10-13; new delivery 2026-10-14:** reuse the supplied HX-700 sources and embedded generator. HELI-25a owns the installed visual; HELI-25b reviews the articulated revision, with adoption planned in §8.1.1. |
| D10 | Pad placement and default start | Pad on the mown area north of the pilot at ≈ 10–15 m; start on the pad, rotor stopped, hold engaged |

## 12. Risks

| # | Risk | Mitigation |
| --- | --- | --- |
| R1 | GDScript cost exceeds the budget | Closed-form model; scalarized kernels; HELI-09 stops integration if over budget. A native kernel is a separate decision under Gate P. |
| R2 | Handling is dominated by electronics gains that are estimated | Separate airframe validation (HELI-24) from electronics tuning; label the gains; rely on pilot rating |
| R3 | No public RC autorotation or hover-power measurements | Declare the gap; HELI-35 collects them; accept ranges, not values |
| R4 | The instrumented X-Cell is not a stock model | Name the configuration; stock variant later |
| R5 | Churn in main-line files (`flight_session.gd`, `simulation.gd`) | One callback seam; byte-identity proofs; serialize the integration steps |
| R6 | Compatibility particle limits; no particle simulation headless; capture route loses history | Shared probe first; pure-function tests for laws; xvfb captures with prewarm |
| R7 | Rotor visual aliasing at real frame rates | Analytic temporal coverage, not a phase-true mesh |
| R8 | Keyboard unflyability frustrates first users | Recommend radio/gamepad; honest trainer electronics only with D7 |
| R9 | GPL contamination from ArduPilot or FlightGear | Implement from papers; cite; never copy code |
| R10 | Scope creep (multirotor, scale heads, water) | Non-goals in §4.13; each needs its own plan |
| R11 | Johnson's VRS curve or Padfield terms mis-transcribed | HELI-02 reads the primary text; HELI-03 is an independent implementation; tests use the published breakpoints |

## 13. Open questions

1. Does the owner fly or own a helicopter (model, electronics, radio setup)? That decides HELI-35 and the second aircraft.
2. Should the first build ship the X-Cell's real flybar handling (slower, more stable) even though most current pilots fly flybarless?
3. Is a dirt or gravel pad surface wanted on the default field? It is the only way rotor-wash dust is physically justified there.
