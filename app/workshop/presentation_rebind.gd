extends RefCounted
## Nonmutating proposal for rebinding saved appearance to a newer companion.
## Call only from an explicit Workshop action; save the result as a separate build.

const Presentation := preload("res://workshop/presentation.gd")
const REPORT_FORMAT := "openrc-aircraft-presentation-rebind"
const REPORT_VERSION := 1


static func propose(profile_value: Variant, current_bindings_value: Variant) -> Dictionary:
	var stored: Dictionary = Presentation.validate_stored(profile_value)
	if not bool(stored.get("ok", false)):
		return _failure("Stored presentation profile is invalid.", stored.get("errors", PackedStringArray()))
	if bool(stored.get("newer_version", false)):
		return _failure("A newer presentation profile cannot be rebound by this version.")

	if typeof(current_bindings_value) != TYPE_DICTIONARY:
		return _failure("Current presentation bindings are unavailable or malformed.")
	var current_bindings: Dictionary = current_bindings_value
	var current_default: Dictionary = Presentation.defaults(current_bindings)
	var current_check: Dictionary = Presentation.validate(current_default, current_bindings)
	if not bool(current_check.get("ok", false)) or not bool(current_check.get("available", false)):
		return _failure("Current presentation bindings are invalid.", current_check.get("errors", PackedStringArray()))

	var old_profile: Dictionary = stored.get("profile", {})
	if old_profile.is_empty():
		return _failure("A supported stored presentation profile is required.")
	var old_pins: Dictionary = old_profile.get("binding", {})
	if _pins_are_empty(old_pins):
		return _failure("An unbound default has no previous aircraft identity to rebind.")

	var current_profile: Dictionary = current_check.get("profile", {})
	var new_pins: Dictionary = current_profile.get("binding", {})
	if str(old_pins.get("visual_family", "")) != str(new_pins.get("visual_family", "")):
		return _failure("Rebinding cannot change the aircraft visual family.")
	if str(old_pins.get("model_manifest_sha256", "")) != str(new_pins.get("model_manifest_sha256", "")):
		return _failure("Rebinding cannot change the physical model manifest.")
	if str(old_pins.get("slots_sha256", "")) == str(new_pins.get("slots_sha256", "")):
		return _failure("Presentation profile already matches the current companion.")
	if not old_profile.get("smoke", []).is_empty():
		return _failure("Saved smoke settings require their original companion and cannot be rebound by this proposal.")

	var candidate := old_profile.duplicate(true)
	candidate["binding"] = new_pins.duplicate(true)
	var checked: Dictionary = Presentation.validate(candidate, current_bindings)
	if not bool(checked.get("ok", false)) or not bool(checked.get("available", false)):
		return _failure("Saved presentation selections do not resolve against the current companion.",
			checked.get("errors", PackedStringArray()))

	var before_content := old_profile.duplicate(true)
	before_content.erase("binding")
	var after_content: Dictionary = checked.get("profile", {}).duplicate(true)
	after_content.erase("binding")
	if before_content != after_content:
		return _failure("Rebinding would change saved presentation settings; no proposal was created.")

	var lighting_layout: Variant = current_bindings.get("lighting_layout", {})
	var layout_version := int(lighting_layout.get("version", 0)) if lighting_layout is Dictionary else 0
	var report := {
		"format": REPORT_FORMAT,
		"version": REPORT_VERSION,
		"from_binding": old_pins.duplicate(true),
		"to_binding": new_pins.duplicate(true),
		"lighting_layout_version": layout_version,
		"rebound_fields": ["binding"],
		"settings_preserved": true,
		"descriptor_equivalence_proven": false,
		"requires_review": true,
		"save_as_copy_only": true,
		"review_note": "The stored profile has no original companion descriptors. Its selected IDs were checked against the current companion, but reuse of an ID cannot prove its prior meaning. Review the appearance before saving as a separate build.",
	}
	return {"ok": true, "errors": PackedStringArray(), "profile": checked.profile,
		"requires_review": true, "report": report}


## Creates an explicit copy proposal that replaces supported custom lighting with the
## current aircraft's stock lighting. Other appearance settings must remain valid.
static func propose_stock_lighting(profile_value: Variant, current_bindings_value: Variant) -> Dictionary:
	var stored: Dictionary = Presentation.validate_stored(profile_value)
	if bool(stored.get("newer_version", false)):
		return _failure("A newer presentation profile cannot be converted to stock lighting.")
	var repaired_lighting := false
	if not bool(stored.get("ok", false)):
		if typeof(profile_value) != TYPE_DICTIONARY:
			return _failure("Stored presentation profile is invalid.", stored.get("errors", PackedStringArray()))
		var raw_profile: Dictionary = profile_value
		var raw_version: Variant = raw_profile.get("version", null)
		if not _integer_number(raw_version) or int(raw_version) not in [3, Presentation.VERSION]:
			return _failure("Stored presentation profile is invalid.", stored.get("errors", PackedStringArray()))
		var raw_lighting: Variant = raw_profile.get("lighting", {})
		if raw_lighting is Dictionary and _integer_number(raw_lighting.get("version", null)) \
				and int(raw_lighting.version) > Presentation.LightingProfile.VERSION:
			return _failure("A newer lighting profile cannot be converted to stock lighting.")
		# A user's explicit stock choice may replace only malformed/missing lighting.
		# Validate every other field before offering the copy; future and unrelated bad
		# fields remain unavailable and are never coerced.
		var repair_candidate := raw_profile.duplicate(true)
		repair_candidate["lighting"] = Presentation.LightingProfile.defaults()
		var repaired: Dictionary = Presentation.validate(repair_candidate)
		if not bool(repaired.get("ok", false)):
			return _failure("Stored presentation profile is invalid.", repaired.get("errors", PackedStringArray()))
		stored = {"ok": true, "profile": repaired.get("profile", {}).duplicate(true),
			"available": repaired.get("available", false), "newer_version": false}
		repaired_lighting = true

	var old_profile: Dictionary = stored.get("profile", {})
	if old_profile.is_empty():
		return _failure("A supported stored presentation profile is required.")
	if int(old_profile.get("version", 0)) not in [3, Presentation.VERSION]:
		return _failure("Stock lighting drafts require a supported v3 or v4 profile; historical profiles already use stock lighting.")
	var lighting_check: Dictionary = Presentation.LightingProfile.validate(old_profile.get("lighting", null))
	if not bool(lighting_check.get("ok", false)):
		return _failure("Saved lighting settings cannot be replaced safely.", lighting_check.get("errors", PackedStringArray()))
	if not repaired_lighting and str(lighting_check.get("profile", {}).get("selection", "")) == "inherit":
		return _failure("Saved lighting already uses the aircraft's stock equipment.")

	if typeof(current_bindings_value) != TYPE_DICTIONARY:
		return _failure("Current presentation bindings are unavailable or malformed.")
	var current_bindings: Dictionary = current_bindings_value
	var current_check: Dictionary = Presentation.validate(Presentation.defaults(current_bindings), current_bindings)
	if not bool(current_check.get("ok", false)) or not bool(current_check.get("available", false)):
		return _failure("Current presentation bindings are invalid.", current_check.get("errors", PackedStringArray()))

	var old_pins: Dictionary = old_profile.get("binding", {})
	if _pins_are_empty(old_pins):
		return _failure("An unbound default has no previous aircraft identity to update.")
	var current_profile: Dictionary = current_check.get("profile", {})
	var new_pins: Dictionary = current_profile.get("binding", {})
	if str(old_pins.get("visual_family", "")) != str(new_pins.get("visual_family", "")):
		return _failure("Stock lighting cannot change the aircraft visual family.")
	if str(old_pins.get("model_manifest_sha256", "")) != str(new_pins.get("model_manifest_sha256", "")):
		return _failure("Stock lighting cannot change the physical model manifest.")

	var pins_changed := old_pins != new_pins
	var validated_source: Dictionary = {}
	if pins_changed:
		# Replace lighting before reuse of the existing rebind checks, so only the
		# preserved appearance fields and its smoke safeguard govern this operation.
		var nonlighting_source := old_profile.duplicate(true)
		nonlighting_source["lighting"] = Presentation.LightingProfile.defaults()
		var rebind: Dictionary = propose(nonlighting_source, current_bindings)
		if not bool(rebind.get("ok", false)):
			return rebind
		validated_source = rebind.get("profile", {}).duplicate(true)
	else:
		var checked: Dictionary = Presentation.validate(old_profile, current_bindings)
		if not bool(checked.get("ok", false)) or not bool(checked.get("available", false)):
			return _failure("Other saved appearance settings cannot be validated against the current companion.",
				checked.get("errors", PackedStringArray()))
		validated_source = checked.get("profile", {}).duplicate(true)

	var candidate := validated_source.duplicate(true)
	candidate["binding"] = new_pins.duplicate(true)
	candidate["lighting"] = Presentation.LightingProfile.defaults()
	var checked_candidate: Dictionary = Presentation.validate(candidate, current_bindings)
	if not bool(checked_candidate.get("ok", false)) or not bool(checked_candidate.get("available", false)):
		return _failure("The stock-lighting draft does not validate against the current companion.",
			checked_candidate.get("errors", PackedStringArray()))

	var before_nonlighting := old_profile.duplicate(true)
	before_nonlighting.erase("binding")
	before_nonlighting.erase("lighting")
	var after_nonlighting: Dictionary = checked_candidate.get("profile", {}).duplicate(true)
	after_nonlighting.erase("binding")
	after_nonlighting.erase("lighting")
	if before_nonlighting != after_nonlighting:
		return _failure("Creating a stock-lighting draft would change other appearance settings; no proposal was created.")

	var lighting_layout: Variant = current_bindings.get("lighting_layout", {})
	var layout_version := int(lighting_layout.get("version", 0)) if lighting_layout is Dictionary else 0
	var report := {
		"format": REPORT_FORMAT,
		"version": REPORT_VERSION,
		"operation": "stock_lighting_draft",
		"from_binding": old_pins.duplicate(true),
		"to_binding": new_pins.duplicate(true),
		"lighting_layout_version": layout_version,
		"rebound_fields": ["binding", "lighting"] if pins_changed else ["lighting"],
		"stock_lighting_selected": true,
		"repaired_missing_or_invalid_lighting": repaired_lighting,
		"nonlighting_settings_preserved": true,
		"descriptor_equivalence_proven": not pins_changed,
		"requires_review": true,
		"save_as_copy_only": true,
		"review_note": "The current aircraft's stock lighting replaces the saved lighting. Other appearance settings were checked against the current companion. Review before saving as a separate build.",
	}
	return {"ok": true, "errors": PackedStringArray(), "profile": checked_candidate.profile,
		"requires_review": true, "report": report}


static func _pins_are_empty(pins: Dictionary) -> bool:
	return str(pins.get("visual_family", "")).is_empty() \
		and str(pins.get("model_manifest_sha256", "")).is_empty() \
		and str(pins.get("slots_sha256", "")).is_empty()


static func _integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	var number := float(value)
	return floor(number) == number and abs(number) <= 9007199254740991.0


static func _failure(message: String, details: Variant = PackedStringArray()) -> Dictionary:
	var errors := PackedStringArray([message])
	if details is Array or details is PackedStringArray:
		for detail: Variant in details:
			var text := str(detail)
			if not text.is_empty():
				errors.append(text)
	return {"ok": false, "errors": errors, "profile": {}, "requires_review": false, "report": {}}
