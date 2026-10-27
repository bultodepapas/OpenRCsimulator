# Native simulation kernel: scoping, 2026-10-27

Research only; no code. The owner asked to scope a native (GDExtension, godot-cpp) port of
the simulation tick. This record summarizes a read-only scout pass over the repository's own
native evidence and outside sources; key citations were spot-checked. It is the input for a
plan once the owner decisions below are taken. Ranked context:
[optimization scan](godot-optimization-scan-2026-10-27.md) item 10.

## What a port would cover

- Kernel: `Simulation.step` (`app/sim/simulation.gd`), its stage closures and RK4.
- Fixed-wing callbacks installed by the session (`flight_session.gd` `_commit_aircraft`) and
  the propulsion routes of `aircraft_propulsion_runtime.gd` (glow step policy, liquid fuel
  event, turbine, electric battery, split/coupled shaft).
- The default stage `_wheel_evaluate`: aero/propulsion/slipstream/swirl/spatial wind,
  `_ground_evaluation` (gear, wheels, terrain, hull, lake) and wash transport; once per tick
  `_pre_step` (servos, shaft, anchors, failures, turbulence from Godot's PCG RNG) and the
  post-tick collision query.
- Size: about 20.2k GDScript lines in 67 files reach these modules (some cold); the truck
  precedent shrank 2,249 GDScript lines to about 1,760 C++. Estimate 6–9k C++ lines for the
  Stik route and 15–20k for the fleet (low confidence).
- Stays in GDScript: session orchestration, checkpoint envelopes, recorder/trace/`.orfl`,
  failures, presentation observers, aircraft validation, and the complete reference
  evaluator, which [STACK](../STACK.md#boundaries-and-data-flow) requires.

## Interface options and expected gains

| Option | Repository evidence | Whole-tick effect | Limit |
| --- | --- | --- | --- |
| (a) Per-function helpers | Slipstream 17× on the component, P-51 tick −29–39% ([Gate P](simulation-state/Gate-P/README.md)) | ≈ 1.3–1.6× | Dictionary decoding 32–39% of the native method; GDScript glue remains |
| (b) Stage evaluator on a prepared model handle (4–8 calls per tick) | Prepared input decoding 0.5–0.6 µs per call; truck evaluator 5–8× but tick 2.8× ([RCV-runtime](rc-monster-truck/RCV-runtime/README.md)) | ≤ ≈ 2× | Pre-step, collision, validation and callback glue stay in GDScript |
| (c) Whole tick, one call | Not measured | ≈ 4–8× on the kernel (inferred) | Not allowed today: SF-08 permits one evaluator boundary, never the tick ([DECISIONS 2026-10-15](../DECISIONS.md)) |
| (d) (c) plus native terrain, lake and scenery queries | Truck lake sampler native and bit-exact on Linux and Windows | Removes per-stage environment callbacks | Needs an environment snapshot owned by the landscape/lake/scenery tracks |

None of these touches the presentation observers, which took about a third of main-thread
CPU in flight before GP-19f/UI-FS-08-R1. Release templates already run the tick 1.5–1.9×
faster than the debug binary used for most measurements.

## Determinism and goldens

- Linux on one host: GDScript rounds once per operation; C++ with `-ffp-contract=off`, SSE2,
  the same grouping and glibc libm reproduces it. Precedents: Gate P 32/32 exact 960-tick
  fingerprints; E0b6p 296/297 exact.
- [NK-1](../../research/native-math-spike/README.md) (Linux, 2026-10-27): `std::` and godot-cpp
  `UtilityFunctions` both return GDScript's bits for 16 functions over 10⁶ inputs each, because
  extension and engine call the same glibc symbols in one process. A port must route
  transcendentals through one shim that copies the engine's `asin`/`acos` clamp and keeps literal
  `pow` exponents out of constant folding: GCC turns `pow(x, 2.0)` into `x * x`, 1 ulp off in
  0.085% of cases.
- Windows: official Godot builds use MinGW while the repository's native modules use MSVC
  `/fp:strict`, so transcendental results can differ; the truck parity harness uses a
  tolerance. Calling the engine's math through godot-cpp utility functions, or building with
  Godot's MinGW toolchain, might restore identity (unverified).
- macOS arm64: different libm and possible FMA contraction; no native run exists.
- Handling proposed: keep the tolerance goldens shared by both backends; require
  fingerprint equality native vs reference on Linux (and Windows if the math spike passes);
  pin the backend in checkpoints; treat cross-backend `.orfl` replays as candidates.

## Build and delivery

Reuse the truck pattern: pinned toolchain (godot-cpp 10.0.0, SCons), `build.py` with
receipts, installation into the ignored `app/native/`, native CI jobs feeding export. This
checkout has no `app/native`, so the truck runs its reference path here. macOS exports
exclude native code today; a native macOS build needs universal slices, signing with library
validation disabled, and CI that does not exist. The reference path stays mandatory, so
players without the library keep the current tick cost.

## Phases (R research, I implementation)

| Step | Type | Work | Gate | Effort |
| --- | --- | --- | --- | --- |
| NK-0 | R | Release-template timing on the target host, observers on/off | p50/p95 still above the 500 µs Gate P on representative aircraft | 1–2 d; dev-VM run done: [release ×1.2, ≈ 1.0 ms airborne, 2.2 ms runway](visual-quality-implementation/VQ-01c/release-tick-2026-10-27/README.md); target host pending |
| NK-1 | R | Math identity spike: engine utility functions vs `std::` vs GDScript, 10⁶ inputs per function, Linux and Windows | Per-platform identity table and call cost | 2 d + Windows host; Linux done: [16 functions bit-identical by both routes](../../research/native-math-spike/README.md), Windows pending |
| NK-2 | I (GDScript) | Immutable prepared model with a revision boundary (load, edit, reload, restore, Workshop) | Fleet fingerprints unchanged | 3–5 d; first slice [NK-2a](native-kernel/NK-2a/README.md): per-tick capability memo |
| NK-3 | I | Option (b) for the Stik route | ≥ 10k exact oracle states incl. malformed inputs; exact 960-tick fingerprints; suite on a native copy | 2–3 wk |
| NK-4 | Decision | Stop if Gate P is met | — | — |
| NK-5 | I | Option (c) after an SF-08 amendment; unported laws fall back to the reference | As NK-3 | 2–3 wk |
| NK-6 | I | Native terrain, lake (reuse the truck sampler), hull and scenery queries | Exact per-query oracles | 1–2 wk |
| NK-7 | I | Glow, battery, turbine, liquid-fuel routes; P-51, Extra, Avanti | Fleet fingerprints | 4–8 wk |
| NK-8 | I | Platform builds, CI, packaged smoke, per-platform tolerance checks | Release timing on target hardware | 1–2 wk + hardware |

A Stik-only port is about 5–7 weeks; the fleet about 3–5 person-months (low confidence).
Risks: two copies of about 20k actively edited lines (mitigation: the native side refuses
unknown law identities), smaller gains in release builds, Windows libm mismatch, Godot beta
API churn.

## Owner decisions

D1 accept NK-0 as the porting trigger; D2 amend SF-08 for a whole-tick port; D3
determinism tier (Linux-exact only, or Windows too, on which toolchain); D4 cross-backend
checkpoint/replay policy; D5 macOS native or reference only, and who builds and signs; D6
maintenance rule for tracks changing ported laws; D7 first route (Stik or P-51 worst case);
D8 whether the slow reference path is acceptable for players without the library.

Decided 2026-10-27 (owner delegated: "do it, test, polish, optimize"): D1 port now; D2 no
amendment, option (b); D3 Linux bit-exact, Windows tolerance-tier through `UtilityFunctions`
until proven; D4 backend identity pinned, cross-backend replays are candidates; D5 macOS
reference-only; D6 the native side refuses unknown law identities; D7 electric Stik first;
D8 yes. [DECISIONS](../DECISIONS.md) holds the row.
