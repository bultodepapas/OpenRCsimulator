# Flight overlays (docs/plans/flight-overlays.md): one CanvasLayer holding seven independent overlays, their presets
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

## Emitted after any change the player makes (X, key, dialog); the owner saves it to the preferences.
signal settings_changed(settings: Dictionary)

const IDS := Settings.IDS
## Numbers refresh at 10 Hz (readable, less churn); sticks and the visibility of warnings follow every frame.
const TEXT_PERIOD_S := 0.1
const MARGIN := 12.0
const FLIGHT_LAYER := 1
## While the Overlays dialog is open: above the pause menu (10), below the dialog (≥ 12), so every switch shows at once.
const PREVIEW_LAYER := 11

var settings: Dictionary = Settings.DEFAULTS.duplicate(true)
var language := "en"
var root: Control
var frames := {}
## The legacy diagnostic texts, written by main.gd exactly as before (input panel, HUD lines, performance line).
var diagnostics_panel: Label
var diagnostics_hud: Label
var performance_label: Label
var _since_text := INF
var _last_telemetry := {}
var _warning_codes := PackedStringArray()


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
	_build()
	apply(initial, false)


func _build() -> void:
	var diagnostics := Frame.new("diagnostics", tr("Diagnostics"))
	diagnostics_panel = Frame.monospace(13)
	diagnostics_panel.name = "Panel"
	diagnostics.body.add_child(diagnostics_panel)
	diagnostics_hud = Frame.monospace(13)
	diagnostics_hud.name = "Hud"
	diagnostics.body.add_child(diagnostics_hud)
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
	_place(WarningsBar.new(), Control.PRESET_CENTER_TOP)


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


## Replaces the settings (validated); `announce` emits settings_changed.
func apply(value: Variant, announce := true) -> void:
	settings = Settings.validate(value)
	for id: String in IDS:
		var on: bool = settings.visible.has(id)
		if id == "warnings":
			frames[id].visible = on and not _warning_codes.is_empty()
		else:
			frames[id].visible = on
	_since_text = INF # show the new choice at once
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


## [F2]: Off → Pilot → Full → Developer → Off. A custom set continues with Off.
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


func unit_system() -> String:
	return Units.resolve(settings.units, language)


## Every frame: advances the refresh clock; true when the numbers are due (then call refresh_numbers()). Building
## the full snapshot only at 10 Hz keeps the per-frame cost to the sticks (HUD-12).
func tick(delta: float) -> bool:
	_since_text += delta
	return _since_text >= TEXT_PERIOD_S


## The 10 Hz part. snap: snapshot() output ({} = no flight to describe).
func refresh_numbers(snap: Dictionary) -> void:
	_since_text = 0.0
	_last_telemetry = snap.get("telemetry", {})
	var system := unit_system()
	# Hidden overlays skip their text: a changed label costs a relayout. apply() forces a refresh when one reappears.
	if frames.flight.visible:
		frames.flight.refresh(_last_telemetry, system)
	if frames.wind.visible:
		frames.wind.refresh(_last_telemetry, float(snap.get("view_heading_deg", 0.0)), system)
	if frames.telemetry.visible:
		frames.telemetry.refresh(_last_telemetry, float(snap.get("rpm", 0.0)))
	if frames.transmitter.visible:
		frames.transmitter.footer.text = str(snap.get("radio_status", ""))
	_warning_codes = snap.get("warnings", PackedStringArray())
	frames.warnings.visible = frames.warnings.refresh(_warning_codes) and is_overlay_visible("warnings")


## Every frame: sticks() output ({} = nothing to show).
func refresh_sticks(controls: Dictionary) -> void:
	if controls.has("sticks"):
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
	var t := Telemetry.compute(s, wind, air, {
		pilot_ned = [float(pilot.get("north", 0.0)), float(pilot.get("east", 0.0)), float(pilot.get("down", 0.0)) - float(pilot.get("eye_height", 0.0))],
		terrain_up = ground[0],
		last_loads = sim.last_loads, mass = sim.mass, gravity = sim.gravity,
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
		span = span, battery = battery, experimental = experimental,
	})
	return {
		telemetry = t, warnings = warnings, view_heading_deg = view_heading_deg, rpm = sim.aux[0],
		radio_status = radio_status(session),
	}


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
		parts.append(TranslationServer.translate("ARMED") if radio.armed else TranslationServer.translate("SAFE"))
	parts.append(TranslationServer.translate("Rates: normal") if session.rates_active() else TranslationServer.translate("Rates: full"))
	return " · ".join(parts)
