# Branch integration — 2026-10-10

**Status: software verification passed; both branch histories preserved.**

## Scope

The clean working tree started on `main` at `e39259e`. After fetching and pruning `origin`, the only other remote branch was `work/pt2-trial-preparation` at `7267b26`: 25 branch-only commits and 5 main-only commits. The merge preserves both histories and the committed research and evidence.

## Conflict decisions

- Preserve wind, atmosphere, electric propulsion and the TOD visual timeline/checkpoint work from the incoming branch.
- Preserve field-world composition, night lighting, moon/stars and progressing evening choices from main.
- Keep one world composer. Its optional scene-local lighting snapshot clears prior field-world flow and takes precedence over global lighting state. An empty snapshot retains the field-world route.
- Keep both Home time controls and both original UI test suites; selecting a control clears the competing selection.
- The TOD checkpoint format cannot represent field-world moon/night lighting or flow. Those flights keep their original flight controls; TOD checkpoint/paused-edit operations require a default or explicitly configured TOD flight.
- Interpret `--date` through the field-world route when paired with `--time` or `--time_of_day`; the TOD route retains `--time-of-day`, `--lighting` and `--lighting-config`.

## Verification

Native Windows import and the original FW and TOD UI suites passed. `test_world_flow.gd` passed all 25 checks, including switching from a progressing field-world scene to a solar snapshot. The FW UI test exposed a backdrop-order regression after replacing Home; moving the replacement to child index 0 restores the menu order.

Four native OpenGL captures were visually inspected: [Home](branch-integration-2026-10-10/home.png), [default daylight](branch-integration-2026-10-10/day.png), [field-world night](branch-integration-2026-10-10/world-night.png), and [TOD solar noon](branch-integration-2026-10-10/solar-noon.png). The daylight and field-world night PNGs are byte-identical to the same captures from a detached `e39259e` worktree on the same adapter and renderer. All captures exited 0 without script/shader errors; [capture identity and hashes](branch-integration-2026-10-10/captures.json) record their limits.

Reproduce the flight captures with the Windows console executable from `.tools`, `--path app --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 -- --capture --scripted --inspect --out=<output.png>`, adding the selection arguments in the manifest. Home uses `--script res://tests/capture_ui.gd -- --out=<output.png> --lang=en --screen=home` instead.

`bash research/test-tools.sh` passed all 12 offline suites (exit 0). `bash app/test.sh` passed in a clean Linux checkout with Godot 4.7.2-stable (exit 0): all 344 scripts parsed, all 174 functional GDScript suites completed, and every subsequent acceptance gate passed. This includes aircraft/model contracts, CLI/replay checks, four 720-tick trimmed flights, matching complete-state hashes at 30/60/144 fps, and E5a/E5b contact checks (E5b: 125 checks, 0 failures). The Linux executable archive was verified by the pinned SHA-512 in `app/get-godot.sh`. Windows shell files use CRLF, so the test checkout uses `core.autocrlf=false`.

The UI help test passed with a nonfatal ObjectDB-leak warning at process exit.

The verified application subtree is `963e2db73d5404b99301708d2192a93aadb2804b`; subsequent changes only add documentation and captured evidence. [Verification summary](branch-integration-2026-10-10/verification.json).

Headless checks establish software behavior and regression protection; they do not establish pilot acceptance or target-GPU visual quality.
