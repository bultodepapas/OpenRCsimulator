# Flight overlay settings (HUD-03/06): the overlay IDs, presets and validation shared by the overlay manager and the
# preferences file. Pure; no nodes. A settings dictionary: { preset, visible: [ids], units, stick_mode }.
extends RefCounted

const Units := preload("res://render/overlays/units.gd")

## BAT-15: "battery" is O9; it shows only when the aircraft has a dynamic battery.
const IDS := ["flight", "transmitter", "warnings", "wind", "telemetry", "diagnostics", "performance", "controls", "battery"]
const PRESET_ORDER := ["off", "pilot", "full", "developer"]
const PRESETS := {
	off = [],
	pilot = ["flight", "transmitter", "warnings", "wind", "controls", "battery"],
	full = ["flight", "transmitter", "warnings", "wind", "telemetry", "controls", "battery"],
	developer = ["flight", "transmitter", "warnings", "wind", "telemetry", "diagnostics", "performance", "controls", "battery"],
}
const DEVELOPER := ["diagnostics", "performance"]
## BAT-15: the Battery overlay is detailed while this overlay is shown (Full, Developer), compact otherwise (Pilot).
## Derived from the visible set, so the saved [hud] keys carry it without a new preference.
const BATTERY_DETAIL_WITH := "telemetry"
## D2/D3/D4: Pilot preset, units by language, Mode 2.
const DEFAULTS := { preset = "pilot", visible = ["flight", "transmitter", "warnings", "wind", "controls", "battery"], units = "auto", stick_mode = 2 }


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
