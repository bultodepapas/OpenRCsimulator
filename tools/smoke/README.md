# Smoke checks and native comparison tools

Checked 2026-10-20. [SMOKE](../../docs/SMOKE.md) owns the runtime/authoring contract; [SM-16–25](../../SMOKE_SYSTEM_MASTER_PLAN.md) owns execution and remaining acceptance. Keep overhaul receipts in [SM-16–23 evidence](../../docs/research/smoke-investigations/SM-16-23/README.md); earlier campaigns remain [historical evidence](../../docs/research/smoke-investigations/SM-00-09/README.md).

Use pinned Godot 4.7.2 and [developer setup](../../docs/TOOLS.md#developer-setup). Import resources on fresh checkouts. Use fresh output directories outside `app/`. Native captures require OpenGL and a display or Xvfb. Headless checks establish software behavior, not native plume quality or measured emissions.

## Contracts and focused checks

Regenerate customization outputs after changing authored bindings or a proved presentation source:

```sh
python research/aircraft-standardization/build_customization.py
python research/aircraft-standardization/build_customization.py --check
python -m unittest discover -s research/aircraft-standardization -p test_customization.py
```

The generator emits companion v3 with proof v2's ten closed text paths. Do not hand-edit its registry. Saved profiles with old pins remain readable but unavailable until explicitly migrated with their original companion; running the generator does not migrate saves.

On Windows, use the bounded runner so exit code zero cannot conceal engine errors:

```powershell
python tools/godot/run_checked.py --label smoke-bindings --timeout 60 -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script tests/test_smoke_bindings.gd
```

Use the same invocation for the relevant suites:

| Scope | Scripts under `app/tests/` |
| --- | --- |
| Profile schema, migration and authored transforms | `test_workshop_presentation.gd`, `test_aircraft_customization.gd`, `test_smoke_bindings.gd` |
| Source boundary, renderer and schedules | `test_smoke_system.gd`, `test_smoke_renderer_v2.gd`, `test_smoke_profiles.gd` |
| Package proof inventory and byte integrity | `test_presentation_sources.gd` |
| Workshop controls, preview and history | `test_workshop_smoke_controls.gd`, `test_workshop_customization.gd`, `test_workshop_smoke.gd`, `test_workshop_smoke_preview.gd` |
| Immutable storage, bundle and reviewed copy | `test_workshop_store.gd`, `test_workshop_bundle.gd`, `test_workshop_profile_transfer.gd` |
| AUX/controller and stock activity integration | `test_smoke_aux.gd`, `test_controller_aux_runtime.gd`, `test_controller_aux_setup.gd`, `test_engine_smoke.gd`, `test_avanti_smoke.gd` |

Linux LF checkouts use `GODOT="$(app/get-godot.sh)"` and `"$GODOT" --headless --path app --audio-driver Dummy --script res://tests/<script>.gd`. The repository runner is `app/test.sh`; use focused checks while editing, then required full/package gates. Fixture names do not establish physical validation. Fractional presented-time/source alignment is under integration and needs its own frame-rate/native receipt.

## Native stock/profile comparison

Use identical aircraft, flight/input/weather/camera and settings for smoke OFF, profile service ON and the retained legacy backend. Run uncaptured timing separately from screenshots/readbacks. Explicit examples for the default aircraft:

```sh
"$(app/get-godot.sh)" --path app --rendering-driver opengl3 --audio-driver Dummy -- --frametimes=/absolute/fresh/off.json --warmup=2 --t=4 --smoke=off --soundscape=off --scenery=off --birds=off --crash-effects=off
"$(app/get-godot.sh)" --path app --rendering-driver opengl3 --audio-driver Dummy -- --frametimes=/absolute/fresh/profile.json --warmup=2 --t=4 --smoke=on --smoke-pump=on --soundscape=off --scenery=off --birds=off --crash-effects=off
"$(app/get-godot.sh)" --path app --rendering-driver opengl3 --audio-driver Dummy -- --frametimes=/absolute/fresh/legacy.json --warmup=2 --t=4 --smoke-backend=legacy --smoke=on --smoke-pump=on --soundscape=off --scenery=off --birds=off --crash-effects=off
```

These short commands are diagnostic examples, not the master plan's longer acceptance workload. Alternate repeated conditions on an idle host; reject focus-paused/nonadvancing runs. Retain frame intervals, nodes/objects, draw calls, adapter/API, allocation/resolved rates and source/config identities. Frame caps and observer overhead limit inferred effect cost. Four emitters and at most 768 particles do not alone establish acceptable fill/sorting cost or scene pacing.

For Avanti tailpipe views:

```powershell
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --path app --rendering-driver opengl3 --audio-driver Dummy --script "$PWD/tools/smoke/capture_avanti.gd" -- --out="$PWD/tmp/avanti-smoke-review" --soundscape=off --scenery=off --birds=off
```

The harness captures the tailpipe, a trimmed flight trail and residuals after OFF. Record which profile/source revision it uses; historical Avanti captures do not qualify the new v2 allocation, motion or fractional timing. Explicit empty/all-disabled Workshop profiles must remain empty in Test fly. Source-bound show smoke additionally needs accepted source operation; independent show mounts have their own request policy.

## Retained legacy probes

The standalone Compatibility project remains a legacy comparison tool:

```sh
"$(app/get-godot.sh)" --path tools/smoke --rendering-driver opengl3 --audio-driver Dummy -- --out-dir=/absolute/fresh/probe
```

It compares point/swept births at 40 m/s and 30 FPS, seeded replay, pause, off-camera residuals and alpha ordering. Hard quads diagnose spacing, not appearance. JSON image hashes cover decoded pixels, not PNG file bytes. Windows uses the same arguments; unattended `Start-Process` calls use `-WindowStyle Hidden` and redirected logs.

The retained production legacy harness is:

```sh
"$(app/get-godot.sh)" --path app --rendering-driver opengl3 --audio-driver Dummy --script res://tests/capture_engine_smoke.gd -- --out=/absolute/fresh/legacy-flight --soundscape=off --scenery=off --birds=off --crash-effects=off
```

It presents eight real 240 Hz ticks per 30 Hz frame and separates actual flight from synthetic RPM/fast-pass/attitude fixtures. Layers isolate smoke/background/airplane. Synthetic RPM ramps cannot prove accepted cut/depletion/source-latch behavior. `--parse-only` checks harness arguments without GPU review. Original legacy allocation is 96 exhaust + 768 pump slots; it is not the new service's shared 768 limit.

Export/package reruns must retain source proofs and resolve runtime resources from the pack. Use an externally supplied harness with `--main-pack=/absolute/smoke.pck` where supported, and record the exact package/platform/backend. One backend's image repeatability is not cross-vendor equivalence. The generated mask remains existing MIT project code; no new texture asset is currently admitted. Any future downloaded asset needs license, byte digest and import settings in the closed presentation proof contract.
