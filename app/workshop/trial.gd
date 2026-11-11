## AE-10: freeze a detached recipe and its exact source for one reproducible trial.
extends RefCounted

const ModelRegistry := preload("res://aircraft/model_registry.gd")
const Store := preload("res://workshop/store.gd")
const AirshipFamily := preload("res://workshop/airship_family.gd")

static func freeze(payload: Dictionary) -> Dictionary:
	if payload.has("battery_mode") and (typeof(payload.battery_mode) != TYPE_STRING or payload.battery_mode != "ideal"):
		return {ok = false, errors = PackedStringArray(["Workshop battery selection supports ideal fixed voltage only; finite-pack trials are not supported."])}
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
	var visual_family: String = str(presentation.manifest.family_id)
	var model_manifest_sha: String = str(presentation.manifest_sha256)
	var profile_script: Script = load("res://workshop/presentation.gd")
	var profile_value: Variant = payload.get("presentation_profile", {})
	if typeof(profile_value) != TYPE_DICTIONARY:
		return {ok = false, errors = PackedStringArray(["Workshop presentation profile must be an object."])}
	var customization_script: Script = load("res://render/aircraft_customization.gd") \
		if ResourceLoader.exists("res://render/aircraft_customization.gd") else null
	if customization_script == null and ModelRegistry.OVERLAY_FAMILIES.has(base_id):
		return {ok = false, errors = PackedStringArray(["Overlay customization dependency is unavailable."])}
	var customization: Dictionary = {}
	var presentation_bindings: Dictionary = {}
	var airship: bool = AirshipFamily.is_base(base)
	if airship:
		# BL-19b: the blimp's companion comes from its own presentation module.
		customization = AirshipFamily.customization()
	elif customization_script != null:
		if ModelRegistry.OVERLAY_FAMILIES.has(base_id):
			var overlay_path := "res://aircraft/customization_overlay.gd"
			if not ResourceLoader.exists(overlay_path):
				return {ok = false, errors = PackedStringArray(["Overlay customization resolver is unavailable."])}
			var overlay: Script = load(overlay_path)
			if overlay == null or not overlay.has_method("describe"):
				return {ok = false, errors = PackedStringArray(["Overlay customization resolver cannot be loaded."])}
			customization = overlay.describe(base_id)
		else:
			customization = customization_script.describe(base_id)
	var checked_profile: Dictionary
	if bool(customization.get("ok", false)) and typeof(customization.get("bindings", null)) == TYPE_DICTIONARY:
		var bindings: Dictionary = customization["bindings"]
		presentation_bindings = bindings
		if str(bindings.get("visual_family", "")) != visual_family \
				or str(bindings.get("model_manifest_sha256", "")) != model_manifest_sha:
			return {ok = false, errors = PackedStringArray(["Customization companion is stale relative to the frozen physical model manifest."])}
		checked_profile = profile_script.validate(profile_value, bindings)
		if bool(checked_profile.get("ok", false)) and not bool(checked_profile.get("available", false)):
			return {ok = false, errors = PackedStringArray(["Presentation profile is unavailable for the current aircraft binding."])}
	else:
		if ModelRegistry.OVERLAY_FAMILIES.has(base_id):
			return {ok = false, errors = customization.get("errors", PackedStringArray(["Overlay customization is invalid."]))}
		checked_profile = profile_script.validate(profile_value)
		if bool(checked_profile.get("ok", false)):
			var normalized_profile: Dictionary = checked_profile.get("profile", {})
			var profile_binding: Dictionary = normalized_profile.get("binding", {})
			var is_unbound_legacy: bool = profile_binding.get("visual_family", "") == "" \
				and profile_binding.get("model_manifest_sha256", "") == "" \
				and profile_binding.get("slots_sha256", "") == "" \
				and (normalized_profile.get("paint", []) as Array).is_empty() \
				and (normalized_profile.get("markings", []) as Array).is_empty() \
				and (normalized_profile.get("smoke", []) as Array).is_empty() \
					and normalized_profile.get("lighting", {}).get("selection", "inherit") == "inherit" \
				and normalized_profile.get("mechanical_audio", profile_script.MechanicalProfile.defaults()) == profile_script.MechanicalProfile.defaults() \
				and int(normalized_profile.get("visual_seed", 0)) == 0
			if not is_unbound_legacy:
				return {ok = false, errors = PackedStringArray(["The current customization companion is required to resolve this pinned presentation profile."])}
	if not bool(checked_profile.get("ok", false)):
		return checked_profile
	var normalized_profile: Dictionary = checked_profile["profile"]
	var presentation_identity: Dictionary = profile_script.identity_record(normalized_profile, presentation_bindings)
	if presentation_identity.is_empty():
		return {ok = false, errors = PackedStringArray(["Presentation identity could not be constructed from the frozen profile."])}
	presentation_identity["sha256"] = str(checked_profile.get("identity_sha256", ""))
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
	if not pinned_compiler.is_empty() and pinned_compiler != compiler.version_for(base, checked_recipe.values):
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
	var display_result := _display_context(payload, ancestor_id, ancestor_revision)
	if not display_result.ok:
		return display_result
	recipe.erase("id")
	recipe.erase("name")
	if airship:
		# The buoyant family ignores these fixed-wing size options; they must not change the physical identity.
		recipe.erase("mass_policy")
		recipe.erase("size_model")
	var base_sha: String = _sha(base_bytes)
	var recipe_sha: String = _sha(JSON.stringify(recipe, "", true, true).to_utf8_buffer())
	var compiler_version: String = compiler.version_for(base, recipe)
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
	result.data.input_identity = {format = str(base.get("format", "openrc-aircraft v2")), sha256 = resolved_sha}
	var model_sha: String = _sha(var_to_bytes(result.data.model))
	var frozen := {ok = true, errors = PackedStringArray(), data = result.data.duplicate(true),
		scale = float(recipe.get("scale", 1.0)), raw_bytes = resolved_bytes, presentation = presentation_binding.duplicate(true),
		presentation_profile = normalized_profile.duplicate(true),
		presentation_identity = presentation_identity.duplicate(true),
		vehicle = "airship" if airship else "airplane",
		identity = {format = AirshipFamily.TRIAL_FORMAT if airship else "openrc-aircraft-trial v1", trial_id = trial_id, base_id = base_id,
			base_sha256 = base_sha, recipe_sha256 = recipe_sha, resolved_sha256 = resolved_sha,
			resolved_model_sha256 = model_sha,
			descriptor_sha256 = descriptor_sha, presentation = presentation_binding.duplicate(true),
			dependencies = dependencies.duplicate(true), dependencies_sha256 = dependency_sha,
			ancestor_variant_id = ancestor_id, ancestor_revision = ancestor_revision,
			compiler = compiler_version, experimental = true}}
	if not display_result.context.is_empty():
		# UI-only context must not participate in the physical or trace identity.
		frozen["display_context"] = display_result.context.duplicate(true)
	return frozen


## An editor-supplied baseline is compared against every persisted build field,
## including presentation and name. An ancestor ID alone never means "saved".
static func _display_context(payload: Dictionary, ancestor_id: String, revision: int) -> Dictionary:
	if not payload.has("display_input"):
		return {ok = true, context = {}}
	var input: Variant = payload.display_input
	if not input is Dictionary or input.size() != 3 or typeof(input.get("name")) != TYPE_STRING \
			or typeof(input.get("baseline")) != TYPE_DICTIONARY or typeof(input.get("requires_copy")) != TYPE_BOOL:
		return _invalid_display_context()
	var name: String = input.name
	if not _valid_display_name(name, true):
		return _invalid_display_context()
	var baseline: Dictionary = input.baseline
	if ancestor_id.is_empty():
		if not baseline.is_empty():
			return _invalid_display_context()
		return {ok = true, context = {state = "unsaved", name = name}}
	if baseline.size() != 8 or typeof(baseline.get("base_id")) != TYPE_STRING \
			or typeof(baseline.get("base_bytes")) != TYPE_PACKED_BYTE_ARRAY \
			or typeof(baseline.get("recipe")) != TYPE_DICTIONARY \
			or typeof(baseline.get("name")) != TYPE_STRING \
			or typeof(baseline.get("descriptor")) != TYPE_DICTIONARY \
			or typeof(baseline.get("dependencies")) != TYPE_DICTIONARY \
			or typeof(baseline.get("compiler")) != TYPE_STRING \
			or typeof(baseline.get("presentation_profile")) != TYPE_DICTIONARY \
			or not _valid_display_name(baseline.name, false):
		return _invalid_display_context()
	var candidate := {base_id = payload.base_id, base_bytes = payload.base_bytes, recipe = payload.get("recipe", {}),
		name = name, descriptor = payload.workshop_descriptor, dependencies = payload.dependencies,
		compiler = payload.compiler_version, presentation_profile = payload.get("presentation_profile", {})}
	var state := "modified" if input.requires_copy or candidate != baseline else "saved"
	return {ok = true, context = {state = state, name = name, saved_name = baseline.name, revision = revision}}


static func _valid_display_name(value: String, allow_empty: bool) -> bool:
	return (allow_empty or not value.is_empty()) and value == value.strip_edges() and value.length() <= Store.MAX_NAME_LENGTH \
		and not value.contains("\n") and not value.contains("\r") and not value.contains("\t")


static func _invalid_display_context() -> Dictionary:
	return {ok = false, errors = PackedStringArray(["Workshop build display context is invalid."])}


static func _sha(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()
