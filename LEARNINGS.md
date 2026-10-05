# Learnings

Practical lessons from **actually building and running** things, as opposed to reading about them (that is [RESEARCH.md](RESEARCH.md)). Each entry says what happened, what we learned, and what we now do differently. Newest first within each section. Evidence lives in the linked files.

## Process

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

- **Run CI locally before pushing.** `act` with the cached `catthehacker/ubuntu:act-latest` image caught that a clean Ubuntu runner lacks the X11 libraries Godot needs (`libXcursor`, …); my machine happened to have them. *Now:* the workflow installs them explicitly. (2026-10-05)
- **Local `act` predicted GitHub correctly:** the first real GitHub run (both jobs) passed in 41 s, as the local run did. (2026-10-05)
- **Run `act` jobs one at a time** (`-j three`, `-j godot`). Running both in parallel failed with `archive/tar: write too long` while copying the repo, a local `act` race rather than a workflow bug. (2026-10-05)
- **Installing Playwright's Chromium dominates the three.js CI time** (1 min 32 s of ~2 min). Cache it if CI time starts to matter. (2026-10-05)

## Environment (this development VM)

- **Shared machine:** 9.6 GB RAM, no GPU, no sound card, no display (Xvfb available), Docker available. Other projects' services run here too. The assistant is not allowed to stop other workloads; the owner does that. (2026-10-05)
- **Third-party plan scans are reference material, not repo content.** Plans and scans (Jensen, RCM, Outerzone) are copyrighted; keep them out of the public repo, e.g. in a gitignored folder. (2026-10-05)

## Aircraft modeling and reference inspection

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
