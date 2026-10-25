# Flight overlays (docs/plans/flight-overlays.md): one CanvasLayer holding independent overlays, their presets
# and the player's settings. Reads the session only; it never writes to it, so traces are unaffected.
# main.gd creates it on the Home route (or with --hud=overlays); automation keeps the legacy labels.
extends CanvasLayer

const UiTheme := preload("res://ui/ui_theme.gd")
const Units := preload("res://render/overlays/units.gd")
const Telemetry := preload("res://render/overlays/telemetry.gd")
const Frame := preload("res://render/overlays/overlay_frame.gd")
const FlightData := preload("res://render/overlays/flight_data.gd")
const Transmitter := preload("res://render/overlays/transmitter.gd")
const WindOverlay := preload("res://render/overlays/wind.gd")
const TelemetryPanel := preload("res://render/overlays/telemetry_panel.gd")
const WarningsBar := preload("res://render/overlays/warnings_bar.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const Settings := preload("res://render/overlays/overlay_settings.gd")
const ControlsGuide := preload("res://render/overlays/controls_guide.gd")
const BatteryPanel := preload("res://render/overlays/battery_panel.gd")
const BatterySensors := preload("res://render/overlays/battery_sensors.gd")
const PlayerInstrument := preload("res://render/overlays/player_instrument.gd")
const ClassicInstrument := preload("res://render/overlays/classic_instrument.gd")
const NavigationInstrument := preload("res://render/overlays/navigation_instrument.gd")
const NavigationData := preload("res://render/overlays/navigation_data.gd")
const TrainingInstrument := preload("res://render/overlays/training_instrument.gd")
const SessionStatistics := preload("res://render/overlays/session_statistics.gd")
const FlightMetrics := preload("res://render/overlays/flight_metrics.gd")
const PLAYER_POSITIONS := {speed = Vector2(0, 1), height = Vector2(1, 1), power = Vector2(0, 0), weather = Vector2(1, 0), fuel = Vector2(0, 0.5), trims = Vector2(0.5, 0.82), engine = Vector2(1, 0.53), heading = Vector2(0, 1), airspeed_dial = Vector2(0.25, 1), attitude = Vector2(0.5, 0.82), altimeter = Vector2(0.75, 1), variometer = Vector2(1, 1), pilot_radar = Vector2(0, 1), wind_track = Vector2(1, 1), cruise_efficiency = Vector2(1, 0), maneuver = Vector2(0, 1), glide = Vector2(1, 1), flight_summary = Vector2(1, 0), session_stats = Vector2(0.0, 0.48)}
const FUEL_RESERVE_WARNING_STREAM: AudioStream = preload("res://assets/ui/audio/reject.ogg")

## Emitted after any change the player makes (X, key, dialog); the owner saves it to the preferences.
signal settings_changed(settings: Dictionary)
signal fuel_reserve_warning_requested(sample: Dictionary)

const IDS := Settings.IDS
## Numbers refresh at 10 Hz (readable, less churn); sticks and the visibility of warnings follow every frame.
const TEXT_PERIOD_S := 0.1
const MARGIN := 12.0
## Reserve space beneath O5 for the taller, photographed DS-24 II in O2 at 720p.
const TELEMETRY_RISE := 64.0
const FLIGHT_LAYER := 1
## While the Overlays dialog is open: above the pause menu (10), below the dialog (≥ 12), so every switch shows at once.
const PREVIEW_LAYER := 11

var settings: Dictionary = Settings.DEFAULTS.duplicate(true)
var language := "en"
## Injected by app_root/main. The widget is read-only and does not own or start statistics collection.
var statistics_service: Object
var statistics_aircraft_id := ""
var root: Control
var frames := {}
## The legacy diagnostic texts, written by main.gd exactly as before (input panel, HUD lines, performance line).
var diagnostics_panel: Label
var diagnostics_hud: Label
var performance_label: Label
## BAT-15: the model's true battery charge, in the developer Diagnostics overlay only.
var diagnostics_battery: Label
## BAT-14: what the radio shows of the flight pack; fed at the 10 Hz refresh even while O9 is closed (its alarms
## drive the warnings).
var battery_sensors: RefCounted = BatterySensors.new()
var _since_text := INF
var _last_telemetry := {}
var _warning_codes := PackedStringArray()
var _has_battery := false
var _battery_dock := Vector3(-1.0, -1.0, -1.0)
var _fuel_warning_player: AudioStreamPlayer
var _fuel_state_known := false
var _last_fuel_low := false
var peak_airspeed := NAN
var _peak_time := -INF
var _battery_reading := {}
var _player_theme: Theme
var _settings_applied := false
var _player_layout_pending := false
var navigation_data := NavigationData.new()
var flight_metrics := FlightMetrics.new()


func _init(initial: Variant = Settings.DEFAULTS, interface_language := "en") -> void:
	name = "FlightOverlays"
	layer = FLIGHT_LAYER # the pause menu (10) and dialogs draw above
	language = interface_language
	root = Control.new()
	root.name = "Root"
	root.theme = UiTheme.build() # Window.theme would not reach a CanvasLayer
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# Share one font atlas per manager, released with the flight. Keep scaling crisp without changing other UI.
	_player_theme = Theme.new()
	_player_theme.default_font = ThemeDB.fallback_font.duplicate()
	if _player_theme.default_font is FontFile:
		(_player_theme.default_font as FontFile).multichannel_signed_distance_field = true
	_fuel_warning_player = AudioStreamPlayer.new()
	_fuel_warning_player.name = "FuelReserveWarning"
	_fuel_warning_player.stream = FUEL_RESERVE_WARNING_STREAM
	_fuel_warning_player.bus = &"Master"
	_fuel_warning_player.volume_db = -12.0
	add_child(_fuel_warning_player)
	_build()
	apply(initial, false)
	visibility_changed.connect(func() -> void:
		if visible: _since_text = INF
	)


func _build() -> void:
	var diagnostics := Frame.new("diagnostics", tr("Diagnostics"))
	diagnostics_panel = Frame.monospace(13)
	diagnostics_panel.name = "Panel"
	diagnostics.body.add_child(diagnostics_panel)
	diagnostics_hud = Frame.monospace(13)
	diagnostics_hud.name = "Hud"
	diagnostics.body.add_child(diagnostics_hud)
	diagnostics_battery = Frame.monospace(13)
	diagnostics_battery.name = "Battery"
	diagnostics_battery.visible = false
	diagnostics.body.add_child(diagnostics_battery)
	_place(diagnostics, Control.PRESET_TOP_LEFT)
	var performance := Frame.new("performance", tr("Performance"))
	performance_label = Frame.monospace(13)
	performance_label.name = "Numbers"
	performance.body.add_child(performance_label)
	_place(performance, Control.PRESET_CENTER_BOTTOM)
	_place(FlightData.new(), Control.PRESET_BOTTOM_LEFT)
	_place(Transmitter.new(), Control.PRESET_BOTTOM_RIGHT)
	_place(WindOverlay.new(), Control.PRESET_TOP_RIGHT)
	var telemetry := TelemetryPanel.new()
	_place(telemetry, Control.PRESET_CENTER_RIGHT)
	telemetry.offset_top -= TELEMETRY_RISE
	telemetry.offset_bottom -= TELEMETRY_RISE
	_place(WarningsBar.new(), Control.PRESET_CENTER_TOP)
	var controls := ControlsGuide.new()
	_place(controls, Control.PRESET_TOP_LEFT)
	_place(BatteryPanel.new(), Control.PRESET_CENTER_RIGHT) # docked by _dock_battery()
	for id: String in PLAYER_POSITIONS:
		var widget: Control
		if id == "session_stats":
			widget = SessionStatistics.new()
		elif id in Settings.NAVIGATION_IDS:
			widget = NavigationInstrument.new(id)
		elif id in Settings.TRAINING_IDS:
			widget = TrainingInstrument.new(id)
		elif id in Settings.CLASSIC_IDS:
			widget = ClassicInstrument.new(id)
		else:
			widget = PlayerInstrument.new(id)
		widget.theme = _player_theme
		_place(widget, Control.PRESET_TOP_LEFT)
		widget.moved.connect(_save_widget_position)
		widget.reset_position_requested.connect(reset_widget_position)
		widget.resized.connect(_queue_player_layout)
	root.resized.connect(_queue_player_layout)
	# Reflow only when layout changes, never once per simulation tick.
	for id: String in ["controls", "diagnostics", "warnings"]:
		frames[id].resized.connect(_dock_diagnostics)
		frames[id].visibility_changed.connect(_dock_diagnostics)
	root.resized.connect(_dock_diagnostics)


func _queue_player_layout() -> void:
	if _player_layout_pending: return
	_player_layout_pending = true
	_flush_player_layout.call_deferred()


func _flush_player_layout() -> void:
	if _player_layout_pending: _layout_player_widgets()


func _layout_player_widgets() -> void:
	_player_layout_pending = false
	var positions: Dictionary = settings.get("positions", {})
	for id: String in PLAYER_POSITIONS:
		if not frames.has(id): continue
		var point: Vector2 = PLAYER_POSITIONS[id]
		if positions.has(id): point = Vector2(positions[id][0], positions[id][1])
		frames[id].place_normalized(point)


func _save_widget_position(id: String, point: Vector2) -> void:
	var next := settings.duplicate(true)
	var positions: Dictionary = next.get("positions", {})
	positions[id] = [point.x, point.y]
	next.positions = positions
	apply(next)


func set_layout_locked(on: bool) -> void:
	var next := settings.duplicate(true)
	next.layout_locked = on
	apply(next)


func set_widget_option(key: String, value: Variant) -> void:
	if key not in ["widget_size", "widget_opacity", "widget_compact", "session_stats_scope"]:
		return
	var next := settings.duplicate(true)
	next[key] = value
	apply(next)


func reset_widget_positions() -> void:
	var next := settings.duplicate(true)
	next.erase("positions")
	apply(next)


## Restore one widget without discarding the rest of a custom layout.
func reset_widget_position(id: String) -> void:
	if id not in Settings.PLAYER_IDS or bool(settings.get("layout_locked", false)): return
	var next := settings.duplicate(true)
	var positions: Dictionary = next.get("positions", {})
	if positions.has(id):
		positions.erase(id)
		if positions.is_empty(): next.erase("positions")
		else: next.positions = positions
		apply(next)
	elif frames.has(id):
		frames[id].place_normalized(PLAYER_POSITIONS[id])


## A session reset, even at identical sampled time, starts fresh flight extrema and battery sensors.
func reset_flight() -> void:
	peak_airspeed = NAN
	_peak_time = -INF
	battery_sensors.reset()
	navigation_data.reset()
	flight_metrics.reset()
	_battery_reading = {}
	_fuel_state_known = false
	_since_text = INF
	for id: String in PLAYER_POSITIONS:
		frames[id].reset_flight()


## Keep the guide and diagnostic header independently readable and clickable.
func _dock_diagnostics() -> void:
	var panel: Control = frames.diagnostics
	var x := MARGIN
	var y := MARGIN
	if frames.controls.visible:
		x += frames.controls.size.x + MARGIN
	if frames.warnings.visible:
		y += frames.warnings.size.y + MARGIN
	# Narrow-window fallback keeps the close button on screen.
	x = minf(x, maxf(MARGIN, root.size.x - panel.size.x - MARGIN))
	panel.position = Vector2(x, y)


func _place(overlay: Control, preset: Control.LayoutPreset) -> void:
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	# Grow away from the anchored edges so a longer text never pushes an overlay off screen.
	match preset:
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM:
			overlay.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_RIGHT, Control.PRESET_CENTER_LEFT:
			overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
		_:
			overlay.grow_vertical = Control.GROW_DIRECTION_END
	match preset:
		Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT:
			overlay.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM:
			overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_:
			overlay.grow_horizontal = Control.GROW_DIRECTION_END
	overlay.close_requested.connect(func(id: String) -> void: set_overlay_visible(id, false))
	frames[overlay.get("id")] = overlay


## Applies changed settings only. A no-op neither redraws widgets nor asks the owner to save again.
func apply(value: Variant, announce := true) -> void:
	var next := Settings.validate(value)
	if _settings_applied and next == settings: return
	var first := not _settings_applied
	var previous := settings
	settings = next
	_settings_applied = true
	var visibility_changed: bool = first or previous.visible != settings.visible
	var appearance_changed := first or ["widget_size", "widget_opacity", "widget_compact"].any(
		func(key: String) -> bool: return previous.get(key) != settings.get(key))
	var layout_changed := first or ["positions", "widget_size", "widget_compact"].any(
		func(key: String) -> bool: return previous.get(key) != settings.get(key))
	var lock_changed: bool = first or previous.get("layout_locked", false) != settings.get("layout_locked", false)
	var statistics_scope_changed: bool = first or previous.get("session_stats_scope", "all") != settings.get("session_stats_scope", "all")
	if first or previous.radio_model != settings.radio_model:
		frames.transmitter.set_radio_model(settings.radio_model)
	if visibility_changed:
		for id: String in IDS:
			var on: bool = settings.visible.has(id)
			if id == "warnings":
				frames[id].visible = on and not _warning_codes.is_empty()
			elif id == "battery":
				frames[id].visible = on and _has_battery
			else:
				frames[id].visible = on
		if not frames.cruise_efficiency.visible: navigation_data.reset()
	if first or Settings.battery_detailed(previous) != Settings.battery_detailed(settings):
		frames.battery.set_detailed(Settings.battery_detailed(settings))
	if lock_changed or appearance_changed:
		for id: String in PLAYER_POSITIONS:
			if lock_changed: frames[id].set_locked(bool(settings.get("layout_locked", false)))
			if appearance_changed:
				frames[id].set_appearance(str(settings.get("widget_size", "normal")), float(settings.get("widget_opacity", 0.94)), bool(settings.get("widget_compact", false)))
	if layout_changed or visibility_changed: _layout_player_widgets()
	if visibility_changed: _dock_battery()
	if visibility_changed or previous.units != settings.units or previous.stick_mode != settings.stick_mode or statistics_scope_changed:
		_since_text = INF # changed readings/newly opened instruments refresh at once
	if announce:
		settings_changed.emit(settings.duplicate(true))


## Live preview for the pause-menu dialog: shown above the pause menu while `on`; back to the flight layer and hidden
## (the paused picture shows the airplane alone) when the dialog closes.
func preview(on: bool) -> void:
	layer = PREVIEW_LAYER if on else FLIGHT_LAYER
	visible = on


func is_overlay_visible(id: String) -> bool:
	return settings.visible.has(id)


func set_overlay_visible(id: String, on: bool) -> void:
	if not IDS.has(id) or is_overlay_visible(id) == on:
		return
	var shown: Array = settings.visible.duplicate()
	if on:
		shown.append(id)
	else:
		shown.erase(id)
	apply(Settings.with_visible(settings, shown))


## [F2]: cycle saved presets in Settings order. A custom set continues with Off.
func cycle_preset() -> void:
	var index: int = Settings.PRESET_ORDER.find(settings.preset)
	set_preset(Settings.PRESET_ORDER[(index + 1) % Settings.PRESET_ORDER.size()])


func set_preset(preset: String) -> void:
	var next := settings.duplicate(true)
	next.preset = preset
	apply(next)


## [F3]: the developer overlays (diagnostics and performance) together, on or off.
func toggle_developer() -> void:
	var on: bool = not Settings.DEVELOPER.any(func(id: String) -> bool: return is_overlay_visible(id))
	var shown: Array = settings.visible.duplicate()
	for id: String in Settings.DEVELOPER:
		shown.erase(id)
		if on:
			shown.append(id)
	apply(Settings.with_visible(settings, shown))


func set_units(system: String) -> void:
	var next := settings.duplicate(true)
	next.units = system
	apply(next)


func set_stick_mode(mode: int) -> void:
	var next := settings.duplicate(true)
	next.stick_mode = mode
	apply(next)


func set_radio_model(model: String) -> void:
	var next := settings.duplicate(true)
	next.radio_model = model
	apply(next)


func unit_system() -> String:
	return Units.resolve(settings.units, language)


## Every frame: advances the refresh clock; true when the numbers are due (then call refresh_numbers()). Building
## the full snapshot only at 10 Hz keeps the per-frame cost to the sticks (HUD-12).
func tick(delta: float) -> bool:
	_since_text += delta
	return _since_text >= TEXT_PERIOD_S


## The 10 Hz part. snap: snapshot() output ({} = no flight to describe).
func refresh_numbers(snap: Dictionary) -> void:
	_last_telemetry = snap.get("telemetry", {})
	var sample_time := float(_last_telemetry.get("time_s", NAN))
	var speed := float(_last_telemetry.get("airspeed", NAN))
	if is_finite(sample_time) and is_finite(speed) and speed >= 0.0:
		if sample_time < _peak_time: reset_flight()
		peak_airspeed = speed if is_nan(peak_airspeed) else maxf(peak_airspeed, speed)
		_peak_time = sample_time
	_since_text = 0.0 # this refresh also satisfies a rewind/reset's pending refresh
	# Constant-size aggregates keep the flight summary complete while its widgets are closed.
	var metrics := flight_metrics.update(_last_telemetry)
	var mass_sample: Dictionary = snap.get("mass_sample", {})
	_update_fuel_warning(mass_sample, bool(snap.get("paused", false)))
	var system := unit_system()
	# Hidden overlays skip their text: a changed label costs a relayout. apply() forces a refresh when one reappears.
	if visible and frames.flight.visible:
		frames.flight.refresh(_last_telemetry, system, mass_sample)
	if visible and frames.wind.visible:
		frames.wind.refresh(_last_telemetry, float(snap.get("view_heading_deg", 0.0)), system)
	if visible and frames.telemetry.visible:
		frames.telemetry.refresh(_last_telemetry, float(snap.get("rpm", 0.0)))
	if visible and frames.transmitter.visible:
		frames.transmitter.footer.text = str(snap.get("radio_status", ""))
	if visible and frames.controls.visible:
		frames.controls.refresh(snap.get("control_guide", {}))
	_warning_codes = snap.get("warnings", PackedStringArray())
	_refresh_battery(snap.get("battery", {}), system)
	var cruise := {}
	if visible and frames.cruise_efficiency.visible:
		cruise = navigation_data.update(_last_telemetry, _battery_reading)
	elif not frames.cruise_efficiency.visible:
		# Menus temporarily hide the layer while simulation time is paused; preserve that window.
		# Only closing/disabling the actual widget discards its samples.
		navigation_data.reset()
	if visible:
		for id: String in PLAYER_POSITIONS:
			if frames[id].visible:
				if id == "session_stats":
					continue # queried below at the same bounded 10 Hz refresh as the other instruments
				elif id in Settings.NAVIGATION_IDS:
					frames[id].refresh_navigation(_last_telemetry, system, _battery_reading, cruise)
				elif id in Settings.TRAINING_IDS:
					frames[id].refresh_training(_last_telemetry, system, peak_airspeed, metrics)
				else:
					frames[id].refresh(_last_telemetry, system, peak_airspeed, _battery_reading, mass_sample, snap.get("trims", {}), float(snap.get("rpm", NAN)))
		if frames.session_stats.visible:
			var scope := str(settings.get("session_stats_scope", "all"))
			var aircraft_id := statistics_aircraft_id if scope == "aircraft" else ""
			var summary: Dictionary = {}
			if statistics_service != null and statistics_service.has_method("query"):
				var result: Variant = statistics_service.call("query", aircraft_id, "session")
				if result is Dictionary:
					summary = result
			frames.session_stats.refresh_statistics(summary, tr("This aircraft") if scope == "aircraft" else tr("All aircraft"))
	frames.warnings.visible = not _warning_codes.is_empty() and is_overlay_visible("warnings")
	if visible and frames.warnings.visible:
		frames.warnings.refresh(_warning_codes)


## BAT-14/15: samples the pack (battery: electrical_state() or {}), shows O9 and the developer truth, and replaces a
## pack_ecm pack's warning codes with the sensors' alarms. Hidden without a dynamic battery.
func _refresh_battery(battery: Dictionary, system: String) -> void:
	_has_battery = battery.get("ok", false)
	var reading: Dictionary = BatterySensors.empty()
	if _has_battery:
		var needs_history: bool = visible and is_overlay_visible("battery") and frames.battery.detailed
		reading = battery_sensors.update(float(battery.get("time_s", _last_telemetry.get("time_s", 0.0))), battery, needs_history)
		if str(battery.get("battery_kind", "")) == "pack_ecm":
			_warning_codes = Telemetry.with_battery_warnings(_warning_codes, Telemetry.battery_warnings(battery, reading.alarms))
	_battery_reading = reading
	frames.battery.visible = _has_battery and is_overlay_visible("battery")
	if visible and frames.battery.visible:
		frames.battery.refresh(reading, system)
		_dock_battery()
	if visible:
		diagnostics_battery.text = BatteryPanel.truth_text(battery) if frames.diagnostics.visible else ""
		diagnostics_battery.visible = not diagnostics_battery.text.is_empty()


## O9 sits centre right: against the edge in the Pilot preset (that side is free there), and left of the Telemetry
## overlay whenever that is shown (Full, Developer). On a screen too narrow for both (≈ 640 px) it stays fully on
## screen over Telemetry. Re-docked only when the layout, the screen or a neighbour's width changes.
func _dock_battery() -> void:
	var panel: Control = frames.battery
	var wanted: Vector2 = panel.get_combined_minimum_size()
	var shift := 0.0
	if frames.telemetry.visible:
		shift = maxf(frames.telemetry.size.x, frames.telemetry.get_combined_minimum_size().x) + MARGIN
		shift = clampf(shift, 0.0, maxf(0.0, root.size.x - wanted.x - 2.0 * MARGIN))
	var key := Vector3(shift, wanted.x, wanted.y)
	if key == _battery_dock:
		return
	_battery_dock = key
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	panel.offset_left -= shift
	panel.offset_right -= shift


## Every frame: sticks() output ({} = nothing to show).
func refresh_sticks(controls: Dictionary) -> void:
	if visible and frames.transmitter.visible and controls.has("sticks"):
		frames.transmitter.refresh(controls.sticks, controls.get("trims", {}), settings.stick_mode)


## tick + refresh_numbers when due + refresh_sticks, for a caller holding one combined snapshot.
func update(snap: Dictionary, delta: float) -> void:
	if tick(delta):
		refresh_numbers(snap)
	refresh_sticks(snap)


## Everything the overlays show, read from a FlightSession without changing it. Returns {} when the session has no
## flight to describe (invalid data, scripted or synthetic poses). pilot: the field's pilot dictionary; span: model
## span (m); view_heading_deg: where the camera looks.
static func snapshot(session: Node, pilot: Dictionary, span: float, experimental: bool, view_heading_deg: float) -> Dictionary:
	if session == null or not session.aircraft.get("ok", false):
		return {}
	var sim: Node = session.sim
	var s: PackedFloat64Array = sim.state
	var time_s: float = sim.time()
	var wind: PackedFloat64Array = session.wind_at(time_s)
	var air: Dictionary = session.air_data(s, time_s)
	var ground: PackedFloat64Array = GroundTerrain.sample(s[0], s[1], session.ground_surfaces)
	# FUEL-06: the load factor divides by the live mass (fuel burned), not the initial wet build.
	var live: Dictionary = session.mass_properties() if session.has_method("mass_properties") else {}
	var t := Telemetry.compute(s, wind, air, {
		pilot_ned = [float(pilot.get("north", 0.0)), float(pilot.get("east", 0.0)), float(pilot.get("down", 0.0)) - float(pilot.get("eye_height", 0.0))],
		terrain_up = ground[0],
		last_loads = sim.last_loads, mass = float(live.mass_kg) if live.get("ok", false) else sim.mass, gravity = sim.gravity,
		throttle = sim.inputs[3], time_s = time_s,
	})
	var envelope: Dictionary = session.aircraft.model.get("envelope", {})
	var radio: RefCounted = session.radio
	var battery: Dictionary = session.electrical_state() if session.battery_is_dynamic() else {}
	var warnings := Telemetry.warnings(t, {
		radio_connected = radio.connected, armed = radio.armed, pause_reason = session.pause_reason,
		controller_kind = radio.profile.get("kind", "radio"), controller_lost = bool(session.get("_controller_lost")),
		stall_pos_deg = rad_to_deg(float(envelope.a1)) if envelope.has("a1") else NAN,
		stall_neg_deg = rad_to_deg(float(envelope.n1)) if envelope.has("n1") else NAN,
		span = span, battery = battery, mass_sample = live, experimental = experimental,
	})
	return {
		telemetry = t, warnings = warnings, view_heading_deg = view_heading_deg, rpm = sim.aux[0], battery = battery,
		mass_sample = live, paused = sim.paused, trims = session.trims.duplicate(),
		radio_status = radio_status(session),
		control_guide = {
			connected = radio.connected, profile = radio.profile,
			device_name = radio.device_name, device_info = { name = radio.device_name },
		},
	}


## One audible cue per above-to-reserve crossing. Initial low fuel is shown but silent; refuelling above the
## threshold rearms the next crossing. The sample is accepted flight state, and Master carries user mute/volume.
func _update_fuel_warning(mass_sample: Dictionary, paused: bool) -> void:
	if not mass_sample.get("ok", false) or not mass_sample.get("finite_fuel", false):
		_fuel_state_known = false
		_last_fuel_low = false
		return
	var low := bool(mass_sample.get("low_fuel", false))
	if _fuel_state_known and not _last_fuel_low and low and not paused:
		var accepted := mass_sample.duplicate(true)
		fuel_reserve_warning_requested.emit(accepted)
		_fuel_warning_player.play()
	_fuel_state_known = true
	_last_fuel_low = low


## The stick positions as the pilot holds them, and the trims; {} without a session. The throttle is the stick, not
## the command a radio holds at idle until armed.
static func sticks(session: Node) -> Dictionary:
	if session == null:
		return {}
	var commands: Dictionary = session.commands
	return {
		sticks = { roll = commands.roll, pitch = commands.pitch, yaw = commands.yaw,
			throttle = session.raw.throttle if session.radio.connected else commands.throttle },
		trims = session.trims,
	}


## The transmitter footer: device, rate profile and arming, in the player's words.
static func radio_status(session: Node) -> String:
	var radio: RefCounted = session.radio
	var parts := PackedStringArray()
	if not radio.connected:
		parts.append(TranslationServer.translate("Keyboard"))
	else:
		var kind: String = "Gamepad" if radio.profile.get("kind", "radio") == "gamepad" else "Radio"
		parts.append(TranslationServer.translate(kind))
		if kind == "Radio":
			parts.append(TranslationServer.translate("ARMED") if radio.armed else TranslationServer.translate("SAFE"))
	parts.append(TranslationServer.translate("Rates: normal") if session.rates_active() else TranslationServer.translate("Rates: full"))
	return " · ".join(parts)
