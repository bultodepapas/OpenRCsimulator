extends RefCounted
## FW-RGB-09: pure Workshop cue edits. Rendering and flight state are not dependencies.

const Profile := preload("res://render/lighting/lighting_profile.gd")
const STATE_KEYS := ["open", "selected_id", "duration_text", "period_text", "pattern_id", "color_text", "zone_ids", "effect_anchor_ids"]
const TICKS_PER_SECOND := 240.0


static func editor_state(profile: Dictionary, cue_id: String, open := true) -> Dictionary:
	var cues: Array = profile.get("sequence", [])
	var index := _index(cues, cue_id)
	if index < 0 and not cues.is_empty(): index = 0
	var cue: Dictionary = cues[index] if index >= 0 else {}
	var pattern: Dictionary = cue.get("pattern", {})
	return {"open": open, "selected_id": str(cue.get("id", "")),
		"duration_text": String.num(float(cue.get("duration_ticks", 960)) / TICKS_PER_SECOND, 4),
		"period_text": String.num(float(pattern.get("period_ticks", 960)) / TICKS_PER_SECOND, 4),
		"pattern_id": str(pattern.get("id", "steady")),
		"color_text": pattern.get("palette", ["#20DFFF"]).duplicate(),
		"zone_ids": cue.get("zone_ids", []).duplicate(),
		"effect_anchor_ids": cue.get("effect_anchor_ids", []).duplicate()}


static func validate_editor_state(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.size() != STATE_KEYS.size(): return _failure("Sequence editor fields are missing or unsupported.")
	for key: String in STATE_KEYS:
		if not raw.has(key): return _failure("Sequence editor fields are missing or unsupported.")
	if typeof(raw.open) != TYPE_BOOL or not _text(raw.selected_id, 64) \
		or not _text(raw.duration_text, 24) or not _text(raw.period_text, 24):
		return _failure("Sequence editor selection or timing text is malformed.")
	if not raw.pattern_id is String or raw.pattern_id not in Profile.PATTERN_IDS or raw.pattern_id == "sequence":
		return _failure("Choose a non-sequence cue pattern.")
	if not raw.color_text is Array or raw.color_text.size() > 8:
		return _failure("A cue palette supports at most eight colors.")
	for value: Variant in raw.color_text:
		if not _text(value, 16): return _failure("Cue color text is malformed.")
	if not _references(raw.zone_ids, Profile.ZONE_IDS) or not _references(raw.effect_anchor_ids, Profile.EFFECT_ANCHOR_IDS):
		return _failure("Sequence editor targets are unsupported or duplicated.")
	return {"ok": true, "value": raw.duplicate(true), "errors": []}


static func add_cue(profile: Dictionary, after_id := "") -> Dictionary:
	if not _editable(profile): return _failure("Choose a lighting preset before adding cues.")
	var next := profile.duplicate(true)
	var cues: Array = next.sequence
	if cues.size() >= Profile.MAX_CUES: return _failure("A sequence supports at most 32 cues.")
	var remaining := Profile.MAX_SEQUENCE_TICKS - _total_ticks(cues)
	if remaining < 1: return _failure("A sequence cannot exceed 60 seconds.")
	var target := ""
	for zone: Dictionary in next.zones:
		if bool(zone.enabled) and (not bool(next.orientation_lock) or not str(zone.id).begins_with("nav_")):
			if target.is_empty() or str(zone.id).begins_with("strip_"):
				target = str(zone.id)
				if target.begins_with("strip_"): break
	if target.is_empty(): return _failure("Enable an unlocked lighting zone before adding cues.")
	var cue_id := _new_id(cues)
	var pattern := {"id": "breath", "palette": ["#20DFFF"], "period_ticks": 960,
		"phase_turns": 0.0, "floor": 0.12, "duty": 0.5, "reverse": false, "segments": 1}
	var position := _index(cues, after_id)
	cues.insert(position + 1 if position >= 0 else cues.size(), {"id": cue_id,
		"duration_ticks": mini(960, remaining), "pattern": pattern,
		"zone_ids": [target], "effect_anchor_ids": []})
	return _finish(next, cue_id)


static func duplicate_cue(profile: Dictionary, cue_id: String) -> Dictionary:
	if not _editable(profile): return _failure("Choose a lighting preset before editing cues.")
	var next := profile.duplicate(true)
	var index := _index(next.sequence, cue_id)
	if index < 0: return _failure("The selected cue is no longer available.")
	var copied: Dictionary = next.sequence[index].duplicate(true)
	copied.id = _new_id(next.sequence)
	next.sequence.insert(index + 1, copied)
	return _finish(next, copied.id)


static func remove_cue(profile: Dictionary, cue_id: String) -> Dictionary:
	if not _editable(profile): return _failure("Choose a lighting preset before editing cues.")
	var next := profile.duplicate(true)
	var index := _index(next.sequence, cue_id)
	if index < 0: return _failure("The selected cue is no longer available.")
	next.sequence.remove_at(index)
	var selected := str(next.sequence[mini(index, next.sequence.size() - 1)].id) if not next.sequence.is_empty() else ""
	return _finish(next, selected)


static func move_cue(profile: Dictionary, cue_id: String, direction: int) -> Dictionary:
	if not _editable(profile) or direction not in [-1, 1]: return _failure("Choose an adjacent cue position.")
	var next := profile.duplicate(true)
	var index := _index(next.sequence, cue_id)
	var target := index + direction
	if index < 0 or target < 0 or target >= next.sequence.size(): return _failure("The cue is already at that end of the sequence.")
	var moving: Dictionary = next.sequence[index]
	next.sequence.remove_at(index)
	next.sequence.insert(target, moving)
	return _finish(next, cue_id)


static func apply_cue(profile: Dictionary, raw_state: Dictionary) -> Dictionary:
	if not _editable(profile): return _failure("Choose a lighting preset before editing cues.")
	var state_check := validate_editor_state(raw_state)
	if not state_check.ok: return state_check
	var state: Dictionary = state_check.value
	var next := profile.duplicate(true)
	var index := _index(next.sequence, state.selected_id)
	if index < 0: return _failure("The selected cue is no longer available.")
	var duration := _ticks(state.duration_text, 1)
	var period := _ticks(state.period_text, 60)
	if duration < 0 or period < 0: return _failure("Enter a cue duration above zero and a cycle from 0.25 to 60 seconds.")
	for zone_id: String in state.zone_ids:
		var zone := _zone(next, zone_id)
		if zone.is_empty() or not bool(zone.enabled): return _failure("Cue targets must be enabled zones in this build.")
		if bool(next.orientation_lock) and zone_id.begins_with("nav_"):
			return _failure("Unlock navigation colors and patterns before targeting them with a cue.")
	for anchor_id: String in state.effect_anchor_ids:
		var enabled := false
		for effect: Dictionary in next.effects:
			if effect.anchor_id == anchor_id and bool(effect.enabled): enabled = true
		if not enabled: return _failure("Enable an effect before adding it to a cue.")
	var cue: Dictionary = next.sequence[index]
	var pattern: Dictionary = cue.pattern.duplicate(true)
	if str(pattern.id) != str(state.pattern_id):
		pattern.floor = 0.12 if state.pattern_id in ["breath", "chase"] else 0.0 if state.pattern_id == "pulse" else 1.0
		pattern.duty = 0.5
		pattern.phase_turns = 0.0
		pattern.reverse = false
		pattern.segments = 16 if state.pattern_id in ["segments", "chase"] else 1
	pattern.id = state.pattern_id
	pattern.period_ticks = period
	pattern.palette = state.color_text.duplicate()
	cue.pattern = pattern
	cue.duration_ticks = duration
	cue.zone_ids = state.zone_ids.duplicate()
	cue.effect_anchor_ids = state.effect_anchor_ids.duplicate()
	return _finish(next, state.selected_id)


static func _finish(profile: Dictionary, selected_id: String) -> Dictionary:
	var targets := {}
	for cue: Dictionary in profile.sequence:
		for zone_id: String in cue.zone_ids: targets[zone_id] = true
	for zone: Dictionary in profile.zones:
		if targets.has(str(zone.id)):
			zone.pattern.id = "sequence"
		elif zone.pattern.id == "sequence":
			zone.pattern.id = "steady" # No orphan sequence references after deleting the last target.
	profile.selection = "custom"
	var checked := Profile.validate(profile)
	if not checked.ok: return checked
	return {"ok": true, "profile": checked.profile, "selected_id": selected_id, "errors": []}


static func _ticks(text_value: String, minimum: int) -> int:
	if not text_value.is_valid_float(): return -1
	var seconds := text_value.to_float()
	if not is_finite(seconds) or seconds < float(minimum) / TICKS_PER_SECOND or seconds > 60.0: return -1
	var ticks := roundi(seconds * TICKS_PER_SECOND)
	return ticks if ticks >= minimum and ticks <= Profile.MAX_SEQUENCE_TICKS else -1


static func _editable(profile: Dictionary) -> bool:
	return profile.get("selection", "inherit") in ["preset", "custom"] and bool(Profile.validate(profile).ok)


static func _index(cues: Array, id: String) -> int:
	for index in cues.size():
		if str(cues[index].get("id", "")) == id: return index
	return -1


static func _zone(profile: Dictionary, id: String) -> Dictionary:
	for zone: Dictionary in profile.get("zones", []):
		if str(zone.id) == id: return zone
	return {}


static func _total_ticks(cues: Array) -> int:
	var result := 0
	for cue: Dictionary in cues: result += int(cue.duration_ticks)
	return result


static func _new_id(cues: Array) -> String:
	for number in range(1, Profile.MAX_CUES + 2):
		var candidate := "cue_%d" % number
		if _index(cues, candidate) < 0: return candidate
	return "cue_new"


static func _text(value: Variant, limit: int) -> bool:
	if not value is String or value.length() > limit: return false
	for index in value.length():
		if value.unicode_at(index) < 32: return false
	return true


static func _references(value: Variant, allowed: Array[String]) -> bool:
	if not value is Array or value.size() > allowed.size(): return false
	var seen := {}
	for id: Variant in value:
		if not id is String or id not in allowed or seen.has(id): return false
		seen[id] = true
	return true


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message]}

