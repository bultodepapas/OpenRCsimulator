# BAT-14/15: radio-style battery telemetry (render/overlays/battery_sensors.gd) and the O9 Battery overlay
# (render/overlays/battery_panel.gd) on fixture electrical_state() dictionaries: quantization, sampled mAh against
# the analytic integral, a remaining % independent of the model's true SOC, alarm debounce and hysteresis, warning
# codes, the older ocv_resistance kind, presets, hiding, the bounded sparkline and the layout at 640, 1280 and 1920 px.
# A live flight scene is in test_overlay_battery_flight.gd.
# Run: godot --headless --path . --script res://tests/test_overlay_battery.gd
extends SceneTree

const Sensors := preload("res://render/overlays/battery_sensors.gd")
const BatteryPanel := preload("res://render/overlays/battery_panel.gd")
const Manager := preload("res://render/overlays/overlay_manager.gd")
const Settings := preload("res://render/overlays/overlay_settings.gd")
const Telemetry := preload("res://render/overlays/telemetry.gd")
const WarningsBar := preload("res://render/overlays/warnings_bar.gd")
const Frame := preload("res://render/overlays/overlay_frame.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const LatencyPatch := preload("res://input/latency_patch.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _near(a: float, b: float, tol := 1e-9) -> bool:
	return absf(a - b) <= tol


func _initialize() -> void:
	TranslationServer.set_locale("en")
	_run()


func _run() -> void:
	_quantization()
	_fuel()
	_radio_percent()
	_voltage_alarms()
	_other_alarms()
	_legacy()
	_history()
	_history_policy()
	_settings_and_texts()
	await _panel()
	await _layout()
	await _warnings_in_flight()
	await _hidden_presentation()
	print("overlay battery: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


func _history_policy() -> void:
	var compact := Sensors.new()
	var full := Sensors.new()
	var scalar := {}
	var detailed := {}
	for i in 650:
		var state := _ecm({pack_current_a = 20.0 + float(i % 5)})
		scalar = compact.update(i * 0.1, state, false)
		detailed = full.update(i * 0.1, state)
	_check("scalar exports omit both history arrays", scalar.history_v.is_empty() and scalar.history_a.is_empty())
	_check("history policy preserves consumed charge and alarms", scalar.used_mah_raw == detailed.used_mah_raw and scalar.alarms == detailed.alarms)
	var reopened := compact.update(64.9, _ecm())
	_check("reopening exports the complete bounded history", reopened.history_v.size() == 600 and reopened.history_a == detailed.history_a)
	reopened.history_a[0] = -999.0
	reopened.alarms.append("caller_only")
	var isolated := compact.update(64.9, _ecm())
	_check("export mutation cannot change sensor buffers or alarms", isolated.history_a[0] != -999.0 and not isolated.alarms.has("caller_only"))
	compact.reset()
	_check("reset clears omitted history too", compact.update(0.0, _ecm()).history_v.size() == 1)


func _hidden_presentation() -> void:
	var manager := Manager.new({preset = "full"}, "en")
	root.add_child(manager)
	manager.refresh_numbers(_snapshot(_ecm({time_s = 0.0})))
	var panel: Control = manager.frames.battery
	var old_voltage: String = panel.values.pack_v.text
	var old_footer: String = manager.frames.transmitter.footer.text
	var old_codes: PackedStringArray = manager.frames.warnings.codes.duplicate()
	manager.visible = false
	var next := _snapshot(_ecm({time_s = 1.0, bus_voltage_v = 13.0}), PackedStringArray(["stall"]))
	next.radio_status = "New radio status"
	next.telemetry.airspeed = 55.0
	manager.refresh_numbers(next)
	_check("hidden layer skips battery, transmitter and warning presentation", panel.values.pack_v.text == old_voltage and manager.frames.transmitter.footer.text == old_footer and manager.frames.warnings.codes == old_codes)
	_check("hidden layer still samples charge and peak speed", manager._battery_reading.used_mah_raw > 0.0 and manager.peak_airspeed == 55.0)
	_check("hidden detailed battery does not export histories", manager._battery_reading.history_v.is_empty())
	manager.visible = true
	_check("showing layer requests immediate refresh", is_inf(manager._since_text))
	manager.refresh_numbers(next)
	_check("reappearing panel catches up with full history", panel.values.pack_v.text == "13.00 V" and panel.reading.history_v.size() == 2 and manager.frames.transmitter.footer.text == "New radio status")
	_check("reappearing warnings reconcile their displayed codes", manager.frames.warnings.codes.has("stall"))
	manager.set_preset("pilot")
	manager.refresh_numbers(next)
	_check("compact visible battery omits unused history exports", manager._battery_reading.history_v.is_empty())
	manager.queue_free()
	await process_frame


## A 4S 3200 mAh LiPo pack_ecm state as the physics side publishes it (BAT-06…11 contract).
func _ecm(changes := {}) -> Dictionary:
	var s := {
		ok = true, battery_kind = "pack_ecm", pack_id = "lipo-4s1p-3200-c30-class",
		display_name = "4S 3200 mAh LiPo (30C class)", chemistry = "lipo", series = 4, parallel = 1, rated_capacity_ah = 3.2,
		bus_voltage_v = 15.2, pack_current_a = 20.0, auxiliary_current_a = 0.3, pack_terminal_power_w = 304.0,
		ocv_v = 16.0, polarization_v = 0.1, cell_voltage_avg_v = 3.8, cell_voltage_min_v = 3.78, soc = 0.8, soc_weak = 0.78,
		temperature_k = 300.0, ambient_k = 293.15, consumed_charge_c = 0.0, remaining_charge_c = 11520.0,
		terminal_energy_j = 0.0, pack_heat_j = 0.0, exhausted = false, esc_state = "normal", esc_limit = 1.0,
		esc_detected_cells = 4, esc_cutoff_voltage_v = 12.8, esc_sensed_voltage_v = 15.2,
		tick = 0, time_s = 0.0, rpm = 9000.0, duty = 0.6, effective_duty = 0.6, enabled = true,
	}
	s.merge(changes, true)
	return s


## The older synthetic ocv_resistance kind: no battery_kind, cells, temperature or ESC fields. 3200 mAh in all.
func _legacy_state(changes := {}) -> Dictionary:
	var s := {
		ok = true, soc = 0.9, bus_voltage_v = 16.4, pack_current_a = 12.0, auxiliary_current_a = 0.0, ocv_v = 16.8,
		consumed_charge_c = 1152.0, remaining_charge_c = 10368.0, terminal_energy_j = 0.0, pack_heat_j = 0.0,
		exhausted = false, duty = 0.5, rpm = 8000.0, time_s = 0.0, tick = 0,
	}
	s.merge(changes, true)
	return s


## Feeds `sensors` one state per 0.1 s sample from sample `from` to `to` (inclusive); returns the last reading.
func _feed(sensors: RefCounted, from: int, to: int, changes: Dictionary) -> Dictionary:
	var r := {}
	for k in range(from, to + 1):
		r = sensors.update(k * 0.1, _ecm(changes))
	return r


func _is_step(value: float, step: float) -> bool:
	return _near(value / step, roundf(value / step), 1e-6)


func _quantization() -> void:
	var sensors := Sensors.new()
	var state := _ecm({ bus_voltage_v = 14.6234, pack_current_a = 38.4567, cell_voltage_avg_v = 3.65589,
		cell_voltage_min_v = 3.6149, temperature_k = 304.46 })
	var before := state.duplicate(true)
	var r: Dictionary = sensors.update(0.0, state)
	_check("pack voltage to 0.01 V", _near(r.pack_voltage_v, 14.62) and _is_step(r.pack_voltage_v, Sensors.VOLTAGE_STEP_V), str(r.pack_voltage_v))
	_check("current to 0.1 A", _near(r.current_a, 38.5) and _is_step(r.current_a, Sensors.CURRENT_STEP_A), str(r.current_a))
	_check("average and lowest cell to 0.01 V", _near(r.cell_avg_v, 3.66) and _near(r.cell_min_v, 3.61), "%s %s" % [r.cell_avg_v, r.cell_min_v])
	_check("pack temperature to 1 K, shown in °C", _near(r.temperature_c, 31.0), str(r.temperature_c))
	_check("power is sampled V × sampled A", _near(r.power_w, 14.62 * 38.5, 1e-9), str(r.power_w))
	_check("the sensor never changes its input", state == before)
	_check("the reading carries no true SOC", not r.has("soc") and not r.has("soc_weak"))
	var held: Dictionary = sensors.update(0.05, _ecm({ bus_voltage_v = 12.0, pack_current_a = 5.0 }))
	_check("between samples the last reading holds", _near(held.pack_voltage_v, 14.62) and _near(held.time_s, 0.0))
	var next: Dictionary = sensors.update(0.095, _ecm({ bus_voltage_v = 12.0, pack_current_a = 5.0 }))
	_check("a sample is due within the refresh slack (0.095 s)", _near(next.pack_voltage_v, 12.0) and _near(next.time_s, 0.095))
	var paused: Dictionary = sensors.update(0.095, _ecm({ bus_voltage_v = 11.0 }))
	_check("no new sample while simulation time stands still", _near(paused.pack_voltage_v, 12.0))
	var tiny: Dictionary = Sensors.new().update(0.0, _ecm({ pack_current_a = -0.01 }))
	_check("a rounded −0 reads 0.0, never \"-0.0\"", "%.1f" % tiny.current_a == "0.0", "%.1f" % tiny.current_a)
	_check("missing fields stay unknown", is_nan(Sensors.new().update(0.0, _ecm({ temperature_k = null })).temperature_c))
	_check("a state that is not ok gives no reading", not Sensors.new().update(0.0, { ok = false }).valid)


func _fuel() -> void:
	# Constant 36 A for 100 s: 3600 A·s = 1000 mAh. The state's true consumed charge is deliberately 0.
	var steady := Sensors.new()
	var r := _feed(steady, 0, 1000, { pack_current_a = 36.0, consumed_charge_c = 0.0 })
	_check("constant 36 A for 100 s reads 1000 mAh", r.used_mah == 1000 and _near(r.used_mah_raw, 1000.0, 1e-9), "%d %.12f" % [r.used_mah, r.used_mah_raw])
	# A ramp I = 10 A + 1 A/s · t over 60 s. Analytic ∫ = 10·60 + 60²/2 = 2400 A·s. The sensor holds each sample until
	# the next (zero-order hold), so its sum is the left Riemann sum: 2400 − k·T·Δt/2 = 2397 A·s.
	var ramp := Sensors.new()
	for k in range(0, 601):
		r = ramp.update(k * 0.1, _ecm({ pack_current_a = 10.0 + 1.0 * (k * 0.1) }))
	var analytic := 2400.0 / 3.6
	var riemann := 2397.0 / 3.6
	_check("ramp: the sensor's integral is the sampled (Riemann) sum", _near(r.used_mah_raw, riemann, 1e-6), "%.9f vs %.9f" % [r.used_mah_raw, riemann])
	_check("ramp: the sampling lag is k·T·Δt/2 = 0.833 mAh below the analytic integral",
		_near(analytic - r.used_mah_raw, 1.0 * 60.0 * 0.1 / 2.0 / 3.6, 1e-6), "%.9f" % (analytic - r.used_mah_raw))
	# Refresh jitter: irregular sample times still integrate the held current over the elapsed time exactly.
	var jitter := Sensors.new()
	var last_t := 0.0
	for k in range(0, 301):
		last_t = k * 0.1 + 0.004 * float((k * 7) % 3 - 1) if k > 0 else 0.0
		r = jitter.update(last_t, _ecm({ pack_current_a = 20.0 }))
	_check("jittered refresh times: held current × elapsed time", _near(r.used_mah_raw, 20.0 * last_t / 3.6, 1e-9), "%.9f" % r.used_mah_raw)
	r = steady.update(0.0, _ecm({ pack_current_a = 36.0 }))
	_check("time running backwards (a restarted flight) restarts the count", r.used_mah == 0)
	var other := Sensors.new()
	_feed(other, 0, 100, {})
	r = other.update(10.1, _ecm({ pack_id = "lipo-3s1p-2200" }))
	_check("a different pack restarts the count", r.used_mah == 0)


func _radio_percent() -> void:
	var full := Sensors.new()
	var empty := Sensors.new()
	var a := {}
	var b := {}
	for k in range(0, 1001):
		a = full.update(k * 0.1, _ecm({ pack_current_a = 36.0, soc = 0.95, soc_weak = 0.95 }))
		b = empty.update(k * 0.1, _ecm({ pack_current_a = 36.0, soc = 0.05, soc_weak = 0.01 }))
	_check("remaining % = 100·(1 − used/rated): 1000 of 3200 mAh = 68.75 %", _near(a.remaining_pct, 68.75), str(a.remaining_pct))
	_check("the same current history gives the same %, whatever the true SOC", a.remaining_pct == b.remaining_pct and a.alarms == b.alarms)
	_check("a pack near true empty raises no chip while the radio sees no alarm",
		Telemetry.battery_warnings(_ecm({ soc = 0.05, soc_weak = 0.01 }), b.alarms).is_empty())
	_check("pack_ecm: snapshot() warnings (no sensor alarms) never use the true SOC",
		Telemetry.warnings({ airspeed = 15.0, alpha_deg = 0.0, height_agl = 40.0, vertical_speed = 0.0, distance_pilot = 80.0 },
			{ battery = _ecm({ soc = 0.02 }) }).is_empty())
	var over := Sensors.new()
	var r := {}
	for k in range(0, 2001):
		r = over.update(k * 0.1, _ecm({ pack_current_a = 100.0 }))
	_check("remaining % clamps at 0 beyond the rated capacity", r.remaining_pct == 0.0 and r.used_mah > 3200, "%d %.2f" % [r.used_mah, r.remaining_pct])


## The first sample index at which `alarm` is in the reading, feeding `cell` V on both cell sensors from `from`.
func _first(sensors: RefCounted, alarm: String, from: int, to: int, cell: float, changes := {}) -> int:
	for k in range(from, to + 1):
		var state := { cell_voltage_avg_v = cell + 0.02, cell_voltage_min_v = cell }
		state.merge(changes, true)
		var r: Dictionary = sensors.update(k * 0.1, _ecm(state))
		if r.alarms.has(alarm):
			return k
	return -1


func _voltage_alarms() -> void:
	var s := Sensors.new()
	_feed(s, 0, 99, {})
	_check("warning sounds 2.0 s after the lowest cell drops below 3.5 V (10.0 → 12.0 s)", _first(s, "cell_warning", 100, 200, 3.45) == 120)
	_check("no critical at 3.45 V", not s.update(12.1, _ecm({ cell_voltage_min_v = 3.45 })).alarms.has("cell_critical"))
	_check("hysteresis: still on at 3.54 V (< 3.5 + 0.05)", s.update(12.2, _ecm({ cell_voltage_min_v = 3.54 })).alarms.has("cell_warning"))
	_check("released at once above 3.55 V", not s.update(12.3, _ecm({ cell_voltage_min_v = 3.56 })).alarms.has("cell_warning"))

	var dip := Sensors.new()
	_feed(dip, 0, 99, {})
	_check("a 1.5 s sag below 3.5 V raises nothing", _first(dip, "cell_warning", 100, 115, 3.4) == -1)
	_check("recovery restarts the hold timer", _first(dip, "cell_warning", 116, 125, 3.6) == -1
		and _first(dip, "cell_warning", 126, 200, 3.4) == 146)

	var crit := Sensors.new()
	_feed(crit, 0, 9, {})
	_check("critical sounds 2.0 s below 3.3 V", _first(crit, "cell_critical", 10, 100, 3.25) == 30)
	var r: Dictionary = crit.update(3.1, _ecm({ cell_voltage_min_v = 3.25 }))
	_check("critical and warning both on", r.alarms.has("cell_critical") and r.alarms.has("cell_warning"))
	_check("critical replaces BATTERY LOW: one danger chip", Array(Telemetry.battery_warnings(_ecm(), r.alarms)) == ["battery_critical"])
	r = crit.update(3.2, _ecm({ cell_voltage_min_v = 3.4 }))
	_check("above 3.35 V critical clears, the warning stays", not r.alarms.has("cell_critical") and r.alarms.has("cell_warning"))

	var average := Sensors.new()
	_feed(average, 0, 9, { cell_voltage_min_v = null })
	_check("without a lowest-cell sensor the average cell is used", _first(average, "cell_warning", 10, 60, 3.4, { cell_voltage_avg_v = 3.4, cell_voltage_min_v = null }) == 30)
	var derived := Sensors.new().update(0.0, _ecm({ cell_voltage_avg_v = null, cell_voltage_min_v = null, bus_voltage_v = 14.8 }))
	_check("average cell falls back to pack voltage / series", _near(derived.cell_avg_v, 3.7) and is_nan(derived.cell_min_v))

	for chemistry: String in ["lifepo4", "nimh"]:
		var flat := Sensors.new()
		var seen := false
		var first_used := -1
		for k in range(0, 900):
			var reading: Dictionary = flat.update(k * 0.1, _ecm({ chemistry = chemistry, rated_capacity_ah = 1.0,
				pack_current_a = 36.0, cell_voltage_avg_v = 1.0, cell_voltage_min_v = 0.9 }))
			seen = seen or reading.alarms.has("cell_warning") or reading.alarms.has("cell_critical")
			if first_used < 0 and reading.alarms.has("used_capacity"):
				first_used = k
		_check("%s: no voltage alarm on a flat curve" % chemistry, not seen)
		_check("%s: the used-mAh alarm at 80 %% of 1000 mAh (t = 80.0 s)" % chemistry, first_used == 800, str(first_used))
	var lipo_used := Sensors.new()
	_check("LiPo: used-mAh alarm at 80 % of 3200 mAh (2560 mAh, t = 256.0 s)",
		_first(lipo_used, "used_capacity", 0, 3000, 3.8, { pack_current_a = 36.0 }) == 2560)


func _other_alarms() -> void:
	var s := Sensors.new()
	var r: Dictionary = s.update(0.0, _ecm({ esc_state = "debounce" }))
	_check("ESC debounce is not yet LVC", not r.alarms.has("lvc"))
	r = s.update(0.1, _ecm({ esc_state = "soft_cut" }))
	_check("soft cut: LVC alarm, LVC chip", r.alarms.has("lvc") and Array(Telemetry.battery_warnings(_ecm(), r.alarms)) == ["battery_lvc"])
	r = s.update(0.2, _ecm({ esc_state = "hard_cut" }))
	_check("hard cut: LVC alarm", r.alarms.has("lvc") and r.esc_state == "hard_cut")
	r = s.update(0.3, _ecm({ temperature_k = 334.0 }))
	_check("61 °C: hot", r.alarms.has("hot") and Array(Telemetry.battery_warnings(_ecm(), r.alarms)) == ["battery_hot"])
	r = s.update(0.4, _ecm({ temperature_k = 332.4 }))
	_check("59 °C: still hot (one sensor step of hysteresis)", r.alarms.has("hot"))
	r = s.update(0.5, _ecm({ temperature_k = 331.4 }))
	_check("58 °C: hot cleared", not r.alarms.has("hot"))
	r = s.update(0.6, _ecm({ exhausted = true, cell_voltage_min_v = 0.0 }))
	_check("exhausted: BATTERY EMPTY alone", Array(Telemetry.battery_warnings(_ecm(), r.alarms)) == ["battery_empty"], str(r.alarms))
	var every: Array[String] = ["exhausted", "cell_critical", "lvc", "cell_warning", "used_capacity", "hot"]
	_check("battery codes most urgent first",
		Array(Telemetry.battery_warnings(_ecm(), every)) == ["battery_empty", "battery_critical", "battery_lvc", "battery_hot"])
	_check("80 % used alone: BATTERY LOW (caution)", Array(Telemetry.battery_warnings(_ecm(), ["used_capacity"])) == ["battery"])
	_check("empty, critical and LVC are danger chips; low and hot are caution",
		["battery_empty", "battery_critical", "battery_lvc"].all(func(c: String) -> bool: return c in WarningsBar.DANGER)
		and not "battery" in WarningsBar.DANGER and not "battery_hot" in WarningsBar.DANGER)
	_check("battery codes go before EXPERIMENTAL and replace stale ones",
		Array(Telemetry.with_battery_warnings(PackedStringArray(["stall", "battery", "experimental"]), PackedStringArray(["battery_lvc"])))
		== ["stall", "battery_lvc", "experimental"])
	_check("without EXPERIMENTAL they go last",
		Array(Telemetry.with_battery_warnings(PackedStringArray(["far"]), PackedStringArray(["battery_hot"]))) == ["far", "battery_hot"])
	_check("Telemetry.warnings maps sensor alarms in its battery slot",
		Array(Telemetry.warnings({ airspeed = 15.0, alpha_deg = 0.0, height_agl = 40.0, vertical_speed = 0.0, distance_pilot = 80.0 },
			{ battery = _ecm(), battery_alarms = ["lvc"], experimental = true })) == ["battery_lvc", "experimental"])
	_check("lithium chemistries only get voltage alarms", Sensors.VOLTAGE_ALARM_CHEMISTRIES == ["lipo", "lihv", "liion"])


func _legacy() -> void:
	var s := Sensors.new()
	var r := {}
	for k in range(0, 101):
		r = s.update(k * 0.1, _legacy_state({ soc = 0.1, exhausted = true }))
	_check("legacy: reading is V, A, mAh and %", r.valid and r.kind == "legacy" and _near(r.pack_voltage_v, 16.4) and _near(r.current_a, 12.0)
		and r.used_mah == roundi(12.0 * 10.0 / 3.6))
	_check("legacy: capacity is the starting charge (3200 mAh)", _near(r.capacity_mah, 3200.0, 1e-9) and _near(r.remaining_pct, 100.0 * (1.0 - 33.0 / 3200.0)))
	_check("legacy: no cell, temperature or ESC readings", is_nan(r.cell_avg_v) and is_nan(r.cell_min_v) and is_nan(r.temperature_c) and r.esc_state == "")
	_check("legacy: no sensor alarms", r.alarms.is_empty())
	_check("legacy rule kept: BATTERY LOW below 20 % SOC", Array(Telemetry.battery_warnings(_legacy_state({ soc = 0.15 }), [])) == ["battery"])
	_check("legacy rule kept: BATTERY LOW when exhausted", Array(Telemetry.battery_warnings(_legacy_state({ soc = 0.5, exhausted = true }), [])) == ["battery"])
	_check("legacy rule kept: nothing at 50 %", Telemetry.battery_warnings(_legacy_state({ soc = 0.5 }), []).is_empty())
	_check("no battery: no code", Telemetry.battery_warnings({}, ["exhausted"]).is_empty())


func _history() -> void:
	var s := Sensors.new()
	var r := {}
	for k in range(0, 2000):
		r = s.update(k * 0.1, _ecm({ bus_voltage_v = 16.0 - k * 0.001, pack_current_a = float(k % 50) }))
	_check("history keeps the last 60 s at 0.1 s (600 samples)", r.history_v.size() == Sensors.HISTORY_SIZE and r.history_a.size() == Sensors.HISTORY_SIZE)
	_check("history_v ends with the newest sample", _near(r.history_v[Sensors.HISTORY_SIZE - 1], r.pack_voltage_v) and _near(r.history_v[0], Sensors.quantize(16.0 - 1400 * 0.001, 0.01)))
	_check("HISTORY_SIZE = HISTORY_S / SAMPLE_PERIOD_S", Sensors.HISTORY_SIZE == roundi(Sensors.HISTORY_S / Sensors.SAMPLE_PERIOD_S))
	var box := Vector2(132, 34)
	var points: PackedVector2Array = BatteryPanel.spark_points(r.history_v, box, BatteryPanel.SPARK_MIN_SPAN_V)
	var inside := Rect2(Vector2.ZERO, box).grow(0.01)
	_check("sparkline: one point per sample, inside its box", points.size() == Sensors.HISTORY_SIZE
		and Array(points).all(func(p: Vector2) -> bool: return inside.has_point(p)))
	_check("sparkline: newest at the right edge", _near(points[points.size() - 1].x, box.x, 1e-9))
	var long := PackedFloat64Array()
	for i in 5000:
		long.append(sin(i * 0.1))
	_check("sparkline never draws more than 600 points", BatteryPanel.spark_points(long, box, 0.5).size() == Sensors.HISTORY_SIZE)
	var flat := BatteryPanel.spark_points(PackedFloat64Array([15.0, 15.0, 15.0]), box, 0.5)
	_check("a flat trace sits mid-box (minimum span)", flat.size() == 3 and _near(flat[0].y, (box.y - 1.0) - 0.5 * (box.y - 2.0)))
	_check("unknown samples are skipped", BatteryPanel.spark_points(PackedFloat64Array([NAN, 1.0, NAN, 2.0]), box, 0.5).size() == 2)
	_check("no history, no points", BatteryPanel.spark_points(PackedFloat64Array(), box, 0.5).is_empty())


func _settings_and_texts() -> void:
	_check("O9 is in Pilot, Full and Developer", ["pilot", "full", "developer"].all(func(p: String) -> bool: return Settings.PRESETS[p].has("battery")))
	_check("compact in Pilot, detailed in Full and Developer", not Settings.battery_detailed(Settings.validate({ preset = "pilot" }))
		and Settings.battery_detailed(Settings.validate({ preset = "full" })) and Settings.battery_detailed(Settings.validate({ preset = "developer" })))
	_check("a custom set keeps the Battery overlay", Settings.validate({ preset = "custom", visible = ["battery", "flight"] }).visible == ["flight", "battery"])
	_check("Battery switch in the overlays dialog", preload("res://ui/overlays_dialog.gd").NAMES.get("battery", "") == "Battery")
	_check("pack label 4S 3200 LiPo", BatteryPanel.pack_label({ series = 4, parallel = 1, capacity_mah = 3200.0, chemistry = "lipo" }) == "4S 3200 LiPo")
	_check("pack label 4S2P 8400 Li-ion", BatteryPanel.pack_label({ series = 4, parallel = 2, capacity_mah = 8400.0, chemistry = "liion" }) == "4S2P 8400 Li-ion")
	_check("no cell count, no pack label", BatteryPanel.pack_label({ capacity_mah = 3200.0 }) == "")
	_check("compact line", BatteryPanel.compact_text({ valid = true, pack_voltage_v = 14.62, current_a = 38.4, used_mah = 1874, remaining_pct = 41.4 })
		== "14.6 V · 38.4 A · 1874 mAh · 41 %", BatteryPanel.compact_text({ valid = true, pack_voltage_v = 14.62, current_a = 38.4, used_mah = 1874, remaining_pct = 41.4 }))
	_check("temperature °C, or °F for imperial", BatteryPanel.temperature_text(31.0, "metric") == "31 °C" and BatteryPanel.temperature_text(60.0, "imperial") == "140 °F"
		and BatteryPanel.temperature_text(NAN, "si") == "")
	_check("developer truth line", BatteryPanel.truth_text(_ecm({ soc = 0.412, soc_weak = 0.398 })) == "True SOC 41.2 % · weakest cell 39.8 %",
		BatteryPanel.truth_text(_ecm({ soc = 0.412, soc_weak = 0.398 })))
	_check("no truth line without a battery", BatteryPanel.truth_text({}) == "")
	var es: Translation = load("res://i18n/es.po")
	var missing := PackedStringArray()
	var texts: Array = ["Battery", "LVC", "%s V/cell", "min %s", "last 60 s", "True SOC %s", "weakest cell %s"]
	for code: String in Telemetry.BATTERY_CODES:
		texts.append(WarningsBar.text_for(code))
	for text: String in texts:
		if String(es.get_message(text)).is_empty():
			missing.append(text)
	_check("every new text has a Spanish translation", missing.is_empty(), str(missing))
	var backplate := Color(UiTheme.PANEL, Frame.BACKPLATE_ALPHA)
	_check("remaining-capacity caution is amber, independent of current-trace green",
		BatteryPanel.alarm_color(["cell_warning"]) == UiTheme.CAUTION
		and BatteryPanel.alarm_color(["used_capacity"]) == UiTheme.CAUTION
		and UiTheme.CAUTION != BatteryPanel.AMP_COLOR)
	_check("danger wins over simultaneous caution; no alarm stays neutral",
		BatteryPanel.alarm_color(["cell_warning", "lvc"]) == UiTheme.ERROR
		and BatteryPanel.alarm_color([]) == UiTheme.TEXT)
	for color: Color in [BatteryPanel.VOLT_COLOR, BatteryPanel.AMP_COLOR, UiTheme.CAUTION, UiTheme.ERROR]:
		_check("trace/bar colour %s ≥ 3:1 on the backplate over any sky" % color.to_html(false), UiTheme.contrast(color, backplate) >= 3.0,
			"%.2f" % UiTheme.contrast(color, backplate))


func _snapshot(battery: Dictionary, codes := PackedStringArray()) -> Dictionary:
	return {
		telemetry = { airspeed = 20.0, ground_speed = 18.0, vertical_speed = -1.0, height_datum = 30.0, height_agl = 30.0,
			distance_pilot = 90.0, alpha_deg = 4.0, beta_deg = 0.0, heading_deg = 90.0, pitch_deg = 2.0, bank_deg = -10.0,
			load_factor = 1.1, throttle = 0.6, time_s = float(battery.get("time_s", 65.0)), wind_speed = 4.0, wind_up = 0.0, wind_from_deg = 270.0 },
		warnings = codes, view_heading_deg = 0.0, rpm = 9000.0, battery = battery,
		sticks = { roll = 0.2, pitch = -0.1, yaw = 0.0, throttle = 0.6 }, trims = { roll = 0.0, pitch = 0.02, yaw = 0.0 },
		radio_status = "Keyboard · Rates: full",
	}


func _texts(node: Node) -> String:
	var parts := PackedStringArray()
	for label: Node in node.find_children("*", "Label", true, false):
		if (label as Control).is_visible_in_tree():
			parts.append(label.text)
	return "\n".join(parts)


func _panel() -> void:
	# The headless display server sets its window to 64×64 on the first frame, over any earlier size: resize after it.
	await process_frame
	root.size = Vector2i(1280, 720)
	await process_frame
	var manager: CanvasLayer = Manager.new({}, "en")
	root.add_child(manager)
	var panel: Control = manager.frames.battery
	manager.update(_snapshot({}), 1.0)
	await process_frame
	_check("no dynamic battery: O9 hidden although the Pilot preset lists it", not panel.visible and manager.is_overlay_visible("battery"))
	manager.update(_snapshot(_ecm({ time_s = 1.0, bus_voltage_v = 14.62, pack_current_a = 38.4 })), 1.0)
	await process_frame
	_check("pack_ecm battery: O9 shown", panel.visible)
	_check("Pilot: compact one line", panel.compact_label.visible and not panel.detail.visible
		and panel.compact_label.text == "14.6 V · 38.4 A · 0 mAh · 100 %", panel.compact_label.text)
	_check("title names the pack", panel.title_label.text == "BATTERY · 4S 3200 LiPo", panel.title_label.text)
	_check("no true SOC in the pilot overlays", not _texts(manager).contains("SOC") and not manager.diagnostics_battery.is_visible_in_tree())
	manager.set_preset("full")
	manager.update(_snapshot(_ecm({ time_s = 1.1, bus_voltage_v = 14.62, pack_current_a = 38.4, esc_state = "soft_cut" })), 1.0)
	await process_frame
	_check("Full: detailed layout", panel.detail.visible and not panel.compact_label.visible)
	_check("detailed rows: pack, cell, lowest, current, power, temperature, used/rated, %",
		panel.values.pack_v.text == "14.62 V" and panel.values.cell_avg.text == "3.80 V/cell" and panel.values.cell_min.text == "min 3.78 V"
		and panel.values.current.text == "38.4 A" and panel.values.power.text == "561 W" and panel.values.temperature.text == "81 °F"
		and panel.values.used.text.ends_with("/ 3200 mAh") and panel.values.percent.text == "100 %",
		"%s | %s | %s | %s | %s | %s | %s | %s" % [panel.values.pack_v.text, panel.values.cell_avg.text, panel.values.cell_min.text,
			panel.values.current.text, panel.values.power.text, panel.values.temperature.text, panel.values.used.text, panel.values.percent.text])
	_check("ESC soft cut shows the LVC chip in caution amber", panel.lvc_chip.visible
		and (panel.lvc_chip.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == UiTheme.CAUTION)
	panel.refresh(Sensors.new().update(0.0, _ecm({ esc_state = "hard_cut" })), "metric")
	_check("hard cut turns the chip danger red", (panel.lvc_chip.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == UiTheme.DANGER.pressed)
	_check("sparklines and the bar are drawn", panel.spark_v.is_visible_in_tree() and panel.spark_a.is_visible_in_tree() and panel.bar.is_visible_in_tree())
	_check("still no true SOC outside the developer overlays", not _texts(manager).contains("SOC"))
	manager.set_units("metric")
	manager.update(_snapshot(_ecm({ time_s = 1.2 })), 1.0)
	_check("metric temperature in °C", panel.values.temperature.text == "27 °C", panel.values.temperature.text)
	manager.set_preset("developer")
	manager.update(_snapshot(_ecm({ time_s = 1.3, soc = 0.8, soc_weak = 0.78 })), 1.0)
	await process_frame
	_check("Developer: true SOC only in Diagnostics", manager.diagnostics_battery.is_visible_in_tree()
		and manager.diagnostics_battery.text == "True SOC 80.0 % · weakest cell 78.0 %"
		and not _texts(panel).contains("SOC"), manager.diagnostics_battery.text)
	manager.set_preset("pilot")
	manager.update(_snapshot(_ecm({ time_s = 1.4 })), 1.0)
	await process_frame
	await process_frame
	_check("back to compact: the box shrinks again", panel.get_global_rect().size.y < 90.0, str(panel.get_global_rect()))
	manager.set_overlay_visible("battery", false)
	manager.update(_snapshot(_ecm({ time_s = 1.5 })), 1.0)
	_check("× closes O9", not panel.visible and manager.settings.preset == "custom")
	manager.set_preset("full")
	manager.update(_snapshot(_legacy_state({ time_s = 2.0 })), 1.0) # another pack: the manager's sensor restarts
	await process_frame
	_check("legacy kind: shown, no cell or temperature values", panel.visible and not panel.values.cell_avg.visible
		and not panel.values.cell_min.visible and not panel.values.temperature.visible and panel.values.pack_v.visible
		and panel.title_label.text == "BATTERY", panel.title_label.text)
	_check("legacy kind: % from the starting charge", panel.values.percent.text == "100 %" and panel.values.used.text == "0 / 3200 mAh",
		panel.values.used.text)
	manager.update(_snapshot({ ok = false }), 1.0)
	_check("a battery state that is not ok hides O9", not panel.visible)
	manager.update({}, 1.0)
	_check("no flight: O9 hidden", not panel.visible)
	manager.queue_free()
	await process_frame


func _shown(manager: CanvasLayer) -> Array:
	return Settings.IDS.filter(func(id: String) -> bool: return manager.frames[id].visible)


func _rects(manager: CanvasLayer, extra := {}) -> String:
	var parts := PackedStringArray()
	for id: String in _shown(manager):
		parts.append("%s %s" % [id, manager.frames[id].get_global_rect()])
	for key: String in extra:
		parts.append("%s %s" % [key, extra[key]])
	return "; ".join(parts)


## Every shown overlay (and `extra` rects) on a `size` screen with no two overlapping.
func _layout_ok(manager: CanvasLayer, size: Vector2, extra := {}) -> bool:
	var screen := Rect2(Vector2.ZERO, size)
	var rects: Array = _shown(manager).map(func(id: String) -> Rect2: return manager.frames[id].get_global_rect())
	rects.append_array(extra.values())
	for i in rects.size():
		if not screen.encloses(rects[i]) or rects[i].size.x <= 0.0:
			return false
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				return false
	return true


func _layout() -> void:
	# Home flights show the latency marker beside the controls guide (HUD-11-R2): O9 must keep clear of it too.
	var patch: CanvasLayer = LatencyPatch.new()
	patch.left_side = true
	root.add_child(patch)
	for language: String in ["en", "es"]:
		TranslationServer.set_locale(language)
		var manager: CanvasLayer = Manager.new({}, language)
		root.add_child(manager)
		var panel: Control = manager.frames.battery
		var snap := _snapshot(_ecm({ time_s = 5.0, esc_state = "hard_cut" }), PackedStringArray(["stall", "far"]))
		for size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.size = size
			for preset: String in ["pilot", "full"]:
				manager.set_preset(preset)
				for i in 2: # the second refresh re-docks O9 after the first layout pass sized its neighbours
					manager.update(snap, 1.0)
					await process_frame
					await process_frame
				var marker: Rect2 = (patch.get_child(0) as Control).get_global_rect()
				_check("%s %s %dx%d: O9 shown, no overlap (latency marker included)" % [language, preset, size.x, size.y],
					panel.visible and _layout_ok(manager, Vector2(size), { latency = marker }), _rects(manager, { latency = marker }))
		root.size = Vector2i(640, 480)
		for preset: String in ["pilot", "full"]:
			manager.set_preset(preset)
			for i in 2:
				manager.update(snap, 1.0)
				await process_frame
				await process_frame
			var rect: Rect2 = panel.get_global_rect()
			_check("%s %s at 640 px: O9 fits on screen (%d px wide)" % [language, preset, rect.size.x],
				Rect2(Vector2.ZERO, Vector2(640, 480)).encloses(rect) and rect.size.x <= 616.0, str(rect))
		manager.set_preset("pilot")
		var every := PackedStringArray(["failsafe", "safe", "stall", "low", "far", "battery_empty", "battery_critical",
			"battery_lvc", "battery", "battery_hot", "experimental"])
		root.size = Vector2i(1280, 720)
		manager.refresh_numbers(_snapshot({}, every))
		await process_frame
		await process_frame
		_check("%s: every warning incl. the battery chips wraps inside the bar" % language,
			manager.frames.warnings.chips.size.x <= WarningsBar.MAX_WIDTH + 0.5, str(manager.frames.warnings.chips.size))
		manager.queue_free()
		await process_frame
	TranslationServer.set_locale("en")
	patch.queue_free()
	await process_frame


## The warnings bar during a sag: BATTERY LOW only after the 2 s hold, then LVC, from the sensor alarms.
func _warnings_in_flight() -> void:
	var manager: CanvasLayer = Manager.new({}, "en")
	root.add_child(manager)
	var first_low := -1
	for k in range(0, 60):
		var cell := 3.8 if k < 10 else 3.45
		var snap := _snapshot(_ecm({ time_s = k * 0.1, cell_voltage_min_v = cell, soc = 0.6 }), PackedStringArray(["battery"]))
		manager.refresh_numbers(snap)
		if first_low < 0 and manager.frames.warnings.codes.has("battery"):
			first_low = k
	_check("BATTERY LOW appears at 3.0 s for a sag from 1.0 s (a stale snapshot code is replaced)", first_low == 30, str(first_low))
	manager.set_overlay_visible("battery", false)
	manager.refresh_numbers(_snapshot(_ecm({ time_s = 6.0, cell_voltage_min_v = 3.45, esc_state = "soft_cut" })))
	_check("with O9 closed the alarms still reach the warnings", Array(manager.frames.warnings.codes) == ["battery_lvc", "battery"],
		str(manager.frames.warnings.codes))
	_check("caution and danger chips are shown", manager.frames.warnings.visible and manager.frames.warnings.chips.get_child_count() == 2)
	manager.queue_free()
	await process_frame

