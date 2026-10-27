extends SceneTree

const Profile = preload("res://render/lighting/lighting_profile.gd")

var _count := 0
var _failures := 0


func _check(label: String, ok: bool) -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)


func _reject(label: String, raw: Variant) -> void:
	var result: Dictionary = Profile.validate(raw)
	_check(label, not result.ok and result.profile.is_empty() and not result.errors.is_empty())


func _test_preset_revisions() -> void:
	# Exact materialized profile exported by the revision-1 factory before the art change.
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighting/night_radian_r1.json"))
	var before := legacy.duplicate(true)
	var checked: Dictionary = Profile.validate(legacy)
	_check("revision 1 materialized preset validates without rewriting", checked.ok and _json_values_equal(checked.profile, before) and legacy == before)
	_check("historical factory reproduces the original revision 1 template", _json_values_equal(Profile.preset("night_radian", 1), before))
	var roundtrip: Dictionary = Profile.validate(JSON.parse_string(JSON.stringify(checked.profile)))
	_check("revision 1 JSON roundtrip keeps its original values and pin", roundtrip.ok and _json_values_equal(roundtrip.profile, before))
	var custom := legacy.duplicate(true)
	custom.selection = "custom"
	custom.brightness = 0.77
	custom.zones[0].pattern.palette = ["#123456"]
	checked = Profile.validate(custom)
	_check("edited revision 1 custom remains materialized and pinned", checked.ok and _json_values_equal(checked.profile, custom))
	for id: String in Profile.PRESET_IDS:
		_check("new preset selects catalog revision 2: " + id, Profile.preset(id).preset_revision == 2)
		_check("revision 1 remains available: " + id, Profile.preset(id, 1).preset_revision == 1)
		for unsupported: int in [0, 3]:
			_check("factory refuses unsupported revision %d: %s" % [unsupported, id], Profile.preset(id, unsupported).is_empty())
	for selection: String in ["preset", "custom"]:
		for unsupported: int in [0, 3]:
			var invalid := legacy.duplicate(true)
			invalid.selection = selection
			invalid.preset_revision = unsupported
			_reject("stored %s refuses revision %d" % [selection, unsupported], invalid)
	var current: Dictionary = Profile.preset("night_radian")
	_check("Night Radian v2 raises broad wing illumination", _zone(current, "strip_left").brightness == 1.0
		and _zone(current, "strip_right").brightness == 1.0 and _zone(before, "strip_left").brightness == 0.2)
	_check("Night Radian v2 retains steady upper orientation accents", _zone(current, "strip_top_left").brightness == 1.5
		and _json_values_equal(_zone(current, "strip_top_left").pattern, _zone(before, "strip_top_left").pattern))
	_check("Night Radian v2 explicitly balances the landing beam", _zone(current, "landing_lamp").brightness == 0.125
		and _zone(before, "landing_lamp").is_empty())


func _json_values_equal(a: Variant, b: Variant) -> bool:
	# JSON numbers are parsed as floats and arrays are untyped. Compare exact values,
	# not GDScript typed-container identity; do not normalize away fields or use tolerances.
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not _json_values_equal(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index: int in a.size():
			if not _json_values_equal(a[index], b[index]): return false
		return true
	return a == b


func _initialize() -> void:
	_test_preset_revisions()
	var inherited: Dictionary = Profile.defaults()
	var defaults_result: Dictionary = Profile.validate(inherited)
	_check("default payload validates as inherit", defaults_result.ok and defaults_result.profile == inherited)
	_check("default payload is empty inherited equipment", inherited.selection == "inherit" and inherited.zones.is_empty() and inherited.effects.is_empty() and inherited.sequence.is_empty())
	_check("exact top-level lighting keys", inherited.keys().size() == 11)

	for preset_id: String in Profile.PRESET_IDS:
		var resolved: Dictionary = Profile.preset(preset_id)
		var checked: Dictionary = Profile.validate(resolved)
		_check("preset is full and valid: " + preset_id, not resolved.is_empty() and checked.ok and checked.profile == resolved)
		_check("preset has a label: " + preset_id, not Profile.label(preset_id).is_empty())
		var roundtrip := Profile.validate(JSON.parse_string(JSON.stringify(resolved)))
		_check("preset survives Godot JSON numeric roundtrip: " + preset_id, roundtrip.ok and roundtrip.profile == resolved)
	_check("unknown preset returns empty", Profile.preset("unregistered").is_empty())
	_check("unknown label returns empty", Profile.label("unregistered").is_empty())
	_check("custom is materialized over a pinned base", Profile.preset("custom").selection == "custom" and Profile.preset("custom").preset_id == "neon_rgb")
	_check("custom offers all semantic zones and disabled effects", Profile.preset("custom").zones.size() == Profile.ZONE_IDS.size()
		and Profile.preset("custom").effects.size() == 2 and not Profile.preset("custom").effects[0].enabled and not Profile.preset("custom").effects[1].enabled)
	_check("festival contains sequence and paired optional sparks", Profile.preset("festival").sequence.size() == 4 and Profile.preset("festival").effects.size() == 2)
	_check("preset zone IDs are canonical semantic IDs", _all_zones_supported(Profile.preset("night_radian")))

	for bad: Variant in [null, false, 1, "lighting", [], {}]:
		_reject("reject non-profile shape %s" % [bad], bad)

	var malformed: Dictionary = inherited.duplicate(true)
	malformed.brightness = true
	_reject("boolean rejected as brightness", malformed)
	malformed = inherited.duplicate(true)
	malformed.brightness = NAN
	_reject("nonfinite brightness rejected", malformed)
	malformed = inherited.duplicate(true)
	malformed.version = true
	_reject("boolean rejected as version", malformed)
	malformed.version = 1.5
	_reject("fraction rejected as version", malformed)
	malformed.version = 1.0e100
	_reject("huge integer rejected before narrowing", malformed)
	malformed = inherited.duplicate(true)
	malformed.visual_seed = 2147483648
	_reject("seed upper bound enforced", malformed)
	malformed = inherited.duplicate(true)
	malformed.erase("effects")
	_reject("missing top-level field rejected", malformed)
	malformed = inherited.duplicate(true)
	malformed.unexpected = "field"
	_reject("unknown top-level field rejected", malformed)
	malformed = inherited.duplicate(true)
	malformed.selection = "disabled"
	malformed.preset_id = "classic_rc"
	_reject("disabled cannot pin an accidental preset", malformed)

	var neon: Dictionary = Profile.preset("neon_rgb")
	var phase_input: Dictionary = neon.duplicate(true)
	for zone: Dictionary in phase_input.zones:
		if zone.id == "strip_left":
			zone.pattern.phase_turns = 0.25
	var phase_result: Dictionary = Profile.validate(phase_input)
	_check("phase config accepts and preserves a valid phase", phase_result.ok and _zone(phase_result.profile, "strip_left").pattern.phase_turns == 0.25)
	_check("phase config changes canonical profile", phase_result.ok and phase_result.profile != neon)
	phase_input = neon.duplicate(true)
	for zone: Dictionary in phase_input.zones:
		if zone.id == "strip_left":
			zone.pattern.phase_turns = 1.01
	_reject("phase bound enforced", phase_input)

	var canonical_a: Dictionary = Profile.preset("festival")
	var canonical_b: Dictionary = canonical_a.duplicate(true)
	canonical_b.zones.reverse()
	canonical_b.effects.reverse()
	for cue: Dictionary in canonical_b.sequence:
		cue.zone_ids.reverse()
		cue.effect_anchor_ids.reverse()
	var canonical_result_a: Dictionary = Profile.validate(canonical_a)
	var canonical_result_b: Dictionary = Profile.validate(canonical_b)
	_check("input array order does not alter canonical profile", canonical_result_a.ok and canonical_result_b.ok and canonical_result_a.profile == canonical_result_b.profile)

	var steady_canonical: Dictionary = Profile.preset("classic_rc")
	var steady_variant: Dictionary = steady_canonical.duplicate(true)
	for zone: Dictionary in steady_variant.zones:
		if zone.id == "nav_left":
			zone.pattern.period_ticks = 14400
			zone.pattern.phase_turns = 0.75
			zone.pattern.floor = 0.2
			zone.pattern.duty = 0.95
			zone.pattern.reverse = true
			zone.pattern.segments = 256
	var steady_result: Dictionary = Profile.validate(steady_variant)
	_check("irrelevant steady pattern fields canonicalize", steady_result.ok and steady_result.profile == steady_canonical)

	var invalid_zone: Dictionary = neon.duplicate(true)
	_zone(invalid_zone, "strip_left").pattern.period_ticks = true
	_reject("boolean rejected as tick period", invalid_zone)
	invalid_zone = neon.duplicate(true)
	_zone(invalid_zone, "strip_left").pattern.period_ticks = 59
	_reject("pattern minimum tick period enforced", invalid_zone)
	invalid_zone = neon.duplicate(true)
	_zone(invalid_zone, "strip_left").pattern.palette = ["#12345"]
	_reject("palette must use #RRGGBB", invalid_zone)
	invalid_zone = neon.duplicate(true)
	_zone(invalid_zone, "strip_left").pattern.segments = 0
	_reject("segment count lower bound enforced", invalid_zone)
	invalid_zone = neon.duplicate(true)
	_zone(invalid_zone, "strip_left").reactive.source = "script"
	_reject("reactive source is closed", invalid_zone)
	invalid_zone = neon.duplicate(true)
	_zone(invalid_zone, "strip_left").brightness = 2.01
	_reject("zone brightness upper bound enforced", invalid_zone)
	invalid_zone = neon.duplicate(true)
	invalid_zone.zones[0].extra = 1
	_reject("unknown zone field rejected", invalid_zone)
	invalid_zone = neon.duplicate(true)
	invalid_zone.zones.append(invalid_zone.zones[0].duplicate(true))
	_reject("duplicate zone ID rejected", invalid_zone)
	invalid_zone = neon.duplicate(true)
	invalid_zone.zones[0].id = "invented_zone"
	_reject("unknown semantic zone ID rejected", invalid_zone)

	var bad_effect: Dictionary = Profile.preset("festival")
	bad_effect.effects.append(bad_effect.effects[0].duplicate(true))
	_reject("duplicate effect anchor rejected", bad_effect)
	bad_effect = Profile.preset("festival")
	bad_effect.effects[0].lifetime_ticks = 11
	_reject("effect lifetime lower bound enforced", bad_effect)
	bad_effect = Profile.preset("festival")
	bad_effect.effects[0].enabled = "true"
	_reject("effect enable requires bool", bad_effect)
	bad_effect = Profile.preset("festival")
	bad_effect.effects[0].intensity = INF
	_reject("effect intensity must be finite", bad_effect)
	bad_effect = Profile.preset("festival")
	bad_effect.sequence[0].duration_ticks = 0
	_reject("cue duration must be positive ticks", bad_effect)
	bad_effect = Profile.preset("festival")
	bad_effect.sequence[0].zone_ids = ["landing_lamp"]
	_reject("sequence cue must target a declared sequence zone", bad_effect)
	bad_effect = Profile.preset("festival")
	bad_effect.sequence[2].effect_anchor_ids = ["vfx_tip_left"]
	bad_effect.effects[0].enabled = false
	_reject("sequence cannot target a disabled effect", bad_effect)
	bad_effect = Profile.preset("festival")
	bad_effect.sequence[0].pattern.id = "sequence"
	_reject("sequence cues cannot nest sequence patterns", bad_effect)

	print("FW-RGB-02 profile: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _all_zones_supported(profile: Dictionary) -> bool:
	for zone: Dictionary in profile.zones:
		if not Profile.ZONE_IDS.has(zone.id):
			return false
	return true


func _zone(profile: Dictionary, zone_id: String) -> Dictionary:
	for zone: Dictionary in profile.zones:
		if zone.id == zone_id:
			return zone
	return {}
