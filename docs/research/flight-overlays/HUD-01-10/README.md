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
