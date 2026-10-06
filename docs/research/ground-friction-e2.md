# E2 — Tyre friction and nose-wheel steering (2026-10-06)

Step E2 of [ROADMAP](../../ROADMAP.md) M2. After [E1](landing-gear-contact-e1.md) the wheels carried the weight but
a landed airplane slid without resistance. E2 adds the tyre forces in the ground plane: the Ugly Stik rolls, coasts
to a stop, steers with the rudder and taxis a figure-eight. Brakes: none. Nothing changes in the air.

## Model

`app/physics/ground_contact.gd`, per wheel in contact with normal load `N` (E1), all in the ground plane (NED N–E):

- **Wheel heading:** body `(cos δ, sin δ, 0)` projected on the ground and normalised; `δ = steer × max_steering`,
  `steer` = the rudder servo's actual position (−1…1, +1 = nose wheel right). Only the nose wheel steers.
- **Contact velocity** `v + ω × r` split into rolling `v_long` and lateral `v_lat` components.
- **Rolling resistance:** `F_long = −C_rr·N·sat(v_long / v_creep)` (linear below the creep speed: no force at rest, no
  chatter). v_creep was 0.05 m/s in E2 and is 0.01 m/s since [E3a](ground-surfaces-e3a.md); the E2 numbers below
  are unchanged by it.
- **Side force:** `F_lat = −μ·N·sat(tan(slip) / tan α_peak)`, `tan(slip) = v_lat / max(|v_long|, 1 m/s)`. Linear
  in the slip angle up to α_peak, saturated at μ·N. Below 1 m/s it is a stiff damper instead of dividing by zero.
- **Friction circle:** `|F_tangential| ≤ μ·N`.
- Each component opposes its own velocity, so friction never adds energy. A gear without `side_friction` stays
  normal-only (E1). A wheel whose heading is vertical gets the normal force only.

**Numerical bound.** The low-speed side force summed over the wheels decays at `λ = μ·g / (tan α_peak · 1 m/s)` for
any airplane (ΣN = m·g). The loader requires `λ·dt ≤ 0.5` (RK4 limit 2.78). Stik: 0.31 at 240 Hz.

## Numbers for the Stik (`landing_gear` in `app/data/aircraft/jensen_ugly_stik_60.json`)

| Quantity | Value | Kind | Source |
| --- | --- | --- | --- |
| μ (peak, side + circle) | 0.8 | borrowed | JSBSim `c172x.xml` `static_friction` 0.8 (tyre on dry pavement) |
| Peak slip angle | 6° | borrowed | Initial slope of JSBSim's default Pacejka side-force curve (`FGLGear.cpp`: stiffness 0.06/°, shape 2.8, curvature 1.03 → slope μ·0.168/°, μ reached at 5.95°) |
| C_rr | 0.04 | estimated | JSBSim C172 `rolling_friction` 0.022, ×2 for a 76 mm RC wheel |
| Nose steering at full rudder | 20° | estimated | RC tricycle practice 15–25° (C172: 10°); kinematic radius 0.351 m / tan 20° = 0.96 m |

All are tyre-on-**dry-pavement** values. The field's surfaces carry no material yet; per-surface factors (grass)
come with E3. Loader rules: friction required with the gear; `C_rr` 0–0.3, `μ` 0.1–1.5, `α_peak` 1–30°,
`max_steering` 0–45° (optional, default 0), units checked, and the λ·dt bound.

## Proof (`app/tests/test_ground_friction.gd`, 26 checks)

| Check | Expected | Measured |
| --- | --- | --- |
| Hand-computed loads (rolling, slipping, reversing, skidding, at rest, steered, 45° heading) | exact | to 1e-12 N |
| Friction power over 2000 random states (1404 touching) | ≤ 0 | max −0.14 W |
| Coast-down from 3 m/s, bare body | C_rr·g = 0.3923 m/s² | 0.3922 (0.02 %); stops in 11.47 m (v²/2a 11.47), then still |
| Full steer at 1 m/s, main-axle radius | L / tan δ = 0.964 m | 0.977 m (+1.3 %), slip 0.49° |
| Full steer at 3 m/s | radius opens (understeer) | 1.348 m, slip 3.43° |
| Tip-over, rigid limit (gear 64× stiffer, 960 Hz), slow speed ramp | inside wheel unloads at g·d/h = 4.47 m/s² | 4.50 m/s² (+0.7 %) at 2.06 m/s |
| Tip-over, real gear | earlier (roll on the springs) | 3.47 m/s² (78 % of rigid) at 1.85 m/s |
| h vs h/2, 3 s turn at 1.5 m/s | agree | 2.9 µm, 6e-9 rad/s |
| Session, parked, engine off, 10 s | still | 5e-10 m |
| Session figure-eight at idle, 30 % steer (6°), stick at 1 throw/s | two full turns, no crash, wheels down | +360.2° / −360.0°, no wheel lifted; loops 7.17 m E and 6.82 m W; right loop closes to 0.017 m; left loop passes 1.24 m from the crossing (speed grows 3 → 3.8 m/s); 18.4 s |

Other evidence:

- `test_aircraft_data.gd` 66 → 72: derived values and five refusals (no friction, peak slip 2° breaks λ·dt, steering
  in rad, steering 60°, C_rr 0.5).
- `test_ground_contact.gd` (22): E1's "no horizontal drift" probe now runs on a normal-only copy of the gear; with
  friction the rocking wheels scrub and really move the CG.
- Mutations on a scratch copy, all caught: side-force sign (14 failures), steering sign (6), no friction circle (1),
  slip floor without `|v_long|` (1, after adding the reversing check), C_rr doubled (5), session not steering (1).
- `--trace --t=3` rows byte-identical (SHA-256 `7d2f8a4c…`); the header's `ground:` line and data fingerprint change.
  Goldens unchanged. `app/test.sh` green.
- Physics cost (VM, noisy): air 511 µs/tick (E1: 510); taxiing on three wheels +25–65 µs/tick over the same loop
  in the air.

**Convergence note.** Near the tip speed a wheel bounces on and off the ground and the h vs h/2 error falls to first
order (ratio 2.0 between successive halvings). At 1 m/s the ratio is 12.7. The h/2 check runs well below the tip speed.

## Findings

1. **The Stik tips before it slides.** For the inside wheel to unload, the needed side grip is d/h = 0.46–0.49,
   below μ = 0.8. Full steer above ≈1.85 m/s lifts the inside wheel, and snapping to full steer at speed rolls it
   onto a wingtip (session at 1.88 m/s: crash). A high-wing tricycle really does this. But a wingtip touch at
   walking pace is a crash for D9d; E3 should decide if a low-energy scrape is a crash.
2. **At idle the Stik rolls on pavement:** idle thrust 2.60 N (2,800 rpm, estimated) > C_rr·m·g 1.13 N. It reaches
   3.8 m/s in 10 s. With no brakes, a taxi pilot controls speed only with steering. On grass (C_rr ≈ 0.1) it would
   sit still. Both inputs are estimates; a coast-down and an idle-creep test on the owner's field would settle them.
3. The model team's main-axle position (E1 finding) is still open. It sets the wheelbase, so it sets the turn
   radius and the tip margin d.

## Not proven / limits

- **No validation yet.** Every check verifies the code against our own data. Independent data still needed: the
  measured turn radius at full steer, a coast-down and an idle-creep test with a real Stik.
- One surface (dry pavement). No skid friction drop (JSBSim dynamic 0.5), no brakes, no wheel inertia, no
  self-aligning torque. The steering follows the rudder servo, yaw trim included.
- The renderer's `airplane.apply_gear` is still not fed. Steering is about model +Y (up), so it needs `−δ`. The
  wheel angle integrates `v_long / radius`.

## Reproduce

```bash
$(app/get-godot.sh) --headless --path app --script res://tests/test_ground_friction.gd
```

Sources: JSBSim (LGPL), `aircraft/c172x/c172x.xml` and `src/models/FGLGear.cpp`, github.com/JSBSim-Team/jsbsim,
read 2026-10-06. Values used as borrowed numbers only, no code copied.
