# Roadmap

Revised **2026-10-05** after three reviews (the second, "from infrastructure to a game", and the third, a senior review before D6, are at the end) of the first plan (weak points and fixes are [at the end](#review-weak-points-found-and-how-the-plan-fixes-them)). It builds on [RESEARCH.md](RESEARCH.md), [STACK.md](STACK.md) and [DECISIONS.md](DECISIONS.md).

**Be water, but on solid ground:** each step is small, has one objective proof, and leaves the project working. Steps go from basic to advanced; nothing advanced starts before its foundation is proven. If a step teaches us the route is wrong, we change the route and record why.

## Rules for every step

1. **One step = one small change** that can be reviewed in a few minutes and keeps the app working.
2. **Every step has a proof:** a passing test, a screenshot, a trace, or a measured number. "Looks fine" is not a proof.
3. **Known answers before unknown answers:** test the math and integrator against exact solutions before adding aerodynamics, whose answers we don't know.
4. **Guesses are labeled:** every parameter carries its source and evidence kind (`manual`, `borrowed`, `estimated`, `measured`).
5. **Gates are real stops:** at a gate we decide with the evidence collected, and record the decision.
6. **Verification is not validation.** A check against numbers computed from our own data proves the code; only independent data (flight tests, real-airplane measurements, pilots) proves realism. Each physics milestone needs at least one of each.
7. **Budgets are measured:** physics ≤ 0.5 ms per 240 Hz tick (≤ 2 ms per 60 fps frame) on the owner's slowest machine. Every aero step reports µs/tick before and after. Over budget after the cheap fixes (flat arrays instead of Dictionaries, fewer allocations) → the C++ GDExtension escape hatch (DECISIONS).
8. **One team per commit.** Stage your own paths (never `git add -A` while the other team has work in progress) and state the proof in the message. Each step ends with a ready-to-paste commit message.

## Where we are

- **Done (2026-10-05):**
  - **Foundations:** research, stack survey, MIT license, CI (local `act` + GitHub).
  - **Platform:** three.js vs Godot bake-off, then Gate 1 → **Godot 4.7**.
  - **Physics core (Phase C):** 64-bit math, rigid body, RK4, a 240 Hz fixed step that is bit-identical across frame rates, and a CSV flight trace.
  - **Aircraft data (D1):** Das Ugly Stik 60, with the CG and nose measured on the full-size plan.
  - **Visual model v1** (model team).

  Each step's proof is in its table row below; the lessons are in LEARNINGS.md.
- **State:** 230 unit and 25 end-to-end physics/input checks (keyboard and a fake radio), 510 model-contract checks, an app-level trimmed-flight check and a frame-rate check on the real app with injected keys; full suite ~27 s.
  - **The Ugly Stik flies trimmed level flight with its engine running:** six-axis aero; .61 glow engine with APC 12×6 thrust and torque; six-axis trim (throttle, elevator, aileron, rudder) applied like radio trims; positional engine sound.
- **Next:** D6b, radio calibration (assign channels by moving the sticks, per-side endpoints, inversion, saved per device). D6a is done: a radio flies while connected, with arming and the unplug failsafe.
- **Open question for D6d:** the solved start trims are added on top of the radio's sticks, and the radio has its own trims. Decide with the owner's radio whether the sim's trims stay, reset to zero, or apply only on the keyboard.
- **Known defect (fix with D7 captures):** physics captures draw the surfaces from the stick commands *without* trims (live rendering includes them), so a capture shows the elevator neutral while the airplane flies with 4.7° of up-trim. D5.9 kept it so its captures could be compared byte for byte.
- **Alpha (v0.1 = PT1) readiness, about 45 % (plan review #3 found more work than the previous 60 % counted):**
  - **Done:** D1–D5.
  - **Left:**
    - D5.9 seams;
    - D6a–d radio (arming safety, calibration, servo model);
    - D7 pilot aids (shadow, HUD, auto-zoom, hot reload);
    - D8a–b verification, flight modes, golden flights, independent validation;
    - D9a–d full-envelope stall, asymmetric stall, gyro, crash;
    - PT1a–g release builds.
  - **Estimate:** roughly 7–9 working sessions (a guess).
  - **Risks (researched, see RESEARCH.md plan review #3):**
    - On Linux an EdgeTX radio in Classic USB mode probably becomes an SDL *gamepad* (throttle as a 0..1 trigger, Ch7/8 lost).
    - Joystick axes read 0 until moved, so a resting throttle reads as mid-throttle.
    - The macOS universal export fails without `import_etc2_astc`.
    - Whether the borrowed aero *feels* like a Stik: its flight modes are 1.45× (pitch) and 1.9× (roll) faster than a flight-identified Ultra Stick 120 (Gate 2).
  - **Alpha will not have:** runway takeoff and landing (M2), wind, a radio setup screen, a realistic engine response, or menus. It starts in the air.
- **M1 so far, measured against the predicted-handling table:**
  - trim α 3.71° at 15 m/s (predicted 3.6°); thrust needed 3.00 N (predicted 2.93);
  - glide L/D 8.46 (predicted 8.7; the hand estimate ignored trim drag); α 1.51° at 20 m/s (predicted 1.5°);
  - full-aileron roll rate 192°/s at 20 m/s (predicted 192);
  - the live app glides at 1.7599 m/s sink against the solver's 1.760;
  - D5 (engine): static thrust 41.2 N (T/W 1.6); cruise at 15 m/s needs 28 % throttle (5,139 rpm, 3.02 N); torque trimmed with 2.2 % right aileron;
  - hands-off trimmed level flight holds altitude and heading to 1e-4 for 30 s (ignoring torque in the trim gives a 26 m spiral dive).

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

Computed by hand from the D1 data (`app/data/aircraft/jensen_ugly_stik_60.json`, 2.601 kg, 720 in², borrowed UltraStick25e aero). These are **predictions to check, not measurements**; a big miss means a bug or bad data, a small one is a tuning question. **They come from the same coefficients the simulation uses, so matching them verifies the code, not the realism** (rule 6). Independent targets are in D8b.

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
| D2 ✅ | Air data: air-relative velocity, α, β, dynamic pressure; **safe at zero and very low airspeed** (no NaN, no divide-by-zero) | Hand-computed values; V → 0 stays finite |
| D3 ✅ | **Full linear aero model, all six axes in one function** (the coefficients already exist), plus the mapping from our command conventions to the data's surface conventions (elevator +TE down, rudder +TE left…) | Hand-computed loads at three states. Sign tests: +pitch command → nose-up moment, +roll → right roll, +yaw → nose right, sideslip → weathervane, rates → damping. A power-off glide trace shows L/D ≈ 8.7 at 15 m/s |
| D4 ✅ | Trim solver (α, elevator, throttle) at a requested speed; failure is reported, never hidden | 15 m/s trims at α 3.6° ± 0.5°; an impossible request fails visibly |
| D5 ✅ | Thrust v0: static thrust from the APC 12×6 data at a labeled rpm, falling with airspeed, first-order lag; **placeholder engine sound** whose pitch follows throttle | Level flight holds ±1 m for 30 s at trim; climb at full throttle is plausible; sound changes with throttle |
| D5.9 ✅ | **Seams before input and HUD.** Split `main.gd` (336 lines, nine jobs) into `flight_session.gd` (aircraft load, trim, reset, crash), `pilot_camera.gd` and `recorder.gd`. Move control throws (now estimates in `spec.gd`) into the aircraft data with provenance, and step the command shaping once per physics tick (`pre_step`) instead of per rendered frame | No behavior change: `--trace` output identical before and after (hash of the rows); captures identical; `test.sh` green. The 30/60/144 fps hash test now drives **the real app with injected key events**, not synthetic loads; a deliberate "shape with the frame delta" bug changes the hashes. ✅ 2026-10-05: `main.gd` 336 → 224 lines plus `sim/flight_session.gd`, `sim/recorder.gd`, `render/pilot_camera.gd`; throws in `controls.max_throw` (6 new data checks); `--trace` SHA-256 `97c4e73c…` identical before and after; 5 captures byte-identical; real-app keys give identical hashes at 30/60/144 fps; the frame-delta mutation (scratch copy) gives three different hashes |
| D6a ✅ | **Radio reader with safety rules.** `rc_input.gd` reads raw axes 0–9 once per physics tick into 64-bit floats. Device key = GUID + VID:PID + name. Set `Input.use_accumulated_input = false` (one frame of latency on Linux/macOS otherwise). **Arming:** the engine follows the stick only after the throttle has been *seen* at or below 5 % (axes read 0 = mid-throttle until moved). **Unplug:** throttle idle, surfaces neutral, visible pause (core of former F3) | Headless tests inject `InputEventJoypadMotion` on fake id 15: mapping, inversion, 0..1 trigger axes, arming, unplug failsafe. Never call `get_joy_guid` on a fake id. Removing the arming rule in a scratch copy fails a test. ✅ 2026-10-05: `input/rc_input.gd` (pure state machine) + `FlightSession` device choice and failsafe; 25 unit checks (`test_rc_input.gd`) and 16 end-to-end checks on the real scene with fake device 15 (`test_e2e_radio.gd`). Mutations in a scratch copy: ungated throttle → 6 failures (the engine sat at 50 % with every axis at 0); a failsafe that does not pause → 3 failures. Keyboard flight hash unchanged at 30/60/144 fps; `--trace` bytes unchanged; physics captures differ only by the new `input:` panel line and two-decimal raw values |
| D6b | **Calibration:** assign channels by "move the stick"; min/center/max per side (piecewise, handles 0..1 triggers); inversion; saved per device key in `user://rc_calibration.cfg`. Radios get no deadzone or expo; gamepads get a profile with both | Unit tests for the calibration math and the config round trip. The owner calibrates their radio without editing files |
| D6c | **Servo model** between stick and surface, at the physics tick: slew rate in the aircraft data (labeled estimate, e.g. 0.12–0.20 s/60°). The keyboard keeps its rate limiter as an input-device profile, not as servo physics | Step test: full stick reaches full throw in the servo time. The trace shows the lag. The frame-rate hash test stays identical |
| D6d | **Owner flies with the radio.** Recommended setup: EdgeTX Advanced mode, Interface = Joystick, ≤ 8 axes, RF modules off (1 ms reports). First compatibility rows (start of F4) | Owner session note; one F4 row per OS tried (device, firmware, USB mode, axes seen, gamepad or joystick) |
| D7 | **Pilot aids:** ground shadow (the main RC height cue), textured grass, HUD (airspeed, altitude, α), performance overlay (fps, frame time p95, physics µs/tick). **Auto-zoom:** FOV narrows with distance, clamped, toggleable (a 720p screen at 50° resolves ~4× worse than the eye). **Hot reload:** a key reloads the aircraft JSON, re-trims and resets; invalid data keeps the old aircraft and shows why | Captures show the shadow. Pure-function test: with auto-zoom the projected span is ≥ 30 px from 20 to 150 m (≈ 12 px at 100 m today). Hot-reload test: an edited coefficient changes the trim, a broken file keeps the old aircraft with a message. Perf numbers recorded on the owner's machine |
| D8a | **Verification and the first golden flights.** Scripted roll, glide and slow-flight maneuvers through the real loop reproduce the predicted-handling table. Flight modes (`research/flight-modes/`) become a test with bands at 10/15/25 m/s. The maneuver traces become **golden flights** (record per-tick inputs, replay, compare within tolerance; moved up from E4 because D9 changes the aero) | Each number within its band. The modes test fails on a deliberate Clp sign flip. A golden replay matches; a deliberate CD0 change is detected |
| D8b | **Validation against independent data:** Froude-scaled UMN Ultra Stick 120 flight-identified modes (RESEARCH.md plan review #3); Dorobantu 2013 for the 25e if obtainable; real-Stik video measurements (roll rate, stall speed by frame counting) | A sim-vs-reference table with ratios. The 1.45× short-period and 1.9× roll gaps are either explained or become D10's first parameters |
| D9a | **Full-envelope blend** (whole aircraft): sigmoid from the linear model to a flat plate (CL, CD with CD90 ≈ 1.2, CY in β for knife edge); α0 and blend sharpness labeled estimates. The linear model stays as the **test oracle** | Below 8° α, loads equal the linear model to 1e-9. Sweeps over α −180…180° and β −90…90° are finite and continuous (bounded jump per 0.1°); CL peaks at the labeled CLmax. **1-g slow flight with full up elevator stalls at 8.6–9.5 m/s** instead of parachuting at 7.0 m/s (α 21°, CL 1.77 today) |
| D9b | **Asymmetric stall:** CRRCSim-style local CL at three spanwise stations (from p̂); a stalled station loses lift, giving roll and yaw | Traces: a cross-controlled stall drops a wing and autorotates; a symmetric stall at zero rates drops the nose without rolling; neutral controls recover |
| D9c | **Gyroscopic precession** of propeller and crank (`−ω × H`, J_p labeled estimate ≈ 3e-4 kg·m²) | Sign test: clockwise prop (seen from behind), pull up → nose yaws right. Torque-free spin conserves total angular momentum with the term |
| D9d | Ground hit → crash → reset | Crashing at any attitude resets cleanly; high-α traces stay finite |
| PT1a | `app/get-templates.sh`: download the 1.28 GB `.tpz`, check its SHA-512 against `SHA512-SUMS.txt`, extract only the Linux, Windows and macOS templates into `export_templates/4.7.2.stable/` | First run prints the hash OK; second run is a no-op |
| PT1b | `export_presets.cfg` (Windows x86_64 with embedded pck, Linux x86_64, macOS universal with built-in ad-hoc signing), `include_filter="data/*.json"`, `exclude_filter="tests/*"`; `import_etc2_astc=true` in `project.godot` (the macOS export fails without it) | Headless export of all three exits 0 with no `ERROR` lines; `test.sh` green |
| PT1c | **Smoke-test the exported Linux binary:** `--headless -- --trace` passes `check_trimmed_flight.py` | Proves the JSON is inside the pack; dropping the include filter in a scratch copy fails it |
| PT1d | macOS artifact check from Linux | `unzip -l` shows the executable with mode 0755; `rcodesign verify` (or `codesign -dv` on a Mac) reports an ad-hoc signature |
| PT1e | CI `export` job on `main` and `workflow_dispatch`; template cache warmed on `main` (tag runs cannot see other tags' caches); third-party actions pinned by commit SHA | The second run logs a cache hit; artifacts downloadable |
| PT1f | CI `release` job on `v*` tags: `gh release create` with three zips and `SHA256SUMS` | A `v0.1.0-rc1` tag produces a release with three assets |
| PT1g | README "First launch": **macOS 15+ no longer accepts right-click → Open**; use System Settings → Privacy & Security → Open Anyway, or `xattr -dr com.apple.quarantine`. Windows: More info → Run anyway (Smart App Control blocks unsigned apps with no override) | The owner downloads, runs and flies v0.1 on each OS; notes in LEARNINGS.md |
| **Gate 2** | **"Is it flyable, readable and fun?"** The owner (and ideally 1–2 RC pilots) fly v0.1 with a radio. **Measured in one session:** three circuits, a loop, a roll, a stall and recovery. Each axis (roll, pitch, yaw, throttle) rated −2 (sluggish) … +2 (twitchy) against a real Stik. Orientation read correctly at 100 m with and without auto-zoom. Radio setup time. Frame time p95 and physics µs/tick | Notes and ratings recorded. Any rating beyond ±1 sets the D10 order; M2 reordered if needed |
| D10 | Sensitivity sweep on the D8 maneuvers and flight modes, in this order: Clp, Cmq, Ixx, Iyy (inventory is 1.7× a Roskam-typical value), servo lag, CLmax/α0, CD0, CG, mass | A table ranking which unknowns matter; decides what to measure next |
| **Gate F** | **Flight-model architecture before M2.** Keep the whole-aircraft model with fixes, or grow a component buildup (tail surfaces → propwash → wing panels)? Evidence: the D8b table, D9 behavior, Gate 2 ratings, physics µs/tick. Default proposal: grow the buildup one surface group at a time, each matching the linear oracle at small α | Decision recorded in DECISIONS.md with the evidence |

### M2 — Takeoff and landing

| # | Step | Proof |
| --- | --- | --- |
| E0a | Horizontal and vertical tail as separate surfaces (local α from q·l and r·l, downwash lag), geometry read from the model team's `ugly_stik_geometry.gd`; the whole-aircraft derivatives lose their tail share | Linearized Cmα, Cmq, Cnβ and Cnr within ±10 % of the oracle at trim; the modes test stays within its bands; µs/tick reported |
| E0b | **Propwash on the tail** (momentum theory with contraction, washed fraction of each surface, labeled lag). Moved up from M5: at 5 m/s and full throttle the washed tail sees ≈ 35× the freestream dynamic pressure | At V = 0 and full throttle, elevator and rudder produce moments; at cruise the factor is ≤ 1.3× (the computed bound) |
| E1 | Tricycle gear contact points as spring-dampers; stiffness from a natural-frequency rule (`ω·dt < 0.1`) | Drop test: no energy gain; agrees across `h` and `h/2` |
| E2 | Rolling friction (labeled guess), nosewheel steering, brakes off | Taxi a figure-eight |
| E3 | Start on the runway: takeoff, circuit, landing, nose-over | Trace of a full circuit |
| E4 | Golden flight of a full circuit (the mechanism exists since D8a) | A replayed circuit matches its recording; a deliberate physics change is detected |
| PT2 | Playtest v0.2 | Owner flies takeoffs and landings |

### M3 — The radio, done properly

| # | Step | Proof |
| --- | --- | --- |
| F3 | Replug and focus-loss polish on top of D6a's failsafe: `ignore_joypad_on_unfocused_application`, reconnect to the same device key, the Windows disconnect hang in 4.7 ([#121539](https://github.com/godotengine/godot/issues/121539)) checked on 4.8 | Scripted unplug/replug log |
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
- swirl and wing-wash effects of the propeller (tail propwash moved to E0b)
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
| Dorobantu et al. 2013 (Ultra Stick 25e flight-identified model, [doi:10.2514/1.C032065](https://doi.org/10.2514/1.C032065), paywalled): obtain via a library | D8b | 1 session |
| Owner's radio over USB on each OS: Classic vs Advanced mode, joystick vs gamepad detection, axes seen | D6d | 1 session with the radio |
| Real-Stik videos: roll rate and stall speed by frame counting | D8b | 1 session |

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

## Plan review #3 (2026-10-05): senior review before D6

A senior game/Godot review of the plan and the code before input, HUD and stall work start. Method:
- read all simulation code;
- ran the suite (green, 24 s);
- measured the app;
- linearized the real equations ([`research/flight-modes/`](research/flight-modes/));
- three research tracks that read Godot 4.7.2, EdgeTX, CRRCSim, PicaSim and YASim source plus the UMN and McGill theses.

Details and sources: [RESEARCH.md, plan review #3](RESEARCH.md#plan-review-3-radio-input-full-envelope-flight-release-and-measured-flight-modes).

**What is already strong (keep it):**
- 64-bit physics with an enforced guard;
- RK4 with known-answer and convergence tests;
- a bit-identical fixed step across frame rates;
- provenance on every number;
- a trim solver on the real equations;
- app-level trace checks;
- mutation checks on the guards themselves.

Few indie simulators start this well. The weak points are about what comes next.

| # | Finding (evidence) | Change |
| --- | --- | --- |
| 1 | **The handling check is circular.** The predicted-handling table uses the same borrowed coefficients as the sim, so D8 could only verify code. The first independent comparison (UMN Ultra Stick 120 flight-identified modes, Froude-scaled, same CL) shows the sim **1.45× faster in pitch and 1.9× faster in roll**, more damped, dutch roll close | Rule 6; D8 split into D8a (verification, modes test, golden flights) and D8b (independent validation); D10 order starts with Clp, Cmq, inertia, servo lag |
| 2 | **No stall at all.** With full up elevator at 1 g the linear model trims at α 21°, CL 1.77, and parachutes at 7.0 m/s; the predicted stall is 8.6–9.5 m/s. Slow flight near landing is where pilots meet the stall | D9a full-envelope blend with the linear model as oracle, with a measured slow-flight target |
| 3 | **A lift cap cannot spin or snap.** The Stik's signature maneuvers and tip stalls (the classic RC landing crash) need asymmetric stall. CRRCSim gets it with three spanwise stations at small cost (source read) | D9b three-station asymmetric stall |
| 4 | **Propwash was "polish" (M5),** but at 5 m/s and full throttle the washed tail sees ≈ 35× freestream dynamic pressure (momentum theory). Takeoff and ground handling depend on it | E0a (separate tail surfaces) and E0b (propwash) before the gear steps |
| 5 | **Gyroscopic precession is missing.** At full rpm a 3 rad/s pitch rate gives ≈ 1 N·m of yaw: 14 % of full rudder at 15 m/s, ~50 % at 8 m/s; snaps far more. It costs one cross product | D9c |
| 6 | **Radio risks were unknown; now they are concrete** (Godot 4.7.2 and EdgeTX source read). On Linux, Classic mode probably becomes an SDL gamepad (throttle as a 0..1 trigger, Ch7/8 lost). Axes read 0 until moved, so a resting throttle reads as **mid-throttle** at startup and after an unplug. Accumulated input adds one frame of latency on Linux/macOS | D6 split into D6a (reader with arming and unplug failsafe, accumulated input off), D6b (calibration), D6c (servo model), D6d (owner flight, recommended EdgeTX setup) |
| 7 | **Device behavior is mixed with physics.** The keyboard rate limiter (4/s, applied per *rendered frame*) stands in for servo dynamics, and the control throws live in `spec.gd` as unlabeled estimates, outside the data rules. Only scripted loads, never the input path, are tested for frame-rate independence | D5.9 moves throws into the aircraft data and steps commands per physics tick; D6c adds a servo model; the hash test drives the real input path |
| 8 | **`main.gd` is becoming a god object:** 336 lines, nine jobs (world, input, sim wiring, trims, trace, capture, camera, sound, panel). D6 and D7 would each add more | D5.9 splits it before D6, with "identical trace bytes" as the proof |
| 9 | **The release plan had three blockers** (source read). The macOS universal export fails without `import_etc2_astc=true`. The aircraft JSON is not exported without an include filter, so the shipped app would refuse to fly. **macOS 15+ removed right-click → Open** | PT1 rewritten as PT1a–g; PT1c smoke-tests the exported binary with the real trace check |
| 10 | **The pilot sees ~12–15 px of airplane at 100 m.** A 720p screen at 50° resolves ~4× worse than the eye; RC sims (SeligSIM) offer auto-zoom | D7 auto-zoom with a pixel target; Gate 2 rates readability with and without it |
| 11 | **Tuning iteration is slow:** every coefficient change needs a restart. Gate 2 is a tuning session | D7 hot reload of the aircraft JSON (invalid data keeps the old aircraft) |
| 12 | **Golden flights came after the aero changes** (E4, in M2), but D9 rewrites the aero first | Golden flight mechanism moved into D8a |
| 13 | **No performance budget.** Measured ≈ 313 µs per tick end to end on this VM; a component buildup could triple it | Rule 7 (≤ 0.5 ms per tick on the owner's slowest machine) with a defined trigger for GDExtension |
| 14 | **"Fun" was not measurable** at Gate 2 | Gate 2 gets a maneuver list, −2…+2 ratings per axis against a real Stik, readability, setup time and frame time |
| 15 | **Inventory Iyy is 1.7× a Roskam-typical value** (Ry 0.438 vs 0.338) | Labeled; D10 parameter |
| 16 | **Commits don't state proofs and mix teams:** several commits named "Refactor code structure for improved readability" add physics and model files together. Bisecting a regression becomes hard | Rule 8 (one team per commit, proof in the message, the assistant supplies the message) |
| 17 | **The flight-model architecture decision was implicit.** The derivative model cannot express propwash, asymmetric stall or damage, and the model team's geometry could feed a component buildup | Gate F before M2, with a default proposal: grow the buildup one surface group at a time, each matching the linear oracle |
