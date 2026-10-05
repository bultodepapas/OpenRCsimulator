# Stage 0/1 bake-off: three.js vs Godot

Both builds implement the same [SPEC.md](SPEC.md). **The criteria and weights below were fixed before the Godot build started**, so results cannot reshape them. Context and options are in [STACK.md](../../STACK.md).

## Criteria (fixed 2026-10-05, before Godot results)

| # | Criterion | Weight | How it is measured |
| --- | --- | --- | --- |
| 1 | Float64 physics ergonomics | 3 | Can the scripted pose and a future 6-DoF state be written in 64-bit math naturally? |
| 2 | Automated evidence | 3 | Headless capture, unit tests and CI with documented commands; count the manual steps |
| 3 | Edit → see loop | 2 | Seconds from saving a change to seeing it |
| 4 | Clean setup | 2 | Time and steps from a clean clone to a first capture |
| 5 | Transmitter input path | 2 | Documented path for raw joystick axes; tested on hardware when available |
| 6 | Distribution | 1 | Download size, install needs, platforms |
| 7 | Readability for humans and AI | 1 | Lines of code; can the scene be understood from text files? |
| 8 | Stage 1 effort | 2 | Time to add controls, panel and reset (filled at B5) |

**Score:** 1–5 per criterion × weight. A gap under 10% of the total counts as a tie. On a tie, pick the route that makes the **next** step (physics, Phase C) easiest. Hard requirement: both must produce captures without a person clicking.

**Caveats:** both builds are written by the same AI assistant. This machine has no GPU (software rendering via SwiftShader / Mesa llvmpipe), so performance is judged later on the owner's hardware.

## three.js results (B2)

| Measure | Value |
| --- | --- |
| Versions | three 0.186.1, Vite 8.3.2, TypeScript 7.0.2, Playwright 1.63.0, Node 24.19 |
| Wall time, spec → both captures | ~3 min 4 s (14:44:16 → 14:47:20 UTC), including writing the code |
| Install (`npm install`, pinned) | 13 s |
| Type check (`tsc --noEmit`) | 0.5 s |
| Build + headless capture (`npm run capture`) | 1.6 s |
| Bundle | 534 KB JS, 132 KB gzip (one chunk; Vite warns > 500 KB) |
| Source | 5 TypeScript files, ~250 lines |
| Manual steps | 0 |
| Unit tests (B4) | 8 Vitest tests, 0.8 s; a deliberately broken axis sign is caught (2 failures) |
| CI (A3), local `act` run | Green. `npm ci` 5 s, tests and capture ~2 s; installing Playwright's Chromium takes 1 min 32 s (cacheable later) |
| Problems hit | None blocking. The pilot view shows the airplane at only ~15 px, so a close-up capture was added for geometry checks |
| Float64 | Native: JS numbers are 64-bit; the scripted pose has no renderer imports |
| Edit loop, measured | Switching the model to Das Ugly Stik 60 (12 parts, new wing-panel type) took 30 s, from spec update to type check and both captures (14:50:30 → 14:51:00 UTC). One file changed for numbers, one for the new wing-panel loop |

## Godot results (B3)

| Measure | Value |
| --- | --- |
| Versions | Godot 4.7.2 official, Compatibility renderer (OpenGL 3 / WebGL 2 class), GDScript |
| Get the engine | `get-godot.sh`: 78 MB download, SHA-512 verified, 146 MB single binary, 9 s. No install, no editor opened |
| Wall time, spec → both captures | 1 min 26 s (14:53:05 → 14:54:31 UTC). **Biased low:** written second, reusing the proven three.js structure |
| Headless capture (`capture.sh`) | 1.3 s for both captures, under Xvfb with Mesa llvmpipe (OpenGL 4.5) |
| Unit tests (B4) | 15 headless checks, 0.2 s, no add-on (`extends SceneTree` script); the broken axis sign is caught (2 failures, exit code 1) |
| Source | 6 GDScript files + project + scene, ~307 lines (three.js: ~291 incl. HTML and capture script) |
| Manual steps | 0 |
| Visual parity | Same position, attitude and framing as three.js in both captures; lighting differs slightly (brighter grass, per-pixel shading) |
| Float64 | GDScript `float` is 64-bit, but `Vector3`/`Basis` are 32-bit. The sim keeps positions as arrays of floats; tests at the render boundary need a 1e-6 tolerance. Works, but needs discipline |
| Problems hit | (1) A clean Ubuntu container lacks X11 libraries (`libXcursor`…), so CI must install them; caught by the local CI run. (2) `BoxMesh` takes one material, so each wing panel is two half-thickness boxes. (3) No audio device in the VM; solved with `--audio-driver Dummy` |
| CI (A3), local `act` run | Green. apt dependencies 30 s, Godot binary cached, tests + capture ~13 s |
| Web export size | Not measured yet (needs the export templates download); documented ~42 MB default, see STACK.md |

## Scores

*Filled at B6, after Stage 1 in both.*
