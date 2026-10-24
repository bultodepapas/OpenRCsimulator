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

## Controls guide (2026-10-15, HUD-11-R2)

Added the default-open Control guide using the existing overlay frame, keyboard reference, effective controller bindings and bundled Kenney glyphs. It follows the selected flight device, preserves a manual tab choice during refresh, and returns to keyboard on disconnect. Named presets include it; custom visibility and closing still persist through the existing settings path. The Home latency marker moves beside it (x = 332, y = 180) to keep both readable.

Native Windows, Godot 4.7.2, Compatibility renderer on NVIDIA RTX 3090:

- `test_overlay_manager`: 90 checks pass, including default visibility, all keyboard reference entries, Mode 1 axes, remapped and unbound buttons, trigger/rate throttle instructions, disconnect, actual × click without focus capture, reopening, settings/dialog integration and English/Spanish layout at 720p (also English at 1080p).
- `test_controls_reference`, `test_controller_prompts` (137), `test_overlay_units` (29), `test_overlay_telemetry` (38), `test_latency_patch` (533), and `test_latency_patch_route` (5) pass.
- Real-flight 1280×720 Spanish viewport captures reviewed for keyboard, a simulated DualSense profile with remapped camera, and scrolled controller commands. Captures use fixture metadata, not a hardware-input acceptance claim. Scratch PNGs and capture harness are local outputs.

No physics, control mapping or simulation state changed. This focused verification does not rerun the full physics suite or close HUD-12 pilot acceptance.

## Close controls and camera marker (2026-10-24, HUD-03-R1)

Native Windows, Godot 4.7.2, Compatibility renderer. The live debug bridge reproduced the guide covering Diagnostics and the default white latency square. The square is the F6a raw-axis camera target: equality at zero is white, not a latency result. Keep that measurement behavior; default new profiles to off and expose the existing preference in Flight overlays. Its independent × saves opt-out, survives pause/resume and stops the hidden physics callback. Existing saved choices remain valid.

All nine overlay close targets are now 28×28 with a persistent background. Diagnostics reflows beside the guide and below warnings on layout/visibility changes. The overlay dialog follows manager changes, including external closes. The camera target has its own backplate, explanation and Spanish status labels; its 192×192 measurement square is unchanged. Compact wrapping keeps it clear of Battery at 720p.

Verification:

- `test_overlay_manager`: 164 checks pass, including real clicks on every overlay's × at 1920×1080, isolated visibility changes, keyboard focus, dialog synchronization, camera opt-in/save/close and pause persistence.
- `test_latency_patch`: 539 checks pass, including hidden-processing suspension, reopening, 240 same-tick samples and byte-identical checkpoint pairs. Route: 5 checks; CLI: 39 checks. The CLI run first exceeded 90 seconds on this shared host, then completed with a 240-second limit.
- `test_overlay_battery`: 123 checks pass, including English/Spanish Pilot and Full layouts with the optional marker at 1080p and 720p. `test_ui_home` and `test_ui_language` pass. Changed runtime/test scripts pass focused parse checks.
- Real Spanish flight at exactly 1920×1080: inspected separate guide/diagnostic headers, clicked Diagnostics closed, enabled the camera target through the dialog, clicked its ×, checked the saved preference and pause/resume, and relaunched with the same isolated profile to confirm it stayed off. No engine errors in the bridge logs. Captures and checked-runner output remain in ignored `tmp/`; no images added to the repository.

No solver or input mapping changed. The optimization removes hidden camera sampling and uses event-driven docking; no FPS improvement or full-suite/physical qualification is claimed. Long diagnostic text can still overlap other content in narrow Developer layouts.

## Player instruments (2026-10-24, HUD-13)

Implemented the [HUD-13 design](../../../plans/flight-overlays.md#hud-13--player-instruments-2026-10-24): four optional instruments for airspeed/flight maximum, height/flight, energy and wind. Player preset and individual switches sit separately from legacy diagnostics. Header dragging saves bounded normalized positions on release; lock, reset positions and each × use the existing preference path. Existing defaults and saved layouts retain their behavior. The maximum is sampled at 10 Hz, including while hidden, and clears on the session reset signal. Battery percentage reuses the radio-side sensor estimate; absent finite battery/fuel data remains explicitly unavailable.

Native Windows, Godot 4.7.2, Compatibility renderer:

- `test_player_widget_settings`: 17 checks pass for validation, malformed/unknown positions, unchanged legacy defaults and preference round-trip.
- `test_player_widgets`: 41 checks pass for values and missing data, fuel/battery fixtures, flight maxima and reset, 10 Hz cadence after rewind, actual multi-frame mouse drag, all four close/reopen buttons without focus capture, locking, dialog controls and viewport bounds at 1920×1080, 2560×1440, 3840×2160 and 1280×720.
- `test_overlay_manager`: 164 checks; `test_overlay_battery`: 123 checks; live battery flight: 12 checks; live fuel flight: 9 checks. UI language checks pass, including the Spanish catalog. Focused parser/import checks pass.
- Rendered 1920×1080 review in English and Spanish through the live debug bridge. The default Stik correctly shows energy unavailable; Turbo Lumber's finite pack shows estimated charge, voltage and current. Reviewed the four default corners, moved Speed through actual mouse motion, locked it and confirmed another drag did not move it. Restarted with the same isolated profile and verified the saved position and lock. Clicked Energy's ×, reopened through Use player layout, and reset positions through the dialog. Injected a sentinel display maximum and pressed the actual flight reset key to verify the main reset seam clears it. No engine errors in the bridge logs; rendered app stopped after verification.

Visual review found a clipped Spanish wind caption and repaired it to “DESDE”; the compass keeps its north marker. Multi-frame native dragging exposed an OS-mouse polling problem in the first draft: final dragging consumes GUI event coordinates and enables release handling only during the gesture. The regression test spans multiple frames.

Local checked-runner outputs and captures stay in ignored `tmp/player-*-checks/` and `tmp/debug-bridge/`; no images committed. Widgets skip hidden refreshes, bound the speed history to 120 samples and reuse the existing 10 Hz snapshot/sensor work. This is software/UI verification, not measured FPS improvement, full-suite qualification or physical validation. HUD-12 hardware/pilot acceptance remains open.

## Expanded instruments (2026-10-24, HUD-13-R1)

Added independent Fuel tank, Trims and Engine instruments, alongside the unchanged four-instrument Player preset. All instruments enables seven. Fuel uses accepted `fuel_remaining_kg`, `volume_ml`, `fill_fraction` and reserve flags; it does not substitute total aircraft mass or infer consumption/endurance. The copied trim snapshot preserves signed roll/pitch/yaw fractions of full travel. Engine RPM retains the existing fixed-wing snapshot semantics; throttle is the simulation command and flight load is the aircraft's g reading.

Appearance options persist under `[hud]`: Small/Normal/Large (85/100/120%), background opacity (80/94/100%) and compact density. Text remains opaque. Wind gains four compass labels, the speed trace marks its latest sample, fuel/throttle have ruled bars, and trims have centred signed tracks. The default trim position leaves space above bottom-centre flight notices. Scaling accounts for widget bounds during layout and dragging. One flight-owned MSDF font atlas keeps scaled text crisp; it copies the bundled font and is released with the manager, without changing the application's global font. This follows the [Godot Control scaling guidance](https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-property-scale).

Optimization: per-instrument keys exclude unrelated telemetry and skip unchanged values/redraws, including paused snapshots. Non-finite values normalize consistently in cache keys. The speed history uses a 120-entry circular buffer rather than shifting its contents on every update. These are bounded UI-work reductions; no FPS or physics-performance improvement is claimed.

Verification on native Windows with Godot 4.7.2:

- Player widgets: 72 checks pass. Coverage includes live draw callbacks proving unchanged fuel does not redraw, invalidation/reopen/missing values, ring ordering and immediate paused-reopen sampling, all seven × controls, real multi-frame scaled drag, compact sizing, appearance controls, shared MSDF font isolation, 1080p default separation, viewport bounds at 1080p/1440p/4K/720p and compact separation at 720p.
- Settings: 24 checks pass for legacy compatibility, new IDs/preset, malformed appearance values, finite bounds and preference round-trip. Overlay manager: 164; Battery: 123. Live fuel: 12, including the production fuel mass key, RPM and detached trims. UI-language checks pass (1742 Spanish catalog entries).
- Native 1920×1080 Spanish glow flight: reviewed normal and large/compact instruments, actual declining finite fuel, RPM and all three trims. Page Down and Bracket Right update the trim readings. Changed size/background/density through the real dialog; restarted the app with the same isolated profile and verified all three choices survived. Dragged the enlarged trim panel, clicked its ×, reopened its individual switch and reset positions. No engine errors; stopped the rendered app after checking.
- Visual review repaired a bottom-centre notice covering the rudder trim and raster-font blur at 120% scale. A first static font cache retained resources at exit; moving atlas ownership into the flight manager removed the leak. The checked widget suite passes teardown without resource/RID warnings.

Checked outputs stay in ignored `tmp/player-v2-*`; native captures/logs are under `tmp/debug-bridge/20261024-122803-47870/` and `20261024-123143-47870/`. No images added to Git. The full physics suite and target-hardware/pilot acceptance were not rerun; no solver or input mappings were changed.

## Instrument visual polish (2026-10-24, HUD-13-R2)

Refined the existing seven widgets with dark-blue panels, restrained amber accents, subtle static shadows/edge highlights, icon headers, a visible drag grip and rounded × targets. Secondary readings share an inset band with opposing alignment; units align with the large reading. Percentage rails gain graduations, the compass has finer bearings and a two-tone pointer, trims use diamond markers, and the speed chart has a shaded area with the newest sample aligned to “Now” at the right edge. Compact mode keeps the same hierarchy. The whole header now acts as the drag target, excluding its close button.

Reused seven official Lucide SVGs from release 1.61.0, commit `c29c276f16590cf017126671535ad8c792be64d8`; [provenance and complete license](../../../../app/assets/ui/instruments/LICENSE.txt) are bundled beside the assets. Only the stroke color was adapted to white for tinting. All three export presets explicitly include the license; SVGs import as ordinary offline resources. There is no new UI framework, blur shader, animation loop or per-frame callback. Existing data cache and bounded history remain in use; no measured performance improvement is claimed.

Verification, native Windows / Godot 4.7.2:

- `test_player_widgets`: 74 checks pass, including new offline-icon and zero-speed plot coverage, all previous seven-widget close/focus/drag/cache tests, 1080p layout separation, higher-resolution bounds and compact 720p layout. The checked runner reports no engine errors or leaked widget resources.
- UI-language checks pass with 1744 Spanish catalog entries. All seven SVGs and the license include in Linux/Windows/macOS presets were checked. The draft parsed before integration; asset imports completed.
- Native English and Spanish 1920×1080 captures reviewed, including English 120% compact layout and Spanish normal layout with finite fuel. Corrected initially low unit baselines and tight trim-header spacing. Dragging the actual grip moved Trims; clicking Energy's new × closed it and left keyboard focus free. The rendered app was stopped after each review.
- The first shared-tree import reported an unrelated ground-vehicle DLL copy failure while completing the asset import. The initial English world build also logged `rp_child` errors in `home_scene.gd`/`main.gd` and world teardown resource warnings. The later Spanish run had no engine errors or teardown warning reported by the bridge. These observations are separate from the clean focused widget checks; the full world/physics suite was not qualified here.

Captures stay in ignored `tmp/debug-bridge/20261024-124351-47870/` and `20261024-124725-47870/`; checked logs in `tmp/player-v3-*`. No review screenshots were added to the repository.

## Classic cockpit (2026-10-24, HUD-13-R3)

Added an optional five-instrument cockpit: true airspeed, artificial horizon, datum altimeter, true heading and
instantaneous vertical speed. The dedicated preset and individual switches coexist with the modern widgets;
default Pilot and the seven-widget All instruments preset retain their previous sets. All five reuse the existing
drag/close/lock/size/opacity/persistence behavior. Compact mode keeps their dial and numerical readout.

Research and applicability, reviewed 2026-10-24:

| Primary source | Finding and application |
| --- | --- |
| [jQuery Flight Indicators](https://github.com/sebmatton/jQuery-Flight-Indicators) | Provides the familiar attitude, heading, speed, altitude and vario group using SVG/web components; GPLv3. Used as a feature/layout reference, not bundled or ported. Its fixed scales and pressure API do not describe this simulator's sensor contracts. |
| [Open Aviation Components](https://github.com/Open-Aviation-Solutions/open-aviation-components), [Unusual Attitudes](https://open-aviation-solutions.github.io/open-aviation-components/unusual-attitudes/) | MPL-2.0 web training components. The attitude-centred instrument scan informs the prominent central horizon. Their teaching scenario and VSI lag are not imported into live telemetry. |
| [OpenKB Drone Godot](https://github.com/travisdetert/openkb-drone-godot) | Godot simulator paired with a separate web telemetry dashboard containing horizon/compass indicators. Reviewed for Godot integration context; adding its web/UDP stack is unnecessary for local widgets. |
| [Godot custom 2D drawing](https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html) | Draw commands are cached until invalidated. Static faces and moving indications use separate Controls, retaining native/offline operation and the existing 10 Hz update. |

No suitable drop-in native instrument package was established by this bounded search. Reused the already pinned
Lucide icons and the existing UI frame rather than adding another UI framework or raster assets. Native drawing
adapts graduations, missing-value behavior and units to the actual telemetry. The horizon clips a ground half-plane
to a disc, rotating opposite bank and shifting down for positive pitch; inverted flight exchanges sky and earth.
Altimeter hands wrap every 1,000/10,000 display units, with a full numeric altitude and separate AGL. TAS/VSI
needles saturate only at the visible scale and show an explicit overflow label; no artificial aircraft operating
arcs, pressure setting, magnetic correction or slip-ball reading is invented.

Verification on native Windows / Godot 4.7.2:

- `test_classic_instruments`: 58 checks, no failures or engine diagnostics. Includes actual draw callbacks for
  level, banked, inverted and vertical attitudes; datum/AGL distinction, north wrap, signed sink, negative altitude,
  imperial/SI conversion, over-range and unavailable indications, unchanged-data redraw suppression, all five
  close/reopen buttons, focus, drag persistence, lock and Spanish attitude terminology. All three sizes and both
  densities fit without overlap at 1080p; bounds also pass at 1440p/4K and the 720p fallback.
- Existing modern widgets: 74 checks; overlay manager: 167; settings/preferences: 25. UI-language checks pass.
  The full-scene manager/language runs retain the existing aircraft inertia warnings; focused widget runs are clean.
  New scripts parsed outside `app/` before integration. Editor import and whitespace checks pass.
- Native 1920×1080 Spanish review: selected Classic cockpit through the real preset control, dragged the horizon,
  closed heading with its ×, restarted with the same isolated profile and observed both saved changes. Reopened
  the cockpit preset and reset positions through the dialog. Reviewed normal and 120% compact layouts and live
  changing telemetry; no bridge engine errors. Rendered sessions were stopped after review.
- Visual review widened the metric speed label spacing, shortened Spanish dial titles, distinguished nose pitch
  from elevator trim, and raised the default horizon above the bottom-centre notice. The vario footer reports
  its scale range. Static faces invalidate for units/language; hidden widgets and unchanged samples do not add
  continuous redraw work. These are implementation bounds, not measured FPS gains.

Checked outputs remain in ignored `tmp/classic-cockpit/` and `tmp/classic-options-checks/`; native review captures
in `tmp/debug-bridge/20261024-130050-47870/`, `20261024-130410-47870/` and the final normal-layout review
`20261024-130901-47870/`. No images added to Git. Five default
dials can overlap at 720p; choose fewer or rearrange them there. No physics, pilot-input mapping or sensor model
changed. The full physics suite and target-hardware/pilot acceptance remain outside this UI verification.
