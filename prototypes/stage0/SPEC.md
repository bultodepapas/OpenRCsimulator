# Stage 0 spec: hello, little airplane

One scene, built twice: in **three.js** ([three/](three/)) and in **Godot** ([godot/](godot/)). Both builds follow this spec exactly, so the comparison measures the tools rather than different scenes. Results go in [COMPARISON.md](COMPARISON.md). See [ROADMAP.md](../../ROADMAP.md) (Phase B) and [STACK.md](../../STACK.md).

No physics yet: the airplane follows a scripted circle.

## Frames and units

- **SI units** throughout.
- **World frame NED:** x north, y east, z down. The origin is on the ground at the pilot's feet.
- **Body frame FRD:** x forward, y right, z down. The attitude is given as Euler angles yaw ψ, pitch θ, roll φ (aerospace ZYX order).
- **Render frame** (both three.js and Godot: right-handed, Y up): `x = east`, `y = −down`, `z = −north`.
  - The model is authored in render axes: nose toward −z, right wing toward +x, wheels toward −y.
  - Conversion happens in **one function** per implementation: `R_render = M · R_ned · Mᵀ`, where `M` maps (N, E, D) to (x, y, z).

## Scripted motion

The airplane flies a level, coordinated right-hand circle in front of the pilot.

| Quantity | Value |
| --- | --- |
| Circle center | north 60 m, east 0, altitude 20 m |
| Radius R | 40 m |
| Speed V | 15 m/s |
| Angular rate ω | V / R = 0.375 rad/s, so one lap takes ≈ 16.76 s |
| Position at time t | N = 60 + R cos(ωt), E = R sin(ωt), D = −20 |
| Heading ψ | ωt + π/2 |
| Bank φ | atan(V² / (g R)) with g = 9.80665, ≈ 29.84° (right wing down) |
| Pitch θ | 0 |
| Propeller | spins about the body x axis at 10 rev/s (visual only, far slower than a real engine) |

## Airplane blockout (Das Ugly Stik 60)

Reference: the owner's plan images of **Das Ugly Stik 60** (Jensen kit, Phil Kraft design; RCM plan 939 is a related version). The Jensen plan prints **wing span 60 in, wing area 723 in², length 52 in, power .40–.61**, which gives span 1.524 m, area 0.466 m², mean chord 0.306 m (rectangular wing) and length 1.321 m. The Jensen plan shows a **nose gear** (tricycle). The RCM photos show the classic livery: red with white wingtip panels and a white fin/rudder.

Everything except span, chord and length is an **eyeballed proportion** for visuals only, not physics data. The black crosses of the classic livery are left out of the blockout.

All parts are boxes unless noted. Positions are part centers in model axes (meters; +x right, +y up, −z forward). The origin is roughly at the CG.

| Part (node name) | Size x × y × z | Center | Color |
| --- | --- | --- | --- |
| `fuselage` | 0.11 × 0.15 × 1.14 | (0, 0, 0.13) | red `#c8102e` |
| `cowl` | 0.10 × 0.13 × 0.08 | (0, 0, −0.48) | dark grey `#333333` |
| `wing_center` | 1.124 × 0.035 × 0.226 | (0, 0.03, 0.023) | top red `#c8102e`, bottom dark `#222222` |
| `wing_tip_left` / `wing_tip_right` | 0.20 × 0.035 × 0.226 | (∓0.662, 0.03, 0.023) | top white `#f2f2f2`, bottom dark `#222222` |
| `aileron_left` / `aileron_right` | 0.62 × 0.02 × 0.08 | (∓0.39, 0.03, 0.176) | red `#c8102e` |
| `stab` | 0.56 × 0.02 × 0.13 | (0, 0, 0.635) | red `#c8102e` |
| `elevator` | 0.56 × 0.02 × 0.07 | (0, 0, 0.735) | red `#c8102e` |
| `fin` | 0.02 × 0.17 × 0.14 | (0, 0.155, 0.63) | white `#f2f2f2` |
| `rudder` | 0.02 × 0.19 × 0.07 | (0, 0.165, 0.735) | white `#f2f2f2` |
| `nosewheel` | cylinder Ø 0.07, width 0.025 | (0, −0.19, −0.40) | black `#111111` |
| `gear_left` / `gear_right` | cylinder Ø 0.076, width 0.028 | (∓0.17, −0.19, 0.05) | black `#111111` |
| `propeller` | 0.305 × 0.025 × 0.01 | (0, 0, −0.54) | black `#111111` |

Ailerons, elevator and rudder pivot on their **leading edge** (the hinge line). The models put each surface under a pivot node there, ready for Stage 1 (ROADMAP B5). The underside of the wing is dark instead of the livery red, a deliberate **readability choice** so the pilot can tell top from bottom. It can be revisited.

## Scene

- **Ground:** a flat 2 km × 2 km grass plane `#4a7a32` with a mown runway strip `#6f9a4a`, 100 m × 12 m, running east–west and centered 15 m north of the pilot.
- **Sky:** a clear background `#9cc9ef`. Fog is optional, but if used it must match in both builds.
- **Lighting:** a sun from the south-west at 45° elevation, plus soft ambient/hemisphere light.
- **Camera (pilot view):** at the origin, eye height 1.7 m. It looks at the airplane every frame (head tracking, no lag). Vertical field of view 50°, near 0.1 m, far 3000 m.
- **Close-up camera (inspection):** fixed to the airplane at model offset (−1.2, 0.9, 2.0) m (left, above, behind), looking at the airplane origin with world up. Being attached to the airplane, it sees the surfaces the same way in every pose.

## Capture mode (for comparable evidence)

Each build supports a capture mode that:
1. sets simulation time to exactly **t = 3.0 s**,
2. renders one frame at **1280 × 720**,
3. saves a PNG, and
4. exits (or signals completion).

These screenshots are the side-by-side evidence.

## Done when

- The airplane circles visibly in a normal interactive run.
- The capture-mode PNG shows the airplane banked right, seen from the pilot position.
- Every number above appears in exactly one place in each implementation.

---

# Stage 1 spec: it answers the sticks (ROADMAP B5)

Stage 1 adds controls to the same scene. The airplane still follows the scripted circle (no physics yet); the controls move the **surfaces** and the **propeller speed**, and an on-screen panel shows the whole input path.

## Channels and keyboard (Mode 2 layout)

| Channel | Keys | Kind | Range |
| --- | --- | --- | --- |
| `roll` (aileron) | ← / → | self-centering | −1 … +1 (+1 = roll right) |
| `pitch` (elevator) | ↓ / ↑ (↓ = stick back = nose up) | self-centering | −1 … +1 (+1 = nose up) |
| `yaw` (rudder) | A / D | self-centering | −1 … +1 (+1 = yaw right) |
| `throttle` | W / S | holds its value | 0 … 1, starts at 0.5 |
| reset | R | action | — |
| view | C | action: toggle pilot / close-up camera | — |

## Input path (the same three stages in both builds)

1. **Raw:** what the keyboard says now. For each self-centering channel the raw target is −1, 0 or +1; both keys pressed gives 0. For throttle, raw is −1, 0 or +1 (decrease / hold / increase).
2. **Command:** the raw target passed through a **rate limiter**.
   - Self-centering channels move toward the target at **4.0 per second**, so full deflection takes 0.25 s and centering takes 0.25 s.
   - Throttle changes at **0.5 per second** while W/S is held and is clamped to 0…1.
   - The limiter is a pure function: `step(command, raw, dt) → command`. It never reads the keyboard or the clock itself.
3. **Surface angle:** command × max throw.

| Surface | Max throw | Positive command moves the trailing edge… |
| --- | --- | --- |
| right aileron | 20° | **up** (roll right) |
| left aileron | 20° | **down** (roll right) |
| elevator | 20° | **up** (nose up) |
| rudder | 25° | **right**, toward +x (yaw right) |

The throws are **estimates** (evidence kind `estimated`): the plan scans do not state them. Replace them when a measured or published value is found.

- The propeller spins at `propRevPerSec × throttle × 2` (10 rev/s at the starting throttle). Still visual only.
- **Reset (R):** scripted time back to 0, all commands to 0, throttle to 0.5.

## Panel

A small fixed overlay (top-left, monospace) with one row per channel: `raw`, `command` (2 decimals) and surface angle in degrees (1 decimal), plus throttle in %. It must be readable in the captures.

## Capture mode for Stage 1

Capture mode accepts fixed command values, so captures are deterministic without a keyboard: `roll=1 pitch=1 yaw=1 throttle=0.5` (in three.js as URL parameters, in Godot as user arguments). They are applied as **settled commands**, skipping the limiter. Each build saves:

- `capture-<build>-inspect-deflected.png`: close-up with roll = pitch = yaw = +1;
- the Stage 0 captures as before (all commands 0), now with the panel visible.

## Done when

- Unit tests prove:
  - the limiter reaches 0.5 after 0.125 s from 0 toward +1, reaches the target exactly without overshoot, and re-centers;
  - throttle holds and clamps;
  - surface signs are right: at roll +1, the right aileron's trailing edge is above its hinge and the left aileron's below; at pitch +1, the elevator's trailing edge is up; at yaw +1, the rudder's trailing edge is at +x.
- The deflected close-up capture shows those deflections, and the panel shows matching numbers.
