## BL-19b: Workshop family adapter for `openrc-airship v1` bases. The shared descriptor, dependency and compiler
## entry points delegate here when the pinned base is an airship, so the fixed-wing paths stay byte-identical.
##
## The airship descriptor is derived from the exact base bytes and the verified presentation, never authored or
## generated: {format, base_id, base_sha256, presentation {visual_family, model_manifest_sha256}}. An airship has
## no wheel-profile or glow dependencies; its dependency manifest is an explicit empty file set.
extends RefCounted

const Compiler := preload("res://workshop/airship_compiler.gd")
const Catalog := preload("res://vehicles/airship/airship_catalog.gd")

const DESCRIPTOR_FORMAT := "openrc-airship-workshop v1"
const DEPENDENCIES_FORMAT := "openrc-airship-workshop-dependencies v1"
const TRIAL_FORMAT := "openrc-airship-trial v1"
const PRESENTATION_SCRIPT := "res://vehicles/airship/airship_presentation.gd"
const DESCRIPTOR_KEYS := ["format", "base_id", "base_sha256", "presentation"]


static func is_base(base: Dictionary) -> bool:
	return Compiler.is_family(base)


static func is_descriptor(value: Variant) -> bool:
	return value is Dictionary and value.get("format", "") == DESCRIPTOR_FORMAT


## Cheap check on raw base bytes (format string near the start of a generated airship file).
static func is_base_bytes(bytes: PackedByteArray) -> bool:
	if bytes.is_empty():
		return false
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	return parsed is Dictionary and is_base(parsed)


## Verified presentation of the blimp's visual family: {ok, visual_family, model_manifest_sha256, bindings,
## slots_sha256, errors}. Uses the presentation module when present; otherwise the default skin GLB hash with no
## customization slots (Appearance/Lighting then report unavailable).
static func presentation(skin_id := "") -> Dictionary:
	if ResourceLoader.exists(PRESENTATION_SCRIPT):
		var script: Script = load(PRESENTATION_SCRIPT)
		if script != null and script.has_method("describe"):
			return script.call("describe", skin_id)
	var model: String = str(Catalog.SKINS[Catalog.DEFAULT_SKIN].model)
	var bytes := FileAccess.get_file_as_bytes(model)
	if bytes.is_empty():
		return {ok = false, errors = PackedStringArray(["Blimp model is unavailable: " + model])}
	return {ok = true, visual_family = Catalog.VISUAL_FAMILY, model_manifest_sha256 = _sha(bytes), bindings = {},
		slots_sha256 = "", errors = PackedStringArray()}


static func descriptor_for(base_id: String, base_bytes: PackedByteArray) -> Dictionary:
	var base: Variant = JSON.parse_string(base_bytes.get_string_from_utf8())
	if not base is Dictionary or not is_base(base) or str(base.get("id", "")) != base_id:
		return _failure("Workshop airship base is missing or does not match the selected blimp.")
	var shown := presentation()
	if not shown.get("ok", false):
		return {ok = false, errors = shown.get("errors", PackedStringArray(["Blimp presentation is unavailable."]))}
	return {ok = true, errors = PackedStringArray(), descriptor = {format = DESCRIPTOR_FORMAT, base_id = base_id,
		base_sha256 = _sha(base_bytes), presentation = {visual_family = str(shown.visual_family),
			model_manifest_sha256 = str(shown.model_manifest_sha256)}}}


static func validate_descriptor(value: Variant, base_id: String, base_bytes: PackedByteArray) -> Dictionary:
	if not is_descriptor(value):
		return _failure("Workshop airship descriptor has an unsupported format.")
	var descriptor: Dictionary = value
	var keys: Array = descriptor.keys()
	keys.sort()
	var expected: Array = DESCRIPTOR_KEYS.duplicate()
	expected.sort()
	if keys != expected or not descriptor.presentation is Dictionary \
			or descriptor.presentation.keys().size() != 2 or not descriptor.presentation.has_all(["visual_family", "model_manifest_sha256"]):
		return _failure("Workshop airship descriptor has unexpected fields.")
	if str(descriptor.base_id) != base_id or str(descriptor.base_sha256) != _sha(base_bytes):
		return _failure("Workshop airship descriptor does not match the exact base snapshot.")
	if str(descriptor.presentation.visual_family) != Catalog.VISUAL_FAMILY:
		return _failure("Workshop airship descriptor names an unknown visual family.")
	return {ok = true, errors = PackedStringArray(), descriptor = descriptor.duplicate(true)}


## Mirrors WorkshopDescriptor.verify_presentation: the current model must still hash to the pinned one.
static func verify_presentation(descriptor: Dictionary) -> Dictionary:
	var shown := presentation()
	if not shown.get("ok", false):
		return {ok = false, errors = shown.get("errors", PackedStringArray(["Blimp presentation is unavailable."]))}
	if str(descriptor.get("presentation", {}).get("model_manifest_sha256", "")) != str(shown.model_manifest_sha256):
		return _failure("The blimp model or its presentation bindings changed after this build was pinned.")
	return {ok = true, errors = PackedStringArray(), manifest = {family_id = str(shown.visual_family)},
		manifest_sha256 = str(shown.model_manifest_sha256)}


static func capture_dependencies(_base: Dictionary) -> Dictionary:
	return {ok = true, errors = PackedStringArray(), manifest = {format = DEPENDENCIES_FORMAT, files = {}}}


static func validate_dependencies(_base: Dictionary, value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("format", "") != DEPENDENCIES_FORMAT or value.keys().size() != 2 \
			or not value.get("files") is Dictionary or not (value.files as Dictionary).is_empty():
		return _failure("Workshop airship dependencies must be the explicit empty manifest.")
	return {ok = true, errors = PackedStringArray(), manifest = (value as Dictionary).duplicate(true)}


static func _sha(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


static func _failure(message: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([message])}
