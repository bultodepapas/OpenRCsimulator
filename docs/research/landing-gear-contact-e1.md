# E1 — Landing gear as spring-damper contacts (2026-10-06)

Step E1 of [ROADMAP](../../ROADMAP.md) M2: the Ugly Stik's three wheels become point contacts with the flat ground,
each a spring-damper on its compression. Before E1 any wheel touching the ground was a crash (D9d). Nothing changes
in the air: the contact adds no term while every wheel is above the ground.

## Model

`app/physics/ground_contact.gd` (pure, 64-bit, evaluated in every RK4 stage):

- Ground: the NED plane `down = 0`. Contact point `i` at body position `r_i` (FRD about the CG). Its NED down
  coordinate is `d_i = pos_D + R₃·r_i`, where `R₃` is the third row of the body→NED rotation (the same row the
  crash hull uses). Compression `δ_i = d_i` when positive.
- Compression rate: the point's velocity in body axes is `v + ω × r_i`; its down component is `δ̇_i = R₃·(v + ω × r_i)`.
- Normal force, up: `F_i = max(0, k_i·δ_i + c_i·δ̇_i)`. The clamp keeps a damper from pulling the wheel into the
  ground on a fast rebound. In body axes the force is `−F_i·R₃`; the moment about the CG is `r_i × F`.
- No tangential force yet (rolling friction, steering and brakes are E2). Because the force is vertical in NED,
  the CG cannot move horizontally during a drop; the test uses that as an integration-error probe.
- A compression beyond `max_compression` is a collapsed leg: a crash like any other hull point.

## Numbers for the Stik (all `estimated`, in `app/data/aircraft/jensen_ugly_stik_60.json`)

| Quantity | Value | How |
| --- | --- | --- |
| Wheel bottoms (le frame, m) | mains (0.215, ±0.18, −0.2581), nose (−0.136, 0, −0.2549) | x from the D9d hull (mains 0.094 m aft of the plan CG, nose 0.257 m ahead); track 0.36 m, axle 0.22 m below the thrust line and wheel radii 0.0381/0.0349 m from the model team's `ugly_stik_geometry.gd` equipment table |
| Stiffness | mains 560 N/m, nose 440 N/m | ROADMAP rule `ω·dt < 0.1` with `ω = √(Σk/m)` at 240 Hz: Σk < 1662 N/m for 2.885 kg. Chosen Σk = 1560 N/m → ω 23.3 rad/s (3.7 Hz), ω·dt = 0.097. The nose/main split makes the static load share (27 % nose, 73 % mains) sag equally, so the airplane sits level |
| Static sag | 18 mm | m·g/Σk; a wire leg plus a foam tyre |
| Damping | mains 18.6, nose 16.5 N·s/m | ζ ≈ 0.4 of the contact's share m/3: `c = 2ζ√(k·m/3)`. The loader refuses ζ outside 0.05–2 |
| Travel before collapse | 0.12 m | energy balance ½mv² = ½Σkδ² plus sag: a level touchdown at 2 m/s sink compresses ≈ 0.10 m, at 3 m/s ≈ 0.15 m, so 2 m/s lands and 3 m/s breaks the gear. The belly (0.053 m below the thrust line) would hit at 0.205 m |
| Belly hull point | (0.12, 0, −0.053) | fuselage bottom under the CG, from the model's fuselage stations; replaces the three wheel points in the crash hull |

The pitch mode on the gear: `k_θ = Σk_i·x_i² ≈ 39 N·m/rad`, `J_yy = 0.387 kg·m²` → 10 rad/s with ζ ≈ 0.2, so the
airplane rocks for a few seconds after a drop (time constant ≈ 0.5 s). A 4 s settle is not enough to reach
10⁻⁴ rad/s; the test waits 6 s.

## Loader rules (`AircraftData._landing_gear`)

`landing_gear` is optional: without it an aircraft keeps the D9d behaviour (every hull point, wheels included, is
a crash). The Extra and the P-51 have no section yet; their generators (`research/extra-300/ex05/`,
`research/p51/p51-05/derive_physics.py`) add it when those tracks reach the ground. With it:

- ≥ 3 named contacts, each `{position, stiffness, damping, max_compression}` with unit, kind and source;
- the CG lies inside the wheelbase and between the sides (the airplane stands on its wheels);
- `ω·dt < 0.1` at the project's physics tick (read from `ProjectSettings`), else "soften the gear or raise the tick";
- each damping ratio in 0.05–2.

## Proof (`app/tests/test_ground_contact.gd`, 22 checks)

- Hand-computed loads: one contact 0.3 m ahead and 0.2 m below the CG at 0.1 m compression sinking at 1 m/s gives
  exactly −110 N and 33 N·m nose-up; a fast rebound gives no force; in the air the function returns an empty array.
- Signs with the Stik's gear: rolled right on the ground → restoring (left) rolling moment; nose-down on the nose
  wheel alone → nose-up moment.
- Drop test (gear only, no air) from 0.5 m: mechanical energy (kinetic + m·g·h + springs) never gains in any tick
  (max gain 0.0 J); at rest after 6 s (3·10⁻⁶ m/s, 5·10⁻⁷ rad/s); the wheels carry exactly m·g with no net moment;
  mean sag within 30 % of the loader's static_sag; rests within 1° of level (−0.39°).
- `h` vs `h/2`: the same 1 s of bouncing at 240 and 480 Hz agrees to 23 µm in altitude, 2.6·10⁻⁴ in quaternion,
  0.3 mm/s in sink. The horizontal drift (2.2 µm at h) shrinks 17.9× at h/2: fourth-order truncation error, not a force.
- Real session: at the trimmed start the session's loads are bit-identical to the air-only evaluator; dropped
  level from 0.35 m with the engine off it lands and rests on three wheels without a crash; from 2.0 m the gear
  collapses (crash at 3.2 m/s sink, message "gear collapsed", restart); inverted at 0.20 m the fin still crashes.
- Mutations on a scratch copy: damper sign flipped → 11 failures (578 J gained in one tick); roll moment sign
  flipped → 8; damper clamp removed → 1; force applied at the CG without moments → 2.
- `test_crash.gd` (12): the belly touches at 0.05 m, the wheels at 0.20 m are not a hull crash, the gear is past its
  travel at 0.10 m; 100 random crashes still crash and restart (two of them by gear collapse).
- `test_aircraft_data.gd` (66): gear track and wheel bottoms agree with the model team's equipment table; the data
  still loads without the section; nine broken-gear cases are refused with specific messages.
- Trace rows of `--trace --t=3` are byte-identical before and after (SHA-256 `7d2f8a4c…`); the header gains a
  `ground:` line and the new data fingerprint. Goldens unchanged. Physics cost on this VM 525.6 → 510.5 µs/tick
  (noise; the air path adds one altitude comparison per RK4 stage).

## Finding: two scripted maneuvers flew below the ground

Before E1 nothing acted on an airplane below `down = 0`: `Maneuvers.fly` steps the simulation directly, so the D9d
crash check never ran. Measured on HEAD, `slow_flight` sank to −78 m (it stalls at 8.8 m/s and falls for the rest
of its 10 s) and `spin_right` to −55 m (the test window at 6 s was 44 m underground). With gear contacts the
ground pushed back and the spin test lost its autorotation (0.23 rad/s). Both maneuvers now start at 150 m
(`SLOW_FLIGHT.altitude`, read by `research/sensitivity/sensitivity.gd` too); air density is constant in the model,
so their physics is unchanged and `test_spin`, `test_envelope`, `test_handling` and the goldens pass as before.

## Finding for the model team

`ugly_stik_geometry.gd` places the main axle at x_aft 0.10 m, 2 cm **ahead** of the plan CG (0.1209 m). Built like
that, a tricycle Stik would sit on its tail. The physics keeps the D9d hull's 0.215 m (mains 0.094 m behind the CG)
and the test only checks track and heights against the table; the plan's gear position should be re-read.

## Known limits (next steps)

- No tangential force: a landed airplane slides without resistance and cannot taxi (E2: rolling friction,
  nosewheel steering).
- The ground is flat at 0 m and the start is still airborne (E3: runway start, takeoff, landing).
- Stiffness is bounded by the 240 Hz tick, not measured. A measured wire-gear stiffness that breaks the rule needs
  substeps for the contact or a finer tick.
- Wheel rotation for the renderer (`airplane.apply_gear`) is not fed yet; it needs the rolling speed from E2.
