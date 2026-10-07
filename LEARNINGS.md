# Learnings

Practical lessons from **actually building and running** things, as opposed to reading about them (that is [RESEARCH.md](RESEARCH.md)). Each entry says what happened, what we learned, and what we now do differently, with its evidence linked. The thematic sections at the top hold cross-cutting lessons, newest first; after them, each track appends its dated entries at the end of the file under `## YYYY-MM-DD · <step IDs> — title`. Where everything else lives: [docs/README.md](docs/README.md).

## Process

- **A full-envelope test at zero angular rates does not validate rotating flight.** A 925-state probe found positive total aerodynamic power in 46 states and a ~1,842 N force discontinuity across reverse flow with p=5 rad/s; the existing envelope and spin checks still pass. None of the 26 ordinary pulse flights sampled positive aerodynamic power, so this is a separate defect, not an established cause of the rudder pulse failure. Reducing Cndr to 30% also breaks the existing spin-recovery sequence. Test coupled maneuvers and local-flow consistency before accepting a tuning change. [Audit](docs/research/flight-model-robustness-audit.md), [plan](docs/FLIGHT-MODEL-ROBUSTNESS-PLAN.md). (2026-10-05; research, production physics unchanged)

- **A correct rudder sign and a passing golden can preserve excessive authority.** The current Ugly Stik reaches 42.41° sideslip and 462.14°/s body yaw rate in a 0.5 s rudder pulse; keyboard, fake radio and engine-off cases reproduce the problem. Changing only `Cndr` to 30% in memory reduces the doublet peaks to 21.73° and 88.24°/s, but does not independently validate that coefficient. The servo returns to trim while autorotation persists. Handling needs magnitude and recovery checks with independent evidence, not only direction or replay. [Diagnosis](docs/research/ugly-stik-rudder-audit.md) and [repair plan](docs/RUDDER-REPAIR-PLAN.md). (2026-10-05, D8b/D10 investigation; production physics unchanged)

- **A metric's mask must contain only what it claims to measure.** The airplane-readability metric took the airplane as "pixels that change when the airplane is hidden", which also caught the D7 ground shadow (and, once, the panel text that names the shadow mode). That contamination made L1b look unreachable after L2, and I reported a threshold recalibration that was wrong. Measured cleanly, the original thresholds pass. Now the readability views turn the shadow off in both images of a pair. (2026-10-05)
- **A mutation that does not fail finds bugs in the code it was meant to test.** Turning engine shadows on "by mutation" changed nothing, because `--engine_shadows` was applied after the sun had been built. The Gate L comparison option had never worked. (2026-10-05)

- **A radio can navigate a Godot menu even when we never assign its sticks to UI.** The pinned 4.7.2 `InputMap::get_builtins()` source already maps joystick axes to directional UI actions. The menu plan now requires an explicit navigation map and a regression case where moving RC sticks cannot change focus. A reproducible palette calculation also found that the proposed red on dark panel is only 2.61:1, so it cannot be the sole control boundary under the adopted 3:1 target. These are source inspection and calculated evidence, not a menu runtime test. [Ten menu investigations](docs/research/menu-investigations/README.md). (2026-10-05, UI research)

- **Menu planning exposed a distinction between pausing physics and pausing a flight session.** Code inspection found that `FlightSession._physics_process()` still polls controls and advances the crash restart counter while `sim.paused` is true; presentation/audio also update separately. A menu must coordinate these paths while keeping calibration responsive. The plan separates fields from initial-flight scenarios and product releases from model/schema revisions. This is inspection evidence, not a new runtime test. [Menu plan](docs/MENU-PLAN.md). (2026-10-05, UI planning)

- **A fix can invalidate an earlier calibration; re-measure instead of defending it.** L2's colour-space fix made the sky correctly brighter, and L1b's tonemap choice (picked against the mis-encoded sky) stopped passing its own readability thresholds. A second sweep showed no setting can, so the thresholds had come from the same error. The guard now protects the corrected baseline, and the absolute target moved to the human gate. (2026-10-05)

- **Look at trajectories before writing assertions about new physics.** D9b took four model versions, each rejected by reading a printed trajectory, not by a failing assert: (1) two strips per wing → roll ran away to 30 rad/s; (2) a drag artefact (linear induced drag evaluated past the stall) → absurd yaw; (3) three strips, still lift-based → 19 rad/s; (4) roll from the **normal force**: a flat plate's normal force keeps growing to 90° while its lift falls after 45°, and only then did the spin look like a spin (~1 turn/s, 11 m/s sink, standard recovery works). Each wrong version would have passed assertions written up front for "it spins". (2026-10-05)

- **When a golden flight changes, find out why before re-recording it.** D9a changed one golden of four. The "gentle" rudder doublet had reached β 55° and α 25° even before, so the old golden recorded the linear model far outside its validity, and the new model stalls there (α 60°). The other three goldens stayed byte-identical, which proves in real flight that the linear oracle holds where the flow is attached. The same look found a data problem: full rudder trims at β 62° with the borrowed derivatives. (2026-10-05)

- **A number repeated from a formula is not a measurement.** The roadmap said the sim rolls at "192°/s at 20 m/s (predicted 192)"; it was the prediction formula evaluated in a unit test. Flown through the real loop, the airplane rolls at 166°/s with the feet still (adverse yaw builds sideslip, the dihedral effect slows the roll) and at 189°/s with the rudder coordinating. Both are right; only the flown ones say how the airplane behaves. *Now:* handling claims come from maneuvers flown in `test_handling.gd`. (2026-10-05)
- **A first real-loop check finds the hidden coupling.** The dead-stick glide came out at L/D 5.9 instead of 8.46. The loop drove a "stopped" engine back to idle, and the idling propeller's extrapolated thrust floor (Ct −0.1 beyond the data) dragged it down. One test exposed a missing engine state and a questionable extrapolation. (2026-10-05)

- **Parse-check a new module before wiring it in.** `render/shadow.gd` used `for pass in 2:` (`pass` is a keyword); once `main.gd` preloaded it, the main scene failed to load and every end-to-end test hung until its timeout, about two minutes of a broken tree that the owner could have committed. *Now:* each new script gets `--check-only` on its own first, and only then is preloaded by `main.gd`. (2026-10-05)
- **Geometry decides what a pilot aid can do; check it with a capture before trusting it.** The ground shadow was correct (the close-up at 0.8 m shows it exactly under the airplane), but from the pilot's eye 1.7 m up and 77 m away the ground is seen at ~1.3°, so the shadow projects to under one pixel. The same low capture also showed auto-zoom pushing the ground out of frame at altitude. Both go to Gate 2 as questions, not as fixes guessed now. (2026-10-05)

- **A safety rule needs a mutation that shows the danger.** Removing the arming rule in a scratch copy made six checks fail, and the failure message itself showed the hazard: engine at 50 % with every axis reading 0, i.e. a radio that was plugged in but never touched. Keep that kind of message in the test detail, because it explains why the rule exists. (2026-10-05)

- **A refactor's proof is "nothing changed", measured in bytes.** D5.9 moved half of `main.gd` and the control throws into new homes. The proof was the `--trace` file hashing identical (SHA-256 `97c4e73c…`) and five captures byte-identical. That needed a baseline taken *before* editing, and a check that captures repeat run to run (they do). The byte comparison also froze a real defect in place (physics captures draw surfaces without trims); it is recorded and fixed in its own step. (2026-10-05)

- **Verification is not validation.** Every handling check so far compared the sim with numbers computed from its own borrowed coefficients, so all of them could pass while the airplane feels wrong. Linearizing the real equations took ~80 lines and a few seconds (`research/flight-modes/`). It gave the first independent comparison: against a flight-identified Ultra Stick 120, the sim is 1.45× faster in pitch and 1.9× faster in roll. *Now:* each physics milestone needs one check against data we did not derive (ROADMAP rule 6). (2026-10-05)
- **Compare like with like before concluding.** At the same airspeed the sim's modes looked 1.6–2.9× faster than the Ultra Stick 120's; at the same lift coefficient (our wing loading is half theirs) the gap was 1.16–1.9×. The scaling choice changed the conclusion. *Now:* comparisons between airplanes state their scaling (Froude, same CL). (2026-10-05)

- **Prop torque decides whether "hands-off" means anything.** With a longitudinal-only trim, the 0.1 N·m cruise torque rolled the airplane into a spiral: 26 m lost in 30 s. Six-axis trim needs only 2.2 % right aileron, like a real nitro Stik. Physics that pilots *feel* (torque, trim) belongs in the first flyable version. (2026-10-05)
- **The panel must show what the airplane actually does.** The capture panel showed a capture argument (throttle 50 %) and stick-only surfaces while the engine ran at 28 % with trims applied. *Now:* surfaces show stick plus trims, and physics captures show the real commands. (2026-10-05)

- **A test's expectation can be the bug.** "Right rudder → side force to the right" was my intuition; physics says the fin is pushed **left** (it deflects air right), which swings the nose right. The model and the borrowed data agreed; the test was wrong. *Now:* every sign test states the physical reason in its name. (2026-10-05)
- **Compare the live app's trace with the solver.** All unit tests passed while the app's headless `--trace` path flew with zero elevator trim and dived (sink 4.6 m/s instead of 1.76). Only comparing the app's own trace with the trim solver exposed it: synchronous paths never run `_process`, where inputs were set. *Now:* `test.sh` runs the real app headless and checks the glide (`tests/check_trimmed_glide.py`). (2026-10-05)
- **Layered guards catch what a single test misses.** A trim mutation (pitch moment ignored) was caught first by the app's `push_error` plus the engine-error guard, before the dedicated trim test even ran. (2026-10-05)

- **Measure the project before re-planning it.** Plan review #2 started from numbers: suite time 21 s, 25 commits with 65 generated-file changes, 1343 lines of visual code vs 425 of physics, no export presets, zero human flights. The numbers made the gap obvious: excellent foundations, nothing playable. *Now:* remaining work is organized as milestones that each end in a build the owner flies, with acceptance targets computed from the data (the predicted-handling table). (2026-10-05)

- **A hand balance is a cheap cross-check of someone else's geometry.** Plausible component masses on the visual model put the CG ahead of the wing's leading edge, which is impossible for a flying airplane. The full-size plan then showed the nose (firewall to LE) is 6.94 in, while the provisional visual model has ~12.8 in. One physics sanity check found a visual-geometry error that no screenshot showed. (2026-10-05)
- **Full-size plans are measuring instruments.** At 100 dpi a 1:1 plan gives 100 px per inch; the chord read 12.07 in against the title block's 12.00 in, a 0.6 % scale check. Read features with zoomed crops and pixel rulers; automatic edge search clipped at its window bounds and gave nonsense. (2026-10-05)
- **Validate your own data with the same loader.** The new loader's first run rejected my own data file (an empty source). (2026-10-05)

- **Review a parallel team's work at the seams, not the pixels.** The model team's work was good, but four integration risks only showed up at the boundaries:
  - their 439-check verifier and their JSON→GDScript sync check existed but **nothing ran them**;
  - my control test still read the dead blockout tables;
  - the wing area differed between documents (720 vs 723 in²);
  - the visual origin is not the CG, which matters for D1.
  *Now:* every team-owned check is wired into `test.sh` or CI, and cross-document numbers are compared during reviews. (2026-10-05)

- **Check every sample against its own timestamp, not only the final value.** A deliberate "emit the trace row before incrementing the tick" bug survived the first trace tests: the final state was right, but every row was labeled one tick early (0.06 m error against its time), and duplicate ticks were not flagged. *Now:* traces must be strictly continuous (`is_continuous()`), and physics checks run on every row. (2026-10-05)
- **One shared parse check means one person's draft can break everyone's run.** A work-in-progress `app/aircraft/verify_model.gd` with type-inference parse errors (`:=` on untyped Dictionary values) made `app/test.sh` fail for all. The guard was right; the fix is process: drafts are checked before they land in `app/`. (2026-10-05)

- **Mutation checks must not touch the shared working tree.** The owner committed while a deliberately broken `q_mul` was on disk for a few seconds, so a local commit contains the bug (caught before any push). *Now:* deliberate breaks run on a copy of `app/` in a scratch folder, never in place. (2026-10-05)

- **A guard needs its own mutation check.** The first float64 guard did not fire: `grep` exits with 2 when one listed folder doesn't exist yet (`physics/`), even when it finds a match, so `if grep …` was false. Only the deliberate `Vector3` test revealed it. *Now:* every guard or check gets a deliberate violation before it counts. (2026-10-05)
- **Scores inform; the owner decides.** The bake-off scored three.js higher; the owner chose Godot for native radio input and the editor. The plan absorbed it by turning the main weakness (32-bit vectors) into an automatic check and naming an escape hatch (C++ GDExtension). (2026-10-05)
- **Other assistants may work in the same repo at the same time.** While I worked, another assistant wrote `docs/UGLY-STIK-PLAN.md` and `docs/research/`, and created `references/ugly-stik/`. *Now:* before moving files, grep the whole repo (including `docs/`) for old paths and fix the links; leave a dated note in shared plans. (2026-10-05)

- **Watch a test fail before trusting it.** In B4 we deliberately flipped one axis sign. Both test suites caught it (2 failures, non-zero exit) and passed again once it was restored. *Now:* every new known-answer test gets one deliberate break before it counts as proof. (2026-10-05)
- **Fix comparison criteria before seeing results.** The bake-off criteria and weights were written before the Godot build ([COMPARISON.md](prototypes/stage0/COMPARISON.md)). *Now:* any A-vs-B choice defines its scoring first. (2026-10-05)
- **Order bias is real.** The second build (Godot) took half the time of the first, largely because it reused the proven structure. *Now:* timing comparisons note which build went first; effort numbers alone are not decisive. (2026-10-05)
- **Confirm the reference object early.** The model was first built as a Hangar 9 Ultra Stick; the owner's plan images showed **Das Ugly Stik 60**. Because every number lived in one spec file, switching cost 30 s. *Now:* keep all numbers in one place per build, and ask for references before modeling. (2026-10-05)

- **Test the real input path, not only the pure functions.** Pure limiter tests passed, but only an end-to-end test (real key events → panel) proves the wiring. Both builds now have one. Panel text updates one frame after a key event, so e2e checks must wait a frame before reading it. (2026-10-05)

## Rendering and evidence

- **A setting chosen in a spike must pass its proof again in the real harness.** Investigation 09 picked Filmic at exposure 0.8 from a spike. With today's airplane and sky it failed the step's own readability thresholds (contrast −0.36, ΔE 29.6). A six-setting sweep with the same metric found ACES 0.6 as the only pass. The thresholds stayed fixed; the setting moved. (2026-10-05)

- **Count before you budget.** The landscape plan's first budget was ≤ 150 draw calls in the pilot view. The L0 counters (`Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, deterministic under llvmpipe) showed the airplane alone uses ~100 of them, while the empty landscape uses 4–6. A budget that ignores its biggest consumer means nothing. (2026-10-05)

- **Gravity alone makes the airplane fall flat** (wings level, nose not following the path), because nothing turns it into the airflow until aerodynamics exist. Correct for C6, and a useful visual baseline: once weathervane stability is added in Phase D, the nose should follow the flight path. (2026-10-05)

- **Attach the inspection camera to the airplane, not the world.** A world-fixed close-up often saw the airplane from the front, so deflections were barely visible. A camera fixed at a model offset (left, above, behind) shows the surfaces the same way in every pose. (2026-10-05)

- **The pilot view cannot verify geometry.** From the pilot's position the airplane is ~15 px wide at ~87 m (1280×720, 50° vertical FOV). That is realistic for RC, and a core readability problem. *Now:* every build has a close-up "inspect" capture alongside the pilot view. (2026-10-05)
- **Two independent builds can cross-check each other.** three.js and Godot each implement the NED → render conversion separately, and their captures show the same position, attitude and framing. *Now:* visual parity between builds is cheap extra evidence. (2026-10-05)
- **Software rendering is enough for captures, not for performance.** This machine has no GPU: Chromium uses SwiftShader and Godot uses Mesa llvmpipe (OpenGL 4.5). Both capture correctly in ~1.5 s. *Now:* performance is judged only on real hardware. (2026-10-05)
- **three.js captures need `preserveDrawingBuffer: true`** (capture mode only), and Chromium needs `--use-angle=swiftshader --enable-unsafe-swiftshader` when there is no GPU. (2026-10-05)

## Toolchain

- **TypeScript 7.0 + Vite 8 + Vitest 5 work together with no friction.** Type check 0.5 s, 8 tests 0.8 s. With TS 7's new defaults, `"types": []` keeps the type check focused. (2026-10-05)
- **three.js is one ~530 KB chunk (132 KB gzip).** Vite warns about chunks over 500 KB; harmless for now. (2026-10-05)

## Godot specifics

- **Engine shadows in Compatibility cost more than draw calls.** The shadowed light is drawn in an additive pass blended in sRGB after tonemapping (Godot #90259, PR #98656 unmerged, searched 2026-10-05). The lit wing came out +14 % brighter, with a hue shift, clipped whites, and doubled draw calls. A planar shadow projected along the light (one quad) gives the pilot the same cue with none of that. (2026-10-05)

- **In Compatibility, a sky shader's `COLOR` is sRGB, not linear.** GLES3 `sky.glsl` (4.7.2, line 250) runs `srgb_to_linear()` (a cubic approximation) on our output, while spatial shaders and fog work in linear. A sky that computes the engine's fog formula in linear therefore comes out darker than the fog it should match (158 vs 203 levels at the ground's rim). The fix is to encode with the exact inverse of that cubic. It also means every earlier sky colour had been displayed darker than intended. A colour seam was the symptom; the engine source was the answer. (2026-10-05)

- **Global shader parameters can be set at runtime, but not read back.** `RenderingServer.global_shader_parameter_get` and `_get_list` print "should never be used outside the editor" and return null under a real renderer, while headless they quietly seem to work. `capture.sh`'s new engine-error guard caught it the first time it ran. *Now:* code remembers the values it sends (`ShaderClock.last_clock`). (2026-10-05)

- **A source-read claim is still a claim until a build tests it.** The export research said `.json` files are left out without an include filter, and that the app would refuse to fly. Exporting without the filter showed the opposite in 4.7.2: the JSON is a recognised resource and `all_resources` ships it. The smoke test of the exported binary decided it, and a mutation that really removes the data (`exclude_filter="data/*"`) showed the test has teeth. The same smoke test exposed that `--trace` on invalid data recorded a ballistic fall instead of failing; it now exits 1. (2026-10-05)
- **A macOS export from Linux can be checked without a Mac.** Parsing the zip's Mach-O (fat header → each slice's `LC_CODE_SIGNATURE` → the CodeDirectory's `CS_ADHOC` flag) verifies "universal and ad-hoc signed" in 60 lines of Python. Even an export with signing disabled carries a (non-ad-hoc) signature from the template, so checking only for "signed" would pass the wrong build. (2026-10-05)

- **Wait for ticks, not seconds, in end-to-end tests.** A first radio test waited `create_timer(0.05)` after a connection and once read the old keyboard throttle: no physics tick had run yet (most likely a slow first frame consumed the timer). `await physics_frame` fires *before* a tick, so four awaits guarantee three complete ticks; two `process_frame` awaits then let the panel update. Five repeated runs passed after the change. (2026-10-05)
- **A fake joypad works headless:** emit `Input.joy_connection_changed` with id 15 and inject `InputEventJoypadMotion` events; `Input.get_joy_axis(15, axis)` then returns the injected values. Replace anything that calls `get_joy_guid`/`get_joy_info` on the fake id, because those print engine errors that fail `test.sh`. Godot keeps the fake device's last axis values after an unplug, which made "replug with the throttle high stays safe" testable. (2026-10-05)

- **A scene added from a test's `_initialize` becomes ready only after the first physics tick.** The simulation's tick counter therefore lags the global tick by one. Frames end on global ticks 40k at 30, 60 and 144 fps alike, so frame-aligned key injection uses simulation ticks 40k − 1 (119, 239, 359). The harness fails loudly if a scheduled tick is not a frame end, instead of silently sampling at different ticks. (2026-10-05)
- **`process_physics_priority` makes the order of fixed-step work explicit.** The flight session (priority −1) shapes the pilot's commands before the simulation (its child, priority 0) steps, in the same tick. Tree order would give the same result today, but it is an implicit rule that a scene move could break. (2026-10-05)

- **Read the engine source when the docs are thin; Godot's docs can be out of date.** Reading the 4.7.2-stable tag found facts no doc page states:
  - a universal macOS export fails without `import_etc2_astc`;
  - `.json` files are exported only through an include filter;
  - joystick axes read 0 until moved;
  - accumulated input delays joypads one frame on Linux/macOS;
  - `agile_event_flushing` works on every platform, although the docs say Android only.

  Godot's macOS page still recommends right-click → Open, which macOS 15 removed. *Now:* risky platform steps (input, export) start with a source read of the pinned tag. (2026-10-05)

- **Aerodynamics and propulsion doubled the physics cost:** 85 → ~185 µs per RK4 step (four derivative evaluations, each doing Dictionary lookups of coefficients), still 21–24× real time at 240 Hz on this VM. If headroom is ever needed, flattening the coefficient Dictionaries into arrays is the cheap first move. (2026-10-05)

- **`:=` cannot infer types from Dictionary values** (they are Variants). I hit it in `aero.gd` right after warning the model team about it. Use explicit types (`var x: float = d.key`) whenever the right side reads a Dictionary or an untyped Array. (2026-10-05)

- **Godot's `--fixed-fps N` makes frame-rate independence testable.** Running the same scripted flight with `--fixed-fps 30/60/144` and hashing the final state (SHA-256 of the `PackedFloat64Array` bytes) proves physics doesn't depend on rendering: identical hashes. A deliberate "step with the frame delta" bug changes the hashes at once. Runs must end at an exact tick (`stop_at_tick`), because at 144 fps a frame can contain two ticks. (2026-10-05)

- **Godot runtime script errors do not fail a run.** A bad format string printed `ERROR:` while the test reported success and exited 0. *Now:* `test.sh` fails if any `ERROR:` / `SCRIPT ERROR:` line appears, verified with a deliberate runtime error. Errors Godot can see at parse time are caught earlier by the parse check. (2026-10-05)
- **GDScript's `%` formatting has no `%e` or `%g`;** use `String.num_scientific()`. The engine-error guard catches it. (2026-10-05)
- **GDScript is fast enough for one airplane's rigid body:** RK4 with a `Callable` derivative and `PackedFloat64Array` state takes ~85 µs per 240 Hz step, about 50× real time, roughly 2% of a 60 fps frame. (2026-10-05)

- **The float32 problem is real inside Godot too.** A test adds a 1e-4 m/s² acceleration for 60 s at 240 Hz: `Vector3` ends with exactly 0 change; the `PackedFloat64Array` helpers give 0.006 m/s (exact). The contrast now lives in `tests/test_math3d.gd`. (2026-10-05)
- **Property tests over a seeded random sample** (500 attitudes) caught a quaternion-product bug that every single known-answer case missed; only the composition property exposed it. *Now:* math helpers get both known answers and seeded properties. (2026-10-05)

- **A script parse error hangs a headless run forever.** A constant named `Panel` shadowed Godot's built-in `Panel` class; `main.gd` failed to load, nothing called `quit()`, and Godot spun at 400% CPU. The unit tests passed because they never load `main.gd`. *Now:* `test.sh` parses **every** script with `--check-only` (verified to exit 1 on a broken script), and every capture runs under `timeout 60`. Avoid naming constants after built-in classes (`Panel`, `Label`, `Timer`, …). (2026-10-05)
- **Godot can test real input without a display:** load the main scene headless, inject events with `Input.parse_input_event`, wait with `create_timer`, and read the UI. (2026-10-05)

- **`Vector3` and `Basis` are 32-bit; GDScript `float` is 64-bit.** The scripted pose keeps positions as arrays of floats; tests at the render boundary need a 1e-6 tolerance. Real physics in Godot would need this discipline everywhere. (2026-10-05)
- **Tests need no add-on:** a script with `extends SceneTree`, run with `--headless --script`, can check and `quit(1)` on failure. 15 checks in 0.2 s. (2026-10-05)
- **Headless capture:** run under `xvfb-run` with `--rendering-driver opengl3`, then wait for `RenderingServer.frame_post_draw` twice before reading the viewport image. `--audio-driver Dummy` silences errors on machines without sound. (2026-10-05)
- **`BoxMesh` takes one material,** so a wing panel with a different underside is built as two half-thickness boxes. (2026-10-05)
- **A script-only project needs no editor and no import step.** Godot ran straight from text files; the pinned binary is 78 MB to download (146 MB unpacked) and is verified by SHA-512. (2026-10-05)

## CI

- **`act` needs `--artifact-server-path` for `upload-artifact` v4.** Without it the step fails locally while the job is fine; with it, `act -j export` ran the whole release job in a clean container (template download, three exports, smoke test, signature check, artifact upload). (2026-10-05)

- **`act` is not a clean checkout.** It copies the working directory, including ignored and untracked folders. After `app/captures/` was untracked, GitHub's fresh checkout lacked the folder, Godot could not save the PNG (error 7), and CI went red; locally and in `act` it passed. *Now:* `capture.sh` and the app create their output folders. Changes to `.gitignore`, paths or generated files are verified from a fresh `git clone` (with `.tools/` linked in). (2026-10-05)

- **A CI step must not rely on the system Python.** `check_landscape_captures.py` ran on `python3` and passed locally and under `act`; GitHub's runner has no Pillow, so CI on main failed (`ModuleNotFoundError: PIL`). This VM has Ubuntu's `python3-pil` and `python3-numpy` (and a second Pillow in `~/.local`), so even `PYTHONNOUSERSITE=1` could not reproduce it. *Now:* every image check in `capture.sh` runs in the pinned, hashed `.tools/visual-venv` (`include-system-site-packages = false`). (2026-10-05)
- **Run CI locally before pushing.** `act` with the cached `catthehacker/ubuntu:act-latest` image caught that a clean Ubuntu runner lacks the X11 libraries Godot needs (`libXcursor`, …); my machine happened to have them. *Now:* the workflow installs them explicitly. (2026-10-05)
- **Local `act` predicted GitHub correctly:** the first real GitHub run (both jobs) passed in 41 s, as the local run did. (2026-10-05)
- **Run `act` jobs one at a time** (`-j three`, `-j godot`). Running both in parallel failed with `archive/tar: write too long` while copying the repo, a local `act` race rather than a workflow bug. (2026-10-05)
- **Installing Playwright's Chromium dominates the three.js CI time** (1 min 32 s of ~2 min). Cache it if CI time starts to matter. (2026-10-05)

## Environment (this development VM)

- **Shared machine:** 9.6 GB RAM, no GPU, no sound card, no display (Xvfb available), Docker available. Other projects' services run here too. The assistant is not allowed to stop other workloads; the owner does that. (2026-10-05)
- **Third-party plan scans are reference material, not repo content.** Plans and scans (Jensen, RCM, Outerzone) are copyrighted; keep them out of the public repo, e.g. in a gitignored folder. (2026-10-05)

## Aircraft modeling and reference inspection

- **EX-00, investigación ampliada:** la foto roja con estrellas apareció asociada a la variante .40, mientras la geometría elegida es .60. Una foto de la misma galería muestra el intradós de franjas azules/blancas, pero otras usan motores/hélices distintos: compartir ficha no acredita compartir SKU. Registrar acabado, dimensiones e instalación por separado. [Foto y procedencia](docs/research/extra-300-photo-investigation.md). (2026-10-05)
- **EX-00, contraste de construcción:** la reseña de primera mano del .60 aporta una masa lista para volar por encima del rango del cartucho y una cuerda media redondeada que no satisface el chequeo `span × chord = area` del loader. Mantener la construcción publicada como caso de sensibilidad, no sustituir silenciosamente nominales ni derivadas. [Segunda ronda](docs/research/extra-300-round2.md). (2026-10-05)

- **EX-00, segundo avión:** el manual del Extra 300S expresa los recorridos en pulgadas en la parte más ancha de cada mando; no se pueden cargar como grados. El ala trapezoidal también obliga a distinguir cuerda local, `S/b` y cuerda aerodinámica media antes de trasladar CG y coeficientes. [Recursos inspeccionados](docs/research/extra-300-resources.md). (2026-10-05; investigación, sin vuelo nuevo)
- **EX-00, integración:** aceptar otra ruta JSON en FlightSession no basta para tener dos aviones. El builder, los anclajes del CG, los ejes de bisagra, el tren, la máscara de sombra y los metadatos de traza conservan supuestos del Stik. La definición de avión debe resolver modelo y física juntos, preservando el caso actual. [Auditoría y plan](docs/research/extra-300-integration-audit.md). (2026-10-05; lectura de código)
- **EX-00, lectura de fuentes:** ampliar la anotación de incidencia del plano permitió leer −½°, evitando interpretarla como 1½°. Un PDF grande o un DXF disponible tampoco garantiza escala ni autoría original: el paquete Extra incluye extracciones del manual y costillas redibujadas, todavía sin calibrar. [Plan del segundo avión](docs/EXTRA-300-PLAN.md). (2026-10-05)

- **An orthographic side view caught a disconnected wing.** The first .61 mesh looked plausible in three quarters but its wing root floated above the fuselage. Lowering the seat and testing both mesh sections at the same x/z point caught the defect numerically. Static dihedral now lives in wing frames above the commanded hinges; the model passes 449 checks, and reversing a hinge sign in a scratch copy triggers 12 failures. [Evidence](docs/research/ugly-stik-model-v1-rig.md). (2026-10-05)
- **Each capture must reset its own pose.** Sending no hinge updates preserved the previous deflection while the next image was labeled neutral. The inspection harness now explicitly applies neutral commands before each neutral capture, including the distance series. [Final captures](docs/research/ugly-stik-model-v1-visual.md). (2026-10-05)
- **A traced shape can be useful without being a calibrated dimension.** The Jensen scan's wheel and PDF page scale disagree. The model records the conditional scale and length normalization, uses only identified fuselage widths, and excludes an ambiguous tail outline. [Calibration limits](docs/research/ugly-stik-model-v1-calibration.md). (2026-10-05)
- **A reference bundle can contain different configurations and printed conversion errors.** The new Ultra Stick RHB plan says 78 in / 61 in; its included Horizon manual says 76 in / 55 in and prints inconsistent metric conversions. The laser-cut README also distinguishes nominal contours from 0.004-inch compensated cuts. These sources are catalogued separately from each other and from Jensen .61. [Inspection](docs/research/ugly-stik-new-files.md). (2026-10-05)

- **A local dimensional check can improve the mesh before every scan is calibrated.** The Jensen chord reads 12.07 in against 12 in nominal, supporting the nearby F1-to-wing reading of 6.94 in. Correcting the nose from 325 to 176.276 mm also required translating its engine, propeller and nose gear. The new checks measure built mesh nodes; restoring the old firewall in a temporary copy triggers three failures. [v2 evidence](docs/research/ugly-stik-model-v2.md). (2026-10-05)
- **Organize references by aircraft identity and verify the move by hash.** All 31 owner-supplied files retained their bytes after relocation; Ultra Stick 120 and the unidentified MoJo drawing have separate folders and updated manifests, so their dimensions cannot silently replace Jensen .61 data. [Reference index](docs/research/aircraft-reference-index.md). (2026-10-05)

- **A model plan needs separate acceptance for playability and dimensional fidelity.** The v2 checks prove articulation and a few dimensions, while the tail and aft fuselage remain estimated. The revised plan keeps v2 available for M1, measures those pieces before detail work, and runs distance-readability trials in parallel. Combined control clearances and capture provenance are explicit next checks. [Review and revised plan](docs/research/ugly-stik-model-review-v2.md). (2026-10-05)

- **A reserved scan section catches errors hidden by fitting stations.** V3 uses x=2800 px outside its F4/F5/F6 fit; both a data calculation and actual mesh probes pass the declared roof/bottom/width allowances. A deterministic pixel-to-metre audit also caught a 1 mm transcription error. Keep source picks and computed values separate. [V3 evidence](docs/research/ugly-stik-model-v3.md). (2026-10-05, US-02/03)
- **Positive surface distance does not rule out containment.** A 1 mm cube entirely inside the fuselage has a 42.5 mm distance to its skin. V3 checks containment as well as triangle proximity; removing tail hinge relief in a scratch copy makes the integrated contract fail. [Clearance evidence](docs/research/ugly-stik-model-v3-installation.md). (2026-10-05, US-04/05)
- **Different views on one plan need separate scale evidence.** The Jensen rib detail reads 13.58 in while the assembled wing chord reads 12.07 in. Normalize the traced section to the shared nominal chord and keep its aerodynamic interpretation unknown. [Wing record](docs/research/ugly-stik-model-v3-wing.md). (2026-10-05, US-05)
- **Reproducible images are preparation for a pilot test, not pilot-test results.** V3 repeats 36 PNG hashes, checks all vertices stay in frame and presents an unfilled orientation form. Actual answers and hardware measurements remain separate acceptance evidence. Wheel spin/steering pivots similarly prepare ground integration without implementing contact forces. [Readability protocol](docs/research/ugly-stik-model-v3-readability.md). (2026-10-05, US-01/06/07/08)

- **A matching paint scheme does not identify the powerplant.** The official Durafly reference describes an electric EPO variant with a dummy nitro engine. Keep the owner's photo-based finish separate from the documented .61 glow anatomy; the photo watermark alone does not establish an exact SKU. [Visual research 01](docs/research/ugly-stik-visual-investigations/01-decoration-identity.md). (2026-10-05, visual planning)
- **The texture plan must account for the current renderer and material multiplication.** Godot 4.7 Compatibility does not provide Decal3D, and material albedo multiplies the atlas. The next visual step therefore starts with UVs and a neutral-tint atlas fixture, checking mipmaps and import from a clean clone before decorating the whole airplane. This is a researched implementation plan, not a completed rendering test. [Visual research 09](docs/research/ugly-stik-visual-investigations/09-materials-atlas.md). (2026-10-05)
- **Procedural mesh detail needs its own measured simplification path.** Godot documents that SurfaceTool.generate_lod() loses normals and UVs. Preserve the textured skin, measure actual draw calls and consider hiding grouped microdetail only if profiling justifies it. [Visual research 10](docs/research/ugly-stik-visual-investigations/10-readability-performance.md). (2026-10-05, research; no benchmark yet)

- **A working open notch does not establish support for closed holes.** The current elevator helper extrudes every contour returned by Geometry2D separately. A future enclosed cutout needs explicit handling of its inner boundary; otherwise it would be capped as another solid. This follows from code inspection and API research, with a small regression fixture still proposed. [Tooling research 01](docs/research/ugly-stik-tooling-investigations/01-polygons-and-meshes.md). (2026-10-05)
- **The first imported texture changes clean-clone validation.** Godot's `--import` waits for resource imports before exiting. Add that prerequisite when the atlas enters the model, keep source/import settings, and regenerate `.godot/`; parse checks alone do not establish visual correctness. This is a documented requirement, not an import experiment performed in this round. [Tooling research 09](docs/research/ugly-stik-tooling-investigations/09-import-ci-tests.md). (2026-10-05)
- **Tool selection should follow a failing case and a measurable benefit.** The new tooling review keeps native meshes, transforms and profiling first; SVG import and Pillow comparisons support the next visible delivery. Blender, mesh processing libraries and new test frameworks remain conditional, with compatibility checks before adoption. Existing local Pillow 11.3.0 is an environment observation, not a pinned project dependency. [Ten tooling investigations](docs/research/ugly-stik-tooling-investigations/README.md). (2026-10-05, research)


## 2026-10-05 · US-V01–08 / D1 — acabado Ugly Stik v4

- Un SVG generado desde apariencia JSON puede incrustarse como fuente GDScript y rasterizarse una vez en Godot; así el modelo funciona sin caché del editor. El fixture temporal comprobó igualdad byte a byte con la importación SVG, y una mutación detectó fuentes desactualizadas.
- El orden de vértices importa además de las normales: una inversión en el helper metálico produjo caras interiores. La comprobación de winding sobre las mallas construidas detecta ese defecto; una mutación lo confirmó. Las tapas de arandelas necesitan anillos, no divisores radiales.
- Medir solo el solver puede ocultar una varilla mal construida. El contrato recorre 71 poses con Commands y mide extremos/longitud de las mallas; estirar una CylinderMesh 10 % hace fallar la prueba. El barrido independiente también comprueba jerarquía transformada, rama continua y cero nodos nuevos.
- Ocultar `aileron_*` para mantenimiento también ocultaba sus servos. Se usan nombres exactos de piel y comodines explícitos; los componentes conservan posición y la visibilidad se restaura por captura.
- Las macros revelaron uniones de bancada cortas, collarín de morro separado y bandas que atravesaban el fuselaje. Se corrigieron apoyos y rutas antes de publicar 95 capturas. Las fotos nuevas permitieron reemplazar el escape ovoide por cuello ancho, cuerpo con nervaduras, cono y boquilla.
- Las 36 imágenes a distancia se repiten exactamente en este entorno, pero eso no prueba orientación humana ni rendimiento GPU. Los contadores incluyen el fotograma entero y llvmpipe no representa el hardware del piloto.
- Con desarrollo paralelo hay que distinguir un fallo del cambio y uno de la base: el `oracle` de aerodinámica falló también al extraer el commit confirmado sin el modelo v4. Los contratos visuales y dos capturas sí se reprodujeron en clon limpio. No se reparó física ajena para hacer pasar la entrega del modelo; la última suite integrada pasó tras los cambios del otro frente, con vuelo trimado y estado idéntico a 30/60/144 fps.

Prueba y archivos: [reporte v4](docs/research/ugly-stik-model-v4.md), [validación](research/ugly-stik/model-v4/validation.json), [galería](research/ugly-stik/model-v4/review.html).

- **US-V01–08, revalidación:** un plan con estado de entrega actualizado puede conservar instrucciones antiguas que declaran los mismos pasos pendientes. Antes de volver a implementar, contrastar el adaptador real, fuentes generadas, contratos y capturas: en esta pasada v4 ya estaba integrada, 807 + 289 comprobaciones pasaron y ambas vistas de presentación conservaron sus hashes. Se corrigieron los estados documentales; lectura humana y GPU objetivo siguen abiertas. [Evidencia](docs/research/ugly-stik-model-v4.md#revalidación-del-árbol-integrado). (2026-10-05)

- **US-V07, capturas automáticas HD:** duplicar resolución conserva el encuadre angular y no corrige una rueda cortada; se revisaron las miniaturas y se abrió la cámara del tren principal. Una suite separada permite añadir macros, relleno y 2560 × 1440 sin cambiar las comparaciones históricas. El wrapper recreó carpeta y galería desde clon limpio, con 28/28 PNG idénticos. En GDScript, una expresión condicional con arrays literales puede perder el tipo `Array[String]` en ejecución aunque pase el parseo; inicializar el array tipado y añadir sus elementos evitó ese fallo. [Prueba](docs/research/ugly-stik-showcase-validation.json). (2026-10-05)

- **US-V03/V06/V07, motor v5:** un disco oscuro no garantiza una admisión hueca; hay que terminar la carcasa antes de la boca y construir labio, pared interior y fondo. Los perfiles de revolución suavizan piezas circulares conservando cabezas hexagonales. Unir conos de ejes distintos por su centro deja huecos: sus anillos extremos deben coincidir en plano y radio. Once macros con la misma cámara y luz permiten descubrir esas uniones; las once imágenes finales se reprodujeron por hash desde un clon limpio. [Análisis y pruebas](docs/research/ugly-stik-engine-v5.md). (2026-10-05)


## 2026-10-05 · SM-PLAN — investigación de humo RC y bomba auxiliar

- El pin real es Godot 4.7.2 con Compatibility. Las partículas GPU están disponibles, pero las capacidades deben comprobarse en ese backend: su código implementa solicitudes explícitas de avance y no admite particle trails. La elección propuesta son dos emisores de sprites independientes. Evidencia: lectura del pin, documentación y fuente GLES3; no se ha medido todavía el efecto.
- La captura actual avanza física sin presentar las poses intermedias. Una nube con historial necesita reproducir esa trayectoria; precalentar partículas en la posición final produciría una referencia visual incorrecta. La pausa de vuelo también es propia de la simulación, por lo que hay que conectar explícitamente el reloj del efecto.
- Un canal AUX puede llegar por USB como eje o botón; el lector actual solo procesa eventos de ejes. La bomba requiere asignación opcional por dispositivo y conservar los cuatro canales AETR. La documentación de bombas reales respalda ese tipo de control, pero no valida cuánto humo produciría nuestro silenciador .61 concreto.

Fuentes, alcance y pruebas pendientes: [plan de humo y bomba](docs/SMOKE-PLAN.md) · [investigación](docs/research/rc-exhaust-smoke.md).

## 2026-10-05 · M5-W00 — investigación y plan de viento

- AirData ya resta viento mundial en ejes de cuerpo, pero la sesión y el HUD le pasan cero. Conectar fuerzas solamente dejaría mal el arranque trimado y la velocidad mostrada: el estado es velocidad respecto al suelo, mientras trim y aerodinámica requieren velocidad relativa al aire. La prueba existente `test_air_data.gd` pasó 11/11 con Godot 4.7.2; todavía no prueba clima integrado.
- Una llamada a `Simulation.step()` consulta cargas cinco veces, cuatro dentro de RK4, y mantiene el mismo tiempo en todas. El generador no puede consumir azar al consultar; las ráfagas temporales requieren tiempos de etapa explícitos. Es un hallazgo de código, con cambio y pruebas pendientes.
- Las seis estaciones del ala corrigen déficit de pérdida, no son un solver distribuido completo. Viento distinto en cada ala exige comprobar cargas locales y evitar duplicar el amortiguamiento global. Dryden describe un modelo estadístico; su nombre no demuestra realismo de un campo RC.
- `Area3D.wind_*` afecta SoftBody3D y no integra nuestra física propia. La deriva de nubes actual está en celdas/s; con viento variable hay que integrar desplazamiento, no multiplicar la velocidad actual por el tiempo. El reloj visual envuelto a 1024 s tampoco sirve como tiempo físico del viento.

Fuentes primarias, configuraciones propuestas y pruebas de implementación: [plan M5 de viento](docs/WIND-PLAN.md), [auditoría Godot](docs/research/wind-godot-integration.md), [investigación física](docs/research/wind-physics-primary-sources.md). Entrega documental; sin viento implementado ni rendimiento nuevo medido.

## 2026-10-05 · M5-W00 — doce investigaciones de herramientas y Godot

- El ensayo aislado con Godot 4.7.2 pasó diez comprobaciones: JSON necesita `full_precision` para conservar el float del fixture y cadenas para semillas grandes; ConfigFile conserva el int64 probado. El parser JSON admite comas finales, por lo que parsear no equivale a validar el formato del clima.
- `SpinBox.set_value_no_signal()` también cuantiza según `step`; silenciar señales no protege la precisión del modelo. El texto pendiente todavía puede diferir de `value` hasta `apply()`. Conservar un borrador preciso y confirmar los editores al aplicar evita cambiar el clima solo por abrir un panel.
- El análisis SciPy de una misma serie OU mostró RMS temporal 0.502766 m/s frente a 0.426056 m/s espectral con segmentos cortos y detrend local. La resolución y el detrend son parte del protocolo de validación. La discretización ZOH de una entrada determinista tampoco entrega por sí sola la covarianza del ruido estocástico.
- La fuente GLES3 integra la velocidad de partículas antes de `process()`: un shader que además mueva `TRANSFORM` debe decidir quién integra para evitar doble transporte. Es evidencia de código; la prueba visual integrada queda pendiente.
- Los monitores custom de Godot recortan negativos y no sirven directamente para componentes N/E/D firmadas. JSBSim y TurbSim son candidatos de comparación offline, con ejes/unidades/hipótesis explícitos; no calibran condiciones RC por sí mismos.

Fuentes, ensayos reproducibles, límites y correspondencia con entregas: [doce investigaciones de viento](docs/research/wind-investigations/README.md). Se afinó el plan; no se implementó meteorología ni se añadieron dependencias al juego.


## 2026-10-05 · EX-00 — doce investigaciones de herramientas

- La lectura de `shadow.gd` mostró que medir la extensión desde las mallas no actualiza la máscara rectangular ni su referencia longitudinal. El Extra necesita contorno y datum propios; esta separación también evita duplicar proporciones del Stik.
- Cargar el script del avión en segundo plano no ejecuta su construcción procedural ni precalienta automáticamente el atlas SVG. Medir lectura, construcción y primer frame por separado antes de introducir hilos.
- La geometría decorativa no identifica coeficientes de vuelo. XFOIL y AVL son candidatos offline con hipótesis limitadas; cualquier contraste exige ejes, unidades, CG y cuerda de normalización coherentes, especialmente MAC frente a `S/b`.
- Las decisiones de herramientas quedan ligadas a pasos EX y ensayos pendientes. Esta ronda revisó código y fuentes; no instaló bibliotecas ni produjo medidas nuevas de vuelo o rendimiento.

Fuentes, doce preguntas y mejoras compartidas con el Stik: [investigaciones de herramientas](docs/research/extra-aircraft-tooling/README.md).

## 2026-10-05 · SM-PLAN revisión 2 — doce investigaciones y ensayo de emisión

- En un proyecto sintético con Godot 4.7.2 Compatibility, un emisor a 40 m/s y límite de 30 fps dejó grupos separados de quads incluso con interpolación y paso de partículas de 60 Hz. Suavizar estados de partículas no equivale a distribuir nacimientos entre poses. El proyecto, PNG y resultado se conservan; no prueban todavía el humo integrado ni rendimiento de GPU real.
- La lectura de GLES3 distingue solicitar tiempo de encolar el procesamiento. La propuesta de reloj manual necesita probar `RenderingServer.particles_request_process(emitter.get_base())` fuera de cámara; `get_instance()` representa otro RID. Las solicitudes temporales se reemplazan y sus dos duraciones no codifican una lista arbitraria de transiciones AUX.
- Una máscara de avión obtenida ocultando también su humo incluiría ambos efectos en la diferencia de imágenes. Capturar la silueta sin humo y usar otra región para la estela evita contaminar la medida de legibilidad.
- Las demos Forward+ y los plugins de editor son referencias, no prueba de compatibilidad. Se mantiene material nativo, máscara pequeña y proximity fade condicionado; se registraron licencias/revisiones de candidatos y herramientas offline sin añadir dependencias.
- El bloque AUX debe validarse aparte de AETR, revalidarse al cambiar calibración y borrar su historial de eventos vistos al cambiar perfil. OFF corta nuevos nacimientos; la nube residual procede de partículas que ya existían.

Evidencia: [doce investigaciones y catálogo](docs/research/smoke-investigations/README.md), [ensayo reproducible](docs/research/smoke-investigations/godot-evidence/README.md), [plan revisado](docs/SMOKE-PLAN.md). La entrega modifica documentación y un experimento aislado; no implementa el efecto en `app/`.


## 2026-10-05 · AV-00 — referencia Avanti S de turbina

- El manual A200 coincide con su ficha histórica en 200 cm de ala y 222 cm de largo; el catálogo reciente usa “2.3m”. Fijar la revisión evita convertir una etiqueta comercial en una nueva medida. No se encontraron ventas comparables que permitan afirmar cuál turbina Avanti es la más popular.
- La fotoinstrucción descargada tiene 91 páginas y muestra el datum del CG en la página 91. Se inspeccionaron fotos y una muestra del montaje; no se encontró un plano completo calibrado del avión. Los planos acotados recuperados son del P100-RX y su soporte.
- Las fuentes oficiales P100-RX discrepan entre revisiones en ralentí y longitud. Se eligió tabla de catálogo 2017 sin BL; la ficha RX-BL y manual 2011 se conservan como comparación. RPM máximas y dos puntos de empuje no identifican el retardo ni la curva de throttle.
- La auditoría de código encontró dependencias de hélice en loader, trim, sesión, render y sonido. Una turbina necesita cargas y estados propios, preservando el caso glow; un nodo propeller vacío solo sirve como adaptación visual temporal. El inicio trimado necesita spool estacionario correspondiente al throttle resuelto, no ralentí fijo.
- La masa A200 de manual es RTF seca: inventario, combustible y CG de vuelo siguen pendientes. La primera vista previa puede avanzar con forma aproximada, mientras esos datos condicionan la aceptación física.

Prueba de esta entrega: archivos abiertos/inspeccionados, hashes y exclusión Git en [validación local](docs/research/avanti-s-validation.json); código y fuentes revisados en el [plan Avanti S](docs/AVANTI-S-PLAN.md). Sin cambios de app ni ensayos de vuelo nuevos.

## 2026-10-05 · UI-PLAN revisión 3 — análisis del menú y doce investigaciones

- Medir la app real encontró un defecto que la inspección solo sospechaba: durante cualquier pausa (failsafe, accidente, calibración) `main.gd._process()` sigue girando la hélice y alimentando el motor a las rpm de vuelo; con el tick congelado en 144, el bus Master siguió a −34 dB. `stream_paused` lo silencia en un bloque de mezcla; `clear_buffer()` falla mientras suena. El driver de audio Dummy mezcla en tiempo real, así que el medidor de pico permite probar volumen y pausa sin tarjeta de sonido.
- La GUID de SDL3 incluye `bcdDevice`, donde EdgeTX escribe su versión de firmware: una clave de calibración con GUID se rompería al actualizar la radio. Todas las radios EdgeTX comparten `1209:4F54` y su cadena USB dice «OpenTX». Deducido del código de SDL y EdgeTX; falta confirmarlo con la radio del propietario.
- Un eje de radio AETR mueve el foco de un menú Godot en headless, y deja de hacerlo al retirar los eventos joypad de `ui_*`, sin perder `get_joy_axis`. Una sonda **sin** `project.godot` o sin `InputMap.load_from_project_settings()` no ve esos eventos y pasaría en falso.
- Tras `Input.parse_input_event` hay que esperar al menos un `process_frame`; `action_press` no mueve el foco. gdUnit4 entrega cada evento dos veces al nodo raíz y GUT crea teclas sin `physical_keycode`: el arnés propio sigue siendo más fiable para este proyecto.
- Godot 4.6+ no dibuja el foco ganado con ratón, `ScrollContainer.follow_focus` es falso por defecto, un `.tres` guardado dos veces cambia 16 líneas por ids aleatorios y `Window.theme` no atraviesa un `CanvasLayer`. Las plantillas de menús revisadas escribieron preferencias (ventana 64 × 64) al ejecutarse headless.

Fuentes, sondas y límites: [doce investigaciones de la ronda 3](docs/research/menu-investigations/README.md#ronda-3-doce-preguntas-más-motor-herramientas-librerías-ejemplos), [plan revisado](docs/MENU-PLAN.md). Documentación y sondas fuera de `app/`; no se implementó ninguna pantalla ni se corrigió el defecto de audio.

## 2026-10-05 · AV-01 parcial — archivo y cotas Avanti

- Extraer imágenes incrustadas del PDF pierde las cotas y flechas vectoriales superpuestas. Se extrajeron regiones de página a 144 dpi, conservando anotaciones y número de paso, y se mantuvieron las 91 páginas completas como contexto.
- Las cotas 60/52/34/39 mm de varillaje tienen extremos distintos: no equivalen todas a distancia entre centros de rótulas. El archivo conserva los recortes para revisar el tramo medido antes de construir articulaciones.
- La secuencia p.69–72 identifica los dos cilindros blancos como depósitos neumáticos por continuidad visual y conexiones rotuladas del tren/freno. El tanque de queroseno/humo de p.73 es distinto; ninguna de esas fotos acredita capacidad en litros.
- La envergadura de 2000 mm, longitud de 2220 mm y motor de 241 × 97 mm permiten controles de escala; no identifican área alar, posición de bancada ni ejes de bisagra. AV-01 sigue parcial, con 30 datos trazables y cuatro cocientes separados de la futura física.
- La mesa local organiza 67 originales acumulados y 209 entradas derivadas/copiadas; ninguna referencia se incorpora al runtime. El panel permite comprobar recorridos geométricos de flap y diferencial de alerones, sin presentarlos como respuesta aerodinámica.

Evidencia y límites: [ficha AV-01](docs/research/avanti-s-av01-metrology.md), [catálogo](docs/research/avanti-s-organized-catalog.json) y [validación](docs/research/avanti-s-av01-validation.json). No se modificó la app ni se hicieron pruebas nuevas de vuelo.

## 2026-10-05 · UI-00/01a/01b — Inicio y radio aislada de los menús

- Una nueva escena de entrada puede convivir con toda la automatización si decide la ruta antes de crear nada e instancia la escena de vuelo **en el mismo frame**: la traza de 3 s y la captura de vuelo salieron idénticas byte a byte. La regla «cualquier argumento tras `--` = vuelo directo» evitó tocar `capture.sh`, `export.sh` y las pruebas que cargan `main.tscn`.
- Una prueba que pasa a la primera no prueba nada hasta mutarla. La del doble Enter siguió en verde al quitar la protección de Inicio, porque `disabled = true` y la de `app_root` protegían por su cuenta; solo sin las tres salieron 2 sesiones. Se mantienen las tres, como defensa en profundidad.
- La precondición de la prueba de radio (sin aislar, el eje 1 mueve el foco) es lo que la hace significativa: si un cambio futuro del motor quitara esos eventos, la prueba lo diría en lugar de pasar en falso. Hay que cargar el InputMap del proyecto (`InputMap.load_from_project_settings()`).
- Los colores de hover del botón rojo deben oscurecerse: aclararlo bajó el contraste del texto a 4,66:1 y oscurecerlo lo subió a 6,06:1. Open Sans a 16 px mide 23 px de ascendente a descendente, por encima del objetivo de 17 px a 720p.
- `test.sh` se detiene en el primer fallo, así que un test en curso de otro agente oculta todos los posteriores. Verificar en un `git clone` local con solo los cambios propios mostró además que el HEAD `59cca56` no parsea (`aircraft/extra_300s_model.gd`, corregido sin commit por su dueño).

Prueba: [registro de ejecución del plan](docs/MENU-PLAN.md#registro-de-ejecución), `tests/test_ui_home.gd`, `tests/test_ui_input.gd`, `ui-home.png` de `capture.sh`.

## 2026-10-05 · VQ-00 — auditoría y plan de calidad visual

- Tres capturas nuevas de la app (piloto, inspección y horizonte, trayectoria scripted) confirman que cielo/bruma/nubes ya están integrados, pero el escenario construido sigue siendo suelo y pista planos sin arbolado. Priorizar L5–L11 aporta contexto y escala antes de más detalle del avión. Son observaciones de imagen, no un playtest ni un benchmark de GPU.
- `msaa_3d=2` significa MSAA 4×, no 2×. La documentación Godot 4.7 también confirma SSAO simplificado y glow en Compatibility; recomendar esos efectos requiere revisar el backend y la versión, no repetir limitaciones antiguas.
- Los contadores visibles del manifiesto y los totales de consola tienen distinto alcance: la vista piloto registró 101 draw calls visibles y 46.842 primitivas visibles. Los logs, PNG y hashes se conservaron juntos. llvmpipe sirve para comprobar render y errores, no para estimar FPS en la RTX 3090 del propietario.
- El propietario quiere una mezcla de realismo y presentación limpia, con ajustes desde equipos modestos hasta potentes; dispone de Ryzen 5900X, RTX 3090 y 64 GB para probar. Ese equipo permite comparar Alto/Forward+, pero no valida el perfil modesto; faltan mediciones de ambos y resolución objetivo.

Entrega documental: [plan visual](docs/VISUAL-QUALITY-PLAN.md), [herramientas](docs/research/visual-quality-tools-2026-10-05.md), [evidencia nueva](docs/research/visual-quality-baseline-2026-10-05/README.md). Tres capturas completadas sin errores de motor/script/shader y SHA-256 comprobados; sin cambios a `app/`, instalación de addons ni mediciones nuevas de vuelo físico.

## 2026-10-06 · EX-01/EX-02 — metrología del Extra 300S .60 y vista previa en Godot

- Las dos hojas del mismo plano no tienen la misma escala: la hoja de ala está a tamaño real (la regla impresa da 399,88 px/in), pero la de fuselaje está reducida (300,56 px/in). Calibrar cada vista con algo que ya esté medido en otra (la cuerda de raíz dibujada en la lateral) y reservar la longitud total como control. Ese control también decidió qué costilla está dibujada: la de ℄ habría dado +5,6 % de longitud.
- Un dibujo vectorial limpio no es un dibujo a escala. Las dos vistas de la p.47 del manual (para planificar la decoración) desplazan la rueda de cola 1,2 in respecto al plano. Medir sus residuos frente a puntos no usados antes de tomarle una cota.
- El área publicada del ala (744 in²) es la del trapecio prolongado hasta ℄, no la expuesta: coincidió al 0,10 %. Con el área expuesta habría parecido un error de escala.
- «CG en la costilla 2D» se resolvió localizando 2D (lateral del fuselaje, 3,39 in de ℄) y comprobando el símbolo del plano (4,116 in frente a 4⅛). El CG nominal queda al 30,0 % de una CMA de 12,03 in. `S/b` (11,65 in) sigue siendo la cuerda de referencia del cargador v1.
- Un alerón con bisagra en flecha no necesita cambiar `apply_surfaces()`: basta un marco fijo orientado sobre la bisagra y un hijo `*_hinge` que solo recibe la deflexión, el mismo patrón que el diedro del Stik. La prueba compara el sentido del movimiento del borde de salida con el del Stik para el mismo mando, y una mutación que voltea el marco la detecta.
- Un `assert()` o un error de ejecución en un script `SceneTree` deja Godot headless parado en el depurador (exit 124 por timeout). En constructores y verificaciones: `push_error` y seguir, para que la prueba falle rápido y con causa.
- **Error propio:** escribí el constructor directamente en `app/` y el propietario hizo commit (`59cca56`) en los segundos en que no parseaba. Con commits `git add -A` en paralelo, los borradores van fuera de `app/` y se copian solo tras `--check-only`, como ya dice AGENTS.md.
- `app/test.sh` se para en el primer fallo: un test sin seguimiento de otro agente (`test_physical_envelope.gd`) ocultaba el resto. Hubo que correr por separado los pasos siguientes para demostrar que este cambio no rompe nada.

Prueba: [informe](docs/research/extra-300-model-v1.md), `research/extra-300/ex01/measure.py --check`, `compile_geometry.py --check` (116 valores frente a la metrología), `aircraft/verify_extra.gd` (84 comprobaciones, seis mutaciones), capturas repetibles en `research/extra-300/ex02/captures/`.

## 2026-10-06 · UI-01d — inglés por defecto y multiidioma

- Godot arranca en el idioma del sistema operativo (`es_ES` con `LANG=es_ES.UTF-8`), así que «inglés por defecto» exige fijarlo en el código; si no, un catálogo español cargado se aplica solo en un equipo en español. La ruta directa también lo fija: la traza siguió idéntica con el sistema en español.
- Un `.po` listado en `internationalization/locale/translations` carga desde un clon sin importar y entra en `--export-pack` con `all_resources`, sin `include_filter` (sonda 23). Es la razón práctica para preferirlo a CSV, además de ser el formato de las herramientas de traducción.
- Labels y Buttons se traducen solos al dibujarse, pero su propiedad `text` conserva el texto fuente: las pruebas deben leer `atr(text)`. Las frases construidas en ejecución desactivan la traducción automática (para no traducir dos veces) y se rehacen en `NOTIFICATION_TRANSLATION_CHANGED`; la mutación que quita ese manejador dejó el botón de idioma en inglés.
- `ConfigFile.get_value()` sin valor por defecto imprime `ERROR` cuando falta la clave, y `test.sh` lo cuenta como fallo: siempre pasar un centinela.
- Las pruebas que crean `app_root` deben inyectar una ruta de preferencias propia: `user://` es la misma carpeta que usa la app al ejecutarse desde el código, y una prueba escribiría los ajustes reales del desarrollador.

Prueba: `tests/test_ui_language.gd` (22 comprobaciones, mutadas), suite completa en un clon limpio, capturas `ui-home-en.png`/`ui-home-es.png`.


### 2026-10-06 — Reparación del rudder y robustez transversal

- **D9-R1/R2:** continuidad de coeficientes estáticos no garantiza continuidad de cargas con rates. El probe original detectaba 46/925 estados con potencia positiva y un salto de ~1.842 N; elementos locales con el mismo flujo/fuerza/brazo eliminan esos casos. V_COM=0 no significa aire inmóvil en un ala que rota.
- **D10-R:** bajar solo `Cndr` mejoraba un pulso y rompía recuperación. Enlazar fuerza y brazo, modelar la pérdida local de las colas y conservar el recorrido permite reparar ambas maniobras. Al derivar `Cldr`, la altura es respecto al ARP antes de la transferencia al CG; usar altura respecto al CG cuenta esa palanca dos veces.
- **D1-R1:** un tensor calculado alrededor del centro de un inventario no corresponde a un avión cuyo CG se declara en otro punto. La masa virtual de balance explicita una configuración consistente y cambia trim/modos; sigue siendo estimación, no medición del hardware.
- **D4-R1:** no basta validar el JSON ni el primer cálculo de cargas. El trim debe formar parte de la aceptación y las etapas intermedias de RK también pueden fallar. En GDScript, cambiar un String capturado por una lambda no comunica el fallo al caller; una caja Dictionary compartida sí. Tres pruebas específicas detectaron k2/k3/k4. Cambiar una inercia válida exige actualizar su inversa cacheada.
- **D4-R1 / datos:** JSON sintácticamente válido con una sección Array donde se esperaba Dictionary provocaba errores de script y podía terminar con `ok=true`. Comprobar formas antes de acceder y tipos numéricos antes de convertir evita ese falso éxito; NaN en hull necesita `is_finite`, no solo comparar límites.
- **D8a-R1:** un Jacobiano por ejes puede esconder acoplamientos del rotor/inercia. Conservar la matriz completa y etiquetar proyecciones evita presentar sus autovalores como los del vuelo completo. A 25 m/s la raíz espiral proyectada y la completa tienen distinto signo.
- Los goldens y bandas calculados por el propio simulador sirven como regresión. Actualizarlos exige explicar el cambio físico; no se mantienen expectativas de barrena provenientes del modelo que creaba energía como si fueran datos externos.

Pruebas y procedencia: [implementación](docs/research/flight-repair-implementation.md), `test_physical_envelope`, `test_rudder_authority`, `test_session_guards`, `test_dynamics` y comprobaciones de masa/datos, trim, manejo y recuperación. Gate 2 sigue esperando vuelo comparativo real.

## 2026-10-06 · AV-02 aislado — geometría y mandos Avanti

- Un inspector fuera de `app/` permite avanzar una forma aproximada y probar bisagras sin interferir con menú, Extra o física en edición. Funciona con Godot 4.7.2 Compatibility y no necesita los PDF/fotos locales.
- Las siete superficies se verifican por el desplazamiento de puntos del borde de salida. La inversión deliberada del flap derecho en un clon temporal falla; así se comprueba que la prueba detecta un mando invertido y no solo valores finitos.
- Mantener la envergadura y longitud nominales no valida secciones, perfiles ni área. La maqueta declara espesores constantes de panel, ejes y posiciones de equipo como estimaciones; no genera datos de vuelo.
- La primera captura en planta dejó la nariz bajo los controles del inspector. Se amplió la escala de encuadre ortográfico y se repitieron las nueve capturas; el manifiesto registra las cámaras finales.
- Las cinco nuevas fotos oficiales de 4320 × 3240 aclaran cabina, tomas y placas de ala, pero mantienen perspectiva. A200-13 se identifica como tubo original P100 de doble pared; no aparecieron dimensiones que permitan calibrar su instalación.

Prueba: [maqueta y resultados](docs/research/avanti-s-av02-preview.md), [clon sin referencias y defecto detectado](docs/research/avanti-s-av02-clone-check.json). No es validación aerodinámica, rendimiento de GPU real ni integración del Avanti en la app.


## 2026-10-05 · VQ-00 ronda 2 — técnicas de render e importación

- En Godot 4.7.2 Compatibility, dos MeshInstance3D con un ShaderMaterial compartido conservaron colores independientes mediante `instance uniform`; cambiar el uniform común afectó a ambos. No se debe heredar la limitación de tutoriales antiguos ni generalizar este ensayo de vec4 a texturas por instancia.
- Una malla fuera de cámara desplazada por vertex shader al centro fue descartada con bounds automáticos; ajustar solo `custom_aabb` recuperó su imagen. Bounds de vegetación deben incluir deformación, no solamente la geometría en reposo.
- La guía oficial distingue preparación visible de materiales en Compatibility y precompilación de pipelines de Forward+/Mobile. Cargar un recurso y medir FPS una vez calentado no prueba ausencia de tirones al mostrar un efecto por primera vez. Es hallazgo documental; no se midió stutter en este ensayo.
- El fixture pasó cinco estados y ocho verificaciones de píxel por ejecución; cinco PNG se repitieron byte a byte en dos procesos llvmpipe. Esto comprueba comportamiento local, no velocidad de una RTX 3090 ni integración de materiales con los aviones.

Evidencia, fuentes y ensayos pendientes: [segunda ronda visual](docs/research/visual-quality-round2/README.md), [código y capturas](docs/research/visual-quality-round2/godot-probe/README.md). Sin cambios de aplicación ni instalación de herramientas externas.

## 2026-10-06 · Avanti — comparar antes de refinar

- Ajustar una cámara por foto y superponer un render transparente revela diferencias que quedan ocultas al ver las imágenes por separado. Se conservaron geometría y fotografías; ninguna deformación 2D se usó para mejorar artificialmente la coincidencia.
- Un residuo pequeño en los puntos de ajuste no garantiza ajuste global: la oblicua posterior tiene RMS de 7,7 px en sus cuatro anclas y 26,1 px en los tres puntos reservados. Modelo aproximado, FOV supuesto y selección manual contribuyen al error; no es una medida física del avión.
- La conversión de ejes de cámara se verificó entre el cálculo numérico y la proyección real de Godot antes de interpretar los contornos. Los PNG conservan transparencia real y la página SVG permite opacidad, contorno, alternancia y corrección uniforme reversible.
- Las superposiciones priorizan fuselaje/tomas, contornos alares y transición de deriva para la siguiente edición. El modelo permanece igual en esta ronda para conservar una referencia de partida.

Evidencia: [comparación y límites](docs/research/avanti-s-transparency-comparison.md), [validación](docs/research/avanti-s-alignment-validation.json). Las composiciones que contienen fotografías permanecen locales y excluidas de Git.

## 2026-10-06 · UI-01c — revisión visual de Inicio

- Mirar la captura encontró lo que las pruebas no podían: la pantalla pasaba contraste, foco y tamaño de texto y, aun así, no mostraba el avión que da identidad al proyecto, y la ficha quedaba a 800 px del botón que describe. Una revisión visual crítica es un paso propio, no un adorno.
- Como la app construye todo su mundo en código, un render fijo con los mismos constructores es más barato y más fiel que una captura PNG: no hay paso de importación y la imagen mejora sola con el modelo y el paisaje. El encuadre fotográfico (teleobjetivo de 12°, avión en el tercio derecho con el morro hacia el menú, horizonte en el tercio inferior) necesitó cuatro iteraciones; mirar una dirección fija a mano dejó el avión detrás del menú, y calcularla desde la posición del avión lo resolvió.
- La fuente predeterminada de Godot no tiene flechas (U+2190–2193) ni «●»; con un respaldo del sistema la imagen cambiaría entre máquinas. Las teclas de flecha se dibujan como triángulos.
- Un panel translúcido al 94 % deja ver el horizonte y se parte en dos tonos; al 97 % ya no. El contraste de superficies translúcidas se comprueba sobre blanco y sobre negro: con el panel al 55 %, el contorno de foco bajaba a 2,28:1.
- Medir antes de asumir: el desglose atribuyó el coste a la textura de césped (≈ 220 ms) y a la construcción del avión (≈ 240 ms). En GDScript una lambda captura las variables locales por valor: un cronómetro que actualiza `t` dentro de la lambda mide tiempos acumulados.

Prueba: capturas `ui-home-en.png`/`ui-home-es.png`, `tests/test_ui_home.gd` (contraste de cada etiqueta, fondo liberado al volar), mutaciones y suite completa en un clon limpio.

## 2026-10-06 · VQ — revisión senior antes de implementar

- El campo actual se construye tanto en `main.gd` como en `ui/home_scene.gd`: compartir materiales no comparte el montaje. L5 debe dar a ambos un constructor de campo común, manteniendo separados cámara, avión, entorno y sesión.
- Las pruebas de atmósfera usan filas y franjas de cielo/suelo vacíos; añadir árboles exige mantener ese fixture y crear casos del campo completo, no aflojar los umbrales. Además, `capture.sh` puede encontrar un PNG anterior tras un proceso fallido: VQ-01a debe exigir salida nueva y estado correcto antes de usar capturas como evidencia.
- `preferences.gd` ya tiene esquema y `app_root.gd` separa la ruta técnica de las preferencias. Calidad se integra ahí; las texturas generadas por código no ganan variantes 1K/2K/4K por añadir un selector. Los primeros presets comparten recursos.
- El plan de paisaje hace depender las colinas L7 del generador L13a, y los assets fuente de la raíz no son recursos exportables de `app/`. La primera entrega se acota a L5/L6, con derivados runtime y prueba de los tres exports.

Prueba: lectura de esos flujos y contratos, y revisión de enlaces/consistencia del [plan ejecutable](docs/VISUAL-QUALITY-PLAN.md). Son hallazgos de revisión; no se implementaron las correcciones ni se ejecutó la suite del juego en esta entrega.

## 2026-10-06 · EX-02 — revisión visual automática del Extra

- Superponer el plano escaneado a la escala exacta de una vista ortográfica comprueba de una vez datos, constructor y cámara. Ala, cola, carenado y rueda de cola caen sobre las líneas; el tren no (carena simétrica frente a una gota, pata cilíndrica frente a una pletina). Esas superposiciones son material derivado del plano: se generan en local y no se versionan.
- Medir bordes de silueta en un render a 1137 px/m frente a `geometry.json` aisló un defecto de 2–3 mm (margen añadido a la cabina) que no se veía en ninguna imagen. A 1280×720 (2,6 mm/px) quedaba dentro del ruido. La primera versión de la comprobación daba 190 mm de error porque la deriva forma parte de la silueta lateral: revisar qué pieza define cada borde antes de culpar al modelo.
- El hallazgo más importante no era de forma sino de lectura: con alabeo de ±60° visto desde tierra, extradós e intradós blancos dan luminancias de 127 y 139. Medir la orientación por tono da una línea base objetiva para EX-10, antes de pintar nada.
- Los recorridos de la vista previa venían del archivo de datos del Stik. Calcularlos del manual del Extra (`asin(d/r)` en la cuerda más ancha: 17,6° / 23,9° / 30,0°) cambió las imágenes deflectadas. Mirar de dónde sale cada número, incluso en código solo visual.
- Con commits en paralelo, el inspector se preparó y verificó en una copia de `app/` y se copió después. Ningún estado intermedio roto llegó al árbol.

Prueba: [informe](docs/research/extra-300-visual-review-v1.md), `research/extra-300/ex02/capture.sh` (82 renders idénticos en dos ejecuciones), `review.json` en `research/extra-300/ex02/review-2026-10-06/`.

## 2026-10-06 · Avanti — afinar con cámaras congeladas

- Mantener las tres cámaras distingue cambios de forma de cambios de encuadre. Reducir la cuerda estimada y segmentar las puntas mejoró las muestras del ala en las tres fotos; el fuselaje siguió discrepando. No basta con mejorar una sola perspectiva.
- Un contorno curvo no debe producir una bisagra curva: el borde de salida sigue las estaciones, mientras el eje y borde delantero del mando se interpolan sobre una recta común.
- La transición cóncava de deriva requiere triangulación de polígonos; un abanico desde un centro puede cubrir huecos. Dos extrusiones de una C, cuyo centro cae fuera del polígono, verifican volumen orientado y detectan inversión de caras en una copia temporal.
- La distancia al borde más cercano es exploratoria y depende de oclusiones: puede cambiar una métrica del fuselaje aunque sus secciones no cambien. Guardar muestras, hashes y resultados desfavorables evita presentarla como metrología.

Prueba: [afinamiento y comparación](docs/research/avanti-s-contour-refinement.md), clon sin referencias, siete bisagras, tres overlays, nueve capturas y visor comprobado en escritorio/móvil. Recursos gráficos locales excluidos de Git.

## 2026-10-06 · VQ — integrar bibliotecas y assets aportados por el propietario

- La licencia general Quaternius QAL (2026-08-28) restringe redistribución independiente, mientras algunas fichas antiguas aún indican CC0. Los planes dejan de tratar al proveedor como CC0 por defecto: conservar evidencia del archivo/paquete o elegir alternativa. No se presume revocación de una licencia anterior demostrada.
- El soporte de Compatibility de Sky3D está declarado por su autor; su coste de integración aquí viene de `TIME`, el control del entorno y la coherencia del reloj. El código MIT tampoco cubre sus mapas estelares CC BY 4.0. ProtonScatter también separa licencia del addon y texturas demo.
- Reutilizar materiales/props reduce autoría, pero generadores con colisión o flotación no sustituyen la física float64. El aporte amplía L6/L9/L10/L11/L18/L19 con candidatos y pruebas sin convertir agua, carreteras o una migración de cielo/terreno en requisitos del primer campo.

Prueba: [contraste con fuentes primarias y decisiones](docs/research/visual-quality-supplement-2026-10-06.md), con el texto original conservado. Integración documental; no se instalaron addons ni se ejecutaron nuevos benchmarks.

## 2026-10-06 · UI-02/03 — pausa, foco y vuelta a Inicio

- Investigar antes de escribir evitó dos errores de diseño: un botón enfocado **no** consume Enter ni Espacio (el evento sigue hasta `_unhandled_input` del vuelo, que tiene Enter para la calibración), y en X11 la notificación de foco de aplicación llega unos 250 ms después de la de ventana, con la tecla aún pulsada. El menú se traga todas las teclas que la GUI deja pasar.
- La prueba con eventos reales encontró dos defectos que la lectura del código no veía: el menú se liberaba dentro de su propio `_unhandled_input` (después `get_viewport()` era nulo), y abrirlo desde `NOTIFICATION_APPLICATION_FOCUS_OUT` fallaba porque el árbol bloquea `add_child()` mientras propaga la notificación; en la app real habría fallado igual. Abrir el menú en diferido lo resuelve.
- Simular la pérdida de foco con `SceneTree.notification()` sigue el camino real (libera teclas y propaga); `root.propagate_notification()` no libera las teclas.
- El defecto de sonido de la investigación 19 se corrige en el mismo sitio que lo causaba: con `stream_paused` asignado en cada frame (una sola asignación tras `play()` no sobrevive hasta que el reproductor registra su playback) y la hélice sin avanzar mientras la simulación está pausada.
- Una retención con nombre en la sesión es más segura que desactivar el nodo: desactivarlo cortaría `_input`, y la radio necesita sus eventos de movimiento para la regla de armado.
- Destruir la escena de Inicio antes de su primer dibujado deja dos texturas GL de 256 × 256 reportadas como filtradas al salir (Compatibility, llvmpipe). Una sonda mínima con una textura sola no lo reproduce, ni la sombra sola; no se aisló más. Una persona no puede pulsar Volar antes del primer frame; la captura espera dos frames.

Prueba: `tests/test_ui_pause.gd` (33 comprobaciones, seis mutaciones detectadas), capturas `ui-pause-en.png`/`ui-pause-es.png`, traza y captura de vuelo idénticas al HEAD, suite completa en un clon limpio.

## 2026-10-06 · EX-02b/EX-10a — superficie suave, tren del plano y decoración que se lee

- Interpolación cúbica **monótona** (Fritsch–Carlson) entre estaciones medidas: pasa por cada medida y no sobrepasa los valores vecinos. Un spline normal habría abombado el marco trasero de la cabina, que sube 79 mm en 53 mm de longitud. Render frente a datos ≤ 1,16 mm.
- Una pieza asentada sobre otra debe tomar el ancho de la piel a su altura, no una fracción del ancho máximo: la cúpula asomaba «orejas» sobre el lomo redondeado.
- Con espaciado uniforme, el morro romo de la carena quedaba entre dos muestras y salía en cuña. El espaciado coseno concentra las secciones donde el contorno gira.
- Las UV en coordenadas del modelo (metros, fracción de cuerda) permiten definir la decoración con las cotas del avión: la misma banda cruza paneles y mandos sin costuras, sin textura. Una banda definida como fracción de la altura local se escalonaba donde cambiaba el techo; en altura absoluta salió recta.
- La métrica de orientación necesitaba dos arreglos para no engañar. La luminancia sola no distingue rojo de azul. Y los píxeles de borde mezclados con el cielo contaban como «azul» (5–15 % en un avión todo blanco); contando solo píxeles interiores, la línea base es 0 %.
- Una copia de trabajo desincronizada (geometría generada anterior) pasaba sus pruebas; el `diff` previo a instalar lo detectó. Sincronizar los ficheros generados antes de verificar en la copia.
- Un `rm -rf $S/...` con variables fue bloqueado por el control de seguridad. Usar `"${S:?}"` en scripts de trabajo.

Prueba: [revisión 2](docs/research/extra-300-visual-review-v1.md#5-revisión-2-2026-10-06-ex02b-y-ex-10a-aplicados), `verify_extra.gd` 104/0 (mutaciones M7–M9 detectadas), `app/test.sh` en verde en un clon limpio, 82 renders idénticos en dos ejecuciones.

## 2026-10-06 · Avanti — continuidad de fuselaje y cabina

- El ajuste moderado de semianchura y vientre mejoró las muestras frontal/posterior del fuselaje con cámaras congeladas; el perfil permaneció igual. No se corrigió la cola a partir de una perspectiva discrepante.
- Separar interpolación de secciones y normales suaves permite mejorar silueta y acabado con pruebas distintas: preservar estaciones/límites y verificar que el sombreado no mueve vértices. El mayor número de triángulos requiere una medición posterior de rendimiento.
- Comparar cada revisión con su antecesora evita atribuir al último cambio las mejoras acumuladas desde la maqueta inicial. El comparador acepta una referencia explícita y guarda hashes de ambas geometrías.
- SciPy erosiona por defecto con cuatro vecinos; el informe anterior decía ocho. Se corrigió la descripción, sin alterar el algoritmo ni reescribir las mediciones históricas.

Prueba: [revisión 3](docs/research/avanti-s-contour-refinement-v3.md), clon sin referencias, comprobaciones de interpolación/normales/mandos y capturas con la misma cámara.

- Verificación v3: la mutación con normales cero sobrevivió al chequeo de longitud tras la codificación de malla. Comparar su orientación con las caras sí detectó el defecto; no basta con exigir vectores unitarios.

## 2026-10-06 · VQ — buscar recursos antes de crearlos

- El segundo catálogo del propietario se convirtió en un procedimiento del plan: revisar repo/fuentes, comparar hasta tres candidatos y documentar reutilizar/adaptar/crear. L6a comprueba primero si existe una familia adecuada antes de ensayar el generador; sus pruebas de silueta, atlas y export siguen vigentes.
- cgbookcase declara CC0 para sus texturas; Poly Pizza/itch.io/OpenGameArt requieren comprobar cada recurso. Asset Store sigue en beta y complementa Asset Library. Godot Shaders licencia código por separado de imágenes y assets de demo: una captura atractiva no aporta los permisos de sus texturas.
- Freesound y las fuentes de mocap amplían el catálogo de investigación, sin convertir audio ni personajes animados en requisitos del primer paisaje. Gratis, uso comercial y redistribución de archivos fuente son condiciones distintas.

Prueba: [fuentes primarias y flujo de selección](docs/research/asset-sources-catalog-2026-10-06.md), texto recibido conservado con SHA-256 y comprobación documental. No se descargaron packs ni se ejecutó la suite del juego en esta entrega.

## 2026-10-06 · VQ — usar herramientas sobre assets reales

- Kenney Nature Kit aportó tres árboles de 78/114/196 triángulos, pero sus GLB originales fallan Khronos con `SCENE_NON_ROOT_NODE`. Godot los importa de todos modos: importar no prueba conformidad. Reescribir con glTF Transform 4.5.0 `weld` produjo derivados sin errores/warnings, −7,7 % de bytes y captura idéntica. El original se conserva como evidencia, no como recurso aprobado.
- En una escena aislada de 480 árboles, 24 MultiMesh con dos superficies consumen 48 draws; unificar colores/material en una superficie da 24 con las mismas 62.080 primitivas. Presupuestar superficies y pases, no solo nodos. No es una medición de FPS ni un ensayo del campo completo.
- La declaración `KHR_materials_unlit` del archivo no describía los materiales efectivos: hojas y troncos llegan con sombreado por píxel y `metallic=1`. Separar conversión conservadora de adaptación artística. El A/B también detectó una conversión sRGB innecesaria para colores por vértice en Compatibility; corregida, la diferencia máxima de la unión es un nivel de 8 bits. Repetirla al cambiar backend.
- Grass001 1K de ambientCG funciona como muestrario de albedo frente a normal OpenGL + roughness en StandardMaterial3D. El relieve cercano no elimina repetición del tile ni demuestra lectura en vuelo. El shader del suelo, su bruma y sus zonas aún necesitan integración y A/B propios.

Prueba: [ensayo Kenney y herramientas](docs/research/visual-quality-nature-trial-2026-10-06.md), seis casos repetidos en dos procesos, validación Khronos y comparación Pillow/NumPy; [muestra PBR](docs/research/visual-quality-material-trial-2026-10-06.md). Ejecución aislada con Godot 4.7.2 Compatibility/llvmpipe; sin cambios de esta tarea en la app ni benchmark de la 3090.

## 2026-10-06 · Avanti — más vistas y ambigüedad de cámara

- Revisar el índice completo de las galerías oficiales recuperó 30 fotos adicionales que no estaban en la primera selección: incluyen frontal baja, interior, detalles bajo el morro y el ala, cola e intradós en vuelo. No son 30 fuentes independientes.
- Cuatro puntos aproximadamente simétricos pueden admitir una solución reflejada: la primera correspondencia de alas en una foto inferior dio una cámara encima del avión. Corregir izquierda/derecha y verificar el hemisferio descartó esa falsa coincidencia.
- La lámina comercial de tres vistas ayuda a distinguir intradós/extradós, pero la ficha del producto no transforma sus dibujos sin cotas en un plano calibrado. El reportaje de Aerotec usa P220 vectorial; no trasladar su salida al P100 fijo.
- La nueva frontal revela diferencias de sección que las primeras oblicuas no resolvían. Las comparaciones se añaden sin cambiar geometría, conservando imágenes, tamaños nativos, puntos reservados y errores desfavorables.

Prueba: [galería y nuevas comparaciones](docs/research/avanti-s-new-angles.md), hashes de 33 recursos, tres renders repetidos en clon sin referencias, ajuste determinista y visor de escritorio/móvil. Todos los originales gráficos siguen fuera de Git.

## 2026-10-06 · UI-04a/b — identidad de build y Ayuda

- Exportar de verdad era barato y mereció la pena: las plantillas ya estaban en la máquina y `export.sh` completo en un clon limpio demostró la cadena entera (el binario exportado declara su `git describe`, el `.exe` pasa de 1.0.0.0 a 0.1.0.0). Una captura de la ventana del binario exportado con `ImageGrab` de Pillow sobre Xvfb, sin `xwd`, enseñó el Inicio empaquetado.
- Buscar un nombre en un binario necesita distinguir datos de ajustes: `addons/build_info` aparecía en el paquete solo como la ruta de `[editor_plugins]` dentro de los ajustes del proyecto; los scripts no estaban.
- Una lambda guardada en una variable `static` de un script hace abortar Godot 4.7.2 al salir (código 134, tres de tres; con la variable vaciada antes, cero de tres). Se descubrió por una sonda que inyectaba un mapeo de teclado; el mapeo pasó a ser parámetro.
- `keyboard_get_label_from_physical` imprime `ERROR: Not supported by this display server` en headless, y `test.sh` lo contaría como fallo; `keyboard_get_current_layout() >= 0` lo evita. `Expression` no resuelve las constantes `KEY_*`, pero `OS.find_keycode_from_string()` sí, con el nombre sin prefijo.
- Comprobar que una pantalla cabe sin scroll con `get_combined_minimum_size()` funciona en headless si el contenedor fija el ancho: detectó 622/641 px frente a 600 igual que la captura, y vigila que una traducción futura no esconda «Acerca de» a quien navega con teclado.
- Con tres botones en una fila, Abajo desde el botón ancho cae en el del centro por geometría; un vecino de foco explícito lo fija.

Prueba: `test_build_info.gd`, `test_controls_reference.gd`, `test_ui_help.gd` (27, con mutaciones), `export.sh` completo, capturas de Ayuda y pista en inglés y español.

## 2026-10-06 · EX-04 — holguras medidas, bisel de bisagras, hélice y piloto

- Antes de cambiar la geometría, medir. Mi predicción («a 30° el timón de canto recto penetra la deriva») era errónea: había 0,8 mm de holgura y el cruce llegaba hacia los 41°. La medida orientó bien el arreglo: el bisel subió la holgura mínima a 1,75 mm y deja libres las bisagras a 45°.
- «Sin penetración» no basta como criterio: sin bisel, el elevador quedaba en contacto exacto (0,0 mm) a 45° y la prueba pasaba. Exigir además una holgura mínima.
- El corte de alivio del elevador del plano limita el timón a 43° con el elevador neutro. Es geometría medida, no un fallo del modelo: se deja tal cual y se documenta como límite para los recorridos de EX-05.
- Un nodo debe colocarse en el centro de su pieza si luego se va a girar: la visera giraba alrededor del origen del avión y flotaba 4 cm sobre la cabina. La comprobación render ↔ datos lo detectó (+17,5 mm) antes que la vista.
- Coordinación entre sesiones: otra sesión iba a leer `Geometry.DATA` para el catálogo de aviones. Publicar las claves estables y las ya cambiadas (`pant_z/pant_y/main_leg_root` → `pant_profile/leg`) evitó que construyera sobre claves retiradas.

Prueba: `verify_extra.gd` 123/0 (mutaciones de bisel, holgura, altura del piloto), `app/test.sh` en verde sobre `HEAD` limpio `0ee0b51`, [revisión 3](docs/research/extra-300-visual-review-v1.md#6-revisión-3-2026-10-06-ex-04-articulación-hélice-piloto-y-cabina-transparente).

## 2026-10-06 · Avanti — perfil transparente del usuario

- Se conservó el PNG adjunto original de 1818 × 865 con alpha y hash, sin regenerarlo ni limpiar sus bordes. El damero del visor permite comprobar la transparencia sin tocar el archivo.
- Un recorte de fondo no elimina la perspectiva ni confirma la variante. Alinear por un extremo posterior inferido sirve como diagnóstico, pero no identifica la posición real del escape ni proporciona cotas.
- La superposición lateral señala cabina más baja/adelantada y parte alta de deriva adelantada en la maqueta. Son hipótesis para contrastar con las otras vistas, no cambios automáticos de geometría.

Prueba: [perfil aportado y comparación](docs/research/avanti-s-user-profile.md), original intacto, proyección verificada y regresión de cámaras de perspectiva en clon sin referencias.

## 2026-10-06 · Avanti AV-02 v4: detalle y siete superposiciones

- Una mejora de cabina/deriva en perfil puede empeorar otra cámara. Conservar cámaras y siete pares v3→v4 permite registrar ese compromiso: perfil mejora parcialmente, posterior alta empeora 0,7 px en muestras de cola; el lomo sigue pendiente. [Evidencia y límites](docs/research/avanti-s-refinement-v4.md).
- Añadir placas cambia el borde más cercano en métricas de silueta aunque la planta alar no cambie. No interpretar esa reducción como mejor forma del ala. La comparación del perfil excluye explícitamente la punta de deriva todavía desalineada.
- Las placas deben comprobarse contra triángulos transformados del alerón, no sólo su bisagra neutra. Cinco órdenes de alabeo y cortes en ambas caras de cada placa detectan una invasión deliberada; sigue siendo una prueba local muestreada.
- Una cavidad de salida requiere quitar la tapa posterior del fuselaje. Los marcos de cabina deben seguir su visibilidad al abrir el inspector interior. ArrayMesh introduce cuantización observable (~0,019 mm en el anillo de esta salida); tolerancias de malla deben reflejarla.

## 2026-10-06 · VQ-01a — la captura tiene que probar que se produjo

- `timeout ... || true` más comprobar que existe un PNG aceptaba evidencia vieja. Ahora cada caso elimina sus PNG/JSON anteriores, exige salida cero, decodifica la imagen y verifica el sidecar/hash; un error retira artefactos parciales y conserva el log. El marcador del conjunto solo se publica tras las comprobaciones completas. Dos mutaciones prueban que las guardas de frescura y código de salida sí importan.
- Separar atmósfera y campo no significa quitar el suelo: L2 mide terreno cercano/lejano y bruma. Un fixture que sobrescribe solo la construcción de suelo/pista conserva las 29 referencias; un obstáculo en la construcción del campo no se filtra al fixture. L5 aún debe compartir el campo con Home.
- Una vista de solo cielo puede registrar cero draw calls de mallas. La vista del sol lo demostró: exigir contadores positivos rechazaba una captura válida. Se admiten ceros, con sus propios controles de imagen, y hay una prueba de ese caso.
- El CSV incluye `created_utc`; comparar los datos de vuelo por separado evita llamar regresión a un cambio de fecha. Los datos y las 29 imágenes quedaron iguales, incluidos los cambios concurrentes del catálogo.
- No editar un script Bash mientras se ejecuta: puede releer el resto desde un offset anterior y fallar aunque `bash -n` pase. La verificación final se hizo sobre un clon congelado; ese fallo intermedio no publicó el marcador de éxito.

Prueba: [VQ-01a](docs/research/visual-quality-implementation/VQ-01a/README.md), suite del juego, 15 casos de guardado, siete experimentos de integración/métricas, dos mutaciones de guardas y 46 capturas nuevas en clon limpio. Sin cambios físicos ni relajación de límites L1–L4.

## 2026-10-06 · EX-03/05/07/11, AV-03, UI-05 — tres aviones en el menú

- Un catálogo de un solo archivo ([aircraft_catalog.gd](app/app_state/aircraft_catalog.gd)) con rutas como texto basta para tres aviones: la simulación lee `data` sin cargar código de render, y [render/airplane.gd](app/render/airplane.gd) es el único lugar que asocia ID → constructor → datum. Un ID desconocido o una vista previa sin datos se rechaza (salida 1), nunca se sustituye por otro avión.
- Poner el punto de referencia aerodinámico del Extra en el **centro aerodinámico ala-fuselaje**, y no en el CG como en el Stik, hace que el modelo global y el local (post-pérdida) tengan la misma rigidez en cabeceo: el Cmα sobre el ARP es solo de cola y la transferencia al CG aporta el resto. Con el ARP en el CG, el modelo local pierde la contribución desestabilizadora del ala/fuselaje.
- Las derivadas de amortiguamiento (Cmq, CLq, CLα̇) usan la pendiente de cola **sin** el factor de downwash (1 − dε/dα): la velocidad de cabeceo cambia el ángulo de la cola directamente. Usar la pendiente efectiva daba Cmq −4,8 en lugar de −9,1. El centro del incremento de sustentación de un alerón está al ~44 % de la cuerda local (teoría de perfil delgado), no en el alerón: ponerlo allí triplicaba Cmδa.
- Con los recorridos altos del manual (elevador 24°), tirar a fondo a 20 m/s lleva el Extra a α ≈ 47°: pérdida, como avisa el manual («too much throw can force the plane into a stall or snap roll»). El looping se vuela con ~0,3 de palanca. Probar un «looping a fondo» habría llevado a reducir eficacias sin evidencia; la prueba describe ahora la técnica del piloto y la pérdida por separado.
- Una prueba que compara el vuelo con predicciones calculadas desde los mismos datos no detecta datos equivocados (mutación del recorrido de alerón: pasa). La detecta la prueba cruzada con el modelo visual (`manual_throws_deg()`). Hacen falta las dos clases de prueba.
- Las etiquetas de Godot guardan el texto fuente y traducen al dibujar: comprobar `label.atr(label.text)`, no `label.text`. Un resumen largo sin `autowrap` ensanchaba la columna lateral de Inicio en español; solo la captura lo mostró.
- Dos errores de tipado de GDScript (`:=` sobre un valor sin tipo) llegaron a `app/` en borradores de prueba y habrían roto la ejecución de todos: los borradores se comprueban con `--check-only` fuera de `app/` antes de copiarlos.

Prueba: `test_aircraft_catalog.gd` (28), `test_extra_handling.gd` (12), `test_ui_aircraft.gd` (16), `verify_avanti.gd` (137), trazas `--aircraft` en `app/test.sh`, `derive_physics.py --check` en CI; siete mutaciones en copia, todas detectadas; vuelos dorados, manejo, barrena y trim del Stik sin cambios.

## 2026-10-05 · Herramientas — selección de skills Godot

- Leer las instrucciones concretas cambia la selección: la skill de input exige zonas muertas radiales para sticks, mientras la emisora RC necesita canales independientes. Se dejó fuera.
- Las guías de iluminación incluyen caminos para Compatibility y Forward+; instalar una guía no valida todos sus ejemplos para nuestro renderizador. La física float64 y los datos con procedencia siguen siendo contratos del proyecto.
- Se instalaron seis skills con commits fijados y sin modificar sus paquetes. Prueba: 238 archivos cotejados con blobs Git, seis frontmatters y sus enlaces relativos comprobados, 17 scripts Python analizados sintácticamente. No se ejecutaron sus ejemplos. [Selección, límites y reproducción](docs/GODOT-SKILLS.md).

## 2026-10-06 · P51 — un avión «de 120 cc» que no existe como ARF

- Buscar el kit antes de modelar cambió el encargo: ningún ARF comercial de P-51D cubre 100-150 cc (el CARF de 2,54 m es de 50-85 cc). La clase 120 cc es la escala 1/4 de planos; escalar el avión real exactamente 1/4 resultó más honesto y más trazable que inventar un «kit», y coincide con Veich/Bates/FokkeRC en envergadura, longitud y área.
- Un modelo de elemento de pala escrito con factores de inducción se rompe a J bajo y en estático; en forma de velocidades inducidas (w_a, w_t con pérdida de Prandtl) converge en todo el rango y da Ct0 0,14 / Cp0 0,057 para la cuatripala 26×12, régimen estático 5.970 rpm con la curva del DA-120. Comprobar siempre el cuadro de Ct(J) a mano antes de volar con él.
- Una hélice grande de paso bajo en un avión de 22 kg hace que a 27 m/s y 40 % de gas el empuje sea negativo y *decreciente con las rpm*: Newton empuja el gas por debajo de cero y el solucionador devuelve «Jacobiano singular». Reintentar solo tras fallar, desde gases iniciales mayores, resolvió el trimado sin mover un bit los goldens del Stik ni el Extra (verificado). Falta un mensaje explícito para «gas > 1».
- El inventario físico no puede colocar el motor en el cortafuegos escalado del avión real: en el modelo RC el bicilíndrico va justo detrás del cono, 0,5 m más adelante. La primera versión pedía 6,5 kg de lastre; con la instalación RC real quedan 1,7 kg, coherentes con lo que los constructores de warbirds reportan.
- El loader rechaza tamaños de caja negativos: `cp_y - axle_y`, no al revés. Y 2 × 2,2 kg de ala + 2 kg de retráctiles ya superan la masa de un 1/4 ligero: contrastar la suma del inventario con el rango del kit antes de ajustar coeficientes.

- Modelo visual: el subagente verificó los signos de las cuatro bisagras contra el Ugly Stik construido directamente, y detectó que el encargo decía «timón +0,3 rad mueve el borde de salida a la izquierda» cuando la convención del repo es a la derecha. Pedir siempre «compara con un avión existente» además de «cumple el enunciado». El pivote del patín de cola se colocó sobre su eje y no sobre la bisagra del timón (0,11 m más atrás): si no, el patín barría de lado en vez de girar.
- Un test de UI que cuenta aviones («1 de 3», tercera pulsación = Avanti) se rompe con cada avión nuevo; el test del catálogo recorre las entradas y absorbió el P-51 sin cambios salvo el recuento.

Prueba: `tests/test_p51_handling.gd` (15 checks), `test_trim.gd`, `test_golden.gd` y `test_extra_handling.gd` sin cambios tras el reintento del trimado, [derivación](research/p51/p51-05/derivation.md), [plan](docs/P51-PLAN.md).


## 2026-10-06 · VQ-01b — referencias visuales y medición reproducible

- El `delta` de Godot no equivale siempre a tiempo real: bajo carga en llvmpipe, tres ventanas de ~60 s monotónicos acumularon solo ~17–19 s de `delta`. El logger conserva ambos canales; sus percentiles de pacing usan `Time.get_ticks_usec()`. Es evidencia del reloj, no un benchmark de la GPU del propietario.
- Un frame que cruza el calentamiento puede incluir un stall de compilación. Se descarta entero y se inicia una ventana completa desde el siguiente intervalo; el último frame se conserva completo. Registrar los extremos reales evita recortar o esconder el peor frame.
- Un vuelo con entrada habilitada se identifica como `live-input`; solo el recorrido sintético con entrada desactivada es `scripted-fixed`. En ese caso, trayectoria, cielo y hélice usan el mismo reloj; sumar `min(delta, 0.1)` a la hélice la hacía depender de la carga.
- Para capturar Inicio → Volar, desactivar el avance automático antes de ceder un frame y avanzar manualmente 360 ticks conserva el estado de 1,5 s. Desactivar el nodo de simulación basta para congelar la imagen: marcarlo como pausado introducía una etiqueta PAUSED que no pertenece a esa pantalla. Comprobar también la cámara activa y el recuento de entornos después de liberar Inicio.
- La distancia de inspección es distancia al ojo, distinta de altura. Las seis poses a 20/50/100 m son fixtures etiquetados; ambos constructores usan cámara y luz comunes. No validan el manejo de un modelo experimental.
- Hashes de código y assets deben incluir las escenas raíz y el fixture, además de shaders/geometría. Los packs pueden omitir fuentes: `source_tree_available=false` y la identidad real de `BuildInfo` son más precisos que hashes ficticios.
- Un clon inmutable hace reproducible la prueba. El catálogo de cuatro aviones llegó mientras se validaba: se conservaron sus cambios, se fusionaron las comprobaciones nuevas de `test.sh` y se repitió la suite sobre esa integración. La actualización concurrente de navegación del P-51 resolvió el test que todavía saltaba directamente del Extra al Avanti.

Prueba: [VQ-01b](docs/research/visual-quality-implementation/VQ-01b/README.md), 112 capturas, nueve pares de campo idénticos, 38 imágenes anteriores y datos de traza intactos; 18 pruebas de guardas, 14 de matriz, 43 de muestreo y 65 de poses/procedencia; suites completas, tres exports y smoke Linux. L5 es el siguiente paso; medir GPU y lectura humana sigue pendiente.

## 2026-10-06 · L5 — campo compartido sin cambiar el vuelo

- Compartir un builder no basta: Inicio y vuelo deben cargar el mismo archivo, antes de crear cámara o sesión. La ruta interactiva necesita un error visible y la automatización un código de salida no cero; nunca sustituir datos inválidos por el campo predeterminado.
- El campo se describe en metros NED, con cantidades y procedencia; la conversión a Godot pertenece al render. Un número finito en float64 puede desbordar float32, y un rectángulo positivo puede colapsar al convertirlo: el loader comprueba también esa representabilidad.
- El orden del JSON no determina qué superficie gana un solape. L5 conserva meshes separados, con prioridad visual pista > segado > rough; dos rectángulos del mismo nivel no pueden compartir área. Los 3 cm de la pista siguen sin ser relieve físico.
- Una prueba con piloto fuera del origen detectó que Inicio ignoraba la estación: su composición ahora usa desplazamientos desde los ojos del piloto. El campo por defecto mantiene la imagen anterior; un campo personalizado cambia ambas rutas coherentemente.
- El JSON debe probarse dentro de cada pack desde un proyecto vacío. Ejecutar el smoke desde `app/` podría resolver el archivo fuente y ocultar un fallo del filtro de exportación. El cargador compilado y el SHA del JSON se verifican en Linux/Windows/macOS.
- Los cuatro snapshots antiguos de pausa/hint dependen del tiempo de pared; no son goldens píxel a píxel. La comparación L5 exige paridad en los otros 108 casos deterministas y en las filas de datos de la traza, conservando los umbrales previos.

Prueba y reproducción: [L5](docs/research/visual-quality-implementation/L5/README.md). No se cambian simulación, colisiones ni datos de aeronaves; el siguiente paso visual es L6a.

## 2026-10-06 · P51-02b — siluetas: superponer antes de medir

- Empecé extrayendo cotas de la tres vistas con rellenos y máscaras; el propietario señaló que el Avanti fue más fácil y rápido. Tenía razón: la superposición con cámara anclada (dos anclas, escala uniforme, render plano transparente) mostró de un vistazo que el ala estaba 0,33 m adelantada y 0,37 m alta y la cabina casi 1 m atrás; la metrología solo puso números. Orden: superponer, mirar, corregir, medir.
- Un dibujo de línea no es una foto: el relleno «fuga» por los huecos de las líneas discontinuas que cruzan el contorno. Cerrar la tinta 3 px antes de rellenar sella el avión; una apertura de 4 px borra cotas y texto; el relleno llega al borde exterior de la tinta y hay que retroceder 2 px. Las cajas de exclusión deben respetar la pieza (la primera cortó la punta de la deriva y falseó la escala un 7 %).
- La reproducción de 1945 es ~3 % anisótropa en el perfil y no en la planta: calibrar cada eje de cada vista con su cota impresa y reservar otras cotas como comprobación (estabilizador, área, MAC quedaron dentro del 0,7 %).
- Las tres vistas comparten la columna de simetría en el papel: la frontal se centra con la planta, porque su píxel más alto es una pala, no el cono.
- Un script que «desplaza» valores existentes no es idempotente: el piloto se fue 0,8 m delante del morro en la tercera ejecución y apareció como una línea vertical misteriosa (su placa blindada). Escribir valores absolutos desde una plantilla.
- La métrica de contorno castiga lo que la referencia dibuja y el modelo no (palas, patín extendido, depósitos): excluirlo por cajas o declararlo cualitativo, no «mejorar» el modelo para ganar píxeles.
- Al medir bien la geometría, la física mejoró sola: el morro largo adelanta la instalación y el lastre virtual bajó de 1,66 a 0,21 kg, como en los P-51 de 1/4 reales con DA-120.

Prueba: [informe](docs/research/p51-silhouette-review-v1.md) con métricas y hashes, `verify_p51.gd` 126, `test_p51_handling.gd` 15, `test_aircraft_catalog.gd` 34, `app/test.sh` completo.

### L6a — elegir árboles por imagen y comprobar la ruta completa (2026-10-06)

- Once siluetas Kenney y siete modelos de otros packs renderizados mostraron que cumplir triángulos no basta para elegir arte. Quaternius Standard aporta copas más orgánicas; se archivó su licencia CC0 incluida y el SHA exacto, sin extrapolar a la licencia general QAL. [Comparación](docs/research/tree-resource-review-2026-10-06/README.md).
- Separar presupuesto de autoría y runtime: fuentes de 3.505–6.265 triángulos producen cards de seis triángulos y una superficie. Las mallas fuente no se exportan ni se aprueban como LOD cercano. Un atlas sin iluminación direccional conserva la luz del campo, pero carece del detalle de normales de la fuente cuando se mira de cerca.
- PNG externos y GLB con texturas extraídas no recibieron los mismos mipmaps por defecto. Un prototipo con importación de editor también produjo pequeñas variaciones del pino entre imports nuevos; cuatro renders del mismo import sí coincidieron. Cargar las dos referencias offline con GLTFDocument, imágenes sin compresión y mips explícitos permitió dos bakes nuevos byte-idénticos. No confundir ese diagnóstico acotado con demostrar un bug interno concreto del editor.
- Padding del atlas no es altura del árbol: situar el quad en Y=0 hacía flotar el tronco. Centrar el marco alrededor del pivote y comprobar el texel opaco inferior detecta el fallo. El downsample requiere RGB ponderado por alpha para evitar bordes negros.
- Revisar el pack real: no basta con que el PNG fuente tenga mips. La prueba desde un proyecto vacío carga atlas/material/catálogo/licencia y comprueba tamaño y mips en Linux, Windows y macOS. Python además debe rechazar bool al validar números de JSON, igual que Godot. [Pruebas](docs/research/visual-quality-implementation/L6a/README.md).


### L6b — vegetación integrada por sectores

- Compatibility empaqueta `MultiMesh` custom data en float16: coordenadas de 0,25 m pierden precisión a ciertas distancias. Codificar las dos coordenadas de la rejilla en cuatro componentes enteros 0–255 mantiene identidad CPU/shader. Un probe real de los 480 árboles detectó el fallo y verifica especie/altura/giro.
- Leer valores continuos como colores del framebuffer puede confundir transferencia de color con errores del hash. La prueba de identidad lee bits blanco/negro, con cuantización explícita de altura/giro. En headless, los getters de instancias del renderer dummy no sustituyen la comprobación OpenGL.
- Las exclusiones deben considerar la copa completa y el corredor de aproximación, no solo el centro del tronco dentro del rectángulo de pista. El loader exige una envolvente conservadora de 15 m y bounds de render incluyen padding bajo suelo, escala y giro.
- Tres especies de un atlas caben en una superficie por sector cuando el shader elige UVs. La arboleda completa usa ocho draws, las vistas piloto cuatro y los claros dos; sombras de cards desactivadas. Son contadores en llvmpipe, no prueba de FPS objetivo ni aceptación humana de legibilidad.
- Un clon sin `.godot` mostró que `capture.sh` dependía de la importación hecha por tests/editor. El runner de capturas y la revisión aislada ahora importan recursos antes de empezar; no se acepta una imagen con atlas ausente aunque Godot termine con código cero.

### Presentación del repositorio y guía de pilotos

- El README y la guía de primer arranque deben reflejar el catálogo y la tabla de controles del código: la guía antigua aún decía que no había menús. Distinguir aviones volables, estimaciones experimentales y previews evita prometer validación física pendiente.
- Para un proyecto que publica prereleases, enlazar a `/releases`: `/releases/latest` no es una entrada fiable a la última alpha. Conservar la etiqueta de release y publicar las mejoras de documentación en otro commit mantiene la identidad del binario.
- Prueba: enlaces locales e imagen verificados; controles y estados cotejados con `controls_reference.gd` y `aircraft_catalog.gd`; solo documentación y plantillas, sin cambios de runtime.

### README visual — capturar el catálogo real

- Una galería uniforme construida con `render/airplane.gd` muestra los cuatro modelos actuales sin reutilizar renders de revisiones antiguas. Los bounds de cada avión mantienen el encuadre; las etiquetas del tour salen del catálogo y conservan el estado experimental/preview.
- GitHub admite GIF, tablas HTML y bloques `details`: un tour de 96 fotogramas a 640×360 pesa 1,7 MB y tiene alternativa estática. Separar vistas de estudio y capturas reales del juego evita presentar una órbita de cámara como maniobra volada.
- Prueba: renders inspeccionados, GIF decodificado (96 frames/10,56 s), hashes y enlaces locales comprobados; render Markdown de GitHub verificado. Herramienta de documentación fuera de `app/`, sin cambios de runtime.

## 2026-10-06 · P51-02c — la foto del usuario con cámara en perspectiva

- Identificar el lado antes de marcar puntos: vista desde abajo con el morro a la derecha, la escarapela del intradós está en el ala derecha, luego se ve el lado derecho y el ala del lado izquierdo de la imagen es la derecha del modelo. Con los lados cambiados el ajuste daba 27 px de RMS y una cámara reflejada (lo mismo que en el Avanti); corregido, 8,6 px.
- El «vértice del cono» en una foto es el centro del casquete visto, no el borde de su silueta; marcarlo en el borde desplazó el morro 25 px.
- Un teleobjetivo deja FOV y distancia correlacionados: el ajuste se va al límite inferior del FOV sin empeorar la superposición. Ajustar el FOV, acotarlo y no leer la distancia como dato.
- Las palas borrosas tienen alpha parcial: el umbral 200 elimina la mayoría y las cajas el resto; sin ellas la métrica cae de 21 a 8,6 px sin tocar el modelo. Reportar siempre qué se excluye.
- Dejar de un lado, pero evaluar en varios ángulos: el dibujo ortográfico midió las estaciones; la oblicua reveló que la boca de la toma es un escalón y no la rampa que había interpolado entre estaciones.

Prueba: [sección de la foto](docs/research/p51-silhouette-review-v1.md#comparación-con-la-foto-oblicua-del-usuario), `research/p51/p51-02/silhouette/photo/metrics-2026-10-06.json`, suite completa.

## 2026-10-06 · P51 — revisión visual: separar dimensiones de formas

- Con las siluetas dentro de 1-3 cm de modelo, lo que delata al P-51 ya no son medidas sino **formas**: deriva/timón de placa, estabilizador de puntas cuadradas, toma ventral «barriga de ballena», raíz alar sin extensión ni carenado, escapes como peine. Una tabla de hallazgos con gravedad A/B/C y evidencia por imagen ordena el trabajo mejor que una lista de deseos.
- Las fotos de archivo sin cámara ajustada sirven para formas y detalles (comparación cualitativa en el ángulo de órbita más parecido), no para medir; mantener la métrica solo donde hay cámara ajustada (dibujo y foto del propietario) evita confundir las dos cosas.
- Cada paso del plan visual lleva un criterio de aceptación por siluetas («no empeorar perfil 7,7 px / planta 15,0 px, mejorar la raíz alar»): así la forma no se corrige a costa de las dimensiones ya medidas.

Prueba: [revisión visual 1](docs/research/p51-visual-review-v1.md), [plan visual](docs/P51-VISUAL-PLAN.md), comparativas en `research/p51/p51-02/visual-review-2026-10-06/`.

## 2026-10-06 · L6c — medir antes de creer la estimación

- La estimación del plan («rojo sobre verde, −0,18 de contraste») valía para la hierba plana y ni ahí: ante las cards de árboles L6b el Stik iluminado de frente es **más claro** que el fondo (Weber +0,6/+0,7) y sobre la hierba +0,7/+0,85. Donde sí aparece el par débil es en **horizontal sobre hierba** (ala roja vista desde arriba: 25 % de píxeles casi invisibles en luminancia, ΔE 53). Y en el **borde de copas**, cielo y árboles se compensan y el Weber medio cae a −0,15 aunque cada píxel siga separándose (≤ 11 % casi invisible, ΔE ≥ 47); con el avión de 12 px del fixture de 50° el mezclado anula el contraste medio ante árboles y hierba. En fondos mixtos o blancos pequeños no usar el contraste medio contra el anillo: registrar la fracción local y el decil bajo de ΔE.
- El norte exacto del fixture VQ-01b no sirve para «ante los árboles»: a 100 m el avión cae en el borde de un árbol con cielo detrás (49/51 %). Dos renders anchos con y sin arboleda, medidos por columnas, encontraron en un minuto el azimut con banda sólida (9°: 0,5°–4,1°); el sur era igual de denso pero mira al sol. Elegir fondos midiendo la escena comprometida, no el dibujo de la distribución.
- Una máscara exacta vale más que clasificar colores: ocultar la arboleda (`--hide_treeline`) y restar imágenes da los árboles píxel a píxel; la fila del horizonte sale de la transformación real de la cámara registrada. Con eso el runner puede rechazar un caso que no es lo que su nombre dice (guardas de identidad, distintas de los umbrales de calidad, que siguen siendo de Gate L).
- Para el playtest, la imagen debe ser la del juego (autozoom, FOV 20,7°, ~30 px de envergadura), no la del fixture de 50° (12,6 px): el contrato de poses pasa de «autozoom prohibido» a «autozoom explícito 0/1 registrado en la evidencia»; la familia VQ-01b sigue fijando 0. Los defaults nuevos reproducen la pose anterior bit a bit, y una prueba lo exige.
- Un orden ciego se fija con una semilla propia y se comprueba que no coincide ni con el orden alfabético ni con el de generación; las imágenes del kit se copian sin sidecar y el visor no contiene nombres de caso. El puntuador exige filas completas: una respuesta en blanco no cuenta como fallo silencioso.
- Trabajo en paralelo: mientras corría mi suite, otro desarrollador guardó `physics/aircraft_data.gd` a medias (función aún no escrita) y la tanda de capturas falló al cargar `main.gd`. La evidencia se repitió en un worktree congelado de HEAD con solo mis archivos; no hay que tocar el trabajo ajeno ni esperar a que termine.

Prueba: [L6c](docs/research/visual-quality-implementation/L6c/README.md), `test_visual_evidence.gd` (97), `test_treeline_readability.py` (10), 64 capturas medidas, suite completa y `capture.sh` en el worktree congelado.

## 2026-10-06 · E1 — tren de aterrizaje como contactos muelle-amortiguador

- La regla `ω·dt < 0.1` del ROADMAP fija el tren más blando de lo que parece: Σk < 1662 N/m para 2,9 kg a 240 Hz, 18 mm de flecha estática. Es la rigidez que el integrador explícito resuelve, no la medida; si algún día se mide un tren más rígido, hacen falta subpasos del contacto o un tick más fino, y así queda etiquetado en la fuente del dato.
- Repartir la rigidez según la carga estática (27 % morro, 73 % principales) hace que el avión repose nivelado; con el morro más blando «sin pensar» quedaba 2° picado y la prueba de reposo lo delató.
- El modo de cabeceo sobre el tren (ζ ≈ 0,2, τ ≈ 0,5 s) tarda más en calmarse que el de altura: 4 s no bastaban para 10⁻⁴ rad/s y el umbral parecía un fallo del contacto. Antes de aflojar una tolerancia, estimar la constante de tiempo del modo.
- La fuerza de contacto es vertical en NED, así que el CG no puede desplazarse en horizontal: la deriva que aparece (2 µm) es error de truncamiento de RK4 en ejes cuerpo y se demuestra porque se reduce 17,9× con h/2 (cuarto orden). Una prueba de convergencia dice más que una tolerancia suelta.
- Devolver un array vacío cuando ninguna rueda toca, en lugar de ceros, mantiene el vuelo en el aire bit a bit (sumar +0,0 a −0,0 cambia el signo que imprime la traza).
- GDScript no admite `%e` en `%`: el error de formato abortó `_initialize` antes de `quit()` y el run headless quedó colgado hasta el `timeout`. Usar `%s` (str) para números pequeños; un test que no llega a `quit()` cuelga, no falla.
- La tabla de equipo del modelo visual sitúa el eje principal 2 cm por delante del CG (triciclo que se sentaría sobre la cola); la física conserva el 0,215 m del casco D9d y la prueba solo compara vía y alturas. Cuando dos equipos estiman el mismo número, la prueba de acuerdo debe limitarse a lo que ambos sostienen.
- Un suelo que no empuja no se nota: `slow_flight` y `spin_right` bajaban a −78 m y −55 m desde 2026-10-05 sin que ninguna prueba lo viera, porque `Maneuvers.fly` no pasa por la comprobación de choque. Al hacer real el suelo, la barrena perdió la autorrotación (0,23 rad/s) y pareció un fallo del tren. Las maniobras que caen empiezan ahora a 150 m; la densidad es constante y sus resultados no cambian. Toda maniobra escrita debería registrar su altitud mínima.
- «Antes» medido en un worktree de HEAD con `.tools` enlazado (traza y bench) sin tocar los archivos a medias de los demás; las mutaciones en una copia `rsync` sin assets (enlazados) para no dejar nunca un archivo roto en el árbol compartido.

Prueba: [E1](docs/research/landing-gear-contact-e1.md), `test_ground_contact.gd` (22), `test_crash.gd` (12), `test_aircraft_data.gd` (66), traza idéntica en filas, goldens sin cambios, 4 mutaciones detectadas.

## 2026-10-06 · P51-V01 — cola por contornos medidos y holguras

- Un loft cuyas estaciones no están ordenadas se pliega sobre sí mismo y la malla «cerrada» deja de serlo: el comprobador de holguras lo lee como penetración en cualquier pose, incluso en neutro, sin que ningún vértice esté dentro del vecino. Ordenar siempre la lista de estaciones (la del cuerno al 86 % quedó detrás de «punta − 9 cm») antes de hacer el loft; una comprobación de monotonía evitaría repetirlo.
- `extra_clearance.gd` usa `global_transform`: solo vale con el avión dentro del árbol de escena (`call_deferred`); en `_initialize` devuelve identidad y toda pareja «penetra». Reutilizarlo fue correcto (es genérico por nombres de malla), pero cuesta ~5 s por pose y pareja sobre lofts de 1-2 k triángulos: con 9 poses tardaba 124 s frente a los 60 s por script de `test.sh`. Solución: verificador propio con dos poses extremas (recorridos volados y 45°) y las tres parejas que pueden tocarse: 33 s.
- La compensación de los elevadores no puede hacerse con una transición diagonal de 8 mm entre estaciones: la nariz del cuerno barre la cara diagonal del estabilizador al deflectar. Escalón casi vertical (±0,5 mm) con el cuerno 2 mm por fuera del corte, como en el avión real.
- Compartir la estación final del elevador con el estabilizador evita que la planta redondeada (curva) difiera entre dos lofts muestreados en estaciones distintas: 0,9 mm de solape desaparecen.
- Invertir un contorno medido y(z) por bisección (parte ascendente = borde de ataque y dorsal; descendente = cabeza y borde de salida) da deriva y timón fieles sin modelar a mano; por debajo del lomo el contorno no existe y hay que decidir explícitamente qué hace el timón (bisel hasta el cono).
- El cono de cola debe acabar antes de la charnela: si la termina 6 mm detrás, el timón atraviesa el fuselaje en neutro y nadie lo ve en las capturas; la holgura sí.

Prueba: `verify_p51.gd` 131, `verify_p51_clearance.gd` 12, siluetas perfil 7,7 → 7,2 px con cámara congelada, [comparación](research/p51/p51-02/silhouette/review-2026-10-06-v01/index.html).

## 2026-10-06 · Documentation — map, registry and index

- **A two-day repository can hold 17 plans, 167 reports and 13 step-ID namespaces with nobody knowing where a step's status lives.** The review found one step with status in three places (ROADMAP, VQ-PLAN, LANDSCAPE-PLAN), a plan whose header contradicted its own table (EXTRA-300-PLAN), a plan auditing a model that D9-R2 had already removed (WIND), Gate F decided without being labelled, and 228 links into an ignored folder. *Now:* `docs/README.md` registers tracks, plans, prefixes and owned paths; a step's status lives in its plan and ROADMAP keeps one line per track; links are checked before delivery.
- **With several tracks in one working tree, run `git status` before editing a shared document.** ROADMAP, LEARNINGS, DECISIONS and AGENTS changed on disk during the review; edits were exact-match replacements that fail when the text differs, never touching another track's lines. A batch that moved and deleted files was refused by the permission classifier; split into single-purpose commands it went through.

Proof: [audit](docs/research/documentation-audit-2026-10-06.md); link and anchor checker clean on every touched document; `--check-only` on the edited catalog script.

## 2026-10-06 · E2 — tyre friction and nose-wheel steering

- **A first-order error ratio is a symptom, not a tolerance problem.** The h vs h/2 turn disagreed by 7.6 mm and halving again gave a ratio of 2.0 where RK4 gives 16. The cause was not the tyre law: at 2 m/s the test airplane was rolling over, and a wheel bouncing on and off the ground is a discontinuity every few ticks. Before loosening a tolerance, measure the convergence order and look at what the body is doing.
- **Check a quasi-static oracle in the limit where it holds.** The inside wheel unloaded at 78 % of the rigid tip-over oracle g·d/h. Making the gear 4×, 16× and 64× stiffer converged to 4.50 vs 4.47 m/s², so the gap is the springs' roll compliance (18 mm sag), not a bug. The stiff-limit run became the test; the real gear is checked to be below it.
- **A snap input and a steady state are different experiments.** The first tip-over looked like 2 m/s; the steady full-steer turn held to 1.85 m/s only when the speed was ramped slowly, and an instant reversal tipped earlier. Test pilots need a stick rate (the test uses one throw per second).
- **Regularised friction needs a stated stability bound, and here it is airplane-independent:** ΣN = m·g makes the low-speed side-force rate μ·g/(tan α_peak·v_floor) for any mass, so the loader can check it like E1's ω·dt rule.
- **The closure test of a figure-eight must match the physics.** At idle the airplane keeps accelerating, so the second loop opens; checking "returns to where the leg began" measured the stick reversal, not the tyres. The test now checks the right loop closes (1.7 cm) and the left loop passes back by the crossing.
- **A mutation that survives names a missing test:** dropping `abs()` from the slip-angle floor passed all checks because nothing rolled backwards; a reversing hand-computed case now catches it.
- The E1 drift probe ("the CG cannot move horizontally") stopped being true with friction; it now runs on a normal-only copy of the gear instead of being deleted or loosened.

Proof: [E2](docs/research/ground-friction-e2.md), `test_ground_friction.gd` (26), `test_aircraft_data.gd` (72), `test_ground_contact.gd` (22), trace rows identical, goldens unchanged, 6 mutations caught.

## 2026-10-06 · E3a — field surfaces under the wheels

- **Read the other tracks' plans before trusting your own default.** E2 tuned "dry pavement" and found idle rolling the airplane away; the landscape plan had always drawn the runway as a mown grass strip whose rectangles were meant to feed ground physics. On grass the idle balance flips (2.6 N thrust vs 2.8 N rolling) and the "finding" mostly dissolves.
- **Borrow the convention, not only the numbers.** JSBSim/FlightGear keep tyre coefficients on the aircraft (pavement) and let the surface scale them; copying that split keeps one aircraft file valid on any field. FlightGear's material values changed between revisions (`grass_rwy` friction 0.9 in an old commit, 0.8 on `next`): cite the branch and the date read.
- **A regularised law has a signature you can predict:** above C_rr 0.1 the creep speed scales with C_rr, so the creep under a steady push is 0.1·F/(m·g) on every surface (0.92 cm/s on the runway and on the rough alike). A number identical across surfaces was the clue it is numerical, not physical; the fix (stiction with per-wheel state) is a step of its own, not a tolerance.
- **Test the lookup where the bug would hide:** a contact under the CG cannot tell a CG lookup from a wheel lookup; a wheel 0.3 m ahead of a CG near the runway's end can (the mutation proved it).
- **Wiring checks belong in the app trace:** a unit test cannot see `main.gd` forgetting `set_field`; the trace header can, so `check_trimmed_flight.py` now fails on gear without the field's surfaces.
- `FileAccess.get_file_as_string` on a missing file prints an engine `ERROR:` that `test.sh` treats as a failure; check `file_exists` first when a missing file is an expected, handled case.

Proof: [E3a](docs/research/ground-surfaces-e3a.md), `test_ground_surfaces.gd` (28), E1/E2 tests unchanged, trace rows identical, 5 mutations caught.

## 2026-10-06 · Plan review #4 — research knowledge base per phase

- **Re-derive a headline number before repeating it.** ROADMAP still said "pitch 1.45× too fast"; two independent research passes found it obsolete since D1-R1 (Iyy 0.218 → 0.387), and `research/sensitivity/results.md` silently predated the repair. Comparison tables must be generated from code and checked against the live test bands, or they rot.
- **A gap against flight data has a cheapest explanation; find it before tuning.** The 2× roll gap is mostly roll inertia (Ixx/(m·b²) 0.0172 vs 0.028 on both swing-tested UMN Sticks); tuning Clp would have "fixed" roll τ and broken roll rate, which already matches within 2 %. Hence ROADMAP rule 10.
- **Blends hide regime changes.** The oracle-to-local blend is continuous in loads but not in derivatives: Clp moves −0.45 → −0.77 and Cmq −13.6 → −4.4 between α 6° and 10°. Linearize across the blend, not only at trim (D11b).
- **Measure the budget before adding physics.** The bench read 501 µs per tick against 500 µs before propwash, shaft dynamics or turbulence; headroom work (Phase H) now precedes them.
- **Parallel research needs a lead's reconciliation pass.** Ten documents disagreed in three places (where rpm lives, the touchdown fix, G1 numbering); the resolutions are recorded in the knowledge-base README so later readers don't relitigate them. A session-wide web-search cap (200) was hit by the fourth agent; later sources were fetched by URL and are marked.

Proof: [knowledge base](docs/research/roadmap-investigations/README.md) (facts re-checked: bench 501 µs/tick; damping probe through `Aero.loads`; propwash ratio recomputed; 347 external URLs checked, 4 repaired); ROADMAP plan review #4; link checker clean on every touched document. No simulation code or data changed.

## 2026-10-06 · AV-05a, AV-06, AV-07 — the Avanti S flies on a turbine

- **An optional data key that the generator forgets is a silent physics change.** The derivation assumed ram recovery (Vmax 73.4 m/s) but did not write `ram_flow`/`ram_jet`; the loader accepts them as optional, so the simulator flew the plain momentum law (70.5 m/s). Comparing the report's Vmax with a trim bisection in the simulator found it; the handling test now checks the lapse the data must produce.
- **A trim solver needs a gradient past the limits.** Clamping the throttle map and the thrust table above full throttle gave "singular Jacobian" at speeds the airplane could almost reach; extrapolating them linearly (trim only, flight never leaves 0…1) turned it into "needs throttle 1.06".
- **Two unexplained symptoms that point the same way are worth testing as one hypothesis, and rejecting when the numbers say so.** The inventory balanced 100 mm forward of the manual's CG and the neutral point sat 35 mm ahead of it; moving the wing forward on the fuselage fixed the balance at 12.5 cm but the neutral point by only 23 mm, so it was not adopted and the stability was anchored on documented CG practice instead.
- **Probe failures before loosening tests:** the "slow" idle deceleration failed because the test's altitude-hold PD oscillated on this airframe, not because of drag; an energy-rate check against the drag polar replaced it (4 % agreement). Full-throw rolls (pb/2V 0.25) leave the linear range at the tips; the linear prediction is checked at the manual's normal D/R.
- **A fuselage-loaded jet does not spin like a trainer:** with Iyy ≈ 4·Ixx the full-up full-rudder entry wallows deep in the stall (α 68°) instead of settling into a spin; the meaningful checks are entry and recovery.
- **The owner commits the whole working tree:** files of an unfinished step can land in a commit. Keep every saved state parseable and passing.

Proof: [model report](docs/research/avanti-s-av06-physics-model.md), `test_turbine.gd` (27), `test_avanti_handling.gd` (30), `derive_physics.py --check`, app `--trace` with `check_trimmed_flight.py`, sensitivity table.

## 2026-10-06 · P51-06, P51-08, P51-09, P51-12, P51-13 — P-51 realism pass

- **Check a propeller model against power, not just thrust.** The blade-element 4-blade 26x12 looked plausible (32.6 kgf static) but needed ~8.5 kW at 5751 rpm; one measured static rpm on a known propeller (28x10 at 6550 rpm on a DA-120, Mejzlik Cp 0.0238) pins the installed power at 6.9 kW, 24 % under the catalogue rating, and the static rpm fell to 4950.
- **Manufacturer tables calibrate a BEM across blade counts:** fitting effective pitch and chord scale to the 2- and 3-blade versions together (rms 6.5 %) gives a defensible 4-blade prediction. Gas-propeller "pitch" understates the aerodynamic pitch by ~44 % (zero thrust at J 0.76-0.81 for a nominal P/D 0.46), which moved the top speed from 32 to 51 m/s.
- **Primary sources settle "unresolved" geometry quickly:** two NACA dimension tables gave root/tip chords, washout (+1°00' / −0°53'), stab incidence +2° and the measured neutral points; the conflicting values came from student slides.
- **A measured neutral point is a better anchor than a fuselage chart:** the textbook build-up put it at 38.5 % MAC; NACA measured 34.2 % in the glide. One lumped, labelled term (K_fus 0.033/deg) carries the difference.
- **Swirl must decay with the axial wash:** taking the wash factor (0.8·w static) from Selig but the ideal swirl gave a 22° static swirl angle at the fin and a 46° takeoff swing in 3 s; scaling the tangential velocity by the same k_w/2 keeps the swirl angle at the ideal wake's (~13° × straightening) and the swing at 30°.
- **Scripted pilots find the airplane's traps:** pulling to 16° at 17 m/s after touchdown drops a wingtip, a hard pull-out after a stall re-stalls the wing, and neutral stick still carries the up trim. Fix the pilot's technique (wheel landing, α-limited pull-out, stick relative to trim) rather than widening the band.
- **Count the CG height when flaring:** the main wheels hang 0.5 m below the CG; a flare started on the CG's height touched down at 3.3 m/s.
- **The owner commits mid-step and other tracks build on uncommitted files:** another track extended `propulsion.gd` on top of this work within the hour. Keep every saved state parsing and passing, and edit shared files with exact-match replacements.

Proof: [flight realism report](docs/research/p51-flight-realism.md), `tests/test_p51_envelope.gd` (15), `tests/test_p51_ground.gd` (11), `tests/test_p51_handling.gd` (15), `research/p51/p51-06/fit_mejzlik.py`, `derive_physics.py --check`; Stik goldens unchanged.

## 2026-10-06 · H1–H3, D11a–b — headroom without behaviour change, and a re-measured baseline

- **Measure the breakdown before optimising.** The headline (592 µs per tick on the loaded VM) hid that five load evaluations cost 73 µs each and the derivative 21 µs × 4, while RK4 itself costs 7 µs. The two cheapest fixes (reuse k1, scalar derivative) took the tick to 400 µs; flattening aero is next, but only once the tracks editing those files have landed.
- **Bit-identical refactors need an oracle that would notice.** A SHA-256 over state, aux and loads for 1,200 ticks × 4 aircraft × 3 regimes proved H2 and H3 changed nothing, and a deliberately stale cache changed all 12 hashes. Two mutations were themselves wrong (adding an exact zero first is not a reassociation; a crash is not a stale cache): check that a mutation is actually non-equivalent before trusting a survivor or a failure.
- **To keep a rewrite bit-identical, keep every operation, including multiplications by zero.** The scalar derivative copies the vector helpers' order and zero terms exactly; reassociating one sum gave 3,123 mismatches in 10,000 states.
- **When a refactor breaks a test, read what the test pinned.** The guard test counted load calls ("once before RK, then k1…k4"); H2 changed the count, not the safety. The test now injects faults by stage and pins the new count of four, so losing the reuse is caught too.
- **A parallel track can change your oracle's inputs mid-measurement.** The Avanti fingerprints moved between two runs because its data was regenerated in between; re-baselining HEAD code against the same data (scratch copy, only my files reverted) separated the two.
- **Validation tables must say they are generated.** `results.md` silently predated the flight repair; it now carries its generator and command. After the repair the loader ties Cnβ to the fin, CG to the inventory and the gear to the mass, so the sweep varies fin area, the whole inventory and mass with its springs: the physical knobs, not the derived numbers.
- **Report a mode near neutral by its pole, not its time constant.** The spiral's τ crosses infinity, so percent changes read −2,390 %; its pole λ stays small and continuous.
- **Pin a known defect instead of committing a red test.** `test_damping_regimes.gd` measures the regime jump (Clp × 1.73, Cmq × 0.28, Cnr × 0.72, CLα × 1.34 over α 0–11°) and fails if it changes either way; the fix flips one flag and the same measurements become the acceptance test.

Proof: ROADMAP H1–H3, D11a, D11b rows; `test_rigid_body.gd` (15), `test_session_guards.gd` (32), `test_damping_regimes.gd` (17); [`research/sensitivity/results.md`](research/sensitivity/results.md); `app/test.sh` green.

## 2026-10-06 · H, D11, E3b, G2, DATA — whole-project audit

- The full regression suite can pass while deliberately preserving a known aerodynamic defect; report verification and fidelity acceptance separately.
- Mutation checks found that the trimmed-flight smoke accepts one row and NaN end values. Require finite samples and completed time/ticks before checking flight drift.
- Measure every active aircraft: the experimental P-51 cost about three times the Stik physics tick on this shared host. Target-machine acceptance remains open.
- The frozen-aux rigid-body kernel is fourth-order; a current P-51 shaft transient showed first-order refinement. Define coupled state and stage time before anchors, shaft, wind or damage grow.
- Recheck historical findings against current code: the reported Stik gear mismatch was a datum error; exit-time audio warnings did not reproduce as cumulative Home/flight leaks.

Proof and recommendations: [project audit](docs/research/project-audit-2026-10-06/README.md), including runtime logs, clean-clone exports and reproducible probes. No simulator behavior changed.

## 2026-10-06 · H8, D11, E3b, DATA, CR — roadmap revision after the audit

- Put the continuous/sampled/discrete state contract before wheel anchors, coupled shafts, flow lags, wind, fuel and persistent damage; a feature list alone hides these dependencies.
- A known-defect characterization stays open for fidelity acceptance. The approach gate covers fin Cnr as well as wing Clp/CLα and tail Cmq, with physically justified bands.
- Profile every active aircraft before optimizing or changing language. Shared-host measurements locate expensive paths; only target hardware can close the performance gate.
- Optional schema v2, contributor interfaces and a custom VLM need concrete consumers. The next product outcome is one independently checked Stik ground circuit.
- Crash impact ranking does not supply material thresholds. Start with a factual contact snapshot; defer damage until contact/state/mass contracts and threshold evidence exist.

Proof: [ROADMAP revision 5](ROADMAP.md#execution-order-and-release-gates), [crash plan](docs/CRASH-DAMAGE-PLAN.md), reconciled research and track registry. Documentation-only change; simulator fixes remain planned and owner gates remain open.

## 2026-10-06 · PT1f — rc4 release preparation

- Release notes compare with the previous tag, so already-committed aircraft and physics changes are included alongside the audit and roadmap work.
- A passing known-defect characterization is not flight validation. The rc4 notes explicitly retain the smoke-checker, damping, coupled-shaft and owner-hardware limitations.
- Preserve raw audit logs, including emitted whitespace; apply source/document whitespace checks separately. Publish the tag only after the branch CI passes, then verify the tag build identity and downloaded release checksums.

Proof: [rc4 notes](docs/releases/v0.1.0-rc4.md), [audit evidence](docs/research/project-audit-2026-10-06/README.md). Release binaries and checksums are produced from the tag by CI; pilot gates remain open.

## 2026-10-06 · C7-R1 — require evidence that the flight actually completed

- A finite initial state and stable endpoints do not prove that any ticks ran. Check the requested sample count, every tick/time pair and every numeric sample before trim tolerances.
- A numerical guard can preserve a valid last state while stopping advancement. The trace producer must fail on the guard or missing progress; saving the remaining recorder buffer is not success.
- Duration is a caller contract: exports/app smoke use three seconds, captures use 1.5 seconds. Explicit arguments prevent accidental acceptance against a trace's own truncated endpoint.
- Failed recordings preserve an existing file and return nonzero; callers must honor the exit status. Fault injection stays in excluded test fixtures.

Proof: [C7-R1 report](docs/research/trace-integrity/C7-R1/README.md), nine process tests inside the passing full suite, isolated three-platform exports and byte-identical numeric traces for all four aircraft against rc4. No aerodynamic parameters or integration equations changed.

## 2026-10-06 · C7-R2 — describe configured physics and recording state separately

Trace model names must follow loaded configuration, not aircraft IDs: removing the P-51 shaft/slipstream opt-ins must change its headers without renaming it. A stopped engine still has a configured propulsion model. Record auxiliary state when recording starts, including mid-flight, and state explicitly that step loads use the previous rigid-body state with updated auxiliaries.

Full-precision JSON remains diagnostic decimal data; a local round trip changed some servo values by about 1e-17. It is not a bit-exact checkpoint. Keep raw-file hashing and replay guarantees in DATA-3 and H8/H9. Proof: 128 metadata checks, 11 trace process tests, full suite, desktop exports and unchanged numeric rows for all four aircraft ([report](docs/research/trace-integrity/C7-R2/README.md)).

## 2026-10-06 · D1-R2 — validate tables before converting their numbers

Casting before validation allowed the shaft table to accept numeric strings and bypass kind/source checks; in-memory NaN power and infinite final RPM also passed the complete loader. Reusing `_xy_table` closes these gaps while preserving the shaft-specific positive RPM/power rule and exact valid values. Check a unit’s type before comparing it to text: numeric/list units can raise GDScript operand errors instead of producing a validation result.

Test failure at the session boundary too: invalid initial data must stay unflyable, while a rejected reload must retain the current model, trim, auxiliaries and clock. Proof: 117 checks, full suite, five before/after probes and unchanged four-aircraft numeric traces ([report](docs/research/aircraft-validation/D1-R2/README.md)).

## 2026-10-06 · DATA-1 — verify the whole generation chain before testing the app

A generator having `--check` does not protect CI until the workflow runs it. The P-51 needs separate source-to-geometry, geometry-to-runtime and physics/report derivation checks, in dependency order. Check the generated report too: the runtime JSON can be current while its published derivation is stale.

Run the exact workflow block in a fresh clone and mutate one valid file at a time. Five stale output/source cases passed the old freshness block and failed the repaired one without rewriting; restored files passed again. This proves reproducibility enforcement, not physical correctness ([DATA-1 evidence](docs/research/aircraft-validation/DATA-1/README.md)).

## 2026-10-06 · H8a — stage time needs a nonautonomous oracle

Autonomous flight goldens cannot reveal a solver that freezes time across RK stages. The coupled analytic system `x′ = v`, `v′ = x + t` exposes it: corrected RK4 converges at about 15× per halving, while the frozen-time mutation converges at about 2×. At 240 Hz their maximum component errors are `3.87e-12` and `2.45e-3`. Retain k1 caching and trace timing when fixing the stage clock.

A state inventory must include discrete engine mode, clock and configuration, not only the body array. Existing traces/goldens are not arbitrary mid-flight checkpoints. Keep H8 open until reset, failure rollback and replay cover the bounded state explicitly. Proof: [H8a report and evidence](docs/research/simulation-state/H8a/README.md), 22 targeted checks, three detected mutation failures and unchanged numeric traces for all four aircraft.

## 2026-10-07 · H6/H7 — test math routing and branch decisions separately

Replacing direct transcendental calls with built-in wrappers preserves the same-machine replay fingerprints. Enforce the boundary with an isolated bare-`sin` mutation. Adjacent-float `sin`/`atan2` perturbations stay below each golden budget/1000, but small state error alone does not prove the same decisions: a real aero-branch mutation changes replay signatures while staying below that threshold. Keep branch instrumentation in temporary copies ([H6](docs/research/simulation-state/H6/README.md), [H7](docs/research/simulation-state/H7/README.md)).

## 2026-10-07 · H8 — checkpoint the complete physics boundary

Engine mode, previous state, sampled auxiliaries, inputs, tick, stop condition and mass properties belong with the body state. A failed tick or late reload must restore them together. Capture a run's timestep so an external engine-rate change cannot reinterpret its committed clock. Restore validates before mutation, pauses and disables live input sampling; replay then feeds recorded inputs directly. This is a physics checkpoint, not a saved radio/menu session. Native Variant bytes preserve exact local state; JSON does not. Proof: 90 checks and exact continuation on all four aircraft ([H8](docs/research/simulation-state/H8/README.md)).

## 2026-10-07 · H9 — recording metadata must not control acceptance

Keep component scales and numerical tolerances in code. A recorded policy describes the run but cannot loosen comparison budgets. New v1 golden records can add auxiliary/mode checkpoints and platform/build stamps while old v1 files remain readable with unknown historical metadata. Validate integer-valued JSON modes before converting them: an Array of parsed floats does not compare equal to int64 modes. Proof: 42 checks, including every component mutation, clock-stamp rejection and legacy replay ([H9](docs/research/simulation-state/H9/README.md)).

## 2026-10-07 · H10 — a conditional abstraction can remain unimplemented

Current flight, trim and linearization consumers share Dynamics cleanly. No blocked consumer justifies another load-contributor interface. Remove measured redundant calculations inside the existing evaluators; reopen extraction only for named duplication or coupling that the shared path cannot handle ([H10](docs/research/simulation-state/H10/README.md)).

## 2026-10-07 · H11 — passive contact can still be inaccurate

The coupled gear frequency is a screen, not switched-contact acceptance. The bounded Stik-derived fixtures pass ring-down, energy and step-refinement checks through the measured ratio 0.291798. The much stiffer 0.583596 fixture remains passive but fails touchdown accuracy, even after another timestep halving for velocity/rate. Keep the current conservative loader limit; neither a larger universal bound nor an automatic substep count follows from this experiment. Eliminate free yaw with the inertia Schur complement: simply deleting the yaw row/column silently constrains it and underestimates some coupled frequencies. An analytic cross-inertia fixture catches that mistake. Actual P-51 has mode-screen evidence only; Extra/Avanti have no active gear configuration ([H11](docs/research/simulation-state/H11/README.md)).

## 2026-10-07 · H4/H5 — exact refactors can improve cost without meeting the budget

Reuse each surface's local flow and share washed/free tail work before introducing a cache or framework. Preserving product/sum order—including zero additions—kept 16 aircraft/regime fingerprints exact and passed 10,000 scalar/vector blend comparisons. Initial component profiles identified P-51 slipstream; gear evaluation was not the large isolated cost. Initial-state timings do not exactly explain an evolving 120-tick batch.

The owner confirmed this host as the target. Two sequential runs still put P-51 trim at 737–761, stall at 878–898 and ground at 502–510 µs/tick; median improvements do not close a 500 µs gate, and p95 overruns matter too. Keep the native experiment bounded to the measured hot path, then remeasure every regime. Label Extra/Avanti's gearless ground fixture honestly, and distinguish batch-average p95 from individual-tick latency ([H4/H5 evidence](docs/research/simulation-state/H4-H5/README.md)).

## 2026-10-07 · Gate P — a correct native hot path can still miss the full-tick budget

Measure through the language boundary, including live model decoding, then through complete simulation ticks. The bounded native tail-wash port passes 10,046 checks and preserves all 32 four-second flight fingerprints. It reduces powered P-51 trim cost 34–39% and stall cost 29–32%, but stall remains 595–619 µs/tick and batch-p95 overruns persist. Initial native stall profiles still spend about 69 µs in aero per load evaluation. An isolated component speedup does not accept a whole-aircraft migration; the next experiment must address that residual cost and evolving contact work ([Gate P evidence](docs/research/simulation-state/Gate-P/README.md)).

Treat boundary array arity as a contract: propulsion returns `[thrust, torque, advance ratio]`, while this kernel takes only the first two. Require a valid call to succeed before counting malformed-input refusals. Returning an empty array through Dynamics causes indexing errors before Simulation can reject it; six nonfinite sentinels preserve the load shape and trigger complete rollback. Keep the GDScript oracle and avoid stale model caches.

Ground and spin-like benchmarks stop the engine, so their timing variation is a control and does not establish powered takeoff/spin cost. Preserve that limitation in performance conclusions. Pin only required godot-cpp classes: an unrestricted generated archive exceeded this host's command-line limit; the OS/RefCounted feature profile builds with strict floating-point flags. Linux success does not establish Windows/macOS compatibility.

## 2026-10-07 · H12 — GDScript cost is calls and allocations, not arithmetic

Eight surfaces cost 65 µs because each paid for about 20 helper calls, 5 array allocations and 15 dictionary lookups. Reading values once and inlining in scalars cut that to ~21 µs, with byte-identical loads. Bit-exactness is cheap to keep when the old form is frozen verbatim in a test (including its helpers) and every product and sum keeps its order: `x + 0.0` is not a no-op (it turns `-0.0` into `+0.0`), but adding `+0.0` to a sum that starts at `+0.0` is, so zero-flow surfaces can be skipped. A single reassociated product failed 5,201 of 10,000 comparisons, so the oracle test is sensitive.

Profile the regime, not the component: the stall fixture recovers toward attached flow within a batch, so it gained only 6–21%, while spin gained 38–45%. Run unchanged-versus-changed timings back to back from a `git archive` copy of HEAD; on this shared host, two runs of identical code differed by up to 95 µs/tick. `app/test.sh` now takes about 10 minutes here, not ~45 s ([H12 evidence](docs/research/simulation-state/H12/README.md)).

## 2026-10-07 · SC-01 (desk research) — scenery costs come from the renderer's rules, not from triangle counts

Godot 4.7.2 Compatibility does no automatic 3D batching, so every surface of every visible prop is a draw call. A populated field is cheap only if props share one palette material and are merged per zone (`ImporterMesh.merge_importer_meshes` fixes winding under negative scale; `SurfaceTool.append_from` does not, and vertices without colours read the source as turning black once any merged mesh has colours). The depth buffer is 24-bit and reverse-Z gains nothing in OpenGL: with the 0.1 m near plane one depth step is about 2.4 m at 2 km and 15 m at 5 km, so distant moving landmarks flicker unless they stay close or the near plane rises. Visible size sets a floor: at 1280 × 720 and 50° FOV an object needs at least d/386 m to cover 2 px, so single flowers in a meadow are noise, not detail. Licenses moved under our feet: quaternius.com switched to QAL v1.0 on 2026-08-28, so "the pack page says CC0" is no longer evidence; the exact archive is ([reports 01–04](docs/research/scenery-investigations/01-prop-asset-sources.md), [SCENERY-PLAN](docs/SCENERY-PLAN.md)).

## 2026-10-07 · H13/H14 — bit-exact GDScript closes most of a native gap

Scalar, allocation-free GDScript took the P-51 slipstream from 86–89 to 37–38 µs per evaluation, against about 19 µs native. Together with H14's propulsion pass, P-51 trim/stall fell from 739–790 to 514–541 µs/tick, near the native-slipstream route's 456–520. Before accepting a native dependency and its three-platform build burden, exhaust bounded, oracle-checked GDScript work. Sharing a sub-expression between two oracle functions (H14's crossflow projection) stays byte-exact only when each value is still built by the same expression; keep `+0.0` additions and write NaN-sensitive tests in the oracle's form (`not x < limit`).

Two parallel `app/test.sh` runs of the same project share `user://` (Godot derives it from the project name), so a UI test's fixed settings file raced and failed spuriously. Run concurrent suites with separate `XDG_DATA_HOME` folders. A suite started before an edit loads the edited scripts in later stages; stop it and rerun rather than citing a mixed run. Seed the coverage floor of an oracle test from a measured run, not a guess ([H13](docs/research/simulation-state/H13/README.md), [H14](docs/research/simulation-state/H14/README.md)).

## 2026-10-07 · H15 — profile the whole tick before naming the next target

The planned H15 target (step bookkeeping) dissolved under measurement: it was about 20 safety checks of about 1 µs each, while attached-flow aero plus air data cost 32–39 µs per evaluation in every aircraft's normal flight. Retargeting H15 cut fleet trim ticks about 20% and brought every fixture under 500 µs/tick at the median. Wrap the session's Callables with timers for a step anatomy first, then micro-profile the pieces; verify any apparent overhead gap by timing the same calls in sequence, since identical P-51 `Dynamics.loads` calls varied from 90 to 107 µs between runs. A wind-free path still needs oracle cases with wind, because WIND-PLAN will use it ([H15](docs/research/simulation-state/H15/README.md)).

## 2026-10-07 · D1-R3 — judge ground support where gravity acts

A support check in body axes is wrong for a taildragger: the P-51 rests 13.9° nose-up, and projecting its CG along body z instead of the resting facet's normal misstates the margin by 94 mm (0.160 vs 0.254 m). Rest is on a lower facet of the contacts' convex hull; measure the margin to the hull edges of the whole coplanar facet, because a centred CG on a square layout sits on both diagonals and a per-triangle test reports zero. The new test caught a sign error in the below-the-wheels case before it shipped ([D1-R3](docs/research/aircraft-validation/D1-R3/README.md)).

## 2026-10-07 · SC-01 (probe) — measure the renderer before writing scenery rules

Three rules from the desk research changed once they were measured in the real renderer ([SC-01 evidence](docs/research/scenery-implementation/SC-01/README.md)):
- **Merging:** `ImporterMesh.merge_importer_meshes` was preferred on paper for its winding fix, but it relit mirrored cars (3,278 px), while `SurfaceTool.append_from` per material reproduced the separate render exactly. With one shared material, 40 cars went from 220 draws to 1. Merged zones lose per-object culling, so a narrow view cost more merged (78 draws) than separate (32): merge per small cell.
- **Depth:** the d²/(near·2²⁴) formula predicted a 15 m depth step at 5 km, but a turbine with a 6 m gap rendered clean there.
- **Shadow quads:** a 2 cm lift held up to 100 m camera height, so the proposed "lift ∝ d²" would have floated shadows by up to 0.3 m.

The probe also found a bug that no landscape check had caught: the 40 km ground is two triangles, and in 4 of 12 raised views the 3 cm runway vanished under it. Splitting the plane 10 × 10 fixed it. Fixed review views can pass while a nearby view fails, so sweep many views. Two practical notes: diagnose an odd frame by checking which camera is active and the object counts before suspecting timing, and render masks for every jittered frame, because masks from the first frame produced false "flicker". 601 PNGs repeated byte for byte across two runs from fresh `git archive` copies.

## 2026-10-07 · E3b1 — stiction anchors: release on the elastic force, share by load

A stuck tyre must break free on its sustained (elastic) load, not on spring plus damper: with the numerical damper included, a thrust-step transient freed a main wheel at 73% of its static load. Give each wheel a spring proportional to its static load share (the CG's barycentric weight on the D1-R3 resting facet), so all wheels reach their hold together; equal springs let the light nose wheel saturate first and cascade. Do not pre-load a re-stuck anchor to make the force continuous: it creates energy (about 1.3 mJ per re-stick, more than the kinetic energy at that speed). The real breakaway (3.1 N) is below the "all wheels at once" sum (3.5 N) because thrust above the ground unloads the mains. Test against an independent quasi-static balance, not the ideal sum. Five mutations, including keeping anchors on airborne wheels and dropping the in-stage clamp, needed their own checks before they were caught ([E3b1](docs/research/ground-contact/E3b1/README.md)).

The H7 checker instruments `ground_contact.gd` and `golden_flights.gd` by unique source text and injects `const Ground`. Keep instrumented lines unique (comment duplicates) and avoid that constant name in instrumented files. Extending aux is a contract change for every consumer: the trace header's `recording_start_aux` follows the four trace columns, while H8 checkpoints carry the full layout; only the full suite found all three consumers.

## 2026-10-07 · E3b2 — solve the start, and state acceptance as the physics

Settling a runway start by simulation slips (E3b1: 13.7 mm at an instant engine start); solving it does not. Solve the engine-off rest pose first, place the anchors there, then solve the idling pose with the anchors fixed: the lean onto the anchors is T/Σk at every wheel and there is no internal stress. The roadmap's "ΣN = m·g ± 0.1 %" was a level-thrust simplification: the idle thrust moves load to the nose, the Stik rests 1.6° nose-down and the tilted thrust adds 0.26 %. Test the exact balance (ΣN = m·g + T·sin θ) and say so. Measure anchor deflection at the wheels, not at the CG: the CG also moves with the extra pitch ([E3b2](docs/research/ground-contact/E3b2/README.md)).

## 2026-10-07 · SC-02…SC-24 (scenery v1) — the expensive part of a populated field is everything but the geometry

The scenery is built from procedural props and a few baked CC0 models, all merged per 40 m cell into one vertex-coloured surface. It costs +8 to +30 draws and +42 to +65 k primitives in the pilot's views, with byte-identical captures and identical trace rows ([SCENERY-PLAN](docs/SCENERY-PLAN.md), [SC-03](docs/research/scenery-implementation/SC-03/README.md)). Lessons:

**Rendering (Compatibility 4.7.2):**
- **Vertex colours arrive linearised.** A vertex colour renders exactly like the same albedo colour whatever `vertex_color_is_srgb` says, so a custom shader must use `COLOR` as is. Converting it again darkened the flowers and the flag.
- **A MultiMesh without per-instance colours hands the shader a vertex `COLOR` with alpha 0.** Flower leaves marked by alpha took the petal colour. `use_colors = true` with white instance colours fixes it (measured: 0 → 382 green pixels).

**Cost:**
- **Live aircraft builds are too heavy for scenery.** Four parked aircraft through the model builders cost ~550 ms per field load, ~120 k triangles and 72 surfaces. Baking them offline with Godot's own meshoptimizer LODs gives 2.1–3.8 k triangles each, merged into the shelter's cell.
- **LOD generation needs an indexed mesh.** A `SurfaceTool.append_from` merge is a plain triangle list: index it (positions and UVs only) before `generate_lods`. Pick the LOD closest to the target, not the first one above it.
- **Build time hides in GDScript loops.** Expanding baked models dominated, until the JSON arrays were turned into packed arrays first and the per-triangle allocations removed.

**Look:**
- **Pointy low-poly blobs read as spikes;** jittered ellipsoids with lighter tops read as crowns and hedges.
- **Flowers sprinkled evenly read as confetti;** clustered patches read as a meadow.
- **Landmarks only matter where the treeline leaves the sky open.** Rebuilding the L6b skyline from its own tree heights put the farmstead, village, turbines and pylons where the pilot sees them. The first pylon sites were hidden.

**Process:**
- **Never edit visuals while a long capture run is in flight.** The L6c run mixed old and new flower colours and failed its own background check.

## 2026-10-07 · E3b3 — explain a reference gap before widening a band

A 1-D point-mass integral of the model's own forces matched the 6-DOF takeoff roll within 0.17 % at the rest attitude, but the gap grew to 2.1 % by 20 m. Rather than widen the band, drive the same integral with the 6-DOF's recorded pitch: it then matched within 0.07 %, so the gap was rotation (more lift, less rolling resistance), not ground coupling. That attitude-matched check is also the sensitive one: a 10 % rolling-resistance error moved V by only 0.35 %, inside the rest-attitude bands but outside the 0.2 % matched band. Size every band from a mutation it must catch ([E3b3](docs/research/ground-contact/E3b3/README.md)).

## 2026-10-07 · D11d — fix the cause the knowledge base named, and expect it to unmask the next defect

The strip model's roll over-damping and lift-slope bump came from missing induced flow and a whole-airplane lift slope per strip, as the knowledge base said, not from strip count. A Weissinger map E = (I + a0·K)⁻¹ on the existing 3 strips per side, with a0 and per-strip CL0 solved for consistency with the oracle, brought Clp from ×1.73 to ×1.12 and CLα from ×1.34 to ×0.98. Write the kernel twice (GDScript and an independent Python script) and compare both with the knowledge base's VLM before trusting it; check the theory limit you actually implement (Weissinger meets Prandtl only at high aspect ratio). Removing the lift-slope bump made the 10 m/s short period less damped (ζ 0.61 → 0.47): it had been masking the tail's Cmq defect. Pin that as E0a2's known defect instead of hiding it. Prove a golden change is the intended one by replaying with the new term switched off (all four exact) before re-recording ([D11d](docs/research/aero-consistency/D11d/README.md)).

## 2026-10-07 · SC-25 — a scripted scene beats ad-hoc screenshots for spotting change

The runway scenario captures one fixed takeoff (threshold start in static equilibrium, scripted pilot, 240 Hz ticks) from five cameras at 12 instants, with a state row per frame ([SC-25](docs/research/scenery-implementation/SC-25/README.md)). Lessons:
- **The useful verdict separates physics from pixels.** Comparing each frame's state as well as its image tells *physics changed* from *visual-only change*. `--scenery=off` changed 48 of 51 frames with the physics identical.
- **Sync is cheap to assert once the manifest has the numbers:** `sim_clock` = t, frames on ticks, propeller angle = ∫ rpm dt, one state for all cameras, shadow under the airplane on the ground.
- **The scripted pilot belongs in its own pure function** so `app/test.sh` can fly it headless. A physics change that breaks the scene then fails the tests, not only the captures.
- **Full frames cost ~50 MB per run,** so history keeps manifests and filmstrips and only the last two runs keep every frame.
- **GDScript's `%` format has no `%e`.** It printed an engine `ERROR` that would fail `app/test.sh`.

## 2026-10-07 · E0a2a — split a lumped coefficient by what physically drives each part

The tail's "effective" slope a_t·η·(1 − dε/dα) was right for the free stream and wrong for pitch rate and elevator, and a hand factor (1.174) patched the elevator. Deriving the free slope, τ and incidence from the existing data kept static lift identical (6.5e-16) while pitch damping rose from 0.28× to 0.64× the oracle, the blend drag bump fell from 20 % to 5 %, and the hand factor became a checkable flap effectiveness (0.64 vs 0.55 from the elevator chord). Drive downwash from the wing's actual lift, not α, so it collapses at the stall. A check that recomputes the expected quantity from the same input can pass a broken implementation: measure the output the implementation produces (the tail angle from its lift) ([E0a2a](docs/research/aero-consistency/E0a2a/README.md)). A shell `cmd | tail && next` hides cmd's failure; check each step's status.

## 2026-10-07 · E0a2b — measure a dynamic derivative with the real code, and know your filter's exact response

A lag held per tick in `pre_step` keeps loads pure and checkpoints exact; it reproduces Cmα̇ with a −dt/(2τ) bias (4 % at 240 Hz) that halves with the tick. Measure the dynamic derivative through the real code with a forced plunge (α oscillating, q = 0) and project on cos(ωt) over an exact whole number of ticks per period: a rounded period leaked the large Cmα·α term into the quadrature and gave a 17 % error. Compare with the filter's exact response, Cmα̇/(1 + (ωτ)²), not its low-frequency limit. Test the path the simulator runs (`FlightSession._loads`), not only the function you changed: a mutation removing the lag from the session survived a test that called the loads directly. When the remaining gap is to a borrowed coefficient from another airplane, accept against the airplane's own geometry and hand the coefficient's source to DATA ([E0a2b](docs/research/aero-consistency/E0a2b/README.md)).

## 2026-10-07 · D11f — use an invariant of the data before changing the model

The fin's yaw-rate damping must equal −2(l_v/b)·Cnβ_fin of the same fin; the local model met it within 1.3 %, so the ×0.72 gap to the oracle was the borrowed Cnr, not the fin. An independent Weissinger solution under yaw rate showed the wing's yaw damping is profile drag (−CD0/3), not the CL² term remembered from handbooks: check a remembered formula against a computation before designing to it. Check derived numbers for physical bounds before using them: a coarse 6-strip induced-drag estimate gave span efficiency 1.15, impossible for a planar wing; 40 strips per side gave 1.0. After D11d, E0a2 and D11f every remaining blend gap traces to borrowed 25e data, so the next move is one owner decision on the data source, not more model work ([D11f](docs/research/aero-consistency/D11f/README.md), [brief](docs/research/aero-consistency/oracle-data-decision.md)).

## 2026-10-07 · D11g — at RC scale the tail's delay is a state, not a derivative

Replacing the borrowed Cmq with the Stik's static value only works if the downwash lag acts in the oracle too; otherwise normal flight loses a third of its pitch damping. Give every consumer the same lag: the loads (one increment, zero when settled, so trim and static solves stay byte-identical) and the flight-mode linearisation (a ninth state). At 15 m/s the wake delay is 51 ms against a 9 rad/s short period (ωτ ≈ 0.46), so a lumped Cmα̇ is not quasi-steady: the lag-state linear model predicted the nonlinear flight's pitch response within 1 %, a lumped Cmα̇ missed by 30 %. Prove a linearisation in the time domain against the real integrator, not only by its eigenvalues. Derive replaced data with a generator and pin it with a test that recomputes it (0.5 %), so a later geometry change cannot leave stale numbers. Measure every derivative the change could touch, not only the ones in question: the probe found the borrowed Cnp has the opposite sign of the local one (D11h). Closed-loop test pilots and marginal scenarios break on honest physics changes: the slow-flight PD pilot stalled the wing dynamically once pitch damping fell, and an idle figure-eight had kept only 0.45 mm of wheel compression. Run the old and new physics through the same fixture change and keep it only if both agree (pilot pitch-rate damping: both stall at 9.68 m/s), and make margins explicit. A fixture that rebuilds sampled state by hand (a 4-entry aux) silently drops new state: build it from the session's own layout ([D11g](docs/research/aero-consistency/D11g/README.md)).

## 2026-10-07 · E1b — make a contact law continuous where it touches, identical where it rests

Ramping the gear damping in from touchdown removed the force step and cut the refinement error through touchdown 2.5–26×, while every state beyond the ramp stayed byte-identical, so no rest, taxi or takeoff test moved. Where a law changes slope matters as much as whether it is continuous: the first ramp ended exactly at the static compression, so every oscillation about rest crossed its kink, and H11's ring-down lost its fourth order. End the ramp well below the operating point and join it C¹. Pin the design intent with an independent measurement (settle by a drop, then compare with the onset), not with the constant that defines it: a mutation moving the ramp back to rest survived until then. Test fixtures that rescale stiffness must rescale every quantity derived from it ([E1b](docs/research/ground-contact/E1b/README.md)).
