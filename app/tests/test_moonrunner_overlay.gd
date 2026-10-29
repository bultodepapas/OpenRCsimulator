extends SceneTree

const Registry := preload("res://aircraft/model_registry.gd")
const OverlayModels := preload("res://aircraft/model_overlay_registry.gd")
const OverlayCustomization := preload("res://aircraft/customization_overlay.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const Profile := preload("res://workshop/presentation.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Trial := preload("res://workshop/trial.gd")
const Store := preload("res://workshop/store.gd")
const Bundle := preload("res://workshop/bundle.gd")
const MODEL := "res://data/aircraft_model_overlays/moonrunner-x99.json"
const OVERLAY := "res://data/aircraft_customization_overlays/moonrunner-x99.json"

var checks := 0
var failures := 0

func _initialize() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MODEL))
	var overlay: Variant = JSON.parse_string(FileAccess.get_file_as_string(OVERLAY))
	_check("model manifest object", manifest is Dictionary)
	_check("customization registry object", overlay is Dictionary and overlay.get("families", []) is Array and overlay.families.size() == 1)
	if manifest is Dictionary and overlay is Dictionary and overlay.get("families", []) is Array and overlay.families.size() == 1:
		var model_result: Dictionary = Registry.validate_manifest(manifest, "moonrunner-x99")
		_check("model verifies source and resource identity", model_result.get("ok", false), str(model_result.get("errors", [])))
		var hash := FileAccess.get_sha256(MODEL)
		var bindings: Dictionary = overlay.families[0]
		var binding_result: Dictionary = Customization.validate_bindings(bindings, "moonrunner-x99", hash)
		_check("companion verifies model and slot identities", binding_result.get("ok", false), str(binding_result.get("errors", [])))
		_check("wrong family is rejected", not Registry.validate_manifest(manifest, "skywalker-x8").get("ok", false))
		_check("wrong companion model hash is rejected", not Customization.validate_bindings(bindings, "moonrunner-x99", "0".repeat(64)).get("ok", false))
		var tampered := bindings.duplicate(true)
		tampered.paint_slots[0].label = "tampered"
		_check("modified slot without new identity is rejected", not Customization.validate_bindings(tampered, "moonrunner-x99", hash).get("ok", false))
	_test_runtime_resolution(overlay)
	_test_missing_resolvers()
	_test_invalid_resolver()
	_test_detached_workshop()
	print("MoonRunner overlay: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _test_runtime_resolution(overlay: Variant) -> void:
	var model: Dictionary = OverlayModels.describe("moonrunner-x99")
	_check("overlay model runtime resolver validates source proof", model.get("ok", false), str(model.get("errors", [])))
	_check("unknown model overlay rejected", not OverlayModels.describe("unknown").get("ok", false))
	var companion: Dictionary = OverlayCustomization.describe("moonrunner-x99")
	_check("overlay companion runtime resolver validates source and slots", companion.get("ok", false), str(companion.get("errors", [])))
	if model.get("ok", false) and companion.get("ok", false):
		var builder: Script = load(str(model.manifest.builder.script))
		var built: Dictionary = builder.build(model.manifest)
		var derived: Dictionary = Registry.validate_derived(model.manifest, built)
		_check("overlay imported model and hinges validate", derived.get("ok", false), str(derived.get("errors", [])))
		if built.get("root") is Node3D:
			built.visual_family = "moonrunner-x99"
			built.model_manifest_sha256 = model.manifest_sha256
			built.customization_bindings = companion.bindings
			var profile: Dictionary = Profile.defaults(companion.bindings)
			profile.paint = [{"slot": companion.bindings.paint_slots[0].id, "color": "#327DE8FF", "pattern": "solid", "accent": "none"}]
			var paint: Dictionary = Customization.apply(built, profile)
			_check("overlay paint slots resolve on imported model", paint.get("ok", false), str(paint.get("errors", [])))
			built.root.free()
	_check("unknown customization overlay rejected", not OverlayCustomization.describe("unknown").get("ok", false))
	_check("wrong requested model hash rejected", not OverlayCustomization.describe_for_model("moonrunner-x99", "0".repeat(64)).get("ok", false))
	var base: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft_customization.json"))
	if base is Dictionary and overlay is Dictionary:
		var duplicate: Dictionary = base.duplicate(true)
		duplicate.families.append({"visual_family": "moonrunner-x99"})
		_check("base family collision rejected", not OverlayCustomization._select(duplicate, overlay).get("ok", false))
		var unknown: Dictionary = overlay.duplicate(true)
		unknown.families[0].visual_family = "unknown"
		_check("unregistered overlay family rejected", not OverlayCustomization._select(base, unknown).get("ok", false))
		var malformed: Dictionary = overlay.duplicate(true)
		malformed["extra"] = true
		_check("malformed overlay registry rejected", not OverlayCustomization._select(base, malformed).get("ok", false))

func _test_missing_resolvers() -> void:
	# Exercise the real consumer code in disposable copies with only its resolver
	# path changed. No production module or saved variant is moved or modified.
	var directory := "user://moonrunner-missing-resolver-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var scripts := {}
	for name: String in ["store", "bundle", "trial"]:
		var source := FileAccess.get_file_as_string("res://workshop/" + name + ".gd")
		var target := "res://aircraft/customization_overlay.gd"
		_check("consumer has one explicit overlay resolver " + name, source.count(target) == 1)
		if source.count(target) != 1: continue
		var path := directory.path_join(name + ".gd")
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_check("disposable consumer writes " + name, false)
			continue
		file.store_string(source.replace(target, "res://aircraft/missing_overlay_control.gd"))
		file.close()
		var script: Script = load(path)
		_check("disposable consumer compiles " + name, script != null)
		if script != null: scripts[name] = script
	if scripts.size() == 3:
		var descriptor: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/workshop/moonrunner-x99.json"))
		var bytes := FileAccess.get_file_as_bytes("res://data/aircraft/moonrunner_x99.json")
		var missing_store: Dictionary = scripts.store._resolve_customization_bindings("moonrunner-x99", descriptor)
		_check("store refuses a missing overlay resolver", not missing_store.get("ok", false) and not missing_store.get("missing", true) and not missing_store.get("errors", []).is_empty())
		var missing_bundle: Dictionary = scripts.bundle._resolve_current_profile({base_id = "moonrunner-x99", workshop_descriptor = descriptor, presentation_profile = {}})
		_check("bundle refuses a missing overlay resolver", not missing_bundle.get("ok", false) and not missing_bundle.get("errors", []).is_empty())
		var missing_trial: Dictionary = scripts.trial.freeze({base_id = "moonrunner-x99", base_bytes = bytes, recipe = Compiler.defaults(), workshop_descriptor = descriptor})
		_check("trial refuses a missing overlay resolver", not missing_trial.get("ok", false) and not missing_trial.get("errors", []).is_empty())
	var model_source := FileAccess.get_file_as_string("res://aircraft/model_registry.gd")
	var model_target := "res://aircraft/model_overlay_registry.gd"
	_check("model registry has one explicit overlay resolver", model_source.count(model_target) == 1)
	if model_source.count(model_target) == 1:
		var path := directory.path_join("model_registry.gd")
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(model_source.replace(model_target, "res://aircraft/missing_model_overlay_control.gd"))
		file.close()
		var model_script: Script = load(path)
		_check("disposable model registry compiles", model_script != null)
		if model_script != null:
			_check("model registry refuses a missing overlay resolver", not model_script.describe("moonrunner-x99").get("ok", false))
			_check("legacy model remains available with the overlay resolver absent", model_script.describe("skywalker-x8").get("ok", false))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for name: String in ["store", "bundle", "trial"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(name + ".gd")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))


func _test_invalid_resolver() -> void:
	# Test the actual consumers with a resolver that reports invalid data, without
	# changing any registered project source or saved variant.
	var directory := "user://moonrunner-invalid-resolver-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var resolver_path := directory.path_join("invalid_overlay.gd")
	var file := FileAccess.open(resolver_path, FileAccess.WRITE)
	file.store_string('extends RefCounted\nstatic func describe(_family: String) -> Dictionary:\n\treturn {"ok": false, "errors": PackedStringArray(["Malformed overlay control."])}\n')
	file.close()
	var scripts := {}
	for name: String in ["store", "bundle", "trial"]:
		var source := FileAccess.get_file_as_string("res://workshop/" + name + ".gd")
		var target := "res://aircraft/customization_overlay.gd"
		_check("invalid control finds overlay resolver " + name, source.count(target) == 1)
		if source.count(target) != 1: continue
		var path := directory.path_join(name + ".gd")
		file = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(source.replace(target, resolver_path))
		file.close()
		var script: Script = load(path)
		_check("invalid control consumer compiles " + name, script != null)
		if script != null: scripts[name] = script
	if scripts.size() == 3:
		var descriptor: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/workshop/moonrunner-x99.json"))
		var bytes := FileAccess.get_file_as_bytes("res://data/aircraft/moonrunner_x99.json")
		var binding: Dictionary = scripts.store._resolve_customization_bindings("moonrunner-x99", descriptor)
		_check("invalid overlay is not treated as missing legacy companion", not binding.get("ok", false) and not binding.get("missing", true))
		var saved: Dictionary = scripts.store.save_variant("Invalid overlay control", "moonrunner-x99", bytes, Compiler.defaults(), "", directory.path_join("store"), descriptor)
		_check("store refuses invalid overlay with empty profile", not saved.get("ok", false) and not saved.get("errors", []).is_empty())
		if saved.get("ok", false): scripts.store.delete_variant(saved.variant.id, directory.path_join("store"))
		var trial: Dictionary = scripts.trial.freeze({base_id = "moonrunner-x99", base_bytes = bytes, recipe = Compiler.defaults(), workshop_descriptor = descriptor})
		_check("trial refuses invalid overlay with empty profile", not trial.get("ok", false) and not trial.get("errors", []).is_empty())
		var bundle: Dictionary = scripts.bundle._resolve_current_profile({base_id = "moonrunner-x99", workshop_descriptor = descriptor, presentation_profile = {}})
		_check("bundle refuses invalid overlay with empty profile", not bundle.get("ok", false) and not bundle.get("errors", []).is_empty())
	for name: String in ["store", "bundle", "trial"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(name + ".gd")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(resolver_path))
	# save_variant can create the test store before rejecting the profile.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join("store")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))


func _test_detached_workshop() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://data/aircraft/moonrunner_x99.json")
	var descriptor: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/workshop/moonrunner-x99.json"))
	var bindings: Dictionary = OverlayCustomization.describe("moonrunner-x99")
	if bytes.is_empty() or not descriptor is Dictionary or not bindings.get("ok", false):
		_check("canonical Workshop inputs load", false)
		return
	var profile: Dictionary = Profile.defaults(bindings.bindings)
	profile.paint = [{"slot": bindings.bindings.paint_slots[0].id, "color": "#327DE8FF", "pattern": "solid", "accent": "none"}]
	var root := "user://moonrunner_overlay_test_%d" % Time.get_ticks_usec()
	var saved: Dictionary = Store.save_variant("MoonRunner overlay fixture", "moonrunner-x99", bytes, Compiler.defaults(), "", root, descriptor, {}, -1, profile)
	_check("new-family customized snapshot saves", saved.get("ok", false), str(saved.get("errors", [])))
	if not saved.get("ok", false): return
	var variant: Dictionary = saved.variant
	var loaded: Dictionary = Store.load_variant(variant.id, root)
	_check("new-family snapshot reloads unchanged", loaded.get("ok", false) and loaded.variant.presentation_profile == profile)
	var trial: Dictionary = Trial.freeze({base_id = variant.base_id, base_bytes = variant.base_bytes, recipe = variant.recipe, workshop_descriptor = variant.workshop_descriptor, dependencies = variant.dependencies, compiler_version = variant.compiler_version, variant_id = variant.id, variant_revision = variant.revision, presentation_profile = variant.presentation_profile})
	_check("new-family customized trial resolves", trial.get("ok", false), str(trial.get("errors", [])))
	var exported: Dictionary = Bundle.export_variant(variant)
	_check("new-family customized bundle exports", exported.get("ok", false), str(exported.get("errors", [])))
	if exported.get("ok", false):
		var imported: Dictionary = Bundle.import_variant(exported.bytes, root + "/imports")
		_check("new-family customized bundle imports", imported.get("ok", false), str(imported.get("errors", [])))
		if imported.get("ok", false):
			_check("import retains exact physical and presentation pins", imported.variant.base_bytes == bytes and imported.variant.presentation_profile == variant.presentation_profile)
			Store.delete_variant(imported.variant.id, root + "/imports")
	_check("new-family snapshot cleans up", Store.delete_variant(variant.id, root).get("ok", false))


func _check(name: String, passed: bool, detail: String = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", name, ": ", detail)
