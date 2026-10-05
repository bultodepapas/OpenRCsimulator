# Learnings

Practical lessons from **actually building and running** things, as opposed to reading about them (that is [RESEARCH.md](RESEARCH.md)). Each entry says what happened, what we learned, and what we now do differently. Newest first within each section. Evidence lives in the linked files.

## Process

- **Watch a test fail before trusting it.** In B4 we deliberately flipped one axis sign. Both test suites caught it (2 failures, non-zero exit) and passed again once it was restored. *Now:* every new known-answer test gets one deliberate break before it counts as proof. (2026-10-05)
- **Fix comparison criteria before seeing results.** The bake-off criteria and weights were written before the Godot build ([COMPARISON.md](prototypes/stage0/COMPARISON.md)). *Now:* any A-vs-B choice defines its scoring first. (2026-10-05)
- **Order bias is real.** The second build (Godot) took half the time of the first, largely because it reused the proven structure. *Now:* timing comparisons note which build went first; effort numbers alone are not decisive. (2026-10-05)
- **Confirm the reference object early.** The model was first built as a Hangar 9 Ultra Stick; the owner's plan images showed **Das Ugly Stik 60**. Because every number lived in one spec file, switching cost 30 s. *Now:* keep all numbers in one place per build, and ask for references before modeling. (2026-10-05)

## Rendering and evidence

- **The pilot view cannot verify geometry.** From the pilot's position the airplane is ~15 px wide at ~87 m (1280×720, 50° vertical FOV). That is realistic for RC, and a core readability problem. *Now:* every build has a close-up "inspect" capture alongside the pilot view. (2026-10-05)
- **Two independent builds can cross-check each other.** three.js and Godot each implement the NED → render conversion separately, and their captures show the same position, attitude and framing. *Now:* visual parity between builds is cheap extra evidence. (2026-10-05)
- **Software rendering is enough for captures, not for performance.** This machine has no GPU: Chromium uses SwiftShader and Godot uses Mesa llvmpipe (OpenGL 4.5). Both capture correctly in ~1.5 s. *Now:* performance is judged only on real hardware. (2026-10-05)
- **three.js captures need `preserveDrawingBuffer: true`** (capture mode only), and Chromium needs `--use-angle=swiftshader --enable-unsafe-swiftshader` when there is no GPU. (2026-10-05)

## Toolchain

- **TypeScript 7.0 + Vite 8 + Vitest 5 work together with no friction.** Type check 0.5 s, 8 tests 0.8 s. With TS 7's new defaults, `"types": []` keeps the type check focused. (2026-10-05)
- **three.js is one ~530 KB chunk (132 KB gzip).** Vite warns about chunks over 500 KB; harmless for now. (2026-10-05)

## Godot specifics

- **`Vector3` and `Basis` are 32-bit; GDScript `float` is 64-bit.** The scripted pose keeps positions as arrays of floats; tests at the render boundary need a 1e-6 tolerance. Real physics in Godot would need this discipline everywhere. (2026-10-05)
- **Tests need no add-on:** a script with `extends SceneTree`, run with `--headless --script`, can check and `quit(1)` on failure. 15 checks in 0.2 s. (2026-10-05)
- **Headless capture:** run under `xvfb-run` with `--rendering-driver opengl3`, then wait for `RenderingServer.frame_post_draw` twice before reading the viewport image. `--audio-driver Dummy` silences errors on machines without sound. (2026-10-05)
- **`BoxMesh` takes one material,** so a wing panel with a different underside is built as two half-thickness boxes. (2026-10-05)
- **A script-only project needs no editor and no import step.** Godot ran straight from text files; the pinned binary is 78 MB to download (146 MB unpacked) and is verified by SHA-512. (2026-10-05)

## CI

- **Run CI locally before pushing.** `act` with the cached `catthehacker/ubuntu:act-latest` image caught that a clean Ubuntu runner lacks the X11 libraries Godot needs (`libXcursor`, …); my machine happened to have them. *Now:* the workflow installs them explicitly. (2026-10-05)
- **Run `act` jobs one at a time** (`-j three`, `-j godot`). Running both in parallel failed with `archive/tar: write too long` while copying the repo, a local `act` race rather than a workflow bug. (2026-10-05)
- **Installing Playwright's Chromium dominates the three.js CI time** (1 min 32 s of ~2 min). Cache it if CI time starts to matter. (2026-10-05)

## Environment (this development VM)

- **Shared machine:** 9.6 GB RAM, no GPU, no sound card, no display (Xvfb available), Docker available. Other projects' services run here too. The assistant is not allowed to stop other workloads; the owner does that. (2026-10-05)
- **Third-party plan scans are reference material, not repo content.** Plans and scans (Jensen, RCM, Outerzone) are copyrighted; keep them out of the public repo, e.g. in a gitignored folder. (2026-10-05)
