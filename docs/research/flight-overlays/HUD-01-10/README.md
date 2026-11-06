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

## Instrument finish (2026-10-24, HUD-13-R4)

Refined both widget families around a dark matte panel and restrained amber instrument markings. Header icons
have subtle surrounds; close buttons have clearer hover/pressed borders; the grip becomes a lock symbol when
positions are locked. Secondary readings use a darker recessed band. Modern speed traces gain faint time
divisions and a narrow line halo; wind has light reference axes; level rails have finer graduations and a top-edge
highlight. Classic instruments gain layered bezels, small recessed fasteners, faceted needles with shadows,
sharper hubs, 5° pitch-ladder subdivisions and framed 13 px numerical readouts. Existing free icons are reused.

Native review exposed a transient-height issue: initial text could grow a classic panel which never shrank to its
final content minimum. Classic panels now refit on minimum-size changes; the four outer normal dials were
confirmed at the same 286×385 size after initialization. This is event-driven layout work. Static face commands
remain cached, values keep their existing 10 Hz/cache behavior, and no animation loop, shader or asset was added.

Verification: the existing modern widget suite passes 74 checks and the classic suite passes 58, including actual
drawing, missing values, extreme attitudes, cache behavior, drag/close, scaled layouts and teardown. The classic
suite was repeated after the height fix. Logs under `tmp/widget-polish-r4/` contain no engine errors. Native
1920×1080 review covered modern, classic normal and 120% compact layouts, locked symbols, and the final aligned
classic row. Bridge logs were clean and both rendered sessions were stopped. Captures stay outside Git under
`tmp/debug-bridge/20261024-131416-47870/` and `20261024-131657-47870/`. Whitespace checks pass. No measured FPS
improvement or full physics-suite qualification is claimed for this presentation-only change.

## Widget efficiency and configuration UX (2026-10-24, HUD-13-R5)

The dialog now separates Modern, Classic, Appearance and Other overlays. Preset, Units, section tabs and Done
remain outside the scrolling page. Native TabBar navigation supports mouse/keyboard input; hidden page controls
lose focusability, restoring their original focus modes when shown. Switching away from a focused page returns
focus to the tab bar. Changing sections never writes settings. Checkbox synchronization uses silent setters and
handlers no longer duplicate the synchronous settings-change refresh. The clamped 900×800 target and short tab
labels fit all four Spanish tabs and all seven modern switches at 1080p; smaller windows scroll the active page.

Settings application returns early for identical validated values. Actual changes update only their affected
visibility, style, lock or layout work. Positions and appearance preserve the telemetry clock; units, stick mode
and newly visible instruments still invalidate readings immediately. Resize notifications coalesce into one
deferred full layout pass, and repeated content-fit requests share one deferred fit. The horizon reuses a 96-point
disc owned by its widget, avoiding construction/rotation of that circle on each redraw. The clipped result remains
identical. A draft static cache retained a GDScript resource at shutdown; the final instance-owned array passes
clean teardown and preserves flight lifetime ownership.

Evidence, native Windows / Godot 4.7.2:

- `test_widget_efficiency`: 18 checks. Controlled requests demonstrate 200 identical settings calls produce zero
  save events, layout passes or style changes; 12 resize notifications produce one full layout pass. Position
  changes save/reflow once without restyling; opacity updates backdrops without layout; presentation-only changes
  preserve telemetry cadence. Actual draw callbacks show static faces stay cached as attitude changes, and 100
  repeated paused samples do not redraw. Cached/fresh clipping agrees for level, vertical, inverted and banked
  cases, and clipping does not mutate the cached circle.
- Existing modern widgets: 74; classic instruments: 58; overlay manager/dialog: 178; battery overlays: 123;
  settings/preferences: 25. All pass. UI-language checks pass. Scene-level tests retain existing aircraft inertia
  warnings; the focused widget tests and retained checked-runner diagnostics are clean.
- Native 1080p Spanish review verified all four tabs, complete modern options without scrolling, classic preset
  selection, size changes, lock and focus return. Clicking the tab bar and pressing Right selected the next
  section. A real 1280×720 viewport retained the pinned choices and Done while scrolling the longer legacy
  section. No bridge engine errors; rendered sessions stopped after review.

Logs live in ignored `tmp/widget-efficiency-r5/`; captures in `tmp/debug-bridge/20261024-140049-47870/` and
`20261024-140416-47870/`. New test code parsed outside `app/` before integration. Whitespace checks pass. These
are measured reductions in UI work under controlled inputs, not an FPS or target-hardware performance claim;
no physics/input mapping changed and the full physics suite was not rerun.

## Player widget ideas from RC telemetry (2026-10-24, HUD-13 research)

Research recorded before HUD-13-R6: the implementation section below identifies delivered work; the remaining
concepts are proposals, not accepted performance claims. The aim is to add navigation, energy management and
training information beyond the existing modern and classic instruments.

Primary references reviewed:

- [INAV Lua Telemetry for EdgeTX/OpenTX](https://github.com/iNavFlight/OpenTX-Telemetry-Widget): pilot-relative
  orientation, radar, altitude history, flight extrema and selectable views. Its Lua runtime targets radios;
  it is a design reference, not a drop-in Godot dependency.
- [INAV OSD](https://inavflight.github.io/docs/next/core-features/osd/) and
  [HUD/home markers](https://inavflight.github.io/docs/next/advanced-features/osd-hud-and-craft-radar/): individually
  positioned elements and spatial navigation cues. These URLs describe the development documentation, not a
  promise that every released firmware/display supports each feature.
- [INAV energy estimates](https://inavflight.github.io/docs/next/core-features/battery/#remaining-flight-time-and-flight-distance-estimation):
  return estimates depend on configured capacity, cruise consumption/speed and optional wind compensation.
- [ArduPilot soaring](https://ardupilot.org/plane/docs/soaring-4_1.html): rising-air estimation and thermalling
  motivate a glider view. This does not establish thermal estimation or autonomous soaring in OpenRC.

Candidate designs, in recommended implementation order:

| Concept | Player use and visual treatment | Local data readiness / boundary |
| --- | --- | --- |
| Pilot radar | Compact compass disc with aircraft silhouette, pilot marker, range rings and a short trail; north-up or heading-up. Recover orientation during distant RC flight. | Existing position offsets and heading; expose horizontal offsets in the presentation snapshot. Label pilot and fixed launch point separately; a launch anchor needs explicit capture/reset. |
| Track and wind | Two distinct arrows for nose heading and ground track, with drift angle and signed head/crosswind. Makes wind correction visible. | Existing world velocity and wind; export ground course and suppress it near zero horizontal speed. Heading-relative crosswind is not runway-relative crosswind. |
| Cruise efficiency | Large consumption-per-distance reading, power and a short trend; compare steady cruise settings. | Shared battery sensor supplies sampled current, voltage, power and used mAh. Derive mAh/km or Wh/km with a low-speed guard and time-window averaging. Consumed Wh needs integration of sensor power; do not expose model-truth SOC. |
| Maneuver meter | Signed load-factor arc with session extrema, bank and angle of attack; useful for loops and pull-ups. | Existing body-z specific load and alpha. Label the measured axis; it is not total acceleration magnitude. Existing stall-blend thresholds are presentation references, not validated stall predictions. |
| Glider view | Large vario, altitude/sink history and optional audio; descent trend makes gliding practice easier. | Existing vertical speed and height support the first version. A ground glide ratio must be labelled explicitly and suppressed outside meaningful descent; it is not aerodynamic L/D. Total-energy compensation and thermal centering require separate work. |
| Approach aid | Runway diagram, lateral alignment, AGL and sink rate; optional touchdown recap. | AGL/sink exist. Selected runway geometry and verified touchdown/contact events must be audited before alignment or landing scores are offered. No fabricated ILS or forward terrain clearance. |
| Flight card | Small timer and flight extrema during flight, expandable recap after landing. | Reuse existing extrema and flight recording boundaries; define reset/end-of-flight events. Do not introduce a competing unbounded recorder. |
| FPV presentation | Optional sparse layout with peripheral speed/altitude tapes, horizon and home cue, leaving the centre readable. | Reuse instrument data. Spatial markers require the actual camera transform/FOV; aircraft heading alone is insufficient for chase or orbit cameras. |

Recommended first slice: pilot radar, track/wind and electric cruise efficiency. Keep endurance/return reserve
for a later, explicitly estimated mode with sufficient sampling and aircraft-specific assumptions. Fuel quantity
exists for finite fuel stores, but a generic fuel-flow/endurance signal is not currently exposed. USB controller
status does not provide RF RSSI, link quality, GPS satellite count or video latency; these should not be invented.

All candidates should inherit the existing drag header, close button, persistent placement, lock, units and size
controls. Offer purpose-based presets (RC navigation, glider, aerobatics, FPV) with individual opt-in switches.
Prefer one dominant reading and an expandable detail area over denser default panels. Preserve the current
shared sampling pipeline, bounded histories, cached static drawing and changed-value redraws; qualify new
layouts at 1080p first. New capability-dependent readings should state unavailable rather than show zero.

Local readiness was checked against `telemetry.gd`, `overlay_manager.gd` and `battery_sensors.gd`; no runtime
code or dependency changed for this research. Any reused code/assets require their existing license and
provenance review; no external code/assets were imported here.

## RC navigation instruments (2026-10-24, HUD-13-R6)

Implemented the first three research candidates as an opt-in RC navigation preset and a separate Navigation
settings page. `navigation_instrument.gd` inherits the player frame, drag/close signals, lock, normalized saved
positions, opacity, size and compact controls. Existing modern/classic presets and the Pilot default are unchanged.
The five settings tabs use a smaller, text-scale-aware font; large accessibility text retains native tab scrolling.
Existing bundled icons and native Godot drawing are reused; no external dependency or asset was imported.

Radar reads horizontal aircraft-minus-pilot N/E offsets, draws a north-up aircraft silhouette and pilot centre,
and selects a 1/2/5 range with edge clearance. Its trail is bounded to 60 relative position samples, sampled no
faster than twice per simulated second. The centre is the pilot, not a launch/home anchor. Wind & drift presents
signed ground-course-minus-heading, plus heading-relative head/tailwind and wind-to-left/right components.
Course becomes unavailable below 1 m/s; missing telemetry has a separate status.

Cruise efficiency integrates the existing battery sensor's sampled power/current and horizontal ground speed,
holding each prior sample over its interval. The estimate needs two seconds of contiguous samples at >=3 m/s,
uses at most ten seconds/120 intervals, and reports Wh/km or Wh/mi. Invalid power/speed, slower movement, time
rewind or a gap over one second resets it. Closing the widget stops/resets its estimator; temporary layer hiding
for a pause/menu preserves its window. Sensor validity is
checked even at identical paused timestamps; an invalid channel cannot leave a stale estimate. No true SOC,
remaining endurance or return reserve is used. Status distinguishes unavailable data, slow movement and warm-up.

The shared manager still samples at its existing 10 Hz cadence. Hidden widgets skip presentation work; diagram
faces cache static drawing. A 60-point consumption graph samples at 2 Hz; power footer changes do not redraw
the unchanged graph. Radar redraws skip repeated paused values. The simulation kernel, solver, controller
mapping and aircraft data are unchanged.

Checked-runner evidence in ignored `tmp/navigation-widgets/checks/`:

- New data tests: 27 checks, including hand-calculated N/E/wind signs, heading wrap, 360 W at 10 m/s = 10 Wh/km,
  sample discontinuities, invalid channels during pause, bounded history, and independence from model SOC.
- New widget tests: 57 checks, including metric/imperial conversion, pause/static drawing, graph invalidation,
  individual close/reopen, saved drag/lock behavior, reset/unavailable statuses and bounded histories. Preset
  separation is checked at 1080p across all size/density settings; viewport bounds at 1440p, 4K and fallback 720p.
- Existing telemetry 41, modern widgets 74, classic widgets 58, efficiency 18, settings 26, manager/dialog 183,
  and battery overlay 123: all pass, for 607 focused checks in total. UI-language checks pass with 1796 Spanish
  entries. Scene-level checks retain the existing aircraft inertia warnings.

An initial preset-cycle assertion expected the old seven-entry sequence and was updated for Navigation. A later
changed-value condition needed an explicit GDScript bool annotation; the final parse and focused checks pass.
These checks establish UI/software behavior, not physical validation or a whole-game FPS gain. The full physics
suite was not rerun for this presentation-only change.

Native Windows/Godot 4.7.2 review at 1920×1080 covered the Spanish Navigation page, all five visible tabs,
individual switches and normal/large layouts. Ugly Stick/ideal power showed an unavailable electric reading;
Turbo Lumber with its finite pack produced 1.7 Wh/km and 95 W after 4.47 simulated seconds. This is a runtime
sample, not a calibrated aircraft efficiency claim. Captures remain ignored under
`tmp/debug-bridge/20261024-142940-47870/shots/` (001 flight, 002 Navigation, 003 large/Appearance). Bridge logs
contained no engine errors and both rendered sessions were stopped. The menu review exposed an unwanted
efficiency reset on temporary layer hiding; the final code preserves it, with a dedicated passing regression.

## Training instruments (2026-10-24, HUD-13-R7)

Implemented three additional research candidates in the Training preset: maneuver load meter, glide monitor
and live flight summary. Settings remain opt-in, with three switches and a preset action below Navigation on
the existing page. The dialog target grows to 900×860, clamped to the viewport, so all six navigation/training
switches fit at 1080p/default text size in Spanish. Smaller windows scroll while keeping Preset, Units and Done
outside the scrolling area. Shared player frames supply drag, close, normalized persistence, lock and appearance.

`flight_metrics.gd` keeps only constant-size session aggregates: sampled signed body-axis load extrema,
maximum AGL and integrated horizontal ground distance. It samples at the manager's existing 10 Hz cadence
even when its widgets are closed. Repeated timestamps do not advance statistics; rewind/explicit reset clears
them. Distance holds the previous valid speed through intervals <=1 s, excludes discontinuities and marks
incomplete totals. Missing speed breaks continuity. No recorder, landing detector, physics callback or
aircraft-specific kernel branch was added. Flight time reuses simulation time and includes ground time.

The load arc spans -4…+8 g; overflow retains the actual number and labels the clipped scale. It is not a tested
airframe limit. Bank and AoA remain separate quantities. The glide ratio is instantaneous horizontal ground
speed divided by sink, with availability guards for speed >=3 m/s, throttle <=5%, bank magnitude <=20° and
sink >0.2 m/s. Powered, turning, slow, non-descending and missing-data cases suppress it. Labels/tooltips identify
the ground reference and avoid claims of aerodynamic L/D, energy compensation or thermal detection.

The glide graph retains at most 60 samples at 2 Hz, clears on unavailable/time-discontinuous data, and shares
cached static grid drawing. Foreground invalidation is separate from static faces; repeated paused samples
avoid redraw. Existing bundled icons and native Godot drawing are reused; no downloaded dependency/assets.

Checked-runner logs in ignored `tmp/training-widgets/checks/`:

- `test_flight_metrics`: 29 checks. Analytic distance/glide ratio, pause/rewind/reset, invalid/missing samples,
  partial-distance marking, late sampling, negative-g extrema and threshold/status priorities.
- `test_training_widgets`: 56 checks. Hidden-widget statistics, units, glide guards, over-range/missing values,
  bounded graph, static/foreground drawing, drag/close/reopen/lock, flight reset and Spanish captions. All three
  sizes and both densities fit the 1080p preset; bounds also checked at 1440p, 4K and fallback 720p. All six
  Spanish navigation/training switches fit at 1080p; the 720p dialog retains pinned controls.
- Existing navigation 57, efficiency 18, modern 74, classic 58, settings 27 and manager/dialog 184 checks pass:
  503 focused checks in total. UI-language checks pass (1820 Spanish entries). Existing scene-level aircraft
  inertia warnings remain. New scripts parsed outside `app/` before integration; whitespace checks pass.

These checks establish presentation and sampling behavior, not physical validation or a whole-game FPS gain.
The full physics suite was not rerun; no simulation behavior changed.

Native Windows/Godot 4.7.2 review used Turbo Lumber in Spanish at 1920×1080: all six switches are visible after
the dialog-height fix, and normal plus large/compact flight layouts keep the centre clear. The live powered
flight showed load, vertical-speed history and advancing session distance while correctly suppressing the glide
ratio; numeric low-throttle glide cases are covered by the focused tests. A native 1280×720 review confirmed
the scrolling page with pinned controls. Captures remain ignored in
`tmp/debug-bridge/20261024-144614-47870/shots/` (001 options, 002 flight, 003 fallback dialog). No bridge engine
errors were reported; both rendered sessions were stopped. No screenshot is added to Git.

## Widget efficiency and usability (2026-10-24, HUD-13-R8)

Modern widgets now invalidate graphics independently from labels: RPM/load changes preserve the throttle bar;
voltage/current changes preserve an unchanged charge bar; wind speed/updraft changes preserve the bearing
diagram; and a trim change redraws only its axis. The height clock uses whole seconds. Compact-to-full mode
redraws the latest value, while repeated paused samples retain cached drawings. Existing classic/navigation/
training static-face caches and bounded histories remain in use.

The manager skips legacy label, warning-chip and battery-panel presentation while its layer is hidden. Charge,
alarms and constant-size flight aggregates continue updating. Battery sensor exports omit both 600-sample
float64 histories unless a visible detailed panel needs them; internal recording continues. This avoids up
to 9,600 bytes of history payload per scalar export, and removes the old intermediate history copy for detailed
exports. Reopening restores complete history and requests an immediate telemetry refresh.

All 18 player headers support double-click restore of that widget alone when unlocked. An ordinary stationary
click no longer saves a position. Existing drag, close, lock and persisted layout remain. The third options tab
is now Flight tools (Ayudas de vuelo); every instrument switch explains its measurements and unavailable data.
Native review caught unwrapped default tooltips extending beyond the screen; instrument switches now provide
word-wrapped help capped at 520 px, with viewport-aware width.

Checked-runner evidence in ignored `tmp/widget-efficiency-r8/checks/`: battery 135, efficiency 21, modern 74,
classic 58, navigation 57, training 56, manager/dialog 187, settings 27 and redraw 17: **632 checks, zero failures**.
The new redraw suite counts actual Control draw callbacks, including geometry changes as positive controls.
History tests cover bounded retention, scalar/full charge equivalence, caller mutation isolation and reopening.
Manager checks cover hidden sampling/presentation, immediate refresh, individual restore and lock protection.
UI-language checks pass with 1,841 Spanish entries; current scripts parse and whitespace checks pass. Initial
test-authoring syntax and an incorrect test filename were corrected before the final passing runs. Existing
aircraft inertia warnings remain. No physics code changed; the full physics suite was not rerun.

These are controlled reductions in work, not measurements of a whole-game FPS gain.

Native Windows/Godot 4.7.2 review in Spanish at 1920×1080 verified all five tabs, all six flight-tool switches,
and the longest glide tooltip fitting inside the viewport after the wrapping fix. A training widget was dragged,
restored by header double-click to normalized (0, 1), closed with × and reopened from its switch. The 720p
fallback retained the scrolling page and pinned controls. Ignored captures are in
`tmp/debug-bridge/20261024-145930-47870/shots/` (interaction/options) and
`tmp/debug-bridge/20261024-150219-47870/shots/` (001 corrected tooltip, 002 fallback dialog). Both native sessions
reported no bridge engine errors and stopped with no crash or leaked objects. No screenshots are added to Git.

## Widget runtime audit (2026-10-24, HUD-13-R9)

Used the repository tool index, checked runner and debug bridge (`profile`, `frames`, `objects`, `soak`,
scripted UI actions, screenshots and exit reports). Graph search did not locate the overlay implementations;
current source was inspected directly. Modern/classic/navigation/training caches remain intact. The audit found
unconditional legacy drawing and an input lifecycle issue affecting every player widget.

- `test_legacy_widget_efficiency` counts actual draw callbacks for transmitter, battery bar, voltage/current
  histories and wind dial. Before changes, 30 identical refreshes produced `[30, 30, 30, 30, 30]` redraws;
  afterward they produce `[0, 0, 0, 0, 0]`. Positive controls change sticks, mode, radio model, charge, history,
  alarm color and camera-relative wind bearing. Unit/temperature-only changes retain graphs. NaN gaps compare
  stably, compact mode skips hidden details, and reopening shows current readings. Battery history comparison
  retains two bounded snapshots for independent invalidation; it is not an unbounded cache.
- Native script profiling recorded 198 `PlayerInstrument._input` calls across 11 sampled frames with no drag.
  The constructor opt-out was overwritten by automatic tree-entry registration. Moving it to `_ready` changes
  the controlled idle count from 18 global listeners to zero. Drag temporarily enables it; release/reset disables
  it again. Tests cover every player family, and a native drag/double-click restored the default position.
- Help text is shorter and legacy close tooltips name their panel. First-hover native review caught tooltip
  height being resolved after popup placement; measured font/wrap dimensions now keep the first popup inside
  the 1080p viewport. Measurement uses Godot's documented
  [Font.get_multiline_string_size](https://docs.godotengine.org/en/4.7/classes/class_font.html#class-font-method-get-multiline-string-size).

Checked-runner final results under ignored `tmp/widget-r9/checks/`: legacy efficiency 14, battery 135, shared
efficiency 22, modern redraw 17, modern 74, classic 58, navigation 57, training 56 and manager/dialog 188:
**621 checks, zero failures**. UI-language checks pass with 1,841 Spanish entries. Baseline failures demonstrating
the defects are stored separately in `tmp/widget-r9/baseline/`. The draft was parsed outside `app/` before
integration. Parse checks caught and resolved a local variable collision during development.

Native Windows/Godot 4.7.2 at 1920×1080, Turbo Lumber: the preset/size/compact soak completed one warm-up,
a baseline and two compared cycles with 1,616 nodes, 1,003 resources, zero orphans, zero growing counters and
zero engine errors (static memory 262.2–262.4 MiB). This is a bounded lifecycle check, not proof against every
possible leak. The reusable `tools/debug/scenarios/widget_presets.txt` also passed with `--fail-on-error`,
covering all player families and returning Home. It moves the cursor off tooltips before further label-based
actions because the bridge scopes those actions to the currently open popup. First-hover screenshot:
`tmp/debug-bridge/20261024-152040-47870/shots/shot-11008-001.jpg`; no captures are added to Git. Native sessions
were stopped without crashes or leaked objects.

Tool limits: an initial profiling session reported missing imported scenery assets; a checked `--import` restored
the cache and later native sessions had no engine errors. The 12-sample report at `tmp/widget-r9/profile-full.json`
was dominated by debug logging and exposed the idle input calls; profiler wall-frame timings are not used for
an FPS claim. The snapshot LSP check was inconclusive (`NO_DIAGNOSTICS` for battery_panel.gd after 30 s,
`tmp/widget-r9/compiler.json`); direct engine parsing and executable checks passed. Existing aircraft inertia
warnings remain. No physics code changed and the full physics suite was not rerun.

## Shared glass and classic faces (2026-10-31, HUD-13-R10 / UI-22-R12)

The player frame now reuses the existing shell crystal shader with a neutral center, pale static reflection and
green decorative header/hover details. Its native panel draws only the border and shadow, avoiding a second
translucent fill. The underlay ignores input, follows widget opacity and has no process callback, screen copy or
animation clock. Classic dials retain their geometry with graphite bezels and pale needles/scale marks; horizon
sky/earth and amber heading/navigation indications remain semantic. Green focus and amber caution are separate
tokens, including battery bars and fuel-reserve chips.

Conditions uses the shared slider thumbs. Controller sections and the flight guide use green selection;
Workshop selection survives hover, and rebuilt lighting/sequence controls attach the existing crystal feedback.
These changes preserve the shared decorator's reduced-motion and screen-owned-style behavior.

Source review began at `c4dc202d`; the unrelated documentation/CI commit `3bf7ba2af` arrived during the work and
did not change these UI paths. Other concurrent CI/release edits were preserved. A separate Good Enemy review
found no blocking defect in the combined UI patch. No physics, telemetry contracts or downloaded assets changed.

Checked Godot 4.8-beta1 verification:

- Player widgets: 153 headless checks and 157 rendered checks; classic: 61; navigation: 57; training: 59;
  widget settings: 27; redraw suppression: 17; widget efficiency: 22; legacy efficiency: 14; battery: 138;
  overlay manager: 213.
- Weather sliders, controller sections (115), Workshop UI, Workshop lighting and lighting-sequence UI (39)
  passed. The rebuilt palette-action test exercises actual keyboard-focus feedback.
- Native `test_ui_crystal.gd` passed, including reduced motion, disabled states, native focus/activation,
  screen-owned overrides, rendered primary contrast and teardown.
- The HUD rendered test samples the actual surface over white and black at 80% and 100% opacity. The minimum
  sampled secondary-text contrast was **5.6977:1**. Opaque interior samples matched across both backgrounds;
  the static reflection was brighter than the lower interior. This bounds sampled pixels, not every scene.

Receipts are under ignored `tmp/widget-glass-{root,menu,hud}-20261031/`. An initial Workshop test assertion had
a syntax error, fixed before its passing rerun. The first rendered highlight test sampled outside the shader's
diagonal reflection; the final test samples the actual reflection and requires a larger brightness difference.
No implementation change was needed for that sampling correction.

Native Windows, NVIDIA RTX 3090 driver 617.42, OpenGL Compatibility: production review at **1920×1080** covered
Player, Classic at 80% and Classic at 100% in Spanish, plus Conditions and Controls. The existing
`tools/debug/scenarios/widget_presets.txt` passed with `--fail-on-error`. The debug session stopped with no crash
or leaked objects. Captures remain in `tmp/debug-bridge/20261031-073854-47870/shots/`; none are added to Git.

Full-suite limits: `app/test.sh` stopped during unrelated F4U resource import with `vector::resize failed, new
size 1048576` / `terminate called without an active exception` (engine exit 3; receipt
`tmp/godot-checks/godot-25mka2vb/`). `app/capture.sh` could not acquire its lock because Git Bash lacks `flock`;
the reported lock-owner text is secondary to that missing command. Neither complete suite is claimed passed.
The underlay adds material/node and GPU work despite having no GDScript processing loop; no performance gain or
full hardware/pilot-readability qualification is claimed.

## Lazy glass allocation (2026-10-31, HUD-13-R11)

Player instruments now create their crystal underlay on first tree visibility and retain it until teardown.
Hidden appearance changes update the stored style; first display applies the current opacity and size. The
visibility listener disconnects after creation. No shader, drawing style or recurring process callback changed.

Fresh presets previously allocated 19 ShaderMaterials, 19 ColorRects and 19 Node2D underlays each. Controlled
lifecycle checks now measure **0/0/0 for Pilot, 4/4/4 for Player and 5/5/5 for Classic**; detached managers allocate
none. Visiting every widget remains bounded at 19 independent surfaces, and reopening preserves material identity.
This reduces initial allocations by deferring work to first use; it does not reduce the eventual maximum.

The baseline is `ce789cae7`; the final player frame SHA-256 is
`a440f40704c4e45e216256d0cb12ab55ac4844a4a25fe93ec036c706ee5ded25`.
Concurrent commit `70709ff4b` included an intermediate candidate; final verification uses the working-tree hashes
and receipts, not that commit alone. Other tracks' edits were preserved. Terra Max implementation and independent
Good Enemy review found no blocking defect in the final HUD change.

Checked Godot 4.8-beta1 results: efficiency/lifecycle 81, headless player 153, classic 61, navigation 57, training
59, redraw 17, settings 27 and overlay manager 213 checks, all passing. Lifecycle coverage includes saved settings,
hidden CanvasLayer/Control ancestors, reparenting, first draw and repeated reopening. The rendered player suite
passed 160 checks. Its baseline and candidate PNGs are byte-identical (SHA-256
`ef121b41cc413c94faed5f833225f3d1b0b4950d13af392e2cc1573a69de5ce0`), with minimum sampled contrast still 5.6977:1.
An initial deferred-construction draft failed first-draw checks; the final synchronous visibility handler fixes it.

Receipts, baseline source copies and captures remain under ignored `tmp/widget-efficiency-r11/`. Seven-trial
headless synchronous median times (baseline → candidate, microseconds) were construction 31,694 → 41,692;
attachment 75,712 → 92,676; first single-widget reveal 282 → 461; warm reveal 95 → 140. These separate runs were
not controlled enough to establish a timing improvement or regression. They exclude frame/GPU time and do not
measure a whole preset's first-use latency. The native profile was dominated by debug logging and did not establish
a HUD frame-time hotspot. **No startup-speed, interaction-latency or FPS improvement is claimed.**

Native Windows/RTX 3090 driver 617.42, OpenGL Compatibility, 1920×1080: the fresh Pilot census had 1,775 nodes
versus 1,813 in the baseline, consistent with avoiding 38 underlay nodes. The existing widget-presets scenario
passed. A later third flight load in that same session failed allocating projected-shadow mesh data
(`alloc_static`/`cowdata`, `projected_shadow.gd:45`, native signal 11); retain
`tmp/debug-bridge/20261031-075525-47870/engine.log`. Its cause and relationship to the candidate remain unproven;
the successful scenario is not a clean-exit or repeated-flight stability qualification. A fresh session at
`tmp/debug-bridge/20261031-075729-47870/` loaded Classic, supported a 1080p visual review and stopped with no crash
or leaked objects. The full-suite import and Git Bash capture limitations recorded in R10 remain unresolved.

## Mechanical classic detailing (2026-10-31, HUD-13-R12)

Reference review used the [UMA airspeed photographs](https://umainstruments.com/aviation-instruments/non-tso-flight-instruments/airspeed-indicators-2/)
and [RC Allen attitude indicator photographed by Mid-Continent](https://www.mcico.com/102-0080-04): dark mounting
plates, recessed circular bezels, clear pale markings and visible needle counterweights. The
[Smith Mark IVA museum record](https://collection.sciencemuseumgroup.org.uk/objects/co29169/smith-air-speed-indicator-mark-iva)
supplied historical context. These are visual references; the implementation reuses the existing vector instrument
renderer and embeds no external photographs, branding or replacement textures.

The five classic faces now have chamfered mounting plates, countersunk slotted fasteners, layered rim lighting,
ivory markings and sculpted hands with dark counterweights and machined pivots. The green crystal shell, semantic
amber references, horizon colors, dial ranges and telemetry transforms are retained. Static housing remains cached;
there are no added nodes, materials, processing callbacks or screen-reading shaders. The extra moving-needle
primitives still draw on the existing change-driven path; no performance improvement is claimed.

Native review caught two inherited legibility defects: the imperial VSI unit legend intersected the −1 scale
mark, and German small/compact attitude text hid the bank value. The legend moved inward without shrinking its
font. Classic readouts now wrap to at most two lines, with nonbreaking spaces keeping attitude labels beside
their values. A regression reproduced the old line-count/height failure and verifies growth, shrinkage, both
German attitude values, unit/overflow messages and a short English readout remaining on one line.

Final classic source SHA-256: `1db07c0eb113c2978abe7013de8122edc4f49c47a60c933b36e68604da312538`.
Source review began at `70709ff4b`; concurrent commit `fabc7ef8a` incorporated these working files. Draft parses
passed before integration. Final checked classic tests passed **67/67 both headless and rendered** on Godot
4.8-beta1; the preceding refit passed all 81 widget-efficiency/lifecycle checks. Receipts are under ignored
`tmp/classic-r12-agent/checks/` and `tmp/classic-r12-root/checks/`.

Windows, RTX 3090 driver 617.42, OpenGL Compatibility, **1920×1080**: normal imperial and small/compact Spanish
and German views were reviewed. Final geometry and imperial legend clearance are in
`tmp/debug-bridge/20261031-081207-47870/shots/shot-5804-001.png`; final German/SI label pairing is in
`tmp/debug-bridge/20261031-081442-47870/shots/shot-32200-001.png`. All three R12 live sessions stopped without
crashes or leaked objects. Independent Terra Max Good Enemy review confirmed the two fixes and found no further
issue in those static views. This is focused visual/software evidence, not motion readability, a complete capture
suite or hardware performance qualification. No images are added to Git.

## Open classic dials and lower titles (2026-10-31, HUD-13-R13)

User review rejected the black rectangular surround and small instrument inside it. Classic widgets now omit
the outer card border/shadow and the R12 mounting plate/fasteners, retaining the circular bezel, ivory scales
and counterweighted hands. At the same widget width, normal dial diameter grows from about 218 to 259 px;
small/compact grows from about 152 to 202 px. The single name, drag grip and close button sit below the circle,
followed by the numerical readout and optional detail footer. There is no duplicate title above the dial.

The existing lazy crystal underlay is parented to the title handle and sized in its local coordinates. This keeps
the surroundings transparent through layout, hide/reveal and density changes without forced container sorting,
new nodes/materials, shaders or frame callbacks. Subtitle/footer backgrounds follow the existing opacity setting,
with 85%/90% contrast floors and fully opaque backgrounds at 100%. Existing style/material instances are reused.

Final classic source SHA-256: `3198b8fc4f2184482df8377de7c4add30b121a25ca26fd0cc725d22794767504`.
Final classic/efficiency test SHA-256 values are
`439444f09e50e36b76b52a7d2ccb1217b9b783e3cbabf37b4b11fabb3158f002` and
`c4743b487e278f4f0801911a82c5f8d74dcc62fbca68f33b89b583833bbad88c`.
Concurrent commits incorporated the working source; these hashes identify the reviewed files independently of
the moving repository HEAD. Checked tests passed **73/73 classic headless, 74/74 classic rendered, 92/92 widget
efficiency and 153/153 base player checks**, with no engine diagnostics. The rendered extra assertion checks
background pixels beside the dial. Coverage includes lower-title layout, compact bounds, opacity, first-draw
underlay ownership and hidden/reparented lifecycle behavior. Receipts remain under ignored
`tmp/classic-r13-bottom-agent/checks/`, `tmp/classic-r13-agent/checks/` and `tmp/classic-r13-root/checks/`.

Windows, Godot 4.8-beta1, RTX 3090 driver 617.42, OpenGL Compatibility, **1920×1080**: the final normal Spanish
view is `tmp/debug-bridge/20261031-083805-47870/shots/shot-51760-001.png`; small/compact is `shot-51760-002.png`
in the same directory. German compact readouts were also inspected. The final app process has stopped and its
engine log contains no crash or leaked-object diagnostics. This is focused static visual and software evidence;
no FPS gain, complete-suite pass, motion readability or other-hardware qualification is claimed. No images are
added to Git.

Independent Terra 6.1 Max Good Enemy review found no concrete regression in the final source and the two
Spanish captures. It identified routed pointer input as a gap in handler-level tests, prompting an additional
native debug-bridge interaction check. Session `20261031-085207-47870` confirmed that a pointer press on the
lower classic title starts dragging, then delivered move/release events. A CLI expression quoting error stopped
the script before release/position/close assertions; it is not a product failure. The session stopped with no
crash or leaked objects. Receipts are `tmp/classic-r13-root/pointer-final-result.txt` and `pointer-final-stop.txt`.
A retry in `20261031-085401-47870` encountered a translation load error at `app/i18n/fr.po:8364` while that file
was modified by concurrent work, and was stopped (no crash, nine exit-leak objects reported). End-to-end pointer release/close remains unverified by this
additional run; the handler-level checks and earlier visual evidence above remain the bounded evidence.

## Liquid fuel tank (2026-11-06, HUD-13-R14)

The user requested a game-like fuel gauge with liquid responding to the aircraft. `fuel_instrument.gd` reuses
the existing modern frame, licensed fuel icon, crystal material, typography and move/close controls. Its local
canvas shader adds a shaded liquid chamber, meniscus and restrained glass reflection. It consumes the accepted
fuel sample for quantity, reserve and family; it never writes to the session. The [overlay guide](../../../plans/flight-overlays.md)
owns behavior and motion limits. Bank/pitch/load feedback is stylized, not physical slosh validation.

Checked native Windows tests passed **153 player widget, 213 overlay manager, 21 production fuel integration
and 17 existing redraw checks**. The production check now covers glow, gasoline and turbine fuel, accepted
fill/reserve propagation and unchanged flight state. Receipts are in ignored `tmp/godot-checks/` under
`fuel-widget-final-player-*`, `fuel-widget-manager-*`, `fuel-family-production-*` and `fuel-widget-redraw-*`.
The redraw suite covers the shared base graphics; the dedicated liquid tests cover the new shader path.

`test_fuel_instrument.gd` passed **61 headless checks and 71 rendered checks**. It covers invalid/missing data,
family fallback, usable-empty residue, reserve provenance, motion at unchanged quantity, paused samples,
reset/rewind/gaps, hidden/reopened widgets and compact geometry. Pixel comparisons establish visible motion,
identical frozen frames, correct render-clock lag handling and invariant full/empty endpoints under bank.
The rendered run also includes all headless cases. Receipts are under `tmp/fuel-widget-tests-agent/` and
`tmp/fuel-widget-tests-final/`. English normal and Spanish small/compact fixtures in
`tmp/fuel-widget-preview-20261106/` were visually inspected at 1920×1080. These use synthetic telemetry and
are explicitly separate from the production-aircraft integration checks.

Native debug-bridge review used Godot **4.8-beta2**, Windows, RTX 3090 driver 617.42, OpenGL Compatibility,
**1920×1080**. The turbine's All instruments view fits without overlap; a roll input changed the liquid target.
Captures and engine log remain in `tmp/debug-bridge/20261106-140913-47870/`. Shutdown reported no crash or leaked
objects. This is focused UI evidence, not complete CI, other-hardware performance or physical validation.
No images are added to Git. A concurrent unrelated commit incorporated the initial implementation;
source hashes below identify the final candidate independently of the moving branch.

Final runtime SHA-256:

- `fuel_instrument.gd`: `5038ab857179c9a915584253cf5973e8ca7b331fa132b6ba19298a6b73514fd2`.
- `fuel_liquid.gdshader`: `25b21fe9524182094f7423e3dd922005d37d9b308d57c8b36c0829fc457a7d03`.
- `overlay_manager.gd`: `e76023fb0c67bff84990403d30e6e187d3eea16b2e8ffa89fad52a5f62574279`.

### Inverted/knife-edge motion and translucency (2026-11-06, HUD-13-R14-R1)

The user's follow-up exposed a limitation in the original sine-based slope: 180° returned to level and 90°
could not place fuel against a side wall. The replacement uses a full-circle surface normal and an analytic
rectangle-area quantile. The telemetry presenter forwards body-right specific force alongside the existing
vertical load factor; the widget derives apparent down without modifying the solver. The existing fuel-feed
model documents this force convention in `app/physics/glow/fuel_feed.gd`. Angular unwrapping avoids a discontinuity
at ±180°. Alpha blending replaces the opaque gradient, exposing internal tank ribs beneath the tinted liquid.

Native checked results: **69 headless / 105 rendered fuel checks, 44 telemetry, 153 player-widget and 21 production
fuel checks**, all passed on the final candidate. Rendered coverage includes 24 combinations of amount and bank
(0°, 45°, 90°, 135°, 180°, −90°), with 2% absolute pixel-area tolerance for rounded corners and antialiasing;
the wall-transmission check distinguishes real alpha blending from an opaque tint. An initially broad meniscus
failed that area bound and was narrowed before the final pass. Receipts are in `tmp/fuel-inverted-checks/`;
reviewed 1920×1080 fixtures are in `tmp/fuel-inverted-preview-final-20261106/`.

Live debug-bridge flight: Extra 300, `--fuel=0.37 --alt=500 --start=airborne --view=chase`, on the same Windows /
Godot 4.8-beta2 / RTX 3090 / OpenGL Compatibility host. Control-driven watchpoints captured **87.58°** bank
at tick 2897 (vertical load 0.200 g, right specific force −0.279 g) and **175.58°** inverted at tick 2973
(−2.371 g vertical, −0.178 g right). The liquid visibly shifted toward the side and then roof while retaining
the accepted remaining quantity. These are maneuver samples, not sustained trim or physical validation.
Captures/logs: `tmp/debug-bridge/20261106-143117-47870/`, shots 002–004. Shutdown reported no crash or leaked objects.
Some live HUD glyphs were partially missing in these captures despite correct label strings and no script
diagnostics; the controlled widget fixtures are clear. Full-scene font readability is not established by this check.

Final SHA-256: `fuel_instrument.gd` = `61e7ae3e7cd01ca10dac05eccdc761ad6fd4fdcc698fcba6ef05328a5ca20faa`;
`fuel_liquid.gdshader` = `73fd41ae1dc3393b99b60a0a007cd16eba86e18f02821d36079b00c183adb91d`;
`telemetry.gd` = `331493ce55f432091d8cafb0ff889f77c5a1ed618c1e5543179229fc97079237`.
No images are added to Git. Full CI, other-GPU performance and physical slosh validation remain separate.

### Glass flight alerts (2026-11-06, HUD-09-R1)

O3 now reuses the existing fluorescent crystal shader above dark text wells, with explicit severity, a short
action and a mouse-only close button. Settings add an Alerts page for details, visible-card limit (1/3/5),
range/energy/status advisories and optional training cues. Critical conditions bypass advisory switches;
the capped overflow summary still names every hidden critical condition. Estimated reserve provenance stays
in the headline when details are off. Presets and older preference dictionaries retain their previous shape.

The presenter sorts and deduplicates accepted warning codes after battery sensor sampling. It does not
infer pack-ECM alarms from model SOC. No usable fuel requires an accepted finite-fuel mass sample with zero
usable fuel. The optional descent/bank/G cues use the display thresholds documented in the
[overlay guide](../../../plans/flight-overlays.md#warning-triggers), with accepted-time dwell/clear grace,
reset/rewind handling and immediate retirement of a cue whose source becomes unavailable. None of these
thresholds changes flight physics or claims an aircraft operating limit.

The card pool is bounded by the largest supported limit. Unchanged warning samples leave its nodes and
transitions untouched; hidden layers stop the entrance tween, and reduced motion cancels it. The shader has
no automatic clock, screen copy or background blur. This establishes bounded UI work, not a frame-time gain.

Checked native Windows / Godot 4.8-beta2 results: `test_alert_policy.gd` **33**, `test_warning_settings.gd`
**35**, `test_warning_presentation.gd` **29**, `test_overlay_manager.gd` **222**,
`test_overlay_battery_flight.gd` **12**, and `test_overlay_fuel_flight.gd` **25** checks, all passed.
Receipts are in `tmp/godot-checks/` under `alerts-policy-invalid-data-*`, `alerts-manager-final-*`,
`alerts-battery-flight-*` and `alerts-fuel-flight-*`; presentation receipts are under
`tmp/alerts-glass-ui-final/checks/`. Geometry coverage includes Spanish action/badge sizing, compact critical
overflow, a 480 px narrow-window fixture, 720p compatibility, and a 1080p Spanish 200% settings fixture.
The extended production fuel check uses the real gasoline/turbine exhaustion transition and accepted source-off
latch; the paused alert replaces reserve reminders without modifying the accepted fuel state. Its final receipt
is `alerts-accepted-empty-fuel-final-*`. The settings test also passed in isolation under `alerts-settings-isolated-*`
after a parallel final run hit an engine allocation failure.

All eight translated catalogs include the 40 new alert messages. Six adjacent fuel-widget messages that were
missing from the other seven catalogs were completed too. The serialized `test_ui_language.gd` run passed
all language checks, including coverage of **2,659** source messages per catalog, format arguments, bundled
glyphs, switching and preference restart behavior (`tmp/godot-checks/alerts-language-isolated-*`).
The earlier parallel language run's allocation failure is retained under `alerts-languages-*`; it is not a pass.

Native rendered review used the debug bridge on Windows / NVIDIA RTX 3090 / OpenGL Compatibility, first at
**1920×1080**, then **2560×1440**. English and Spanish alert fixtures have readable severity, titles and
actions; the native Alerts page remains usable, with tab scrolling for longer Spanish labels. Settings were
changed through real controls and retained across app restart. The initial native review caught a collapsed
action-label height; the repaired geometry is covered by the presentation test and final captures.
These are presentation fixtures in a paused production scene, not flight-model evidence. Captures/logs stay
in `tmp/debug-bridge/20261106-144745-47870/` (shots 004–008); the prior session holds the English Alerts page.
Both sessions shut down without crashes or leaked objects. No images are added to Git.

The shared branch advanced during implementation; runtime SHA-256 identifies the reviewed candidate:
`alert_policy.gd` = `a7a1a349807d0998a36996146020a5b61b8be306c3849ee48d17dcd374020399`;
`warnings_bar.gd` = `ae32991e5cb32f5f5dd9567019eed5ec6782b11bbd163ae36d1d221706d89971`;
`overlay_manager.gd` = `850af74740dc4f9e52703830dd418a39c21f2a94edc84de9a6723147d48e5d11`.
Full CI, other-hardware performance and pilot acceptance remain separate.

### Colored translucent alert glass (2026-11-06, HUD-09-R2)

The owner's follow-up asked for alerts closer to the menus' radioactive glass, including red and yellow light.
O3 now uses red danger, yellow caution and green status glass across the whole surface, with rounded 12 px
walls, soft semantic halos and pale text. Base opacity is 78%; a 14% dark interior film protects copy without
covering the glass reflections. Opaque mode still produces solid backplates. The shared crystal shader adds
an optional per-material text-area brightness ceiling; its default is numerically identical to the menu's
previous green bound. Existing shader provenance and export notices remain in place.

One 560 ms sine-eased arrival sweep animates only optical uniforms. Text stays fully opaque. Hiding the rail,
enabling reduced motion, removing a pooled card or hiding the overflow summary clears its light immediately.
There is no automatic shader clock, screen read, new texture or continuously running effect.

`test_warning_presentation.gd` passed **40 headless / 49 rendered checks** on Windows, Godot 4.8-beta2,
NVIDIA RTX 3090 / OpenGL Compatibility. Rendered checks sample each severity's text rectangles over white
and black at rest and through the sweep, require at least **4.5:1** contrast, and establish actual transmission
by requiring the glass-center color to change by more than 0.05 between backdrops. The first rendered palette
failed the caution/status detail threshold (4.07:1 / 4.02:1); paler supporting text passed on the final candidate.
Headless color bounds are estimates; the actual-pixel result is specific to this renderer. The rendered
`test_ui_crystal.gd` consumer checks and **222** overlay-manager checks also passed. Receipts are under
`tmp/godot-checks/alerts-radiant-*` and `alerts-menu-glass-consumer-*`.

Native production-scene fixtures were reviewed in English at **1920×1080** and Spanish at **2560×1440**;
captures/logs are in `tmp/debug-bridge/20261106-151629-47876/` (shots 001 and 003). These show all three semantic
colors together and preserve the estimated-reserve qualifier. The session exited without a crash or leaks.
Spanish was also reviewed at **1920×1080** after selecting Spanish through Home before flight, in
`tmp/debug-bridge/20261106-151928-47876/` (shot 001); every severity label and action is visible. This session
also exited without a crash or leaks.
Images remain ignored. This is focused appearance/contrast evidence; full CI and other-renderer/hardware
qualification remain separate.

Final runtime SHA-256: `warnings_bar.gd` = `ceb918151574f63514d5f6b97ce8ecea1f575ffa401abd5c4cab3bce8aaee77b`;
`crystal.gdshader` = `21c72c091d1775efee3828c72af0f309d0816fff5691624fbd0917cb0ec816ee`.

### G-driven waves, bubbles and foam (2026-11-06, HUD-13-R14-R2)

Research and tool selection preceded implementation. [PWira's 2D Liquid Wave](https://godotshaders.com/shader/2d-liquid-wave/)
provides freely reusable MIT shader code; its value noise and noisy foam approach were adapted, with the full
notice in `app/render/overlays/FUEL_LIQUID_LICENSE.txt`. No upstream images or new dependencies were imported.
[GPU Gems' wave chapter](https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-1-effective-water-simulation-physical-models)
informed the multi-mode surface, and the [SwRI slosh references](https://www2.swri.org/www2/fluid-slosh/slosh-dynamics.htm)
provide mechanical-analog background. These sources do not validate this HUD's parameters against a real fuel tank.
[Godot's compute documentation](https://docs.godotengine.org/en/stable/tutorials/shaders/compute_shaders.html)
excludes the Compatibility renderer from compute support; the existing CanvasItem shader and simulation clock
therefore remain the implementation. The checked runner and debug bridge provide acceptance evidence.

The bounded angular spring and bubble phase now scale with square-root projected g. Three standing surface
modes use the actual surface chord, so waves retain useful shape on either wall or the roof. Maneuver impulses
excite a separate air envelope that decays more slowly than wave energy. Sixteen procedural hollow bubbles rise
opposite apparent down; broken foam patches sit on the wet side of the meniscus. Numeric fuel remains accepted
simulation data. This is a 2D visual approximation, not CFD, tank-specific slosh or fuel-feed prediction.

The first rendered pass found air effects too faint under smaller load changes. Perceptual gain and stronger
bubble rims corrected that without changing the accepted quantity. Preview force captions were also corrected.
Final checked result: **133 fuel-widget checks** (including 80 non-rendered assertions), plus **21 production-fuel
checks** across glow, gasoline and turbine aircraft. Coverage includes both knife edges, inverted positive/negative
g, high/low g response, decay, clipping, transparency, empty/full/unknown guards, pause, lifecycle resets, area at
rest, and CPU/shader agreement across the 1024-second clock and both effect-phase rollovers. Receipts:
`tmp/fuel-aeration-checks/`; final 1920×1080 fixtures: `tmp/fuel-aeration-preview-clock-checked/`.

Live Extra 300 flight on Windows / Godot 4.8-beta2 / OpenGL Compatibility / RTX 3090 at 1920×1080 reached
**87.713°** bank (tick 103), **175.895°** inverted (tick 179, vertical load **−2.350 g**), and **−92.059°** bank
(tick 259). Inverted fuel visibly moved to the roof with aeration and a moving meniscus. These are transient
maneuver samples, not sustained trim. Logs and captures: `tmp/debug-bridge/20261106-145532-47870/`, shots 002–003;
shot 001 has a focus-loss pause menu obscuring the HUD. No script/shader diagnostics, crash or exit leaks occurred.
Some glyphs in the last live capture again showed the previously recorded intermittent font issue; controlled
fixtures remain clear. Raw render timings were observed, but the attempted isolated shader ablation was rejected
as an unknown/hidden target, so no shader-cost or wider performance qualification is claimed.

Final SHA-256: `fuel_instrument.gd` = `cf2e2e9d34b1e131fa903937e68ab4a355808b0fa7917ba8828a878e998d0b24`;
`fuel_liquid.gdshader` = `1a5a32acd0ea29ec9e633102221d5f72e36573b97bbc51c0e962b84ee553fbad`;
`test_fuel_instrument.gd` = `f6abce32405e722f63e0ba4ec084c8580fe941205e22aa3b6f724ee8313801ef`.
No images are added to Git. Full CI, other-GPU performance and physical slosh validation remain separate.

### Liquid shader efficiency (2026-11-06, HUD-13-R14-R3)

The pre-optimization shader was preserved as `tmp/fuel-optimization/baseline.gdshader`, SHA-256
`1a5a32acd0ea29ec9e633102221d5f72e36573b97bbc51c0e962b84ee553fbad`. The widget's CPU lifecycle already avoids
per-frame callbacks, hidden refreshes and repeated paused motion publication, so that code was left intact.
Shader inspection found uniform-only spring, force direction, surface/chord and wave-coefficient work repeated
per fragment, plus bubble/noise work where its contribution was zero.

The candidate moves those shared calculations to the quad's vertex stage through four flat `vec4` varyings.
It skips settled wave cosines, aeration outside the antialiased wet region, foam noise outside its maximum
band, and bubble distances outside conservative rim/core/glint bounds. The original 16 seeds, paths, fades,
accumulation order, opacity clamps and glass expressions are retained. The shader adds no texture, pass,
particle node or CPU frame callback. [Godot's varying documentation](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html#interpolation-qualifiers)
was checked before using flat vertex-to-fragment data.

**335 checks passed** on Windows / Godot 4.8-beta2 / OpenGL Compatibility / NVIDIA RTX 3090, driver 617.42,
at 1920×1080. These include the existing 133 widget checks, 177 same-process baseline/candidate image pairs,
24 timing-batch changing-image checks and the report-write check. The image matrix covers normal/compact
tanks, six attitudes including both knife edges and inverted, calm/agitated states, and seven fills including
unknown, empty, 2%, 37%, 85%, 98% and full. Nine further pairs exercise nonzero spring offset/velocity at
0.04, 1 and 6 g, clock rollover and a render clock trailing its sample. Every pair had
**zero pixels exceeding 0.025 maximum RGB difference**;
this is tolerance-based parity, not a claim of identical encoded files. Native fixture images were inspected.

The optional test mode accepts `--fuel-reference-shader=<absolute-path>` alongside the existing
`--fuel-capture-dir=<fresh-directory>`. Add `--fuel-profile` for the bounded comparison. It loads the reference
in memory, preserves the production source, and writes `shader-comparison.json` with source hashes, engine,
adapter, matrix results and raw timings. Profiling uses three ABBA sequences per size, 12 warmup and 60 measured
samples per phase. Each sample forces eight draws without swapping window buffers, then synchronously reads
back the 1080p root image. Other fixture cards are hidden, and start/end changes are checked within the tank's
rectangle rather than across the whole viewport. The render-loop setting
is restored. This measures draw submission/completion plus readback, not isolated GPU time or flight FPS.

| Workload | Reference median | Candidate median | Interpretation |
| --- | ---: | ---: | --- |
| Normal 208×101 liquid rectangle | 8.250 ms | 8.287 ms | Inconclusive: paired ABBA changes ranged from 0.93% lower to 0.96% higher. |
| Amplified 1860×900 rectangle | 8.521 ms | 8.330 ms | Inconclusive: paired groups ranged from 2.62% higher to 9.65% lower. |

Medians are across the six phase medians per role, for eight draws plus one readback. The enlarged rectangle
retains the normal shader dimensions to amplify fragment workload; it is not a player HUD layout. Earlier
window-scheduled and single-draw probes were noisy. An eight-draw run with other fixture cards still visible
showed a 13.6% lower stress median, but the stronger isolated fixture did not reproduce that magnitude consistently.
These observations do not establish a reliable speedup. The normal-widget difference remains below the resolution
of this comparison; no FPS or general hardware performance improvement is claimed. The retained benefit is the
structural reduction in repeated shader calculations, with matched visual coverage and unchanged CPU lifecycle.
The baseline live scene stayed at its 120 Hz display cap; raw root GPU readings have unverified freshness.

Final receipts and comparison: `tmp/fuel-optimization/checks/` and `tmp/fuel-optimization/final-reviewed/`.
Live baseline session: `tmp/debug-bridge/20261106-150542-47870/`, clean shutdown with no crash or leaked objects.
Final SHA-256: `fuel_liquid.gdshader` = `dbbe65e204a06ceb814ac5eb155153a5ed44c1f73faf6b70fceafb649a64a441`;
`test_fuel_instrument.gd` = `61724a142fe721e7970e939bbf21a3e6c77a2aa2355f664054b0ae0253fa2e07`.
Full CI, Mobile/Metal, Forward+, WebGL and other-GPU qualification were not run for this localized change.

### Alert motion and sound (2026-11-06, HUD-09-R3)

Research preceded implementation. [Material 3 motion](https://m3.material.io/styles/motion) informed the
Playful/Subtle distinction; the older [Material duration and easing guide](https://m1.material.io/motion/duration-easing.html)
informed a quicker exit than entry. The selected 230/160 ms timings are this project's choices.
[Xbox audio accessibility](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/105)
and [motion settings](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/117)
informed independent alert volume, mute and motion controls. This does not claim guideline conformance.
The sounds reuse the existing CC0 Impact Sounds bank; its [source mapping](../../../../assets/ui-audio/README.md)
remains authoritative. No new sound/image assets or dependencies were added.

Playful arrivals use a small spring slide, Subtle a smaller cubic slide, and Off/global reduced motion settle
immediately. Text remains opaque. On insertion, survivors occupy their new vertical slots immediately and settle
horizontally, keeping urgent copy separate; removals reflow upward over 230 ms. Cleared copy disappears from
the visual/accessibility tree immediately while its unlabelled glass silhouette exits over 160 ms. Explicit
close/reset removes every silhouette. Active cards, retirees and their reusable pool are bounded; there is
no recurring idle process for motion. The existing single 560 ms optical sweep remains.

The manager now routes all selected warning audio through one Master-bus voice, including finite-fuel reserve;
the accepted fuel-crossing signal remains, without a second player. New danger immediately replaces lower
severity or lower-priority danger audio. Other cues use a 0.9 s global gap; a repeated code needs 0.8 s absent
and a 4 s cooldown. A lower-priority danger inside that gap is suppressed rather than queued. Clear confirmation
requires at least 1 s of actual active flight plus 0.3 s quiet. Initial state, menus, hidden warnings, ordinary
pause, option changes, reset and rewind silently re-baseline. A new radio/controller-loss cue can still play
when that fault itself pauses flight. Test sound explicitly auditions a caution without changing flight history.

GOOD ENEMY review found and corrected a lost critical cue after a recent caution and ambiguous signed-AoA
stall guidance. Motion tests additionally exposed insertion overlap, intermediate-container-sort jumps and
detached-node teardown defects; those were fixed before the final native capture.

Checked results on Windows / pinned Godot 4.8-beta2:

| Focused script | Passed checks |
| --- | ---: |
| `test_warning_motion.gd` | 30 |
| `test_alert_audio.gd` | 51 |
| `test_alert_feedback.gd` | 16 |
| `test_warning_settings.gd` | 89 |
| `test_overlay_manager.gd` | 222 |
| `test_overlay_fuel_flight.gd` | 25 |
| `test_alert_policy.gd` | 33 |
| `test_warning_presentation.gd`, rendered | 49 |

Total: **515 checks**, plus language coverage for all **2666 source messages** across all eight catalogs.
The 1080p rendered checks retain contrast ≥4.5:1 over white/black through the optical sweep and measurable
scene transmission. Motion checks sample text rectangles during insertion, interruption, churn, hide/reset,
reduced motion and teardown. Receipts are in `tmp/godot-checks/alert-feedback-*` and
`tmp/alerts-motion-ui/checks/`; the final manager/boundary/fuel runs use the `*-frozen` labels.

The reusable [feedback fixture](../../../../research/flight-overlays/feedback_preview.gd) exercises actual
production rail/audio classes without simulation state. Pass `--out=<fresh absolute directory>`; native PCM
recording additionally needs `--record-audio`, `--display-driver headless --audio-driver WASAPI`, and real time
(omit `--fixed-fps`/`--write-movie`). Final output: `tmp/alert-feedback-HUD09R3/native-final/`. At 48 kHz stereo,
all four cue windows contain nonzero PCM; overall peak is **0.2474**, RMS **0.00711**. The Master-muted pass
contains **zero nonzero samples**. These are mixer measurements, not speaker preference or output latency.

The 499-frame movie is **1920×1080 at 60 fps**, reviewed during insertion and removal. Godot Movie Maker takes
its initial viewport from project settings, so capture used an ignored temporary project mirror with only
viewport width/height changed from 1280×720 to 1920×1080. The production project was unchanged. The first
720p movie was diagnostic only. Final preview `tmp/alert-feedback-HUD09R3/alert-feedback-native.mp4` combines
the 1080p video with the separate WASAPI mix, shifted 50 ms to align fixture preroll; it is not a latency test.
Source/artifact hashes and PCM-window review are retained beside it. No images or recordings are added to Git.

Native OpenGL Compatibility / RTX 3090 review also covered Spanish controls and Test sound at 1920×1080
(`tmp/debug-bridge/20261106-154912-47878/`, shot 002). Final-source alert fixtures in a paused production flight
were reviewed at 1920×1080 and 2560×1440 (`tmp/debug-bridge/20261106-155206-47879/`, shots 001–002), using injected
selected codes for presentation review. The loaded warning-script hash matched the candidate; both sessions
closed with no crash or leaked objects. These do not validate physical warning thresholds or flight behavior.

Final SHA-256: `warnings_bar.gd` = `f033075500e0fc83e91d1b173a6e8a6bac404e80ae52022da309f70e88166ee0`;
`alert_audio.gd` = `a00c33753c72187977f46768727f3732a1df440e553f7e4a55ceab26856c133c`;
`overlay_manager.gd` = `15ba9e53047ddb18dc640477dd092ab75ff0e305b182a0edd8fa981d023377fe`.
Full CI, other renderers/hardware and perceptual audio preference remain unqualified by this focused pass.

### Alert callback efficiency (2026-11-06, HUD-09-R4)

The HUD-09-R3 candidate was preserved before optimization in
`tmp/alert-efficiency-HUD09R4/reference/`, with `baseline-hashes.json`. Baseline warning/audio/manager hashes
are the R3 hashes above. The [focused benchmark](../../../../research/flight-overlays/bench_alerts.gd) compares
those five copied alert scripts against the candidate in one process; other app dependencies are shared.
Only preload paths are rewritten in temporary reference copies. The original copies are checked against
the independently retained manifest, and both source sets are checked again after measurement.

The changes remove work after the rail has already settled: repeat cleanup performs no shader-uniform writes
or card-pool scan. Styles are immutable and reused by severity/opacity; unchanged survivors keep their copy
and style state. Each card still owns its mutable material. Sweep math is computed once per step and touches
only active cards and an attached summary. A retiring summary can no longer be relit by a subsequent sweep.
Selection is cached by a detached raw-code array and the four category flags. Accepted battery/fuel/training
observers still run every sample. Audio validates mute/time/rewind before its stable-active fast path; empty
input continues through clear timing, and the first retirement still stops playback immediately.

Matched native result: Windows / Godot 4.8-beta2 / OpenGL Compatibility / RTX 3090 (driver 617.42), actual
1920×1080 viewport. Three reference/candidate/candidate/reference rounds use 64 warmup calls, then eight
32-call batches per group. Values below are medians of per-call **batch means**, excluding deferred layout,
drawing, GPU completion and audio mixing; their recorded p95s are also batch-mean statistics. They are not
frame times or whole-flight FPS. Shared-host background activity caused visible timing variation.

| Alert callback workload | Reference µs/call | Candidate µs/call | Change |
| --- | ---: | ---: | ---: |
| Empty | 39.375 | 37.094 | −5.8% |
| Three steady alerts | 49.125 | 37.313 | −24.0% |
| Three alerts with sound disabled | 28.250 | 33.219 | +17.6%; inconclusive in this run |
| Settled preview | 28.688 | 18.438 | −35.7% |
| Disabled after warming a ten-card pool | 33.313 | 17.281 | −48.1% |
| Repeated three/four-alert changes | 1051.344 | 871.313 | −17.1% |
| Optical sweep update | 3.094 | 2.219 | −28.3% |

The changing-rail row is a back-to-back stress workload, not normal 10 Hz flight usage. Native receipts and
raw distributions: `tmp/alert-efficiency-HUD09R4/native-abba/`. The muted case had one paired round regress
12.5% while two improved 17.8–19.1%; the aggregate was therefore not accepted as a reliable direction.
One targeted repeat used `--only=muted_three --calls=512` to reduce short-batch noise. It measured
**34.574 → 28.826 µs/call (−16.6%)**, with all three paired rounds improving 12.4–20.2%.
That separate receipt is `native-muted-longer/`; both runs are retained. The callback savings are small
absolute costs at the normal refresh rate and do not establish a full-game performance gain.

The same native run compared **24 static image pairs** across English/Spanish, translucent/opaque glass,
limits 1/3/5 and white/black backgrounds. Every pair was byte-identical. Captures also assert actual 1080p
dimensions, visible populated cards/overflow, on-screen rectangles and pixels differing from the backdrop,
so two blank frames cannot satisfy parity. The shader and animation durations were unchanged. No images
were retained for passing pairs; the fixture saves diagnostic images only on a mismatch.

**554 focused checks passed:** motion 42, audio 51, new efficiency boundaries 27, feedback 16, manager 222,
settings 89, real-fuel path 25, policy 33 and rendered presentation 49. Coverage includes unchanged-code
training dwell/clear, accepted pack alarms and real fuel exhaustion, repeated-empty all-clear timing, mutable
input arrays, filtering, reset/rewind/pause/reopen, locale, accessibility after reuse, independent materials,
opaque toggles and bounded style caches. The existing rendered contrast/transmission checks still pass.
GOOD ENEMY review found no confirmed cache/lifecycle regression. Individual receipts use
`tmp/alert-efficiency-HUD09R4/checks-{bar,enemy}/` and `tmp/godot-checks/alert-efficiency-*`.

The repeated WASAPI fixture (`native-audio/`) still emits info/caution/danger/cleared, with 48 kHz stereo
peak **0.2474**, RMS **0.00711** and **101568 nonzero samples**; Master mute again produces exact digital
silence. Mixer capture does not establish speaker preference or output latency. `summary.json` retains the
measurements, paired-round changes, check inventory and source identities. No assets/dependencies were added.

Final SHA-256: `warnings_bar.gd` = `2e6bd011246bce7b466b1a6caad26c4f303062f49d872c39fcf59f4562706585`;
`alert_audio.gd` = `a63f8eb55bb4b8514c2ef479d04c50d5d1d0f80f35b3a2e79a1a65cf1d87602b`;
`overlay_manager.gd` = `986e3fdd3fc35181f0490731169f0ecf526d5234e0902da2ebde63cc29f8e546`.
Full CI, whole-flight frame-time/memory budgets, other renderers and other hardware remain separate gates.
