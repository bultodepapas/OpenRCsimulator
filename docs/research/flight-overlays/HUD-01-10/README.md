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

Readability on a pilot's monitor and validation of warning thresholds in real flight. The 1080p capture was completed during merge integration below.

## HUD-03/06/11 merge integration (2026-10-13)

Integrated local `a48ca0f` and incoming `6e7c477`, checked in a fresh LF clone on WSL Ubuntu with Godot 4.7.2. The merged smoke feature already owns H, so overlay presets use F2; F3 still toggles developer overlays. Help, the dialog, Spanish text and the first-launch guide use the same binding. `test_overlay_manager` now has 64 checks, including real F2/H events proving that the overlay preset and Stik smoke pump are independent. The local Timber aircraft-route test also advances five pause-menu rows to End after HUD-06 adds its button; the complete corrected route passes.

The five textual conflicts retain both smoke/overlay decisions and translation sets, the local H12 byte-parity and D11j analytic Timber couple checks, and the local regime-test UID. AS-01's parameter register was regenerated through its source and contains 159 paths. Schema/register/migration checks, the Extra/P-51/Avanti generators, offline tool regressions and 632 local documentation links pass.

Three-second legacy/overlay traces are identical after removing only `created_utc` for all five catalog aircraft. Invalid `--hud` and `--rates` choices exit 31. Pilot-preset PNGs were rendered and visually checked in English and Spanish at 1280×720 and 1920×1080, with correct units and no clipping or overlap. The canonical capture runner accepts only 720p; the additional 1080p runs check successful engine exit, absence of engine errors, a fresh decodable PNG and its exact dimensions directly. This closes the rendered-capture part of HUD-11, not HUD-12's monitor/pilot acceptance.

Existing failures reproduced at premerge `a48ca0f`:

- `test_landscape_gravel` and `test_landscape_vegetation` expect 47 static cells; the accepted scenery builds 63.
- The two coupled-shaft CLI failures recorded above abort the P-51 hot/high trace.
- TT-07's strict generated-data freshness check passes on Windows/Python 3.11.9 and fails on Linux/Python 3.12.3: four numeric fields differ by at most 2.23e-16, identically before and after merging. The accepted data remains the runtime input; this check needs a separate cross-version generation repair.

All 484 application GDScript files parse. Across `app/test.sh` and explicit continuations after its existing failures, 238 of 240 GDScript tests pass; the two scenery counts above remain red. The corrected Timber menu test passes separately. All subsequent tool/model/CLI/trace/FPS/ground-contact stages pass except TT-07 freshness and the same two of ten shaft CLI tests. The suite therefore remains red for five pre-existing checks; the merge corrections introduce no remaining observed failure.

The complete capture workflow's image, repeatability, shader/cue, trace and runway-scenario checks pass. The initial L6c attempt stopped at case 45 after Godot saved a PNG and exited 141; the unmodified L6c tool rerendered all 64 cases successfully, then the runway scenario passed. The final capture inventory contains 46 primary images plus all required review manifests; it was published from the ordered successful initial capture log after rechecking every PNG/sidecar hash, and records the continuation and both log hashes. Software OpenGL captures do not close hardware readability or timing gates.

## Visual review and repairs (2026-10-13, HUD-11-R1)

Eleven software-OpenGL captures (Xvfb, llvmpipe) of real flights: Pilot/Full/Developer presets, gusty and crosswind weather, English and Spanish, 720p and 1080p, Mode 1 with deflected sticks and trims, all seven warnings, a first Home flight, and Pause → Flight overlays through the real app route. Scratch capture script, not committed. Findings and repairs:

| Finding | Repair | Proof |
| --- | --- | --- |
| Telemetry read "-0°" for small negative pitch/bank | `Units.angle()` signs the rounded value | 6 new cases in `test_overlay_units` (29 checks) |
| Wind box changed width at 10 Hz as a gust's updraft text came and went | Three fixed lines (speed, bearing, updraft) in a 150 px column | size equal with and without updraft |
| Five or more warnings reached the Wind box (≈ 780 px of chips) | Chips wrap in a 640 px centred flow | all seven Spanish chips wrap; no overlap at 720p |
| The pause dialog changed overlays the player could not see (hidden while paused) | `preview()`: overlays shown above the pause menu (layer 11) while the dialog is open; the suspended pause column hides, then returns before focus restores | Home → Fly → Pause → dialog route: layers, visibility, focus back on "Flight overlays" |
| The first-flight hint (top right) covered the Wind overlay and the warnings | Hint card at bottom centre | hint rect intersects no Pilot overlay on a real first flight |
| The default Home latency marker (centre right) covered Telemetry and the Transmitter title | `LatencyPatch.left_side` on overlay flights: top left at y = 120; legacy/CLI unchanged | marker rect intersects no Pilot overlay; F6a tests 533 + 5 + 26 checks pass |

`test_overlay_manager`: 77 checks. Developer-preset overlap with long diagnostic lines remains accepted. Full suite after the repairs: 239 of 241 GDScript tests pass (the two scenery-count tests above stay red) and all 30 later `test.sh` stages run, red only for the same two shaft-CLI cases.
