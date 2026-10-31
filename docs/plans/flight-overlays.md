# Flight overlays plan

**Date:** 2026-10-13. **Status:** HUD-00…10 implemented (b0b0347); HUD-11 done with 720p and 1080p rendered captures; HUD-05-R1/R2 add selectable JETI and Radiolink views; HUD-13 implements movable player instruments; HUD-12 waits for owner reading on target hardware. **Prefix:** HUD-00…HUD-13 ([registry](../README.md#tracks-plans-and-step-ids)). **Owner:** flight-overlays track, under the main line's acceptance. Supersedes [MENU-REDESIGN-PLAN](../MENU-REDESIGN-PLAN.md) UI-27 (D1).
**Owns:** `app/render/overlays/`, `app/ui/overlays_dialog.gd`, `app/tests/test_overlay_*.gd`, `docs/research/flight-overlays/`.
**Coordinated, not owned:** the seams in `app/main.gd` (main line), `app/app_root.gd`, `app/ui/pause_menu.gd`, `app/ui/controls_reference.gd`, `app/app_state/preferences.gd`, `app/i18n/es.po` (menu track). `render/hud.gd` and `render/panel.gd` are unchanged and still build the diagnostic text.
**Evidence:** [HUD-01…10](../research/flight-overlays/HUD-01-10/README.md), [HUD-05-R1](../research/flight-overlays/HUD-05-R1/README.md), [HUD-05-R2](../research/flight-overlays/HUD-05-R2/README.md).

## 1. What exists

Home flights provide nine legacy overlays and seven player instruments on one `CanvasLayer` (`render/overlays/overlay_manager.gd`). Each has a title and an × that closes only that overlay; the × never takes keyboard focus. Diagnostics docks beside the control guide and below active warning chips to keep their headers accessible.

| ID | Overlay | Anchor | Content |
| --- | --- | --- | --- |
| O1 | Flight data | bottom left | airspeed, ground speed, height above ground, vertical speed, throttle, slant distance from the pilot's eye, flight time |
| O2 | Transmitter | bottom right | selectable JETI DS-24 II or Radiolink T16D official frontal photo, simulated LCD and live gimbals (Mode 1/2), trim marks, input device, radio state and rate profile |
| O3 | Warnings | top centre | FAILSAFE, RADIO SAFE, STALL, LOW, FAR, BATTERY LOW, EXPERIMENTAL; chips wrap within 640 px; hidden when empty |
| O4 | Wind | top right | downwind arrow relative to the view; speed, "from" bearing and updraft on fixed lines |
| O5 | Telemetry | right | α, β, pitch/bank angle, heading, load factor, engine rpm |
| O6 | Diagnostics (developer) | top left | today's input panel and HUD text, unchanged |
| O7 | Performance (developer) | bottom centre | fps, frame p95, physics µs/tick |
| O8 | Control guide | top left | keyboard reference and active controller axes/buttons/AUX; aircraft equipment availability, accepted gear status and smoke output; scrollable, with device tabs and existing Kenney prompts |
| O9 | Battery (BAT-15) | right | finite packs only: pack V, V/cell and lowest cell, A, W, temperature, used/rated mAh, radio-side %, ESC LVC chip, 60 s V/A sparklines; compact line in Pilot. Owned by the [battery plan](battery-realism.md); [evidence](../research/battery/BAT-15/README.md) |

Presets: Off, Pilot (O1–O4 + O8, default), Full (O1–O5 + O8), Developer (all legacy overlays), Player (four core HUD-13 instruments + warnings), All instruments (seven + warnings), Custom (any other set). **F2** cycles Off → Pilot → Full → Developer → Player → All instruments; **F3** toggles O6+O7; Pause → **Flight overlays** sets overlays, units and stick mode and previews them live above the paused flight. Settings live under `[hud]` in `settings.cfg` (additive; older builds ignore it). Legacy named presets include the guide; saved custom sets retain their explicit visibility choices.

Pause → **Flight overlays** → **Radio appearance** selects JETI DS-24 II or Radiolink T16D. The choice is saved in `[hud]` and changes O2 immediately. It affects the illustration only; the device profile and control mapping remain independent.

Rules the implementation keeps:

- Overlays read the session; they never write to it. A 3 s trace with `--hud=overlays` equals the legacy trace except its creation time (Stik and Extra).
- Automation keeps the legacy labels: `--hud=legacy` is the direct-route default; `--hud=overlays` opts in. `capture_ui` still reads `_hud.text`.
- Numbers come from 64-bit state in `telemetry.gd` (pure): load factor = −F<sub>z,body</sub>/(m·g) from `sim.last_loads` (gravity excluded); height above ground from `GroundTerrain.sample` on the session's own surface table. No session accessor was added.
- Units (`units.gd`): metric km/h·m·m/s, imperial mph·ft·ft/min, SI m/s·m; "auto" = imperial for English, metric otherwise (D3). Exact factors 0.44704 m/s and 0.3048 m.
- Numbers refresh at 10 Hz; sticks every frame.
- The first-flight hint sits bottom centre. The optional latency camera marker is off by default, has its own close button and saved switch in Flight overlays, and stops sampling while hidden. It sits beside the controls guide when enabled; see the [camera protocol and controls](../FIRST-LAUNCH.md#8-film-stick-to-screen-latency-f6a).

### Warning triggers

| Code | Trigger | Source |
| --- | --- | --- |
| failsafe | pause reason "radio disconnected" | session |
| safe | radio connected, not armed | `radio.armed` |
| stall | airborne (> 1 m), airspeed ≥ 3 m/s, α within 2° of the solved stall-blend start `envelope.a1`/`n1` (D5) | aircraft v2 envelope; none if absent |
| low | airborne, sinking > 2 m/s, ground reached within 2 s | telemetry |
| far | slant distance beyond where the 6° minimum auto-zoom FOV shows the span below 30 px of a 1080 px reference height, i.e. where the pilot view's auto-zoom reaches its floor at every resolution (Stik ≈ 523 m; ≈ 349 m before CAM-23) | `Spec.AUTO_ZOOM`, model span |
| battery | `ocv_resistance` packs: modelled battery exhausted or SOC < 20 %. `pack_ecm` packs: observable alarms only (`battery`, `battery_critical`, `battery_lvc`, `battery_hot`, `battery_empty`), see [BAT-15](../research/battery/BAT-15/README.md) | `electrical_state()` |
| experimental | experimental aircraft-data route | main |

The 1 m, 3 m/s, 2 m/s, 2 s and 20 % values are display thresholds, not physics, and await pilot review.

## 2. Steps

| ID | Work | Proof / status |
| --- | --- | --- |
| HUD-00 | Decisions D1–D6 (owner accepted the defaults, 2026-10-13); registry row; F2 for presets (H remains the smoke pump) | [DECISIONS](../DECISIONS.md) row / done |
| HUD-01 | `units.gd`, `telemetry.gd` | `test_overlay_units` 23, `test_overlay_telemetry` 36 checks / done |
| HUD-02 | `overlay_frame.gd`, `overlay_manager.gd`, legacy route for automation | trace identity; `test_overlay_manager` / done |
| HUD-03 | ×, presets, F2/F3 | real mouse click hides only its overlay, takes no focus, a flight key still arrives / done |
| HUD-03-R1 | Visible close targets, separate guide/diagnostics, optional camera marker with close/save/reopen and hidden-sampling suspension | [Native review and focused checks, 2026-10-24](../research/flight-overlays/HUD-01-10/README.md#close-controls-and-camera-marker-2026-10-24-hud-03-r1) / done |
| HUD-04 | O1 Flight data | unit-formatted values in a live flight scene / done |
| HUD-05 | O2 Transmitter | Mode 1/2 stick and trim layout checks / done |
| HUD-05-R1 | JETI DS-24 II Carbon Line Orange visual with live controls and LCD | [source, captures and layout verification](../research/flight-overlays/HUD-05-R1/README.md) / done |
| HUD-05-R2 | Radiolink T16D visual and persisted JETI/Radiolink chooser | [source, captures and verification](../research/flight-overlays/HUD-05-R2/README.md) / done |
| HUD-06 | `[hud]` preferences, Pause → Flight overlays dialog | round trip and per-key fallback / done; no UI-driver capture of the dialog yet |
| HUD-07 | O4 Wind | arrow angle for view headings; calm hides the arrow / done |
| HUD-08 | Height above ground and load factor | from existing public state; level n = 1, 60° turn n = 2, terrain AGL / done, no seam needed |
| HUD-09 | O3 Warnings | one fixture per code, order, no STALL without a stall angle / done |
| HUD-10 | O5 Telemetry | live flight scene / done |
| HUD-11 | Spanish texts, contrast, layout | es entries; contrast ≥ 4.5:1 over any sky; no overlap at 1280×720 and 1920×1080 (Pilot, Full) and in Spanish; en/es rendered captures at 720p and 1080p / done |
| HUD-11-R1 | Visual review repairs: "-0°", wind jitter, warning wrap, dialog preview, hint and latency-marker placement | [review](../research/flight-overlays/HUD-01-10/README.md#visual-review-and-repairs-2026-10-13-hud-11-r1) / done |
| HUD-11-R2 | Default-open controls guide, profile-aware prompts, keyboard reference, close/reopen and Spanish copy | [verification](../research/flight-overlays/HUD-01-10/README.md#controls-guide-2026-10-15-hud-11-r2) / done |
| HUD-12 | Cost and pilot acceptance | VM (no GPU): ≈ 60 µs mean per frame, ≈ 0.26 ms on the 10 Hz refresh frames / owner reads Pilot preset in flight at 720p and 1080p: pending |
| HUD-13 | Player instruments, flight maximum, bounded dragging, persistent positions, lock/reset and independent switches/× | [Focused checks and native 1080p review](../research/flight-overlays/HUD-01-10/README.md#player-instruments-2026-10-24-hud-13) / implemented |
| HUD-13-R1 | Fuel, trims, engine, size/background/compact settings, crisp scaled text and cached drawing | [Verification](../research/flight-overlays/HUD-01-10/README.md#expanded-instruments-2026-10-24-hud-13-r1) / implemented |
| HUD-13-R2 | Instrument visual polish: icon headers, drag grips, clear close targets, inset readings and refined gauges | [Verification](../research/flight-overlays/HUD-01-10/README.md#instrument-visual-polish-2026-10-24-hud-13-r2) / implemented |

## 3. Decisions

| ID | Question | Chosen (2026-10-13) |
| --- | --- | --- |
| D1 | Replace UI-27? | Yes |
| D2 | Default preset | Pilot |
| D3 | Default units | By language (en imperial, es metric) |
| D4 | Default stick mode | Mode 2 |
| D5 | Stall source | Aircraft envelope `a1`/`n1`, 2° margin |
| D6 | Height reference | Above the ground under the aircraft |

## 4. Player instruments and remaining limits

### HUD-13 — Player instruments (2026-10-24)

Visual thesis: neutral dark crystal surfaces with large white readings, fluorescent green interaction details and a separate amber data accent. Classic instruments retain graphite bezels, pale scale marks and needles, and meaningful horizon/navigation colors. Reuse the existing Godot theme, telemetry, unit conversions and battery sensors. HUD-13-R2 uses seven small, pinned Lucide SVG icons with their [license and provenance](../../app/assets/ui/instruments/LICENSE.txt); no replacement UI framework is needed.

Content: four core instruments — airspeed with sampled flight maximum and ground speed; height above terrain with climb, distance and flight time; estimated battery remaining or accepted finite-fuel level; wind speed and a north-referenced direction dial. HUD-13-R1 adds fuel percentage/volume/mass/reserve, three signed trim axes, and engine RPM/throttle command/flight load. Unknown/unavailable readings stay explicit. Existing diagnostic overlays remain separate.

Interaction: drag the header with bounded movement and save on release; hover and dragging highlight the handle; instrument arcs and bars update with accepted telemetry. No ornamental animation or continuous hidden redraws. A Player preset opts into these instruments; existing saved/custom layouts remain valid. Options provide individual switches, position locking and reset layout. Close buttons never take flight keyboard focus.

Implemented in `player_instrument.gd`: `speed`, `height`, `power`, `weather`, `fuel`, `trims` and `engine`. Coordinates use normalized available travel inside a 12 px viewport margin, accounting for the chosen widget scale. Settings accept only finite numeric pairs for these IDs. Saving occurs on drag release, not each motion. Existing 10 Hz snapshots feed visible instruments; battery readings share the existing sensor instance. The recent-speed graph is a 120-sample circular buffer. Each instrument skips unchanged relevant data, including paused snapshots; hidden instruments skip refresh. Session reset clears sampled extrema and sensor history; maximum speed continues sampling while its widget is closed. No per-frame widget polling is needed.

HUD-13-R1 appearance options apply to player instruments only: sizes 85/100/120%, background opacity 80/94/100%, and compact density. The minimum opacity preserves secondary text contrast against bright sky; text itself stays opaque. A shared, flight-owned MSDF copy of the bundled font keeps scaled text sharp without changing other UI or retaining a static font resource after teardown. Compact mode retains numerical details, status and trim bars. The All instruments default leaves the centre clear and raises Trims above the bottom-centre notices. Fuel uses `fuel_remaining_kg`, never live aircraft mass or an inferred voltage percentage; no unsupported flow/endurance is invented. RPM is the existing fixed-wing engine value (propeller shaft or turbine spool), not a general cross-vehicle auxiliary-index contract.

HUD-13-R2 adds a consistent icon/header strip, visible drag grip and rounded close target, a fine amber header rule, subtle static edge/shadow treatment and inset secondary readings. The whole header drags, except the close button. Gauges use ruled percentage rails, a finer compass rose, signed trim markers and a shaded recent-speed plot whose newest sample stays at the right edge. Units align with the main reading; compact mode keeps the same visual hierarchy. Cached shapes and ordinary Godot drawing keep the existing event-driven/10 Hz behavior; there are no new frame callbacks, blur shaders or ornamental animations.

HUD-13-R3 adds the opt-in **Classic cockpit** preset and five individually selectable analog instruments: `airspeed_dial`, `attitude`, `altimeter`, `heading`, `variometer`. They subclass the existing player widget frame for dragging, closing, scaling, opacity and persistence. The modern seven-instrument preset and legacy defaults stay unchanged. Five dial panels fit at 1080p at all three sizes; the central horizon is raised above notices. Compact mode shrinks the dial and hides its supplementary footer, retaining its numerical readout.

HUD-13-R4 refines both families with recessed secondary readings, icon surrounds, outlined close hover states and a visible locked-position symbol. Modern graphs gain faint time divisions and a restrained line halo; level rails gain finer subdivisions. Classic dials gain layered bevels, recessed fasteners, shaded/faceted needles, sharper hubs, 5° pitch-ladder subdivisions and a framed digital readout. Static details retain cached drawing, and lock feedback invalidates on changes only. Classic panels fit their current minimum content height after telemetry initialization so their dial rows stay aligned.

HUD-13-R5 separates configuration into Modern, Classic, Appearance and Other overlays. Preset, Units, tabs and Done stay outside the scrolling page. Hidden pages cannot capture focus; tab changes preserve settings. Short labels and a clamped 900×800 dialog expose all seven modern switches at 1080p. Settings application skips identical validated values and updates only affected visibility, style, lock or layout work. Resize bursts and content-fit requests are coalesced; style/position changes preserve telemetry cadence. The attitude widget owns a reusable 96-point circle rather than rebuilding it during every draw. Focused checks measure saves, layout passes, static/foreground redraws and cache equivalence; these reductions do not establish a whole-game FPS improvement.

HUD-13-R6 adds the opt-in **RC navigation** preset and Navigation settings page: `pilot_radar`, `wind_track` and
`cruise_efficiency`. They reuse player frame placement, close, lock and appearance controls. Radar uses horizontal
aircraft-minus-pilot offsets, a north-up automatic scale and a bounded recent trail. Drift compares ground course
with true heading; wind components are relative to horizontal nose heading. Electrical efficiency integrates
shared battery sensor power/current and ground speed over a rolling ten-second window, requiring two seconds at
3 m/s or faster. Unknown sensors, slow flight, gaps and resets invalidate it; it never estimates remaining range
or reads true SOC. Hidden efficiency stops sampling, histories are bounded, and static diagram faces remain
cached. The original modern/classic presets remain unchanged. Other research concepts remain proposals.

HUD-13-R7 adds the opt-in **Training** preset with `maneuver`, `glide`, and `flight_summary`. Its controls sit below
Navigation on the same page; a clamped 900×860 dialog fits all six switches in Spanish at the 1080p/default-text
target. The maneuver arc shows signed body-axis load and sampled extrema, with bank/AoA context. Glide shows
vertical speed, bounded history and a guarded instantaneous ground glide ratio; it does not infer aerodynamic
L/D, total-energy compensation or thermal centering. Constant-size flight aggregates keep distance and maxima
while widgets are closed, with a partial-distance flag for missing intervals. No automatic landing detection or
separate flight recorder is added. Existing presets and the flight kernel remain unchanged. See the
[training evidence](../research/flight-overlays/HUD-01-10/README.md#training-instruments-2026-10-24-hud-13-r7).

HUD-13-R8 separates modern graphic invalidation from text changes, including independent trim tracks and a
whole-second flight clock. Hidden overlay layers skip legacy presentation while charge, alarms and flight
aggregates continue sampling. Battery history remains bounded and is exported only for a visible detailed
panel. Reopening the layer requests fresh readings immediately. All 18 player headers support unlocked
double-click position reset without moving other widgets; clicks without movement do not save a layout.
The Flight tools tab groups navigation/training, with measurement and usage tooltips for every player widget.
Controlled draw, export and interaction checks are recorded in the existing evidence report.

HUD-13-R9 extends change-driven drawing to legacy transmitter, wind and detailed battery graphs. Compact
battery mode skips detail formatting; voltage/current histories invalidate independently and missing samples
compare stably. All 18 player widgets disable global input in `_ready`, after Godot's automatic registration;
only active drags enable it. Help text is shorter, legacy close buttons identify their panel, and tooltips supply
their measured height before popup placement. Checked-runner draw counts, native script profiling and repeated
preset-switch object censuses support the changes; see the R9 section of the existing evidence report.

HUD-13-R10 shares the shell's existing crystal shader through a static, noninteractive underlay. The native
frame keeps its border, shadow and layout; its center is drawn once by the shader at the selected 80/94/100%
opacity. Decorative header and hover accents are green, while telemetry accents remain amber. Classic faces
use neutral graphite and white without recoloring sky/earth or the heading reference. Caution chips and battery
bars use a separate amber token instead of the green focus token. [Verification and limits](../research/flight-overlays/HUD-01-10/README.md#shared-glass-and-classic-faces-2026-10-31-hud-13-r10--ui-22-r12).

HUD-13-R11 creates each crystal underlay only when first visible and retains it for reuse. Fresh Pilot, Player and
Classic layouts allocate 0, 4 and 5 surfaces respectively, down from 19 each. First-draw and lifecycle checks pass,
and the controlled rendered image is unchanged. This establishes fewer initial allocations, not faster frames;
see the [measurement and stability limits](../research/flight-overlays/HUD-01-10/README.md#lazy-glass-allocation-2026-10-31-hud-13-r11).

HUD-13-R12 refines classic faces with reference-led mounting plates, recessed fasteners, ivory scales and
counterweighted hands. It also separates VSI units from the scale and preserves long compact readouts on two
lines. The shared crystal shell and telemetry mappings remain intact; see the
[references and verification](../research/flight-overlays/HUD-01-10/README.md#mechanical-classic-detailing-2026-10-31-hud-13-r12).

The presentation reads existing telemetry only: TAS, pitch/bank, height above datum plus AGL, true heading and instantaneous vertical speed. No pressure setting, magnetic correction, pitot system, calibrated airspeed arcs, gyro dynamics or slip-ball indication is implied. Fixed needle scales mark overflow without discarding the numeric reading; missing values suppress the indication. The horizon clips the ground half-plane to a disc and handles inverted/vertical attitudes without a shader. Static faces have their own cached draw commands; only visible, changed values redraw the foreground at the existing 10 Hz rate. Unit/language changes invalidate the face. Research, source applicability and verification live in the [HUD-13-R3 evidence](../research/flight-overlays/HUD-01-10/README.md#classic-cockpit-2026-10-24-hud-13-r3).

See the [player instructions](../FIRST-LAUNCH.md#4-settings-and-flight-options) and [verification](../research/flight-overlays/HUD-01-10/README.md#player-instruments-2026-10-24-hud-13). Layout bounds are checked at 1080p, 1440p, 4K and the 720p fallback; native visual review is at 1080p. This does not qualify GPU performance or pilot readability on other hardware.

References: [EdgeTX widgets](https://manual.edgetx.org/v2.10/color-radios/screen-settings/widgets), [flight extrema](https://manual.edgetx.org/v2.10/color-radios/model-settings/telemetry/common-telemetry-sensors), and [Godot Control input](https://docs.godotengine.org/en/stable/classes/class_control.html). The design adopts configurable sensor widgets and flight-scoped maxima; it retains this simulator's existing charge-estimation policy rather than inferring percentage from voltage.

- Pilot reading at 720p and 1080p on target hardware (HUD-12).
- The developer preset may overlap at 720p with long diagnostic lines; only "on screen" is checked there.
- Legacy overlays retain fixed anchors. Player instruments support dragging and a common size setting; individual per-widget scale is not implemented. Compact mode is the dense-layout fallback at 720p; custom placement can overlap.
- Warning thresholds and the transmitter view are presentation aids, not validated against a real flight.
