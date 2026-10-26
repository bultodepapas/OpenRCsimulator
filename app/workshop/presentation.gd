extends RefCounted
## Closed, data-only aircraft appearance profile and canonical presentation identity.
## Bindings are supplied by the registered customization companion; profiles never
## carry resource paths, executable scripts, or mount coordinates.

const FORMAT: String = "openrc-aircraft-presentation"
const VERSION: int = 4
const LEGACY_VERSION: int = 1
const IDENTITY_FORMAT: String = "openrc-aircraft-presentation-identity"
const IDENTITY_VERSION: int = 1
const BINDINGS_FORMAT: String = "openrc-aircraft-customization-bindings"
const BINDINGS_VERSION: int = 4
const LEGACY_BINDINGS_VERSION: int = 1
const SCHEDULE_POLICY: String = "ticks-240-v1"
const PRESENTATION_ENGINE_VERSION: String = "4.8.0"
const MAX_PROFILE_BYTES: int = 65536
const MAX_PROFILE_DEPTH: int = 12
const MAX_PROFILE_NODES: int = 8192
const MAX_PAINT_SLOTS: int = 32
const MAX_MARKING_SLOTS: int = 16
const MAX_SMOKE_SLOTS: int = 4
const MAX_SHOW_SMOKE_SLOTS: int = 3
const MAX_SOURCE_SMOKE_SLOTS: int = 1
const MAX_AUTHORED_SMOKE_SLOTS: int = 8
const SMOKE_V2_BOUNDS := {
	"density": [0.0, 2.0, 1.0], "emission_rate_hz": [1.0, 240.0, 48.0],
	"jet_speed_mps": [0.0, 30.0, 0.65], "dispersion_m2_s": [0.0, 2.0, 0.1],
	"buoyancy_mps": [-2.0, 3.0, 0.27], "turbulence_mps": [0.0, 5.0, 0.22],
	"drag_s": [0.05, 3.0, 0.4], "velocity_inheritance": [0.0, 1.0, 1.0],
	"phase_offset_s": [0.0, 60.0, 0.0],
}
const MAX_PALETTE_COLORS: int = 8
const MAX_TEXT_LENGTH: int = 12
const MAX_LABEL_LENGTH: int = 32
const MAX_SAFE_INTEGER: float = 9007199254740991.0
const PROFILE_KEYS: PackedStringArray = [
	"format", "version", "binding", "paint", "markings", "smoke", "visual_seed", "schedule_policy",
]
const PROFILE_BINDING_KEYS: PackedStringArray = ["visual_family", "model_manifest_sha256", "slots_sha256"]
const BINDINGS_KEYS: PackedStringArray = [
	"format", "version", "visual_family", "model_manifest_sha256", "paint_slots", "marking_slots", "smoke_slots", "slots_sha256",
]
const BINDINGS_V2_KEYS: PackedStringArray = [
	"format", "version", "visual_family", "model_manifest_sha256", "paint_slots", "marking_slots", "smoke_slots",
	"presentation_sources", "presentation_engine_version", "slots_sha256",
]
const PresentationSources := preload("res://render/presentation_sources.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const LightingProfile := preload("res://render/lighting/lighting_profile.gd")
const MechanicalProfile := preload("res://audio/mechanical_profile.gd")
const PRESENTATION_SOURCE_PATHS: PackedStringArray = [
	"res://render/aircraft_customization.gd",
	"res://render/presentation_sources.gd",
	"res://render/smoke/exhaust.gd",
	"res://render/smoke/process.gdshader",
	"res://render/smoke/profile_process.gdshader",
	"res://render/smoke/profile_smoke.gd",
	"res://render/smoke/profile_smoke_schedule.gd",
]
const PAINT_ENTRY_KEYS: PackedStringArray = ["slot", "color", "pattern", "accent"]
const MARKING_ENTRY_KEYS: PackedStringArray = ["slot", "text", "color"]
const SMOKE_ENTRY_KEYS: PackedStringArray = [
	"slot", "enabled", "color", "amount", "width_m", "lifetime_s", "shape", "mode",
	"burst_s", "pulse_period_s", "pulse_duty", "palette", "step_s",
]
const PAINT_SLOT_KEYS: PackedStringArray = ["id", "label", "targets"]
const PAINT_SLOT_OPTIONAL_KEYS: PackedStringArray = ["accent_targets"]
const MARKING_SLOT_KEYS: PackedStringArray = ["id", "label", "max_chars", "targets"]
const SMOKE_SLOT_KEYS: PackedStringArray = ["id", "label", "kind", "pair", "role"]
const SMOKE_SHOW_SLOT_KEYS: PackedStringArray = ["node_path", "position_m", "direction"]
const SMOKE_SOURCE_SLOT_KEYS: PackedStringArray = [
	"source_kind", "source_anchor_ref", "physical_source_ref", "physical_source_kind_ref",
]
const PAINT_TARGET_KEYS: PackedStringArray = ["node_path", "surface", "kind"]
const PAINT_TARGET_OPTIONAL_KEYS: PackedStringArray = ["parameter"]
const MARKING_TARGET_KEYS: PackedStringArray = ["node_path", "position_m", "direction", "up", "width_m", "height_m"]
const PAINT_PATTERNS: PackedStringArray = ["solid"]
const SMOKE_SHAPES: PackedStringArray = ["ribbon", "cloud", "fan"]
const SMOKE_MODES: PackedStringArray = ["hold", "burst", "pulse"]
const HEX_DIGITS: String = "0123456789ABCDEF"


## Explicit legacy/stock appearance. Passing a verified companion binds even the empty
## profile to that exact model and slot contract.
static func defaults(bindings: Dictionary = {}, version: int = VERSION) -> Dictionary:
	var pins: Dictionary = {"visual_family": "", "model_manifest_sha256": "", "slots_sha256": ""}
	if not bindings.is_empty():
		var checked_bindings: Dictionary = _validate_bindings(bindings)
		if bool(checked_bindings.get("ok", false)):
			pins = checked_bindings["pins"].duplicate(true)
	var profile: Dictionary = {
		"format": FORMAT,
		"version": version,
		"binding": pins,
		"paint": [],
		"markings": [],
		"smoke": [],
		"visual_seed": 0,
		"schedule_policy": SCHEDULE_POLICY,
	}
	if version >= 3:
		profile["lighting"] = LightingProfile.defaults()
	if version >= 4:
		profile["mechanical_audio"] = MechanicalProfile.defaults()
	return profile


## Validate and canonicalize a profile. With no companion, registered selections remain
## structurally readable but report available=false; trial preparation always supplies one.
static func validate(value: Variant, bindings: Dictionary = {}) -> Dictionary:
	var errors := PackedStringArray()
	var context: Dictionary = {"ok": true, "available": false, "legacy": true, "pins": {
		"visual_family": "", "model_manifest_sha256": "", "slots_sha256": ""},
		"binding_version": BINDINGS_VERSION, "paint_slots": {}, "marking_slots": {}, "smoke_slots": {}}
	if not bindings.is_empty():
		context = _validate_bindings(bindings)
		if not bool(context.get("ok", false)):
			return _result(false, context.get("errors", PackedStringArray()), {}, false)

	if typeof(value) != TYPE_DICTIONARY:
		errors.append("Presentation profile must be an object.")
		return _result(false, errors, {}, false)
	var tree_result: Dictionary = _validate_json_tree(value)
	if not bool(tree_result.get("ok", false)):
		errors.append_array(tree_result.get("errors", PackedStringArray()))
		return _result(false, errors, {}, false)
	if JSON.stringify(value, "", true, true).to_utf8_buffer().size() > MAX_PROFILE_BYTES:
		errors.append("Presentation profile exceeds the %d-byte limit." % MAX_PROFILE_BYTES)
		return _result(false, errors, {}, false)

	# Empty dictionaries are historical absence. New edits call defaults() explicitly.
	var source: Dictionary = value
	if source.is_empty():
		source = defaults(bindings, LEGACY_VERSION)
	var expected_profile_keys := PROFILE_KEYS.duplicate()
	if _integer_number(source.get("version")) and int(source.version) >= 3:
		expected_profile_keys.append("lighting")
	if _integer_number(source.get("version")) and int(source.version) >= 4:
		expected_profile_keys.append("mechanical_audio")
	if not _has_exact_keys(source, expected_profile_keys):
		errors.append("Presentation profile has missing or unsupported fields.")
		return _result(false, errors, {}, false)
	if source["format"] != FORMAT or not _integer_number(source["version"]) \
			or int(source["version"]) not in [LEGACY_VERSION, 2, 3, VERSION]:
		errors.append("Presentation profile format or version is unsupported.")
		return _result(false, errors, {}, false)
	if source["schedule_policy"] != SCHEDULE_POLICY:
		errors.append("Presentation schedule policy is unsupported.")
	if not _integer_number(source["visual_seed"]) or int(source["visual_seed"]) < 0 \
			or float(source["visual_seed"]) > 2147483647.0:
		errors.append("Presentation visual_seed must be an integer from 0 through 2147483647.")
	if not errors.is_empty():
		return _result(false, errors, {}, false)
	context["profile_version"] = int(source["version"])
	if bindings.is_empty() and int(source["version"]) == LEGACY_VERSION:
		context["binding_version"] = 2

	var binding_result: Dictionary = _validate_profile_binding(source["binding"])
	if not bool(binding_result.get("ok", false)):
		errors.append_array(binding_result.get("errors", PackedStringArray()))
		return _result(false, errors, {}, false)
	var requested_pins: Dictionary = binding_result["pins"]
	var has_entries: bool = _has_entries(source)
	var profile_is_unbound_default: bool = _pins_are_empty(requested_pins) and not has_entries
	var available: bool = bool(context.get("available", false))
	var resolved_pins: Dictionary = requested_pins.duplicate(true)
	if available:
		var registered_pins: Dictionary = context["pins"]
		if profile_is_unbound_default:
			resolved_pins = registered_pins.duplicate(true)
		elif requested_pins != registered_pins:
			errors.append("Presentation profile model or slot binding pins are stale.")
			return _result(false, errors, {}, false)
	else:
		if has_entries and _pins_are_empty(requested_pins):
			errors.append("A customized profile must pin its model and slot contract.")
			return _result(false, errors, {}, false)
		if has_entries:
			available = false
		else:
			available = _pins_are_empty(requested_pins)

	var canonical_paint: Array = []
	var paint_seen: Dictionary = {}
	if typeof(source["paint"]) != TYPE_ARRAY or source["paint"].size() > MAX_PAINT_SLOTS:
		errors.append("Presentation paint selections must be an array of at most %d entries." % MAX_PAINT_SLOTS)
	else:
		for entry: Variant in source["paint"]:
			var checked: Dictionary = _validate_paint_entry(entry, context, available)
			if not bool(checked.get("ok", false)):
				errors.append_array(checked.get("errors", PackedStringArray()))
				break
			var normalized: Dictionary = checked["value"]
			if paint_seen.has(normalized["slot"]):
				errors.append("Presentation profile contains a duplicate paint slot.")
				break
			paint_seen[normalized["slot"]] = true
			canonical_paint.append(normalized)
	canonical_paint.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left["slot"]) < str(right["slot"]))

	var canonical_markings: Array = []
	var marking_seen: Dictionary = {}
	if typeof(source["markings"]) != TYPE_ARRAY or source["markings"].size() > MAX_MARKING_SLOTS:
		errors.append("Presentation markings must be an array of at most %d entries." % MAX_MARKING_SLOTS)
	else:
		for entry: Variant in source["markings"]:
			var checked: Dictionary = _validate_marking_entry(entry, context, available)
			if not bool(checked.get("ok", false)):
				errors.append_array(checked.get("errors", PackedStringArray()))
				break
			var normalized: Dictionary = checked["value"]
			if marking_seen.has(normalized["slot"]):
				errors.append("Presentation profile contains a duplicate marking slot.")
				break
			marking_seen[normalized["slot"]] = true
			canonical_markings.append(normalized)
	canonical_markings.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left["slot"]) < str(right["slot"]))

	var canonical_smoke: Array = []
	var smoke_seen: Dictionary = {}
	var show_smoke_count: int = 0
	var source_smoke_count: int = 0
	var smoke_limit: int = MAX_SMOKE_SLOTS if int(source["version"]) == LEGACY_VERSION else MAX_AUTHORED_SMOKE_SLOTS
	var enabled_smoke_count: int = 0
	if typeof(source["smoke"]) != TYPE_ARRAY or source["smoke"].size() > smoke_limit:
		errors.append("Presentation smoke profiles must be an array of at most %d entries." % MAX_SMOKE_SLOTS)
	else:
		for entry: Variant in source["smoke"]:
			var checked: Dictionary = _validate_smoke_entry(entry, context, available)
			if not bool(checked.get("ok", false)):
				errors.append_array(checked.get("errors", PackedStringArray()))
				break
			var normalized: Dictionary = checked["value"]
			if bool(normalized["enabled"]):
				enabled_smoke_count += 1
			if smoke_seen.has(normalized["slot"]):
				errors.append("Presentation profile contains a duplicate smoke slot.")
				break
			smoke_seen[normalized["slot"]] = true
			if available:
				var smoke_kind: String = str(context["smoke_slots"][normalized["slot"]].get("kind", ""))
				if smoke_kind == "show":
					show_smoke_count += 1
				elif smoke_kind == "source":
					source_smoke_count += 1
			canonical_smoke.append(normalized)
	if int(source["version"]) == LEGACY_VERSION and (show_smoke_count > MAX_SHOW_SMOKE_SLOTS or source_smoke_count > MAX_SOURCE_SMOKE_SLOTS):
		errors.append("Presentation smoke profiles support at most three show slots and one source outlet.")
	if enabled_smoke_count > MAX_SMOKE_SLOTS:
		errors.append("Presentation smoke profiles support at most four enabled outlets.")
	canonical_smoke.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left["slot"]) < str(right["slot"]))

	if not errors.is_empty():
		return _result(false, errors, {}, false)
	var canonical: Dictionary = {
		"format": FORMAT,
		"version": int(source["version"]),
		"binding": resolved_pins,
		"paint": canonical_paint,
		"markings": canonical_markings,
		"smoke": canonical_smoke,
		"visual_seed": int(source["visual_seed"]),
		"schedule_policy": SCHEDULE_POLICY,
	}
	if int(source.version) >= 3:
		var lighting_result: Dictionary = LightingProfile.validate(source.lighting)
		if not bool(lighting_result.get("ok", false)):
			errors.append_array(lighting_result.get("errors", PackedStringArray()))
			return _result(false, errors, {}, false)
		canonical["lighting"] = lighting_result.profile
	if int(source.version) >= 4:
		var mechanical_result: Dictionary = MechanicalProfile.validate(source.mechanical_audio)
		if not mechanical_result.ok:
			errors.append_array(mechanical_result.errors)
			return _result(false, errors, {}, false)
		canonical["mechanical_audio"] = mechanical_result.profile
	var canonical_bytes: PackedByteArray = _canonical_json(canonical).to_utf8_buffer()
	if canonical_bytes.size() > MAX_PROFILE_BYTES:
		errors.append("Canonical presentation profile exceeds the %d-byte limit." % MAX_PROFILE_BYTES)
		return _result(false, errors, {}, false)
	return _result(true, errors, canonical, available,
		_identity_sha256(canonical, int(context.get("binding_version", BINDINGS_VERSION))))


## Return the stable identity for a profile already bound to the supplied companion.
## A missing companion is accepted only for the explicit empty legacy appearance.
static func identity(profile: Variant, bindingpins: Dictionary = {}) -> String:
	var checked: Dictionary = validate(profile, bindingpins)
	if not bool(checked.get("ok", false)) or not bool(checked.get("available", false)):
		return ""
	return str(checked.get("identity_sha256", ""))


## Structured sidecar identity for trace metadata. This remains separate from the
## physical Workshop trial identity and contains only the three presentation pins.
static func identity_record(profile: Variant, bindings: Dictionary = {}) -> Dictionary:
	var checked: Dictionary = validate(profile, bindings)
	if not bool(checked.get("ok", false)):
		return {}
	var canonical: Dictionary = checked["profile"]
	return {
		"format": IDENTITY_FORMAT,
		"version": IDENTITY_VERSION,
		"sha256": str(checked.get("identity_sha256", "")),
		"schedule_policy": str(canonical.get("schedule_policy", SCHEDULE_POLICY)),
		"visual_seed": int(canonical.get("visual_seed", 0)),
		"binding": canonical.get("binding", {}).duplicate(true),
	}


## Storage accepts a bounded, structurally valid future profile as unavailable data. The
## supported-runtime validator continues to reject its newer schema version.
static func validate_stored(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		var version_value: Variant = value.get("version", null)
		if _integer_number(version_value) and int(version_value) > VERSION:
			if value.get("format", null) != FORMAT:
				return _result(false, PackedStringArray(["Future presentation profile format is unsupported."]), {}, false)
			var tree_result: Dictionary = _validate_json_tree(value)
			if not bool(tree_result.get("ok", false)):
				return _result(false, tree_result.get("errors", PackedStringArray()), {}, false)
			if JSON.stringify(value, "", true, true).to_utf8_buffer().size() > MAX_PROFILE_BYTES:
				return _result(false, PackedStringArray(["Future presentation profile exceeds the %d-byte limit." % MAX_PROFILE_BYTES]), {}, false)
			return {"ok": true, "errors": PackedStringArray(), "profile": value.duplicate(true),
				"available": false, "newer_version": true, "identity_sha256": ""}
	return validate(value)


## Public hash helper shared with the generated companion pipeline. Slot lists are sorted by
## ID; target order is meaningful and remains intact. Object keys are recursively sorted.
static func bindings_sha256(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return ""
	var material: Dictionary = value.duplicate(true)
	material.erase("slots_sha256")
	for slot_key: String in ["paint_slots", "marking_slots", "smoke_slots"]:
		if typeof(material.get(slot_key, null)) == TYPE_ARRAY:
			var slots: Array = material[slot_key].duplicate(true)
			slots.sort_custom(func(left: Variant, right: Variant) -> bool:
				if typeof(left) != TYPE_DICTIONARY or typeof(right) != TYPE_DICTIONARY:
					return str(left) < str(right)
				return str(left.get("id", "")) < str(right.get("id", "")))
			material[slot_key] = slots
	if typeof(material.get("presentation_sources", null)) == TYPE_ARRAY:
		var sources: Array = material["presentation_sources"].duplicate(true)
		sources.sort_custom(func(left: Variant, right: Variant) -> bool:
			if typeof(left) != TYPE_DICTIONARY or typeof(right) != TYPE_DICTIONARY:
				return str(left) < str(right)
			return str(left.get("path", "")) < str(right.get("path", "")))
		material["presentation_sources"] = sources
	return _sha256(_canonical_json(material).to_utf8_buffer())


static func _validate_paint_entry(value: Variant, context: Dictionary, available: bool) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY or not _has_exact_keys(value, PAINT_ENTRY_KEYS):
		errors.append("Paint selection has missing or unsupported fields.")
		return {"ok": false, "errors": errors}
	var slot: Variant = value["slot"]
	if typeof(slot) != TYPE_STRING or not _valid_slot_id(str(slot)):
		errors.append("Paint selection has an invalid registered slot ID.")
		return {"ok": false, "errors": errors}
	var slot_id: String = slot
	var slot_descriptor: Dictionary = {}
	if available:
		var slots: Dictionary = context.get("paint_slots", {})
		if not slots.has(slot_id):
			errors.append("Paint slot '%s' is unavailable in the pinned model." % slot_id)
			return {"ok": false, "errors": errors}
		slot_descriptor = slots[slot_id]
	elif typeof(value["pattern"]) != TYPE_STRING or not PAINT_PATTERNS.has(value["pattern"]):
		errors.append("Paint pattern is unsupported.")
		return {"ok": false, "errors": errors}
	if typeof(value["pattern"]) != TYPE_STRING or not PAINT_PATTERNS.has(value["pattern"]):
		errors.append("Paint pattern is unsupported.")
	var color_result: Dictionary = _canonical_color(value["color"], true)
	if not bool(color_result.get("ok", false)):
		errors.append("Paint color must be an opaque sRGB #RRGGBB or #RRGGBBFF swatch.")
	var accent_value: Variant = value["accent"]
	var accent: String = ""
	if typeof(accent_value) != TYPE_STRING:
		errors.append("Paint accent must be 'none' or a canonical color swatch.")
	elif accent_value == "none":
		accent = "none"
	else:
		var accent_result: Dictionary = _canonical_color(accent_value, true)
		var supports_accent: bool = not slot_descriptor.get("accent_targets", []).is_empty() if available else false
		if not bool(accent_result.get("ok", false)) or (available and not supports_accent):
			errors.append("Paint accent is invalid, non-opaque, or the registered slot has no accent target.")
		else:
			accent = str(accent_result["value"])
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": errors, "value": {
		"slot": slot_id,
		"color": color_result["value"],
		"pattern": str(value["pattern"]),
		"accent": accent,
	}}


static func _validate_marking_entry(value: Variant, context: Dictionary, available: bool) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY or not _has_exact_keys(value, MARKING_ENTRY_KEYS):
		errors.append("Marking selection has missing or unsupported fields.")
		return {"ok": false, "errors": errors}
	var slot: Variant = value["slot"]
	var label: Variant = value["text"]
	if typeof(slot) != TYPE_STRING or not _valid_slot_id(str(slot)):
		errors.append("Marking selection has an invalid registered panel ID.")
		return {"ok": false, "errors": errors}
	if typeof(label) != TYPE_STRING or not _valid_marking_text(str(label)):
		errors.append("Marking text must use 1–%d supported English/Spanish letters, digits, spaces, or hyphens." % MAX_TEXT_LENGTH)
		return {"ok": false, "errors": errors}
	var slot_descriptor: Dictionary = {}
	if available:
		var slots: Dictionary = context.get("marking_slots", {})
		if not slots.has(str(slot)):
			errors.append("Marking panel '%s' is unavailable in the pinned model." % str(slot))
		else:
			slot_descriptor = slots[str(slot)]
			if str(label).length() > int(slot_descriptor.get("max_chars", 0)):
				errors.append("Marking text exceeds the registered %d-character panel limit." % int(slot_descriptor.max_chars))
	var color_result: Dictionary = _canonical_color(value["color"], true)
	if not bool(color_result.get("ok", false)):
		errors.append("Marking color must be an opaque sRGB #RRGGBB or #RRGGBBFF swatch.")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": errors, "value": {
		"slot": str(slot), "text": str(label), "color": color_result["value"],
	}}


static func smoke_v2_defaults() -> Dictionary:
	var result: Dictionary = {"palette_mode": "step"}
	for key: String in SMOKE_V2_BOUNDS:
		result[key] = float(SMOKE_V2_BOUNDS[key][2])
	return result


## Pure shared renderer/editor normalization. Never mutates a stored profile.
static func normalize_smoke_entry(value: Variant, version: int = VERSION) -> Dictionary:
	var tree := _validate_json_tree(value)
	if not tree.get("ok", false):
		return tree
	return _validate_smoke_entry(value, {"profile_version": version}, false)


## Produce a new revision proposal only; old records and bindings remain untouched.
static func migrate_v1(profile: Variant, old_bindings: Dictionary, new_bindings: Dictionary) -> Dictionary:
	var old: Dictionary = validate(profile, old_bindings)
	if not old.get("ok", false) or int(old.get("profile", {}).get("version", 0)) != LEGACY_VERSION:
		return {"ok": false, "errors": ["Migration requires a verified v1 profile and its original companion."]}
	var target: Dictionary = _validate_bindings(new_bindings)
	if not target.get("ok", false) or old_bindings.get("visual_family") != new_bindings.get("visual_family") \
			or old_bindings.get("model_manifest_sha256") != new_bindings.get("model_manifest_sha256"):
		return {"ok": false, "errors": ["Migration cannot change aircraft family or physical model identity."]}
	var proposed: Dictionary = old.profile.duplicate(true)
	proposed.version = 2
	proposed.binding = target.pins.duplicate(true)
	var changes: Array = []
	for entry: Dictionary in proposed.smoke:
		var slot_id := str(entry.slot)
		if not target.smoke_slots.has(slot_id):
			return {"ok": false, "errors": ["Migration outlet is unavailable: " + slot_id]}
		var previous: Dictionary = {}
		for slot: Dictionary in old_bindings.get("smoke_slots", []):
			if str(slot.id) == slot_id:
				previous = slot
		if previous.get("kind") != target.smoke_slots[slot_id].get("kind"):
			return {"ok": false, "errors": ["Migration cannot silently change outlet purpose: " + slot_id]}
		entry.merge(smoke_v2_defaults(), false)
		changes.append({"slot": slot_id, "old_slot": slot_id, "new_slot": slot_id,
			"old_preset": str(previous.get("emissions_preset", "legacy_v1")),
			"new_preset": str(target.smoke_slots[slot_id].get("emissions_preset", "legacy_v1")),
			"old_activation_policy": str(previous.get("activation_policy", "legacy_v1")),
			"new_activation_policy": str(target.smoke_slots[slot_id].get("activation_policy", "legacy_v1")),
			"settings": smoke_v2_defaults(), "legacy_amount": entry.amount})
	var checked: Dictionary = validate(proposed, new_bindings)
	if not checked.get("ok", false):
		return checked
	return {"ok": true, "errors": [], "profile": checked.profile, "report": {
		"from_version": LEGACY_VERSION, "to_version": 2,
		"old_binding": old.profile.binding.duplicate(true), "new_binding": checked.profile.binding.duplicate(true),
		"outlets": changes, "requires_review": true,
		"empty_smoke_policy": "explicitly_disabled", "legacy_amount_policy": "preserved_history_v2_uses_density_and_rate",
		"appearance_policy": "v2 motion and density require visual review; no equivalence claimed",
	}}


static func _validate_smoke_entry(value: Variant, context: Dictionary, available: bool) -> Dictionary:
	var errors := PackedStringArray()
	var version: int = int(context.get("profile_version", LEGACY_VERSION))
	if version not in [LEGACY_VERSION, 2, 3, VERSION] or typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["Smoke profile version or object is unsupported."]}
	var expected := SMOKE_ENTRY_KEYS.duplicate()
	if version >= 2:
		for key: String in smoke_v2_defaults():
			if value.has(key):
				expected.append(key)
	if not _has_exact_keys(value, expected):
		errors.append("Smoke profile has missing or unsupported fields.")
		return {"ok": false, "errors": errors}
	var slot: Variant = value["slot"]
	if typeof(slot) != TYPE_STRING or not _valid_slot_id(str(slot)):
		errors.append("Smoke profile has an invalid registered show-slot ID.")
		return {"ok": false, "errors": errors}
	if available:
		var registered_smoke: Dictionary = context.get("smoke_slots", {})
		if not registered_smoke.has(str(slot)) or str(registered_smoke.get(str(slot), {}).get("kind", "")) not in ["show", "source"]:
			errors.append("Smoke profile slot '%s' is not an authored show or source endpoint." % str(slot))
	if typeof(value["enabled"]) != TYPE_BOOL:
		errors.append("Smoke enabled must be a boolean.")
	var color_result: Dictionary = _canonical_color(value["color"])
	if not bool(color_result.get("ok", false)):
		errors.append("Smoke color must be an sRGB #RRGGBB or #RRGGBBAA swatch.")
	var amount: float = _bounded_number(value["amount"], 0.0, 1.0, "amount", errors)
	var width_m: float = _bounded_number(value["width_m"], 0.01, 2.0, "width_m", errors)
	var lifetime_s: float = _bounded_number(value["lifetime_s"], 0.1, 8.0, "lifetime_s", errors)
	var burst_s: float = _bounded_number(value["burst_s"], 0.0, 8.0, "burst_s", errors)
	var pulse_period_s: float = _bounded_number(value["pulse_period_s"], 0.0, 8.0, "pulse_period_s", errors)
	var pulse_duty: float = _bounded_number(value["pulse_duty"], 0.0, 1.0, "pulse_duty", errors)
	var step_s: float = _bounded_number(value["step_s"], 0.0, 8.0, "step_s", errors)
	var shape: Variant = value["shape"]
	var mode: Variant = value["mode"]
	if typeof(shape) != TYPE_STRING or not SMOKE_SHAPES.has(shape):
		errors.append("Smoke shape is unsupported.")
	if typeof(mode) != TYPE_STRING or not SMOKE_MODES.has(mode):
		errors.append("Smoke mode is unsupported.")
	if typeof(value["palette"]) != TYPE_ARRAY or value["palette"].size() > MAX_PALETTE_COLORS:
		errors.append("Smoke palette must be an array of at most %d colors." % MAX_PALETTE_COLORS)
		return {"ok": false, "errors": errors}
	var palette: Array = []
	for palette_color: Variant in value["palette"]:
		var palette_result: Dictionary = _canonical_color(palette_color)
		if not bool(palette_result.get("ok", false)):
			errors.append("Smoke palette entries must be canonical sRGB swatches.")
			break
		palette.append(palette_result["value"])
	if typeof(mode) == TYPE_STRING:
		match str(mode):
			"hold":
				if burst_s != 0.0 or pulse_period_s != 0.0 or pulse_duty != 0.0:
					errors.append("Hold smoke mode requires zero burst and pulse timing fields.")
			"burst":
				if burst_s < 0.05 or pulse_period_s != 0.0 or pulse_duty != 0.0:
					errors.append("Burst smoke mode requires 0.05–8 seconds and zero pulse fields.")
			"pulse":
				if burst_s != 0.0 or pulse_period_s < 0.05 or pulse_duty < 0.01:
					errors.append("Pulse smoke mode requires a 0.05–8 second period and 0.01–1 duty.")
	if palette.size() <= 1 and step_s != 0.0:
		errors.append("A smoke palette with zero or one color requires step_s=0.")
	if palette.size() > 1 and step_s < 0.05:
		errors.append("A multi-color smoke palette requires step_s from 0.05 through 8 seconds.")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var normalized: Dictionary = {
		"slot": str(slot),
		"enabled": bool(value["enabled"]),
		"color": color_result["value"],
		"amount": amount,
		"width_m": width_m,
		"lifetime_s": lifetime_s,
		"shape": str(shape),
		"mode": str(mode),
		"burst_s": burst_s,
		"pulse_period_s": pulse_period_s,
		"pulse_duty": pulse_duty,
		"palette": palette,
		"step_s": step_s,
	}
	if version >= 2:
		for key: String in SMOKE_V2_BOUNDS:
			var bounds: Array = SMOKE_V2_BOUNDS[key]
			normalized[key] = _bounded_number(value.get(key, bounds[2]), float(bounds[0]), float(bounds[1]), key, errors)
		var palette_mode: Variant = value.get("palette_mode", "step")
		if typeof(palette_mode) != TYPE_STRING or palette_mode not in ["step", "smooth"]:
			errors.append("Smoke palette_mode must be step or smooth.")
		normalized["palette_mode"] = palette_mode
	return {"ok": errors.is_empty(), "errors": errors, "value": normalized}


static func _validate_profile_binding(value: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY or not _has_exact_keys(value, PROFILE_BINDING_KEYS):
		errors.append("Presentation profile binding has missing or unsupported fields.")
		return {"ok": false, "errors": errors}
	var family: Variant = value["visual_family"]
	var manifest_hash: Variant = value["model_manifest_sha256"]
	var slots_hash: Variant = value["slots_sha256"]
	if typeof(family) != TYPE_STRING or (not str(family).is_empty() and not _valid_base_id(str(family))):
		errors.append("Presentation visual_family is invalid.")
	if typeof(manifest_hash) != TYPE_STRING or (not str(manifest_hash).is_empty() and not _valid_sha256(str(manifest_hash))):
		errors.append("Presentation model_manifest_sha256 is invalid.")
	if typeof(slots_hash) != TYPE_STRING or (not str(slots_hash).is_empty() and not _valid_sha256(str(slots_hash))):
		errors.append("Presentation slots_sha256 is invalid.")
	var all_empty: bool = str(family).is_empty() and str(manifest_hash).is_empty() and str(slots_hash).is_empty()
	var all_pinned: bool = typeof(family) == TYPE_STRING and _valid_base_id(str(family)) \
		and typeof(manifest_hash) == TYPE_STRING and _valid_sha256(str(manifest_hash)) \
		and typeof(slots_hash) == TYPE_STRING and _valid_sha256(str(slots_hash))
	if not all_empty and not all_pinned:
		errors.append("Presentation binding must contain either all legacy-empty pins or all three valid pins.")
	return {"ok": errors.is_empty(), "errors": errors, "pins": {
		"visual_family": str(family),
		"model_manifest_sha256": str(manifest_hash),
		"slots_sha256": str(slots_hash),
	}}


static func _validate_bindings(value: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("Customization bindings have missing or unsupported fields.")
		return {"ok": false, "errors": errors}
	var checked: Dictionary = value
	var version_value: Variant = checked.get("version", null)
	if checked.get("format", null) != BINDINGS_FORMAT or not _integer_number(version_value) \
			or int(version_value) not in [LEGACY_BINDINGS_VERSION, 2, 3, BINDINGS_VERSION]:
		errors.append("Customization binding format or version is unsupported.")
		return {"ok": false, "errors": errors}
	var binding_version: int = int(version_value)
	var expected_keys: PackedStringArray = BINDINGS_KEYS if binding_version == LEGACY_BINDINGS_VERSION else BINDINGS_V2_KEYS
	if binding_version >= 3:
		expected_keys = expected_keys.duplicate()
		expected_keys.append("source_proof_version")
	if binding_version == 4:
		expected_keys.append("lighting_layout")
	if not _has_exact_keys(checked, expected_keys):
		errors.append("Customization bindings have missing or unsupported fields.")
		return {"ok": false, "errors": errors}
	if typeof(checked["visual_family"]) != TYPE_STRING or not _valid_base_id(str(checked["visual_family"])):
		errors.append("Customization binding visual family is invalid.")
	if typeof(checked["model_manifest_sha256"]) != TYPE_STRING or not _valid_sha256(str(checked["model_manifest_sha256"])):
		errors.append("Customization binding model manifest hash is invalid.")
	if typeof(checked["slots_sha256"]) != TYPE_STRING or not _valid_sha256(str(checked["slots_sha256"])):
		errors.append("Customization slot contract hash is invalid.")
	if binding_version >= 2:
		var proof_version: int = 1
		if binding_version >= 3:
			proof_version = int(checked.source_proof_version) if _integer_number(checked.get("source_proof_version")) else 0
		var source_paths: Array = PresentationSources.paths_for_version(proof_version)
		if binding_version >= 3 and (not _integer_number(checked.get("source_proof_version")) or proof_version not in [2, 3]):
			errors.append("Customization source proof version is unsupported.")
		if checked["presentation_engine_version"] != PRESENTATION_ENGINE_VERSION:
			errors.append("Customization presentation engine version is unsupported.")
		if source_paths.is_empty() or typeof(checked["presentation_sources"]) != TYPE_ARRAY or checked["presentation_sources"].size() != source_paths.size():
			errors.append("Customization presentation source pins are incomplete.")
		else:
			for source_index: int in source_paths.size():
				var source: Variant = checked["presentation_sources"][source_index]
				if typeof(source) != TYPE_DICTIONARY or not _has_exact_keys(source, PackedStringArray(["path", "sha256"])):
					errors.append("Customization presentation source pin has missing or unsupported fields.")
					break
				if source["path"] != source_paths[source_index] or typeof(source["sha256"]) != TYPE_STRING or not _valid_sha256(str(source["sha256"])):
					errors.append("Customization presentation source pins are unknown, unsorted, or invalid.")
					break
	var tree_result: Dictionary = _validate_json_tree(checked, 0, {}, 16, 8192)
	if not bool(tree_result.get("ok", false)):
		errors.append_array(tree_result.get("errors", PackedStringArray()))
	for slot_key: String in ["paint_slots", "marking_slots", "smoke_slots"]:
		if typeof(checked[slot_key]) != TYPE_ARRAY:
			errors.append("Customization %s must be an array." % slot_key)
		elif checked[slot_key].size() > 64:
			errors.append("Customization %s exceeds its 64-slot limit." % slot_key)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	if binding_version == 4:
		var lighting_check := Customization.AircraftLights.validate_authored_layout(checked.lighting_layout)
		if not lighting_check.ok:
			return lighting_check
	var paint_slots: Dictionary = _slot_map(checked["paint_slots"], PAINT_SLOT_KEYS, PAINT_SLOT_OPTIONAL_KEYS, "paint_slots", errors)
	var marking_slots: Dictionary = _slot_map(checked["marking_slots"], MARKING_SLOT_KEYS, [], "marking_slots", errors)
	var smoke_slots: Dictionary = _slot_map(checked["smoke_slots"], SMOKE_SLOT_KEYS, [], "smoke_slots", errors, binding_version)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	if bindings_sha256(checked) != checked["slots_sha256"]:
		errors.append("Customization slot contract hash does not match its authored bindings.")
		return {"ok": false, "errors": errors}
	var pins: Dictionary = {
		"visual_family": checked["visual_family"],
		"model_manifest_sha256": checked["model_manifest_sha256"],
		"slots_sha256": checked["slots_sha256"],
	}
	return {"ok": true, "errors": errors, "available": true, "legacy": false,
		"binding_version": binding_version, "pins": pins, "paint_slots": paint_slots,
		"marking_slots": marking_slots, "smoke_slots": smoke_slots}


static func _slot_map(value: Array, required_keys: PackedStringArray, optional_keys: PackedStringArray,
		field: String, errors: PackedStringArray, binding_version: int = 2) -> Dictionary:
	var result: Dictionary = {}
	if field == "smoke_slots" and binding_version >= 3 and value.size() > MAX_AUTHORED_SMOKE_SLOTS:
		errors.append("Customization supports at most eight authored smoke outlets.")
		return result
	for slot_value: Variant in value:
		if typeof(slot_value) != TYPE_DICTIONARY:
			errors.append("Customization %s contains a non-object slot." % field)
			return result
		var slot: Dictionary = slot_value
		if field == "smoke_slots" and binding_version >= 3:
			var checked_slot: Dictionary = Customization.validate_smoke_slot(slot, 3)
			if not checked_slot.get("ok", false) or result.has(str(slot.get("id", ""))):
				errors.append("Customization smoke outlet is invalid or duplicated: " + str(checked_slot.get("errors", [])))
				return result
			result[str(slot.id)] = slot
			continue
		var expected_keys: PackedStringArray = required_keys.duplicate()
		var allowed_keys: PackedStringArray = required_keys.duplicate()
		if field == "smoke_slots":
			if slot.get("kind", null) == "show":
				expected_keys.append_array(SMOKE_SHOW_SLOT_KEYS)
				allowed_keys.append_array(SMOKE_SHOW_SLOT_KEYS)
			elif slot.get("kind", null) == "source":
				expected_keys.append_array(SMOKE_SOURCE_SLOT_KEYS)
				allowed_keys.append_array(SMOKE_SOURCE_SLOT_KEYS)
			else:
				errors.append("Customization smoke endpoint kind is unsupported.")
				return result
		else:
			for optional_key: String in optional_keys:
				if slot.has(optional_key):
					expected_keys.append(optional_key)
					allowed_keys.append(optional_key)
		if slot.size() != expected_keys.size() or not slot.has_all(expected_keys):
			errors.append("Customization %s slot has missing or unsupported fields." % field)
			return result
		for key: Variant in slot.keys():
			if typeof(key) != TYPE_STRING or not allowed_keys.has(str(key)):
				errors.append("Customization %s slot has missing or unsupported fields." % field)
				return result
		var id_value: Variant = slot.get("id", null)
		var label_value: Variant = slot.get("label", null)
		if typeof(id_value) != TYPE_STRING or not _valid_slot_id(str(id_value)):
			errors.append("Customization %s contains an invalid slot ID." % field)
			return result
		if typeof(label_value) != TYPE_STRING or not _valid_label(str(label_value)):
			errors.append("Customization %s contains an invalid label." % field)
			return result
		if result.has(str(id_value)):
			errors.append("Customization %s contains a duplicate slot ID." % field)
			return result
		if field == "paint_slots":
			if not _validate_paint_targets(slot.get("targets", null), errors):
				return result
			if slot.has("accent_targets") and not _validate_paint_targets(slot["accent_targets"], errors):
				return result
		elif field == "marking_slots":
			if not _integer_number(slot.get("max_chars", null)) or int(slot["max_chars"]) < 1 or int(slot["max_chars"]) > MAX_TEXT_LENGTH:
				errors.append("Customization marking max_chars must be an integer from 1 through %d." % MAX_TEXT_LENGTH)
				return result
			if not _validate_marking_targets(slot.get("targets", null), errors):
				return result
		else:
			if slot["kind"] not in ["show", "source"] or typeof(slot["pair"]) != TYPE_STRING \
					or (not str(slot["pair"]).is_empty() and not _valid_slot_id(str(slot["pair"]))) \
					or typeof(slot["role"]) != TYPE_STRING \
					or not ["wing_tip_left", "wing_tip_right", "tail", "tailpipe", "exhaust"].has(str(slot["role"])):
				errors.append("Customization smoke endpoint kind, pair, or role is invalid.")
				return result
			if slot["kind"] == "show":
				if str(slot["role"]) == "tailpipe" and not str(slot["pair"]).is_empty():
					errors.append("Customization tailpipe show endpoint must be unpaired.")
					return result
				if (str(slot["node_path"]) != "." and not _safe_node_path(slot["node_path"])) \
						or typeof(slot["position_m"]) != TYPE_ARRAY \
						or slot["position_m"].size() != 3 or typeof(slot["direction"]) != TYPE_ARRAY \
						or slot["direction"].size() != 3:
					errors.append("Customization show endpoint pose must use an authored node path and bounded triples.")
					return result
				var pose_errors := PackedStringArray()
				for coordinate: Variant in slot["position_m"]:
					_bounded_number(coordinate, -100.0, 100.0, "smoke position_m", pose_errors)
				for coordinate: Variant in slot["direction"]:
					_bounded_number(coordinate, -1.0, 1.0, "smoke direction", pose_errors)
				if not pose_errors.is_empty():
					errors.append_array(pose_errors)
					return result
			else:
				for selector_key: String in SMOKE_SOURCE_SLOT_KEYS:
					if typeof(slot[selector_key]) != TYPE_STRING or str(slot[selector_key]).is_empty() \
							or str(slot[selector_key]).length() > 128:
						errors.append("Customization smoke source selector is invalid.")
						return result
		result[str(id_value)] = slot
	return result


static func _validate_paint_targets(value: Variant, errors: PackedStringArray) -> bool:
	if typeof(value) != TYPE_ARRAY or value.is_empty() or value.size() > 64:
		errors.append("Paint binding targets must contain 1–64 authored material regions.")
		return false
	for target_value: Variant in value:
		if typeof(target_value) != TYPE_DICTIONARY:
			errors.append("Paint target has missing or unsupported fields.")
			return false
		var target: Dictionary = target_value
		var expected_count: int = PAINT_TARGET_KEYS.size() + (1 if target.has("parameter") else 0)
		if target.size() != expected_count or not target.has_all(PAINT_TARGET_KEYS):
			errors.append("Paint target has missing or unsupported fields.")
			return false
		for key: Variant in target.keys():
			if typeof(key) != TYPE_STRING or (not PAINT_TARGET_KEYS.has(str(key)) \
					and not PAINT_TARGET_OPTIONAL_KEYS.has(str(key))):
				errors.append("Paint target has missing or unsupported fields.")
				return false
		if not _safe_node_path(target["node_path"]) or not _integer_number(target["surface"]) \
				or int(target["surface"]) < 0 or target["kind"] not in ["standard_albedo", "shader_color"]:
			errors.append("Paint target path, surface, or material kind is invalid.")
			return false
		if (target["kind"] == "shader_color") != target.has("parameter"):
			errors.append("Shader paint targets require a parameter; standard albedo targets forbid one.")
			return false
		if target.has("parameter") and (typeof(target["parameter"]) != TYPE_STRING \
				or str(target["parameter"]).is_empty() or str(target["parameter"]).length() > 64):
			errors.append("Paint shader parameter binding is invalid.")
			return false
	return true


static func _validate_marking_targets(value: Variant, errors: PackedStringArray) -> bool:
	if typeof(value) != TYPE_ARRAY or value.is_empty() or value.size() > 2:
		errors.append("Marking binding targets must contain 1–2 fixed authored label mounts.")
		return false
	for target_value: Variant in value:
		if typeof(target_value) != TYPE_DICTIONARY or not _has_exact_keys(target_value, MARKING_TARGET_KEYS):
			errors.append("Marking target has missing or unsupported fields.")
			return false
		var target: Dictionary = target_value
		if not _safe_node_path(target["node_path"]):
			errors.append("Marking target node path must identify a registered local mount.")
			return false
		for vector_key: String in ["position_m", "direction", "up"]:
			var vector_value: Variant = target[vector_key]
			if typeof(vector_value) != TYPE_ARRAY or vector_value.size() != 3:
				errors.append("Marking target %s must be an authored three-number vector." % vector_key)
				return false
			var lower: float = -100.0 if vector_key == "position_m" else -1.0
			var upper: float = 100.0 if vector_key == "position_m" else 1.0
			for coordinate: Variant in vector_value:
				_bounded_number(coordinate, lower, upper, "marking %s" % vector_key, errors)
		var width: float = _bounded_number(target["width_m"], 0.01, 10.0, "marking width_m", errors)
		var height: float = _bounded_number(target["height_m"], 0.01, 10.0, "marking height_m", errors)
		if width <= 0.0 or height <= 0.0 or not errors.is_empty():
			return false
		var direction: Array = target["direction"]
		var up: Array = target["up"]
		var direction_length: float = 0.0
		var up_length: float = 0.0
		var cross := [
			float(direction[1]) * float(up[2]) - float(direction[2]) * float(up[1]),
			float(direction[2]) * float(up[0]) - float(direction[0]) * float(up[2]),
			float(direction[0]) * float(up[1]) - float(direction[1]) * float(up[0]),
		]
		for axis: int in 3:
			direction_length += float(direction[axis]) * float(direction[axis])
			up_length += float(up[axis]) * float(up[axis])
		if direction_length <= 1.0e-8 or up_length <= 1.0e-8 \
				or cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2] <= 1.0e-8:
			errors.append("Marking target direction and up vectors must be nonzero and nonparallel.")
			return false
	return true


static func _canonical_color(value: Variant, opaque_only: bool = false) -> Dictionary:
	if typeof(value) != TYPE_STRING:
		return {"ok": false, "value": ""}
	var swatch: String = str(value)
	if not swatch.begins_with("#") or (swatch.length() != 7 and swatch.length() != 9):
		return {"ok": false, "value": ""}
	var canonical: String = "#"
	for index: int in range(1, swatch.length()):
		var code: int = swatch.unicode_at(index)
		var upper: int = code
		if code >= 97 and code <= 102:
			upper = code - 32
		var character: String = String.chr(upper)
		if not HEX_DIGITS.contains(character):
			return {"ok": false, "value": ""}
		canonical += character
	if canonical.length() == 7:
		canonical += "FF"
	if opaque_only and canonical.substr(7, 2) != "FF":
		return {"ok": false, "value": ""}
	return {"ok": true, "value": canonical}


static func _valid_marking_text(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_TEXT_LENGTH or value != value.strip_edges():
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		var allowed: bool = (code >= 48 and code <= 57) or (code >= 65 and code <= 90) \
			or (code >= 97 and code <= 122) or code == 32 or code == 45 \
			or code in [193, 201, 205, 211, 218, 220, 209, 225, 233, 237, 243, 250, 252, 241]
		if not allowed:
			return false
	return true


static func _valid_label(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_LABEL_LENGTH:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if code < 32 or code > 126:
			return false
	return true


static func _valid_slot_id(value: String) -> bool:
	if value.is_empty() or value.length() > 80:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		var letter: bool = code >= 97 and code <= 122
		var digit: bool = code >= 48 and code <= 57
		if index == 0 and not letter:
			return false
		if not letter and not digit and code != 95:
			return false
	return true


static func _safe_node_path(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var path: String = str(value)
	if path.is_empty() or path.length() > 256 or path.begins_with("/") or path.contains("..") \
			or path.contains(":") or path.contains("\\"):
		return false
	for segment: String in path.split("/", false):
		if segment.is_empty() or segment == ".":
			return false
	return true


static func _bounded_number(value: Variant, minimum: float, maximum: float, name: String,
		errors: PackedStringArray) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		errors.append("Presentation %s must be a finite number." % name)
		return 0.0
	var number: float = float(value)
	if not is_finite(number) or number < minimum or number > maximum:
		errors.append("Presentation %s must be between %s and %s." % [name, minimum, maximum])
		return 0.0
	return number


static func _integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	var number: float = float(value)
	return floor(number) == number and abs(number) <= MAX_SAFE_INTEGER


static func _pins_are_empty(value: Dictionary) -> bool:
	return str(value.get("visual_family", "")).is_empty() \
		and str(value.get("model_manifest_sha256", "")).is_empty() \
		and str(value.get("slots_sha256", "")).is_empty()


static func _has_entries(profile: Dictionary) -> bool:
	if profile.has("mechanical_audio") and (not profile.mechanical_audio is Dictionary or profile.mechanical_audio != MechanicalProfile.defaults()):
		return true
	if typeof(profile.get("lighting")) == TYPE_DICTIONARY and profile.lighting.get("selection", "inherit") != "inherit":
		return true
	for key: String in ["paint", "markings", "smoke"]:
		if typeof(profile.get(key, null)) == TYPE_ARRAY and not (profile[key] as Array).is_empty():
			return true
	return int(profile.get("visual_seed", 0)) != 0


static func _valid_base_id(value: String) -> bool:
	if value.is_empty() or value.length() > 128:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		var valid: bool = (code >= 48 and code <= 57) or (code >= 97 and code <= 122) \
			or code == 45 or code == 95 or code == 46
		if index == 0 and not ((code >= 48 and code <= 57) or (code >= 97 and code <= 122)):
			return false
		if not valid:
			return false
	return true


static func _valid_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _has_exact_keys(value: Dictionary, expected: PackedStringArray) -> bool:
	if value.size() != expected.size() or not value.has_all(expected):
		return false
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING or not expected.has(str(key)):
			return false
	return true


static func _validate_json_tree(value: Variant, depth: int = 0, budget: Dictionary = {},
		max_depth: int = MAX_PROFILE_DEPTH, max_nodes: int = MAX_PROFILE_NODES) -> Dictionary:
	var errors := PackedStringArray()
	if budget.is_empty():
		budget["remaining"] = max_nodes
	if depth > max_depth:
		errors.append("Presentation JSON exceeds the maximum nesting depth.")
		return {"ok": false, "errors": errors}
	budget["remaining"] = int(budget["remaining"]) - 1
	if int(budget["remaining"]) < 0:
		errors.append("Presentation JSON exceeds the maximum node count.")
		return {"ok": false, "errors": errors}
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return {"ok": true, "errors": errors}
		TYPE_FLOAT:
			if not is_finite(float(value)):
				errors.append("Presentation JSON contains a non-finite number.")
		TYPE_ARRAY:
			for item: Variant in value:
				var nested: Dictionary = _validate_json_tree(item, depth + 1, budget, max_depth, max_nodes)
				if not bool(nested.get("ok", false)):
					errors.append_array(nested.get("errors", PackedStringArray()))
					break
		TYPE_DICTIONARY:
			for key: Variant in value.keys():
				if typeof(key) != TYPE_STRING:
					errors.append("Presentation JSON object keys must be strings.")
					break
				var nested: Dictionary = _validate_json_tree(value[key], depth + 1, budget, max_depth, max_nodes)
				if not bool(nested.get("ok", false)):
					errors.append_array(nested.get("errors", PackedStringArray()))
					break
		_:
			errors.append("Presentation JSON contains a non-JSON value.")
	return {"ok": errors.is_empty(), "errors": errors}


static func _canonical_json(value: Variant) -> String:
	return JSON.stringify(_canonical_value(value), "", true, true)


static func _canonical_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var number: float = float(value)
			if floor(number) == number and abs(number) <= MAX_SAFE_INTEGER:
				return int(number)
			return number
		TYPE_ARRAY:
			var result: Array = []
			for item: Variant in value:
				result.append(_canonical_value(item))
			return result
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			var keys: Array = value.keys()
			keys.sort()
			for key: Variant in keys:
				result[key] = _canonical_value(value[key])
			return result
	return value


static func _identity_sha256(profile: Dictionary, binding_version: int) -> String:
	var material: Dictionary = {
		"format": IDENTITY_FORMAT,
		"version": IDENTITY_VERSION,
		"profile_format": FORMAT,
		"profile_version": int(profile.get("version", LEGACY_VERSION)),
		"binding_format": BINDINGS_FORMAT,
		"binding_version": binding_version,
		"binding": profile["binding"],
		"profile": profile,
		"visual_seed": profile["visual_seed"],
		"schedule_policy": profile["schedule_policy"],
	}
	return _sha256(_canonical_json(material).to_utf8_buffer())


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


static func _result(ok: bool, errors: PackedStringArray, profile: Dictionary = {},
		available: bool = false, identity_sha256: String = "") -> Dictionary:
	return {"ok": ok, "errors": errors, "profile": profile, "available": available,
		"identity_sha256": identity_sha256}
