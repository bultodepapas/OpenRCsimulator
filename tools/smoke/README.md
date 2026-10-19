# Engine smoke tools

Checked 2026-10-19. [SMOKE](../../docs/SMOKE.md) owns current behavior and renderer limits; [SMOKE-PLAN](../../docs/SMOKE-PLAN.md) owns remaining qualification and proposed customization. These tools use pinned Godot 4.7.2 after [developer setup](../../docs/TOOLS.md#developer-setup). Use a Linux LF checkout for Bash examples and fresh output directories outside `app/` to preserve earlier reports. Rendered runs need OpenGL and a display or Xvfb.

## Headless checks

```bash
GODOT="$(app/get-godot.sh)"
"$GODOT" --headless --path app --audio-driver Dummy --script res://tests/test_smoke_aux.gd
"$GODOT" --headless --path app --audio-driver Dummy --script res://tests/test_engine_smoke.gd -- --soundscape=off
"$GODOT" --headless --path app --audio-driver Dummy --script res://tests/test_controller_aux_runtime.gd
"$GODOT" --headless --path app --audio-driver Dummy --script res://tests/test_controller_aux_setup.gd
"$GODOT" --headless --path app --audio-driver Dummy --script res://tests/capture_engine_smoke.gd -- --parse-only
```

`app/test.sh` discovers the four test suites. AUX uses fake device events and temporary profiles. The engine test includes real main-scene attachment, H/echo/reset, guided assignment and device-event routing; capture parsing does not run the GPU review. Native Windows uses the same arguments with `.tools/Godot_v4.7.2-stable_win64_console.exe` (`&` in PowerShell). Import resources first on a fresh checkout.

## Compatibility probe

```sh
"$(app/get-godot.sh)" --path tools/smoke --rendering-driver opengl3 --audio-driver Dummy -- --out-dir=/absolute/fresh/probe
```

On Windows use `.tools/Godot_v4.7.2-stable_win64_console.exe` with the same arguments. From PowerShell, start it with `Start-Process -WindowStyle Hidden` and redirect both logs when running unattended. The standalone project compares point and swept-box births at 40 m/s/30 FPS, then checks fixed-seed replay, pause, off-camera residual aging and alpha ordering. JSON hashes are decoded image-pixel hashes; PNG file hashes differ. The probe's hard quads demonstrate birth spacing, not smoke appearance.

## Production flight review

```sh
"$(app/get-godot.sh)" --path app --rendering-driver opengl3 --audio-driver Dummy \
  --script res://tests/capture_engine_smoke.gd -- --out=/absolute/fresh/flight --soundscape=off --scenery=off --birds=off --crash-effects=off
```

The harness presents each 30 FPS interval after eight actual 240 Hz physics ticks. It records real throttle/bank flight separately from synthetic RPM, fast-pass and attitude fixtures. Layers include combined view, smoke over background, background, airplane without smoke, and a smoke mask. Pause, OFF/residual/expiry, reset and live M5 gust cases have explicit checks. Startup/shutdown RPM ramps are synthetic fixtures, not proof of accepted combustion/source-latch integration. GPU repeatability applies only to the identified engine/backend/machine.

For a package check, export the `Windows` preset to a PCK, then run the same externally supplied review script with `--main-pack=/absolute/smoke.pck`; its production resources come from the pack. This is a resource/import/render check, not qualification of every desktop binary.

## Native timing

```sh
"$(app/get-godot.sh)" --path app --rendering-driver opengl3 --audio-driver Dummy -- \
  --frametimes=/absolute/off.json --warmup=2 --t=4 --smoke=off --soundscape=off --scenery=off --birds=off --crash-effects=off
```

Compare an alternating sequence with `--smoke=on`, then `--smoke=on --smoke-pump=on`, using the same scene/settings and an idle host. Reject a run that paused on focus loss or stopped advancing ticks. The report retains frame intervals, draw calls, objects/nodes, adapter/API and simulation scope. A frame-rate cap, other applications and observer overhead limit any inferred effect cost. [Recorded campaign](../../docs/research/smoke-investigations/SM-00-09/README.md).

All source and the runtime's synchronous 64² mask are original project code under the repository MIT license. No external artwork, plugin or new dependency is required.
