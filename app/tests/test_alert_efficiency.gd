## HUD-09-R4: unchanged source codes must not freeze time-dependent manager behavior.
extends SceneTree

const Manager := preload("res://render/overlays/overlay_manager.gd")
const Flight := preload("res://sim/flight_session.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const GASOLINE := "res://data/aircraft/p51d_mustang_120.json"

var _count := 0
var _failed := 0
var _clock := 0.0
var _cues: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("en")
	await process_frame
	root.size = Vector2i(1920, 1080)
	var old_motion: bool = UiTheme.reduced_motion
	UiTheme.reduced_motion = false
	var bus := AudioServer.get_bus_index(&"Master")
	var old_mute := AudioServer.is_bus_mute(bus)
	var old_db := AudioServer.get_bus_volume_db(bus)
	AudioServer.set_bus_mute(bus, false)
	AudioServer.set_bus_volume_db(bus, 0.0)
	var manager := Manager.new({preset = "custom", visible = ["warnings"], warning_training = true}, "en")
	root.add_child(manager)
	manager.alert_audio.set("_clock", func() -> float: return _clock)
	manager.alert_audio.cue_requested.connect(func(cue: String, _code: String) -> void: _cues.append(cue))
	await process_frame
	_training(manager)
	_battery(manager)
	_fuel(manager)
	_audio_and_lifecycle(manager)
	await _locale(manager)
	manager.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.25).timeout # release stopped OGG playbacks before exit
	AudioServer.set_bus_mute(bus, old_mute)
	AudioServer.set_bus_volume_db(bus, old_db)
	UiTheme.reduced_motion = old_motion
	TranslationServer.set_locale("en")
	print("alert efficiency: %d checks, %d failed" % [_count, _failed])
	quit(1 if _failed else 0)


func _snapshot(codes: PackedStringArray) -> Dictionary:
	return {warnings = codes, paused = false,
		telemetry = {time_s = 0.0, height_agl = 30.0, airspeed = 20.0,
			vertical_speed = 0.0, bank_deg = 0.0, load_factor = 1.0}}


func _step(manager: CanvasLayer, snap: Dictionary, time_s: float, wall_s := -1.0) -> void:
	snap.telemetry.time_s = time_s
	if snap.has("battery"):
		snap.battery.time_s = time_s
	_clock = time_s if wall_s < 0.0 else wall_s
	manager.refresh_numbers(snap)


func _training(manager: CanvasLayer) -> void:
	var snap := _snapshot(PackedStringArray(["far"]))
	snap.telemetry.vertical_speed = -7.0
	_step(manager, snap, 0.0)
	_step(manager, snap, 0.59)
	_check("unchanged raw warnings do not bypass training dwell", not manager.frames.warnings.codes.has("sink_rate"))
	_step(manager, snap, 0.60)
	_check("training cue appears when accepted time reaches dwell", manager.frames.warnings.codes.has("sink_rate"))
	snap.telemetry.vertical_speed = 0.0
	_step(manager, snap, 0.70)
	_step(manager, snap, 1.00)
	_check("training clear grace holds the existing cue", manager.frames.warnings.codes.has("sink_rate"))
	_step(manager, snap, 1.10)
	_check("unchanged raw warnings do not freeze training clear", not manager.frames.warnings.codes.has("sink_rate"))
	manager.set_warning_option("warning_training", false)


## Same accepted pack shape and voltage hold used by test_overlay_battery.gd.
func _battery(manager: CanvasLayer) -> void:
	manager.reset_flight()
	var pack := {
		ok = true, battery_kind = "pack_ecm", pack_id = "lipo-4s1p-3200-c30-class",
		display_name = "4S 3200 mAh LiPo (30C class)", chemistry = "lipo", series = 4, parallel = 1, rated_capacity_ah = 3.2,
		bus_voltage_v = 15.2, pack_current_a = 20.0, auxiliary_current_a = 0.3, pack_terminal_power_w = 304.0,
		ocv_v = 16.0, polarization_v = 0.1, cell_voltage_avg_v = 3.8, cell_voltage_min_v = 3.78, soc = 0.8, soc_weak = 0.78,
		temperature_k = 300.0, ambient_k = 293.15, consumed_charge_c = 0.0, remaining_charge_c = 11520.0,
		terminal_energy_j = 0.0, pack_heat_j = 0.0, exhausted = false, esc_state = "normal", esc_limit = 1.0,
		esc_detected_cells = 4, esc_cutoff_voltage_v = 12.8, esc_sensed_voltage_v = 15.2,
		tick = 0, time_s = 0.0, rpm = 9000.0, duty = 0.6, effective_duty = 0.6, enabled = true,
	}
	var snap := _snapshot(PackedStringArray(["far"]))
	snap.battery = pack
	for index in range(0, 30):
		snap.battery.cell_voltage_min_v = 3.8 if index < 10 else 3.25
		_step(manager, snap, index * 0.1)
	_check("sensor alarm waits for the accepted two-second hold", not manager.frames.warnings.codes.has("battery_critical"))
	_step(manager, snap, 3.0)
	_check("unchanged raw warnings still receive the accepted sensor alarm",
		manager.frames.warnings.codes == PackedStringArray(["battery_critical", "far"]))


## Use the same real-session exhaustion transition as test_overlay_fuel_flight.gd.
func _fuel(manager: CanvasLayer) -> void:
	manager.reset_flight()
	var session := Flight.new()
	session.input_enabled = false
	session.setup(GASOLINE)
	session.reset()
	var available: bool = session.is_flyable() and session.liquid_fuel_is_active()
	_check("gasoline fixture supplies a flyable finite-fuel session", available)
	if available:
		var index: int = session._liquid_index()
		session.sim.state[2] = -1000.0
		session.sim.continuous[index] = 1.0e-9
		session.sim.continuous[index + 1] = 1.0
		var before: Dictionary = session.mass_properties()
		var snap := _snapshot(PackedStringArray(["fuel_reserve_estimated", "far"]))
		snap.mass_sample = before
		_step(manager, snap, float(before.get("time_s", 0.0)))
		_check("accepted pre-exhaustion sample retains usable fuel",
			before.get("ok", false) and before.get("finite_fuel", false) and float(before.get("fuel_usable_kg", 0.0)) > 0.0
			and not manager.frames.warnings.codes.has("fuel_empty"))
		session.sim.step()
		var empty: Dictionary = session.mass_properties()
		snap.mass_sample = empty
		_step(manager, snap, float(empty.get("time_s", 0.0)))
		_check("unchanged raw warnings reveal accepted empty fuel",
			empty.get("ok", false) and empty.get("finite_fuel", false) and float(empty.get("fuel_usable_kg", NAN)) == 0.0
			and manager.frames.warnings.codes.has("fuel_empty") and not manager.frames.warnings.codes.has("fuel_reserve_estimated"))
	session.free()


func _audio_and_lifecycle(manager: CanvasLayer) -> void:
	manager.set_warning_option("warning_motion", "off")
	manager.reset_flight()
	_cues.clear()
	var snap := _snapshot(PackedStringArray())
	_step(manager, snap, 0.0)
	snap.warnings = PackedStringArray(["far"])
	_step(manager, snap, 1.0)
	_step(manager, snap, 2.10)
	snap.warnings = PackedStringArray()
	_step(manager, snap, 2.20)
	_step(manager, snap, 2.49)
	_check("clear sound waits for quiet", _cues == ["caution"])
	_step(manager, snap, 2.51)
	_step(manager, snap, 3.00)
	_check("repeated empty snapshots produce exactly one all-clear", _cues == ["caution", "cleared"])
	manager.reset_flight()
	_cues.clear()
	_step(manager, snap, 4.0)
	snap.warnings = PackedStringArray(["far"])
	_step(manager, snap, 4.5)
	snap.paused = true
	_step(manager, snap, 4.6)
	_check("pause with unchanged codes retires sound", _cues == ["caution"] and not manager.alert_audio.audio_player().playing)
	snap.paused = false
	_step(manager, snap, 4.7)
	_check("resume with unchanged codes is a silent baseline", _cues == ["caution"])
	snap.warnings = PackedStringArray(["stall", "far"])
	_step(manager, snap, 5.7)
	_check("new danger after resume still plays", _cues == ["caution", "danger"])
	manager.visible = false
	_step(manager, snap, 5.8)
	manager.visible = true
	_step(manager, snap, 5.9)
	_check("hide and reopen with unchanged codes is silent", _cues == ["caution", "danger"]
		and not manager.alert_audio.audio_player().playing)
	_step(manager, snap, 1.0, 6.0)
	_check("rewind with unchanged codes silently rebuilds the rail", _cues == ["caution", "danger"]
		and manager.frames.warnings.codes == PackedStringArray(["stall", "far"]))
	manager.reset_flight()
	_check("reset immediately clears selected codes", manager.frames.warnings.codes.is_empty())
	_step(manager, snap, 1.0, 6.1)
	_check("same codes after reset establish a silent fresh baseline", _cues == ["caution", "danger"]
		and manager.frames.warnings.codes == PackedStringArray(["stall", "far"]))
	snap.warnings = PackedStringArray(["stall", "far", "battery", "experimental"])
	_step(manager, snap, 2.0, 7.0)
	manager.set_warning_option("warning_navigation", false)
	manager.set_warning_option("warning_energy", false)
	manager.set_warning_option("warning_status", false)
	_check("category edits immediately refilter the same raw codes", manager.frames.warnings.codes == PackedStringArray(["stall"]))
	manager.set_warning_option("warning_navigation", true)
	manager.set_warning_option("warning_energy", true)
	manager.set_warning_option("warning_status", true)
	_check("re-enabling categories restores the same raw codes", manager.frames.warnings.codes
		== PackedStringArray(["stall", "battery", "far", "experimental"]))
	manager.set_overlay_visible("warnings", false)
	_check("explicit close clears the rail", not manager.frames.warnings.is_presenting())
	manager.set_overlay_visible("warnings", true)
	_check("reopening restores current selected codes", manager.frames.warnings.codes
		== PackedStringArray(["stall", "battery", "far", "experimental"]))
	var mutable := _snapshot(PackedStringArray(["far"]))
	_step(manager, mutable, 3.0, 8.0)
	mutable.warnings.append("stall")
	_step(manager, mutable, 3.1, 8.1)
	_check("in-place raw-code addition invalidates selection", mutable.warnings.has("stall")
		and manager.frames.warnings.codes == PackedStringArray(["stall", "far"]))
	mutable.warnings.remove_at(mutable.warnings.find("stall"))
	_step(manager, mutable, 3.2, 8.2)
	_check("in-place raw-code removal invalidates selection", manager.frames.warnings.codes == PackedStringArray(["far"]))


func _locale(manager: CanvasLayer) -> void:
	manager.set_warning_option("warning_motion", "playful")
	manager.set_warning_option("warning_limit", 1)
	manager.reset_flight()
	var snap := _snapshot(PackedStringArray(["stall", "low", "far"]))
	_step(manager, snap, 10.0)
	await process_frame
	await process_frame
	var rail: Control = manager.frames.warnings
	var card: Control = rail.chips.get_child(0)
	var original_id := card.get_instance_id()
	var entry: Tween = rail.get("_entrance")
	if entry != null and entry.is_valid(): entry.custom_step(1.0)
	_check("English active and overflow warnings are present", card.find_child("Headline", true, false).text == "STALL"
		and rail.summary.find_child("Detail", true, false).text == "LOW ALTITUDE")
	TranslationServer.set_locale("es")
	await process_frame
	await process_frame
	_check("locale updates active and overflow text with identical codes", rail.chips.get_child(0).get_instance_id() == original_id
		and rail.codes == PackedStringArray(["stall", "low", "far"])
		and card.find_child("Headline", true, false).text == "PÉRDIDA"
		and rail.summary.find_child("Detail", true, false).text == "POCA ALTURA")
	_check("locale change does not start a new alert entrance", rail.get("_entrance") == null)


func _check(label: String, ok: bool) -> void:
	_count += 1
	if not ok:
		_failed += 1
		printerr("FAIL " + label)
