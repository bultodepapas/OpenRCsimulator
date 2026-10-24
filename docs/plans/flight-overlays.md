# Flight overlays plan

**Date:** 2026-10-13. **Status:** HUD-00…10 implemented (b0b0347); HUD-11 done with 720p and 1080p rendered captures; HUD-05-R1/R2 add selectable JETI and Radiolink views; HUD-12 waits for owner reading on target hardware. **Prefix:** HUD-00…HUD-12 ([registry](../README.md#tracks-plans-and-step-ids)). **Owner:** flight-overlays track, under the main line's acceptance. Supersedes [MENU-REDESIGN-PLAN](../MENU-REDESIGN-PLAN.md) UI-27 (D1).
**Owns:** `app/render/overlays/`, `app/ui/overlays_dialog.gd`, `app/tests/test_overlay_*.gd`, `docs/research/flight-overlays/`.
**Coordinated, not owned:** the seams in `app/main.gd` (main line), `app/app_root.gd`, `app/ui/pause_menu.gd`, `app/ui/controls_reference.gd`, `app/app_state/preferences.gd`, `app/i18n/es.po` (menu track). `render/hud.gd` and `render/panel.gd` are unchanged and still build the diagnostic text.
**Evidence:** [HUD-01…10](../research/flight-overlays/HUD-01-10/README.md), [HUD-05-R1](../research/flight-overlays/HUD-05-R1/README.md), [HUD-05-R2](../research/flight-overlays/HUD-05-R2/README.md).

## 1. What exists

Home flights provide nine independent overlays on one `CanvasLayer` (`render/overlays/overlay_manager.gd`). Each has a title and an × that closes only that overlay; the × never takes keyboard focus. Diagnostics docks beside the control guide and below active warning chips to keep their headers accessible.

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

Presets: Off, Pilot (O1–O4 + O8, default), Full (O1–O5 + O8), Developer (all), Custom (any other set). **F2** cycles Off → Pilot → Full → Developer; **F3** toggles O6+O7; Pause → **Flight overlays** sets overlays, units and stick mode and previews them live above the paused flight. Settings live under `[hud]` in `settings.cfg` (additive; older builds ignore it). Named presets include the guide; saved custom sets retain their explicit visibility choices.

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
| far | slant distance beyond where the 6° minimum auto-zoom FOV shows the span below 30 px at 720 px (Stik ≈ 349 m) | `Spec.AUTO_ZOOM`, model span |
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

## 3. Decisions

| ID | Question | Chosen (2026-10-13) |
| --- | --- | --- |
| D1 | Replace UI-27? | Yes |
| D2 | Default preset | Pilot |
| D3 | Default units | By language (en imperial, es metric) |
| D4 | Default stick mode | Mode 2 |
| D5 | Stall source | Aircraft envelope `a1`/`n1`, 2° margin |
| D6 | Height reference | Above the ground under the aircraft |

## 4. Open work and limits

- Pilot reading at 720p and 1080p on target hardware (HUD-12).
- The developer preset may overlap at 720p with long diagnostic lines; only "on screen" is checked there.
- Overlays have fixed anchors; dragging and per-overlay scale are not implemented.
- Warning thresholds and the transmitter view are presentation aids, not validated against a real flight.
