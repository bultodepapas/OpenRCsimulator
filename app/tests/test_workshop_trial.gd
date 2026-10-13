extends SceneTree
## AE-02/10: canonical trial identity, immutable snapshots and provenance refusal.
const Builder := preload("res://render/airplane.gd")
const Trial := preload("res://workshop/trial.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Descriptor := preload("res://workshop/descriptor.gd")
const Dependencies := preload("res://workshop/dependencies.gd")
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
	payload.workshop_descriptor.format = Descriptor.LEGACY_FORMAT
	payload.workshop_descriptor.presentation = {"visual_id": Catalog.DEFAULT_ID, "scale_root": "airplane"}
	var old_saved := Trial.freeze(payload)
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
