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

- **Done:** research (RESEARCH.md), stack survey (STACK.md), the Stage 0 spec ([prototypes/stage0/SPEC.md](prototypes/stage0/SPEC.md)), and the **three.js Stage 0 build**, with pilot-view and close-up captures.
- **Done since:** Phase A (MIT license, repo hygiene, CI green locally), B3 (Godot Stage 0, matching the three.js build), B4 (frame tests in both; a deliberately broken sign is caught).
- **Done since:** B5 (Stage 1 controls in both, with unit and end-to-end input tests; CI green) and B6 (scored: **three.js 73, Godot 57 of 80**, see COMPARISON.md).
- **Next:** **Gate 1**: the owner confirms the platform; then B7 promotes the winner into `app/`.

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
| B3 ✅ | Godot 4.7 Stage 0 with the same capture mode (under Xvfb) | `capture-godot.png` and `capture-godot-inspect.png` |
| B4 ✅ | Frame-conversion tests in both: heading 0° puts the nose at −z; heading 90° puts it at +x; bank right puts the right wing down | Automated test passes in each build |
| B5 ✅ | Stage 1 in both: keyboard moves the surfaces through **rate-limited, self-centering** commands; an input panel shows raw → mapped values; a reset key | Captures of neutral and deflected surfaces; panel visible |
| B6 ✅ | Score both against the **criteria fixed in advance** ([COMPARISON.md](prototypes/stage0/COMPARISON.md)) | Filled comparison table |
| **Gate 1** | **Choose the platform.** No physics code before this gate, because the physics language follows the platform | Decision recorded in DECISIONS.md |
| B7 | Promote the winner into `app/`; keep the other build as an archived reference | `app/` builds and captures in CI |

## Phase C — Physics foundations (headless, no aerodynamics yet)

| # | Step | Proof |
| --- | --- | --- |
| C1 | Float64 vector/quaternion module. All trig goes through one `math` module | Property tests: rotation preserves length; Euler ↔ quaternion round trip; composition |
| C2 | Rigid-body state and its derivative: 6 degrees of freedom, full inertia tensor including `Ixz`, body-frame Euler equations | Unit tests on hand-computed derivatives |
| C3 | RK4 integrator with quaternion renormalization | Free fall matches `½gt²` to 1e-9 m after 10 s. Torque-free spin conserves energy and angular momentum to 1e-6 relative over 60 s |
| C4 | Convergence check at steps `h`, `h/2`, `h/4` | Error ratio ≈ 16 per halving (fourth order) |
| C5 | Fixed-step loop: accumulator, cap on catch-up steps, render interpolation, pause when the tab is hidden | The same scripted inputs at 30, 60 and 144 fps rendering give the same final state |
| C6 | Replace the scripted circle with the rigid body under gravity only, plus reset | Visible: the airplane falls and resets. Trace matches C3 |
| C7 | **Flight trace export** (CSV: step, time, state, inputs, forces). The main debugging tool from now on | A trace file opens in a spreadsheet; columns carry units |

## Phase D — First flight, in thin slices

| # | Step | Proof |
| --- | --- | --- |
| D1 | Aircraft data file v0 (Das Ugly Stik 60): plan geometry (60 in span, 723 in², 52 in) and a labeled mass estimate; inertia **estimated** from a component inventory; derivatives `borrowed` from the UltraStick25e; provenance per value; a loader that checks units, ranges and required fields | Loader tests, including deliberately broken files |
| D2 | Air data: air-relative velocity, α, β, dynamic pressure (wind = 0) | Unit tests with hand-computed values |
| D3 | Longitudinal forces only: lift `CL0 + CLα·α`, drag `CD0 + k·CL²`, weight | Power-off glide ratio in the trace equals `CL/CD` from the data |
| D4 | Pitch moment (`Cm0`, `Cmα`, `Cmq`, `Cmδe`); stability sign check (`Cmα < 0`); **trim solver** for level flight at 15 m/s | Trim found with surfaces within limits, *or* a clear failure message naming what to change (CG, `Cm0`) |
| D5 | Thrust v0: throttle × estimated static thrust, with a first-order lag | Level flight holds altitude within ±1 m for 30 s at trim |
| D6 | Lateral-directional derivatives (`CYβ`, `Clβ`, `Clp`, `Clδa`, `Cnβ`, `Cnr`, `Cnδr`), with sign checks | Right aileron step rolls right; a sideslip disturbance damps out |
| D7 | Interactive flight from an air start at trim. Textured ground and horizon for height cues. Debug HUD (airspeed, altitude, α) | Owner flies 2 minutes with no numerical blow-up; trace saved |
| D8 | Crude stall: lift cap plus drag rise above the stall angle | A high-α trace stays finite; recovery is possible |
| D9 | Ground-hit detection → crash → reset (no landing gear yet) | Crashing at any attitude resets cleanly |
| D10 | Sensitivity sweep: mass, CG, `Cmα`, `CD0` at ±20% | A table ranking which unknowns matter. It decides what to research or measure next |
| **Gate 2** | **"Is it flyable and readable?"** The owner (and ideally 1–2 RC pilots) fly it. Includes the pilot-view readability check (the airplane was only ~15 px at 87 m in B2) | Notes recorded; the next phases reordered if needed |

## Phase E — Ground handling

| # | Step | Proof |
| --- | --- | --- |
| E1 | Tricycle landing-gear contact points (nose gear, per the Jensen plan) as spring-dampers. Stiffness is chosen from a natural-frequency rule (`ω·dt < 0.1`), not tuned by feel | Drop test: no energy gain; results agree across `h` and `h/2` |
| E2 | Rolling friction (labeled as a guess) and nosewheel steering | Taxi a figure-eight |
| E3 | Start on the runway: takeoff, landing, nose-over | Trace of a full circuit, from takeoff to landing |

## Phase F — Real transmitter

| # | Step | Proof |
| --- | --- | --- |
| F1 | Raw input inspector: all axes and buttons, update rate, reconnect | Screenshot with the owner's EdgeTX radio and gamepad |
| F2 | Mapping and calibration (center, endpoints, inversion), saved and exportable | Survives a restart |
| F3 | Disconnect and focus-loss policy: visible pause; resuming needs an explicit action | Scripted unplug/replug log |
| F4 | Compatibility table: device, firmware, OS, browser/engine, usable channels | One row per tested device |

## Phase G — Nitro

| # | Step | Proof |
| --- | --- | --- |
| G1 | APC 12×6 propeller table ingestion with interpolation; out-of-range queries flagged | Tests against the file's own rows |
| G2 | Engine rpm model: stopped/running, throttle → target rpm, lag, idle; shaft dynamics (`I·dω/dt = Q_engine − Q_prop`) | Throttle-step trace; all assumed numbers labeled |
| G3 | Engine sound driven by rpm | A recording or user check |
| G4 | (Optional) fuel mass and CG shift | Trim drift trace over a tank |

## Phase H — Better air and polish

Chosen by what Gate 2 and playtests ask for:
- wind, then gusts
- stall hysteresis
- propwash on the tail
- ground effect
- replay
- camera zoom options
- pilot observation sessions
- installable app (PWA or Electron)

## Research tracks

Each track is time-boxed and attached to the step that needs it:

| Track | Needed by | Time box |
| --- | --- | --- |
| Das Ugly Stik 60 data: published weight/CG/throws, plan dimensions (tail, gear, airfoil), component mass inventory | D1 | 1–2 sessions |
| APC 12×6 predicted-load plot | G1 | 1 session |
| Which transmitter/gamepad the owner has | F1 | ✅ Owner has EdgeTX/OpenTX and other RC radios plus a gamepad; keyboard during development |
| Pilot observation sessions | Gate 2 | After D7 |
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
