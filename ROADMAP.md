# Roadmap

Revised **2026-10-05** after a self-review of the first plan (weak points and fixes are [at the end](#review-weak-points-found-and-how-the-plan-fixes-them)). It builds on [RESEARCH.md](RESEARCH.md), [STACK.md](STACK.md) and [DECISIONS.md](DECISIONS.md).

**Be water, but on solid ground:** each step is small, has one objective proof, and leaves the project working. Steps go from basic to advanced; nothing advanced starts before its foundation is proven. If a step teaches us the route is wrong, we change the route and record why.

## Rules for every step

1. **One step = one small change** that can be reviewed in a few minutes and keeps the app working.
2. **Every step has a proof:** a passing test, a screenshot, a trace, or a measured number. "Looks fine" is not a proof.
3. **Known answers before unknown answers:** test the math and integrator against exact solutions before adding aerodynamics, whose answers we don't know.
4. **Guesses are labeled:** every parameter carries its source and evidence kind (`manual`, `borrowed`, `estimated`, `measured`).
5. **Gates are real stops:** at a gate we decide with the evidence collected, and record the decision.

## Where we are

- **Done (2026-10-05):**
  - **Foundations:** research, stack survey, MIT license, CI (local `act` + GitHub).
  - **Platform:** three.js vs Godot bake-off, then Gate 1 → **Godot 4.7**.
  - **Physics core (Phase C):** 64-bit math, rigid body, RK4, a 240 Hz fixed step that is bit-identical across frame rates, and a CSV flight trace.
  - **Aircraft data (D1):** Das Ugly Stik 60, with the CG and nose measured on the full-size plan.
  - **Visual model v1** (model team).

  Each step's proof is in its table row below; the lessons are in LEARNINGS.md.
- **State:** 130 physics/input checks + 449 model-contract checks, ~21 s for the full suite. The airplane **does not fly yet**: gravity only, no aerodynamics.
- **Next:** milestone **M1 "First flight"**, starting with D2 (air data). Plan review #2 (end of file) explains why the plan is now organized by playable milestones.

## Phase A — Ground base

The project foundation, before more code piles up.

| # | Step | Proof |
| --- | --- | --- |
| A1 | Choose and add a license ✅ **MIT** (owner decision, 2026-10-05) | `LICENSE` file; GitHub shows it after the next push |
| A2 ✅ | Repo hygiene: pin the Node version (`.nvmrc` + `engines`), add `.editorconfig` and `.gitignore` entries for `node_modules`, `dist` and `.godot`, and document dev commands in AGENTS.md | A clean clone + the documented commands reproduce the captures |
| A3 ✅ | CI on GitHub Actions: install, type check, tests, headless capture for both prototypes; screenshots uploaded as artifacts | ✅ Green locally (`act`) and on GitHub (run 37330100172, 41 s, 2026-10-05) |
| A4 ✅ | Working agreement: small commits; each commit message states its proof | Written in AGENTS.md |

## Phase B — Bake-off: the same small scene in three.js and Godot

| # | Step | Proof |
| --- | --- | --- |
| B1 | Shared Stage 0 spec ✅ | [SPEC.md](prototypes/stage0/SPEC.md) |
| B2 | three.js Stage 0 ✅ | `capture-three.png` (pilot view) and `capture-three-inspect.png` (close-up) |
| B3 ✅ | Godot 4.7 Stage 0 with the same capture mode (under Xvfb) | `app/captures/capture.png` and `capture-inspect.png` (formerly `capture-godot*.png`) |
| B4 ✅ | Frame-conversion tests in both: heading 0° puts the nose at −z; heading 90° puts it at +x; bank right puts the right wing down | Automated test passes in each build |
| B5 ✅ | Stage 1 in both: keyboard moves the surfaces through **rate-limited, self-centering** commands; an input panel shows raw → mapped values; a reset key | Captures of neutral and deflected surfaces; panel visible |
| B6 ✅ | Score both against the **criteria fixed in advance** ([COMPARISON.md](prototypes/stage0/COMPARISON.md)) | Filled comparison table |
| **Gate 1** ✅ | **Choose the platform.** No physics code before this gate, because the physics language follows the platform | ✅ **Godot** (owner's decision; scores three.js 73 / Godot 57), recorded in DECISIONS.md |
| B7 ✅ | Promote the winner into `app/`; keep the other build as an archived reference | ✅ `app/` with a float64 guard (verified to fail on a `Vector3` in `sim/`); tests and captures green |

## Phase C — Physics foundations (headless, no aerodynamics yet)

In GDScript, on 64-bit `float`s only. `app/test.sh` rejects `Vector3`/`Basis`/`Quaternion`/`Transform3D` in `sim/` and `physics/`.

| # | Step | Proof |
| --- | --- | --- |
| C1 ✅ | Float64 vector/quaternion helpers in `app/physics/` (plain floats or `PackedFloat64Array`, never `Vector3`). All trig goes through one module | Property tests: rotation preserves length; Euler ↔ quaternion round trip; composition. The guard stays green |
| C2 ✅ | Rigid-body state and its derivative: 6 degrees of freedom, full inertia tensor including `Ixz`, body-frame Euler equations | Unit tests on hand-computed derivatives |
| C3 ✅ | RK4 integrator with quaternion renormalization, plus a **GDScript performance check** | Free fall matches `½gt²` to 1e-9 m after 10 s. Torque-free spin conserves energy and angular momentum to 1e-6 relative over 60 s. **The integrator runs ≥ 20× faster than real time at 240 Hz** in GDScript; if not, the escape hatch is C++ GDExtension (DECISIONS) |
| C4 ✅ | Convergence check at steps `h`, `h/2`, `h/4` | Error ratio ≈ 16 per halving (fourth order) |
| C5 ✅ | Fixed-step loop: Godot's physics tick at 240 Hz (`_physics_process`) calls our integrator; cap catch-up steps; interpolate rendering; pause when the window loses focus | The same scripted inputs at 30, 60 and 144 fps rendering give the same final state |
| C6 ✅ | Replace the scripted circle with the rigid body under gravity only, plus reset | Visible: the airplane falls and resets. Trace matches C3 |
| C7 ✅ | **Flight trace export** (CSV: step, time, state, inputs, forces). The main debugging tool from now on | A trace file opens in a spreadsheet; columns carry units |

## Milestones from here: each one ends in a build the owner flies

Every milestone keeps the small-step rule (one proof per step) and ends with a **playtest build** that the owner downloads and flies on their own computer and radio. Notes from that session can reorder the next milestone.

### Predicted handling: targets the sim must reproduce

Computed by hand from the D1 data (`app/data/aircraft/jensen_ugly_stik_60.json`, 2.601 kg, 720 in², borrowed UltraStick25e aero). These are **predictions to check, not measurements**; a big miss means a bug or bad data, a small one is a tuning question.

| Quantity | Predicted | Notes |
| --- | --- | --- |
| Wing loading | 5.6 kg/m² (18.4 oz/ft²) | Normal for a .60 sport plane |
| Stall speed | 8.6–9.5 m/s (19–21 mph) | CLmax 1.0–1.2 (assumed) |
| Trim at 15 m/s | α 3.6°, CL 0.40, L/D 8.7, drag 2.9 N | |
| Best glide | L/D 11.5 at 10.8 m/s | |
| Full aileron (±20°) steady roll rate | 144°/s at 15 m/s, 192°/s at 20 m/s | from Clδa, Clp |
| Static margin at the plan CG | 15.8 % MAC | borrowed Cmα / CLα |

### M1 — First flight (owner flies the Ugly Stik with keyboard or radio)

| # | Step | Proof |
| --- | --- | --- |
| D1 ✅ | Aircraft data file v0 (Das Ugly Stik 60): plan geometry, plan CG, inventory mass and inertia, borrowed aero with conventions, a validating loader | 30 checks, including 12 broken-data cases; the app refuses to fly on invalid data |
| D2 | Air data: air-relative velocity, α, β, dynamic pressure; **safe at zero and very low airspeed** (no NaN, no divide-by-zero) | Hand-computed values; V → 0 stays finite |
| D3 | **Full linear aero model, all six axes in one function** (the coefficients already exist), plus the mapping from our command conventions to the data's surface conventions (elevator +TE down, rudder +TE left…) | Hand-computed loads at three states. Sign tests: +pitch command → nose-up moment, +roll → right roll, +yaw → nose right, sideslip → weathervane, rates → damping. A power-off glide trace shows L/D ≈ 8.7 at 15 m/s |
| D4 | Trim solver (α, elevator, throttle) at a requested speed; failure is reported, never hidden | 15 m/s trims at α 3.6° ± 0.5°; an impossible request fails visibly |
| D5 | Thrust v0: static thrust from the APC 12×6 data at a labeled rpm, falling with airspeed, first-order lag; **placeholder engine sound** whose pitch follows throttle | Level flight holds ±1 m for 30 s at trim; climb at full throttle is plausible; sound changes with throttle |
| D6 | Flying from an air start at trim, with keyboard **and radio/gamepad raw axes**: channel mapping, center/endpoint calibration and inversion saved to `user://`, no deadzone (former F1 + F2, moved up because the owner has EdgeTX radios) | End-to-end test with injected joystick events; owner flies with the radio |
| D7 | Pilot aids: **ground shadow** (the main height cue in RC), textured grass, HUD (airspeed, altitude, α), performance overlay (fps, physics µs/step), view zoom key | Captures show the shadow; perf overlay numbers recorded on the owner's machine |
| D8 | Handling check against the predictions table: scripted roll, glide and slow-flight maneuvers through the real loop | Each predicted number reproduced within its band, recorded from traces |
| D9 | Crude stall (lift cap + drag rise) and ground hit → crash → reset | High-α trace stays finite; recovery possible; crashing at any attitude resets cleanly |
| PT1 | **Playtest kit v0.1:** Windows, Linux and macOS exports built by CI on a git tag (cached export templates, only these platforms), published as a GitHub release. macOS is unsigned: first launch via right-click → Open | The owner downloads, runs and flies it on each OS |
| **Gate 2** | **"Is it flyable, readable and fun?"** The owner (and ideally 1–2 RC pilots) fly v0.1: readability at distance, feel versus a real Stik, radio setup friction, frame time | Notes recorded; M2 reordered if needed |
| D10 | Sensitivity sweep (mass, CG, Cmα, CD0, inertia ±20 %) on the D8 maneuvers | A table ranking which unknowns matter; decides what to measure next |

### M2 — Takeoff and landing

| # | Step | Proof |
| --- | --- | --- |
| E1 | Tricycle gear contact points as spring-dampers; stiffness from a natural-frequency rule (`ω·dt < 0.1`) | Drop test: no energy gain; agrees across `h` and `h/2` |
| E2 | Rolling friction (labeled guess), nosewheel steering, brakes off | Taxi a figure-eight |
| E3 | Start on the runway: takeoff, circuit, landing, nose-over | Trace of a full circuit |
| E4 | **Golden flights:** record the inputs of a flight, replay them, and compare the traces within tolerance; this becomes the regression test for every later physics change | A replayed circuit matches its recording; a deliberate physics change is detected |
| PT2 | Playtest v0.2 | Owner flies takeoffs and landings |

### M3 — The radio, done properly

| # | Step | Proof |
| --- | --- | --- |
| F3 | Disconnect and focus-loss policy: visible pause; resuming needs an explicit action and low throttle | Scripted unplug/replug log |
| F4 | Compatibility table: device, firmware, OS, Godot version, usable channels | One row per tested device |
| F5 | Setup screen: pick device, move sticks to assign channels, see raw → mapped live | Owner sets up a new radio without editing files |

### M4 — Nitro

| # | Step | Proof |
| --- | --- | --- |
| G1 | APC 12×6 propeller table ingestion with interpolation; out-of-range queries flagged | Tests against the file's own rows |
| G2 | Engine rpm model: stopped/running, throttle → target rpm, lag, idle; shaft dynamics (`I·dω/dt = Q_engine − Q_prop`) | Throttle-step trace; all assumed numbers labeled |
| G3 | Engine sound driven by simulated rpm (replaces the D5 placeholder) | A recording or owner check |
| G4 | (Optional) fuel mass and CG shift | Trim drift trace over a tank |
| PT4 | Playtest v0.4 | Owner judges throttle response and sound |

### M5 — Air and polish

Chosen by what the playtests ask for:
- wind, then gusts
- propwash on the tail (matters for Stik takeoffs and rudder authority)
- stall hysteresis and a post-stall extension
- ground effect
- camera options
- settings persistence
- pilot observation sessions
- web export, if wanted

## Research tracks

Each track is time-boxed and attached to the step that needs it:

| Track | Needed by | Time box |
| --- | --- | --- |
| Das Ugly Stik 60 data: plan CG ✅ and nose ✅ measured; still open: control throws, tail areas/arm, airfoil, a weighed build | D8, D10 | 1–2 sessions |
| APC 12×6 data at a realistic .61 rpm (static thrust for D5) | D5, G1 | 1 session |
| Which transmitter/gamepad the owner has | D6 | ✅ Owner has EdgeTX/OpenTX and other RC radios plus a gamepad; keyboard during development |
| Pilot observation sessions | Gate 2 | After PT1 |
| Real-Stik handling references (roll rate, stall speed, glide) from pilots or videos, to check the predicted-handling table | D8 | 1 session |
| Owner's flying computer for the playtest builds | PT1 | ✅ Windows, Linux and macOS |
| License compatibility for bundled data (UIUC "GPL'd data") | Before bundling any airfoil data | 1 session |

## Review: weak points found and how the plan fixes them

Self-review of the first roadmap, 2026-10-05. Items marked *measured* come from running the three.js Stage 0 build.

| # | Weak point | Why it matters | Fix in this plan |
| --- | --- | --- | --- |
| 1 | **Public repo, no license** | Nobody may legally reuse or contribute; contradicts "open source" | A1, first step |
| 2 | Stages were too big (old Stage 2 bundled integrator, loop, aero, thrust, stall, data and tests) | Big steps hide which change broke what | Split into C1–C7 and D1–D10 |
| 3 | Physics language depended on an undecided platform | Physics written in TS would not run inside Godot | Gate 1 before any physics code |
| 4 | No known-answer tests before aerodynamics | Integrator bugs would masquerade as "aircraft behavior" | Phase C: free fall, torque-free spin, convergence order |
| 5 | Borrowed 25e derivatives with .60 geometry may not trim | The airplane could be unflyable for reasons unrelated to code | D4 trim solver + stability sign checks; D10 sensitivity |
| 6 | Inertia of the .60 is unknown | Roll/pitch response depends on it | D1 labeled estimate; D10 tells us whether it matters |
| 7 | *Measured:* the airplane is ~15 px wide at 87 m in the pilot view; a pilot-view screenshot cannot verify geometry | Readability is a core RC problem, and checks need a close-up | Close-up capture added (B2); readability check in Gate 2 |
| 8 | Keyboard is on/off; full deflection instantly is unflyable | First flights would feel broken | B5: rate-limited, self-centering commands |
| 9 | Flat untextured ground gives no height or speed cues | Landing and altitude judgment impossible | D7 adds ground texture and horizon cues |
| 10 | The flight trace was planned late (old Stage 6) | Physics bugs are hard to see without data | Moved to C7, before aerodynamics |
| 11 | Stiff gear springs can go numerically unstable | Bouncing or exploding landings | E1 stiffness from a natural-frequency rule |
| 12 | Transmitter hardware availability unknown | Phase F could be blocked | Ask the owner now |
| 13 | Bake-off bias: criteria could be chosen after seeing results; the same AI writes both builds | An unfair comparison wastes the bake-off | Criteria fixed in COMPARISON.md before the Godot build |
| 14 | This machine renders in software (no GPU) | Performance numbers here do not represent real machines | Performance judged on the owner's real hardware |
| 15 | Research tracks had no owner or time box | Research can grow without end | Each track attached to a step, time-boxed |
| 16 | No CI | "Works on my machine" drift; no shared evidence | A3 |

## Plan review #2 (2026-10-05): from infrastructure to a game

Measured state before this review: 25 commits in one day; Phases A–C and D1 done; full suite 21 s, green. **The airplane has never flown, and the owner has never received a build.** Changes and why:

| # | Finding (evidence) | Change |
| --- | --- | --- |
| 1 | Nothing playable exists: no export presets, no release; all runs were headless on a VM with no GPU | **Milestones end in playtest builds** (PT1 = v0.1 after first flight), built by CI on a tag |
| 2 | Steps were all foundations; the first thing a player feels (flight) was eight steps away | M1 compresses aero into **one full six-axis step (D3)**: the D1 coefficients already exist, and sign tests guard each axis. The small-step rule still holds |
| 3 | Radio input sat in Phase F, after ground handling, although the owner owns EdgeTX radios and keyboard flying is not RC flying | Raw joystick input and calibration **moved into M1 (D6)** |
| 4 | Height judgment needs a shadow; the pilot view showed a ~15 px airplane at 87 m | **Ground shadow, HUD, zoom and perf overlay in M1 (D7)** |
| 5 | No numbers said what "flies like a Stik" means | **Predicted-handling table** from the D1 data; D8 checks the sim against it |
| 6 | Generated captures and traces are committed: 65 PNG/CSV changes in 25 commits | ✅ `app/captures/` untracked (`.gitignore` + `git rm --cached`, files kept on disk); CI artifacts only; deliberate golden references only |
| 7 | No regression test for "feel" once physics evolves | **Golden flights (E4):** record inputs, replay, compare traces |
| 8 | Performance only measured on a software-rendering VM | Perf overlay (D7) and frame-time notes at every playtest |
| 9 | Visual model nose ≈ 1.85× the plan (found by the D1 hand balance) | Reported to the model team; physics is unaffected (it uses the plan CG and LE) |
| 10 | Godot `.uid` files will appear once anyone opens the editor | Commit them when they appear (Godot's recommendation); don't delete |
