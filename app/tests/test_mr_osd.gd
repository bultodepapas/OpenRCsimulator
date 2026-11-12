# DR-31b: the FPV quad OSD model and HUD elements. Known answers: a 10° nose-up quaternion reads pitch +10, a 20°
# right roll reads roll +20, a 90° yaw heads 090; a level body with w = -2 m/s climbs +2 m/s; from the origin heading
# east, home 10 m north is 10 m away at -90° (left); 10 m/s is 36 km/h or 22 mph; layouts cycle Off -> Race ->
# Freestyle -> Full and units Metric <-> Imperial, saved only with a path; an armed flight sets home, feeds the
# statistics and shows them after the disarm; Off keeps the arm state and hints but hides the layout elements; a
# low cell warns LAND NOW. Headless: the drawing runs, but no 1080p readability or legibility claim.
extends SceneTree

const Osd := preload("res://vehicles/multirotor/osd_model.gd")
const Hud := preload("res://vehicles/multirotor/multirotor_hud.gd")
const Paint := preload("res://vehicles/multirotor/osd_painter.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")

const EPS := 1.0e-6
const CONFIG := "user://test_mr_osd.cfg"

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


static func _q_axis(axis: Vector3, deg: float) -> PackedFloat64Array:
	var h := deg_to_rad(deg) * 0.5
	return PackedFloat64Array([cos(h), axis.x * sin(h), axis.y * sin(h), axis.z * sin(h)])


static func _body(north: float, east: float, down: float, w_body: float, q: PackedFloat64Array) -> PackedFloat64Array:
	var b := PackedFloat64Array([north, east, down, 0.0, 0.0, w_body])
	b.append_array(q)
	b.append_array(PackedFloat64Array([0.0, 0.0, 0.0]))
	return b


func _run() -> void:
	_model()
	_config()
	_firmware()
	_stats()
	await _hud()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _model() -> void:
	var pitch := Osd.euler_deg(_q_axis(Vector3(0, 1, 0), 10.0))
	_check("10° nose up reads pitch +10, roll 0", absf(pitch.x - 10.0) < 1.0e-4 and absf(pitch.y) < 1.0e-4, str(pitch))
	var roll := Osd.euler_deg(_q_axis(Vector3(1, 0, 0), 20.0))
	_check("20° right roll reads roll +20", absf(roll.y - 20.0) < 1.0e-4 and absf(roll.x) < 1.0e-4, str(roll))
	var heading := Osd.heading_deg(_q_axis(Vector3(0, 0, 1), 90.0))
	_check("90° yaw heads 090", absf(heading - 90.0) < 1.0e-4, str(heading))
	_check("-30° yaw heads 330", absf(Osd.heading_deg(_q_axis(Vector3(0, 0, 1), -30.0)) - 330.0) < 1.0e-4)
	var flight := Osd.flight_values(_body(3.0, 4.0, -5.0, -2.0, PackedFloat64Array([1, 0, 0, 0])))
	_check("level body w = -2 m/s climbs +2 m/s with no ground speed", absf(float(flight.climb_mps) - 2.0) < EPS
		and absf(float(flight.ground_mps)) < EPS and float(flight.north) == 3.0, str(flight))
	var pitched := Osd.flight_values(_body(0, 0, 0, -2.0, _q_axis(Vector3(0, 1, 0), 90.0)))
	_check("nose straight up, body w = -2 m/s is 2 m/s of ground speed north", absf(float(pitched.ground_mps) - 2.0) < 1.0e-4
		and absf(float(pitched.climb_mps)) < 1.0e-4, str(pitched))
	_check("a short state has no flight values", Osd.flight_values(PackedFloat64Array([0, 0, 0])).is_empty())
	var home := Osd.home_vector(0.0, 0.0, 90.0, Vector2(10.0, 0.0))
	_check("heading east, home 10 m north is 10 m away at -90°", absf(float(home.distance_m) - 10.0) < EPS
		and absf(float(home.relative_deg) + 90.0) < EPS, str(home))
	var behind := Osd.home_vector(0.0, 0.0, 0.0, Vector2(-5.0, 0.0))
	_check("home straight behind reads ±180°", absf(absf(float(behind.relative_deg)) - 180.0) < EPS, str(behind))
	_check("10 m/s is 36 KM/H", Osd.speed_text(10.0, "metric") == "36 KM/H", Osd.speed_text(10.0, "metric"))
	_check("10 m/s is 22 MPH", Osd.speed_text(10.0, "imperial") == "22 MPH", Osd.speed_text(10.0, "imperial"))
	_check("altitude: one decimal below 100 m, whole above", Osd.altitude_text(12.34, "metric") == "12.3 M"
		and Osd.altitude_text(123.4, "metric") == "123 M" and Osd.altitude_text(10.0, "imperial") == "33 FT")
	_check("distance: metres then kilometres", Osd.distance_text(950.0, "metric") == "950 M"
		and Osd.distance_text(1500.0, "metric") == "1.50 KM" and Osd.distance_text(2000.0, "imperial") == "1.24 MI")
	_check("climb text carries its sign", Osd.climb_text(1.5, "metric") == "+1.5 M/S" and Osd.climb_text(-0.5, "metric") == "-0.5 M/S",
		Osd.climb_text(1.5, "metric"))
	_check("vario steps: 0, ±1, ±2, ±3", Osd.vario_steps(0.1) == 0 and Osd.vario_steps(1.0) == 1 and Osd.vario_steps(-3.0) == -2
		and Osd.vario_steps(8.0) == 3)
	_check("charge bands at 25 % and 50 %", Osd.charge_band(0.1) == 0 and Osd.charge_band(0.4) == 1 and Osd.charge_band(0.9) == 2)


func _config() -> void:
	_check("layouts cycle Off -> Race -> Freestyle -> Full -> Custom -> Off", Osd.next_in(Osd.LAYOUTS, "off") == "race"
		and Osd.next_in(Osd.LAYOUTS, "race") == "freestyle" and Osd.next_in(Osd.LAYOUTS, "freestyle") == "full"
		and Osd.next_in(Osd.LAYOUTS, "full") == "custom" and Osd.next_in(Osd.LAYOUTS, "custom") == "off")
	_check("Full shows every element; Off none", Osd.ELEMENTS.all(func(e: String) -> bool: return Osd.shows("full", e))
		and Osd.ELEMENTS.all(func(e: String) -> bool: return not Osd.shows("off", e)))
	_check("every layout element is a known element with a name", Osd.LAYOUT_ELEMENTS.keys().all(func(l: String) -> bool:
		return (Osd.LAYOUT_ELEMENTS[l] as Array).all(func(e: Variant) -> bool: return e in Osd.ELEMENTS))
		and Osd.ELEMENTS.all(func(e: String) -> bool: return Osd.ELEMENT_NAMES.has(e)))
	_check("invalid saved values fall back to the defaults", Osd.sanitize({layout = "huge", units = 3, style = "neon",
		crosshair = 7, custom = ["nope", 4]}) == Osd.DEFAULTS.merged({custom = []}, true))
	_check("no path: nothing is saved", not Osd.save_config("", {layout = "full", units = "imperial"}))
	_check("no path: the defaults load", Osd.load_config("") == Osd.DEFAULTS)
	var saved := {layout = "custom", units = "imperial", style = "analog", crosshair = "dot", custom = ["gforce", "rpm"]}
	_check("a saved choice loads back", Osd.save_config(CONFIG, saved) and Osd.load_config(CONFIG) == saved, str(Osd.load_config(CONFIG)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))
	var custom := Osd.toggled(Osd.sanitize({layout = "race"}), "gforce", true)
	_check("switching an element on starts Custom from the current layout", custom.layout == "custom"
		and "gforce" in Osd.elements_of(custom) and "timer" in Osd.elements_of(custom) and not "horizon" in Osd.elements_of(custom))
	_check("switching it off again removes only it", not "gforce" in Osd.elements_of(Osd.toggled(custom, "gforce", false))
		and "timer" in Osd.elements_of(Osd.toggled(custom, "gforce", false)))


## DR-31c: the flight controller conventions (warnings, blink, G, estimates, up/down).
func _firmware() -> void:
	var w := func(s: Dictionary) -> String: return str(Osd.warning(s).text)
	_check("arming refusals show only while the arm switch is on", w.call({arm_requested = true, block = FC.BLOCK_THROTTLE}) == "THROTTLE"
		and w.call({arm_requested = false, block = FC.BLOCK_THROTTLE}) == ""
		and w.call({arm_requested = true, block = FC.BLOCK_SWITCH}) == "ARM SWITCH"
		and w.call({arm_requested = true, not_ready = true}) == "RXLOSS")
	_check("a crash outranks the pack; an empty pack outranks LAND NOW", w.call({crashed = true, cell_v = 3.0}) == "CRASH"
		and w.call({depleted = true, cell_v = 3.0}) == "BATT EMPTY" and w.call({cell_v = 3.3}) == "LAND NOW")
	var low: Dictionary = Osd.warning({cell_v = 3.5, armed = true, armed_notice = true})
	_check("LOW BATTERY is a blinking warning and outranks ARMED", low.text == "LOW BATTERY" and low.severity == Osd.WARNING
		and bool(low.blink))
	_check("BATT < FULL only before the first arm", w.call({cell_v = 4.0}) == "BATT < FULL" and w.call({cell_v = 4.0, ever_armed = true}) == ""
		and w.call({cell_v = 4.2}) == "")
	var armed: Dictionary = Osd.warning({armed = true, armed_notice = true, cell_v = 4.1, ever_armed = true})
	_check("ARMED is a green info notice", armed.text == "ARMED" and armed.severity == Osd.INFO and not bool(armed.blink))
	_check("blink: 2 Hz at 50 %", Osd.blink_on(0.1) and not Osd.blink_on(0.3) and Osd.blink_on(0.6))
	var g := Osd.GForce.new()
	for tick in 240:
		g.sample(tick, _body(0, 0, -5, 0, PackedFloat64Array([1, 0, 0, 0])), 1.0 / 240.0)
	var rest := g.value
	for tick in range(240, 720):
		# 1 g of acceleration north: the body speed grows by g/240 per tick.
		var u := float(tick - 240) * Osd.G / 240.0
		var b := _body(0, 0, -5, 0, PackedFloat64Array([1, 0, 0, 0]))
		b[3] = u
		g.sample(tick, b, 1.0 / 240.0)
	_check("G: 1.00 at rest, 1.41 accelerating at 1 g level", absf(rest - 1.0) < 1.0e-9 and absf(g.value - sqrt(2.0)) < 1.0e-3,
		"%.4f %.4f" % [rest, g.value])
	g.sample(10, _body(0, 0, -5, 0, PackedFloat64Array([1, 0, 0, 0])), 1.0 / 240.0)
	_check("G resets on a restart (the tick goes back)", g.value == 1.0)
	_check("remaining time: 500 mAh to the 80 % mark at 2.5 mAh/s is 200 s", absf(Osd.remaining_s(0.7, 1000.0, 300.0, 120.0) - 200.0) < 1.0e-9
		and Osd.remaining_s(0.95, 1000.0, 50.0, 20.0) < 0.0 and Osd.remaining_s(0.7, 0.0, 300.0, 120.0) < 0.0)
	_check("live efficiency: 18 A at 10 m/s is 500 mAh/km; slow reads ---", Osd.efficiency_text(18.0, 10.0, "metric") == "500 MAH/KM"
		and Osd.efficiency_text(18.0, 0.5, "metric") == "--- MAH/KM", Osd.efficiency_text(18.0, 10.0, "metric"))
	_check("up/down reference: D looking straight down, U straight up, none level",
		Osd.updown(_q_axis(Vector3(0, 1, 0), -90.0), 0.0) == "D" and Osd.updown(_q_axis(Vector3(0, 1, 0), 80.0), deg_to_rad(20.0)) == "U"
		and Osd.updown(PackedFloat64Array([1, 0, 0, 0]), deg_to_rad(30.0)) == "")
	_check("clock and rpm texts", Osd.clock_text(-1.0) == "--:--" and Osd.clock_text(125.0) == "02:05"
		and Osd.rpm_text(24000.0 * TAU / 60.0) == "24.0K")


func _stats() -> void:
	var stats := Osd.Stats.new()
	var t := {speed_mps = 12.0, altitude_agl_m = 5.0, has_battery = true, bus_voltage_v = 16.0, pack_current_a = 20.0,
		consumed_mah = 100.0}
	stats.sample(t, Vector2(0, 0), 0.0, 4, 0.0)
	t.speed_mps = 20.0
	t.bus_voltage_v = 14.4
	t.pack_current_a = 50.0
	t.consumed_mah = 160.0
	stats.sample(t, Vector2(300, 400), 500.0, 4, 30.0)
	t.speed_mps = 5.0
	stats.sample(t, Vector2(300, 0), 300.0, 4, 61.0)
	_check("statistics keep maxima and minima", stats.max_speed_mps == 20.0 and stats.max_distance_m == 500.0
		and absf(stats.min_cell_v - 3.6) < EPS and stats.max_current_a == 50.0 and absf(stats.max_power_w - 720.0) < 1.0e-9,
		"%s %s %s" % [stats.max_speed_mps, stats.min_cell_v, stats.max_power_w])
	_check("statistics integrate the path and the used charge", absf(stats.total_distance_m - 900.0) < EPS
		and absf(stats.used_mah - 60.0) < EPS, "%s %s" % [stats.total_distance_m, stats.used_mah])
	var rows := stats.rows("metric", 4)
	var labels := rows.map(func(r: Array) -> String: return str(r[0]))
	_check("rows: time, speed, distances, battery and efficiency", "Flight time" in labels and "Min cell voltage" in labels
		and "Efficiency" in labels and str(rows[0][1]) == "01:01", str(rows))
	var no_pack := Osd.Stats.new()
	no_pack.sample({speed_mps = 3.0}, Vector2.INF, INF, 0, 2.0)
	_check("no pack: no battery rows (flight rows, average and full throttle)", no_pack.rows("metric", 0).size() == 7
		and is_inf(no_pack.max_distance_m) == false, str(no_pack.rows("metric", 0)))
	var thr := Osd.Stats.new()
	thr.sample({collective = 1.0, rotor_speed_rad_s = PackedFloat64Array([2000.0, 2100.0, 1900.0, 2050.0])}, Vector2.INF, INF, 0, 0.0, 1.2)
	thr.sample({collective = 1.0}, Vector2.INF, INF, 0, 2.0, 2.5)
	thr.sample({collective = 0.0}, Vector2.INF, INF, 0, 4.0, 1.0)
	_check("throttle statistics: 2 s at full of 4 s, average 50 %, max G and RPM", absf(thr.full_throttle_s - 2.0) < EPS
		and absf(thr.average_throttle() - 0.5) < EPS and thr.max_g == 2.5 and thr.max_rpm_rad_s == 2100.0,
		"%s %s %s" % [thr.full_throttle_s, thr.average_throttle(), thr.max_g])


func _telemetry(armed: bool, volts := 16.4) -> Dictionary:
	return {armed = armed, crashed = false, depleted = false, arm_block = 0, flight_mode = 0, collective = 0.4,
		altitude_agl_m = 8.0, speed_mps = 10.0, has_battery = true, bus_voltage_v = volts, pack_current_a = 18.0,
		consumed_mah = 220.0, soc = 0.7, commands = PackedFloat64Array([0.4, 0.5, 0.45, 0.42]), time_s = 0.0}


## DR-31c HUD behaviour: the settings panel, the analog style, arming warnings, the timer alarm, G and the mode name.
func _hud_c(hud: CanvasLayer, state: Dictionary) -> void:
	hud.show_menu("paused", true)
	hud.toggle_osd_settings()
	var panel: PanelContainer = hud.settings_panel
	_check("OSD settings open beside the menu", panel.visible and hud.osd_button.text == "OSD settings"
		and panel.get_global_rect().position.x > hud.menu.get_global_rect().end.x - 1.0,
		"%s %s" % [panel.get_global_rect(), hud.menu.get_global_rect()])
	(panel.checks["gforce"] as CheckBox).button_pressed = true
	_check("checking an element selects Custom with it", hud.osd_config.layout == "custom" and hud.shows("gforce")
		and "Custom" in hud.layout_button.text)
	panel.style_button.pressed.emit()
	panel.crosshair_button.pressed.emit()
	_check("style and crosshair cycle", hud.osd_config.style == "analog" and hud.osd_config.crosshair == "aircraft"
		and "Analog" in panel.style_button.text and "Aircraft" in panel.crosshair_button.text)
	hud.hide_menu()
	_check("closing the menu closes the settings", not panel.visible)
	var t := _telemetry(true)
	t.time_s = 50.0
	hud.update(t, state)
	_check("analog style: every value white", hud.arm_label.get_theme_color("font_color") == Paint.TEXT)
	panel.style_button.pressed.emit()
	var refused := _telemetry(false)
	refused.arm_block = FC.BLOCK_THROTTLE
	var arming := state.duplicate()
	arming.arm_requested = true
	hud.update(refused, arming)
	_check("an arm request at high throttle shows THROTTLE in amber", hud.warning_label.text == "THROTTLE"
		and hud.warning_label.get_theme_color("font_color") == Paint.CAUTION, hud.warning_label.text)
	var late := state.duplicate()
	late.flight_s = 601.0
	late.pilot_mode = FC.FLIGHT_ANGLE
	late.accepted = _body(0, 0, -5, 0, PackedFloat64Array([1, 0, 0, 0]))
	t.tick = 7
	hud.update(t, late)
	_check("past 10 min the flight timer turns red", hud.timer_label.get_theme_color("font_color") == Paint.DANGER)
	_check("the mode reads ANGL and G reads 1.00 at rest", hud.mode_label.text == "ANGL" and float(hud._draw_state.g) == 1.0,
		"%s %s" % [hud.mode_label.text, hud._draw_state.g])
	await process_frame # draw the Custom layout with every new element path


func _hud() -> void:
	var hud: CanvasLayer = Hud.new()
	root.add_child(hud)
	await process_frame
	hud.cells = 4
	hud.hide_menu()
	_check("the default layout is Freestyle, metric", hud.osd_config == Osd.DEFAULTS and hud.layout_button.text == "OSD layout: Freestyle"
		and hud.units_button.text == "OSD units: Metric", hud.layout_button.text)
	_check("OSD text uses the monospaced face", hud.mode_label.get_theme_font("font") == Paint.font())
	var state := {camera = "fpv", tilt_deg = 30.0, vfov_deg = 90.0, aspect = 16.0 / 9.0,
		attitude = PackedFloat64Array([1, 0, 0, 0]), body = _body(0.0, 0.0, -8.0, 0.0, PackedFloat64Array([1, 0, 0, 0])),
		sticks = {roll = 0.2, pitch = -0.3, yaw = 0.0, throttle = 0.4}, stick_policy = "absolute"}
	var t := _telemetry(false)
	hud.update(t, state)
	_check("no home before the first arm", not hud.home.is_finite() and (hud._draw_state.home as Dictionary).is_empty())
	t = _telemetry(true)
	hud.update(t, state)
	_check("arming sets home where the quad is and shows ARMED", hud.home == Vector2(0, 0) and hud.warning_label.text == "ARMED",
		"%s %s" % [hud.home, hud.warning_label.text])
	_check("battery line: charge, pack and cell voltage, current and used charge", "70%" in hud.battery_label.text
		and "4.10 V/cell" in hud.battery_label.text and "mAh" in hud.battery_label.text, hud.battery_label.text)
	_check("throttle reads THR", hud.throttle_label.text == "THR 40%", hud.throttle_label.text)
	for i in 30:
		t.time_s = 0.1 * float(i + 1)
		state.body = _body(float(i), 0.0, -8.0, 0.0, PackedFloat64Array([1, 0, 0, 0]))
		hud.update(t, state)
	var home_info: Dictionary = hud._draw_state.home
	_check("the home vector follows the flight", absf(float(home_info.distance_m) - 29.0) < 1.0e-6
		and absf(absf(float(home_info.relative_deg)) - 180.0) < 1.0e-6, str(home_info))
	t = _telemetry(true, 13.2)
	t.time_s = 3.1
	hud.update(t, state)
	_check("a cell below 3.4 V warns LAND NOW", hud.warning_label.text == "LAND NOW", hud.warning_label.text)
	_check("no statistics while armed", not hud.stats_panel.visible)
	t = _telemetry(false, 15.0)
	hud.update(t, state)
	_check("the disarm after a flight shows the statistics", hud.stats_panel.visible and "FLIGHT STATISTICS" in hud.stats_label.text
		and "MAX DISTANCE" in hud.stats_label.text and "29 M" in hud.stats_label.text, hud.stats_label.text)
	hud.update(_telemetry(false, 13.2), state)
	_check("the statistics own the centre: no warning over them", hud.stats_panel.visible and hud.warning_label.text.is_empty(),
		hud.warning_label.text)
	hud.update(t, state)
	hud.show_menu("paused", true)
	_check("the menu hides the statistics", not hud.stats_panel.visible)
	hud.hide_menu()
	hud.cycle_units()
	_check("imperial units relabel the statistics", hud.units_button.text == "OSD units: Imperial" and "95 FT" in hud.stats_label.text,
		hud.stats_label.text)
	hud.cycle_layout()
	_check("Freestyle -> Full shows angles, motors and sticks", hud.osd_config.layout == "full" and hud.shows("motors")
		and hud.shows("sticks") and hud.shows("ladder") and "Full" in hud.layout_button.text)
	hud.update(t, state)
	_check("Full adds the power and efficiency line (imperial: per mile)", " W  " in hud.battery_label.text and "MAH/MI" in hud.battery_label.text,
		hud.battery_label.text)
	await process_frame # the draw callback runs every element without engine errors
	hud.cycle_layout()
	_check("Full -> Custom (the saved custom set)", hud.osd_config.layout == "custom" and hud._elements == Osd.DEFAULTS.custom)
	hud.cycle_layout()
	hud.update(t, state)
	_check("Off hides the layout but keeps the arm state", hud.osd_config.layout == "off" and not hud.mode_label.visible
		and not hud.timer_label.visible and not hud.battery_label.visible and not hud.throttle_label.visible
		and hud.arm_label.text.begins_with("MOTORS DISARMED") and not hud.stats_panel.visible)
	var low_cell := _telemetry(true, 13.2)
	low_cell.time_s = 9.0
	hud.update(low_cell, state)
	_check("Off still warns LAND NOW on a low cell", hud.warning_label.text == "LAND NOW", hud.warning_label.text)
	hud.update(t, state)
	await process_frame
	hud.cycle_layout()
	hud.update(t, state)
	_check("Race keeps mode, timer, pack and throttle", hud.mode_label.visible and hud.timer_label.visible and hud.battery_label.visible
		and not "mAh" in hud.battery_label.text and not hud.shows("horizon"))
	t = _telemetry(true)
	t.time_s = 10.0
	hud.update(t, state)
	_check("arming again resets the statistics and hides them", not hud.stats_panel.visible and hud.stats.flight_s == 0.0)
	# Armed on the ground for 3 s (no height, no path): not a flight, so no statistics.
	var pad := _telemetry(true)
	pad.altitude_agl_m = 0.0
	var pad_state := state.duplicate()
	pad_state.body = _body(0.0, 0.0, 0.0, 0.0, PackedFloat64Array([1, 0, 0, 0]))
	hud.stats.reset()
	for i in 4:
		pad.time_s = 20.0 + float(i)
		hud.update(pad, pad_state)
	pad.armed = false
	hud.update(pad, pad_state)
	_check("an arm-and-wait on the pad shows no statistics", not hud._stats_ready and not hud.stats_panel.visible,
		"flight_s %s" % hud.stats.flight_s)
	# A real flight, then (as on Betaflight) a disarmed roll stick keeps the statistics and pitch forward closes them.
	var hop := _telemetry(true)
	for i in 4:
		hop.time_s = 30.0 + float(i)
		hud.update(hop, state)
	hop.armed = false
	hud.update(hop, state)
	var shown: bool = hud.stats_panel.visible
	var moved := state.duplicate()
	moved.sticks = {roll = 0.9, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	hud.update(hop, moved)
	var kept: bool = hud.stats_panel.visible
	moved.sticks = {roll = 0.0, pitch = -0.8, yaw = 0.0, throttle = 0.0}
	hud.update(hop, moved)
	_check("roll keeps the statistics; pitch forward closes them", shown and kept and not hud.stats_panel.visible)
	_check("a high throttle closes them too (after the sticks were low)", hud.stats_stick_high({throttle = 0.9, pitch = 0.0}, "absolute")
		and not hud.stats_stick_high({throttle = 0.6, pitch = 0.0}, "absolute") and hud.stats_stick_high({throttle = 0.6}, "rate"))
	var scripted := state.duplicate()
	scripted.sticks = {arm = true}
	hud.update(hop, scripted)
	_check("a sample without sticks draws no stick overlay", (hud._draw_state.sticks as Dictionary).is_empty())
	await _hud_c(hud, state)
	_check("nothing was saved without a path", not FileAccess.file_exists(CONFIG))
	hud.update(t, {}) # no optional keys: still updates
	await process_frame
	_check("a state without body or attitude draws no flight elements", (hud._draw_state.flight as Dictionary).is_empty())
	hud.queue_free()
	await process_frame
