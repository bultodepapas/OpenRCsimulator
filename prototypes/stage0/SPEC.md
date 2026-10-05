# Stage 0 spec: hello, little airplane

One scene, built twice: in **three.js** ([three/](three/)) and in **Godot** ([godot/](godot/)). Both builds follow this spec exactly, so the comparison measures the tools rather than different scenes. Results go in [COMPARISON.md](COMPARISON.md). See [ROADMAP.md](../../ROADMAP.md) (Stage 0) and [STACK.md](../../STACK.md).

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

## Airplane blockout (Ultra Stick .60 style)

Span and length come from the Hangar 9 Ultra Stick .60 manual (66 in, 55 in). Everything else is an **eyeballed proportion** for visuals only, not physics data.

All parts are boxes unless noted. Positions are part centers in model axes (meters; +x right, +y up, −z forward). The origin is roughly at the CG.

| Part (node name) | Size x × y × z | Center | Color |
| --- | --- | --- | --- |
| `fuselage` | 0.14 × 0.16 × 1.20 | (0, 0, 0.10) | white `#f2f2f2` |
| `cowl` | 0.13 × 0.14 × 0.12 | (0, 0, −0.56) | dark grey `#333333` |
| `wing` (fixed part) | 1.676 × 0.04 × 0.27 | (0, 0.10, −0.03) | top yellow `#ffcc00`, bottom dark blue `#1a2a6c` |
| `aileron_left` / `aileron_right` | 0.60 × 0.02 × 0.08 | (∓0.50, 0.10, 0.145) | red `#d01c1c` |
| `stab` | 0.60 × 0.02 × 0.14 | (0, 0.02, 0.61) | yellow `#ffcc00` |
| `elevator` | 0.60 × 0.02 × 0.07 | (0, 0.02, 0.715) | red `#d01c1c` |
| `fin` | 0.02 × 0.18 × 0.16 | (0, 0.12, 0.62) | yellow `#ffcc00` |
| `rudder` | 0.02 × 0.20 × 0.07 | (0, 0.13, 0.735) | red `#d01c1c` |
| `gear_left` / `gear_right` | wheel: cylinder Ø 0.09, width 0.03 | (∓0.18, −0.22, −0.28) | black `#111111` |
| `tailwheel` | cylinder Ø 0.04, width 0.015 | (0, −0.10, 0.68) | black `#111111` |
| `propeller` | 0.305 × 0.025 × 0.01 | (0, 0, −0.63) | black `#111111` |

Ailerons, elevator and rudder pivot on their **leading edge** (the hinge line). The models put each surface under a pivot node there, ready for Stage 1. The bottom of the wing is a different color so the pilot can tell top from bottom.

## Scene

- **Ground:** a flat 2 km × 2 km grass plane `#4a7a32` with a mown runway strip `#6f9a4a`, 100 m × 12 m, running east–west and centered 15 m north of the pilot.
- **Sky:** a clear background `#9cc9ef`. Fog is optional, but if used it must match in both builds.
- **Lighting:** a sun from the south-west at 45° elevation, plus soft ambient/hemisphere light.
- **Camera (pilot view):** at the origin, eye height 1.7 m. It looks at the airplane every frame (head tracking, no lag). Vertical field of view 50°, near 0.1 m, far 3000 m.

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
