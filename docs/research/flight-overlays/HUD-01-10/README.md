# HUD-01…10 flight overlays: evidence

Date: 2026-10-13. Committed as b0b0347 (base 69a7b5e). Machine: development VM, Godot 4.7.2, headless (no GPU). Scope: software behaviour and cost on this VM; no pilot reading and no target-hardware timing. Plan and current behaviour: [flight overlays plan](../../../plans/flight-overlays.md).

## Tests

| Test | Checks | What it proves |
| --- | --- | --- |
| `app/tests/test_overlay_units.gd` | 23 | Exact mph/ft factors, ft/min, language rule, rounding, no "−0.0", unknown value shown as "–" |
| `app/tests/test_overlay_telemetry.gd` | 36 | Level flight; 30° climb (vertical speed V·sin 30°, from world vertical); 60° level turn n = 2.0 from body loads; AGL over terrain; wind bearing and arrow per view heading; FAR distance (Stik ≈ 348.9 m); one fixture per warning, order, no STALL without a stall angle or on the wheels |
| `app/tests/test_overlay_manager.gd` | 61 | Settings validation and presets; Mode 1/2 stick and trim layout; contrast ≥ 4.5:1 over white and black sky; `[hud]` round trip and per-key fallback; a real mouse click on an × hides only that overlay, takes no focus, and a flight key still arrives; H/F3 cycles; warnings hide when closed or empty; no overlap at 1280×720 and 1920×1080 (Pilot, Full; Spanish with three warnings); the Pause dialog drives the manager and closes on Esc; a real flight scene (Home route) shows live values, H and F3 work, a menu hides the overlays |
| `app/tests/test_controls_reference.gd` | existing | H and F3 listed for the handled keys |

Shared UI consequences: the pause menu gains **Flight overlays** after Help (Home route only), so `test_ui_pause` and `test_ui_runway` reach End with five Down presses instead of four. H and F3 share one Help row ("Overlay preset · developer overlays") so the English and Spanish Help pages keep fitting 600 px (`test_ui_help`, `test_ui_atmosphere`); two separate rows measured 616 px.

## Trace identity

3 s headless traces, `--hud=legacy` versus `--hud=overlays`, Ugly Stik and Extra 300S: identical except the `# created_utc` header line (722 data rows each). Command, from `app/`:

```
"$(./get-godot.sh)" --headless --path . --audio-driver Dummy -- [--aircraft=gp-extra-300s-60] --hud=<mode> --trace=<file> --t=3
cmp <(grep -v '^# created_utc' legacy.csv) <(grep -v '^# created_utc' overlays.csv)
```

`--hud=fancy` is refused with exit code 31 (ERR_INVALID_PARAMETER).

## Cost

[`research/flight-overlays/bench_overlays.gd`](../../../../research/flight-overlays/bench_overlays.gd), 1200 frames per preset, live flight scene:

| Preset | Mean per frame | p95 | 10 Hz refresh frames (median / max) |
| --- | --- | --- | --- |
| Pilot | 63 µs | 275 µs | 256 µs / 1517 µs |
| Full | 60 µs | 278 µs | 260 µs / 1060 µs |

Building the snapshot every frame cost 209 µs mean (373 µs p95); refreshing numbers at 10 Hz and only sticks per frame brought it to ≈ 60 µs. In isolation the snapshot costs ≈ 50 µs (terrain sample ≈ 10 µs) and an unchanged-text refresh ≈ 23 µs; the rest of a refresh frame is relayout of labels whose text changed. Wall-clock numbers are VM-specific.

## Full suite

`app/test.sh`: every GDScript test passes. `tests/test_shaft_cli.py` fails 2 of 10 (`test_corrupted_coupled_metadata_is_rejected`, `test_stage_weather_and_custom_air_traces`: "--trace aborted: recorder did not receive every tick"); a clean worktree of 69a7b5e, before any overlay change, fails the same two tests the same way, so they are pre-existing and outside this track. `test.sh` stops at that step; the steps after it (trimmed traces for the four aircraft, unknown-aircraft refusal, frame-time logger, fixed-step 30/60/144 fps identity, E0b5/E0b6p wash, E5a/E5b ground) were run separately from a copy of the script and pass.

## Rendered captures

`tests/capture_ui.gd --screen=flight --size=1280x720`, `--lang=en` and `--lang=es`, under Xvfb with software OpenGL (llvmpipe): the Pilot preset draws flight data bottom left, transmitter (Mode 2, keyboard, rates full) bottom right and wind (calm) top right, without overlap or clipping; English shows mph/ft, Spanish km/h/m. The capture route calls `_process(0.0)` after the last 10 Hz refresh, so its flight time reads 0:00 at t = 1.5 s; live flights refresh normally. Images are local outputs, not committed.

## Not covered

1920×1080 rendered capture, readability on a pilot's monitor, and validation of warning thresholds in real flight.
