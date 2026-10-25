extends RefCounted
class_name LightingProfile

const FORMAT := "openrc-aircraft-lighting"
const VERSION := 1
const PRESET_REVISION := 1
const MAX_ZONES := 32
const MAX_EFFECTS := 4
const MAX_ENABLED_EFFECTS := 2
const MAX_CUES := 32
const MAX_SEQUENCE_TICKS := 14400
const MAX_PROFILE_NODES := 6144
const MAX_PROFILE_BYTES := 24576
const MAX_STRING_CHARS := 256

const PRESET_IDS: Array[String] = [
	"classic_rc",
	"night_radian",
	"neon_rgb",
	"night_aerobatics",
	"festival",
	"custom",
]
const ZONE_IDS: Array[String] = [
	"nav_left",
	"nav_right",
	"nav_tail",
	"strobe_left",
	"strobe_right",
	"strobe_dorsal",
	"strobe_ventral",
	"strip_left",
	"strip_right",
	"strip_top_left",
	"strip_top_right",
	"strip_belly",
	"landing_lamp",
]
const PATTERN_IDS: Array[String] = [
	"steady",
	"breath",
	"pulse",
	"chase",
	"wave",
	"rainbow",
	"segments",
	"sequence",
]
const REACTIVE_SOURCES: Array[String] = ["none", "throttle", "airspeed", "roll_rate", "pitch_rate"]
const EFFECT_KINDS: Array[String] = ["spark", "trail", "burst"]
const EFFECT_ANCHOR_IDS: Array[String] = ["vfx_tip_left", "vfx_tip_right"]


static func defaults() -> Dictionary:
	return {
		"format": FORMAT,
		"version": VERSION,
		"selection": "inherit",
		"preset_id": "",
		"preset_revision": 0,
		"orientation_lock": false,
		"brightness": 1.0,
		"visual_seed": 0,
		"zones": [],
		"effects": [],
		"sequence": [],
	}


static func label(id: String) -> String:
	match id:
		"classic_rc": return "Classic RC"
		"night_radian": return "Night Radian"
		"neon_rgb": return "Neon RGB"
		"night_aerobatics": return "Night Aerobatics"
		"festival": return "Festival / Fireworks"
		"custom": return "Custom"
		_: return ""


static func preset(id: String) -> Dictionary:
	if not PRESET_IDS.has(id):
		return {}
	var checked: Dictionary = validate(_preset_payload(id))
	if not checked.ok:
		return {}
	return checked.profile


static func validate(raw: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not _preflight_json_bounds(raw, errors):
		return {"ok": false, "errors": errors, "profile": {}}
	if not _exact_keys(raw, [
		"format", "version", "selection", "preset_id", "preset_revision",
		"orientation_lock", "brightness", "visual_seed", "zones", "effects", "sequence",
	], [], "profile", errors):
		return {"ok": false, "errors": errors, "profile": {}}

	if raw.format != FORMAT:
		_error(errors, "profile.format must be %s" % FORMAT)
	if _integer(raw.version, "profile.version", 1, 1, errors) != VERSION:
		_error(errors, "profile.version is unsupported")

	var selection := _string(raw.selection, "profile.selection", 16, errors)
	if not ["inherit", "preset", "custom", "disabled"].has(selection):
		_error(errors, "profile.selection is unsupported")
	var preset_id := _string(raw.preset_id, "profile.preset_id", 32, errors, true)
	var preset_revision := _integer(raw.preset_revision, "profile.preset_revision", 0, PRESET_REVISION, errors)
	var orientation_lock := _boolean(raw.orientation_lock, "profile.orientation_lock", errors)
	var brightness := _number(raw.brightness, "profile.brightness", 0.0, 2.0, errors)
	var visual_seed := _integer(raw.visual_seed, "profile.visual_seed", 0, 2147483647, errors)

	var zones := _normalize_zones(raw.zones, errors)
	var effects := _normalize_effects(raw.effects, errors)
	var sequence := _normalize_sequence(raw.sequence, errors)

	match selection:
		"inherit", "disabled":
			if not preset_id.is_empty() or preset_revision != 0:
				_error(errors, "profile.%s must use an empty preset id and revision 0" % selection)
			if not zones.is_empty() or not effects.is_empty() or not sequence.is_empty():
				_error(errors, "profile.%s must have empty zones, effects, and sequence" % selection)
		"preset":
			if not _is_base_preset(preset_id) or preset_revision != PRESET_REVISION:
				_error(errors, "profile.preset must pin a supported preset at revision 1")
		"custom":
			if not _is_base_preset(preset_id) and preset_id != "aircraft_default":
				_error(errors, "profile.custom must pin a supported base preset or aircraft_default")
			if preset_revision != PRESET_REVISION:
				_error(errors, "profile.custom must pin base revision 1")
	
	var zone_ids: Dictionary = {}
	var sequence_zone_ids: Array[String] = []
	for zone: Dictionary in zones:
		zone_ids[zone.id] = true
		if zone.pattern.id == "sequence":
			sequence_zone_ids.append(zone.id)
	if not sequence.is_empty() and sequence_zone_ids.is_empty():
		_error(errors, "profile.sequence requires at least one sequence zone")
	if sequence.is_empty() and not sequence_zone_ids.is_empty():
		_error(errors, "sequence zones require at least one cue")
	for cue: Dictionary in sequence:
		for cue_zone_id: String in cue.zone_ids:
			if not zone_ids.has(cue_zone_id):
				_error(errors, "profile.sequence cue %s references unknown zone %s" % [cue.id, cue_zone_id])

	var effect_by_anchor: Dictionary = {}
	for effect: Dictionary in effects:
		effect_by_anchor[effect.anchor_id] = effect
	for cue: Dictionary in sequence:
		for anchor_id: String in cue.effect_anchor_ids:
			if not effect_by_anchor.has(anchor_id):
				_error(errors, "profile.sequence cue %s references unknown effect %s" % [cue.id, anchor_id])
			elif not effect_by_anchor[anchor_id].enabled:
				_error(errors, "profile.sequence cue %s references disabled effect %s" % [cue.id, anchor_id])

	if not errors.is_empty():
		return {"ok": false, "errors": errors, "profile": {}}
	var canonical := {
		"format": FORMAT,
		"version": VERSION,
		"selection": selection,
		"preset_id": preset_id,
		"preset_revision": preset_revision,
		"orientation_lock": orientation_lock,
		"brightness": brightness,
		"visual_seed": visual_seed,
		"zones": zones,
		"effects": effects,
		"sequence": sequence,
	}
	return {"ok": true, "errors": [], "profile": canonical}


static func _preset_payload(id: String) -> Dictionary:
	var selection := "preset"
	var base_id := id
	if id == "custom":
		selection = "custom"
		base_id = "classic_rc"
	var profile := defaults()
	profile.selection = selection
	profile.preset_id = base_id
	profile.preset_revision = PRESET_REVISION
	profile.orientation_lock = id == "night_aerobatics"
	profile.brightness = 0.8 if id == "night_radian" else (0.75 if id == "neon_rgb" else (0.9 if id == "night_aerobatics" else (0.7 if id == "festival" else 1.0)))

	match id:
		"classic_rc", "custom":
			profile.zones = [
				_zone("nav_left", ["#FF241C"]),
				_zone("nav_right", ["#22E85B"]),
				_zone("nav_tail", ["#FFFFFF"]),
				_zone("strobe_left", ["#FFFFFF"]),
				_zone("strobe_right", ["#FFFFFF"]),
				_zone("strobe_dorsal", ["#FFFFFF"]),
				_zone("strobe_ventral", ["#FFFFFF"]),
				_zone("landing_lamp", ["#FFF1D6"]),
			]
		"night_radian":
			profile.zones = _navigation_zones()
			profile.zones.append(_zone("strip_left", ["#20DFFF", "#794CFF", "#FF38A8", "#FFBF4A"], "wave", 1920, 0.0, 0.12, 0.5, false, 16, "none", 0.0, 0.2))
			profile.zones.append(_zone("strip_right", ["#20DFFF", "#794CFF", "#FF38A8", "#FFBF4A"], "wave", 1920, 0.0, 0.12, 0.5, false, 16, "none", 0.0, 0.2))
			profile.zones.append(_zone("strip_top_left", ["#FFBF4A"], "steady", 240, 0.0, 1.0, 0.5, false, 1, "none", 0.0, 0.5))
			profile.zones.append(_zone("strip_top_right", ["#FFBF4A"], "steady", 240, 0.0, 1.0, 0.5, false, 1, "none", 0.0, 0.5))
			profile.zones.append(_zone("strip_belly", ["#20DFFF"], "steady", 240, 0.0, 1.0, 0.5, false, 1, "none", 0.0, 0.5))
		"neon_rgb":
			profile.zones = _navigation_zones()
			profile.zones.append(_zone("strip_left", ["#20DFFF", "#794CFF", "#FF38A8"], "chase", 960, 0.0, 0.18, 0.5, false, 16))
			profile.zones.append(_zone("strip_right", ["#20DFFF", "#794CFF", "#FF38A8"], "chase", 960, 0.0, 0.18, 0.5, false, 16))
			profile.zones.append(_zone("strip_top_left", ["#FFB34A"], "steady"))
			profile.zones.append(_zone("strip_top_right", ["#FFB34A"], "steady"))
			profile.zones.append(_zone("strip_belly", ["#20DFFF"], "steady"))
		"night_aerobatics":
			profile.zones = _navigation_zones()
			profile.zones.append(_zone("strip_left", ["#20DFFF", "#794CFF"], "breath", 1440, 0.0, 0.18, 0.5, false, 1, "roll_rate", 0.2))
			profile.zones.append(_zone("strip_right", ["#20DFFF", "#794CFF"], "breath", 1440, 0.0, 0.18, 0.5, false, 1, "roll_rate", 0.2))
			profile.zones.append(_zone("strip_top_left", ["#FFBF4A"], "steady", 240, 0.0, 1.0, 0.5, false, 1, "throttle", 0.15))
			profile.zones.append(_zone("strip_top_right", ["#FFBF4A"], "steady", 240, 0.0, 1.0, 0.5, false, 1, "throttle", 0.15))
			profile.zones.append(_zone("strip_belly", ["#20DFFF"], "steady"))
			profile.effects = [
				_effect("vfx_tip_left", "spark", false, 0.3, 60, false),
				_effect("vfx_tip_right", "spark", false, 0.3, 60, false),
			]
		"festival":
			profile.zones = _navigation_zones()
			profile.zones.append(_zone("strip_left", ["#20DFFF"], "sequence"))
			profile.zones.append(_zone("strip_right", ["#20DFFF"], "sequence"))
			profile.zones.append(_zone("strip_top_left", ["#FFBF4A"], "steady"))
			profile.zones.append(_zone("strip_top_right", ["#FFBF4A"], "steady"))
			profile.zones.append(_zone("strip_belly", ["#20DFFF"], "steady"))
			profile.effects = [
				_effect("vfx_tip_left", "spark", true, 0.5, 96, false),
				_effect("vfx_tip_right", "spark", true, 0.5, 96, false),
			]
			profile.sequence = _festival_sequence()
	return profile


static func _navigation_zones() -> Array[Dictionary]:
	return [
		_zone("nav_left", ["#FF241C"]),
		_zone("nav_right", ["#22E85B"]),
		_zone("nav_tail", ["#FFFFFF"]),
	]


static func _zone(
	zone_id: String,
	palette: Array,
	pattern_id: String = "steady",
	period_ticks: int = 240,
	phase_turns: float = 0.0,
	floor_value: float = 1.0,
	duty: float = 0.5,
	reverse: bool = false,
	segments: int = 1,
	reactive_source: String = "none",
	reactive_gain: float = 0.0,
	zone_brightness: float = 1.0
) -> Dictionary:
	return {
		"id": zone_id,
		"enabled": true,
		"brightness": zone_brightness,
		"pattern": _pattern(pattern_id, palette, period_ticks, phase_turns, floor_value, duty, reverse, segments),
		"reactive": {"source": reactive_source, "gain": reactive_gain},
	}


static func _pattern(
	pattern_id: String,
	palette: Array,
	period_ticks: int = 240,
	phase_turns: float = 0.0,
	floor_value: float = 1.0,
	duty: float = 0.5,
	reverse: bool = false,
	segments: int = 1
) -> Dictionary:
	return {
		"id": pattern_id,
		"palette": palette,
		"period_ticks": period_ticks,
		"phase_turns": phase_turns,
		"floor": floor_value,
		"duty": duty,
		"reverse": reverse,
		"segments": segments,
	}


static func _effect(anchor_id: String, kind: String, enabled: bool, intensity: float, lifetime_ticks: int, required: bool = true) -> Dictionary:
	return {
		"anchor_id": anchor_id,
		"kind": kind,
		"enabled": enabled,
		"intensity": intensity,
		"lifetime_ticks": lifetime_ticks,
		"required": required,
	}


static func _festival_sequence() -> Array[Dictionary]:
	var ids: Array[String] = ["strip_left", "strip_right"]
	return [
		_cue("breathe_in", 960, _pattern("breath", ["#1A2B88", "#20DFFF"], 960, 0.0, 0.08), ids, []),
		_cue("root_to_tip_chase", 960, _pattern("chase", ["#20DFFF", "#FF38A8"], 960, 0.0, 0.16, 0.5, false, 16), ids, []),
		_cue("outward_wave", 960, _pattern("wave", ["#20DFFF", "#FF38A8", "#794CFF"], 960, 0.0, 0.12, 0.5, false, 16), ids, ["vfx_tip_left", "vfx_tip_right"]),
		_cue("quiet_fade", 960, _pattern("breath", ["#1A2B88", "#20DFFF"], 960, 0.0, 0.03), ids, []),
	]


static func _cue(cue_id: String, duration_ticks: int, pattern: Dictionary, zone_ids: Array[String], effect_anchor_ids: Array[String]) -> Dictionary:
	return {
		"id": cue_id,
		"duration_ticks": duration_ticks,
		"pattern": pattern,
		"zone_ids": zone_ids,
		"effect_anchor_ids": effect_anchor_ids,
	}


static func _is_base_preset(id: String) -> bool:
	return ["classic_rc", "night_radian", "neon_rgb", "night_aerobatics", "festival"].has(id)


static func _normalize_zones(raw: Variant, errors: Array[String]) -> Array[Dictionary]:
	var zones: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		_error(errors, "profile.zones must be an array")
		return zones
	if raw.size() > MAX_ZONES:
		_error(errors, "profile.zones exceeds %d entries" % MAX_ZONES)
		return zones
	var seen: Dictionary = {}
	for index: int in raw.size():
		var zone: Dictionary = _normalize_zone(raw[index], "profile.zones[%d]" % index, errors)
		if zone.is_empty():
			continue
		if seen.has(zone.id):
			_error(errors, "profile.zones contains duplicate id %s" % zone.id)
			continue
		seen[zone.id] = true
		zones.append(zone)
	zones.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))
	return zones


static func _normalize_zone(raw: Variant, path: String, errors: Array[String]) -> Dictionary:
	if not _exact_keys(raw, ["id", "enabled", "brightness", "pattern", "reactive"], [], path, errors):
		return {}
	var id := _string(raw.id, path + ".id", 64, errors)
	if not ZONE_IDS.has(id):
		_error(errors, path + ".id is not a supported semantic zone")
	var enabled := _boolean(raw.enabled, path + ".enabled", errors)
	var brightness := _number(raw.brightness, path + ".brightness", 0.0, 2.0, errors)
	var pattern := _normalize_pattern(raw.pattern, path + ".pattern", true, errors)
	var reactive := _normalize_reactive(raw.reactive, path + ".reactive", errors)
	if not _valid_zone_id(id):
		return {}
	return {"id": id, "enabled": enabled, "brightness": brightness, "pattern": pattern, "reactive": reactive}


static func _normalize_pattern(raw: Variant, path: String, allow_sequence: bool, errors: Array[String]) -> Dictionary:
	if not _exact_keys(raw, ["id", "palette", "period_ticks", "phase_turns", "floor", "duty", "reverse", "segments"], [], path, errors):
		return {}
	var pattern_id := _string(raw.id, path + ".id", 16, errors)
	if not PATTERN_IDS.has(pattern_id) or (pattern_id == "sequence" and not allow_sequence):
		_error(errors, path + ".id is not a supported pattern")
	var palette := _normalize_palette(raw.palette, path + ".palette", errors)
	var period_ticks := _integer(raw.period_ticks, path + ".period_ticks", 60, 14400, errors)
	var phase_turns := _number(raw.phase_turns, path + ".phase_turns", 0.0, 1.0, errors)
	var floor_value := _number(raw.floor, path + ".floor", 0.0, 1.0, errors)
	var duty := _number(raw.duty, path + ".duty", 0.05, 0.95, errors)
	var reverse := _boolean(raw.reverse, path + ".reverse", errors)
	var segments := _integer(raw.segments, path + ".segments", 1, 256, errors)
	if not PATTERN_IDS.has(pattern_id):
		return {}
	# Every serialized field is checked, then fields unused by a pattern are fixed
	# to canonical values so they cannot hide state or alter presentation identity.
	match pattern_id:
		"steady":
			period_ticks = 240
			phase_turns = 0.0
			floor_value = 1.0
			duty = 0.5
			reverse = false
			segments = 1
		"breath":
			duty = 0.5
			reverse = false
			segments = 1
		"pulse":
			floor_value = 0.0
			reverse = false
			segments = 1
		"wave", "rainbow":
			floor_value = 1.0
			duty = 0.5
			segments = 1
		"sequence":
			palette = ["#FFFFFF"]
			period_ticks = 240
			phase_turns = 0.0
			floor_value = 1.0
			duty = 0.5
			reverse = false
			segments = 1
	return {
		"id": pattern_id,
		"palette": palette,
		"period_ticks": period_ticks,
		"phase_turns": phase_turns,
		"floor": floor_value,
		"duty": duty,
		"reverse": reverse,
		"segments": segments,
	}


static func _normalize_palette(raw: Variant, path: String, errors: Array[String]) -> Array[String]:
	var palette: Array[String] = []
	if typeof(raw) != TYPE_ARRAY:
		_error(errors, "%s must be an array" % path)
		return palette
	if raw.is_empty() or raw.size() > 8:
		_error(errors, "%s must contain 1 to 8 colors" % path)
		return palette
	for index: int in raw.size():
		var color := _string(raw[index], "%s[%d]" % [path, index], 7, errors)
		if not _valid_color(color):
			_error(errors, "%s[%d] must be #RRGGBB" % [path, index])
		else:
			palette.append(color.to_upper())
	return palette


static func _normalize_reactive(raw: Variant, path: String, errors: Array[String]) -> Dictionary:
	if not _exact_keys(raw, ["source", "gain"], [], path, errors):
		return {}
	var source := _string(raw.source, path + ".source", 16, errors)
	if not REACTIVE_SOURCES.has(source):
		_error(errors, path + ".source is unsupported")
	var gain := _number(raw.gain, path + ".gain", 0.0, 1.0, errors)
	if source == "none":
		gain = 0.0
	return {"source": source, "gain": gain}


static func _normalize_effects(raw: Variant, errors: Array[String]) -> Array[Dictionary]:
	var effects: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		_error(errors, "profile.effects must be an array")
		return effects
	if raw.size() > MAX_EFFECTS:
		_error(errors, "profile.effects exceeds %d entries" % MAX_EFFECTS)
		return effects
	var seen: Dictionary = {}
	var enabled_count := 0
	for index: int in raw.size():
		var effect: Dictionary = _normalize_effect(raw[index], "profile.effects[%d]" % index, errors)
		if effect.is_empty():
			continue
		if seen.has(effect.anchor_id):
			_error(errors, "profile.effects contains duplicate anchor_id %s" % effect.anchor_id)
			continue
		seen[effect.anchor_id] = true
		if effect.enabled:
			enabled_count += 1
		effects.append(effect)
	if enabled_count > MAX_ENABLED_EFFECTS:
		_error(errors, "profile.effects may enable at most %d effects" % MAX_ENABLED_EFFECTS)
	effects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.anchor_id) < String(b.anchor_id))
	return effects


static func _normalize_effect(raw: Variant, path: String, errors: Array[String]) -> Dictionary:
	if not _exact_keys(raw, ["anchor_id", "kind", "enabled", "intensity", "lifetime_ticks"], ["required"], path, errors):
		return {}
	var anchor_id := _string(raw.anchor_id, path + ".anchor_id", 64, errors)
	if not EFFECT_ANCHOR_IDS.has(anchor_id):
		_error(errors, path + ".anchor_id is not a supported semantic effect anchor")
	var kind := _string(raw.kind, path + ".kind", 16, errors)
	if not EFFECT_KINDS.has(kind):
		_error(errors, path + ".kind is unsupported")
	var enabled := _boolean(raw.enabled, path + ".enabled", errors)
	var intensity := _number(raw.intensity, path + ".intensity", 0.0, 1.0, errors)
	var lifetime_ticks := _integer(raw.lifetime_ticks, path + ".lifetime_ticks", 12, 480, errors)
	var required := true
	if raw.has("required"):
		required = _boolean(raw.required, path + ".required", errors)
	if not _valid_id(anchor_id):
		return {}
	return {"anchor_id": anchor_id, "kind": kind, "enabled": enabled, "intensity": intensity, "lifetime_ticks": lifetime_ticks, "required": required}


static func _normalize_sequence(raw: Variant, errors: Array[String]) -> Array[Dictionary]:
	var sequence: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		_error(errors, "profile.sequence must be an array")
		return sequence
	if raw.size() > MAX_CUES:
		_error(errors, "profile.sequence exceeds %d cues" % MAX_CUES)
		return sequence
	var seen: Dictionary = {}
	var total_ticks := 0
	for index: int in raw.size():
		var cue: Dictionary = _normalize_cue(raw[index], "profile.sequence[%d]" % index, errors)
		if cue.is_empty():
			continue
		if seen.has(cue.id):
			_error(errors, "profile.sequence contains duplicate cue id %s" % cue.id)
			continue
		seen[cue.id] = true
		total_ticks += cue.duration_ticks
		sequence.append(cue)
	if total_ticks > MAX_SEQUENCE_TICKS:
		_error(errors, "profile.sequence total duration exceeds %d ticks" % MAX_SEQUENCE_TICKS)
	return sequence


static func _normalize_cue(raw: Variant, path: String, errors: Array[String]) -> Dictionary:
	if not _exact_keys(raw, ["id", "duration_ticks", "pattern", "zone_ids", "effect_anchor_ids"], [], path, errors):
		return {}
	var id := _string(raw.id, path + ".id", 64, errors)
	if not _valid_id(id):
		_error(errors, path + ".id must be lowercase snake_case")
	var duration_ticks := _integer(raw.duration_ticks, path + ".duration_ticks", 1, MAX_SEQUENCE_TICKS, errors)
	var pattern := _normalize_pattern(raw.pattern, path + ".pattern", false, errors)
	var zone_ids := _normalize_reference_ids(raw.zone_ids, path + ".zone_ids", ZONE_IDS, 32, errors)
	var effect_anchor_ids := _normalize_reference_ids(raw.effect_anchor_ids, path + ".effect_anchor_ids", EFFECT_ANCHOR_IDS, MAX_EFFECTS, errors)
	if not _valid_id(id):
		return {}
	return {
		"id": id,
		"duration_ticks": duration_ticks,
		"pattern": pattern,
		"zone_ids": zone_ids,
		"effect_anchor_ids": effect_anchor_ids,
	}


static func _normalize_reference_ids(raw: Variant, path: String, allowed_ids: Array[String], limit: int, errors: Array[String]) -> Array[String]:
	var ids: Array[String] = []
	if typeof(raw) != TYPE_ARRAY:
		_error(errors, "%s must be an array" % path)
		return ids
	if raw.size() > limit:
		_error(errors, "%s exceeds %d entries" % [path, limit])
		return ids
	var seen: Dictionary = {}
	for index: int in raw.size():
		var id := _string(raw[index], "%s[%d]" % [path, index], 64, errors)
		if not allowed_ids.has(id):
			_error(errors, "%s[%d] is not a supported reference" % [path, index])
		if seen.has(id):
			_error(errors, "%s contains duplicate id %s" % [path, id])
		elif allowed_ids.has(id):
			seen[id] = true
			ids.append(id)
	ids.sort()
	return ids


static func _exact_keys(raw: Variant, required: Array, optional: Array, path: String, errors: Array[String]) -> bool:
	if typeof(raw) != TYPE_DICTIONARY:
		_error(errors, "%s must be an object" % path)
		return false
	if raw.size() > required.size() + optional.size():
		_error(errors, "%s has unknown fields" % path)
		return false
	var valid := true
	for key: Variant in raw.keys():
		if typeof(key) != TYPE_STRING or (not required.has(key) and not optional.has(key)):
			_error(errors, "%s has an unknown field" % path)
			valid = false
	for key: String in required:
		if not raw.has(key):
			_error(errors, "%s is missing %s" % [path, key])
			valid = false
	return valid


static func _preflight_json_bounds(root_value: Variant, errors: Array[String]) -> bool:
	var stack: Array[Dictionary] = [{"value": root_value, "depth": 0}]
	var node_count := 0
	var byte_count := 0
	while not stack.is_empty():
		var item: Dictionary = stack.pop_back()
		var value: Variant = item.value
		var depth: int = item.depth
		if depth > 12:
			_error(errors, "profile JSON nesting exceeds 12 levels")
			return false
		node_count += 1
		if node_count > MAX_PROFILE_NODES:
			_error(errors, "profile exceeds %d JSON nodes" % MAX_PROFILE_NODES)
			return false
		match typeof(value):
			TYPE_DICTIONARY:
				if value.size() > MAX_PROFILE_NODES:
					_error(errors, "profile object exceeds the JSON node bound")
					return false
				var keys: Array = value.keys()
				byte_count += 2 + maxi(0, keys.size() - 1) + keys.size()
				for key: Variant in keys:
					node_count += 1
					if node_count > MAX_PROFILE_NODES:
						_error(errors, "profile exceeds %d JSON nodes" % MAX_PROFILE_NODES)
						return false
					if typeof(key) != TYPE_STRING or String(key).length() > MAX_STRING_CHARS:
						_error(errors, "profile contains a non-string or oversized object key")
						return false
					byte_count += _json_scalar_size(key)
					stack.append({"value": value[key], "depth": depth + 1})
			TYPE_ARRAY:
				if value.size() > MAX_PROFILE_NODES:
					_error(errors, "profile array exceeds the JSON node bound")
					return false
				byte_count += 2 + maxi(0, value.size() - 1)
				for child: Variant in value:
					stack.append({"value": child, "depth": depth + 1})
			TYPE_STRING:
				if value.length() > MAX_STRING_CHARS:
					_error(errors, "profile contains an oversized string")
					return false
				byte_count += _json_scalar_size(value)
			TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_NIL:
				byte_count += _json_scalar_size(value)
			_:
				_error(errors, "profile contains a value that is not JSON data")
				return false
		if byte_count > MAX_PROFILE_BYTES:
			_error(errors, "profile exceeds the %d-byte lighting budget" % MAX_PROFILE_BYTES)
			return false
	return true


static func _json_scalar_size(value: Variant) -> int:
	if typeof(value) == TYPE_FLOAT and not is_finite(float(value)):
		return 16
	if typeof(value) == TYPE_INT:
		return str(value).to_utf8_buffer().size()
	if typeof(value) == TYPE_BOOL:
		return 4 if not value else 5
	if typeof(value) == TYPE_NIL:
		return 4
	return JSON.stringify(value).to_utf8_buffer().size()


static func _string(value: Variant, path: String, max_length: int, errors: Array[String], allow_empty: bool = false) -> String:
	if typeof(value) != TYPE_STRING:
		_error(errors, "%s must be a string" % path)
		return ""
	var text_value: String = value
	if text_value.length() > max_length or (text_value.is_empty() and not allow_empty):
		_error(errors, "%s has an invalid length" % path)
		return ""
	return text_value


static func _integer(value: Variant, path: String, minimum: int, maximum: int, errors: Array[String]) -> int:
	if typeof(value) != TYPE_INT:
		_error(errors, "%s must be an integer" % path)
		return minimum
	var int_value: int = value
	if int_value < minimum or int_value > maximum:
		_error(errors, "%s is out of range" % path)
	return int_value


static func _number(value: Variant, path: String, minimum: float, maximum: float, errors: Array[String]) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		_error(errors, "%s must be a finite number" % path)
		return minimum
	var number_value := float(value)
	if not is_finite(number_value):
		_error(errors, "%s must be finite" % path)
	elif number_value < minimum or number_value > maximum:
		_error(errors, "%s is out of range" % path)
	return number_value


static func _boolean(value: Variant, path: String, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_BOOL:
		_error(errors, "%s must be a boolean" % path)
		return false
	return value


static func _valid_color(value: String) -> bool:
	if value.length() != 7 or not value.begins_with("#"):
		return false
	for index: int in range(1, 7):
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 70) or (code >= 97 and code <= 102)):
			return false
	return true


static func _valid_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index: int in value.length():
		var code := value.unicode_at(index)
		var lowercase_letter := code >= 97 and code <= 122
		var digit := code >= 48 and code <= 57
		if index == 0 and not lowercase_letter:
			return false
		if not lowercase_letter and not digit and code != 95:
			return false
	return true


static func _valid_zone_id(value: String) -> bool:
	return ZONE_IDS.has(value)


static func _error(errors: Array[String], message: String) -> void:
	if errors.size() < 64:
		errors.append(message)
