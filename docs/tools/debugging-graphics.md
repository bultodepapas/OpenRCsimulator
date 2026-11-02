# Debugging graphics and rendering

Extends the [shared playbook](debugging.md). Tools: [graphics](graphics.md). [Back to the index](README.md).

## Reproduce

- Fix every input that changes pixels: `--t=<seconds>`, a camera (`--inspect`, `--look_az/--look_el/--look_alt`, `--alt`, `--autozoom=0`), `--time-of-day=`, `--weather=`, `--landscape=`; keep `OPENRC_SCENERY=off` unless scenery is the subject, and `LP_NUM_THREADS=1`.
- Render the view with a [single capture](graphics.md#single-capture). Repeat when determinism is in question: identical SHA-256 means the view is deterministic. A difference between repeats can reveal wall-clock animation, `TIME` in a shader or unordered placement.
- Interactively: `debugctl.py launch` (1920×1080 under Xvfb), reach the view with `fly`, `view name=chase`, `key`
  or `mouse`, then `screenshot max_width=960 format=jpg` and open the file ([debug bridge](../../tools/debug/README.md#quick-start)).
- If an area checker fails, rerun only that checker with a new `--out` and keep its `summary.json`.

## Observe

- Isolate layers with flags: `--hide_airplane`, `--hide_treeline`, `--shadow=off|vertical|sun`, `--scenery=off`, `--field-shadows=off`, `--scene_detail=<preset>`, `--engine_shadows`.
- Diff images: `compare_captures.py compare <before> <after>` ([compare captures](graphics.md#compare-captures)). Look at the PNGs as well; metrics miss small objects.
- Read the capture log line `saved … draw_calls=… primitives=…` for cost changes, and the engine log for `SHADER ERROR`.
- Performance: `--frametimes=<json> --frame-diagnostics` on real hardware ([frame diagnosis](graphics.md#frame-diagnosis)). Headless and llvmpipe runs cannot measure the GPU.
- Stutter while flying: `debugctl.py frames` lists hitches with what changed in that frame (pipeline compilations,
  objects, memory, physics catch-up); a long single frame breaks down with `launch --verbose` and `timeline`.
  Pipeline counters stay 0 on the VM's Compatibility renderer.
- The editor's script profiler and remote scene tree have runtime equivalents that need no display:
  `launch --script-profile` + `profile`, and `find`/`nodes`/`get` ([debug bridge](../../tools/debug/README.md#hunting-stutter-leaks-and-bugs-pt1h-r8)).

## Verify

1. Before/after captures of the same view differ only where intended (`compare_captures.py`). When determinism is at issue, repeat the new view and check byte identity.
2. Run the affected area checker with a new `--out` when one exists; otherwise inspect a matched capture of the view.
3. Follow the [verification scope](shared.md#verification-scope): run the full capture suite locally for broad visual integration or release preparation; CI runs the complete visual and app suites, including shader `TIME` and script parse checks.
4. Target-GPU appearance and performance need native evidence; label llvmpipe results as such.
