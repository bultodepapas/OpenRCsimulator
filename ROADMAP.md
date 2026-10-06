# Roadmap

Revised **2026-10-05** after three reviews (the second, "from infrastructure to a game", and the third, a senior review before D6, are at the end) of the first plan (weak points and fixes are [at the end](#review-weak-points-found-and-how-the-plan-fixes-them)). It builds on [RESEARCH.md](RESEARCH.md), [STACK.md](STACK.md) and [DECISIONS.md](DECISIONS.md). Every track, plan and step-ID prefix is registered in the [documentation map](docs/README.md). Deepened on 2026-10-06 by [plan review #4](#plan-review-4-2026-10-06-deep-research-before-m2-grows), which adds a research knowledge base per phase ([docs/research/roadmap-investigations/](docs/research/roadmap-investigations/README.md)).

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
9. **Read before you build.** Each phase has a knowledge-base document in [docs/research/roadmap-investigations/](docs/research/roadmap-investigations/README.md) (theory, tools, data, tests, pitfalls). Read it before the step; if the step proves it wrong, fix the document in the same change.
10. **Measure before tuning.** A gap against independent data is closed by measuring the unknown that explains it (mass, CG, inertia, throws, thrust), never by tuning a coefficient that only hides it. Values fitted to a reference are flagged and never count as validation of that reference.

## Where we are

- **Done (2026-10-05):**
  - **Foundations:** research, stack survey, MIT license, CI (local `act` + GitHub).
  - **Platform:** three.js vs Godot bake-off, then Gate 1 → **Godot 4.7**.
  - **Physics core (Phase C):** 64-bit math, rigid body, RK4, a 240 Hz fixed step that is bit-identical across frame rates, and a CSV flight trace.
  - **Aircraft data (D1):** Das Ugly Stik 60, with the CG and nose measured on the full-size plan.
  - **Visual model v1** (model team).

  Each step's proof is in its table row below; the lessons are in LEARNINGS.md and `docs/learnings/`.
- **State:** about 1,250 automated checks in ~45 s (unit, end-to-end with keyboard and a fake radio, flight modes, flown handling, envelope, spin, gyro, crash, 4 golden flights, model contract, app trace, frame-rate independence), plus `app/export.sh` release builds with their own smoke tests.
  - **The Ugly Stik flies trimmed level flight with its engine running:** six-axis aero; .61 glow engine with APC 12×6 thrust and torque; six-axis trim (throttle, elevator, aileron, rudder) applied like radio trims; positional engine sound.
- **Releases:** [v0.1.0-rc1](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc1) (M1 flight, radio, pilot aids) and [v0.1.0-rc2](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc2) (landscape L0–L4: sky, haze, clouds, sun shadow; frame-time report). [v0.1.0-rc3](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc3) adds Home/pause/aircraft selection, experimental Extra and Mustang models, and the L6a/b treeline. Notes per release in `docs/releases/`.
- **Next: Gate 2 — the owner flies v0.1.** Everything in M1 that can be done without the owner is done (2026-10-05). Waiting on the owner: D6d (fly with your radio, F4 rows), a `v0.1.0-rc1` tag for PT1f, PT1g (launch on each OS), Gate 2 ratings, then Gate F. Done in M1: D9d (crash hull and restart), D9c (gyroscopic precession), D9b (asymmetric stall, spins with standard recovery), D9a (full-envelope stall at 8.8 m/s, linear model kept as exact oracle), D6a–c (radio with safety and calibration, servos), D7 (shadow, grass, HUD, perf, auto-zoom, hot reload), D8a (handling verification, modes test, golden flights).
- **UI track ([MENU-PLAN](docs/MENU-PLAN.md), subordinate to Gate 2):** UI-00…05 done (2026-10-05/06): Home over a live render of our field, English by default with Spanish, radios never navigate menus, pause menu on Esc or focus loss (propeller and engine sound freeze), End flight back to Home, one build identity from `git describe`, Help generated from the controls table with the player's key labels, aircraft selector over the catalog. Next: UI-06 scenarios, UI-07 preferences, UI-08 HUD and volume. Proofs and the execution log are in the plan.
- **Visual quality and landscape tracks ([VISUAL-QUALITY-PLAN](docs/VISUAL-QUALITY-PLAN.md) executes the L steps defined in [LANDSCAPE-PLAN](docs/LANDSCAPE-PLAN.md); subordinate to Gate 2):** L0–L4 shipped in rc2; VQ-01a/b (112 fixed captures with rendered-state provenance, frame-time logger), L5 (one validated field shared by Home and flight), L6a/b (three reviewed tree silhouettes, 480 trees in eight sectors, 2–8 draws) done; L6c readability numbers recorded, the owner's blinded playtest (Gate L) pending. Next: L9a, VQ-02. Software rendering verifies the protocol, not target-GPU performance.
- **Second aircraft track ([EXTRA-300-PLAN](docs/EXTRA-300-PLAN.md), subordinate to Gate 2):** the Great Planes Extra 300S .60 is measured from its plans and **flyable, experimental** (EX-00–05, 07, 10a, 11 done): chosen on Home or with `--aircraft=gp-extra-300s-60`, physics generated from the measured geometry by `research/extra-300/ex05/derive_physics.py` (textbook estimates, labelled), `tests/test_extra_handling.gd` (hands-off, roll rates within 7 % of prediction, loop, stalls, spin recovery), Stik goldens unchanged. Next: EX-06 thrust axis, EX-08 envelope, EX-09 independent contrast. Third aircraft: the Avanti S ([AVANTI-S-PLAN](docs/AVANTI-S-PLAN.md)) flies as **experimental** since AV-07 (2026-10-06): turbine propulsion kind (AV-05a, `physics/turbine.gd`), physics generated by `research/avanti-s/av06/derive_physics.py` from kit, owner and JetCat data, `tests/test_avanti_handling.gd` (30); in-air start, flaps and gear up ([model report](docs/research/avanti-s-av06-physics-model.md)).
- **Flight-model repair ([FLIGHT-MODEL-ROBUSTNESS-PLAN](docs/FLIGHT-MODEL-ROBUSTNESS-PLAN.md), [RUDDER-REPAIR-PLAN](docs/RUDDER-REPAIR-PLAN.md), [report](docs/research/flight-repair-implementation.md); 2026-10-06):** done: D9-R1/R2 (wing and tail loads as local elements with `v + ω × r` and `r × F`, continuity across reverse flow, passive aerodynamic power; mixed stall deficits and `station_kappa` removed), D4-R1 (transactional aircraft load and trim, non-finite rollback), D1-R1 (one mass inventory for CG and inertia), D8a-R1 (shared `Dynamics`, full 8×8 Jacobian with the gyroscopic term; 4×4 projections are approximations), D10-R (rudder derivatives tied to force and arm, authority and recovery regressions). Open: Gate 2-R (pilot and real build), E0b propwash and G2 shaft balance; the local tail uses free-stream flow, so E0a is only partly done. The rudder doublet now peaks at β 19.9° (was 42.4°).
- **Proposals, not started:** [SMOKE-PLAN](docs/SMOKE-PLAN.md) (SM-00…09, exhaust and pump) and [WIND-PLAN](docs/WIND-PLAN.md) (M5-W00…08; its code audit predates the repair and is re-read before W01).
- **Plan review #4 (2026-10-06, [below](#plan-review-4-2026-10-06-deep-research-before-m2-grows)):** ten research documents ([knowledge base](docs/research/roadmap-investigations/README.md)) deepen M2–M5 and add Phase H (headroom: physics is at **501 µs of its 500 µs** budget per tick), D11 (flight-model consistency: roll damping varies 1.7× and pitch damping 3× across the approach α range), M4b electric propulsion, and three parallel programs: validation (VAL), aircraft data v2 (DATA) and perception (PERC). H1–H3 and D11a–b done the same day (trimmed tick 592 → 400 µs on the loaded VM, every trajectory bit-identical). H4–H6 rewrite `aero.gd`, `propulsion.gd`, `slipstream.gd` and `turbine.gd`, which the P-51 and Avanti tracks are changing now: they wait for that work to land. Next: E3b1.
- **Fourth aircraft track ([P51-PLAN](docs/P51-PLAN.md), subordinate to Gate 2):** P51-00 to P51-09, P51-12 and P51-13 done (2026-10-06); P51-10 visual V01-V08/V10 done. A giant-scale **P-51D Mustang 1/4 (2.82 m, 120 cc class)** is in the catalog as **experimental**: geometry scaled exactly 1/4 from the full-size airplane and measured on the AN 01-60-3 three-view; physics from `research/p51/p51-05/derive_physics.py`, cross-checked against NACA flight data and RC-class data ([flight realism](docs/research/p51-flight-realism.md): washout 1.88°, stab +2°, neutral point 34.2 % MAC, CL_max 1.02 from Reynolds-dependent section data, 21.5 kg, Mejzlik-calibrated 4-blade 26x12, installed DA-120 power 6.9 kW). Opt-in physics added for it (absent data = unchanged, Stik goldens bit-identical): shaft-balance rpm (G2 first slice), thrust angles, propeller normal force and P-factor, tail slipstream with swirl (E0b first slice, `physics/slipstream.gd`), per-strip wing incidence, tail-wheel steering. Proof: `tests/test_p51_handling.gd` (15), `tests/test_p51_envelope.gd` (15: modes, 51 m/s top speed, climb, idle glide, stalls with left wing drop and recovery, roll rates, turn), `tests/test_p51_ground.gd` (11: three-point attitude, left takeoff swing, 39 m takeoff roll, wheel landing and rollout). Next: P51-14 pilot review (trim feel, swing strength, stall break), V09 scheme.
- **Open question for D6d:** the solved start trims are added on top of the radio's sticks, and the radio has its own trims. Decide with the owner's radio whether the sim's trims stay, reset to zero, or apply only on the keyboard.
- **Alpha (v0.1 = PT1) readiness: all the work that does not need the owner is done (2026-10-05).**
  - **Done:** D1–D5, D5.9, D6a–c, D7, D8a, D8b (US120 part), D9a–d, D10, PT1a–e (PT1f written, PT1g documented).
  - **Waiting on the owner:**
    - D6d: fly with your radio, compatibility rows;
    - PT1g: launch the build on Linux and macOS (Windows confirmed);
    - Gate 2: ratings;
    - D8b: real-Stik videos.
  - **Known limits going into Gate 2:**
    - roll responds 2.07–2.37× faster than two flight-identified Ultra Sticks (US120 and 25e), mostly because the inventory Ixx is low; the short period is 1.07× (US120) and 0.87× (25e) (D11a, 2026-10-06);
    - after the 2026-10-06 repair the reference rudder doublet peaks at β 19.9° (was 42.4°); the spiral mode is slightly unstable at 10 and 15 m/s and neutral at 25 m/s (engineering bands, not telemetry);
    - a developed spin needs opposite rudder (it does not recover hands-off);
    - from the pilot's eye the ground shadow only helps up close;
    - auto-zoom can push the ground out of frame.
  - **Alpha will not have:** runway takeoff and landing (M2), wind, a radio setup screen or a realistic engine response. It starts in the air. (rc3 added Home, pause, Help and aircraft selection: UI-00…05.)
- **M1 so far, measured against the predicted-handling table:**
  - trim α 3.71° at 15 m/s (predicted 3.6°); thrust needed 3.00 N (predicted 2.93);
  - glide L/D 8.46 (predicted 8.7; the hand estimate ignored trim drag); α 1.51° at 20 m/s (predicted 1.5°);
  - full-aileron roll rate, **flown** (D8a): coordinated 148°/s at 15 m/s and 189°/s at 20 m/s (single-axis prediction 144/192); with the feet still 123/166°/s, because adverse yaw and the dihedral effect slow the roll. (An earlier "192 measured" here was the formula evaluated in a unit test, not a flight.)
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
| D6b ✅ | **Calibration:** assign channels by "move the stick"; min/center/max per side (piecewise, handles 0..1 triggers); inversion; saved per device key in `user://rc_calibration.cfg`. Radios get no deadzone or expo; gamepads get a profile with both | Unit tests for the calibration math and the config round trip. The owner calibrates their radio without editing files. ✅ 2026-10-05: `input/rc_calibration.gd` wizard ([K], Enter per step, [Esc]) and profile store (per device key, validated on load); calibrated endpoints in `rc_input.gd`; SDL-known gamepads get a deadzone/expo profile with a rate throttle, except devices named like radios. 41 + 19 unit checks and an end-to-end calibration (swapped axes, saved, reloaded on replug). Mutation "ignore the stick direction" → 4 failures. The owner's own calibration remains for D6d |
| D6c ✅ | **Servo model** between stick and surface, at the physics tick: slew rate in the aircraft data (labeled estimate, e.g. 0.12–0.20 s/60°). The keyboard keeps its rate limiter as an input-device profile, not as servo physics | Step test: full stick reaches full throw in the servo time. The trace shows the lag. The frame-rate hash test stays identical. ✅ 2026-10-05: `controls.servo_full_throw_time` 0.14 s (estimated: 0.19 s/60° × ~45° arm travel); servo positions are simulation state (`aux`, trace v3 `srv_*`); aero, rendering and captures use them. `test_servo.gd`: full throw on tick 34 exactly, lag visible in the trace, roll rate builds with the aileron. Instant-servo mutation → 4 failures. Trimmed flight: every v2 trace column identical. Keyboard hash unchanged (its 4/s virtual stick is slower than the 7.1/s servo, so the servo never limits it). Physics captures now draw the trimmed surfaces (known defect fixed) |
| D6d | **Owner flies with the radio.** Recommended setup: EdgeTX Advanced mode, Interface = Joystick, ≤ 8 axes, RF modules off (1 ms reports). First compatibility rows (start of F4) | Owner session note; one F4 row per OS tried (device, firmware, USB mode, axes seen, gamepad or joystick) |
| D7 ✅ | **Pilot aids:** ground shadow (the main RC height cue), textured grass, HUD (airspeed, altitude, α), performance overlay (fps, frame time p95, physics µs/tick). **Auto-zoom:** FOV narrows with distance, clamped, toggleable (a 720p screen at 50° resolves ~4× worse than the eye). **Hot reload:** a key reloads the aircraft JSON, re-trims and resets; invalid data keeps the old aircraft and shows why | Captures show the shadow. Pure-function test: with auto-zoom the projected span is ≥ 30 px from 20 to 150 m (≈ 12 px at 100 m today). Hot-reload test: an edited coefficient changes the trim, a broken file keeps the old aircraft with a message. Perf numbers recorded on the owner's machine. ✅ 2026-10-05 (except the owner's perf numbers, at Gate 2): `render/shadow.gd`, `render/ground.gd`, `render/hud.gd`, auto-zoom in `render/pilot_camera.gd`, [F5] `FlightSession.reload()`; keys Z (auto-zoom), F3 (perf line), F5. `test_pilot_aids.gd` (20 checks): ≥ 30 px from 20 to 150 m with auto-zoom (11.8 px at 100 m without); shadow footprint narrows when banked; deterministic grass; p95; reload with more drag needs more throttle, broken data refused. Captures `-physics-nozoom` and `-physics-low-inspect` added; captures repeat byte for byte. **Findings for Gate 2:** (1) from the pilot's eye (1.7 m) at 77 m the ground is seen at ~1.3°, so a vertical shadow is < 1 px thick: it is a cue for close passes and landings only; (2) auto-zoom at altitude pushes the ground out of the frame (SeligSIM's "keep ground in view" mode exists for this) |
| D8a ✅ | **Verification and the first golden flights.** Scripted roll, glide and slow-flight maneuvers through the real loop reproduce the predicted-handling table. Flight modes (`research/flight-modes/`) become a test with bands at 10/15/25 m/s. The maneuver traces become **golden flights** (record per-tick inputs, replay, compare within tolerance; moved up from E4 because D9 changes the aero) | Each number within its band. The modes test fails on a deliberate Clp sign flip. A golden replay matches; a deliberate CD0 change is detected. ✅ 2026-10-05: `sim/maneuvers.gd` (scripted, closed-loop capable), `test_handling.gd` (9 checks: trim α 3.71°, hands-off hold, coordinated roll 148/189°/s vs 144/192, adverse-yaw roll 83–88 %, dead-stick glide L/D 8.46), `physics/linearize.gd` + `physics/flight_modes.gd` + `test_modes.gd` (34 checks, ±3 % bands at 10/15/25 m/s), golden flights `tests/golden/*.json` (4 maneuvers, replay error ~1e-15; `record_golden.gd` re-records). New: engine running/stopped state (a glide start is dead stick). Mutations: CD0 +3.7 % → all 4 goldens fail (8–18 cm); roll-damping sign flip → modes fail. Finding: the idle propeller's extrapolated Ct floor (−0.1) cuts the glide to L/D 5.9; check against windmilling data in G1 |
| D8b (partly ✅) | **Validation against independent data:** Froude-scaled UMN Ultra Stick 120 flight-identified modes (RESEARCH.md plan review #3); Dorobantu 2013 for the 25e if obtainable; real-Stik video measurements (roll rate, stall speed by frame counting) | A sim-vs-reference table with ratios. The 1.45× short-period and 1.9× roll gaps are either explained or become D10's first parameters. ✅ 2026-10-05 for the US120 part: `research/sensitivity/results.md` (regenerated by `research/sensitivity/sensitivity.gd`) — short period 1.45×, roll τ 2.1× faster, dutch roll 1.16×, spiral stable both; full rudder trims at β 63°. D10 shows the gaps are **not** explained by ±20 % on any single unknown (roll τ: Clp −17/+25 %, Ixx ±20 %; short period: Iyy +12/−9 %, CG ±9 %). Still open: Dorobantu 2013 (library) and real-Stik video measurements (owner) |
| D9a ✅ | **Full-envelope blend** (whole aircraft): sigmoid from the linear model to a flat plate (CL, CD with CD90 ≈ 1.2, CY in β for knife edge); α0 and blend sharpness labeled estimates. The linear model stays as the **test oracle** | Below 8° α, loads equal the linear model to 1e-9. Sweeps over α −180…180° and β −90…90° are finite and continuous (bounded jump per 0.1°); CL peaks at the labeled CLmax. **1-g slow flight with full up elevator stalls at 8.6–9.5 m/s** instead of parachuting at 7.0 m/s (α 21°, CL 1.77 today). ✅ 2026-10-05: `aero.envelope` data (CL_max 1.1, CL_min −0.8, blend 6°, CD90 1.2 Viterna, sideslip blend 15–25°); the loader solves the stall start so the lift peaks exactly at CL_max (12.1° / −10.9°) and refuses a stall inside the ±8° oracle region. `test_envelope.gd` (14 checks): loads bit-identical to the linear model in 500 attitudes inside the region; finite and continuous (≤ 0.021 per 0.1°) over all α and β; flown slow flight stalls at **8.84 m/s** (theory 9.03) while the linear oracle holds to 7.62 m/s; tail slide finite. Mutation: a weight of 1e-12 breaks the oracle test. Physics 249 µs/tick (+3 %). Golden `rudder_doublet` re-recorded deliberately (the only one that changed): that "gentle" maneuver reaches β 55° and α 25° even in the linear model. **Finding for D8b/D10:** full rudder holds β = Cnδr·δr/Cnβ = 62° in the linear model; real sport planes reach ~15–25°, so the borrowed Cnδr/Cnβ or the 25° rudder throw is too high |
| D9b ✅ | **Asymmetric stall:** CRRCSim-style local CL at three spanwise stations (from p̂); a stalled station loses lift, giving roll and yaw | Traces: a cross-controlled stall drops a wing and autorotates; a symmetric stall at zero rates drops the nose without rolling; neutral controls recover. ✅ 2026-10-05 (recovery by the standard technique, not neutral controls): 3 equal strips per wing side (`Aero.WING_STATIONS_PER_SIDE`), local α from p and r, stall deficits only (linear oracle exact while every strip is attached), roll from the **normal-force** deficit and yaw from the axial one, scaled by κ so the strips reproduce the data's Clp. `test_spin.gd` (9 checks): no stall moment without rotation (exactly 0); roll damping = the linear oracle at 5°, positive (autorotation) at 13.5°; a symmetric airplane stalls without rolling, while the inventory's Jxy (−0.0023) drops a wing; the cross-controlled stall spins at 7.5 rad/s (~1.2 turn/s) sinking 11 m/s; opposite rudder + forward stick for 0.9 s recovers and stays recovered (held longer it spins the other way, as real airplanes do). **Not met:** a developed spin does not recover with neutral controls (inertial pitch-up (Izz−Ixx)·p·r beats the nose-down moment) — Gate 2 and D10 question. Path: two strips ran away (the up-going one stayed attached); lift-based moments ran away (lift falls past 45° while a plate's normal force keeps growing) — mutation "roll from lift" → spin 11.7 rad/s, caught. Physics 290 µs/tick (+16 % over D9a). Golden `rudder_doublet` re-recorded again (only one changed) |
| D9c ✅ | **Gyroscopic precession** of propeller and crank (`−ω × H`, J_p labeled estimate ≈ 3e-4 kg·m²) | Sign test: clockwise prop (seen from behind), pull up → nose yaws right. Torque-free spin conserves total angular momentum with the term. ✅ 2026-10-05: `propulsion.propeller.rotating_inertia` 3.5e-4 kg·m² (estimated: 37 g prop as a rod + spinner + crank); `RB.derivative(..., h_rotor)`, `Simulation.rotor_momentum`, H = 0.41 N·m·s at full rpm. `test_gyro.gd` (6 checks): pull-up → nose right, yaw right → nose down, size = J⁻¹·(0,0,q·h), total angular momentum conserved to 2e-11 over 60 s, flown full-throttle pull-up yaws further right. Reversed-rotor mutation → flown check + 3 goldens fail. Goldens re-recorded deliberately: the three with the engine running changed, the dead-stick glide did not |
| D9d ✅ | Ground hit → crash → reset | Crashing at any attitude resets cleanly; high-α traces stay finite. ✅ 2026-10-05: `crash_hull` data (10 points: tips, spinner, tail, stab tips, fin top, wheels from the visual model's equipment table; estimated, replaced by gear contacts in E1); `FlightSession.touches_ground()`; a crash freezes 1.5 s (360 ticks) showing speed and sink, then restarts; R skips the freeze. `test_crash.gd` (10 checks): wheels at 0.20 m, inverted fin, knife-edge tip, vertical-dive spinner; 100 random crashes from any attitude restart exactly at the trimmed start. CG-only mutation → 5 failures. High-α finiteness: `test_envelope.gd` tail slide |
| PT1a ✅ | `app/get-templates.sh`: download the 1.28 GB `.tpz`, check its SHA-512 against `SHA512-SUMS.txt`, extract only the Linux, Windows and macOS templates into `export_templates/4.7.2.stable/` | First run prints the hash OK; second run is a no-op. ✅ 2026-10-05: SHA-512 verified (same hash as the release's SHA512-SUMS.txt), 4 files (306 MB) in `~/.local/share/godot/export_templates/4.7.2.stable/`, the .tpz deleted; second run 0.01 s |
| PT1b ✅ | `export_presets.cfg` (Windows x86_64 with embedded pck, Linux x86_64, macOS universal with built-in ad-hoc signing), `include_filter="data/*.json"`, `exclude_filter="tests/*"`; `import_etc2_astc=true` in `project.godot` (the macOS export fails without it) | Headless export of all three exits 0 with no `ERROR` lines; `test.sh` green. ✅ 2026-10-05: Linux 76 MB, Windows 112 MB, macOS 63 MB. **Correction to the research:** in 4.7.2 a `.json` file is a recognised resource and is exported by `all_resources` even without the include filter (measured: the build without it still flies); the filter stays, explicit and harmless |
| PT1c ✅ | **Smoke-test the exported Linux binary:** `--headless -- --trace` passes `check_trimmed_flight.py` | Proves the JSON is inside the pack; dropping the include filter in a scratch copy fails it. ✅ 2026-10-05: the exported binary flies alt 30.000 → 30.000 m, identical to the editor. Mutation `exclude_filter="data/*"` → "cannot read …json" and the check fails. Also fixed: `--trace` on invalid data now exits 1 instead of recording a ballistic fall |
| PT1d ✅ | macOS artifact check from Linux | `unzip -l` shows the executable with mode 0755; `rcodesign verify` (or `codesign -dv` on a Mac) reports an ad-hoc signature. ✅ 2026-10-05: `tests/check_macos_export.py` parses the Mach-O: 0755, universal (x86_64 + arm64), both slices ad-hoc signed (CS_ADHOC). Mutation `codesign=0` → "signed, flags 0x0", fails |
| PT1e ✅ (act) | CI `export` job on `main` and `workflow_dispatch`; template cache warmed on `main` (tag runs cannot see other tags' caches); third-party actions pinned by commit SHA | The second run logs a cache hit; artifacts downloadable. 2026-10-05: `export` job (also on `v*` tags) runs `app/export.sh`; template cache keyed on `get-templates.sh`; every action in `ci.yml` pinned by commit SHA. Proven locally (`app/export.sh`, 42 s, all checks) and in `act` (`app` then `export` jobs green; export 2 min 56 s in a clean container including the template download; `release-builds` artifact uploaded). The GitHub cache hit is seen on the second run after the next push to main |
| PT1f ✅ | CI `release` job on `v*` tags: `gh release create` with three zips and `SHA256SUMS` | A `v0.1.0-rc1` tag produces a release with three assets. 2026-10-05: `release` job (`gh release create`, prerelease, notes from `docs/FIRST-LAUNCH.md`). ✅ 2026-10-05: tag `v0.1.0-rc1` (requested by the owner) → [prerelease](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc1) with Windows (36 MB), macOS (57 MB), Linux (27 MB) zips and SHA256SUMS. Downloaded back: checksums OK, macOS universal + ad-hoc signed, the Linux binary flies the trimmed-flight check. The first attempt's build job was cancelled after 15 min without a GitHub runner (no steps ran; the same job passed on `main` in 1.5 min); `gh run rerun --failed` published it |
| PT1g (Windows ✅) | README "First launch": **macOS 15+ no longer accepts right-click → Open**; use System Settings → Privacy & Security → Open Anyway, or `xattr -dr com.apple.quarantine`. Windows: More info → Run anyway (Smart App Control blocks unsigned apps with no override) | The owner downloads, runs and flies v0.1 on each OS; notes in LEARNINGS.md. 2026-10-05: [docs/FIRST-LAUNCH.md](docs/FIRST-LAUNCH.md) (download check, first launch per OS incl. macOS 15+, controls, radio setup, what v0.1 has, what to report), linked from the README. ✅ 2026-10-05: the owner downloaded `v0.1.0-rc1` and ran it on Windows: "works perfect". Still to try: Linux and macOS |
| **Gate 2** | **"Is it flyable, readable and fun?"** The owner (and ideally 1–2 RC pilots) fly v0.1 with a radio. **Measured in one session:** three circuits, a loop, a roll, a stall and recovery. Each axis (roll, pitch, yaw, throttle) rated −2 (sluggish) … +2 (twitchy) against a real Stik. Orientation read correctly at 100 m with and without auto-zoom. Radio setup time. Frame time p95 and physics µs/tick | Notes and ratings recorded. Any rating beyond ±1 sets the D10 order; M2 reordered if needed |
| D10 ✅ | Sensitivity sweep on the D8 maneuvers and flight modes, in this order: Clp, Cmq, Ixx, Iyy (inventory is 1.7× a Roskam-typical value), servo lag, CLmax/α0, CD0, CG, mass | A table ranking which unknowns matter; decides what to measure next. ✅ 2026-10-05: `research/sensitivity/results.md` (13 unknowns × ±20 %, each varied in the data so derived values follow). Ranking by largest effect: Cnr (spiral +162 %), Cnβ (spiral, dutch roll), Clp (roll τ and rate), CG ±0.02 m (short period, spiral), CD0 (glide ±20 %), mass (−20 % refused by the plausibility range; +20 % → stall +9 %), Ixx (roll τ), Iyy, CL_max (stall speed), Izz, Cmq, Cmα, servo time (none on these outputs). **Measure next:** a weighed build with its CG and a swing test for Ixx (cheap), then rudder authority (β at full rudder) from video or pilot reports |
| **Gate F** ✅ | **Flight-model architecture before M2.** Decided 2026-10-06 by the flight repair ([DECISIONS](DECISIONS.md): local passive loads): wing and tail loads are local elements that reproduce the linear oracle at small angles, i.e. the component buildup grown one surface group at a time, as this gate proposed. Still open: E0b propwash, G2 shaft balance, Gate 2 pilot validation | [Report](docs/research/flight-repair-implementation.md); DECISIONS row of 2026-10-06 |

### M1 follow-up — flight-model consistency (D11, plan review #4)

Found by the knowledge base ([02](docs/research/roadmap-investigations/02-aerodynamics-rc-scale.md), [08](docs/research/roadmap-investigations/08-validation-flight-testing.md)) and re-checked with a probe ([facts re-checked](docs/research/roadmap-investigations/README.md#facts-the-lead-re-checked)). Do it before E3c: an approach at 1.3 V_s flies inside the blend region where the damping changes.

| # | Step | Proof |
| --- | --- | --- |
| D11a ✅ | Re-run D8b/D10 on the post-repair baseline (perturb CG by moving the whole inventory with it, Cnβ by fin area, mass with the gear springs scaled alongside: no "refused" rows) and add the Ultra Stick 25e comparison (Dorobantu 2013 preprint: flight-identified modes, swing-test inertias) at matched CL | `research/sensitivity/results.md` regenerated; its 15 m/s baseline equals the `test_modes` bands; a table with both Sticks; mutation Ixx × 2 moves roll τ ≈ 2×. ✅ 2026-10-06: [`results.md`](research/sensitivity/results.md) now says it is generated and how; no refused rows (mass ±15 %: +20 % leaves the plausible range). **US120:** short period 1.07×, roll τ 2.07× faster, dutch roll 1.26×, spiral unstable (τ −21 s). **25e** (nondimensional, CL 0.28, sim at 18.8 m/s): short period 0.87×, roll pole 2.37×, dutch roll 1.46×; Ixx/(m·b²) 0.0172 vs 0.0282 swing-tested. D10 ranking: fin area and Cnr dominate the spiral (reported as its pole λ: τ crosses infinity near neutral), then Clp, CG, mass, CD0, Ixx. The inventory mass is 2.885 kg, not the 2.601 kg of the predicted-handling table (D1-R1) |
| D11b ✅ (pinned) | Regime-consistency test: linearized Clp, Cmq, Cnr, CLα at α 0…11° | Fails today and the failure is documented; it turns green with D11d and E0a2. ✅ 2026-10-06: [`tests/test_damping_regimes.gd`](app/tests/test_damping_regimes.gd) (17 checks): oracle region equals the data within 1 % (moment transfer from the reference point); worst ratio to the oracle over α 0–11°: **Clp × 1.73, Cmq × 0.28, Cnr × 0.72, CLα × 1.34** (bump at α 7–8°). `KNOWN_DEFECT` pins the defect within ±10 % so CI stays green and any change fails; the fix sets it to false, which turns the same measurements into the ±15 % acceptance test |
| D11c | Minimal vortex-lattice tool (`research/aero/vlm.py`) with known answers, then an AVL comparison pipeline (pinned binary, outside `app/`) for the Stik, Extra and P-51 | Elliptic CLα within 1 %; AR 5 Clp −0.40; derivative table AVL vs VLM vs borrowed vs flight-identified; no data change |
| D11d | Wing strips with the wing-alone section slope and a precomputed induced-flow map; aileron as a strip deflection; ≤ 6 strips per side until Gate P | D11b passes for Clp and CLα; goldens re-recorded deliberately; µs/tick reported |
| D11e | Added-air (apparent) roll inertia as a separate derived term; the owner's swing test (VAL-6) replaces the inventory Ixx | Roll τ within ±30 % of both Sticks, with no damping coefficient tuned to get there (rule 10) |

### Phase H — Headroom, determinism and an extensible state (before E0b, G2 and M5)

Physics costs **501 µs per tick** on the dev VM against the 500 µs budget (rule 7), before propwash, shaft dynamics, turbulence or hull contacts; stalled flight costs ≈ 570 µs. These steps buy headroom and fix the state layout once, so that G2, the E3b anchors and the M5 filters do not each force every golden to be re-recorded. Knowledge: [01](docs/research/roadmap-investigations/01-numerics-architecture-performance.md). H1–H7 and H10 are refactors: goldens stay bit-identical.

| # | Step | Proof |
| --- | --- | --- |
| H1 ✅ | Per-component cost bench (the HUD's F3 line already shows the live tick cost, so no custom monitor) | Table of µs per component. ✅ 2026-10-06: `tests/bench_physics.gd` keeps its headline and adds µs per call of air data, aero, propulsion, gear, `Dynamics.loads`, session loads, derivative and RK4 for trimmed, stalled (α 15°) and on-ground states, plus stalled ticks; `-- --aircraft=<id>` benches any catalog aircraft. Before H2: session loads 73 µs × 5 per tick, derivative 21 µs × 4, aero 45 µs on the oracle path alone (Dictionary access) |
| H2 ✅ | Reuse the tick's loads as the RK4 stage-1 loads (one of five load evaluations per tick is redundant); build deflections once per tick | Goldens bit-identical; −60…70 µs/tick. ✅ 2026-10-06: `rk4_step(..., k1_given)`; `FlightSession._deflections` caches by servo positions (cleared per aircraft). Proof: SHA-256 of state, aux and loads over 1,200 ticks for 4 aircraft × 3 regimes (scripted maneuver, stall, ground) identical before and after; a never-invalidating cache (scratch copy) changes all 12. `test_session_guards.gd` now pins 4 load calls per tick (its k2–k4 failure injections follow the new count) |
| H3 ✅ | Allocation-free `RB.derivative` | 0.0 difference on 10,000 random states. ✅ 2026-10-06: the derivative is written in scalars with every product and sum in the original order (zero terms kept), one allocation instead of ~20; `test_rigid_body.gd` compares it byte for byte with the vector form (kept as `derivative_reference`) on 10,000 seeded states and at rest: 0 mismatches; a reassociated sum (scratch copy) gives 3,123. 21.2 → 2.8 µs per call. With H2: trimmed tick 592 → 400 µs, stalled 526 → 380 µs (dev VM, loaded; same bench and session). Preallocated RK4 stages left for H4 (RK4 overhead ≈ 7 µs) |
| H4 | Compile the model Dictionary into a flat pack with index constants; flatten air data, `_global_loads` and the blend early-out | Goldens bit-identical; trimmed tick ≤ 250 µs on the VM |
| H5 | Flatten `_local_loads` and `ground_contact.loads` | Stalled and spinning tick ≤ 250 µs; goldens bit-identical |
| H6 | Every transcendental call in `physics/` and `sim/` goes through `math3d` (27 direct calls remain), guarded in `test.sh` | The guard fails on an injected `sin(`; goldens bit-identical |
| H7 | 1-ulp sensitivity test: perturb `atan2_`/`sin_` and replay the goldens | Air goldens move < tolerance/1000 (scratch: 1.4e-12 m over 60 s); the test fails when a golden crosses a branch |
| H8 | Extensible state: rigid body + named extras (rotor speed, wash lag, turbulence filters, fuel, battery) with a layout table (name, unit, integrated or per-tick, tolerance); `state_layout` in the trace header; the golden v2 reader keeps reading v1 | Old goldens replay; the header lists the layout; adding an unused extra changes nothing |
| H9 | Golden policy v2: tolerance goldens gated on one CI reference platform (Linux x86-64) with per-component tolerances and a platform stamp; bit-exact replay stays a same-machine diagnostic | CI fails on a mutated tolerance; Windows and macOS runs are reported, not gating |
| H10 | Load contributors (`aero`, `propulsion`, `slipstream`, `gear`; later `wind`, `hull`) behind one interface: `prepare(model) → pack`, `add_loads(state, ctx, out)` | Goldens bit-identical; a no-op contributor changes nothing |
| H11 | Gear stability rule from the eigenvalues of M⁻¹K and M⁻¹C (|λ|max·dt ≤ 0.3) instead of ω·dt < 0.1 (≈ 27× inside RK4's limit and mass-dependent), with contact substeps when a stiffer gear needs them | Stik unchanged; ring-down matches the eigenvalues ±1 %; a 5 mm-sag P-51 test gear lands without energy gain; the air path stays bit-identical |
| **Gate P** | **GDExtension or not.** Decide once H1–H5 are done and the flattened tick has been measured on the owner's slowest machine with the planned M2–M5 features. Choose GDExtension only if the tick stays > 250 µs | Measured table and a DECISIONS row. If yes, a spike: RB derivative + RK4 in C++ (godot-cpp pinned, `-ffp-contract=off`, the GDScript kept as the oracle, CI builds for three OSes), agreement ≤ 1e-14 relative on 10,000 states |

### M2 — Takeoff and landing

Knowledge: [04](docs/research/roadmap-investigations/04-ground-handling-collisions.md) (ground), [03](docs/research/roadmap-investigations/03-propeller-propwash.md) (propwash), [01](docs/research/roadmap-investigations/01-numerics-architecture-performance.md) (contacts and numerics). Recommended order: E3b1–E3b3 and E1b, then E0b (with the P-51 track's `slipstream.gd`, see plan review #4), D11 and E0a2 before E3c.

| # | Step | Proof |
| --- | --- | --- |
| E0a (partly ✅) | Horizontal and vertical tail as separate surfaces (local α from q·l and r·l, downwash lag), geometry read from the model team's `ugly_stik_geometry.gd`; the whole-aircraft derivatives lose their tail share | Linearized Cmα, Cmq, Cnβ and Cnr within ±10 % of the oracle at trim; the modes test stays within its bands; µs/tick reported. ✅ partly, 2026-10-06 (D9-R2): both tails are local surfaces (`v + ω × r`, `r × F`) in free-stream flow and the global derivatives lose their tail share; downwash lag and the propwash factor remain for E0b |
| E0a2 | Tail with its true lift slope and an explicit downwash state lagged by l_t/V (CLα̇, Cmα̇; `CLadot` is in the data but unused); remove the effectiveness fudges | D11b passes for Cmq + Cmα̇; the lag fit is within 5 % ([02](docs/research/roadmap-investigations/02-aerodynamics-rc-scale.md)) |
| E0b | **Propwash on the tail** (momentum theory with contraction, washed fraction of each surface, labeled lag). Moved up from M5: at 5 m/s and full throttle the washed tail sees ≈ 35× the freestream dynamic pressure | At V = 0 and full throttle, elevator and rudder produce moments; at cruise the factor is ≤ 1.3× (the computed bound) |
| E0b1 | Pure `wake()` function: momentum theory, contraction, the closed-form ratio q_wash/q∞ = 1 + 8Ct/(πJ²) | 35.3× at 5 m/s and 1.30× at level-flight thrust at 15 m/s; a mutation fails ([03](docs/research/roadmap-investigations/03-propeller-propwash.md)) |
| E0b2 | Explicit hub position for the Stik (the data puts the prop at the CG; the real hub is 0.414 m ahead), cross-checked with `ugly_stik_geometry.gd`; washed tail pieces from the geometry | `test_aircraft_data.gd` agreement; goldens re-recorded deliberately only if the torque arm changes them |
| E0b3 | Land the tail increment by reviewing the P-51 track's `slipstream.gd`: the washed minus free-stream tail load, outside the oracle blend, opt-in per aircraft, with a C¹ jet edge and a reverse-flow fade | Elevator and rudder moments at V = 0; increment exactly 0 with the wash off; µs/tick reported |
| E0b4 | Wash-speed factor as data (k_s, k_f), set from measured jet decay (Khan) and Selig: the ideal 2·v_i is an upper bound, and the tail sees 12–20× at 5 m/s, not 35× | Static tail centreline 1.0–1.4·v_i; cruise linearization within +12 % of the oracle |
| E0b5 | Wash transport lag as a state (H8) | Step delay = distance / wash speed ± 5 %; frame-rate hash identical |
| E0b6 | Swirl with a bounded factor (ideal swirl yaws as hard as full rudder) | Static swirl yaw ≤ 50 % of full-rudder yaw; sign test: a clockwise prop yaws left on the ground roll |
| E0b7 | Owner field checks (field kit item 4): nose-wheel lift at full throttle, taxi blip, takeoff swing | Video and numbers in a research note; k_s/k_f relabelled "measured (behaviour)"; the Stik's propwash switched on, goldens re-recorded |
| E1 ✅ | Tricycle gear contact points as spring-dampers; stiffness from a natural-frequency rule (`ω·dt < 0.1`) | Drop test: no energy gain; agrees across `h` and `h/2`. ✅ 2026-10-06: `physics/ground_contact.gd` (per wheel `F = max(0, k·δ + c·δ̇)` at the wheel bottom, moment `r × F`, nothing added in the air), optional `landing_gear` data section (Stik: mains 560 N/m, nose 440 N/m from the rule at 240 Hz, ω·dt 0.097, sag 18 mm, ζ 0.4, 0.12 m travel; the loader refuses a CG outside the wheelbase, ω·dt ≥ 0.1 or ζ outside 0.05–2); the wheels leave the crash hull (belly point added), a leg past its travel is a crash. `test_ground_contact.gd` (22): hand-computed loads, restoring signs, drop test with zero energy gain and rest at m·g within 1°, h vs h/2 within 23 µm (horizontal drift 17.9× smaller at h/2: 4th order), the Stik lands from 0.35 m and breaks its gear from 2.0 m. Trace rows byte-identical (`7d2f8a4c…`), goldens unchanged, 4 mutations caught, 510 µs/tick on the VM (was 526). [Report](docs/research/landing-gear-contact-e1.md). Extra and P-51 keep D9d (wheels crash) until their generators add the section. Found by the real ground: `slow_flight` and `spin_right` sank to −78 m and −55 m on HEAD (nothing acted below the ground); both now start at 150 m, their physics unchanged. **Finding for the model team:** the visual main axle (x_aft 0.10 m) sits ahead of the CG |
| E2 ✅ | Rolling friction (labeled guess), nosewheel steering, brakes off | Taxi a figure-eight. ✅ 2026-10-06: tyre forces in the ground plane along each wheel's heading (rolling resistance C_rr·N, slip-angle side force saturating at μ·N, friction circle), nose wheel steered 20° by the rudder servo; dry-pavement values C_rr 0.04 (estimated), μ 0.8 and peak slip 6° (borrowed from JSBSim); the loader requires them with the gear and bounds the side-force rate (λ·dt 0.31 ≤ 0.5). `test_ground_friction.gd` (26): hand-computed loads, no power over 2000 random states, coast-down at C_rr·g within 0.02 %, turn radius 0.977 m vs kinematic 0.964 m, tip-over 4.50 m/s² vs rigid oracle 4.47 (real gear 78 % of it, roll compliance), h vs h/2 2.9 µm, session figure-eight at idle (two full turns, no wheel lifted). Trace rows byte-identical, goldens unchanged, 6 mutations caught, air cost unchanged (511 µs/tick). [Report](docs/research/ground-friction-e2.md). **Findings:** the Stik tips before it slides (full steer above ≈1.85 m/s); idle (2.6 N) out-pulls rolling resistance (1.1 N) on pavement. Not validated: turn radius, coast-down and idle creep on a real Stik |
| E3 | Start on the runway: takeoff, circuit, landing, nose-over, in four sub-steps | Trace of a full circuit |
| E3a ✅ | Field surfaces under the wheels: runway (mown strip), mown and rough scale μ and C_rr | Coast-downs and idle on each surface. ✅ 2026-10-06: `app/data/ground/surface_friction.json` (FlightGear `grass_rwy`, `Grass`, `Grassland` factors; rough rolling estimated), `physics/ground_surfaces.gd` builds a lookup from the field's rectangles (runway over mown over rough); each wheel finds its own surface; `FlightSession.set_field`, invalid table refuses the flight. `test_ground_surfaces.gd` (28): refusals, lookup on the real field, hand-computed scaled loads, no power across edges, coast-downs within 1 % (runway 0.979 vs 0.981 m/s²), idle holds on the runway (2.6 N vs 2.8 N) where pavement rolled 21 m. 5 mutations caught; trace rows identical. Rolling creep 0.05 → 0.01 m/s (still 0.9 cm/s against a steady push). [Report](docs/research/ground-surfaces-e3a.md) |
| E3b | Runway start: parked at the threshold, engine at idle, true stiction (no creep); takeoff roll | Sits still at idle; full-throttle ground roll and lift-off speed against a hand estimate |
| E3b1 | Stick/slip anchor per wheel in the per-tick state (mode, anchor north/east), switched only in `pre_step`; while slipping, the force is the E2 law bit for bit ([04](docs/research/roadmap-investigations/04-ground-handling-collisions.md)) | Parked at idle for 60 s: drift < 2 mm (today 0.9 cm/s); breakaway at C_rr,static·N ± 1 %; goldens and trace rows unchanged |
| E3b2 | Runway start: static solve on the gear at the threshold, engine at idle, anchors stuck | After 1 s: \|v\| < 1e-6 m/s, ΣF_n = m·g ± 0.1 %, attitude within 0.1° of the solve |
| E3b3 | Takeoff roll against the hand integral (APC table, C_rr per surface; no propwash until E0b3) | Distance to 10 m/s within 3 % of 4.69 m (runway, elevator neutral); with full up-elevator the nose wheel unloads at 11.3 ± 0.5 m/s after 6.0 m; recomputed when E0b lands |
| E1b | Continuous touchdown force for every contact (Hunt–Crossley or ramped damping, chosen by the order test) plus rebound damping. Today the damper jumps by tens of newtons at first contact, which drops RK4 to first order ([01](docs/research/roadmap-investigations/01-numerics-architecture-performance.md)) | No force step at first contact; h/h₂ convergence ratio ≥ 8 through a touchdown (≈ 2 today); drop test without energy gain |
| E3c | Circuit and landing on the runway | Trace of a full circuit: takeoff, pattern, landing, roll-out |
| E3c1 | Closed-loop approach-and-flare maneuver for tests (`sim/maneuvers.gd`); needs D11d and E0a2, because the approach flies in the blend region | Touchdown sink ≤ 1 m/s; roll-out stops on the runway; no crash |
| E3c2 | Full circuit trace | Trace and capture: takeoff, pattern, landing, roll-out, no hull contact |
| E3d | Nose-over and wingtip scrape: which ground touches are crashes | A wingtip touch at walking pace is not a crash; a nose-in at speed is |
| E3d1 | Hull points become frictional contacts with per-component data (stiffness, μ, crash normal speed: wingtip 1.5, belly 2.5, tail 1.0 m/s, estimated) and anchors; one typed contact list replaces `crash_hull` | A wingtip at walking pace rocks back without a crash; a nose-in at 10 m/s crashes; a belly touch at 1 m/s sink slides to a stop |
| E3d2 | Prop-strike event and crash reasons by component, in the UI and the trace | The message names the component and the speed; a prop strike alone stops the engine and keeps the airframe (owner decides whether it is a crash) |
| E4 | Golden flight of a full circuit (the mechanism exists since D8a) | A replayed circuit matches its recording within the H9 tolerances; C_rr + 10 % and anchor stiffness × 2 are each detected |
| PT2 | Playtest v0.2 | Owner flies takeoffs and landings; field kit item 5 (pull test on three surfaces, coast-down, idle creep, takeoff distance) recorded with kind `measured` |

### M2+ — Ground breadth (after PT2; with each aircraft track)

Knowledge: [04](docs/research/roadmap-investigations/04-ground-handling-collisions.md).

| # | Step | Proof |
| --- | --- | --- |
| E5a | Taildragger gear for the Extra and P-51 through their generators (tailwheel steered by the rudder, caster option); first recheck the generated gear geometry, which sits 31–33° from vertical | Sits tail-down at the geometric attitude ± 0.5°; yaw eigenvalue vs the bicycle model ± 10 %; a free caster diverges at 5 m/s |
| E5b | Nose-over (tail up, soft spot): friction needed is ≈ 0.35–0.37 for the Extra and P-51, which rough grass plus a soft spot can reach | The tail lifts at the rigid-gear oracle's d/h ± 2 % |
| E5c | Brakes (JSBSim formula, brake groups, channel or rudder differential) | Straight braking deceleration μ_brake·g ± 2 % |
| E5d | Retracts (unblocks P51-11 together with DATA-10) | Cycle time matches the data; a gear-up landing at 0.8 m/s sink slides |
| E6a | Wheel-radius contact geometry with per-wheel diameter; rolling resistance by wheel size and surface after PT2's measurements | Static attitude < 1 mm from the analytic circle; E3a reproduced for 76 mm wheels |
| E6b | Terrain contact on the float64 sampler of LANDSCAPE L12a. Never use Godot physics queries in the simulation: they are 32-bit and synchronised with frames | All-zero grid: trace bytes identical; holds on 3° grass, rolls on pavement; ≤ 10 µs/tick |
| E6c | Trees as float64 capsules and crown cylinders with a grid broad phase (L14) | A scripted flight into a tree crashes at the right tick ± 1; flying between trees does not |
| E7a | Hand, catapult and bungee launch: a scenario start state, and a tension-only spring with release for the bungee | The start state equals the requested (v, θ); bungee energy balance within the damping losses |
| E7b | Part loss after a component crash (wingtip, gear leg) | The lost-tip roll moment equals the strip removal in `linearize.gd` |

### M3 — The radio, done properly

Knowledge: [06](docs/research/roadmap-investigations/06-radio-input-servos-latency.md). Proposed convention (owner decides at D6d): with a radio, the simulator is receiver + servos + linkages, and the radio does expo, rates, mixes and trims. EdgeTX sends channel outputs that are already shaped, so the simulator never shapes them again.

| # | Step | Proof |
| --- | --- | --- |
| F1 | Input report: `-- --input-report` lists each device (GUID, name, VID:PID, axes moved, min/max, mean event spacing = report interval) | Fake-device headless test; the owner's D6d run gives one F4 row per OS |
| F2 | Linkage trim: the solved start trims become a per-aircraft `controls.linkage_trim` at a stated reference speed (like a clevis or subtrim), applied for every device, with the radio's trims centred. Answers the D6d trim question: the Stik's solved elevator trim (+26 % of throw) is beyond EdgeTX's default ±25 % trim range | A 20 m/s start keeps the reference trim; hands-off at the reference speed holds; a double-trim mutation fails |
| F3 | Replug and focus-loss polish on top of D6a's failsafe: the exact device key, else the same family with confirmation; re-arm after every axis reset; `ignore_joypad_on_unfocused_application` pinned; the Windows disconnect hang in 4.7 ([#121539](https://github.com/godotengine/godot/issues/121539)) checked on 4.8 | Scripted unplug/replug/focus log: never a non-idle throttle before re-arming |
| F3b | Measure and cut the per-event `_input` cost (4 axes at 1 kHz) | µs per frame before and after; e2e radio tests unchanged |
| F4 | Compatibility table: device, firmware, OS, Godot version, USB mode, axes, report interval, usable channels | One row per tested device |
| F5 | Setup screen (= UI-10b/12): pick a device; raw → calibrated → surface monitor; warnings for Classic USB mode on Linux (it becomes an SDL gamepad) and for RF modules left on (4 ms reports instead of 1 ms) | Owner sets up a new radio without editing files |
| F6 | Measured latency: an on-screen latency patch filmed at 240 fps (≥ 20 trials), with VSync on and off and frame caps, on the owner's machines. Proposed budget: ≤ 50 ms median, ≤ 70 ms p95 at 60 Hz. Godot samples joysticks once per rendered frame | Median/p95 table against the budget; decisions on `physics_jitter_fix` and on a threaded reader recorded |
| F7 | Servo data schema per surface (speed per 60°, voltage, torque, deadband, frame period, arm travel), no behaviour change | `--trace` bytes and goldens identical; the loader refuses a missing unit or kind |
| F8 | Servo L2: deadband and a first-order lag (≈ 0.075 s measured on hobby servos) plus slew. Today a 5 % stick move finishes in 7 ms | Analytic step tests; frame-rate hash identical; goldens re-recorded deliberately; owner A/B |
| F9 | Servo L3: hinge moments (estimates), torque–speed derating, blowback (the Stik's elevator from ≈ 34 m/s) | The hold angle equals the analytic value; < 30 % change at 15 m/s; a dive shows blowback; µs/tick |
| F10 | Expo and rates for keyboard and gamepad only (EdgeTX expo formula), never applied to a radio | Formula tests; a "shape a radio" mutation fails |
| F11 | Extra channels: rates switch, flaps, panic, trainer | e2e: a button toggles the rates; menus unaffected |

### M4 — Nitro

Knowledge: [05](docs/research/roadmap-investigations/05-propulsion-engines-motors.md), [03](docs/research/roadmap-investigations/03-propeller-propwash.md) (G1), [10](docs/research/roadmap-investigations/10-audio-perception-presentation.md) (G3). The P-51 track committed a first shaft balance (P51-06) and `turbine.gd` (AV-05) on 2026-10-06; G2a brings the shaft into the H8 state for every aircraft.

| # | Step | Proof |
| --- | --- | --- |
| G1a | Propeller tables Ct, Cp(J, rpm) with per-run provenance (file, sha256, true diameter). Today a measured 11×6 at ≤ 6,259 rpm stands in for the Stik's 12×6 at 11,149 rpm, and UIUC data show Ct rising ≈ 50 % with rpm | The loader reproduces every file row at its knot; duplicate UIUC rows removed |
| G1b | Out-of-range flags (J gap, J beyond the table, rpm outside it) counted in the trace | Counters fire on crafted queries; a 40 m/s dive reports its out-of-range ticks |
| G1c | One offline BEM tool (generalised from the P-51's `bem.py`) producing four-quadrant tables | Within ±10 % Ct and ±15 % Cp of UIUC 11×6 and 12×6E at matched rpm; windmill branch present |
| G1d | Windmilling and stopped-propeller drag (today a stopped prop has no drag) | Dead-stick glide with stopped and windmilling props ordered and within bands of D8a's L/D 8.46 (no prop) |
| G1e | Propeller normal force and P-factor at the hub (blade term plus jet term) | Sign tests; within ±30 % of the BEM table (12×6: 0.11 N·m at 15 m/s and α 10°; P-51 26×12: 2.3 N·m) |
| G2a | Shaft balance I·dω/dt = Q_engine(ω, throttle, σ) − Q_prop(ω, V_air) − Q_friction for every aircraft. Rotor speed is integrated in RK4 (H8), the inflow is air-relative (wind included), and each engine's torque-curve shape is documented | Throttle-step convergence ratio ≈ 16 per halving; in-flight unloading (+14 % rpm at 35 m/s for the .61) vs the hand calculation; data without a shaft section stays bit-identical |
| G2b | Rotor-acceleration reaction −dh/dt, so torque roll arrives with the throttle punch (0.83 vs 0.05 N·m on its first tick) | Sign and size test, plus its mutation |
| G2c | Throttle actuator: servo slew, carburettor admitted-fraction table, combustion delay | Step trace vs the owner's phone-audio rpm trace (VAL-7) within a band set beforehand |
| G2d | Engine states OFF / CRANKING / RUNNING in the H8 state; stop below 0.8·idle (JSBSim rule); starter; `engine_running` retired | An idle trimmed below the stall rpm stops within 2 s and stays stopped |
| G2e | Realism layer, deterministic and off by default: rich-idle flooding, plug cool-down, lean cut on a fast throttle | Unit test per state; with the toggle off, goldens unchanged |
| G3a | Per-tick sound snapshot (rpm, crank angle, load, thrust, airspeed, position) and tone data (`engine.cycle`, cylinders, blades). Audio reads only the snapshot | Trace and frame-rate hashes identical with sound on and off |
| G3b | Low-latency audio (a ~50 ms queue; the placeholder adds ~186 ms) with a wavetable core (3.1 vs 14.8 ms of CPU per second of audio) | An rpm step is heard within 70 ms; no underruns at 30/60/144 fps |
| G3c | Engine tones (firing at rpm/60 for a 2-stroke) and propeller tones (blade passing at blades·rpm/60), levels vs rpm and load | Offline Goertzel: peaks at the predicted orders ≥ 40 dB above the floor |
| G3d | Own propagation: travel delay and Doppler from geometry, spherical spreading, ISO 9613-1 air absorption. Godot's 3D Doppler (no travel delay) and distance filter (−16 dB at 25 m) are turned off | Pitch ratio ±0.5 %; onset delay ±1 ms; −23.1 dB from 7 to 100 m |
| G3e | Dead stick, windmill and airframe noise; load timbre from G2; ground reflection; buses and a limiter (UI-08) | Offline spectra per state; bus mute test |
| G3f | Fit to the owner's recordings (.61 + 12×6 at 3 m, 7 m and a fly-by, with a tachometer; licence chosen by the owner) and a blind ABX test | Orders 1–8 within 3 dB at three rpm points; ABX results in the PT4 notes |
| G4a | Fuel tank state and burn map; the engine stops when empty | Full-throttle burn-out time within 5 % of the hand calculation |
| G4b | Time-varying mass, CG and inertia from the tank (later the battery), updated once per tick | Trim drift trace over a tank; CG shift vs the hand calculation; goldens without fuel unchanged |
| G5 | Several power plants (`powerplants[]`, with DATA-14) | Counter-rotating twin: net reaction torque 0 ± 1e-12; engine-out yaw sign |
| PT4 | Playtest v0.4 | Owner judges throttle response, idle reliability and sound with the PT4 checklist in [05](docs/research/roadmap-investigations/05-propulsion-engines-motors.md) |

#### M4b — Electric propulsion (proposed; most RC pilots fly electric)

| # | Step | Proof |
| --- | --- | --- |
| EL1 | Drela three-constant motor (Kv, R, I0), averaged ESC and an ideal battery; an electric Stik variant | Operating point vs the hand calculation; the variant trims and passes the handling test |
| EL2 | LiPo battery: open-circuit voltage vs state of charge, internal resistance, one RC pair; state of charge in the H8 state | Voltage-sag trace on a throttle punch vs the hand calculation |
| EL3 | ESC behaviours (Hobbywing manual values): start ramp, soft and hard low-voltage cut-off, brake vs freewheel, signal-loss cut, arming | Unit test per mode; the brake gives a stopped-prop glide |
| EL4 | Winding temperature with R(T); ESC derating | Sustained full throttle plateaus; derating at the threshold |
| EL5 | Static operating point vs measured data (a test-stand dataset or the owner's wattmeter) | Current and thrust within ±10 % |
| EL6 | Flight time vs telemetry (mAh per minute of a pattern) | Within ±15 % |

Turbine: AV-05a (spool ≈ 3 s up, ≈ 1.9 s down) and AV-05b (ECU states) belong to the [Avanti plan](docs/AVANTI-S-PLAN.md), using [05](docs/research/roadmap-investigations/05-propulsion-engines-motors.md).

### M5 — Air and polish

Chosen by what the playtests ask for:
- wind, then gusts ([WIND-PLAN](docs/WIND-PLAN.md), M5-W00…W08, Gates W-A/W-B)
- exhaust smoke and a smoke pump ([SMOKE-PLAN](docs/SMOKE-PLAN.md), SM-00…09)
- swirl and wing-wash effects of the propeller (tail propwash moved to E0b)
- stall hysteresis and a post-stall extension
- ground effect
- camera options (now VQ-03 in [VISUAL-QUALITY-PLAN](docs/VISUAL-QUALITY-PLAN.md))
- settings persistence (now UI-07/08 in [MENU-PLAN](docs/MENU-PLAN.md))
- pilot observation sessions
- web export, if wanted

Proposed sub-steps (plan review #4; knowledge: [07](docs/research/roadmap-investigations/07-atmosphere-wind-turbulence.md), [02](docs/research/roadmap-investigations/02-aerodynamics-rc-scale.md), [03](docs/research/roadmap-investigations/03-propeller-propwash.md), [06](docs/research/roadmap-investigations/06-radio-input-servos-latency.md)). [WIND-PLAN](docs/WIND-PLAN.md) keeps its M5-W numbering; *new* marks what extends it.

| # | Step | Proof |
| --- | --- | --- |
| M5-ATM-1 | Atmosphere module: ISA plus temperature, QNH and humidity (ideal gas + Buck); the default returns the literal 1.225 | Table within ±0.05 %; goldens byte-identical (computing 1.225 from the constants gives 1.2250000181) |
| M5-ATM-2 | Field elevation and weather in the field and weather data; ρ flows through the session, trim, HUD and trace | A trim at σ 0.78 needs V × 1.132 at the same α |
| M5-ATM-3 | Engine torque × σ in G2a; without it a hot, high field raises rpm while static thrust stays constant | Static thrust ≈ σ·T₀ at σ 0.78; the "ignores σ" mutation fails |
| M5-W04a/c | OU turbulence parametrised as the MIL-HDBK-1797 first-order form (σ from W20, scale length from height); *new:* xoshiro128** generator with the seed in the trace header | Welch PSD vs MIL; the first 1000 outputs equal the C reference |
| M5-W05c/d | Wind and its gradient sampled per RK4 stage; each surface sees v + ω×r − G·r; *new:* Dryden p, q, r gusts | Rotational equivalence to 1e-12 (rolling at p in still air = a field with ∂W_z/∂y = −p); double-count guard |
| M5-W08a | *New:* treeline wake from the field data (height, porosity): velocity deficit and turbulence factor. The flying area sits in the wake for most wind directions | Profiles at 2/5/10/20/30 tree heights match the sourced endpoints; owner A/B |
| M5-W08b | *New:* Allen (2006) thermals with drift | Published check case; mass balance ≈ 0 |
| M5-W08c/d | *New:* slope lift (cylinder, then a panel method on L13 hills); dynamic-soaring shear layer (long term) | Cylinder closed form; Rayleigh-cycle energy gain |
| M5-W-T | Trace columns for ρ, wind, gust rates and seed; replay from recorded wind (turbulence is bit-identical only per platform) | Cross-platform replay equal with recorded wind |
| M5-GE-1/2 | Ground effect on the wing strips (per-strip height), then on the tail downwash | Flare: ≈ 4° extra up-elevator at h/b 0.17 (±50 %) |
| M5-STALL-1 | Per-strip 360° tables (Viterna) in data v2 | Continuity sweep; post-stall CL/CD ≈ 1/tan α |
| M5-STALL-2 | Goman–Khrabrov separation state per strip (stall hysteresis) | α̇ = 0 is bit-identical to static; a closed hysteresis loop; cycle passivity |
| M5-STALL-3 | Control effectiveness in stalled flow | Slow-flight aileron-reversal sign test |
| M5-SPIN-1/2 | Fuselage crossflow segments (knife edge), then tail shielding in spins | Knife-edge β band; spin recovery turns vs a pilot band |
| M5-PROP-1…3 | Wing-root wash and swirl roll; 3D hover (torque roll, vortex ring in tail slides); a measured diffusion profile | Static roll ≈ 40 % of torque ±15 %; a scripted hover at T/W ≥ 1 |
| M5-AIDS-1…4 | Gyro "receiver", off by default: rate damping, envelope and self-level, panic recovery, trainer with two devices | Gust roll rate decays ≥ 2× faster; ≥ 99 % of 100 random attitudes recover above 10 m; no-aid goldens identical |

## Parallel programs (plan review #4)

Three programs run beside the milestones. Each step still has one proof.

### VAL — validation against real aircraft

Knowledge: [08](docs/research/roadmap-investigations/08-validation-flight-testing.md). Rule 6 needs independent data. Misses are reported in a generated dashboard, not as CI failures; values used for tuning are flagged (rule 10). VAL-1 and VAL-2 became D11a.

| # | Step | Proof |
| --- | --- | --- |
| VAL-3 | `openrc-reference v1` reference files and a generated `research/validation/dashboard.md` (sim, reference, ratio, band, source, kind, used-for-tuning) | US120 and 25e rows present; Clp × 2 turns the roll rows red |
| VAL-4 | Metamorphic tests: mirror symmetry, Froude invariance, energy non-increase | Pass at 1e-12 / 1e-9; the named mutations fail |
| VAL-5 | Owner ground kit (field kit item 1) | Measurements JSON and photos in `research/validation/VAL-5/`, kind `measured` |
| VAL-6 | Swing tests: bifilar Ixx and Izz, compound Iyy, the rig validated on a plank | Plank within 3 % of theory; Stik inertias with an error budget |
| VAL-7 | Static thrust, rpm (tachometer or audio FFT) and throttle-step lag (field kit item 3) | Compared with 41.3 N, 11,149 rpm and τ 0.25 s |
| VAL-8 | Tripod-video flight cards: roll rate, stall speed, glide, takeoff and landing roll | Frame-count CSVs; dashboard rows |
| VAL-9 | Log tooling outside `app/`: ArduPilot `.bin` → `openrc-flightlog v1` CSV, plus replay scored by Theil's inequality coefficient (TIC) | Synthetic round trip TIC < 0.02; Clp × 1.5 gives > 0.1 |
| VAL-10 | Replay the public UMN "Thor" flights 44/45 doublets through a 25e test aircraft | TIC table vs Dorobantu's 0.07 / 0.12 / 0.26 |
| VAL-11 | Passive-logger flights: a flight controller wired only as a logger; pitot calibrated by reciprocal GPS runs | Logs and dashboard rows with uncertainties |
| VAL-12 | Equation-error identification of Clp, Clδa, Cmq, Cmδe, Cnβ, Cnr with error bounds and held-out validation | Estimates ± 2σ; held-out TIC < 0.25 |
| VAL-13 | Monte-Carlo envelope over the unknowns by kind and uncertainty (200 seeded runs) | 5–95 % bands; each reference marked inside or outside |
| VAL-14 | Pilot protocol: tasks with desired and adequate standards scored from traces, Cooper–Harper plus the −2…+2 per axis, blind A/B | Protocol, one owner session, A/B binomial p |
| VAL-15 | Extra and P-51 contrast rows in the same dashboard (EX-09, P51-09) | Rows per aircraft, labelled |

### DATA — aircraft data v2 and the pipeline

Knowledge: [09](docs/research/roadmap-investigations/09-aircraft-data-pipeline.md).

| # | Step | Proof |
| --- | --- | --- |
| DATA-1 | P-51 `build_geometry`, `compile_geometry` and `derive_physics --check` in CI next to the Extra's | CI fails on a stale copy (scratch clone) |
| DATA-2 | Cheap stall-start solve: one bisection takes 110 ms of the 119 ms aircraft load | Solved angles unchanged ≤ 1e-12 rad; load ≤ 15 ms; goldens unchanged |
| DATA-3 | Hash the file bytes (today a re-serialized copy is hashed) and write the hash in the trace header | One changed late digit changes the hash |
| DATA-4 | JSON Schema 2020-12 for v1, checked in CI | The schema rejects every shape mutation the loader rejects |
| DATA-5 | One shared `tools/aircraft/` library for the Extra and P-51 derivations | Both `--check` outputs byte-identical |
| DATA-6 | Inventory shapes (box, cylinder, tube, sphere, point) | Closed-form inertia tests to 1e-12 |
| DATA-7 | A shared `openrc-geometry v1` schema for the three aircraft | Compiler outputs byte-identical; the model teams' verify scripts pass |
| DATA-8 | `openrc-aircraft v2`: an ID-keyed component tree (surfaces with panels and controls, bodies, rotors, power plants, contacts, point masses), with the derivatives kept as an optional oracle; `migrate_v1_to_v2.py`; the loader accepts both | Model dict identical (0 ulp) through both paths; every golden bit-for-bit |
| DATA-9 | Controls as data: a mixer matrix replaces the hard-coded aileron, elevator and rudder | Stik goldens bit-for-bit; elevon test wing |
| DATA-10 | Kinematic actuators for flaps and retracts (unblocks P51-11) | Flap traverse time; the P-51 trims with take-off flap |
| DATA-11 | Variants as merge patches (CG, fuel, prop) | A CG-aft variant moves the short period as the static margin predicts |
| DATA-12 | Plausibility gates per aircraft class (static margin, wing loading, T/W, inertia radii) as warnings | A 2 % static margin warns, it does not refuse |
| DATA-13 | AVL backend in `tools/aircraft/` (offline, pinned, not bundled: GPL tools stay outside `app/`) | Known rectangular-wing case; lattice refinement < 2 % |
| DATA-14 | Power units as a list driving thrusters (with G5) | Engine-out Cn = T·y/(q S b) to 1e-9 |
| DATA-15 | Section polars with Reynolds number for the strips | The linear region reproduces the oracle |
| DATA-16 | Aircraft packages in `res://` and `user://` with a manifest and licences; data only (no scripts, no `.tres` or `.pck`) | A copied package flies; a script file is refused; 50 aircraft listed in < 50 ms |

### PERC — what the pilot sees and hears

Knowledge: [10](docs/research/roadmap-investigations/10-audio-perception-presentation.md). Rendering itself belongs to the visual-quality track.

| # | Step | Proof |
| --- | --- | --- |
| PERC-1 | A "natural" field of view from screen size and viewing distance: the 50° default shows the airplane at 0.63× real size on a 27″ screen at 60 cm | Pure-function test; capture span ± 1 px |
| PERC-2 | Auto-zoom exponent (on-screen size ∝ d^−k with k = 1, 0.5 or 0) and a keep-ground-in-view variant (VQ-03 scope). Today's auto-zoom holds 30 px from 39 to 349 m and erases the approaching/receding cue | Size law within 5 % from 20 to 300 m |
| PERC-3 | Moving-clip blinded orientation kit (L6c design), four camera modes | Error rate and response time per mode: a Gate 2 number |
| PERC-4 | Minimum thickness or a 1 px outline for sub-pixel parts at distance | Flicker in a 150 m roll reduced by ≥ 50 % |
| PERC-5 | Prop disc above a blade-rate threshold (with the model team) | No stroboscopic blades at 30/60/144 fps |
| PERC-6 | Accessibility: an optional orientation glyph and a pattern-based top/bottom livery | Toggle test; `--trace` identical |
| PERC-7 | Frame pacing on the owner's machine (60/144 Hz, VSync modes) | p95 and judder per mode |
| PERC-8/9 | Head tracking (OpenTrack UDP, camera only); a VR spike (OpenXR) | Replayed camera path; simulation trace unchanged |

### Owner's field kit (one afternoon with a real Stik)

The cheapest, most valuable independent data. Each item names the steps it feeds; record the method, photos and raw numbers.

1. Weight, three-scale CG, throws at five stick positions, trims after a flight, servo speed (240 fps phone video) → VAL-5, D11, F7.
2. Bifilar swing test for Ixx (≈ $10, 2 h), then Izz and Iyy → VAL-6, D11e. This is the most valuable single measurement: roll inertia explains most of the 2× roll gap.
3. Static thrust (luggage scale) and rpm (optical tachometer or phone audio) at full throttle and idle; a throttle-step audio recording → VAL-7, G1, G2c.
4. Nose-wheel lift at full throttle from standstill, taxi blip, takeoff swing (video) → E0b7.
5. Pull test with a luggage scale on the runway, mown and rough grass; coast-down; idle creep; takeoff distance → E3b, PT2.
6. Engine sound at 3 m, 7 m and a fly-by, with a tachometer → G3f.
7. Radio: `--input-report` on each OS; the latency video → F1, F4, F6.

Open question: does a built Das Ugly Stik 60 exist (the owner's or a club member's)? Without one, items 1–5 use the closest built sport plane, labelled as such.

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
| Dorobantu et al. 2013 (Ultra Stick 25e flight-identified model, [doi:10.2514/1.C032065](https://doi.org/10.2514/1.C032065)) ✅ a readable preprint was found on 2026-10-06 ([08](docs/research/roadmap-investigations/08-validation-flight-testing.md)); its modes and swing-test inertias feed D11a | D8b, D11a | done |
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

## Plan review #4 (2026-10-06): deep research before M2 grows

Ten research documents ([knowledge base](docs/research/roadmap-investigations/README.md)), one per phase or cross-cutting area: about 74,000 words and about 350 sources (papers, NASA/NACA reports, simulator source code from JSBSim, YASim, CRRCSim, PicaSim and ArduPilot, Godot and EdgeTX source, manufacturer data). Each document read the code and the existing research (RESEARCH.md, WIND-PLAN, the E1–E3a reports) and builds on them. The lead re-checked the key numbers ([list](docs/research/roadmap-investigations/README.md#facts-the-lead-re-checked)) and resolved the points where the documents disagree ([table](docs/research/roadmap-investigations/README.md#where-the-documents-disagree-and-the-resolution-used-in-roadmap)). The web-search budget ran out partway through; sources each document could not open are marked "search result only".

**Kept, because they are sound:**
- own float64 6-DOF physics with RK4 at 240 Hz;
- the linear model as the test oracle, and the component buildup (Gate F);
- provenance on every number;
- discrete modes switched in `pre_step`;
- golden flights;
- the radio's arming and failsafe rules.

| # | Finding (evidence) | Change |
| --- | --- | --- |
| 1 | **No physics headroom.** 501 µs per tick against the 500 µs budget, before propwash, shaft dynamics, turbulence and hull contacts; stalled flight ≈ 570 µs. One of the five load evaluations per tick is redundant, and removing allocations makes the derivative 11× faster ([01](docs/research/roadmap-investigations/01-numerics-architecture-performance.md)) | Phase H (H1–H5) before E0b, G2 and M5; Gate P decides on GDExtension with numbers from the owner's slowest machine |
| 2 | **Damping changes with the regime.** Clp −0.45 → −0.77 and Cmq −13.6 → −4.4 between α 6° and 10° (oracle → local model), where an approach flies; re-measured by the lead ([02](docs/research/roadmap-investigations/02-aerodynamics-rc-scale.md)) | D11b red test, fixed by D11d (strips) and E0a2 (tail) before the E3c landing |
| 3 | **The roll gap is mostly inertia.** Roll τ is 2.1× too fast against two flight-identified Sticks. Ixx/(m·b²) is 0.0172 in the sim against 0.028 for both swing-tested UMN Sticks; Clp explains only 1.15×; added air mass (≈ 23 % of Ixx) is missing. The 1.45× pitch gap is obsolete since D1-R1 ([02](docs/research/roadmap-investigations/02-aerodynamics-rc-scale.md), [08](docs/research/roadmap-investigations/08-validation-flight-testing.md)) | D11a, D11e; rule 10 (measure, don't tune); the owner's swing test (field kit item 2) |
| 4 | **Validation numbers went stale silently.** `research/sensitivity/results.md` predates the repair, and the sweep now refuses three of its top rows ([08](docs/research/roadmap-investigations/08-validation-flight-testing.md)) | D11a regenerates it; the VAL-3 dashboard is generated from code |
| 5 | **A second flight-identified reference is available:** the Dorobantu 2013 Ultra Stick 25e preprint (modes, swing-test inertias, servo model) and public UMN flight logs ([08](docs/research/roadmap-investigations/08-validation-flight-testing.md)) | D11a, VAL-10; research-track row closed |
| 6 | **The state layout would be retrofitted again and again.** Rotor speed (G2), wheel anchors (E3b), wash lag (E0b), turbulence filters (M5), fuel and battery (G4, EL2) all add state. Holding rpm constant across RK4 stages becomes a first-order error once rpm depends on airspeed ([01](docs/research/roadmap-investigations/01-numerics-architecture-performance.md), [05](docs/research/roadmap-investigations/05-propulsion-engines-motors.md)) | H8 extensible state and H9 golden policy before G2; rotor speed integrated in RK4 |
| 7 | **Touchdown force jump.** The gear damper jumps by tens of newtons at first contact, dropping RK4 to first order and making landing goldens fragile across platforms ([01](docs/research/roadmap-investigations/01-numerics-architecture-performance.md), [04](docs/research/roadmap-investigations/04-ground-handling-collisions.md)) | E1b before E3c and E4 |
| 8 | **Torque roll arrives late, and dead-stick physics are missing.** The −dh/dt reaction is absent (0.83 vs 0.05 N·m on a throttle punch's first tick), a stopped prop has no drag, and engine power ignores air density ([05](docs/research/roadmap-investigations/05-propulsion-engines-motors.md), [07](docs/research/roadmap-investigations/07-atmosphere-wind-turbulence.md)) | G2b, G1d, M5-ATM-3 |
| 9 | **Propwash: the formula is right but gives an upper bound.** 35× at 5 m/s is ideal momentum theory; measured jet decay at the tail gives 12–20×, and only ≈ 37 % of the stabilizer is washed. The P-51 track's `slipstream.gd` (labelled "P51-12", an unregistered ID) has the right increment design but no reverse-flow cut-off, no lag and a constant wash factor ([03](docs/research/roadmap-investigations/03-propeller-propwash.md)) | E0b1–E0b7; the owner decides who owns `slipstream.gd` |
| 10 | **Propeller data used outside its range.** An 11×6 measured at ≤ 6,259 rpm drives a 12×6 at 11,149 rpm, while UIUC data show Ct rising ≈ 50 % with rpm ([03](docs/research/roadmap-investigations/03-propeller-propwash.md)) | G1a–G1c (rpm as a table dimension, one BEM tool) |
| 11 | **Radio.** EdgeTX sends shaped channel outputs; Godot samples joysticks once per rendered frame; the sim's own latency (≈ 42 ms) already exceeds a real link's, so no RF delay is added. The solved elevator trim exceeds the radio's trim range ([06](docs/research/roadmap-investigations/06-radio-input-servos-latency.md)) | F1–F11; F2 linkage trim answers the D6d question |
| 12 | **Data v1 fits one airplane shape.** Loading an aircraft takes 110 ms (one bisection); the P-51 pipeline has no CI check; the data hash is not the file's ([09](docs/research/roadmap-investigations/09-aircraft-data-pipeline.md)) | DATA-1…16; v2 before more generated aircraft |
| 13 | **Electric propulsion is absent,** although most RC pilots fly electric ([05](docs/research/roadmap-investigations/05-propulsion-engines-motors.md)) | M4b (EL1–EL6) after G2 |
| 14 | **Perception.** The 50° camera shrinks the airplane to 0.63× real size; auto-zoom erases the approaching/receding cue; the sound queue adds ≈ 186 ms; Godot's 3D Doppler has no travel delay ([10](docs/research/roadmap-investigations/10-audio-perception-presentation.md)) | PERC-1…9, G3a–f |
| 15 | **Wind and atmosphere.** Sample the wind and its gradient per stage; xoshiro128** is bit-exact in GDScript; the treeline wakes the flying area for most wind directions; density altitude is absent (1500 m at 35 °C: stall +13 %, thrust −22 %) ([07](docs/research/roadmap-investigations/07-atmosphere-wind-turbulence.md)) | M5-ATM-1…3, M5-W refinements |

**Decisions for the owner** (recommendation first; each becomes a DECISIONS row once taken):
1. Make the state extensible now (H8), with rotor speed integrated in RK4.
2. Golden policy v2: tolerance goldens on one CI reference platform; bit-exact replay as a same-machine diagnostic; wind recorded in traces.
3. Flatten the GDScript first; GDExtension only through Gate P, with numbers from the owner's slowest machine.
4. Data v2 as an ID-keyed component tree with the derivatives as an optional oracle, before more aircraft are generated. Mods are data only. GPL tools (AVL, XFOIL) stay outside `app/`.
5. Measure, don't tune (rule 10): a swing test for Ixx before any roll tuning. Does a built Stik exist?
6. Radio convention: the radio shapes; the sim is receiver + servos + linkages; linkage trim replaces the start trims (D6d).
7. Propwash stays opt-in per aircraft until the field checks (E0b7). Decide who owns `slipstream.gd`; recommended: main-line E0b steps.
8. Atmosphere default ISA (the literal 1.225) with an optional field elevation. Are thermals and slope soaring in M5?
9. Electric propulsion priority; recommended: M4b after G2.
10. Crash defaults: realistic or forgiving durability, and whether a prop strike at idle is a crash.
11. Latency target: ≤ 50 ms median and ≤ 70 ms p95 at 60 Hz, measured before any input optimisation.

**Recommended order from here:**
1. H1–H5: headroom, with no behaviour change.
2. D11a–b: re-measure, and add the red damping test.
3. E3b1–E3b3 and E1b: runway start, takeoff roll, smooth touchdown.
4. H8–H9: the extensible state and the golden policy.
5. E0b and G2a–b: propwash and the engine shaft.
6. D11c–e and E0a2: consistent damping.
7. E3c–E4, then PT2.

The owner's field kit can happen at any time; it unblocks D11e, E0b7, G2c and PT2.
