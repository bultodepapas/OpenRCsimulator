extends RefCounted
## Preview a compatible-only copy of saved appearance settings. This module has no
## persistence or history dependency; callers apply the returned profile only after review.

const Presentation := preload("res://workshop/presentation.gd")

const DOMAIN_FIELDS: Array[String] = ["paint", "markings", "smoke"]


static func propose(source_profile: Variant, source_bindings: Variant,
		target_profile: Variant, target_bindings: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(source_bindings) != TYPE_DICTIONARY or (source_bindings as Dictionary).is_empty():
		errors.append("Source customization bindings are unavailable.")
	if typeof(target_bindings) != TYPE_DICTIONARY or (target_bindings as Dictionary).is_empty():
		errors.append("Target customization bindings are unavailable.")
	if not errors.is_empty():
		return _failure(errors)
	var checked_source: Dictionary = Presentation.validate(source_profile, source_bindings)
	if not bool(checked_source.get("ok", false)):
		_append_errors(errors, "Source presentation profile", checked_source.get("errors", PackedStringArray()))
	elif not bool(checked_source.get("available", false)):
		errors.append("Source profile is not available against its supplied bindings.")
	var checked_target: Dictionary = Presentation.validate(target_profile, target_bindings)
	if not bool(checked_target.get("ok", false)):
		_append_errors(errors, "Target presentation profile", checked_target.get("errors", PackedStringArray()))
	elif not bool(checked_target.get("available", false)):
		errors.append("Target profile is not available against its supplied bindings.")
	if not errors.is_empty():
		return _failure(errors)

	var source: Dictionary = checked_source["profile"]
	var target: Dictionary = checked_target["profile"].duplicate(true)
	# A stock v1 target has no authored choices to migrate. Offer its current-format
	# equivalent in the review; the caller still applies only after confirmation.
	var promoted_legacy_target := false
	if int(source.version) >= 2 \
			and target == Presentation.defaults(target_bindings, Presentation.LEGACY_VERSION):
		target = Presentation.defaults(target_bindings, int(source.version))
		promoted_legacy_target = true
	# Lighting v3 extends v2 without changing its paint or smoke interpretation.
	if int(source.version) >= 3 and int(target.version) == 2:
		target.version = 3
		target["lighting"] = Presentation.LightingProfile.defaults()
	elif int(source.version) == 2 and int(target.version) >= 3:
		source = source.duplicate(true)
		source.version = 3
		source["lighting"] = Presentation.LightingProfile.defaults()
	if int(source.version) == 4 and int(target.version) == 3:
		target.version = 4
		target["mechanical_audio"] = Presentation.MechanicalProfile.defaults()
	elif int(source.version) == 3 and int(target.version) == 4:
		source = source.duplicate(true)
		source.version = 4
		source["mechanical_audio"] = Presentation.MechanicalProfile.defaults()
	# Customized legacy profiles still require an explicit migration.
	if int(source.version) != int(target.version):
		return _failure(PackedStringArray(["Appearance profiles use different schema versions; review an explicit migration before copying."]))
	var source_slots: Dictionary = {
		"paint": _slot_map(source_bindings, "paint_slots"),
		"markings": _slot_map(source_bindings, "marking_slots"),
		"smoke": _slot_map(source_bindings, "smoke_slots"),
	}
	var target_slots: Dictionary = {
		"paint": _slot_map(target_bindings, "paint_slots"),
		"markings": _slot_map(target_bindings, "marking_slots"),
		"smoke": _slot_map(target_bindings, "smoke_slots"),
	}
	var applied: Array = []
	var skipped: Array = []
	if source.get("mechanical_audio", Presentation.MechanicalProfile.defaults()) != Presentation.MechanicalProfile.defaults():
		target["mechanical_audio"] = source.mechanical_audio.duplicate(true)
		applied.append({"domain": "mechanical_audio", "slot": "mechanical_audio", "reason": "compatible"})
	# Semantic kit IDs are universal; target geometry and optional anchors are fitted
	# by its own rig. Source mesh transforms and resource paths never cross aircraft.
	if source.get("lighting", {}).get("selection", "inherit") != "inherit":
		target["lighting"] = source.lighting.duplicate(true)
		applied.append({"domain": "lighting", "slot": "lighting", "reason": "compatible"})
	for domain: String in DOMAIN_FIELDS:
		for entry_value: Variant in source.get(domain, []):
			var entry: Dictionary = entry_value
			var slot: String = str(entry.get("slot", ""))
			var source_slot: Dictionary = source_slots[domain].get(slot, {})
			var target_slot: Dictionary = target_slots[domain].get(slot, {})
			var reason: String = _compatibility_reason(domain, entry, source_slot, target_slot, target_bindings)
			if reason == "compatible":
				_replace_entry(target[domain], slot, entry)
				applied.append({"domain": domain, "slot": slot, "reason": "compatible"})
			else:
				skipped.append({"domain": domain, "slot": slot, "reason": reason})
		(target[domain] as Array).sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return str(left.get("slot", "")) < str(right.get("slot", "")))

	var checked_proposal: Dictionary = Presentation.validate(target, target_bindings)
	if not bool(checked_proposal.get("ok", false)) or not bool(checked_proposal.get("available", false)):
		_append_errors(errors, "Proposed target profile", checked_proposal.get("errors", PackedStringArray()))
		if errors.is_empty():
			errors.append("Proposed profile is unavailable against the target bindings.")
		return _failure(errors)
	return {"ok": true, "errors": errors, "profile": checked_proposal["profile"].duplicate(true),
		"applied": applied, "skipped": skipped, "promoted_legacy_target": promoted_legacy_target}


static func _compatibility_reason(domain: String, entry: Dictionary, source_slot: Dictionary,
		target_slot: Dictionary, target_bindings: Dictionary) -> String:
	if source_slot.is_empty():
		return "source_slot_missing"
	if target_slot.is_empty():
		return "target_slot_missing"
	match domain:
		"paint":
			if str(entry.get("pattern", "")) != "solid":
				return "paint_pattern_unsupported"
			if _paint_kind_signature(source_slot, "targets") != _paint_kind_signature(target_slot, "targets"):
				return "paint_kind_mismatch"
			if str(entry.get("accent", "none")) != "none":
				if (source_slot.get("accent_targets", []) as Array).is_empty() \
						or (target_slot.get("accent_targets", []) as Array).is_empty():
					return "paint_accent_unsupported"
				if _paint_kind_signature(source_slot, "accent_targets") \
						!= _paint_kind_signature(target_slot, "accent_targets"):
					return "paint_accent_kind_mismatch"
			return "compatible"
		"markings":
			if str(target_bindings.get("presentation_engine_version", "")) != Presentation.PRESENTATION_ENGINE_VERSION:
				return "marking_glyph_support_unpinned"
			if str(entry.get("text", "")).length() > int(target_slot.get("max_chars", 0)):
				return "marking_text_too_long"
			return "compatible"
		"smoke":
			if str(source_slot.get("kind", "")) != str(target_slot.get("kind", "")) \
					or str(source_slot.get("role", "")) != str(target_slot.get("role", "")):
				return "smoke_endpoint_mismatch"
			for field: String in ["activation_policy", "source_kind", "emissions_preset"]:
				if str(source_slot.get(field, "")) != str(target_slot.get(field, "")):
					return "smoke_source_policy_mismatch"
			return "compatible"
	return "unsupported_domain"


static func _paint_kind_signature(slot: Dictionary, field: String) -> String:
	var kinds := PackedStringArray()
	for target_value: Variant in slot.get(field, []):
		if typeof(target_value) != TYPE_DICTIONARY:
			continue
		var kind: String = str(target_value.get("kind", ""))
		if not kind.is_empty() and not kinds.has(kind):
			kinds.append(kind)
	kinds.sort()
	return ",".join(kinds)


static func _slot_map(bindings: Dictionary, field: String) -> Dictionary:
	var result: Dictionary = {}
	for slot_value: Variant in bindings.get(field, []):
		if typeof(slot_value) == TYPE_DICTIONARY:
			var slot: Dictionary = slot_value
			result[str(slot.get("id", ""))] = slot
	return result


static func _replace_entry(entries: Array, slot: String, source_entry: Dictionary) -> void:
	for index: int in entries.size():
		if typeof(entries[index]) == TYPE_DICTIONARY \
				and str(entries[index].get("slot", "")) == slot:
			entries[index] = source_entry.duplicate(true)
			return
	entries.append(source_entry.duplicate(true))


static func _append_errors(target: PackedStringArray, context: String, values: Variant) -> void:
	if values is PackedStringArray or values is Array:
		for value: Variant in values:
			target.append("%s: %s" % [context, str(value)])
	else:
		target.append("%s: validation failed." % context)


static func _failure(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "errors": errors, "profile": {}, "applied": [], "skipped": []}
