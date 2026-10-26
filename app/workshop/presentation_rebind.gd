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


static func _pins_are_empty(pins: Dictionary) -> bool:
	return str(pins.get("visual_family", "")).is_empty() \
		and str(pins.get("model_manifest_sha256", "")).is_empty() \
		and str(pins.get("slots_sha256", "")).is_empty()


static func _failure(message: String, details: Variant = PackedStringArray()) -> Dictionary:
	var errors := PackedStringArray([message])
	if details is Array or details is PackedStringArray:
		for detail: Variant in details:
			var text := str(detail)
			if not text.is_empty():
				errors.append(text)
	return {"ok": false, "errors": errors, "profile": {}, "requires_review": false, "report": {}}
