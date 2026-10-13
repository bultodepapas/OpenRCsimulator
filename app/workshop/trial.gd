## AE-10: freeze a detached recipe and its exact source for one reproducible trial.
extends RefCounted


static func freeze(payload: Dictionary) -> Dictionary:
	if not payload.get("base_bytes") is PackedByteArray or not payload.get("recipe", {}) is Dictionary:
		return {ok = false, errors = PackedStringArray(["Workshop source and recipe have invalid types."])}
	var base_bytes: PackedByteArray = payload.get("base_bytes", PackedByteArray())
	var parser := JSON.new()
	if base_bytes.is_empty() or parser.parse(base_bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {ok = false, errors = PackedStringArray(["Workshop source is missing or invalid."])}
	var base: Dictionary = parser.data
	var base_id: String = str(payload.get("base_id", ""))
	if str(base.get("id", "")) != base_id:
		return {ok = false, errors = PackedStringArray(["Workshop source does not match the selected aircraft."])}
	var descriptor_loader: Script = load("res://workshop/descriptor.gd")
	var supplied_descriptor: Variant = payload.get("workshop_descriptor", {})
	var descriptor_result: Dictionary
	if supplied_descriptor is Dictionary and supplied_descriptor.is_empty():
		descriptor_result = descriptor_loader.load_for(base_id, base_bytes)
	else:
		descriptor_result = descriptor_loader.validate(supplied_descriptor, base_id, base_bytes)
	if not descriptor_result.get("ok", false):
		return descriptor_result
	var descriptor_sha: String = _sha(JSON.stringify(descriptor_result.descriptor, "", true, true).to_utf8_buffer())
	var compiler: Script = load("res://workshop/compiler.gd")
	var recipe: Dictionary = compiler.defaults()
	recipe.merge(payload.get("recipe", {}), true)
	var ancestor_id: String = str(recipe.get("id", ""))
	recipe.erase("id")
	recipe.erase("name")
	var base_sha: String = _sha(base_bytes)
	var recipe_sha: String = _sha(JSON.stringify(recipe, "", true, true).to_utf8_buffer())
	var trial_id: String = "workshop-" + _sha((base_sha + ":" + recipe_sha + ":" + descriptor_sha + ":workshop-compiler-v1").to_utf8_buffer()).substr(0, 32)
	recipe.id = trial_id
	var result: Dictionary = compiler.compile(base, recipe)
	if not result.get("ok", false):
		return result
	var resolved_bytes: PackedByteArray = JSON.stringify(result.raw, "", true, true).to_utf8_buffer()
	var resolved_sha: String = _sha(resolved_bytes)
	result.data.input_identity = {format = "openrc-aircraft v2", sha256 = resolved_sha}
	var model_sha: String = _sha(var_to_bytes(result.data.model))
	return {ok = true, errors = PackedStringArray(), data = result.data.duplicate(true),
		scale = float(recipe.get("scale", 1.0)), raw_bytes = resolved_bytes,
		identity = {format = "openrc-aircraft-trial v1", trial_id = trial_id, base_id = base_id,
			base_sha256 = base_sha, recipe_sha256 = recipe_sha, resolved_sha256 = resolved_sha,
			resolved_model_sha256 = model_sha,
			descriptor_sha256 = descriptor_sha,
			ancestor_variant_id = ancestor_id, compiler = "workshop-compiler-v1", experimental = true}}


static func _sha(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()
