# Aircraft lighting

FW-35c, 2026-10-19. Aircraft lights are presentation state, shared by the fixed-wing flight route, helicopter route and Home previews. They never change flight physics, battery consumption or recorded control inputs. [Verification](research/field-world/FW-35c/README.md).

## Pilot controls and defaults

Use **L** or the controller's **Cycle lights** action. Airplanes retain ALL → NAV → OFF; the first daytime press selects ALL. NAV includes navigation lights and strobes. The helicopter retains AUTO → ALL → NAV → OFF → AUTO. Keyboard repeat does not cycle. The flight HUD shows the current resolved mode and marks automatic operation.

Automatic lights turn fully ON at **17:30 local simulator time**, including flights loaded after that time. Time comes from the accepted fixed `time_of_day_config.local_seconds`, or the field world's civil clock. Flowing worlds use the exact simulation clock and configured time scale, independently of the sky's update cadence. The OS clock and timezone are never used. The legacy fixed-sun scene has no civil time and retains its daytime default.

The established solar rules continue before 17:30 and after midnight: airplanes light below 6° solar elevation; the helicopter retains its smooth fade from 3° to −4°. Dawn therefore keeps its existing lighting behavior. Manual ALL, NAV or OFF takes priority over every time/solar update, paused time edit and sky/moon change.

The override belongs to one flight. The existing session `resetting` boundary clears it: successful restart, aircraft-data reload or checkpoint restoration resumes automatic selection. Rejected edits/reloads do not clear it. Starting another flight or changing aircraft starts automatic selection independently; no override is saved in preferences or physical checkpoints. A helicopter `--heli-lights=all|nav|off` supplies an initial override; its next session reset resumes AUTO.

## Shared interface

[`aircraft_light_state.gd`](../app/render/world/aircraft_light_state.gd) is a persistent, flight-owned `RefCounted`. It owns timing and precedence; adapters own luminous nodes and rendering.

| API/state | Contract |
| --- | --- |
| `configure_evening(seconds)` | Seconds since local midnight, 0–86399; default 63000 (17:30). Invalid values preserve the accepted setting. |
| `set_mode("auto"|"all"|"nav"|"off")` | AUTO clears the override; other choices establish it. Invalid modes preserve state. |
| `update(local_seconds, daytime_gain)` | Resolve the current state. Adapter supplies the existing solar policy as a 0–1 gain; return value reports output changes. NAN civil time disables only the evening rule. |
| `selection`, `active_mode`, `gain` | User selection, resolved ALL/NAV/OFF and resolved light intensity. Manual ON always uses gain 1. |
| `reset()` | Resume AUTO without changing configuration. Sample the reset clock immediately afterward. |
| `cycle_mode(include_auto=false)` | Existing airplane cycle; `true` includes the helicopter AUTO detent. |

`World.aircraft_local_seconds(config, clock_s)` and `World.aircraft_sun_elevation(snapshot)` adapt both time systems. Fixed TOD uses geometric solar elevation, rather than the clamped rendering Sun. `World.dress_aircraft(...)` is an automatic-only preview helper; a flight keeps its own persistent state so repeated updates preserve manual choices.

The airplane route exposes `set_aircraft_lights(mode)` for UI consumers. Its keyboard/controller routes share the same selection operation. It creates the kit lazily, after measuring model/shadow geometry, then changes visibility only when the resolved mode changes. Dynamic anchors still follow articulated parts; gear gates can suppress a landing beam even in ALL. UI state reflects mode changes even when diagnostics are hidden.

## Adopting the standard

Catalog airplanes already use the common route, including the Stik powerplant variants. No aircraft-ID branch or new scene script is required. Keep all existing geometry, materials, hinge names and generators.

The default kit derives its positions from the model. Existing optional root metadata `light_anchors` overrides `nav_left`, `nav_right`, `nav_tail` and `landing`. Each anchor can supply a model-local `position`, a root-relative `follow` NodePath, a `follow_offset`, and `gear_gated`. The P-51 uses these existing bindings. Preserve their authoring pipeline when changing anchors.

For different equipment, the model root can declare `light_groups`, an Array containing any supported subset of `navigation`, `strobe`, `landing`, `orientation`. Omitted metadata enables all four. Landing includes the beam and its lamp sprite; orientation includes the emissive wing/belly strips. Unsupported groups stay dark in every mode.

Authored luminous effects can use `AircraftLights.bind_groups(kit, bindings, supported_groups)`. `bindings` maps group names to Arrays of `Node3D` references or kit-relative NodePaths. Bind the emitted glow and corresponding light together; bind only luminous presentation nodes, leaving reflective lens geometry intact. Invalid or duplicate references are rejected before replacing accepted bindings. Successful binding starts OFF; apply the flight state's resolved mode afterward. Instances retain their own nodes/materials; binding never edits shared source materials.

A different aircraft adapter should own one shared light-state instance, sample its authoritative clock and existing solar gain, apply `active_mode`/`gain` to its supported effects, and reset at its session boundary. The helicopter adapter demonstrates this while retaining rotor phase, exposure caps, its armed beacon gate and body-optic fade. Keep animation updates separate from selection changes.

## Checks

Run the focused suite with the pinned engine:

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_aircraft_light_control.gd
```

For native before/after images, omit `--headless` and append `-- --capture-aircraft-lights=<absolute-output-directory>`. Use an isolated APPDATA directory for native test runs. The suite covers every fixed-wing visual family and the helicopter, actual input handlers, exact threshold crossings, manual precedence, dawn/daylight policy, new flights, resets, data reloads, Home changes, bounded attachment and configurable group references. Existing `test_night_kit.gd`, `test_p51_lights.gd` and `test_heli_night_lights.gd` retain geometry, motion, gate and emissive checks.
