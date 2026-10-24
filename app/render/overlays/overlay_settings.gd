# Flight overlay settings (HUD-03/06): the overlay IDs, presets and validation shared by the overlay manager and the
# preferences file. Pure; no nodes. A settings dictionary also accepts optional player widget layout and style keys.
extends RefCounted

const Units := preload("res://render/overlays/units.gd")

## BAT-15: "battery" is O9; it shows only when the aircraft has a dynamic battery.
const CLASSIC_IDS := ["airspeed_dial", "attitude", "altimeter", "heading", "variometer"]
const IDS := ["flight", "transmitter", "warnings", "wind", "telemetry", "diagnostics", "performance", "controls", "battery", "speed", "height", "power", "weather", "fuel", "trims", "engine", "airspeed_dial", "attitude", "altimeter", "heading", "variometer"]
const PLAYER_IDS := ["speed", "height", "power", "weather", "fuel", "trims", "engine", "airspeed_dial", "attitude", "altimeter", "heading", "variometer"]
const WIDGET_SIZES := ["small", "normal", "large"]
const WIDGET_SIZE_SCALES := {"small": 0.85, "normal": 1.0, "large": 1.2}
const DEFAULT_WIDGET_SIZE := "normal"
const WIDGET_OPACITY_STEPS := [0.80, 0.94, 1.0]
const DEFAULT_WIDGET_OPACITY := 0.94
const WIDGET_OPACITY_MIN := 0.80
const WIDGET_OPACITY_MAX := 1.0
const DEFAULT_WIDGET_COMPACT := false
const PRESET_ORDER := ["off", "pilot", "full", "developer", "player", "instruments", "cockpit"]
const PRESETS := {
	off = [],
	pilot = ["flight", "transmitter", "warnings", "wind", "controls", "battery"],
	full = ["flight", "transmitter", "warnings", "wind", "telemetry", "controls", "battery"],
	developer = ["flight", "transmitter", "warnings", "wind", "telemetry", "diagnostics", "performance", "controls", "battery"],
	player = ["warnings", "speed", "height", "power", "weather"],
	instruments = ["warnings", "speed", "height", "power", "weather", "fuel", "trims", "engine"],
	cockpit = ["warnings", "airspeed_dial", "attitude", "altimeter", "heading", "variometer"],
}
const DEVELOPER := ["diagnostics", "performance"]
const RADIO_MODELS := ["jeti_ds24_ii", "radiolink_t16d"]
## BAT-15: the Battery overlay is detailed while this overlay is shown (Full, Developer), compact otherwise (Pilot).
## Derived from the visible set, so the saved [hud] keys carry it without a new preference.
const BATTERY_DETAIL_WITH := "telemetry"
## D2/D3/D4: Pilot preset, units by language, Mode 2.
const DEFAULTS := { preset = "pilot", visible = ["flight", "transmitter", "warnings", "wind", "controls", "battery"], units = "auto", stick_mode = 2, radio_model = "jeti_ds24_ii" }


## Settings from anything (a preferences file, a dialog): always a complete valid dictionary, defaults where invalid.
## A named preset defines the visible set; only "custom" keeps its own list.
static func validate(value: Variant) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	if typeof(value) != TYPE_DICTIONARY:
		return out
	var preset: Variant = value.get("preset")
	if typeof(preset) == TYPE_STRING and (PRESETS.has(preset) or preset == "custom"):
		out.preset = preset
	var units: Variant = value.get("units")
	if typeof(units) == TYPE_STRING and Units.SYSTEMS.has(units):
		out.units = units
	var mode: Variant = value.get("stick_mode")
	if typeof(mode) == TYPE_INT and (mode == 1 or mode == 2):
		out.stick_mode = mode
	var radio_model: Variant = value.get("radio_model")
	if typeof(radio_model) == TYPE_STRING and RADIO_MODELS.has(radio_model):
		out.radio_model = radio_model
	var widget_size: Variant = value.get("widget_size")
	if typeof(widget_size) == TYPE_STRING and WIDGET_SIZES.has(widget_size):
		out.widget_size = widget_size
	var widget_opacity: Variant = value.get("widget_opacity")
	if _is_finite_number(widget_opacity):
		out.widget_opacity = clampf(float(widget_opacity), WIDGET_OPACITY_MIN, WIDGET_OPACITY_MAX)
	var widget_compact: Variant = value.get("widget_compact")
	if typeof(widget_compact) == TYPE_BOOL:
		out.widget_compact = widget_compact
	# These are optional so legacy settings keep their exact shape. Validate them before a preset returns early.
	var raw_positions: Variant = value.get("positions")
	if typeof(raw_positions) == TYPE_DICTIONARY:
		var positions: Dictionary = {}
		for id: String in PLAYER_IDS:
			if not raw_positions.has(id):
				continue
			var raw_pair: Variant = raw_positions[id]
			if typeof(raw_pair) != TYPE_ARRAY:
				continue
			var pair: Array = raw_pair
			if pair.size() != 2 or not _is_finite_number(pair[0]) or not _is_finite_number(pair[1]):
				continue
			positions[id] = [clampf(float(pair[0]), 0.0, 1.0), clampf(float(pair[1]), 0.0, 1.0)]
		out.positions = positions
	var layout_locked: Variant = value.get("layout_locked")
	if typeof(layout_locked) == TYPE_BOOL:
		out.layout_locked = layout_locked
	if out.preset != "custom":
		out.visible = PRESETS[out.preset].duplicate()
		return out
	out.visible = []
	var shown: Variant = value.get("visible")
	if typeof(shown) == TYPE_ARRAY or typeof(shown) == TYPE_PACKED_STRING_ARRAY:
		for id: String in IDS: # canonical order, duplicates and unknown names dropped
			if id in shown:
				out.visible.append(id)
	return out


## The preset whose overlay set equals `ids`, or "custom".
static func preset_for(ids: Array) -> String:
	for preset: String in PRESET_ORDER:
		var wanted: Array = PRESETS[preset]
		if wanted.size() == ids.size() and wanted.all(func(id: String) -> bool: return ids.has(id)):
			return preset
	return "custom"


## BAT-15: whether the Battery overlay uses its detailed layout under `settings`.
static func battery_detailed(settings: Dictionary) -> bool:
	return Array(settings.get("visible", [])).has(BATTERY_DETAIL_WITH)


## `settings` with `ids` shown and the matching preset name.
static func with_visible(settings: Dictionary, ids: Array) -> Dictionary:
	var next := settings.duplicate(true)
	next.visible = []
	for id: String in IDS:
		if id in ids:
			next.visible.append(id)
	next.preset = preset_for(next.visible)
	return next


static func _is_finite_number(value: Variant) -> bool:
	var value_type: int = typeof(value)
	return (value_type == TYPE_INT or value_type == TYPE_FLOAT) and is_finite(float(value))
