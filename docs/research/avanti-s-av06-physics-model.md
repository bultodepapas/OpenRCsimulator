# Avanti S: turbine, physics data and flight validation (AV-05 to AV-07)

2026-10-06 · AV-05/AV-06/AV-07 · **The Avanti S flies: experimental physics estimate, validated against its own data and the research envelopes; not flight-identified.**

Scope: SebArt Avanti S Jet 2.2m (A200, 2.00 m span) with a JetCat P100-RX, catalog ID `sebart-avanti-s-a200-p100rx`, in-air start, flaps up, gear up. Inputs: [requirements audit](avanti-s-av05-physics-requirements.md), [turbine research](avanti-s-av05-turbine-dynamics.md), [airframe research](avanti-s-av06-airframe-data.md), [aero references](avanti-s-av06-aero-references.md). Generated data: [derivation](../../research/avanti-s/av06/derivation.md).

## 1. What was built

| Piece | File | Notes |
| --- | --- | --- |
| Turbojet model | [turbine.gd](../../app/physics/turbine.gd) | ECU throttle map; spool dN/dt = clamp((N_cmd − N)/τ_gov, −R_dec(N), R_acc(N)); bench thrust table × installed factor; momentum theory with ram recovery: ṁ = ṁ0(1 + c·u²), V_jet = √(V_j0² + k(N)·u²); captured-air momentum −ṁ·v_air at the intakes (ram drag + inlet normal force); spool gyro I·ω; no reaction torque, no propwash |
| Loader branch | [aircraft_data.gd](../../app/physics/aircraft_data.gd) `_turbine` | `propulsion.kind = "turbine"` inside `openrc-aircraft v1`; absent kind = glow propeller (all older files unchanged); propeller keys refused on a turbine |
| Dispatch | `Propulsion.steady_rpm/loads`, `Dynamics.rotor_momentum`, `FlightSession._pre_step` | two-line hooks; trim, session, traces and HUD work unchanged |
| Differential ailerons | `controls.max_throw.aileron_down` (optional), `Commands.surface_deflections_deg` | manual 30° up / 25° down; refused if down > up |
| Data generator | [derive_physics.py](../../research/avanti-s/av06/derive_physics.py) + [inputs.json](../../research/avanti-s/av06/inputs.json) | every input `{value, unit, kind, source}`; `--check` in `app/test.sh` |
| Sensitivity | [sensitivity.py](../../research/avanti-s/av06/sensitivity.py) | one input at a time, nothing written |
| Flight tests | [test_turbine.gd](../../app/tests/test_turbine.gd) (27), [test_avanti_handling.gd](../../app/tests/test_avanti_handling.gd) (30) | plus the app trace in `test.sh` |

## 2. Evidence classes of the main numbers

| Quantity | Value | Class | Basis |
| --- | --- | --- | --- |
| Span, dry mass, CG, throws | 2.00 m, 10.5 kg, 240 mm, 30/25/30/30° | verified | SebArt manual |
| P100-RX idle/max rpm, thrust, air and fuel flow | 44k/154k rpm, 2/100 N, 0.23 kg/s | verified | JetCat catalog 2017 |
| Thrust vs rpm | 100·(n/154k)^3.12 N | derived | catalog end points; JetCat P160/P220 ECU fits (b 3.14/3.21) |
| Throttle map | n = idle + Δn·s^(1/3) | derived | ECU "ThrStick Curve" 3.0 (thrust follows the stick) |
| Spool | R_acc 0.4·n, R_dec 0.6·n rpm/s, τ_gov 0.4 s | approximation | idle → 95 % thrust 3.6 s, max → 5 % 1.6 s; P100 models and traces 2–3.6 s (±40 %) |
| Installed thrust | 0.92 of bench | approximation | tube and intakes, range 0.85–0.97 |
| Wing panel, stab half, airframe | 626 g, 149 g, 5.3 kg | verified (owners) | forum measurements |
| Fuel | 1.6 l of the 3.2 l stock tank, 0.80 kg/l | derived | dealer volume, catalog density; declared half-tank state |
| Wing, stab, fin areas, sweep | 0.702, 0.165, 0.169 m², 14.9° c/4 | approximation | AV-02 photo blockout; no published area |
| CL_max, e, CD0 | 0.85, 0.75, 0.035 | approximation | DATCOM, Nita–Scholz, component build-up |
| Neutral point | 271 mm (46.5 % MAC) | simulator-specific anchor | see §3 |

## 3. Stability and balance: what the blockout could not explain

Two independent symptoms point at the same unresolved geometry error:

- **Neutral point.** Blockout + textbook methods (Helmbold with sweep, DATCOM downwash, Munk–Multhopp fuselage with Biot–Savart upwash) give 225 mm aft of the root LE. The manual's CG range 240–260 mm, flown by many owners, would then be 4–10 % MAC unstable. The real airplane is stable there.
- **Balance.** The inventory (owner-measured structure, catalog engine, estimated equipment) balances at 140 mm. Builders move batteries and electronics to balance; at the bay limit (z 0.30 m) a 0.40 kg virtual tail weight is still needed.

A wing placed 12.5 cm further forward on the fuselage would balance the inventory with no ballast, but it moves the textbook neutral point by only +23 mm and would be visible in the photo overlays, so it was **not** adopted. Instead the neutral point is anchored on documented data: the manual's aft-most CG (260 mm, "3D unlimited") is taken as near-neutral (3 % MAC, range 0–6 %). The wing-body aerodynamic centre moves aft by 50 mm (13.8 % MAC) to meet it. That one shift is reported in the derivation; nothing else is tuned. Result: static margin 8.5 % MAC at the beginner CG.

**To resolve with measurements:** root LE station and root chord at the fuselage, stab span and chord, fuselage width at the wing, and the battery and tank positions of a real P100 build.

## 4. Sensitivity

`python3 research/avanti-s/av06/sensitivity.py`. Fuel rows keep the baseline balance (the tank sits ahead of the CG); other rows re-balance onto 240 mm.

| Case | Mass (kg) | CG (mm) | Stall (m/s) | Vmax (m/s) | SM at CG (% MAC) | Roll at 40 m/s, D/R 50 % (°/s) | Climb at start (m/s) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| baseline | 11.76 | 240 | 17.8 | 73.4 | 8.5 | 260 | 17.9 |
| wing area 0.78 m2 (+11 %) | 11.73 | 240 | 16.8 | 72.4 | 8.0 | 261 | 17.8 |
| wing area 0.85 m2 (sibling scaling, +21 %) | 11.71 | 240 | 16.1 | 71.5 | 7.6 | 262 | 17.7 |
| CL_max 0.75 | 11.76 | 240 | 18.9 | 73.4 | 8.5 | 260 | 17.9 |
| CL_max 0.95 | 11.76 | 240 | 16.8 | 73.4 | 8.5 | 260 | 17.9 |
| installed thrust 0.85 | 11.76 | 240 | 17.8 | 70.3 | 8.5 | 260 | 16.1 |
| installed thrust 0.97 | 11.76 | 240 | 17.8 | 75.5 | 8.5 | 260 | 19.1 |
| excrescence factor 1.05 | 11.76 | 240 | 17.8 | 76.8 | 8.5 | 260 | 18.1 |
| excrescence factor 1.25 | 11.76 | 240 | 17.8 | 70.5 | 8.5 | 260 | 17.6 |
| Oswald e 0.70 | 11.76 | 240 | 17.8 | 73.4 | 8.5 | 260 | 17.8 |
| full tank (3.2 l) | 13.04 | 221 | 18.9 | 73.3 | 13.7 | 260 | 15.6 |
| empty tank | 10.48 | 263 | 16.5 | 73.4 | 2.1 | 260 | 20.8 |
| anchor margin 0 % at 260 mm | 11.76 | 240 | 17.8 | 73.4 | 5.5 | 260 | 17.9 |
| anchor margin 6 % at 260 mm | 11.76 | 240 | 17.8 | 73.4 | 11.5 | 260 | 17.9 |

Reading: the area uncertainty moves stall by −1.7 m/s and Vmax by −3 %. The fuel state moves the CG 42 mm, from 221 mm (full) to 263 mm (empty), the same pattern as SebArt's Krill manual (240 mm full, 260 mm at landing). An empty tank leaves 2 % MAC margin: realistic and important for AV-10 (fuel burn).

## 5. Validation results

Flown through the real session loop (`test_avanti_handling.gd`, 30 checks, 9 s) and the app's `--trace` path (`check_trimmed_flight.py`):

| Check | Result | Reference |
| --- | --- | --- |
| Trim at 29 m/s | throttle 8.6 %, α 4.1°, elevator −1.8°, no aileron or rudder | thrust follows the stick; no torque to trim |
| Hands-off 30 s | Δalt 0.0000 m, ΔV 0.00000 m/s | — |
| Spool-up idle → 95 % thrust | 3.60 s | P100 evidence 2–3.6 s |
| Spool-down max → 5 % | 1.61 s | faster than spool-up (P100 model) |
| Roll, D/R 50 %, 29 / 45 m/s | 188 / 282 °/s | single-axis prediction ± 7 % |
| Maximum level speed | 73.3 m/s (264 km/h) | manual: tested to 250 km/h; owner GPS ~180 km/h half throttle with 2.2× thrust |
| Clean 1-g stall | 17.8 m/s | aero estimate 17.2–17.9 m/s |
| Power-off glide | L/D 9.4 | — |
| Idle energy loss | −31.9 m²/s³ vs polar −33.3 (4 %) | ± 15 % |
| Pattern loop, 50 m/s, 0.25 stick | 360° in 6.4 s, min 31.9 m/s | > stall |
| Full-up + full-rudder entry | α 68°, \|ω\| 1.4 rad/s, wallowing stall, no steady spin | fuselage-loaded jet (Iyy ≈ 4 Ixx) |
| Recovery 1 s opposite rudder, then neutral | α 4°, \|ω\| 0.44 rad/s 2–3 s later | owners: snaps out of loops, wing drop in slow flight |
| Inertia | 0.62 / 2.44 / 2.97 kg·m² | research window Ixx 0.55–0.90, Iyy 1.9–2.3 (slightly above), Izz 2.9–3.6 |

A real bug was found on the way: the generator first omitted the ram-recovery keys, which the loader accepts as optional. The simulator then flew the plain momentum law (Vmax 70.5 m/s) while the report assumed ram recovery (73.4 m/s). The handling test now fails if the keys are missing.

## 6. What the simulator cannot represent yet (shared changes, not hidden by tuning)

| Missing | Effect | Needed |
| --- | --- | --- |
| Flap command and flap aerodynamics | no 20°/50° takeoff and landing; approach on a clean wing (stall 17.8 vs ~15 m/s with 50°) | input channel + session state + aero increments (researched: ΔCLmax +0.18/+0.33, ΔCD +0.016/+0.070, flap Cm, elevator mix): AV-09 |
| Retract state, gear contacts, brakes | in-air start only; no takeoff or landing | gear state with drag/hull per state; E1/E2 contacts already exist: AV-09 |
| Fuel burn | mass and CG fixed at half tank; real CG travels 221 → 263 mm | AV-10 (G4) |
| Engine start/stop, flameout, fuel cut | glide starts with the engine already stopped | G2 |
| Transmitter D/R and expo | full high-rate throws at full stick; set D/R on the radio | product decision (rates in the app or the radio) |
| Ground effect, altitude and temperature | flare and hot-day performance | shared physics |
| Fuselage Cnb (v1 contract) | weathercock stability overestimated | shared, all aircraft |
| Turbine sound | two-stroke synth plays at turbine rpm | AV-08 (render track) |
| Rotation sense of the P100 spool | gyroscopic sign assumed (not published) | owner observation or JetCat |

## 7. What this does not prove

No flight data of an Avanti S exists publicly (no telemetry, stall speed or roll rate). Consistency checks prove the implementation matches its data; the envelope checks only show the estimate is inside ranges from manuals, other engines and textbook methods. The neutral-point anchor encodes the manufacturer's CG range, not a measured stability. Pilot evaluation (Gate 2) is still to come.

## Reproduce

```bash
python3 research/avanti-s/av06/derive_physics.py           # data file + derivation report
python3 research/avanti-s/av06/sensitivity.py              # sensitivity table
$(app/get-godot.sh) --headless --path app --script res://tests/test_avanti_handling.gd
$(app/get-godot.sh) --path app -- --aircraft=sebart-avanti-s-a200-p100rx   # fly it
```
