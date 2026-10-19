# BAT-14/15 — Radio-style battery telemetry and the O9 Battery overlay

2026-10-19 · **Status:** software verified on fixture `electrical_state()` dictionaries and on live synthetic `ocv_resistance` and Timber `pack_ecm` flights; not physically validated. Every threshold and resolution below is a declared presentation default, not a measurement. Plan: [battery realism §6](../../../plans/battery-realism.md#6-telemetry-hud-and-pilot-information). Overlay architecture: [flight overlays](../../../plans/flight-overlays.md).

## What was built

| File | Role |
| --- | --- |
| `app/render/overlays/battery_sensors.gd` | BAT-14. Pure `RefCounted` sampler: sensor emulation, consumed mAh, radio-side remaining %, debounced alarms, 60 s history |
| `app/render/overlays/battery_panel.gd` | BAT-15. O9 "Battery" widget on the `overlay_frame.gd` pattern (title, rows, ×) |
| `app/render/overlays/overlay_manager.gd` | Places O9, feeds the sensor at the 10 Hz refresh, adds the sensor alarms to the warnings, writes the developer truth row; `snapshot()` now carries `battery` |
| `app/render/overlays/overlay_settings.gd` | `battery` id in Pilot, Full and Developer; `battery_detailed()` |
| `app/render/overlays/telemetry.gd` | `battery_warnings()`, `with_battery_warnings()`, `BATTERY_CODES` |
| `app/render/overlays/warnings_bar.gd` | Chip texts and danger/caution class of the new codes |
| `app/ui/overlays_dialog.gd` | "Battery" switch |
| `app/i18n/es.po` | Spanish for every new text |
| `app/tests/test_overlay_battery.gd` | Fixture checks of the sensor, warnings, panel and layout (below) |
| `app/tests/test_overlay_battery_flight.gd` | A live `--electric-demo=4s-battery` flight through `snapshot()` |

### Sensor API (`battery_sensors.gd`)

```gdscript
func reset() -> void
func update(time_s: float, state: Dictionary) -> Dictionary   # state: electrical_state() or {}
static func empty() -> Dictionary                              # the reading before any sample
static func quantize(value: float, step: float) -> float
```

`update()` returns `{valid, kind ("pack_ecm" | "legacy"), display_name, chemistry, series, parallel, capacity_mah, time_s, pack_voltage_v, cell_avg_v, cell_min_v, current_a, power_w, used_mah (int), used_mah_raw, remaining_pct, temperature_c, esc_state, alarms: Array[String], history_v, history_a}`. Unknown values are `NAN` (the panel hides them). It never reads `soc` or `soc_weak`.

- A sample is taken when at least `SAMPLE_PERIOD_S − SAMPLE_SLACK_S` of simulation time has passed; between samples the last reading holds.
- Used mAh integrates the **held current sample** over the time to the next sample (zero-order hold), like a radio's consumption sensor. It never reads the true consumed charge.
- Remaining % = `100·(1 − used_mAh/capacity_mAh)`, clamped to 0…100. Capacity is the rated capacity (`pack_ecm`) or, for the older synthetic packs, the charge they start with.
- Time running backwards (restart, rollback) or a different pack restarts the sensor.
- The older kind (no `battery_kind`) gets V, A, mAh and % only, and no sensor alarms.

### Declared presentation defaults

| Quantity | Value | Analogue / source |
| --- | --- | --- |
| Sample period, refresh slack | 0.1 s, 0.01 s | EdgeTX telemetry frame (BAT-00 F8); slack absorbs 1/240 s tick and frame jitter |
| Resolutions | 0.01 V, 0.1 A, 1 K, 1 mAh (nearest) | VFAS, Curr, Tmp1, Fuel |
| Cell warning / critical | 3.5 V / 3.3 V on the **loaded** lowest cell (average cell without a lowest-cell sensor) | Betaflight documentation style (BAT-00 F7) |
| Voltage alarm hold, release | 2.0 s continuously below; released above threshold + 0.05 V | estimated |
| Used-capacity warning | 80 % of the capacity | plan §6.3 |
| Pack hot | ≥ 333.15 K (60 °C), cleared below 59 °C | estimated, not a cited cell limit |
| Voltage alarms | LiPo, LiHV, Li-ion only; LiFePO4 and NiMH use the mAh alarm (flat curves, plan §5.1) | plan §5.1 |
| History | 600 samples (60 s) | sparkline only |

### Alarms and warning codes

| Sensor alarm | Warning code | Chip | Class |
| --- | --- | --- | --- |
| `exhausted` | `battery_empty` | BATTERY EMPTY | danger |
| `cell_critical` | `battery_critical` | BATTERY CRITICAL | danger |
| `lvc` (ESC `soft_cut` or `hard_cut`) | `battery_lvc` | LVC · land now | danger |
| `cell_warning` or `used_capacity` | `battery` | BATTERY LOW | caution; dropped while critical or empty |
| `hot` | `battery_hot` | BATTERY HOT | caution |

A `pack_ecm` pack raises chips only from these alarms. `snapshot()` is static and passes no alarms, so the manager replaces the battery codes with `Telemetry.with_battery_warnings()`; they keep their slot before EXPERIMENTAL. The sensor runs while O9 is closed. The older kind keeps the HUD-09 rule (BATTERY LOW below 20 % model SOC or when exhausted).

### Overlay layout and presets

- O9 is in Pilot (compact: one line `V · A · mAh · %`), Full and Developer (detailed: pack V, V/cell, lowest cell, A, W, temperature, used/rated mAh, bar with %, ESC LVC chip, 60 s V and A sparklines drawn with `draw_polyline`).
- The layout is detailed whenever the Telemetry overlay (O5) is shown. It is derived from the saved visible set, so the existing `[hud]` keys persist it.
- O9 is docked centre right: against the edge in Pilot (free there), left of Telemetry in Full/Developer. Below about 640 px it stays on screen over Telemetry.
- Hidden when the aircraft has no dynamic battery or the battery state is not `ok`.
- Temperature reads °F with imperial units (EdgeTX imperial setting), °C otherwise.
- True SOC (average and weakest cell) appears only in the Developer Diagnostics overlay (O6), as a separate row.

## Verification

Commands (Godot 4.7.2, headless, `--audio-driver Dummy`, 60 s limit each):

```sh
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script res://tests/test_overlay_battery.gd
```

| Test | Result |
| --- | --- |
| `test_overlay_battery.gd` (new) | 123 checks, 0 failed |
| `test_overlay_manager.gd` (2 expectations updated for the new id) | 97 checks, 0 failed |
| `test_overlay_telemetry.gd` | 38 checks, 0 failed |
| `test_overlay_units.gd` | 29 checks, 0 failed |
| `test_overlay_battery_flight.gd` (synthetic `ocv_resistance` and Timber `pack_ecm` flights) | 10 checks, 0 failed |
| UI tests touching the dialog, pause and catalogue | `test_ui_modal_responsive` 560 cases 0 failures; `test_ui_pause`, `test_ui_help`, `test_ui_settings_integration` pass; `test_aircraft_catalog` 100 checks 0 failed |
| Parse check (`--check-only`) of every script touched by BAT-04…15 | 0 failures; `check_transcendentals.py` passes |

`test_overlay_battery.gd` covers:
- quantization, held readings between samples, the refresh slack and no `-0.0`
- used mAh: constant 36 A for 100 s = 1000 mAh with the true consumed charge set to 0; a 10 A + 1 A/s ramp over 60 s gives the left Riemann sum 2397 A·s, exactly k·T·Δt/2 = 0.833 mAh below the analytic 2400 A·s; jittered sample times integrate exactly
- the same current history with true SOC 0.95 and 0.05 gives the same % and alarms; % clamps at 0
- alarm timing: warning at exactly 2.0 s, a 1.5 s sag raises nothing, recovery restarts the timer, release only above +0.05 V, critical over warning, average-cell fallback, no voltage alarms for LiFePO4/NiMH, used-mAh alarm at 80 %
- LVC, hot with one-step hysteresis, exhausted, code order and classes, slot before EXPERIMENTAL
- the older kind: readings, capacity, no alarms, HUD-09 rule kept
- history bounded to 600, sparkline points bounded and inside their box
- presets, dialog name, Spanish catalog for every new text, trace and bar colours ≥ 3:1 on the backplate
- O9 hides without a battery, compact in Pilot, detailed in Full, Developer truth row, shrink back to compact, × close, the older kind
- no overlap with any shown overlay or the Home latency marker at 1280×720 and 1920×1080 (Pilot, Full, en and es); O9 inside a 640×480 screen; all eleven chips wrap inside the warnings bar
- warnings over time: BATTERY LOW at 3.0 s for a sag from 1.0 s, a stale snapshot code replaced, alarms still reach the bar with O9 closed

`test_overlay_battery_flight.gd` flies the synthetic 4S `ocv_resistance` pack: O9 is shown and detailed in Full, reads the session's pack voltage and used/rated mAh, shows no cell or temperature values, and no "SOC" text appears outside Diagnostics. A second case flies the Timber in battery mode `pack` through the product route (`--aircraft=turbo-lumber-evolution --battery=pack`): the session is `pack_ecm`, O9 is detailed in Full with the V/cell, lowest-cell and temperature rows from the sensors, and no "SOC" text appears outside Diagnostics.

Deliberate mutations on a disposable copy of `app/` (each restored after the run), all caught: fuel from the true charge, % from true SOC, no hold, no hysteresis, SOC rule for `pack_ecm`, unbounded history, voltage alarms on flat chemistries, manager ignoring alarms, integrating the new sample (right Riemann), no Telemetry shift, no narrow-screen clamp, lowest cell ignored. One further mutant (removing only the left-offset shift) was equivalent: the minimum size keeps the box shifted.

No rendered captures: Xvfb is not reliable on this VM. Layout evidence is the rectangle checks above.

## Limits and open items

- **Not logged.** The plan's BAT-14 proof "emulated vs true columns logged" needs trace and `.orfl` columns (physics main line). The sampler is fed at the overlay's 10 Hz frame-time refresh, so its sample instants are not replay-identical; logging needs a tick-synchronous feed from the session.
- **Not configurable.** Thresholds are constants, not per-aircraft telemetry profiles or transmitter settings. There is no voltage-based % with R compensation (PX4 style), no detected-cell mismatch alarm and no "pack unsafe" pre-flight alarm.
- **Rollback.** A rollback to an earlier time restarts the count at 0, unlike a real radio, which knows nothing of rollbacks.
- **Layout.** The detailed layout is tied to the Telemetry overlay. At 640 px the detailed O9 covers Telemetry (all overlays already overlap there).
- **Diagnostics text.** `main.gd`'s `--electric-demo` diagnostics line still prints the model SOC; it shows only in the Developer Diagnostics overlay.
- **HUD plan.** [flight-overlays.md](../../../plans/flight-overlays.md) §1 still lists O1–O8 and the old battery trigger; the HUD owner should add the O9 row and the codes above and resolve the DR "O8 OSD" id (decision D12).
- **Pilot acceptance.** Readability and thresholds await an owner reading in flight, like HUD-12.
