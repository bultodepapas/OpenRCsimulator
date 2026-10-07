# Roadmap

2026-10-06 · revision 5 · **Status: early R&D; Gate 2 pilot acceptance open. Next: E3b2 runway start (static solve with stuck anchors) toward the Stik ground circuit; the owner's Gate P decision is pending.** This revision implements the [whole-project audit](docs/research/project-audit-2026-10-06/README.md). It retains Godot, float64 dynamics, the fixed step, local aerodynamic loads and provenance. Step namespaces and track ownership: [documentation map](docs/README.md). Research: [phase knowledge base](docs/research/roadmap-investigations/README.md); foundations: [STACK](STACK.md), [DECISIONS](DECISIONS.md), [RESEARCH](RESEARCH.md).

The [execution order below](#execution-order-and-release-gates) is authoritative. Milestone tables define work and acceptance; unchecked rows are planned, not promises for the next release. Completed rows retain their dated proof. Reviews at the end are historical inputs, not a second execution queue.

**Be water, but on solid ground:** each step is small, has one objective proof, and leaves the project working. Steps go from basic to advanced; nothing advanced starts before its foundation is proven. If a step teaches us the route is wrong, we change the route and record why.

## Rules for every step

1. **One step = one small change** that can be reviewed in a few minutes and keeps the app working.
2. **Every step has a proof:** a passing test, a screenshot, a trace, or a measured number. "Looks fine" is not a proof.
3. **Known answers before unknown answers:** test the math and integrator against exact solutions before adding aerodynamics, whose answers we don't know.
4. **Guesses are labeled:** every parameter carries its source and evidence kind (`manual`, `borrowed`, `estimated`, `measured`).
5. **Gates are real stops:** at a gate we decide with the evidence collected, and record the decision.
6. **Verification is not validation.** A check against numbers computed from our own data proves the code; only independent data (flight tests, real-airplane measurements, pilots) proves realism. Each physics milestone needs at least one of each.
7. **Budgets are measured:** physics ≤ 0.5 ms per 240 Hz tick (≤ 2 ms per 60 fps frame) on the owner's slowest machine. Every aero step reports µs/tick before and after. Measure every active aircraft in representative regimes. Profile and apply justified cheap fixes first; Gate P decides whether a measured bottleneck needs the C++ GDExtension escape hatch (DECISIONS).
8. **One team per commit.** Stage your own paths (never `git add -A` while the other team has work in progress) and state the proof in the message. Each step ends with a ready-to-paste commit message.
9. **Read before you build.** Each phase has a knowledge-base document in [docs/research/roadmap-investigations/](docs/research/roadmap-investigations/README.md) (theory, tools, data, tests, pitfalls). Read it before the step; if the step proves it wrong, fix the document in the same change.
10. **Measure before tuning.** A gap against independent data is closed by measuring the unknown that explains it (mass, CG, inertia, throws, thrust), never by tuning a coefficient that only hides it. Values fitted to a reference are flagged and never count as validation of that reference.

## Where we are

- **Main line:** Phase A–C and the M1 engineering baseline work; Gate F selected local component loads. E1–E3b1, H1–H11 implementation/evidence work and D11a–b are done; H10 did not trigger an interface extraction. H12–H15 made the aero, air-data, slipstream and tilted-shaft propulsion paths allocation-free with exact trajectories. **Every fixture now meets 500 µs/tick at the median in GDScript; Gate P awaits the owner** because P-51 trim/stall still exceed it at batch p95 by up to 36 µs on the shared target. The native route remains research-only. D11b characterizes a known defect; it does not accept flight fidelity. The [audit](docs/research/project-audit-2026-10-06/README.md) parsed 159 scripts and ran 59 test programs successfully, but also demonstrated gaps in the smoke checker and data validation.
- **Current physics:** the rigid-body RK4 kernel is fourth-order with frozen auxiliary inputs; the complete P-51 shaft transient measured first-order convergence. The P-51 already has opt-in shaft balance, tail slipstream and ground handling; the Avanti already has turbine propulsion. These are committed experimental slices, not completed G2/E0b validation.
- **Validation:** [D11a results](research/sensitivity/results.md) include both Ultra Sticks and no refused sweep rows. Roll responds 2.07–2.37× faster; short-period ratios are 1.07 and 0.87. This comparison identifies uncertainty, not permission to fit unrelated airframes to one another. Real-build measurements and Gate 2 remain open.
- **Releases:** rc1–rc3 published; [rc4](docs/releases/v0.1.0-rc4.md) packages this audited baseline through the tag-gated release workflow; the audit built all three desktop exports and ran Linux. Owner acceptance on Linux/macOS, the physical radio and target GPU remains separate from build smoke tests. Use an identified current build for the next session; no new rc1 tag is required.
- **Flight repair:** [robustness](docs/FLIGHT-MODEL-ROBUSTNESS-PLAN.md) and [rudder repair](docs/RUDDER-REPAIR-PLAN.md) landed; their pilot acceptance is still open.
- **Ugly Stik model:** [model plan](docs/UGLY-STIK-PLAN.md) and [finish plan](docs/UGLY-STIK-VISUAL-PLAN.md) own geometry and appearance; human readability and target hardware evidence remain open.
- **Extra:** [EXTRA-300-PLAN](docs/EXTRA-300-PLAN.md) owns the experimental flyable model and independent contrast.
- **Avanti:** [AVANTI-S-PLAN](docs/AVANTI-S-PLAN.md) owns the experimental turbine aircraft; current starts are in the air with gear/flaps up.
- **P-51:** [P51-PLAN](docs/P51-PLAN.md) owns the experimental model and generated physics; [visual plan](docs/P51-VISUAL-PLAN.md) owns appearance acceptance.
- **Product shell:** [MENU-PLAN](docs/MENU-PLAN.md) owns Home, pause, help, aircraft selection and further scenarios/preferences.
- **Field and readability:** [VISUAL-QUALITY-PLAN](docs/VISUAL-QUALITY-PLAN.md) sequences [LANDSCAPE-PLAN](docs/LANDSCAPE-PLAN.md); Gate L still needs the owner's blinded reading test and target-GPU measurements. Software captures do not close it.
- **Crash:** [CRASH-DAMAGE-PLAN](docs/CRASH-DAMAGE-PLAN.md) next delivers a typed contact snapshot and factual cause; wreck effects and persistent damage are deferred.
- **Later proposals:** [WIND-PLAN](docs/WIND-PLAN.md) and [SMOKE-PLAN](docs/SMOKE-PLAN.md); read their historical code assumptions again before implementation.

## Execution order and release gates

**Next product outcome: one credible Ugly Stik takeoff–circuit–landing session (PT2).** Other aircraft remain useful experimental fixtures. A phase number groups a subject; it does not require completing every row before the next subject starts.

| Order | Work | Dependency and exit evidence |
| --- | --- | --- |
| 1 — repairs complete | C7-R1/R2, D1-R2, D1-R3 and DATA-1 | Completion/finiteness, active-model headers, shaft validation and generator freshness now have regression proof. See the repair and DATA rows; audit findings remain historical evidence. |
| 2 — in parallel | Gate 2/D6d, Gate L, PT1g; VAL-5/6/7 measurements; F1/F4 and minimum F6 latency observation | Owner uses a named build, physical radio and target hardware. Record uncertainties and raw evidence. Automated keyboard/fake-radio tests cannot close these gates. If trim prevents the session, bring forward the bounded F2 linkage-trim decision. |
| 3 — state prerequisite complete | H8/H9 bounded state and replay policy | Completed: explicit continuous, sampled and discrete state; RK stage time; reset, rollback and replay. Required before E3b1 anchors, E0a2/E0b5 lags, G2a coupling, wind filters, fuel or damage. No generic component framework required. |
| 4 — prepare the Stik ground circuit | D11d, E0a2 and D11f; E0b low-speed tail authority; E1b and E3b1–3 after their state/data prerequisites | Accept **Clp, Cmq, Cnr and CLα** through the approach regime with justified bands; contact energy/refinement checks; stable idle and takeoff roll. G1 operating-range evidence and VAL-7 bound powered-performance claims. No homegrown VLM prerequisite. |
| 5 — close M2 | E3c, E4 and PT2, after Gate 2 issues affecting flight/readability are resolved | Reproducible circuit plus an independent ground/flight comparison and owner handling evidence; retain separate verification and validation results. If measurements are unavailable, label the build experimental and leave validation open. |
| 6 — choose from pilot evidence | M3 radio breadth, G2/G3 propulsion and audio, electric slice, atmosphere/wind, aircraft breadth or CR-A presentation extensions/wreck | Choose the next small outcome from measured gaps. H4/H5/Gate P run where profiling requires them; expansion must fit the target budget. No requirement to finish all M4 nitro effects before electric or all M5 features for a useful simulator. |

**Gate 2 policy:** while it is open, continue repairs, measurement tooling and reversible experiments. Do not promote experimental aircraft to validated, expand shared schemas for speculative consumers, or accept major optional presentation scope merely because the backlog contains it. Record the pilot findings before committing the next product expansion. Gate F is already decided; it is not waiting behind Gate 2.

**Performance policy:** after H1–H5 the owner's confirmed slowest target (this Linux KVM / i5-10500 host) still exceeded 500 µs/tick; H12–H15 (bit-exact GDScript) brought every fixture under it at the median: Ugly Stik trim/stall 218–236, P-51 trim 444–476 and stall 457–461 µs/tick ([H15](docs/research/simulation-state/H15/README.md)). Earlier figures: The two [H4/H5 target runs](docs/research/simulation-state/H4-H5/README.md) measured P-51 trim at 737–761, stall at 878–898 and ground at 502–510 µs/tick, with additional batch-average p95 overruns. The [Gate P native experiment](docs/research/simulation-state/Gate-P/README.md) preserves all 32 flight fingerprints and reduces powered P-51 cost, but its stalled median remains 595–619 µs/tick. Native adoption remains unaccepted; measure the remaining aero/contact workload and verify all release platforms before adding a production dependency. A 250 µs target is optional reserve, not an automatic language-migration trigger.

**CR-01 timing:** the diagnostic snapshot/cause can run alongside this sequence; only the later crash presentation/wreck bundle competes for post-gate product priority.

**Scope controls:** H10 contributor interfaces need a concrete second implementation or demonstrated coupling problem; DATA-8 v2 needs a consumer v1 cannot represent cleanly; D11c custom VLM needs a question established offline tools cannot answer. None is a prerequisite for PT2. Existing optional v1 sections and the shared Dynamics evaluator stay until evidence requires change.

### Audit repairs

These repair IDs belong to the main-line roadmap; completed rows record their implementation proof. [Audit findings and reproductions](docs/research/project-audit-2026-10-06/README.md) supply the baseline.

| ID | Change | Acceptance and timing |
| --- | --- | --- |
| C7-R1 ✅ | Harden trace duration parsing and the trimmed-flight checker; distinguish successful completion from initial-only output or numerical abort | **2026-10-06:** rejects invalid durations/paths, faults or missing ticks, malformed/non-finite samples, and duration/clock mismatches. All callers specify duration. Proof: 9 process tests (including real-trace mutations and last-tick fault injection), full `app/test.sh`, isolated Windows/Linux/macOS exports; four exported flights retain byte-identical numeric rows against rc4. [Report and evidence](docs/research/trace-integrity/C7-R1/README.md). |
| C7-R2 ✅ | Derive trace feature metadata from the active aircraft and state layout; document the actual trace version | 2026-10-06: versioned headers identify configured aero/propulsion/slipstream, state layouts and recording-start auxiliary state. CSV stays v3; current smoke reader rejects missing/inconsistent metadata. Proof: 128 metadata checks, 11 trace process tests, full suite, desktop exports and four unchanged source/export flights. [Report and evidence](docs/research/trace-integrity/C7-R2/README.md). Exact file hashing remains DATA-3. |
| D1-R2 ✅ | Validate nested shaft-table numbers, finiteness and quantity provenance as strictly as scalar data | 2026-10-06: shaft curves use the shared typed, finite, provenanced table validator and retain positive RPM/power constraints. Invalid units fail cleanly; invalid reload preserves the active flight. Proof: 117 checks, full suite, five before/after loader probes and unchanged numeric traces for all four aircraft. [Report and evidence](docs/research/aircraft-validation/D1-R2/README.md). |
| D1-R3 ✅ | Replace the gear bounding-box support test with a support-polygon test for configurations requesting static ground support | 2026-10-07: `AircraftData.ground_support()` finds the lower hull facet the airplane rests on and projects the CG along its normal, so taildraggers are judged at their three-point attitude (P-51 13.9° nose-up, margin 0.254 m; Stik 0.096 m); the margin uses the whole coplanar facet. The audit B3 layout is now refused; 81 data checks; 3 mutations caught; full suite and 16/16 fingerprints unchanged. A retracted/in-flight-only gear flag is deferred until a consumer (Avanti) needs it. [Report](docs/research/aircraft-validation/D1-R3/README.md). |
| D6b-R1 | Validate saved calibration profiles: finite ordered endpoints, allowed axes, unique primary assignments and device identity | Before profile import or wider-device rollout; reject duplicated axes, NaN and out-of-range fields without applying a partial profile; valid replug/calibration still works. |

DATA-1 now checks P-51 generated outputs in CI. DATA-3 (input hash) precedes new reference datasets. Within their owning tracks, the next capture change must isolate output directories/log files per run, and the next UI help change must remove the obsolete claim that any ground touch restarts a flight. These are scoped follow-ups, not new release-blocking feature programs. Fixture shutdown warnings remain a low-priority test-hygiene item unless a sustained gameplay leak is reproduced.

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

### Predicted handling: historical D1 verification targets

Computed from the original D1 data (2.601 kg, 720 in², borrowed UltraStick25e aero). The inventory repair changed the mass to 2.885 kg; use D11a/generated results for the current baseline. This table preserves the original hand checks, not current tuning targets. Agreement with the same coefficients verifies implementation, not realism (rule 6); independent comparisons belong to D8b/VAL.

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
| D8b (partly ✅) | Independent modal comparisons plus real-Stik measurements | The original US120 comparison was completed 2026-10-05. **D11a supersedes its numbers** after the repair and adds the obtained Dorobantu 25e preprint; the old 1.45× pitch gap, stable spiral and library blocker are obsolete. Current ratios are in D11a. Real-build inertia/throws, flight videos and pilot validation remain open under VAL/Gate 2. |
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
| **Gate 2** | **Is the identified build flyable, readable and fun with a radio?** Owner and, if available, other RC pilots fly three airborne circuits, a loop, roll and stall/recovery; rate roll/pitch/yaw/throttle −2…+2 against a real Stik; test 100 m orientation with/without zoom, setup time and trim convention | Record radio/OS/build, ratings, frame-time distribution, physics cost and a minimum F6 latency observation. Ratings outside ±1 trigger investigation and reorder D11/M2; they do not justify arbitrary coefficient fitting. Record optional-track priorities and unresolved acceptance separately. |
| D10 ✅ | Sensitivity sweep on the D8 maneuvers and flight modes, in this order: Clp, Cmq, Ixx, Iyy (inventory is 1.7× a Roskam-typical value), servo lag, CLmax/α0, CD0, CG, mass | A table ranking which unknowns matter; decides what to measure next. ✅ 2026-10-05: `research/sensitivity/results.md` (13 unknowns × ±20 %, each varied in the data so derived values follow). Ranking by largest effect: Cnr (spiral +162 %), Cnβ (spiral, dutch roll), Clp (roll τ and rate), CG ±0.02 m (short period, spiral), CD0 (glide ±20 %), mass (−20 % refused by the plausibility range; +20 % → stall +9 %), Ixx (roll τ), Iyy, CL_max (stall speed), Izz, Cmq, Cmα, servo time (none on these outputs). **Historical sweep; D11a replaces these numbers and removes refused rows. Measure next:** a weighed build with its CG and a swing test for Ixx (cheap), then rudder authority (β at full rudder) from video or pilot reports |
| **Gate F** ✅ | **Flight-model architecture before M2.** Decided 2026-10-06 by the flight repair ([DECISIONS](DECISIONS.md): local passive loads): wing and tail loads are local elements that reproduce the linear oracle at small angles, i.e. the component buildup grown one surface group at a time, as this gate proposed. Still open: E0b propwash, G2 shaft balance, Gate 2 pilot validation | [Report](docs/research/flight-repair-implementation.md); DECISIONS row of 2026-10-06 |

### M1 follow-up — flight-model consistency (D11)

Found by the knowledge base ([02](docs/research/roadmap-investigations/02-aerodynamics-rc-scale.md), [08](docs/research/roadmap-investigations/08-validation-flight-testing.md)) and re-checked with a probe ([facts re-checked](docs/research/roadmap-investigations/README.md#facts-the-lead-re-checked)). Do it before E3c: an approach at 1.3 V_s flies inside the blend region where the damping changes.

| # | Step | Proof |
| --- | --- | --- |
| D11a ✅ | Re-run D8b/D10 on the post-repair baseline (perturb CG by moving the whole inventory with it, Cnβ by fin area, mass with the gear springs scaled alongside: no "refused" rows) and add the Ultra Stick 25e comparison (Dorobantu 2013 preprint: flight-identified modes, swing-test inertias) at matched CL | `research/sensitivity/results.md` regenerated; its 15 m/s baseline equals the `test_modes` bands; a table with both Sticks; mutation Ixx × 2 moves roll τ ≈ 2×. ✅ 2026-10-06: [`results.md`](research/sensitivity/results.md) now says it is generated and how; no refused rows (mass ±15 %: +20 % leaves the plausible range). **US120:** short period 1.07×, roll τ 2.07× faster, dutch roll 1.26×, spiral unstable (τ −21 s). **25e** (nondimensional, CL 0.28, sim at 18.8 m/s): short period 0.87×, roll pole 2.37×, dutch roll 1.46×; Ixx/(m·b²) 0.0172 vs 0.0282 swing-tested. D10 ranking: fin area and Cnr dominate the spiral (reported as its pole λ: τ crosses infinity near neutral), then Clp, CG, mass, CD0, Ixx. The inventory mass is 2.885 kg, not the 2.601 kg of the predicted-handling table (D1-R1) |
| D11b ✅ (characterization only) | Regime-consistency test: linearized Clp, Cmq, Cnr, CLα at α 0…11° | 2026-10-06: [`test_damping_regimes.gd`](app/tests/test_damping_regimes.gd), 17 checks; worst oracle ratios **1.73, 0.28, 0.72, 1.34**. `KNOWN_DEFECT` deliberately pins these results. Fidelity acceptance remains open under D11d/E0a2/D11f: explain the response across α, separate physical variation from blend artifacts, and justify the acceptance bands before changing the flag. The borrowed oracle and its current ±15 % band are hypotheses, not physical truth. |
| D11c (conditional research) | Compare analytic derivatives with an established offline tool such as AVL and available flight identification; build a small VLM only if a specific unresolved question warrants it | Known-answer case and refinement/error study; provenance and applicability per derivative. No required custom solver and no data change merely to match one tool. |
| D11d | Resolve wing Clp/CLα blend artifacts using consistent strip slope, force arms and induced-flow treatment; increase strip count only when refinement proves it necessary | D11b wing responses accepted through approach α with sourced bands and refinement evidence; deliberate golden updates and µs/tick. D11c is optional supporting research. |
| D11e | Measure rigid-airframe Ixx (VAL-6); evaluate added-air inertia separately, including uncertainty and applicability | Report roll-mode comparison to both Ultra Sticks and the measured Stik, with uncertainty; do not force different aircraft into a universal ±30 % target or alter damping to hide an inertia error. Required before claiming the roll gap resolved, not before an explicitly experimental circuit. |

| D11f | Resolve fin Cnr through the oracle/local transition, with consistent local velocity, force and moment arm | All four D11b responses have justified acceptance across approach α; rudder doublet, dutch roll, spiral, reverse-flow continuity and passive loads regressions remain covered. Required before E3c acceptance. |

### Phase H — State contract and measured headroom

H1–H11 implementation and bounded evidence work are complete below; H10 did not trigger. **Gate P awaits the owner's decision:** after H12–H15 every fixture meets the 500 µs budget at the median in GDScript; P-51 trim/stall exceed it at batch p95 by up to 36 µs on the shared target. H4/H5 closed the first GDScript pass; H12–H15 are the measured bit-exact second pass. H8/H9 now satisfy the state prerequisite for E3b1 and later coupled shaft, wash, wind, fuel and damage. Follow the [execution order](#execution-order-and-release-gates). Knowledge: [01](docs/research/roadmap-investigations/01-numerics-architecture-performance.md). Behavior-preserving refactors retain same-machine fingerprints; intentional model changes use justified tolerance and convergence evidence.

| # | Step | Proof |
| --- | --- | --- |
| H1 ✅ | Per-component cost bench (the HUD's F3 line already shows the live tick cost, so no custom monitor) | Table of µs per component. ✅ 2026-10-06: `tests/bench_physics.gd` keeps its headline and adds µs per call of air data, aero, propulsion, gear, `Dynamics.loads`, session loads, derivative and RK4 for trimmed, stalled (α 15°) and on-ground states, plus stalled ticks; `-- --aircraft=<id>` benches any catalog aircraft. Before H2: session loads 73 µs × 5 per tick, derivative 21 µs × 4, aero 45 µs on the oracle path alone (Dictionary access) |
| H2 ✅ | Reuse the tick's loads as the RK4 stage-1 loads (one of five load evaluations per tick is redundant); build deflections once per tick | Goldens bit-identical; −60…70 µs/tick. ✅ 2026-10-06: `rk4_step(..., k1_given)`; `FlightSession._deflections` caches by servo positions (cleared per aircraft). Proof: SHA-256 of state, aux and loads over 1,200 ticks for 4 aircraft × 3 regimes (scripted maneuver, stall, ground) identical before and after; a never-invalidating cache (scratch copy) changes all 12. `test_session_guards.gd` now pins 4 load calls per tick (its k2–k4 failure injections follow the new count) |
| H3 ✅ | Allocation-free `RB.derivative` | 0.0 difference on 10,000 random states. ✅ 2026-10-06: the derivative is written in scalars with every product and sum in the original order (zero terms kept), one allocation instead of ~20; `test_rigid_body.gd` compares it byte for byte with the vector form (kept as `derivative_reference`) on 10,000 seeded states and at rest: 0 mismatches; a reassociated sum (scratch copy) gives 3,123. 21.2 → 2.8 µs per call. With H2: trimmed tick 592 → 400 µs, stalled 526 → 380 µs (dev VM, loaded; same bench and session). Preallocated RK4 stages left for H4 (RK4 overhead ≈ 7 µs) |
| H4 ✅ (GDScript pass) | Profile all aircraft and remove measured repeated aero/slipstream work | 2026-10-07: scalar local-flow/immersion calculations and shared washed/free tail work preserve all 16 aircraft/regime fingerprints over 960 ticks, including both final target runs; 10,000 local-flow reference comparisons are byte-exact. Two 16×120 cost distributions per fixture are recorded on the owner-confirmed target. **Budget shortfall escalates to Gate P; this is not performance acceptance.** [Evidence](docs/research/simulation-state/H4-H5/README.md). |
| H5 ✅ (regime evidence) | Optimize measured local-load bottlenecks and establish target costs for trim, stall, spin and ground | 2026-10-07: local loads reuse computed flow; initial gear evaluation is small relative to aero, so no unsupported ground rewrite. All four aircraft retain exact trajectories. P-51 trim 737–761, stall 878–898 and ground 502–510 µs/tick exceed 500; other tail-latency overruns are recorded. Extra/Avanti ground rows are explicitly no-contact probes. **Gate P remains unmet.** [Distributions and limits](docs/research/simulation-state/H4-H5/README.md). |
| H6 ✅ | Every transcendental call in `physics/` and `sim/` goes through `math3d`, guarded in `test.sh` | 2026-10-07: clean guard, isolated bare-`sin` rejection and four unchanged per-tick golden fingerprints against direct built-ins. Full suite passes. [Evidence](docs/research/simulation-state/H6/README.md). |
| H7 ✅ | 1-ulp sensitivity test: perturb `atan2_`/`sin_` and replay the goldens | 2026-10-07: exact next-float-up perturbations stay below tolerance/1000 on all four air goldens; branch tapes match. A real golden branch mutation is detected despite sub-threshold state error; adjacent-float stall fixture crosses its decision. [Evidence and scope](docs/research/simulation-state/H7/README.md). |
| H8 ✅ | Bounded continuous, sampled and discrete state contract; derivative ownership, stage time, reset, rollback and checkpoint/replay | 2026-10-07: 90 checks cover unused entries, atomic validation, pre-step/k1–k4 failure, complete reset/reload rollback and exact four-aircraft mid-flight continuation. Fixed timestep belongs to the run. Native checkpoints include auxiliaries/modes; restoration pauses downstream of live input. H8a proves coupled stage time/order. [Contract and full regression](docs/research/simulation-state/H8/README.md). |
| H8a ✅ | Supply absolute RK stage time while preserving the autonomous API, sampled auxiliaries and cached k1 | 2026-10-06: 22 checks cover exact stage times, fourth-order coupled analytic solution, input/aux holds and later-stage fault rollback; frozen-time mutation fails three checks. Full `app/test.sh`, three scene smokes and four unchanged aircraft traces pass. [State inventory and evidence](docs/research/simulation-state/H8a/README.md). H8 separately completes checkpoint/reset/discrete-state coverage. |
| H9 ✅ | Per-component tolerance scales and platform/build stamps; same-machine bit-exact refactor diagnostics | 2026-10-07: 42 checks reject every component mutation, mode/clock mismatch and partial extension; recorded budgets cannot loosen acceptance. New v1 files add auxiliary/mode checkpoints and stamps; legacy goldens remain readable. Ubuntu reference CI and manual/non-gating other-platform policy are explicit. [Evidence](docs/research/simulation-state/H9/README.md). |
| H10 ✅ (conditional; not triggered) | Extract a contributor interface only for a concrete consumer blocked by shared Dynamics | 2026-10-07: flight, trim and linearization still fit the shared evaluator. No justified extraction or dispatch layer; reopen for named duplication/coupling and measure it then. [Assessment](docs/research/simulation-state/H10/README.md). |
| H11 ✅ | Coupled contact stiffness/damping policy; substep evaluation only outside measured support | 2026-10-07: 72 checks use production contact/RK4 for ring-down, passive energy and 240/480/960 Hz refinement. Full-inertia/free-yaw mode screen has an analytic reference. Six Stik-derived fixtures pass through measured ρ=0.291798; the stiffer 0.583596 case fails accuracy despite passivity. Loader stays conservative; no universal relaxed limit or substep count. All catalog entries screened; P-51 dynamics remain outside this bounded result. [Evidence](docs/research/simulation-state/H11/README.md). |
| H12 ✅ | Allocation-free local-strip aerodynamics (the path every aircraft uses in stall/spin) | 2026-10-07: scalar `_local_loads`, same operation order, `math3d` routing kept. 10,000 byte-exact comparisons against a frozen oracle (0 failures; one reassociated product fails 5,201); 64/64 960-tick fingerprints match Gate P `oracle-1`; full `app/test.sh` passes, goldens unchanged. 62–75 → 18–29 µs/call. Spin ticks fall 38–45% for the fleet; outside P-51 powered trim/stall one batch-p95 value is over 500 (Avanti stall 500.8), down from 15. P-51 powered trim/stall stay 780–841 µs/tick in GDScript. [Evidence](docs/research/simulation-state/H12/README.md). |
| H13 ✅ | Allocation-free GDScript slipstream path (`Slipstream.loads`, tail increment, immersion) with a frozen oracle | 2026-10-07: 10,000 byte-exact P-51 comparisons (6,083 washed, 1,429 static, 448 stopped; a reassociated sum fails 2,157); 64/64 fingerprints; full `app/test.sh` on a clean `77cdae9` clone exits 0, goldens unchanged. Slipstream 86–89 → 37–38 µs/call; P-51 trim 739–757 → 545–584, stall 780–790 → 559–577 µs/tick. Native slipstream rerun on committed H12: trim 456–477, stall 510–520. [Evidence](docs/research/simulation-state/H13/README.md). |
| H14 ✅ | Allocation-free tilted-shaft propulsion loads (normal force and P-factor share one crossflow projection) | 2026-10-07: 20,000 byte-exact comparisons across all aircraft (9,537 tilted; a reassociated sum fails 190); 64/64 fingerprints; full `app/test.sh` exits 0, goldens unchanged. P-51 propulsion 19–21 → 9–14 µs/call; trim 571–577 → 514–520, stall 578–584 → 540–541 µs/tick; batch p95 591–695. [Evidence](docs/research/simulation-state/H14/README.md). |
| H15 ✅ | Allocation-free attached-flow evaluation: `Air.compute`, `Aero.local_flow_weight`, `Aero._global_loads` with `coefficients()` inlined | 2026-10-07: retargeted by measurement. The step anatomy showed the planned bookkeeping target was about 20 safety checks of about 1 µs each, while attached-flow aero plus air data cost 32–39 µs per evaluation in every aircraft's normal flight. 10,000 air-data and 10,000 global-load byte-exact comparisons (5,000 windy, 2,000 envelope-free; mutations fail 1,662/2,042); H4/H12 oracles stay exact; 64/64 fingerprints; full `app/test.sh` exits 0, goldens unchanged. Fleet trim ticks −20%; Stik trim/stall 218–236, P-51 trim 444–476, stall 457–461 µs/tick: **every median within 500**; P-51 trim/stall batch p95 519–536. [Evidence](docs/research/simulation-state/H15/README.md). |
| **Gate P — owner decision** | **GDExtension or not.** After profiling and justified H4/H5 work, measure every active aircraft at trim, stall/spin, ground and enabled propulsion on the owner’s slowest supported machine. Migrate only if the 500 µs/tick budget or a documented near-term reserve cannot be met | 2026-10-07: Linux KVM / i5-10500 / pinned Godot 4.7.2, confirmed by the owner as the target. Both final runs miss 500 µs/tick in P-51 powered trim/stall and ground; p95 batch-average overruns also occur elsewhere. [Measured decision](docs/research/simulation-state/H4-H5/README.md), recorded in DECISIONS. The [bounded Linux native experiment](docs/research/simulation-state/Gate-P/README.md) now passes 10,046 kernel checks, the full app suite and 32 exact four-second fingerprints. P-51 trim improves to 461–484 and stall to 595–619 µs/tick; stall and batch-p95 overruns keep this gate unmet. Production stays GDScript. [H12](docs/research/simulation-state/H12/README.md)–[H14](docs/research/simulation-state/H14/README.md) cut GDScript P-51 trim/stall to 514–541 µs/tick (native slipstream on H12 measured 456–520), so the native route no longer has a clear performance case. [H15](docs/research/simulation-state/H15/README.md) brings every fixture within 500 µs/tick at the median in GDScript (P-51 stall 457–461, below native-on-H12's 510–520); P-51 trim/stall batch p95 is 519–536 on a host with a capture renderer at 100% of one core. **Recommendation: close Gate P as "no GDExtension"**, keep production GDScript and archive the native experiment as research (code and evidence stay). Condition: one whole-fleet remeasurement on the quiet target (renderer stopped) meets 500 at median and batch p95; if P-51 p95 still exceeds, the owner chooses between a documented experimental-aircraft p95 reserve and one bounded `thrust_torque`/`wake` sharing step. |

### M2 — Takeoff and landing

Knowledge: [04](docs/research/roadmap-investigations/04-ground-handling-collisions.md) (ground), [03](docs/research/roadmap-investigations/03-propeller-propwash.md) (propwash), [01](docs/research/roadmap-investigations/01-numerics-architecture-performance.md) (contacts and numerics). Dependencies follow the [execution order](#execution-order-and-release-gates): H8 before E3b1; D1-R3 before E3b2; E1b, D11d/E0a2/D11f and scoped E0b before accepting E3c. M2 proves one Stik ground circuit; M2+ breadth is separate.

| # | Step | Proof |
| --- | --- | --- |
| E0a (partly ✅) | Horizontal and vertical tail as separate surfaces (local α from q·l and r·l, downwash lag), geometry read from the model team's `ugly_stik_geometry.gd`; the whole-aircraft derivatives lose their tail share | Linearized Cmα, Cmq, Cnβ and Cnr within ±10 % of the oracle at trim; the modes test stays within its bands; µs/tick reported. ✅ partly, 2026-10-06 (D9-R2): both tails are local surfaces (`v + ω × r`, `r × F`) in free-stream flow and the global derivatives lose their tail share; downwash lag and the propwash factor remain for E0b |
| E0a2 | Reconcile tail lift slope/downwash with the whole-aircraft reference without arbitrary effectiveness factors; add downwash lag only through H8 | Explain Cmq and CLα/Cmα behavior through approach α; lag response/refinement when enabled; D11b pitch acceptance, passive loads and small-angle agreement. |
| E0b (P-51 first slice exists) | Establish low-speed tail authority for the Stik using the shared slipstream module, actual washed geometry and propulsion evidence | Static and cruise force/moment checks, reverse-flow continuity, disabled-path identity and cost; independent field observations before a validated Stik wash claim. Momentum-theory ratios are bounds for a stated operating point, not universal tail multipliers. |
| E0b1 | Pure `wake()` function: momentum theory, contraction, the closed-form ratio q_wash/q∞ = 1 + 8Ct/(πJ²) | 35.3× at 5 m/s and 1.30× at level-flight thrust at 15 m/s; a mutation fails ([03](docs/research/roadmap-investigations/03-propeller-propwash.md)) |
| E0b2 | Explicit hub position for the Stik (the data puts the prop at the CG; the real hub is 0.414 m ahead), cross-checked with `ugly_stik_geometry.gd`; washed tail pieces from the geometry | `test_aircraft_data.gd` agreement; goldens re-recorded deliberately only if the torque arm changes them |
| E0b3 (P-51 slice exists) | Review and reuse committed `slipstream.gd` for the Stik: washed minus free-stream tail increment, opt-in configuration, smooth edge and reverse-flow behavior | Zero-speed elevator/rudder authority, exactly zero increment when disabled, continuity and passive-flow tests over the supported envelope; aircraft/regime cost. |
| E0b4 | Determine wash-speed/decay and surface coverage from matched geometry and data; keep estimates distinct from measurements | Bound tail loads and cruise derivatives at stated throttle/airspeed; show sensitivity to uncertain decay. Literature 12–20× at one condition is a prior, not a universal acceptance target. |
| E0b5 | Wash transport lag as a state (H8) | Step delay = distance / wash speed ± 5 %; frame-rate hash identical |
| E0b6 (P-51 slice exists) | Verify swirl direction and magnitude against shaft torque, wake assumptions and available observations | Torque/sign/continuity checks and uncertainty band; do not impose an arbitrary fraction of full-rudder authority as physical validation. |
| E0b7 | Field checks: nose-wheel unloading, taxi blip and takeoff swing, with recorded configuration and throttle/rpm | Raw observations and uncertainty; coefficients inferred from behavior are labelled fitted/derived, not directly measured. Preserve independent held-out cases; Stik enablement and golden changes are explicit. |
| E1 ✅ | Tricycle gear contact points as spring-dampers; stiffness from a natural-frequency rule (`ω·dt < 0.1`) | Drop test: no energy gain; agrees across `h` and `h/2`. ✅ 2026-10-06: `physics/ground_contact.gd` (per wheel `F = max(0, k·δ + c·δ̇)` at the wheel bottom, moment `r × F`, nothing added in the air), optional `landing_gear` data section (Stik: mains 560 N/m, nose 440 N/m from the rule at 240 Hz, ω·dt 0.097, sag 18 mm, ζ 0.4, 0.12 m travel; the loader refuses a CG outside the wheelbase, ω·dt ≥ 0.1 or ζ outside 0.05–2); the wheels leave the crash hull (belly point added), a leg past its travel is a crash. `test_ground_contact.gd` (22): hand-computed loads, restoring signs, drop test with zero energy gain and rest at m·g within 1°, h vs h/2 within 23 µm (horizontal drift 17.9× smaller at h/2: 4th order), the Stik lands from 0.35 m and breaks its gear from 2.0 m. Trace rows byte-identical (`7d2f8a4c…`), goldens unchanged, 4 mutations caught, 510 µs/tick on the VM (was 526). [Report](docs/research/landing-gear-contact-e1.md). Extra and P-51 keep D9d (wheels crash) until their generators add the section. Found by the real ground: `slow_flight` and `spin_right` sank to −78 m and −55 m on HEAD (nothing acted below the ground); both now start at 150 m, their physics unchanged. **Finding for the model team:** the visual main axle (x_aft 0.10 m) sits ahead of the CG |
| E2 ✅ | Rolling friction (labeled guess), nosewheel steering, brakes off | Taxi a figure-eight. ✅ 2026-10-06: tyre forces in the ground plane along each wheel's heading (rolling resistance C_rr·N, slip-angle side force saturating at μ·N, friction circle), nose wheel steered 20° by the rudder servo; dry-pavement values C_rr 0.04 (estimated), μ 0.8 and peak slip 6° (borrowed from JSBSim); the loader requires them with the gear and bounds the side-force rate (λ·dt 0.31 ≤ 0.5). `test_ground_friction.gd` (26): hand-computed loads, no power over 2000 random states, coast-down at C_rr·g within 0.02 %, turn radius 0.977 m vs kinematic 0.964 m, tip-over 4.50 m/s² vs rigid oracle 4.47 (real gear 78 % of it, roll compliance), h vs h/2 2.9 µm, session figure-eight at idle (two full turns, no wheel lifted). Trace rows byte-identical, goldens unchanged, 6 mutations caught, air cost unchanged (511 µs/tick). [Report](docs/research/ground-friction-e2.md). **Findings:** the Stik tips before it slides (full steer above ≈1.85 m/s); idle (2.6 N) out-pulls rolling resistance (1.1 N) on pavement. Not validated: turn radius, coast-down and idle creep on a real Stik |
| E3 | Start on the runway: takeoff, circuit, landing, nose-over, in four sub-steps | Trace of a full circuit |
| E3a ✅ | Field surfaces under the wheels: runway (mown strip), mown and rough scale μ and C_rr | Coast-downs and idle on each surface. ✅ 2026-10-06: `app/data/ground/surface_friction.json` (FlightGear `grass_rwy`, `Grass`, `Grassland` factors; rough rolling estimated), `physics/ground_surfaces.gd` builds a lookup from the field's rectangles (runway over mown over rough); each wheel finds its own surface; `FlightSession.set_field`, invalid table refuses the flight. `test_ground_surfaces.gd` (28): refusals, lookup on the real field, hand-computed scaled loads, no power across edges, coast-downs within 1 % (runway 0.979 vs 0.981 m/s²), idle holds on the runway (2.6 N vs 2.8 N) where pavement rolled 21 m. 5 mutations caught; trace rows identical. Rolling creep 0.05 → 0.01 m/s (still 0.9 cm/s against a steady push). [Report](docs/research/ground-surfaces-e3a.md) |
| E3b | Runway start: parked at the threshold, engine at idle, true stiction (no creep); takeoff roll | Sits still at idle; full-throttle ground roll and lift-off speed against a hand estimate |
| E3b1 ✅ | After H8, implement per-wheel stick/slip anchors with tick-boundary mode transitions; calibrate the static resistance law separately from sliding/rolling | 2026-10-07: opt-in `breakaway_factor` (Stik 1.25, estimated); per-wheel `[north, east, stuck]` aux; stuck force clamped inside RK4, release on the elastic force k·d, re-stick below 0.02 m/s with an unloaded anchor; springs Σk = m·(19.2 rad/s)² split by static load share. 60 s parked at idle on the runway drifts 0.04 mm (E2 alone: 102 mm in 10 s); breakaway 2.92–3.09 N brackets the quasi-static prediction 3.11 N (load transfer); no energy gain; 240/480 Hz agree to 1.5e-12 m; checkpoint replay exact; airborne flight byte-identical. 25 checks, 5 mutations caught; full `app/test.sh` exits 0 (92 sections). Parked tick +55 µs (399 vs 343). Factor, stick speed and springs stay estimated/numerical until a field pull test. [Evidence](docs/research/ground-contact/E3b1/README.md). |
| E3b2 | Runway start: static solve on the gear at the threshold, engine at idle, anchors stuck | After 1 s: \|v\| < 1e-6 m/s, ΣF_n = m·g ± 0.1 %, attitude within 0.1° of the solve |
| E3b3 | Takeoff roll against a hand integral using the current mass, prop data and surface resistance; record whether wash is enabled | Numerical roll distance/speed agree with the independently calculated model integral within a justified band; recompute assumptions after E0b. Old 4.69 m/11.3 m/s estimates are historical, not real-flight acceptance. VAL-7/PT2 provide physical comparison. |
| E1b | Investigate continuous touchdown damping/contact onset (for example ramped damping or Hunt–Crossley); select from energy and refinement evidence | No unphysical force jump or energy gain; h/h₂ touchdown/rollout errors meet a declared accuracy budget. Require fourth-order convergence only on smooth intervals; contact switching can reduce global order. Before E3c/E4 acceptance. |
| E3c | Circuit and landing on the runway | Trace of a full circuit: takeoff, pattern, landing, roll-out |
| E3c1 | Closed-loop approach-and-flare maneuver for tests (`sim/maneuvers.gd`); requires D11d, E0a2, D11f, scoped E0b and E1b | Touchdown sink ≤ 1 m/s; roll-out stops on the runway; no crash. Passing a controller-driven maneuver verifies this case, not pilot handling. |
| E3c2 | Full circuit trace | Trace and capture: takeoff, pattern, landing, roll-out, no hull contact |
| E3d | Nose-over and wingtip scrape: which ground touches are crashes | A wingtip touch at walking pace is not a crash; a nose-in at speed is |
| E3d1 | After CR-01/H8, add frictional hull contacts with stable component IDs and sourced or explicitly estimated contact parameters | Low-speed wingtip/belly contact can recover or slide; high-speed nose impact emits the correct typed event. Contact-parameter sensitivity and no-energy-gain checks; no claim of structural realism until CR-07 evidence. |
| E3d2 | Prop-strike event and component cause, reusing CR-01 snapshot/UI semantics | Component and contact speed recorded once in UI/trace; engine stop and restart rules tested. Structural damage/default durability remains in the CR plan. |
| E4 | Golden flight of a full circuit (the mechanism exists since D8a) | A replayed circuit matches its recording within the H9 tolerances; C_rr + 10 % and anchor stiffness × 2 are each detected |
| PT2 | Playtest v0.2: one Stik takeoff, circuit, landing and rollout | E3c/E4 verification; owner radio session; independent pull/coast-down, idle creep and takeoff/landing observations with configuration and uncertainty. Report fidelity gaps separately; no PT2 validation closure from generated expectations alone. |

### M2+ — Ground breadth (after PT2; with each aircraft track)

Knowledge: [04](docs/research/roadmap-investigations/04-ground-handling-collisions.md).

| # | Step | Proof |
| --- | --- | --- |
| E5a (P-51 first slice exists) | Review committed P-51 tailwheel handling, then extend through each aircraft generator; add caster behavior only when requested | Recheck contact geometry and static attitude; steering/ground-loop signs, refinement and independent pilot contrast. Existing P-51 tests do not validate all taildraggers. |
| E5b | Nose-over (tail up, soft spot): friction needed is ≈ 0.35–0.37 for the Extra and P-51, which rough grass plus a soft spot can reach | The tail lifts at the rigid-gear oracle's d/h ± 2 % |
| E5c | Brakes (JSBSim formula, brake groups, channel or rudder differential) | Straight braking deceleration μ_brake·g ± 2 % |
| E5d | Retracts (unblocks P51-11 together with DATA-10) | Cycle time matches the data; a gear-up landing at 0.8 m/s sink slides |
| E6a | Wheel-radius contact geometry with per-wheel diameter; rolling resistance by wheel size and surface after PT2's measurements | Static attitude < 1 mm from the analytic circle; E3a reproduced for 76 mm wheels |
| E6b | Terrain contact through the simulation-owned float64 sampler of LANDSCAPE L12a; rendering consumes the same terrain definition | All-zero grid preserves trace; slope behavior and cost tested. Keep engine collision queries outside authoritative flight state unless a separate precision, timing and replay contract is demonstrated. |
| E6c | Trees as float64 capsules and crown cylinders with a grid broad phase (L14) | A scripted flight into a tree crashes at the right tick ± 1; flying between trees does not |
| E7a | Hand, catapult and bungee launch: a scenario start state, and a tension-only spring with release for the bungee | The start state equals the requested (v, θ); bungee energy balance within the damping losses |
| E7b | Part loss after a component crash — implemented once under CR-12/13 in [CRASH-DAMAGE-PLAN](docs/CRASH-DAMAGE-PLAN.md) | H8, CR contact/threshold gates and G4b mass semantics precede persistent damage; removed loads/mass/inertia match the component inventory. No second damage implementation in M2+. |

### M3 — Radio breadth and measured latency

Knowledge: [06](docs/research/roadmap-investigations/06-radio-input-servos-latency.md). F1/F4 and minimum F6 measurements serve Gate 2 now; F2 can move forward if required for usable trim. D6b-R1 precedes imported profiles. Further servo detail follows measured need and H8 for new state. Proposed convention (owner decides at D6d): with a radio, the simulator is receiver + servos + linkages, and the radio does expo, rates, mixes and trims. EdgeTX sends channel outputs that are already shaped, so the simulator never shapes them again.

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

### M4 — Propulsion response, operating range and sound

Knowledge: [05](docs/research/roadmap-investigations/05-propulsion-engines-motors.md), [03](docs/research/roadmap-investigations/03-propeller-propwash.md) (G1), [10](docs/research/roadmap-investigations/10-audio-perception-presentation.md) (G3). P51-06 committed the first shaft balance and AV-05 committed turbine propulsion on 2026-10-06. G2a brings coupled shaft dynamics into H8. G1 matched operating-range evidence and G1d dead-stick drag can be advanced for M2 validation; full four-quadrant BEM, optional failures and detailed sound are separate outcomes.

| # | Step | Proof |
| --- | --- | --- |
| G1a | First obtain matched prop diameter/rpm/thrust evidence for the intended Stik operating band (VAL-7); then add Ct/Cp(J, rpm) dimensions where measurements justify them | Per-run provenance and exact interpolation knots; report out-of-range use and fitted versus held-out cases. Current 11×6 ≤ 6,259 rpm data do not validate a 12×6 at 11,149 rpm. Full table breadth is not a prerequisite for an explicitly bounded M2 experiment. |
| G1b | Out-of-range flags (J gap, J beyond the table, rpm outside it) counted in the trace | Counters fire on crafted queries; a 40 m/s dive reports its out-of-range ticks |
| G1c (conditional breadth) | Generalize the existing offline P-51 BEM tool only when G1a/b expose operating regions that require it | Matched-rpm comparisons with uncertainty; windmill/four-quadrant cases before claiming those regimes. A synthetic table is not independent propeller validation. |
| G1d | Stopped-propeller and windmilling drag at matched airframe configurations | Correct limiting cases, torque/energy balance and paired glide traces; compare to independent glide/prop evidence with uncertainty. The old no-prop L/D 8.46 is a historical baseline, not an acceptance band for every prop state. |
| G1e | Propeller normal force and P-factor at the hub (blade term plus jet term) | Sign tests; within ±30 % of the BEM table (12×6: 0.11 N·m at 15 m/s and α 10°; P-51 26×12: 2.3 N·m) |
| G2a | After H8, integrate rotor speed with rigid-body state and stage-local air-relative inflow: I·dω/dt = Q_engine − Q_prop − Q_friction | Smooth coupled throttle/inflow transient converges at the intended order; actual 240 Hz error reported, not only a ratio. Preserve legacy behavior for aircraft without shaft data. P-51 current split update is characterized as first-order; update goldens deliberately. |
| G2b | Rotor-acceleration reaction −dh/dt with consistent momentum accounting for propeller and turbine rotor models | Sign, magnitude and total angular-momentum checks under spin-up/down; no double-counting steady shaft torque or gyroscopic precession; mutation caught. |
| G2c | Throttle actuator: servo slew, carburettor admitted-fraction table, combustion delay | Step trace vs the owner's phone-audio rpm trace (VAL-7) within a band set beforehand |
| G2d | Engine states OFF / CRANKING / RUNNING in the H8 state; stop below 0.8·idle (JSBSim rule); starter; `engine_running` retired | An idle trimmed below the stall rpm stops within 2 s and stays stopped |
| G2e | Realism layer, deterministic and off by default: rich-idle flooding, plug cool-down, lean cut on a fast throttle | Unit test per state; with the toggle off, goldens unchanged |
| G3a | Per-tick sound snapshot (rpm, crank angle, load, thrust, airspeed, position) and tone data (`engine.cycle`, cylinders, blades). Audio reads only the snapshot | Trace and frame-rate hashes identical with sound on and off |
| G3b | Low-latency audio (a ~50 ms queue; the placeholder adds ~186 ms) with a wavetable core (3.1 vs 14.8 ms of CPU per second of audio) | An rpm step is heard within 70 ms; no underruns at 30/60/144 fps |
| G3c | Engine tones (firing at rpm/60 for a 2-stroke) and propeller tones (blade passing at blades·rpm/60), levels vs rpm and load | Offline Goertzel: peaks at the predicted orders ≥ 40 dB above the floor |
| G3d | Own propagation: travel delay and Doppler from geometry, spherical spreading, ISO 9613-1 air absorption. Godot's 3D Doppler (no travel delay) and distance filter (−16 dB at 25 m) are turned off | Pitch ratio ±0.5 %; onset delay ±1 ms; −23.1 dB from 7 to 100 m |
| G3e | Dead stick, windmill and airframe noise; load timbre from G2; ground reflection; buses and a limiter (UI-08) | Offline spectra per state; bus mute test |
| G3f | Fit to the owner's recordings (.61 + 12×6 at 3 m, 7 m and a fly-by, with a tachometer; licence chosen by the owner) and a blind ABX test | Orders 1–8 within 3 dB at three rpm points; ABX results in the PT4 notes |
| G4a | After H8, fuel tank state and burn map; the engine stops when empty | Full-throttle burn-out time within 5 % of the hand calculation |
| G4b | Shared time-varying mass, CG and inertia contract for fuel consumption and later CR-13 component loss; specify frame/reference shifts and momentum effects | Hand-computed mass/CG/inertia updates, reset/rollback/replay under H8, physical momentum bookkeeping for the stated process; unchanged no-consumption/no-loss paths. Fuel and damage use the same contract. |
| G5 | Several power plants (`powerplants[]`, with DATA-14) | Counter-rotating twin: net reaction torque 0 ± 1e-12; engine-out yaw sign |
| PT4 | Playtest v0.4 | Owner judges throttle response, idle reliability and sound with the PT4 checklist in [05](docs/research/roadmap-investigations/05-propulsion-engines-motors.md) |

#### M4b — Electric propulsion (optional next product slice)

EL1 needs the H8/G2a shaft contract and matched motor/prop data; it does **not** wait for nitro failures, acoustic propagation or fuel burn. Choose its priority after Gate 2; add EL2–4 only with measured need and state/validation coverage.

| # | Step | Proof |
| --- | --- | --- |
| EL1 | Drela three-constant motor (Kv, R, I0), averaged ESC and an ideal battery; an electric Stik variant | Operating point vs the hand calculation; the variant trims and passes the handling test |
| EL2 | LiPo battery: open-circuit voltage vs state of charge, internal resistance, one RC pair; state of charge in the H8 state | Voltage-sag trace on a throttle punch vs the hand calculation |
| EL3 | ESC behaviours (Hobbywing manual values): start ramp, soft and hard low-voltage cut-off, brake vs freewheel, signal-loss cut, arming | Unit test per mode; the brake gives a stopped-prop glide |
| EL4 | Winding temperature with R(T); ESC derating | Sustained full throttle plateaus; derating at the threshold |
| EL5 | Static operating point vs measured data (a test-stand dataset or the owner's wattmeter) | Current and thrust within ±10 % |
| EL6 | Flight time vs telemetry (mAh per minute of a pattern) | Within ±15 % |

Turbine: AV-05a (spool ≈ 3 s up, ≈ 1.9 s down) and AV-05b (ECU states) belong to the [Avanti plan](docs/AVANTI-S-PLAN.md), using [05](docs/research/roadmap-investigations/05-propulsion-engines-motors.md).

### M5 — Atmosphere and advanced flight envelopes

These are separate acceptance groups, selected by pilot evidence rather than one large release:

| Group | Entry dependency | Acceptance boundary |
| --- | --- | --- |
| Atmosphere (ATM) | One density/environment input shared by trim, loads, propulsion and trace | Minimal density consistency before comparisons at different elevation/temperature; fixed sea-level remains acceptable when explicitly scoped. Humidity/weather UI can wait. |
| Wind and turbulence | H8 stage time and sampled/discrete state; current local-airflow contract | Calm baseline, deterministic forcing/replay and independent statistical checks, then Gates W-A/W-B. Thermals, slope lift and tree wakes are optional breadth. |
| Stall/spin and ground effect | D11 approach consistency and relevant independent maneuvers | Separate steady, transient and recovery envelopes with uncertainty; H8 before new separation states. No mandatory DATA-8 migration. |
| Advanced propulsion and aids | Validated base response for the target maneuver | Hover/wing wash and gyro aids opt-in; unchanged unaided path; one aircraft/task at a time. |

Smoke, camera, settings and possible web/VR exports stay in their owning tracks; they are not completion criteria for the atmospheric model.

Proposed sub-steps (retained from review #4; scenario-specific numerical bands below require an applicability check before implementation, rather than being universal aircraft targets; knowledge: [07](docs/research/roadmap-investigations/07-atmosphere-wind-turbulence.md), [02](docs/research/roadmap-investigations/02-aerodynamics-rc-scale.md), [03](docs/research/roadmap-investigations/03-propeller-propwash.md), [06](docs/research/roadmap-investigations/06-radio-input-servos-latency.md)). [WIND-PLAN](docs/WIND-PLAN.md) keeps its M5-W numbering; *new* marks what extends it.

| # | Step | Proof |
| --- | --- | --- |
| M5-ATM-1 | Atmosphere module: ISA plus temperature, QNH and humidity (ideal gas + Buck); the default returns the literal 1.225 | Table within ±0.05 %; goldens byte-identical (computing 1.225 from the constants gives 1.2250000181) |
| M5-ATM-2 | Field elevation and weather in the field and weather data; ρ flows through the session, trim, HUD and trace | A trim at σ 0.78 needs V × 1.132 at the same α |
| M5-ATM-3 | Apply the selected atmosphere consistently to each propulsion kind; start with the justified density correction for combustion-engine torque in G2a | Per-kind limiting cases and coupled static operating-point comparisons at stated density; do not impose combustion-engine scaling on electric or turbine models without their own evidence. |
| M5-W04a/c | OU turbulence parametrised as the MIL-HDBK-1797 first-order form (σ from W20, scale length from height); *new:* xoshiro128** generator with the seed in the trace header | Welch PSD vs MIL; the first 1000 outputs equal the C reference |
| M5-W05c/d | Wind and its gradient sampled per RK4 stage; each surface sees v + ω×r − G·r; *new:* Dryden p, q, r gusts | Rotational equivalence to 1e-12 (rolling at p in still air = a field with ∂W_z/∂y = −p); double-count guard |
| M5-W08a | *New:* treeline wake from the field data (height, porosity): velocity deficit and turbulence factor. The flying area sits in the wake for most wind directions | Profiles at 2/5/10/20/30 tree heights match the sourced endpoints; owner A/B |
| M5-W08b | *New:* Allen (2006) thermals with drift | Published check case; mass balance ≈ 0 |
| M5-W08c/d | *New:* slope lift (cylinder, then a panel method on L13 hills); dynamic-soaring shear layer (long term) | Cylinder closed form; Rayleigh-cycle energy gain |
| M5-W-T | Trace columns for ρ, wind, gust rates and seed; replay from recorded wind (turbulence is bit-identical only per platform) | Cross-platform replay equal with recorded wind |
| M5-GE-1/2 | Ground effect on the wing strips (per-strip height), then on the tail downwash | Flare: ≈ 4° extra up-elevator at h/b 0.17 (±50 %) |
| M5-STALL-1 | Per-strip 360° tables (Viterna), as a validated optional data extension; v2 only if DATA-8 is justified | Continuity sweep; post-stall CL/CD ≈ 1/tan α |
| M5-STALL-2 | Goman–Khrabrov separation state per strip (stall hysteresis) | α̇ = 0 is bit-identical to static; a closed hysteresis loop; cycle passivity |
| M5-STALL-3 | Control effectiveness in stalled flow | Slow-flight aileron-reversal sign test |
| M5-SPIN-1/2 | Fuselage crossflow segments (knife edge), then tail shielding in spins | Knife-edge β band; spin recovery turns vs a pilot band |
| M5-PROP-1…3 | Wing-root wash and swirl roll; 3D hover (torque roll, vortex ring in tail slides); a measured diffusion profile | Static roll ≈ 40 % of torque ±15 %; a scripted hover at T/W ≥ 1 |
| M5-AIDS-1…4 | Gyro "receiver", off by default: rate damping, envelope and self-level, panic recovery, trainer with two devices | Gust roll rate decays ≥ 2× faster; ≥ 99 % of 100 random attitudes recover above 10 m; no-aid goldens identical |

## Parallel programs (plan review #4)

Three programs support chosen milestones; they are not three additional mandatory releases. Each step needs a named consumer and a proof. VAL measurements run early; DATA tooling follows actual pipeline risks; PERC is selected by Gate 2/Gate L evidence.

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

### DATA — reliable aircraft inputs and a conditional schema evolution

Knowledge: [09](docs/research/roadmap-investigations/09-aircraft-data-pipeline.md).

| # | Step | Proof |
| --- | --- | --- |
| DATA-1 ✅ | P-51 `build_geometry`, `compile_geometry` and `derive_physics --check` in CI next to the Extra's | 2026-10-06: all three checks precede app tests. Proof: `actionlint`; exact workflow step passes in a fresh clone, rejects five independently stale output/source cases without rewriting, then passes after restoration. [Report and reproducible evidence](docs/research/aircraft-validation/DATA-1/README.md). |
| DATA-2 | Cheap stall-start solve: one bisection takes 110 ms of the 119 ms aircraft load | Solved angles unchanged ≤ 1e-12 rad; load ≤ 15 ms; goldens unchanged |
| DATA-3 | Hash exact input file bytes and record the hash plus trace/schema identity; distinguish any canonical semantic hash by name | A changed late digit changes the raw hash; saved artifact reproduces it exactly. Readers explicitly handle legacy headers. Before new reference datasets; paired with C7-R2 active-feature metadata. |
| DATA-4 | JSON Schema 2020-12 for v1, checked in CI | The schema rejects every shape mutation the loader rejects |
| DATA-5 | Extract only duplicated Extra/P-51 derivation helpers whose conventions already agree; keep aircraft-specific derivations visible | Both generator `--check` outputs byte-identical; one documented unit/frame convention per extracted helper. No unified generator rewrite just to reduce file count. |
| DATA-6 | Inventory shapes (box, cylinder, tube, sphere, point) | Closed-form inertia tests to 1e-12 |
| DATA-7 | A shared `openrc-geometry v1` schema for the three aircraft | Compiler outputs byte-identical; the model teams' verify scripts pass |
| DATA-8 (conditional) | Introduce `openrc-aircraft v2` only for an approved consumer v1 cannot represent cleanly; prototype the smallest migration, then consider an ID-keyed component model | Written consumer/limitations comparison; old files still load; resolved models and existing trajectories unchanged; migration/provenance tested. H8, PT2, new v1 aircraft and per-strip polars do not require v2. |
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

### Owner's field kit (schedule by available aircraft and equipment)

The cheapest, most valuable independent data. Each item names the steps it feeds; record the method, photos and raw numbers.

1. Weight, three-scale CG, throws at five stick positions, trims after a flight, servo speed (240 fps phone video) → VAL-5, D11, F7.
2. Bifilar swing test for Ixx (≈ $10, 2 h), then Izz and Iyy → VAL-6, D11e. This tests the leading explanation of the roll gap; include suspension/measurement uncertainty and keep apparent-air effects separate.
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

> Historical review snapshot. Completed work, timings, proposed priorities and owner questions below describe that review, not the current queue. Revision 5 [execution order](#execution-order-and-release-gates) and the current step rows supersede them.

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

> Historical review snapshot. Completed work, timings, proposed priorities and owner questions below describe that review, not the current queue. Revision 5 [execution order](#execution-order-and-release-gates) and the current step rows supersede them.

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

> Historical review snapshot. Completed work, timings, proposed priorities and owner questions below describe that review, not the current queue. Revision 5 [execution order](#execution-order-and-release-gates) and the current step rows supersede them.

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

> Historical review snapshot. Completed work, timings, proposed priorities and owner questions below describe that review, not the current queue. Revision 5 [execution order](#execution-order-and-release-gates) and the current step rows supersede them.

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

**Superseded execution order:** revision 5 moves H8 before anchors, adds Cnr acceptance, profiles all aircraft and makes VLM/data v2 conditional. Follow the [current execution order](#execution-order-and-release-gates). The owner's measurements can run in parallel.
