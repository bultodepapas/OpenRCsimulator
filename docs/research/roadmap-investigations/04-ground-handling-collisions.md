# 04 — Landing gear, tyres, ground handling, terrain, collisions and crashes

**Status:** research knowledge base, 2026-10-06. **Serves:** ROADMAP M2 E3b (stiction, runway start, takeoff roll), E3c (circuit and landing), E3d (nose-over, wingtip scrape vs crash), E4 (circuit golden), PT2; LANDSCAPE-PLAN L12–L14 (terrain, trees as obstacles); taildragger gear for the Extra 300S and P-51D; P51-11 (retracts, flaps); hand launch; damage. **Read with:** [ROADMAP M2](../../../ROADMAP.md), [E1 gear contact](../landing-gear-contact-e1.md), [E2 tyre friction](../ground-friction-e2.md), [E3a surfaces](../ground-surfaces-e3a.md), [RESEARCH.md: ten additional investigations, items 1–2](../../../RESEARCH.md#ten-additional-investigations), [LANDSCAPE-PLAN](../../LANDSCAPE-PLAN.md), [terrain sampler spike](../landscape-investigations/03-terrain-mesh-gdscript.md).

## Summary

1. **Stiction: use a per-contact stick/slip anchor held in `aux`** (YASim's "stuck point", an elasto-plastic/Dahl-type model): mode and anchor change only in `pre_step`, once per tick; inside the four RK4 stages the anchor is a plain spring-damper. Deterministic, no chatter, no creep, and in slip mode the force is today's E2 law bit for bit, so goldens survive.
2. **Anchor stiffness has the same bound as E1:** Σk ≤ m(0.1/dt)² = **1,662 N/m** for the Stik at 240 Hz. Holding idle thrust (2.60 N) then deflects the anchor by 1.6 mm. YASim's fixed 5 mm breakaway would be 3,622 N/m (ω·dt 0.148): derive k from the rule, not from a distance.
3. **JSBSim does not use a penalty friction law:** it solves the tyre and structure friction forces as clamped Lagrange multipliers (projected Gauss-Seidel, ≤ 50 iterations) that cancel the contact velocity within one step. Exact stiction, but the force depends on the other forces and on dt, so it is not a pure function of the state. **Not recommended here** (RK4 stages, goldens).
4. **Takeoff hand estimate for the Stik (E3b proof target):** with the APC table, thrust is 41.3 N static (T/W 1.46). Full throttle from rest with the elevator neutral reaches 10 m/s in **4.69 m / 1.15 s on the mown runway** (C_rr 0.10). With the elevator full up, the nose wheel unloads at **V_R ≈ 11.3 m/s (1.19 V_s) after ≈ 6.0 m** (runway), 12.4 m/s after 7.8 m (mown), 13.3 m/s after 10.0 m (rough). V_R is set by the elevator's free-stream authority and will drop when propwash (E0b) lands.
5. **Tricycle versus taildragger, in numbers:** with tyre cornering stiffness proportional to wheel load, both layouts are neutral-steer. A taildragger diverges when its tailwheel grips less than its share. For the Extra, a tailwheel at 30 % of its load-proportional stiffness diverges above **5.0 m/s** (no aero), and a free caster diverges at any speed. The Stik stays stable even with a free-castering nose wheel.
6. **Nose-over (quasi-static; corrected by E5b, 2026-10-09):** `d/h` is the main-contact pitch-moment threshold at a specified attitude. Current Extra: 0.604 three-point, **0.369 tail-up**; P-51: 0.651 / 0.348. A tail-up aircraft already has a clear tail; its smaller ratio is not the threshold for first tail lift from three-point support. Whether real rough grass or a soft spot reaches either ratio remains unmeasured. [E5b derivation and verification](../ground-contact/E5b/README.md).
7. **Hull points must become frictional contacts with per-component crash thresholds** (CRRCSim has `max_force` per hardpoint; PicaSim uses per-axis Δv and Δω limits plus a suspension crash force and a prop-strike box). Proposed: each point carries its normal impact-speed limit, friction μ and stiffness; a wingtip touched at walking pace is a scrape.
8. **Touchdown force jump:** E1's damper produces a 54 N step at first contact at 1 m/s sink (107 N at 2 m/s). This costs RK4 its order near bounces, which matches E1's finding of first-order convergence. Ramp the damping with compression (Hunt–Crossley style) and add rebound damping (JSBSim C172: 2–4× the compression damping).
9. **Rolling resistance on grass has a physical scale:** for a rigid wheel, C_rr = √(z/d) (z = sinkage, d = diameter). E3a's 0.10, 0.20 and 0.30 on a 76 mm wheel imply 0.8, 3 and 7 mm of sinkage, which is plausible. The same sinkage on a 165 mm wheel gives 0.07, 0.14 and 0.20. Wheel diameter belongs in the gear data.
10. **Never use Godot physics queries in the simulation:** `PhysicsDirectSpaceState3D` works in 32-bit `Vector3` (`cast_motion` returns a `PackedFloat32Array`), is safe only in `_physics_process`, and depends on the selected engine (DEFAULT = GodotPhysics3D; Jolt is the default for projects created since 4.6). Keep a float64 terrain and obstacle model on the sim side, and cache one plane per contact per tick.
11. **Launches are initial conditions first:** hand launch at about 6 m/s and 20° up (PicaSim data), a 0.2 s motor delay (ArduPilot), catapult ≥ 20 m/s², bungee as a tension-only spring later. The Stik (V_s 9.5 m/s, 2.9 kg) is not a hand-launch airplane.
12. **Every ground number is borrowed or estimated.** The cheapest independent validation: pull the real Stik across the grass with a luggage scale (gives static breakaway and C_rr), coast-down and idle-creep videos, and the takeoff roll measured with cones.

## Where the code stands

Facts from the repository on 2026-10-06. Several files have uncommitted changes from other tracks, among them a new `app/physics/slipstream.gd`: an opt-in E0b first slice, used first on the P-51.

| Area | Today | File |
| --- | --- | --- |
| Ground | Flat NED plane `down = 0` | [ground_contact.gd](../../../app/physics/ground_contact.gd) |
| Normal force | Per wheel `F = max(0, k·δ + c·δ̇)`, with δ measured along NED down (vertical, not along the strut), applied at the fixed wheel-bottom point, moment `r × F`. Stik: mains 560 N/m, nose 440 N/m, ζ 0.4, 0.12 m travel (all estimated) | same; [E1](../landing-gear-contact-e1.md) |
| Tyre forces | Rolling `−C_rr·N·sat(v_long/v_creep)` with v_creep = max(0.01, 0.1·C_rr) m/s; side `−μN·sat(tan slip / tan 6°)` with a 1 m/s slip floor; friction circle. Pure functions of the state, so every RK4 stage sees the same law | same; [E2](../ground-friction-e2.md) |
| Stiction | **None.** A steady push below C_rr·N creeps at v_creep·F/(C_rr N), about 0.9 cm/s at idle on grass | same, `ROLL_CREEP` comment |
| Surfaces | Runway, mown and rough rectangles scale μ (0.8 / 0.7 / 0.7) and C_rr (×2.5 / ×5 / ×7.5); looked up per wheel in every stage | [ground_surfaces.gd](../../../app/physics/ground_surfaces.gd), [surface_friction.json](../../../app/data/ground/surface_friction.json) |
| Steering | Nose wheel ±20° from the rudder **servo** position; no tailwheel, no caster, no brakes | `flight_session._loads` |
| Crash | Every tick after integration: any `crash_hull` point with `down ≥ 0` → crash; any leg past `max_compression` → "gear collapsed". The scene freezes for `CRASH_HOLD_S` = 1.5 s, then resets to the trimmed **airborne** start. Hull points carry no force, so a belly slide, a wingtip scrape or a nose-over all end the flight at once | [flight_session.gd](../../../app/sim/flight_session.gd) `touches_ground`, `gear_collapsed`, `_crash` |
| Hull data | `crash_hull`: a flat list of points (Stik 8: tips, spinner, tail, stab tips, fin, belly) | [jensen_ugly_stik_60.json](../../../app/data/aircraft/jensen_ugly_stik_60.json) |
| Taildraggers | Extra and P-51 have **no `landing_gear`**: their wheels are hull points, so touching the ground is a crash (D9d) | `gp_extra_300s_60.json`, `p51d_mustang_120.json` (generated) |
| Aux state | `aux` = [rpm, 3 servos], advanced once per tick in `pre_step`, held over the RK4 stages; the simulation rejects non-finite or resized aux | [simulation.gd](../../../app/sim/simulation.gd) |
| Rendering | `airplane.apply_gear(wheel_angles, steering)` exists but the sim does not feed it | [airplane.gd](../../../app/render/airplane.gd) |
| Terrain | L12a plan: float64 triangle-exact sampler `sim/terrain.gd`, 1.1–1.8 µs/call measured, grid all-zero at first; L14: trees as float64 cylinders | [LANDSCAPE-PLAN](../../LANDSCAPE-PLAN.md) |

**Missing for M2:** stiction, a runway start state, takeoff and landing proofs, frictional hull contacts, crash criteria by component, rebound damping, a continuous touchdown force, brakes, tailwheel gear, retracts, terrain normals, obstacles, launch modes and damage.

## Theory and models

### 1. Gear models in open simulators (exact formulas)

**JSBSim `FGLGear` / `FGAccelerations`** (LGPL-2.1; master, read 2026-10-06):
- Strut: `F = min(−k·δ − c·δ̇, 0)`, linear or `SQUARE` damping, separate `damping_coeff_rebound` when extending; optional `maximumForce` per surface. First-contact guard `|δ̇| ≤ δ/dt`.
- `BOGEY` (wheel, compression along the strut) vs `STRUCTURE` (hull point, along the ground normal, isotropic friction).
- Side force, Pacejka "magic formula" (no relaxation length): `D·sin(C·atan(B·s − E·(B·s − atan(B·s))))`, s in degrees, B 0.06, C 2.8, D = μ_s, E 1.03; a `CORNERING_COEFF` table can replace it; × surface `staticFFactor`.
- Brakes: `C_roll = rollingFFactor·C_rr + brake·staticFFactor·(μ_s − C_rr)` (assumes anti-skid); groups LEFT, RIGHT, CENTER, NOSE, TAIL, NONE.
- Friction **solve**: roll and side multipliers bounded by ±coefficient·F_n, solved by projected Gauss-Seidel (Catto 2005; ≤ 50 iterations) so that they cancel `v + a·dt` at every contact; moving STRUCTURE points get one dynamic multiplier (μ_d·F_n).
- "Crash" is only an out-of-bounds report (sink > 44 ft/s).
- C172: tyres μ_s 0.8, μ_d 0.5, C_rr 0.022; rebound damping 2–4× compression; wingtips and tail skid are STRUCTURE with μ 0.2.

**FlightGear YASim `Gear`** (GPL-2.0):
- Normal: `fmag = clen·spring·(frac + spring2·frac²)` plus damping along the ground normal, clamped so that |damp| ≤ fmag.
- Without stiction: friction = μ·N·min(|v|/0.1 m/s, 1) (the same regularisation as our E2; static μ 0.8, dynamic 0.7, rolling 0.02 by default).
- **With `stiction`:** each gear keeps a **stuck point** in global coordinates. The tangential force is a spring `|d|/fric_spring · N·μ_s` (fric_spring = **5 mm**) plus a damper `|v|·N·μ_s`. When the deflection exceeds fric_spring, or the force exceeds μN, the gear is "rolling" or "slipping". `Model::newState` calls `updateStuckPoint` **once per integrated step**: when rolling, the point slides along the wheel heading (with up to 5° of "tyre flex" slip); when slipping, it resets to the contact. This is our recommended pattern.
- Ground "bumpiness" is a deterministic height function of position.

**CRRCSim `gear01/gear.cpp`** (GPL-2.0): per hardpoint `F_n = k·penetration − c·v_down`; tarmac μ_max 0.8, sliding 0.55, rolling 0.01, brake 0.6; lateral μ ramps from 0 at 0.1 m/s to sliding at 1 m/s. **Crash = any hardpoint's normal force > `max_force`.** Hardpoints can be animated by a `RETRACT` channel.

**PicaSim** (PolyForm Noncommercial: **numbers only**, never code): Bullet `btRaycastVehicle` wheels; retracts rate-limited at 1/s with an `unretractedDrag` area. Crash flags: AIRFRAME when the per-tick body-axis **Δv** exceeds 3–5 m/s (x, y) or 3–10 m/s (z), or **Δω** exceeds 300–750 °/s (scaled by √size); UNDERCARRIAGE when the suspension force exceeds `suspensionCrashForce` (Extra3DLarge 120 N); PROPELLER when a box at the disc touches anything while the prop turns faster than `crashPropSpeed`. Launch: 6 m/s at +20° (ElectricKato).

**X-Plane 11.0 beta 14:** removing the "locked down when stopped" hack made the Cessna "wander around the runway like a drunken moose" until beta 15. A parked-drift test is mandatory for any stiction change.

**ArduPilot SITL** (GPL-3.0): no gear; on the ground it clamps height and removes velocity components (`GROUND_BEHAVIOR`). Fine for autopilots, wrong for handling.

**Gazebo/ODE:** friction pyramid (μ, μ2, `fdir1`, `slip1/2`) and soft contact `kp`/`kd`, with ERP = h·kp/(h·kp + kd) and CFM = 1/(h·kp + kd): the implicit-Euler form of a spring-damper.

### 2. Stiction without chatter

| Model | Law | State | Fit here |
| --- | --- | --- | --- |
| Regularised Coulomb (today) | F = −F_max·sat(v/v_ε) | none | No hold under a steady push; creep ∝ F |
| Karnopp (1985) | Dead zone \|v\| < DV: stuck, and F equals the applied force up to F_s; outside it F = F_c·sign(v) | none, but it needs the "applied force" | Needs the sum of the other forces in each stage; discontinuous; awkward with 6-DOF couplings |
| Dahl (1968) | dF/dx = σ₀(1 − F/F_c·sign v)^α | one per direction | Smooth, no static breakaway peak |
| LuGre (Canudas de Wit et al. 1995) | ż = v − σ₀\|v\|z/g(v); g(v) = F_c + (F_s − F_c)e^{−(v/v_s)²}; F = σ₀z + σ₁ż + σ₂v | one per direction | Physically rich (Stribeck, pre-sliding), but **stiff**: the paper's σ₀ = 1e5 N/m on 1 kg gives ω·dt = 1.3 at 240 Hz. Its z is integrated **inside** RK4, which makes `aux` part of the ODE |
| Elasto-plastic / anchor (YASim stuck point; Gonthier et al. 2004 bristle) | F = −k·(p − a) − c·v_t inside the friction limit; the anchor a moves when the limit is exceeded | 2 floats (anchor N, E) + a mode flag per contact | **Recommended.** Same structure as `aux`; k is chosen by the ω·dt rule |
| Constraint/PGS (JSBSim, Box2D, PhysX) | Multipliers solved so that v_t = 0, clamped at μN | warm-start multipliers | Exact stiction, but the loads are no longer a pure function of the state |

**Recommended law (L1, E3b).** Per contact `i`, aux holds `mode_i ∈ {0 slip, 1 stick}` and the anchor `(a_N, a_E)` on the ground plane.

- RK4 stages (pure):
  - slip mode: `F_t = F_E2(v)` (today's law, unchanged);
  - stick mode: `d = p_contact − a`, split along the wheel heading into (d_long, d_lat);
    `F_long = −k_a·d_long − c_a·v_long`, clamped to ±F_break,long, where F_break,long = C_rr,static·N (brakes off) or the brake law;
    `F_lat = −k_a·d_lat − c_a·v_lat`, clamped to ±μN; then the friction circle.
- `pre_step` (once per tick, from the end-of-tick state):
  - slip → stick if the contact is on the ground, `|v_t| < v_stick` (0.02 m/s, estimated) and the E2 force alone holds the contact (\|F_E2\| < limit); the anchor goes to the current contact point, so the force starts continuous;
  - stick → slip if the spring force exceeds its limit in either axis, or if the contact lifts off; the anchor is cleared.
- Stiffness: Σk_a ≤ m(0.1/dt)² (1,662 N/m for the Stik, so 554 N/m per wheel); `c_a = 2ζ√(k_a·m/n)` with ζ 0.7. Hold deflection at idle 1.6 mm; on a 3° slope 0.9 mm.
- Why it is RK4-safe: the force inside a step is smooth (one clamp at most); modes change only between steps; the anchor is a constant within the step, like rpm. Determinism comes from a fixed tick and an ordered contact list.
- Energy: the stored ½k_a d² is released when the contact slips (dissipated by the damper and E2). Verify "friction power + d/dt(anchor energy) ≤ 0" per tick.
- Lateral relaxation (later, L2): in stick-roll mode, letting the anchor slide **along the heading only** (YASim "rolling") turns the lateral spring into a first-order tyre lag with relaxation length σ = C_α/k_lat. Pacejka's rule of thumb: σ ≈ wheel radius, measured 0.12–0.45 m on motorcycle tyres. With k_lat = μN/1 cm, σ = 1 cm / tan 6° ≈ 9.5 cm for the Stik (≈ 2.5 wheel radii).

### 3. Tyres and surfaces for RC

- **Rolling resistance:** a rigid wheel on yielding ground gives C_rr = √(z/d) (Wikipedia, after Guiggiani 2018). On hard pavement the diameter effect is "negligible within practical diameters". Full-size grass: 0.05 short, 0.08 long, 0.13 long and wet (Stinton, quoted in a HAW Hamburg thesis; search result only); FlightGear grass 0.05–0.1 (E3a). **No measured C_rr exists for 2.5–3.5 in RC foam or rubber wheels on mown grass**: the wheelchair studies found cover drum and carpet only, and smaller casters (4 in) resist most on most surfaces. E3a's 0.10/0.20/0.30 stay estimates.
- **Bekker-lite (L2):** pressure–sinkage p = (k_c/b + k_φ)·zⁿ (Project Chrono SCM, BSD-3), which gives sinkage z from wheel load, width b and diameter, then C_rr = √(z/d). No verified k_c, k_φ, n exist for turf: postpone, and calibrate with the luggage-scale test.
- **Static versus rolling:** a wheel at rest needs a breakaway force above rolling (bearing, tyre flat spot, grass). Keep `breakaway_factor` = C_rr,static/C_rr (estimated 1.0–1.5, unverified) as data, not a constant.
- **μ (side, peak):** 0.8 dry pavement (JSBSim); grass 0.7× (FlightGear). RC foam tyres on grass are unmeasured.
- **Brakes on RC:** rare; used on some giant-scale and jet models (mechanical or air brakes on a channel, often mixed with rudder for differential braking; unverified product data). Model them with JSBSim's formula and brake groups.
- **Grass height:** a pure rolling-factor model ignores bump steer and nose-wheel "digging". FlightGear's bumpiness is a deterministic function of position: a cheap L2 option, applied to the per-tick plane cache.

### 4. Taildragger, tricycle, nose-over, weathervaning

Bicycle model on the ground (derived; `C` = cornering stiffness, `a` = front contact ahead of the CG, `b` = rear contact behind it, L = a + b):
- the yaw stiffness term is `C_r·b − C_f·a`; the system is stable if it is ≥ 0, otherwise it diverges above V_crit² = L²·C_f·C_r / (m·(C_f·a − C_r·b));
- if `C ∝ N` (same μ and peak slip on every tyre), then N_f = W·b/L and N_r = W·a/L, so **C_f·a = C_r·b exactly: neutral**, for tricycle and taildragger alike;
- **taildragger** (front = mains, rear = tailwheel): every loss of tailwheel grip (small hard wheel, spring-coupled steering, castering, tail-up, light tail) makes C_r·b < C_f·a, i.e. divergence. Computed for the Extra (mains 0.135 m ahead of the CG, tailwheel 0.805 m behind, μ 0.64, I_zz 0.30 kg·m² estimated):

  | Tailwheel stiffness, % of load share | Diverges above, no aero | With aero C_nβ 0.12 |
  | --- | --- | --- |
  | 100 / 50 | never / 7.5 m/s | never / never |
  | 30 | 5.0 m/s | 5.25 m/s, restabilised ≈ 16 m/s |
  | 0 (free caster) | 0.5 m/s | 0.5 m/s, restabilised ≈ 20 m/s |

  This is the FAA description in numbers: the airplane "begins to pivot", the inertia at the CG "continues and even tightens the turn", and there is a speed band where "neither [rudder nor tailwheel] is wholly effective".
- **Tricycle** (front = nose, rear = mains): a free-castering nose wheel (C_f = 0) stays stable (Stik max eigenvalue −0.42 /s, 0.5–25 m/s). Its failure is **wheel-barrowing** (nose wheel overloaded) and **tip-over in turns** (E2: the Stik tips before it slides).
- **Tailwheel steering:** spring-coupled to the rudder servo; PicaSim's Extra uses ±45°. Model it as a steered contact with `max_steering` plus a castering option, and an optional spring compliance (L2: a steering angle that lags with the side load).
- **Nose-over (quasi-static, derived, rigid gear):** with no other pitching moment, main-only normal load `N` and backward drag `D` give nose-up moment `N*d - D*h`. Thus `D/N = d/h` is the zero-moment threshold; `atan(d/h)` is the geometric angle from vertical, not the ratio itself. First tail lift uses the three-point attitude; a tail-up ratio concerns pitch reversal with the tail already clear. The table below retains the original rounded geometry estimates; [E5b](../ground-contact/E5b/README.md) records current loaded inputs and explicitly separates these events. Fixed body contact points penetrate the nominal plane under spring load, so use their actual force arms or approach the rigid limit.

  | Aircraft (generator geometry) | Ground attitude | Tail down: d/h (angle) | Tail up: d/h (angle) | Prop-tip strike after nose-down rotation |
  | --- | --- | --- | --- | --- |
  | Extra 300S | 10.9° | 0.60 (31°) | 0.37 (20°) | 19.5° |
  | P-51D 1/4 | 13.9° | 0.66 (33°) | 0.35 (19°) | 14.8° |
  | Stik (tricycle; mains behind the CG) | level | tip-back: mains 21° behind the CG vertical; tail strike at 18.5° pitch | — | Forward tip over the nose wheel needs μ > 1.07: only a leg collapse or a bump can do it |

  Raymer's textbook ranges (not fetched; quoted from memory, unverified): tricycle mains ≥ 15° behind the CG vertical; taildragger mains 16–25° ahead of it in the tail-down attitude. The generators' 31–33° are outside that range. **Re-check the Extra and P-51 gear positions or their CG** before E5-T1 (as E1 found for the Stik's visual axle).
- **Weathervaning:** more side area behind the main wheels than ahead of them makes the airplane turn into the wind (FAA). It comes for free once wind (M5) feeds the aero model while the airplane is on the gear. It is more pronounced on taildraggers because the pivot (mains) sits farther forward.

### 5. Takeoff and landing performance

Ground roll (Anderson/Raymer form; derived): `a = g[(T/W − μ_r) − (ρS/(2W))(C_D − μ_r·C_L)V²]`. With constant thrust: `S_G = (1/2B)·ln(A/(A − B·V²))`, where A = g(T/W − μ_r) and B = gρS(C_D − μ_r·C_L)/(2W). The best ground C_L is μ_r/(2k). Course notes use V_LO = 1.2 V_s; Anderson uses 1.1 V_s.

**Stik hand estimate** (inputs from `jensen_ugly_stik_60.json`: m 2.885 kg, S 0.4645 m², CL0 0.1068, CLα 4.58, CLδe 0.0983, CD0 0.0434, k 0.0815, Cm0 −0.0278, Cmδe −0.8488 /rad, elevator 20°, CLmax 1.1; thrust = Ct(J)·ρn²D⁴ from the APC table with the rpm lag τ 0.25 s from idle 2,800 to 11,149 rpm; ground attitude −0.39°, CG 0.24 m above the ground and 0.094 m ahead of the mains):
- V_s = 9.51 m/s; static thrust 41.3 N (T/W 1.46); idle thrust 2.60 N.
- **Elevator neutral, throttle slammed, distance to 10 m/s:** pavement 4.52 m (1.10 s), runway 4.69 m (1.15 s), mown 5.02 m, rough 5.41 m. The constant-T₀ closed form gives 3.65–4.45 m: the gap is the spool-up lag and the thrust lapse with J.
- **Rotation** (nose wheel unloads; moment about the main contact including the d'Alembert term `m·a·h`; thrust passes through the CG height, so T·h cancels against it except for (D + F_rr)·h): V_R = 10.65 m/s / 5.1 m (pavement), **11.33 m/s / 6.0 m (runway)**, 12.36 / 7.8 (mown), 13.29 / 10.0 (rough). With a 2 s throttle ramp: runway 7.7 m, 2.4 s. Rotated to α 8°: V_LO 11.8 m/s; to 10°: 10.7 m/s. So the Stik lifts off almost as soon as it rotates.
- Uncertainty: about ±20 % on V_R. It ignores tail-force arm differences (≈ 13 %), ground effect and propwash; E0b will lower V_R.

Script (reproduces the numbers; plain Python 3):

```python
import math
g,rho,m,S,c,D=9.80665,1.225,2.8850583,0.464515,0.3048,0.3048; W=m*g
CL0,CLa,CLde,CD0,k,CLmd,Cm0,Cma,Cmde=0.1068,4.58,0.0983,0.0434,0.0814934,0.23,-0.0278,-0.723,-0.8488
ct=[(0,.113),(.373,.0796),(.414,.0725),(.457,.0633),(.504,.0537),(.55,.0437)]
Ct=lambda J:next(c0+(c1-c0)*(J-j0)/(j1-j0) for (j0,c0),(j1,c1) in zip(ct,ct[1:]) if J<=j1)
idle,nmax,tau,xcg,h=2800,11149,.25,.094,.24; zD=h+.07; ag=math.radians(-.39)
def roll(crr,de,vstop=None,dt=1e-4):
    t=V=x=0; rpm=idle
    while t<20:
        rpm=nmax-(nmax-rpm)*math.exp(-dt/tau); n=rpm/60
        T=Ct(V/(n*D))*rho*n*n*D**4; q=.5*rho*V*V
        CL=CL0+CLa*ag+CLde*de; Dg=q*S*(CD0+k*(CL-CLmd)**2); L=q*S*CL; F=crr*max(W-L,0)
        M=-xcg*(W-L)+(zD-h)*Dg-h*F+q*S*c*(Cm0+Cma*ag+Cmde*de)
        if (vstop and V>=vstop) or (vstop is None and M>=0): return V,x,t
        V+=(T-Dg-F)/m*dt; x+=V*dt; t+=dt
print(roll(.10,0,10.0), roll(.10,math.radians(-20)))   # runway: (10.0, 4.69, 1.15) (11.33, 6.04, 1.28)
```

**Landing and bounce:**
- E1 gear (ζ 0.4, clamped): a vertical contact event has restitution e = 0.36 (linear theory without the clamp: 0.25), 26 mm peak compression and 2.0 g at 1 m/s sink, 52 mm and 4.1 g at 2 m/s. Rebound damping ×2 gives e = 0.26.
- Typical RC bounces come from lift, not from the springs. A taildragger wheel landing pitches the nose **up** (mains ahead of the CG), raises α and balloons; a tricycle touching on its mains pitches the nose down and sticks. That falls out of the contact geometry for free.
- Flare: in ground effect the induced drag drops and the lift slope rises (another aero investigation covers this; it is not modelled today).
- Hard landings: E1 collapses at > 0.12 m travel ≈ 2.5–3 m/s sink. CRRCSim and PicaSim use a **force** limit instead (k·δ_max = 67 N per Stik main, ≈ 2.4 g on one wheel). No published RC wire- or aluminium-gear failure data was found: the limits stay estimated, and the owner's judgement ("this would have bent the gear") is the validation.

### 6. Contact geometry, crash versus scrape, damage

- **Points first, shapes later:** wingtips, spinner/prop disc, belly, tail, stab tips, fin top and canopy as STRUCTURE-like points. Each has a spring-damper normal force along the ground normal and Coulomb friction (JSBSim C172 uses μ 0.2 on pavement; balsa or film on grass is unmeasured, estimated 0.3–0.5), plus the same anchor so an airplane resting on a tip does not creep.
- **Kinetic energy for scale (Stik):** 3 J at 1.4 m/s (walking), 13 J at 3, 36 J at 5, 144 J at 10, 325 J at 15 m/s.
- **Crash criterion, data-driven per point (proposal):** a crash happens when, at first penetration (point above the ground in `sim.previous`, at or below it in `sim.state`), the **normal contact speed** `v_n = R₃·(v + ω×r)` exceeds the point's `crash_normal_speed`; or its penetration exceeds `crash_depth` (a backstop for slow crushes); or a gear contact exceeds `max_force`/`max_compression`; or the prop disc touches with rpm > `strike_rpm`.

| Component | crash_normal_speed (m/s) | μ on grass | Other | Kind |
| --- | --- | --- | --- | --- |
| Wing tip | 1.5 | 0.4 | sustained slide > 8 m/s for > 0.2 s → crash (cartwheel risk) | estimated |
| Belly / fuselage bottom | 2.5 (≈ gear-collapse energy) | 0.4 | belly landing below this = scrape | estimated |
| Fin, rudder, stab tips | 1.0 | 0.4 | — | estimated |
| Canopy / top (inverted) | 1.0 | 0.4 | — | estimated |
| Spinner / prop disc | 2.0 | 0.4 | rpm > 1.5 × idle at contact → prop strike: **engine stops**, not a crash | estimated; PicaSim has a prop crash box gated by prop speed |
| Gear leg | — | tyre law | `max_force` 67 N (Stik main, = k·δ_max) | derived from E1 |
| Global backstop | Δv_body per tick > 5 m/s or \|Δω\| > 750 °/s | — | — | borrowed (PicaSim Trainer) |

- **E3d's two anchors:** a wingtip touched at walking pace (E2's tip-over at 1.88 m/s rolls the tip down at ≈ 1 m/s, estimated) is a scrape, and the airplane rocks back. A nose-in at 10 m/s gives v_n ≫ 2 m/s: crash.
- **Damage (later):** RealFlight and aerofly have breakable parts (product feature, details unverified here). A damage model needs the component aero buildup (Gate F direction) so that a lost tip removes its strip. Order: crash events by component (E3d), then "continue after a scrape", then part loss.
- **Crash-to-reset UX:** keep the 1.5 s hold, show the component and speed ("left wingtip, 3.2 m/s"), and write a trace event row. A durability multiplier (settings, recorded in the trace header) lets players soften the thresholds without changing the physics data.

### 7. Terrain and obstacles

- **Height field:** L12a's sampler (float64, triangle-exact, diagonal rule) also returns the plane: height `h(n,e)`, normal `n̂` = normalize(−∂h/∂n, −∂h/∂e, −1) in NED, and the surface id. Compression along n̂: `δ = n̂·(p − p₀)`. Friction lies in the tangent plane, and the heading is projected on that plane, as JSBSim's ground frame does.
- **Per-tick plane cache (recommended):** in `pre_step`, query once per contact at the end-of-tick position (plus the predicted motion v·dt), store (p₀, n̂, factors) in aux and evaluate the plane in the stages. Cost: ≈ 11 contacts × 1.5 µs ≈ 17 µs/tick, against 44 queries (≈ 66 µs) if the sampler runs every stage; L12's budget is ≤ 10 µs/tick, so skip contacts above the reach. At 30 m/s a point moves 0.125 m per tick: well inside a terrain triangle. Crossing an edge mid-tick costs a planar extrapolation error, and the next tick corrects it.
- **Slope:** parked on a slope, the anchor must hold `m·g·sin θ`. A 3° slope needs 1.48 N, more than C_rr·N on pavement (1.13 N): the Stik rolls downhill on pavement and holds on grass, as a real one would.
- **Trees (L14):** a trunk capsule plus a crown cylinder in float64. Broad phase: a uniform grid (32 m cells) built at load; per tick, test only the cells within the airplane's bounding sphere (half-span + |v|·dt). The 480 treeline trees cost one cell lookup when the airplane is far away. Narrow phase: segment (previous → current position of each hull point) against the capsule, so nothing tunnels. Crown contact = crash (estimated; real models usually lodge in trees).
- **Godot queries:** see the Godot section. Runway markings and textures have no physical role; the surface table does.

### 8. Launch methods

| Method | What the sim needs | Data |
| --- | --- | --- |
| Hand launch | A start mode: position at shoulder height, velocity along the throw (ground-relative, separate from airspeed when there is wind), pitch-up, throttle delay | PicaSim 6 m/s, +20° (ElectricKato); ArduPilot motor delay ≥ 0.2 s, acceleration trigger 15 m/s², min speed 4 m/s |
| Catapult or rail | Initial speed at the rail exit, or a short scripted acceleration | ArduPilot trigger ≈ 20 m/s², delay 0.5 s |
| Bungee / hi-start | A tension-only spring from a ground stake to the hook (position in aircraft data), with release at a line angle or when slack; it adds a pitching moment | YASim `Hitch` (tow length, elasticity, break force); ArduPilot delay ≈ 5 s |
| Runway | Static solve on the gear, engine at idle, all anchors in stick mode | E3b |

The Stik's V_s is 9.5 m/s at 2.9 kg, so a hand launch needs either a hard throw (≈ 8–10 m/s, unrealistic by hand) or T/W > 1 to hang on the prop: not a sensible hand-launch aircraft. Launch modes matter for future foamies and gliders.

### Fidelity levels

| Level | Gear and tyres | Hull and crash | Terrain |
| --- | --- | --- | --- |
| L0 (today) | Spring-damper, regularised friction, surfaces | Hull point = instant crash | Flat |
| L1 (M2) | + anchor stiction, rebound damping, continuous touchdown, brakes, tailwheel steer/caster | Frictional hull points, crash thresholds by component, prop-strike event | Flat; surfaces |
| L2 | + wheel radius geometry, lateral relaxation, Bekker-lite C_rr, bumpiness, retract kinematics, strut compliance | Damage events (part loss) | L12 sampler with per-tick planes; trees |
| L3 | Constraint solve (PGS) or C++ GDExtension; flexible wire gear (fore-aft and lateral) | Shape contacts (capsules) | Deformable soil |

## Implementation options and trade-offs

| Decision | Options | Recommendation |
| --- | --- | --- |
| Stiction | Keep the creep / LuGre inside RK4 / **anchor in aux** / PGS solve | **Anchor.** LuGre is stiff and puts aux into the ODE; PGS breaks "loads = f(state, aux)" |
| Touchdown damping | Linear c·δ̇ / JSBSim's dt-based speed clamp / **c·min(1, δ/δ_r)·δ̇** | **Ramp** (δ_r ≈ 5 mm, estimated): continuous and dt-free |
| Crash rule | Global Δv (PicaSim) / force (CRRCSim) / **per-point normal speed** | Per point, plus a gear force limit, with global Δv as a backstop |
| Terrain query | Godot raycast / sampler every stage / **per-tick plane cache** | Plane cache |
| Side law at speed | E2 / Pacejka / relaxation | Keep E2 for M2; relaxation at L2 if PT2 finds taxiing "darty" |
| Rolling resistance | Surface factors / √(z/d) per wheel | Factors for M2; diameter-aware after the field test |

## Godot / GDScript notes

- **No engine physics in `sim/` or `physics/`.** `PhysicsDirectSpaceState3D` (4.x) uses 32-bit `Vector3` (unless the engine is built with `precision=double`); `cast_motion` returns a `PackedFloat32Array`; the space is safe to access only in `_physics_process`. The engine is `DEFAULT` (GodotPhysics3D today, "may change"; Jolt is the default for projects created since 4.6), so results can change with the engine, and queries see bodies at the last physics sync, not at RK4 stage positions.
- **Precision:** float32 steps by ≈ 0.2 mm at 2–4 km (Godot large-world docs); a 1.6 mm anchor needs float64.
- **Aux layout:** append `[mode, a_N, a_E]` per contact (Stik: 11 contacts = 33 floats), later the plane cache. Size is fixed per aircraft at load, so `Simulation.step`'s size check holds. Modes are 0.0/1.0.
- **Performance:** taxiing already adds 25–65 µs/tick (E2) to a 510 µs baseline (budget 500). Eight hull points × 4 stages could add 40–80 µs (estimated). Mitigations: a per-point early-out from CG altitude and maximum point depth (like `reach`), flat contact arrays instead of Dictionaries; the contact loop is the cleanest GDExtension candidate.
- **Determinism:** fixed contact order, no Dictionary iteration in the hot path, no `randf`; bumpiness integer-hashed (as L13a), never `FastNoiseLite` (float32).
- **Rendering:** feed `airplane.apply_gear` (wheel angle ∫ v_long/r dt in render state; steering sign −δ, see E2).

## Reusable libraries, tools, code and datasets

| Name | What it gives us | License | Link | How to use it here |
| --- | --- | --- | --- | --- |
| JSBSim `FGLGear`, `FGAccelerations`, `c172x.xml` | Strut, rebound and square-law damping, brake groups, Pacejka, BOGEY/STRUCTURE, PGS friction; C172 tyre values | LGPL-2.1 | github.com/JSBSim-Team/jsbsim | Formulas and numbers, cited; no code copy |
| FlightGear YASim `Gear`, `Model`, `Hitch` | Stuck-point stiction, bumpiness, tow | GPL-2.0 | github.com/FlightGear/flightgear | Pattern only (clean-room) |
| CRRCSim `gear01` | `max_force` crash per hardpoint; tarmac μ; retract hardpoints | GPL-2.0 | github.com/mrtbrnz/crrcsim (mirror) | Pattern and numbers |
| PicaSim | Crash Δv/Δω, suspension crash force, prop-strike box, launch data | PolyForm Noncommercial 1.0.0 | github.com/Rowlhouse/PicaSim | **Numbers only** |
| ArduPilot automatic takeoff | Launch-phase parameters | GPL-3.0 (code) | ardupilot.org | Launch data |
| Box2D (Catto) | Soft constraints; PGS reference | MIT | box2d.org | Reference for L3 |
| Project Chrono SCM | Bekker–Wong soil | BSD-3-Clause | api.projectchrono.org | Bekker-lite equations (L2) |
| auralius/LuGre | 1995 paper reconstruction | none declared | github.com/auralius/LuGre | Equation cross-check only |
| L12a `sim/terrain.gd` (planned) | Float64 height + plane | project (MIT) | [LANDSCAPE-PLAN](../../LANDSCAPE-PLAN.md) | Ground query |

## Parameters and data

| Quantity | Value | Unit | Kind | Source |
| --- | --- | --- | --- | --- |
| Tyre μ_s / μ_d, dry pavement | 0.8 / 0.5 | 1 | borrowed | JSBSim c172x |
| Tyre C_rr, full-size, pavement | 0.022 (JSBSim), 0.02 (YASim default), 0.01 (CRRCSim) | 1 | borrowed | sources 3, 5, 8 |
| Grass C_rr, full-size: short / long / long wet | 0.05 / 0.08 / 0.13 | 1 | borrowed (search result only) | Stinton via Lucht thesis |
| Stik C_rr: pavement / runway / mown / rough | 0.04 / 0.10 / 0.20 / 0.30 | 1 | estimated / borrowed factors | E2, E3a |
| Implied rigid-wheel sinkage (76 mm) | 0.12 / 0.76 / 3.0 / 6.8 | mm | derived | √(z/d) |
| Structure contact μ (wingtip, skid), pavement | 0.2 | 1 | borrowed | JSBSim c172x |
| Hull μ on grass (balsa or film) | 0.3–0.5 | 1 | estimated | — |
| JSBSim Pacejka B / C / E | 0.06 /° / 2.8 / 1.03 | — | borrowed | FGLGear.cpp |
| Relaxation length | ≈ wheel radius; 0.12–0.45 m measured on motorcycle tyres | m | borrowed | Pacejka 2006 via Wikipedia |
| Rebound / compression damping | 2–4 | ratio | borrowed | JSBSim c172x |
| YASim stiction spring breakaway | 5 | mm | borrowed | Gear.cpp |
| Anchor Σk (Stik, 240 Hz) | ≤ 1,662 | N/m | derived | ω·dt < 0.1 |
| Anchor stick speed v_stick | 0.02 | m/s | estimated | — |
| Breakaway factor C_rr,static/C_rr | 1.0–1.5 | 1 | estimated (unverified) | — |
| LuGre Table I (1 kg lab mass, not RC) | σ₀ 1e5 N/m, σ₁ √1e5 N·s/m, σ₂ 0.4 N·s/m, F_c 1 N, F_s 1.5 N, v_s 0.001 m/s | — | borrowed | Canudas de Wit 1995 via auralius/LuGre |
| Stik W, V_s, T_static, idle thrust | 28.3 N, 9.51 m/s, 41.3 N, 2.60 N | — | derived | aircraft JSON |
| Stik V_R runway / mown / rough | 11.3 / 12.4 / 13.3 | m/s | derived (±20 %) | §5 |
| Stik tail-strike pitch; mains behind CG | 18.5; 21.4 | ° | derived | E1 geometry |
| Gear restitution (E1, clamped); touchdown force step at 1 m/s | 0.36; 54 N | — | derived | §5 |
| Gear max_force (Stik main) | 67 | N | derived | 560 N/m × 0.12 m |
| PicaSim crash Δv (x, y, z); Δω | 3–5, 3–5, 3–10 m/s; 300–750 °/s | — | borrowed | PicaSim settings XML |
| PicaSim suspension crash force; tailwheel steering (Extra3DLarge, 1.5 m) | 120 N; 45° | — | borrowed | Aeroplane.xml |
| Hand launch: speed / angle; motor delay; trigger | 6 m/s / +20°; ≥ 0.2 s; 15 m/s² (catapult 20) | — | borrowed | PicaSim; ArduPilot docs |
| Extra / P-51: nose-over d/h tail-up; Extra V_crit at 30 % tailwheel grip | 0.37 / 0.35; 5.0 m/s | — | derived from generated geometry | §4 |

## Validation

**Verification (known answers):**
1. Anchor hold: idle on the runway for 60 s → drift < 2 mm (today 0.9 cm/s). On pavement (2.60 N > 1.13 N) it must still roll as today.
2. Breakaway: a force ramp of 0.1 N/s breaks away at C_rr,static·N ± 1 %.
3. Energy: friction power + d/dt(anchor energy) ≤ 0 over 2,000 random states (random modes and anchors).
4. Slip mode = E2 bit for bit: coast-downs, figure-eight, goldens, `--trace` rows unchanged.
5. h vs h/2 on a parked-then-taxi run, with modes switching at the same ticks.
6. Takeoff: distance to 10 m/s within 3 % of the §5 integral (4.69 m runway); nose-wheel unload at 11.3 ± 0.5 m/s.
7. Nose-over: tail-up main-only pitch moment changes sign at its attitude-specific d/h ± 2 %; a separate quasi-static three-point test lifts the tail at its larger ratio. Sudden patch dynamics and real soft-ground coefficients require separate evidence.
8. Ground loop: `linearize.gd` yaw eigenvalue of the taxiing Extra vs the bicycle model ± 10 %.
9. Bounce: e within ±0.03 of the law; no force step at onset.
10. Crash rules: tip at walking pace no; nose-in at 10 m/s yes; belly at 1 m/s sink slides; at 3 m/s crashes.

**Independent validation (owner, cheap):** luggage-scale pull of the real Stik on the grass runway (breakaway peak and steady pull, 5 repeats); coast-down and idle-creep videos; takeoff distance with cones every 2 m; turn radius at full steer and the speed at which the Stik tips in a turn; PT2 ratings for taxiing, takeoff run and landing bounce.

**Mutation tests that must fail:** anchor spring sign flipped (energy gain); anchor never released (cannot take off); mode switched inside RK4 stages (h/h2 and determinism fail); hull friction sign flipped; crash threshold ignored (nose-in survives); surface lookup at the CG instead of per contact; terrain plane cache not refreshed (slope test drifts).

## Pitfalls and risks

1. **Creep or chatter at rest** (X-Plane's "drunken moose"). Mitigation: the anchor, plus a parked-drift test in `app/test.sh`.
2. **Mode logic inside RK4 stages** breaks determinism and order. Mitigation: switch only in `pre_step`.
3. **Stiff anchor** (a 5 mm breakaway gives ω·dt 0.148). Mitigation: k from the rule; the loader refuses Σk above the bound.
4. **Energy from moving the anchor.** Mitigation: move it only toward the limit circle; energy check (verification 3).
5. **Touchdown force step** drops RK4 to first order at bounces. Mitigation: ramped damping; an h/h2 order check on a drop.
6. **Instant-crash hull** forbids belly landings and scrapes. Mitigation: E3d.
7. **V_R depends on propwash** (E0b in progress). Mitigation: split the E3b proof (neutral-elevator integral + rotation check); re-baseline the rotation speed when the Stik opts into the slipstream.
8. **Implausible taildragger geometry** (31–33° tail-down). Mitigation: re-check the generators' gear x and CG first.
9. **Contact fixed at the wheel bottom:** at 14° tail-down the true lowest point moves r·sin 14° (≈ 9 mm on a 76 mm wheel). Mitigation: L2 wheel-circle geometry.
10. **Godot float32 queries leaking into the sim.** Mitigation: add `direct_space_state` to the float64 guard's banned list for `sim/` and `physics/`.
11. **Performance over budget.** Mitigation: early-outs, flat arrays, µs/tick per step, GDExtension.
12. **Crash thresholds decide fun.** Mitigation: honest data plus a durability multiplier in settings, recorded in the trace.
13. **Surface and terrain edges** (steps in μ and in the normal). Mitigation: the per-tick plane cache; friction power ≤ 0 across edges (as E3a).
14. **Validation gap:** every ground value is borrowed or estimated. Mitigation: the owner's field tests before PT2.

## Proposed roadmap steps

| Proposed ID | Step | Proof | Depends on |
| --- | --- | --- | --- |
| E3b1 | Stick/slip anchor per gear contact in `aux` (mode, a_N, a_E), switched in `pre_step`; slip = E2 law | Parked at idle on the runway 60 s: drift < 2 mm (today 0.9 cm/s); breakaway ramp at C_rr,static·N ± 1 %; goldens and trace rows unchanged | E3a |
| E3b2 | Runway start: static solve on the gear at the threshold, engine at idle, anchors stuck | After 1 s: \|v\| < 1e-6 m/s, ΣF_n = m·g ± 0.1 %, attitude within 0.1° of the solve | E3b1 |
| E3b3 | Takeoff roll proof | Distance to 10 m/s within 3 % of the hand integral (runway 4.69 m); nose-wheel unload within ±0.5 m/s of 11.3 m/s; lift-off logged | E3b2 |
| E3b4 | Continuous touchdown (ramped damping) and rebound damping | Drop e within ±0.03 of the law; no force step at onset; h/h2 order ≥ 3 through a bounce | E1 |
| E3c1 | Closed-loop approach and flare maneuver for tests (`sim/maneuvers.gd`) | Touchdown sink ≤ 1 m/s on the runway, roll-out stops on the runway, no crash | E3b3 |
| E3c2 | Full circuit trace (takeoff, pattern, landing, roll-out) | Trace + capture; no hull contact; stop within the runway | E3c1 |
| E3d1 | Hull points become frictional contacts (data: component, stiffness, μ, crash_normal_speed, crash_depth), with anchors | Wingtip at walking pace: no crash, rocks back; nose-in at 10 m/s: crash; belly 1 m/s sink: slides to a stop | E3b1 |
| E3d2 | Prop strike event (engine stops above strike_rpm) and crash reasons by component in UI and trace | The message names the component and speed; a prop-strike-only test keeps the airframe and stops the engine | E3d1 |
| E4 | Golden of the full circuit | Replay matches; C_rr +10 % and the anchor stiffness ×2 are both detected | E3c2 |
| PT2 | Owner playtest of takeoffs and landings, plus field tests (scale pull, coast-down, idle, takeoff distance) | Ratings and measured C_rr / breakaway recorded; data updated with kind `measured` | E4 |
| E5-T1 | Taildragger gear for the Extra and P-51 via their generators (tailwheel steered by rudder ± caster option) | Sits tail-down at the geometric attitude ± 0.5°; yaw eigenvalue vs bicycle model ± 10 %; free caster diverges at 5 m/s | E3d1, generator geometry re-check |
| E5-T2 | Nose-over check (mapped to ROADMAP E5b) | Separate tail-up moment reversal and three-point tail lift at their own rigid d/h ± 2 %; verify compliance and loading-rate effects rather than assuming earlier lift | E5-T1 |
| E5-B | Brakes (JSBSim formula, brake groups, channel or rudder-differential) | Straight braking deceleration = μ_brake·g ± 2 %; taildragger noses over at the oracle threshold | E5-T1 |
| E5-R | Retracts (P51-11): gear position in aux, rate-limited; contact disabled up; drag area; belly points active | Cycle time matches data; gear-up landing at 0.8 m/s sink slides (scrape) | E3d1 |
| X-ground-1 | Wheel-radius contact geometry and per-wheel diameter in data | Tail-down static attitude error < 1 mm vs analytic circle | E5-T1 |
| X-ground-2 | Bekker-lite C_rr(d, surface) | Reproduces E3a for 76 mm wheels; the P-51's larger wheels roll easier by √(d₁/d₂) at equal sinkage | PT2 measurements |
| X-terrain-1 | Contacts on the L12a sampler via the per-tick plane cache; compression and friction along n̂ | All-zero grid: trace bytes identical; tilted-plane test: holds on 3° (grass), rolls on pavement; ≤ 10 µs/tick | L12a, E3b1 |
| X-terrain-2 | Hillside crash and slope landing (L13b) | Scripted trace crashes on a hillside at the predicted tick ± 1 | X-terrain-1, E3d1 |
| X-obstacle-1 | Trees as float64 capsules and crown cylinders, grid broad phase, swept test (L14) | Scripted flight into a tree crashes at the right tick ± 1; between trees no crash; µs/tick reported | L14, E3d1 |
| X-launch-1 | Hand and catapult launch start modes (state + throttle delay) | Start state equals the requested (v, θ) exactly; the motor starts after the delay | UI-06 scenarios |
| X-launch-2 | Bungee / hi-start tension-only spring with release | Energy: ½k·x² → kinetic plus potential within damping losses; release at the line angle | X-launch-1 |
| X-damage-1 | Part loss (tip, gear leg) after a component crash, aero strips removed | Lost-tip roll moment matches the strip removal in `linearize.gd` | E3d2, component aero |

## Decisions to take now

1. **Contact state lives in `sim.aux`**, sized per aircraft at load (modes, anchors, later plane caches). Reason: traces, goldens, resets and the h/h2 tests must see it. Choosing FlightSession-side state now would break replay later.
2. **One contact list with a type** (wheel / structure), replacing the bare `crash_hull` list with `contacts` that carry their component, stiffness, μ and crash limits. Keep `crash_hull` as the legacy fallback so existing data loads; this is an additive optional field in `openrc-aircraft v1`.
3. **Loads stay a pure function of (state, aux).** No constraint solver in the stages: penalty and anchor laws only. That keeps RK4, goldens and the GDExtension path simple.
4. **The ground interface is `ground(n, e) → (h, n̂, surface factors)` in float64 on the sim side**, cached once per tick per contact. Never Godot physics. The flat plane is its first implementation, so L12a plugs in without touching `ground_contact.gd` again.
5. **Static breakaway, rolling C_rr, side μ and wheel diameter are separate data**, so the field measurements can replace each one independently.
6. **Crash is an event with a reason**, defined by per-component data, and separate from reset policy (hold-and-reset today, "continue after scrape" later, damage later).
7. **Owner decisions needed:** (a) is a prop strike at idle a crash or "engine stopped, keep rolling"? (b) default durability (realistic vs forgiving)? (c) agree to run the luggage-scale, coast-down and takeoff-distance tests before PT2?

## Sources

1. JSBSim Team, `src/models/FGLGear.cpp` and `FGLGear.h`, master, read 2026-10-06. https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/FGLGear.cpp (fetched)
2. JSBSim Team, `src/models/FGAccelerations.cpp` (PGS friction), master. https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/FGAccelerations.cpp (fetched)
3. JSBSim Team, `aircraft/c172x/c172x.xml` ground reactions. https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/aircraft/c172x/c172x.xml (fetched)
4. JSBSim FGLGear class documentation. https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGLGear.html (cited via RESEARCH.md, not re-fetched)
5. FlightGear, YASim `Gear.cpp`, branch next. https://raw.githubusercontent.com/FlightGear/flightgear/next/src/FDM/YASim/Gear.cpp (fetched)
6. FlightGear, YASim `Model.cpp` (`newState` → `updateStuckPoint`). https://raw.githubusercontent.com/FlightGear/flightgear/next/src/FDM/YASim/Model.cpp (fetched)
7. FlightGear, YASim `Hitch.hpp`. https://raw.githubusercontent.com/FlightGear/flightgear/next/src/FDM/YASim/Hitch.hpp (cited via RESEARCH.md)
8. CRRCSim (Reucker, Kansky, Wulf), `src/mod_fdm/gear01/gear.cpp`, GPL-2.0, GitHub mirror. https://raw.githubusercontent.com/mrtbrnz/crrcsim/HEAD/src/mod_fdm/gear01/gear.cpp (fetched)
9. D. Chapman, PicaSim source: `Wheel.cpp`, `AeroplanePhysics.cpp`, README licence notes. https://github.com/Rowlhouse/PicaSim (fetched)
10. PicaSim data: `data/SystemData/Aeroplanes/Extra3DLarge/Aeroplane.xml`; `data/SystemSettings/Aeroplane/{AcroBat,ElectricKato,Trainer}.xml`. https://github.com/Rowlhouse/PicaSim/tree/main/data (fetched)
11. ArduPilot, `libraries/SITL/SIM_Aircraft.cpp`. https://raw.githubusercontent.com/ArduPilot/ardupilot/master/libraries/SITL/SIM_Aircraft.cpp (fetched)
12. ArduPilot, Automatic Takeoff (hand, catapult, bungee). https://ardupilot.org/plane/docs/automatic-takeoff.html (fetched)
13. Open Robotics, SDFormat 1.11 `surface.sdf`. https://raw.githubusercontent.com/gazebosim/sdformat/main/sdf/1.11/surface.sdf (fetched)
14. ODE background (ERP/CFM ↔ kp/kd), ROS wiki mirror. https://mirror.umd.edu/roswiki/opende(2f)Background.html (search result only)
15. E. Catto, "Soft Constraints", GDC 2011. https://box2d.org/files/ErinCatto_SoftConstraints_GDC2011.pdf (fetched)
16. C. Canudas de Wit, H. Olsson, K. J. Åström, P. Lischinsky, "A new model for control of systems with friction", IEEE TAC 40(3):419–425, 1995. https://lup.lub.lu.se/search/publication/8517353 (search result only); https://ieeexplore.ieee.org/document/376053 (linked from 17)
17. A. Ramadhan (auralius), LuGre reconstruction (Table I parameters). https://github.com/auralius/LuGre (fetched)
18. D. Karnopp, "Computer simulation of stick-slip friction in mechanical dynamic systems", J. Dyn. Sys. Meas. Control 107(1):100–103, 1985; Simulink implementation page. https://mathworks.com/matlabcentral/fileexchange/155462-karnopp-s-model-stick-slip-friction-dynamics-in-simulink (search result only)
19. Y. Gonthier, J. McPhee, C. Lange, J.-C. Piedbœuf, "A regularized contact model with asymmetric damping and dwell-time dependent friction", Multibody Syst. Dyn. 11:209–233, 2004. https://doi.org/10.1023/B:MUBO.0000029392.21648.bc (DOI verified via Crossref 2026-10-06; not read)
20. Altair, MotionSolve friction formulation (LuGre, Dahl comparison). https://2022.help.altair.com/2022/hwsolvers/altair_help/topics/tools/bushing_model_friction_formulation_ms_r.htm (fetched)
21. Laminar Research (B. Supnik), "X-Plane 11.0 public beta 14 is out". https://developer.x-plane.com/?p=7504 (fetched)
22. Wikipedia, "Rolling resistance" (√(z/d), diameter dependence). https://en.wikipedia.org/wiki/Rolling_resistance (fetched)
23. Wikipedia, "Relaxation length" (after Pacejka 2006, Cossalter 2006). https://en.wikipedia.org/wiki/Relaxation_length (fetched)
24. Wikipedia, "Ground loop (aviation)"; "Conventional landing gear"; "Tricycle landing gear". https://en.wikipedia.org/wiki/Ground_loop_(aviation) (fetched)
25. FAA, Airplane Flying Handbook FAA-H-8083-3C, ch. 14 "Transition to Tailwheel Airplanes". https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/15_afh_ch14.pdf (fetched)
26. C. Lutze, AOE 3104 notes "Takeoff and Landing", Virginia Tech. https://archive.aoe.vt.edu/lutze/AOE3104/takeoff&landing.pdf (fetched; equations are images, structure only)
27. Lucht, bachelor thesis, HAW Hamburg (quotes Stinton's grass C_rr). https://www.fzt.haw-hamburg.de/pers/Scholz/arbeiten/TextLuchtBachelor.pdf (search result only)
28. Project Chrono, vehicle terrain models (SCM, Bekker). https://api.projectchrono.org/vehicle_terrain.html (fetched)
29. Godot Engine, `doc/classes/PhysicsDirectSpaceState3D.xml` and `ProjectSettings.xml` (physics_engine, Jolt default since 4.6), master. https://github.com/godotengine/godot/tree/master/doc/classes (fetched)
30. Godot docs, "Ray-casting" (space safe only in `_physics_process`). https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html (fetched as rst)
31. Godot docs, "Large world coordinates". https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html (fetched as rst)
32. Evaluation of rolling resistance in manual wheelchair wheels and casters (drum, carpets only). https://pmc.ncbi.nlm.nih.gov/articles/PMC8049518 (fetched)
33. Dickey et al., RESNA 2018, wheelchair casters on surfaces (4 in highest resistance). https://www.resna.org/sites/default/files/conference/2018/pdf_versions/wheelchair_seating/Dickey.pdf (search result only)
34. Jolt Physics 3.0.1, vehicle collision tester. https://jrouwe.github.io/JoltPhysicsDocs/3.0.1/_vehicle_collision_tester_8h.html (cited via RESEARCH.md)
35. Repository: [ground_contact.gd](../../../app/physics/ground_contact.gd), [ground_surfaces.gd](../../../app/physics/ground_surfaces.gd), [flight_session.gd](../../../app/sim/flight_session.gd), [E1](../landing-gear-contact-e1.md), [E2](../ground-friction-e2.md), [E3a](../ground-surfaces-e3a.md), [LANDSCAPE-PLAN](../../LANDSCAPE-PLAN.md) (read 2026-10-06).

Not fetched, quoted from textbook knowledge and marked where used: D. Raymer, *Aircraft Design: A Conceptual Approach* (tip-back and taildragger gear angles); J. D. Anderson, *Introduction to Flight* (V_LO = 1.1 V_s); K. H. Hunt and F. R. E. Crossley 1975 (damping ∝ δ·δ̇); P. Dahl 1968; P. Dupont et al. 2002 (elasto-plastic friction).
