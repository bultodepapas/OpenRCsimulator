# Learnings

Practical lessons from **actually building and running** things, as opposed to reading about them (that is [RESEARCH.md](RESEARCH.md)). Each entry says what happened, what we learned, and what we now do differently. Newest first within each section. Evidence lives in the linked files.

## Process

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

- **Godot's `--fixed-fps N` makes frame-rate independence testable.** Running the same scripted flight with `--fixed-fps 30/60/144` and hashing the final state (SHA-256 of the `PackedFloat64Array` bytes) proves physics doesn't depend on rendering: identical hashes. A deliberate "step with the frame delta" bug changes the hashes at once. Runs must end at an exact tick (`stop_at_tick`), because at 144 fps a frame can contain two ticks. (2026-10-05)

- **Godot runtime script errors do not fail a run.** A bad format string printed `ERROR:` while the test reported success and exited 0. *Now:* `test.sh` fails if any `ERROR:` / `SCRIPT ERROR:` line appears, verified with a deliberate runtime error. Errors Godot can see at parse time are caught earlier by the parse check. (2026-10-05)
- **GDScript's `%` formatting has no `%e`;** use `String.num_scientific()`. (2026-10-05)
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

- **Run CI locally before pushing.** `act` with the cached `catthehacker/ubuntu:act-latest` image caught that a clean Ubuntu runner lacks the X11 libraries Godot needs (`libXcursor`, …); my machine happened to have them. *Now:* the workflow installs them explicitly. (2026-10-05)
- **Local `act` predicted GitHub correctly:** the first real GitHub run (both jobs) passed in 41 s, as the local run did. (2026-10-05)
- **Run `act` jobs one at a time** (`-j three`, `-j godot`). Running both in parallel failed with `archive/tar: write too long` while copying the repo, a local `act` race rather than a workflow bug. (2026-10-05)
- **Installing Playwright's Chromium dominates the three.js CI time** (1 min 32 s of ~2 min). Cache it if CI time starts to matter. (2026-10-05)

## Environment (this development VM)

- **Shared machine:** 9.6 GB RAM, no GPU, no sound card, no display (Xvfb available), Docker available. Other projects' services run here too. The assistant is not allowed to stop other workloads; the owner does that. (2026-10-05)
- **Third-party plan scans are reference material, not repo content.** Plans and scans (Jensen, RCM, Outerzone) are copyrighted; keep them out of the public repo, e.g. in a gitignored folder. (2026-10-05)
