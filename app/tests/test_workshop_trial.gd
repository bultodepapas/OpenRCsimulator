extends SceneTree
## AE-02/10: canonical trial identity, immutable snapshots and provenance refusal.
const Builder := preload("res://render/airplane.gd")
const Trial := preload("res://workshop/trial.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Descriptor := preload("res://workshop/descriptor.gd")
const Dependencies := preload("res://workshop/dependencies.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var bytes := FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	var base: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	var payload := {base_id = Catalog.DEFAULT_ID, base_bytes = bytes, recipe = {}}
	var first := Trial.freeze(payload)
	check("default trial freezes", first.get("ok", false))
	if not first.get("ok", false):
		printerr(first.get("errors", []))
		quit(1)
		return
	check("trial identity hashes its resolved model manifest", first.identity.trial_id == _expected_trial_id(first.identity))
	var alternate_manifest_identity: Dictionary = first.identity.duplicate(true)
	alternate_manifest_identity.presentation.model_manifest_sha256 = "f".repeat(64)
	check("model manifest pin changes the trial identity", first.identity.trial_id != _expected_trial_id(alternate_manifest_identity))
	var alternate_family_identity: Dictionary = first.identity.duplicate(true)
	alternate_family_identity.presentation.visual_family = "other-model-family"
	check("resolved visual family changes the trial identity", first.identity.trial_id != _expected_trial_id(alternate_family_identity))
	var bound_visual: Dictionary = Builder.build(Catalog.DEFAULT_ID, NAN, first.presentation)
	check("frozen trial carries the manifest consumed by its renderer", not bound_visual.is_empty()
		and bound_visual.model_manifest_sha256 == first.identity.presentation.model_manifest_sha256)
	if not bound_visual.is_empty():
		bound_visual.root.free()
	var stale_presentation: Dictionary = first.presentation.duplicate(true)
	stale_presentation.model_manifest_sha256 = "0".repeat(64)
	check("renderer rejects changed presentation after freeze", Builder.build(Catalog.DEFAULT_ID, NAN, stale_presentation).is_empty())
	payload.recipe = Compiler.defaults()
	var explicit := Trial.freeze(payload)
	check("omitted and explicit defaults have the same identity", explicit.identity == first.identity)
	var integer_payload: Dictionary = payload.duplicate(true)
	for key: String in ["scale", "weight_multiplier", "power_multiplier", "control_multiplier", "tank_capacity_multiplier"]:
		integer_payload.recipe[key] = 1
	var integer_trial := Trial.freeze(integer_payload)
	check("integer and float recipes have identical resolved identity", integer_trial.get("ok", false)
		and integer_trial.identity == first.identity and integer_trial.raw_bytes == first.raw_bytes)
	var numeric_roundtrip: Dictionary = integer_payload.duplicate(true)
	numeric_roundtrip.recipe = JSON.parse_string(JSON.stringify(integer_payload.recipe, "", true, true))
	var reloaded_numeric := Trial.freeze(numeric_roundtrip)
	check("JSON round-trip preserves the full trial identity", reloaded_numeric.get("ok", false)
		and reloaded_numeric.identity == integer_trial.identity)
	numeric_roundtrip.recipe.scale = 1.000000000001
	var nearby_numeric := Trial.freeze(numeric_roundtrip)
	check("canonicalization preserves tiny physical edits", nearby_numeric.get("ok", false)
		and nearby_numeric.identity.trial_id != first.identity.trial_id)
	var tank_size_recipe: Dictionary = Compiler.defaults()
	tank_size_recipe.tank_capacity_multiplier = 1.5
	var tank_size_payload: Dictionary = payload.duplicate(true)
	tank_size_payload.recipe = tank_size_recipe
	var tank_size_trial: Dictionary = Trial.freeze(tank_size_payload)
	check("tank capacity is a physical trial input", tank_size_trial.get("ok", false)
		and tank_size_trial.identity.trial_id != explicit.identity.trial_id
		and tank_size_trial.data.model.fuel_system.tanks.size() == 1
		and is_equal_approx(tank_size_trial.data.model.fuel_system.tanks[0].capacity_m3,
			explicit.data.model.fuel_system.tanks[0].capacity_m3 * 1.5))
	var invalid_cosmetic: Dictionary = payload.duplicate(true)
	invalid_cosmetic.recipe.name = {"invalid": true}
	check("invalid recipe metadata is refused before hashing", not Trial.freeze(invalid_cosmetic).get("ok", false))
	payload.recipe.name = "A cosmetic name"
	var renamed := Trial.freeze(payload)
	check("display names do not alter physical identity", renamed.identity.trial_id == first.identity.trial_id)
	payload.recipe.scale = 2.0
	var scaled := Trial.freeze(payload)
	check("physical edits change the identity", scaled.get("ok", false) and scaled.identity.trial_id != first.identity.trial_id)
	check("source remains byte-exact", bytes == FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data))
	payload.recipe.scale = 0.5
	check("frozen snapshot does not follow subsequent draft edits", scaled.scale == 2.0)
	var descriptor: Dictionary = Descriptor.load_for(Catalog.DEFAULT_ID, bytes).descriptor
	var dependencies: Dictionary = Dependencies.capture(base).manifest
	payload.workshop_descriptor = descriptor.duplicate(true)
	payload.dependencies = dependencies.duplicate(true)
	payload.compiler_version = Compiler.COMPILER_VERSION
	payload.variant_id = "saved-parent"
	payload.variant_revision = 3
	var saved := Trial.freeze(payload)
	check("saved revision ancestry is retained", saved.get("ok", false)
		and saved.identity.ancestor_variant_id == "saved-parent" and saved.identity.ancestor_revision == 3)
	var conflicting_ancestor: Dictionary = payload.duplicate(true)
	conflicting_ancestor.recipe.id = "different-parent"
	check("conflicting recipe and payload ancestry is refused", not Trial.freeze(conflicting_ancestor).get("ok", false))
	conflicting_ancestor.variant_id = ""
	conflicting_ancestor.variant_revision = 0
	check("explicit empty ancestry cannot mask a saved recipe ID", not Trial.freeze(conflicting_ancestor).get("ok", false))
	var missing_pin: Dictionary = payload.duplicate(true)
	missing_pin.workshop_descriptor = {}
	check("saved ancestry cannot silently acquire today's descriptor", not Trial.freeze(missing_pin).get("ok", false))
	var oversized: Dictionary = payload.duplicate(true)
	var oversized_bytes := PackedByteArray()
	oversized_bytes.resize(Descriptor.MAX_BASE_BYTES + 1)
	oversized.base_bytes = oversized_bytes
	check("oversized source is refused before JSON parsing", not Trial.freeze(oversized).get("ok", false))
	var malformed_payload: Dictionary = payload.duplicate(true)
	malformed_payload.base_id = StringName(Catalog.DEFAULT_ID)
	check("non-string base IDs are refused", not Trial.freeze(malformed_payload).get("ok", false))
	malformed_payload = payload.duplicate(true)
	malformed_payload.compiler_version = StringName(Compiler.COMPILER_VERSION)
	check("non-string compiler pins are refused", not Trial.freeze(malformed_payload).get("ok", false))
	malformed_payload = payload.duplicate(true)
	malformed_payload.variant_id = StringName("saved-parent")
	check("non-string ancestor IDs are refused", not Trial.freeze(malformed_payload).get("ok", false))
	malformed_payload = payload.duplicate(true)
	malformed_payload.variant_revision = 3.5
	check("fractional ancestor revisions are refused", not Trial.freeze(malformed_payload).get("ok", false))
	malformed_payload = payload.duplicate(true)
	malformed_payload.variant_revision = 0
	check("saved ancestry without a positive revision is refused", not Trial.freeze(malformed_payload).get("ok", false))
	malformed_payload = payload.duplicate(true)
	malformed_payload.variant_id = ""
	malformed_payload.variant_revision = 3
	check("orphan ancestor revisions are refused", not Trial.freeze(malformed_payload).get("ok", false))
	payload.compiler_version = "unsupported-compiler"
	check("compiler replacement is refused", not Trial.freeze(payload).get("ok", false))
	payload.compiler_version = Compiler.COMPILER_VERSION
	var first_path: String = payload.dependencies.files.keys()[0]
	payload.dependencies.files[first_path] = "0".repeat(64)
	check("dependency replacement is refused without modifying resources", not Trial.freeze(payload).get("ok", false))
	payload.dependencies = dependencies.duplicate(true)
	payload.workshop_descriptor.base_sha256 = "0".repeat(64)
	check("stale descriptor is refused", not Trial.freeze(payload).get("ok", false))
	payload.workshop_descriptor = descriptor.duplicate(true)
	payload.workshop_descriptor.presentation.model_manifest_sha256 = "0".repeat(64)
	check("changed presentation dependency cannot freeze a trial", not Trial.freeze(payload).get("ok", false))
	payload.workshop_descriptor = descriptor.duplicate(true)
	var historical_base: Dictionary = base.duplicate(true)
	_strip_physical_identity(historical_base)
	var historical_validation: Dictionary = AircraftData.validate_and_derive(historical_base)
	check("v1 source remains valid after removing identity-bound fuel data",
		historical_validation.get("ok", false))
	if not historical_validation.get("ok", false):
		printerr("Historical source errors: ", historical_validation.get("errors", []))
	var historical_bytes: PackedByteArray = _source_bytes(historical_base)
	var historical_descriptor: Dictionary = descriptor.duplicate(true)
	historical_descriptor.format = Descriptor.LEGACY_FORMAT
	historical_descriptor.base_sha256 = _sha(historical_bytes)
	historical_descriptor.inventory_bindings = _legacy_inventory_bindings(historical_base)
	historical_descriptor.presentation = {"visual_id": Catalog.DEFAULT_ID, "scale_root": "airplane"}
	check("v1 fixture has a genuinely identity-free source snapshot",
		not _has_physical_identity_metadata(historical_base)
		and historical_descriptor.format == Descriptor.LEGACY_FORMAT)
	var historical_descriptor_result: Dictionary = Descriptor.validate(
		historical_descriptor, Catalog.DEFAULT_ID, historical_bytes)
	check("historical v1 descriptor validates against its old source snapshot",
		historical_descriptor_result.get("ok", false))
	var historical_dependencies: Dictionary = Dependencies.capture(historical_base)
	check("historical source dependencies remain capturable", historical_dependencies.get("ok", false))
	var historical_payload: Dictionary = payload.duplicate(true)
	historical_payload.base_bytes = historical_bytes
	historical_payload.workshop_descriptor = historical_descriptor
	historical_payload.dependencies = historical_dependencies.get("manifest", {})
	var old_saved := Trial.freeze(historical_payload)
	check("v1 saved descriptor can still launch through its explicit adapter", old_saved.get("ok", false))
	check("legacy descriptor trial hash binds the resolved model manifest", old_saved.get("ok", false)
		and old_saved.identity.trial_id == _expected_trial_id(old_saved.identity))
	payload.workshop_descriptor = descriptor.duplicate(true)
	payload.compiler_version = ""
	check("saved ancestry without a compiler pin is refused", not Trial.freeze(payload).get("ok", false))
	print("Workshop trial: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)

func _expected_trial_id(identity: Dictionary) -> String:
	var material: String = str(identity.base_sha256) + ":" + str(identity.recipe_sha256) + ":" \
		+ str(identity.descriptor_sha256) + ":" + str(identity.presentation.visual_family) + ":" \
		+ str(identity.presentation.model_manifest_sha256) + ":" \
		+ str(identity.dependencies_sha256) + ":" + str(identity.compiler)
	return "workshop-" + _sha(material.to_utf8_buffer()).substr(0, 32)

func _sha(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


func _source_bytes(base: Dictionary) -> PackedByteArray:
	return (JSON.stringify(base, "\t", true, true) + "\n").to_utf8_buffer()


func _has_physical_identity_metadata(base: Dictionary) -> bool:
	if base.has("physical_identity_version") or base.has("crash_hull_ids"):
		return true
	for item: Variant in base.get("inventory", []):
		if item is Dictionary and item.has("id"):
			return true
	var gear: Variant = base.get("landing_gear", {})
	if gear is Dictionary:
		for contact: Variant in gear.get("contacts", []):
			if contact is Dictionary and contact.has("id"):
				return true
	var propulsion: Variant = base.get("propulsion", {})
	if propulsion is Dictionary and propulsion.has("id"):
		return true
	var controls: Variant = base.get("controls", {})
	return controls is Dictionary and controls.has("surface_ids")


func _strip_physical_identity(base: Dictionary) -> void:
	base.erase("physical_identity_version")
	# FUEL-03: emulate the identity-free legacy fixture without v2 ID-bound tank state.
	if base.erase("fuel_system"):
		var balance: Dictionary = base.balance
		balance.erase("fuel_state")
		balance.erase("cg_range")
		var mass := 0.0
		var first := [0.0, 0.0, 0.0]
		for item: Dictionary in base.inventory:
			mass += float(item.mass.value)
			for axis in 3:
				first[axis] += float(item.mass.value) * float(item.position.value[axis])
		balance.plan_cg.value = [first[0] / mass, first[1] / mass, first[2] / mass]
	for item: Variant in base.get("inventory", []):
		if item is Dictionary:
			item.erase("id")
	var gear: Variant = base.get("landing_gear", {})
	if gear is Dictionary:
		var contacts: Variant = gear.get("contacts", [])
		if contacts is Array:
			for contact: Variant in contacts:
				if contact is Dictionary:
					contact.erase("id")
	var propulsion: Variant = base.get("propulsion", {})
	if propulsion is Dictionary:
		propulsion.erase("id")
	base.erase("crash_hull_ids")
	var controls: Variant = base.get("controls", {})
	if controls is Dictionary:
		controls.erase("surface_ids")


func _legacy_inventory_bindings(base: Dictionary) -> Array:
	var bindings: Array = []
	for index: int in range(base.get("inventory", []).size()):
		var name: String = str(base["inventory"][index].get("name", ""))
		var name_hash: String = _sha(name.to_utf8_buffer())
		bindings.append({"key": "inventory-%03d-%s" % [index, name_hash.substr(0, 12)],
			"index": index, "name_sha256": name_hash})
	return bindings
