## AE-10: freeze a detached recipe and its exact source for one reproducible trial.
extends RefCounted


static func freeze(payload: Dictionary) -> Dictionary:
	var base_bytes_value: Variant = payload.get("base_bytes", null)
	var base_id_value: Variant = payload.get("base_id", null)
	var recipe_value: Variant = payload.get("recipe", {})
	if typeof(base_bytes_value) != TYPE_PACKED_BYTE_ARRAY or typeof(base_id_value) != TYPE_STRING \
			or typeof(recipe_value) != TYPE_DICTIONARY:
		return {ok = false, errors = PackedStringArray(["Workshop source ID, source bytes, or recipe have invalid types."])}
	var parameters: Script = load("res://workshop/parameters.gd")
	var checked_recipe: Dictionary = parameters.validate(recipe_value)
	if not checked_recipe.ok:
		return {ok = false, errors = checked_recipe.errors}
	var base_bytes: PackedByteArray = base_bytes_value
	var base_id: String = base_id_value
	var descriptor_loader: Script = load("res://workshop/descriptor.gd")
	if base_bytes.size() > descriptor_loader.MAX_BASE_BYTES:
		return {ok = false, errors = PackedStringArray(["Workshop source exceeds the snapshot size limit."])}
	var parser := JSON.new()
	var base_text: String = base_bytes.get_string_from_utf8()
	if base_bytes.is_empty() or base_text.to_utf8_buffer() != base_bytes \
			or parser.parse(base_text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {ok = false, errors = PackedStringArray(["Workshop source is missing or invalid."])}
	var base: Dictionary = parser.data
	var source_id: Variant = base.get("id", null)
	if typeof(source_id) != TYPE_STRING or source_id != base_id:
		return {ok = false, errors = PackedStringArray(["Workshop source does not match the selected aircraft."])}
	var supplied_descriptor: Variant = payload.get("workshop_descriptor", {})
	var descriptor_result: Dictionary
	if supplied_descriptor is Dictionary and supplied_descriptor.is_empty():
		descriptor_result = descriptor_loader.load_for(base_id, base_bytes)
	else:
		descriptor_result = descriptor_loader.validate(supplied_descriptor, base_id, base_bytes)
	if not descriptor_result.get("ok", false):
		return descriptor_result
	var presentation: Dictionary = descriptor_loader.verify_presentation(descriptor_result.descriptor)
	if not presentation.get("ok", false):
		return presentation
	var descriptor_sha: String = _sha(JSON.stringify(descriptor_result.descriptor, "", true, true).to_utf8_buffer())
	var dependency_loader: Script = load("res://workshop/dependencies.gd")
	var supplied_dependencies: Variant = payload.get("dependencies", {})
	var dependency_result: Dictionary
	if supplied_dependencies is Dictionary and supplied_dependencies.is_empty():
		dependency_result = dependency_loader.capture(base)
	else:
		dependency_result = dependency_loader.verify(base, supplied_dependencies)
	if not dependency_result.get("ok", false):
		return dependency_result
	var dependencies: Dictionary = dependency_result.manifest
	var dependency_sha: String = _sha(JSON.stringify(dependencies, "", true, true).to_utf8_buffer())
	var compiler: Script = load("res://workshop/compiler.gd")
	var pinned_compiler_value: Variant = payload.get("compiler_version", "")
	if typeof(pinned_compiler_value) != TYPE_STRING:
		return {ok = false, errors = PackedStringArray(["Saved variant compiler version must be a string."])}
	var pinned_compiler: String = pinned_compiler_value
	if not pinned_compiler.is_empty() and pinned_compiler != compiler.COMPILER_VERSION:
		return {ok = false, errors = PackedStringArray(["This saved variant requires a different Workshop compiler version; the saved variant remains unchanged."])}
	# Hash the same normalized numeric values the compiler consumes (1 == 1.0).
	var recipe: Dictionary = checked_recipe.values
	var recipe_ancestor_id: Variant = recipe.get("id", "")
	var ancestor_id_value: Variant = payload.get("variant_id", recipe_ancestor_id)
	var ancestor_revision_value: Variant = payload.get("variant_revision", 0)
	if typeof(ancestor_id_value) != TYPE_STRING or typeof(ancestor_revision_value) != TYPE_INT:
		return {ok = false, errors = PackedStringArray(["Saved variant ancestry has invalid ID or revision types."])}
	var ancestor_id: String = ancestor_id_value
	var ancestor_revision: int = ancestor_revision_value
	if recipe.has("id") and recipe.id != ancestor_id:
		return {ok = false, errors = PackedStringArray(["Recipe ID and saved variant ancestry disagree."])}
	if (ancestor_id.is_empty() and ancestor_revision != 0) or (not ancestor_id.is_empty() and ancestor_revision < 1):
		return {ok = false, errors = PackedStringArray(["Saved variant ancestry requires a matching ID and positive revision."])}
	if not ancestor_id.is_empty() and (pinned_compiler.is_empty() or supplied_dependencies.is_empty() or supplied_descriptor.is_empty()):
		return {ok = false, errors = PackedStringArray(["Saved variant provenance is incomplete; reload it from the Workshop library."])}
	recipe.erase("id")
	recipe.erase("name")
	var base_sha: String = _sha(base_bytes)
	var recipe_sha: String = _sha(JSON.stringify(recipe, "", true, true).to_utf8_buffer())
	var compiler_version: String = compiler.COMPILER_VERSION
	var visual_family: String = presentation.manifest.family_id
	var model_manifest_sha: String = presentation.manifest_sha256
	var trial_id: String = "workshop-" + _sha((base_sha + ":" + recipe_sha + ":" + descriptor_sha \
		+ ":" + visual_family + ":" + model_manifest_sha + ":" + dependency_sha + ":" + compiler_version).to_utf8_buffer()).substr(0, 32)
	recipe.id = trial_id
	var result: Dictionary = compiler.compile(base, recipe)
	if not result.get("ok", false):
		return result
	# Detect a dependency replacement while compiling, before any live flight can be touched.
	var unchanged: Dictionary = dependency_loader.verify(base, dependencies)
	if not unchanged.get("ok", false):
		return unchanged
	var model_unchanged: Dictionary = descriptor_loader.verify_presentation(descriptor_result.descriptor)
	if not model_unchanged.get("ok", false):
		return model_unchanged
	if model_unchanged.manifest_sha256 != model_manifest_sha:
		return {ok = false, errors = PackedStringArray(["Model presentation changed while compiling the trial."])}
	var presentation_binding: Dictionary = {visual_family = visual_family,
		model_manifest_sha256 = model_manifest_sha}
	var resolved_bytes: PackedByteArray = JSON.stringify(result.raw, "", true, true).to_utf8_buffer()
	var resolved_sha: String = _sha(resolved_bytes)
	result.data.input_identity = {format = "openrc-aircraft v2", sha256 = resolved_sha}
	var model_sha: String = _sha(var_to_bytes(result.data.model))
	return {ok = true, errors = PackedStringArray(), data = result.data.duplicate(true),
		scale = float(recipe.get("scale", 1.0)), raw_bytes = resolved_bytes, presentation = presentation_binding.duplicate(true),
		identity = {format = "openrc-aircraft-trial v1", trial_id = trial_id, base_id = base_id,
			base_sha256 = base_sha, recipe_sha256 = recipe_sha, resolved_sha256 = resolved_sha,
			resolved_model_sha256 = model_sha,
			descriptor_sha256 = descriptor_sha, presentation = presentation_binding.duplicate(true),
			dependencies = dependencies.duplicate(true), dependencies_sha256 = dependency_sha,
			ancestor_variant_id = ancestor_id, ancestor_revision = ancestor_revision,
			compiler = compiler_version, experimental = true}}


static func _sha(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()
