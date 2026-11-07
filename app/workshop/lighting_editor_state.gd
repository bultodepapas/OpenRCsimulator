extends RefCounted
## Data-only Lighting edit buffers. Component bounds are shared with the profile;
## validated raw values remain authoritative until the player explicitly applies.

const Profile := preload("res://render/lighting/lighting_profile.gd")
const Sequence := preload("res://workshop/lighting_sequence.gd")
const REQUIRED := ["zone", "zones_open", "effects_open", "color_text"]
const OPTIONAL := ["sequence", "draft", "numbers"]
const DRAFT_KEYS := ["zone", "effects", "brightness", "color_pending"]


static func validate(raw: Variant) -> Dictionary:
	if not _keys(raw, REQUIRED, OPTIONAL):
		return _failure("Lighting editor recovery has missing or unsupported fields.")
	if not _text(raw.zone, 80) or (not raw.zone.is_empty() and raw.zone not in Profile.ZONE_IDS) \
			or typeof(raw.zones_open) != TYPE_BOOL or typeof(raw.effects_open) != TYPE_BOOL:
		return _failure("Lighting editor recovery selection is malformed.")
	if not raw.color_text is Array or raw.color_text.size() > 8:
		return _failure("Lighting editor recovery palette exceeds eight entries.")
	for color: Variant in raw.color_text:
		if not _text(color, 16):
			return _failure("Lighting editor recovery color text is malformed.")
	if raw.has("sequence") and not Sequence.validate_editor_state(raw.sequence).ok:
		return _failure("Lighting sequence recovery has malformed or unsupported fields.")
	if raw.has("numbers"):
		if not raw.numbers is Dictionary or raw.numbers.size() > 2 + 2 * Profile.MAX_EFFECTS:
			return _failure("Lighting numeric recovery is malformed.")
		var zone_numbers := false
		var effect_numbers := false
		for key: Variant in raw.numbers:
			if not key is String or not _text(raw.numbers[key], 64):
				return _failure("Lighting numeric recovery text is malformed.")
			var parts: PackedStringArray = key.split("/")
			if key not in ["period", "gain"] and not (parts.size() == 3 and parts[0] == "effect" \
					and parts[1] in Profile.EFFECT_ANCHOR_IDS and parts[2] in ["intensity", "lifetime"]):
				return _failure("Lighting numeric recovery field is unsupported.")
			if not raw.has("draft"):
				return _failure("Lighting numeric recovery has no draft.")
			if key.begins_with("effect/"): effect_numbers = true
			else: zone_numbers = true
		if zone_numbers and effect_numbers:
			return _failure("Lighting numeric recovery mixes exclusive edits.")
	if raw.has("draft"):
		var draft: Variant = raw.draft
		if not _keys(draft, DRAFT_KEYS, []) or not draft.zone is Dictionary \
				or not draft.effects is Array or draft.effects.size() > Profile.MAX_EFFECTS \
				or typeof(draft.color_pending) != TYPE_BOOL:
			return _failure("Lighting pending recovery fields are malformed.")
		if draft.brightness != null and (typeof(draft.brightness) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(draft.brightness)) or float(draft.brightness) < 0.0 or float(draft.brightness) > 2.0):
			return _failure("Lighting pending brightness is outside its limits.")
		var errors: Array[String] = []
		if not draft.zone.is_empty():
			Profile._normalize_zone(draft.zone, "pending zone", errors)
			if not errors.is_empty():
				return {"ok": false, "errors": errors}
			if draft.zone.get("id") != raw.zone or raw.color_text.size() != draft.zone.pattern.palette.size():
				return _failure("Lighting pending zone does not match its editor selection.")
		elif draft.color_pending:
			return _failure("Lighting pending color has no zone draft.")
		Profile._normalize_effects(draft.effects, errors)
		if not errors.is_empty():
			return {"ok": false, "errors": errors}
		for key: String in raw.get("numbers", {}):
			if key in ["period", "gain"] and draft.zone.is_empty():
				return _failure("Lighting numeric recovery has no zone.")
			if key == "gain" and draft.zone.reactive.source == "none":
				return _failure("Lighting numeric response has no source.")
			if key.begins_with("effect/"):
				var anchor := key.split("/")[1]
				if not draft.effects.any(func(effect: Dictionary) -> bool: return effect.anchor_id == anchor):
					return _failure("Lighting numeric recovery has no matching effect.")
	# Profile normalization canonicalizes steady/sequence patterns. Do not replace
	# a pending period, palette or other control value with that accepted form.
	return {"ok": true, "value": raw.duplicate(true), "errors": []}


static func _keys(raw: Variant, required: Array, optional: Array) -> bool:
	if not raw is Dictionary:
		return false
	for key: Variant in raw:
		if key not in required and key not in optional:
			return false
	for key: String in required:
		if not raw.has(key):
			return false
	return true


static func _text(value: Variant, limit: int) -> bool:
	if not value is String or value.length() > limit:
		return false
	for index: int in value.length():
		if value.unicode_at(index) < 32 or value.unicode_at(index) == 127:
			return false
	return true


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message]}
