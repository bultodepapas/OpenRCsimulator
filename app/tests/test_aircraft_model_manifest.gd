extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Registry := preload("res://aircraft/model_registry.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_catalog_family_mapping()
	_test_manifest_rejections()
	_test_gltf_section_contract()
	_test_builders()
	print("Aircraft model manifest: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_catalog_family_mapping() -> void:
	var families: Dictionary = {}
	var ids := Catalog.ids()
	for aircraft_id in ids:
		var family_id: String = Catalog.visual_family(aircraft_id)
		_check("catalog family is explicit: " + aircraft_id, not family_id.is_empty())
		families[family_id] = true
	_check("seven physical configurations map to five visual families", ids.size() == 7 and families.size() == 5, str(families.keys()))
	for family_id in families:
		var result: Dictionary = Registry.describe(str(family_id))
		_check("manifest describes catalog visual family " + str(family_id), result.ok, str(result.errors))
		if result.ok:
			_check("manifest family id is exact " + str(family_id), result.manifest.family_id == family_id)
	var unknown: Dictionary = Registry.describe("unknown-aircraft")
	_check("unknown visual family does not fall back", not unknown.ok and _has_code(unknown.diagnostics, "MODEL_MANIFEST_MISSING"))


func _test_manifest_rejections() -> void:
	var valid_result: Dictionary = Registry.describe("jensen-das-ugly-stik-60")
	if not valid_result.ok:
		_check("rejection fixtures have a valid manifest base", false, str(valid_result.errors))
		return
	var valid: Dictionary = valid_result.manifest
	var unknown_field := valid.duplicate(true)
	unknown_field.future_model_mode = "guess"
	var rejected: Dictionary = Registry.validate_manifest(unknown_field)
	_check("unknown manifest fields reject", not rejected.ok and _has_code(rejected.diagnostics, "MODEL_FIELD_UNKNOWN"), str(rejected.diagnostics))
	var unknown_version := valid.duplicate(true)
	unknown_version.version = 2
	rejected = Registry.validate_manifest(unknown_version)
	_check("unknown model manifest versions reject", not rejected.ok and _has_code(rejected.diagnostics, "MODEL_VERSION_UNSUPPORTED"))
	var bad_hash := valid.duplicate(true)
	bad_hash.dependencies[0].sha256 = "0".repeat(64)
	rejected = Registry.validate_manifest(bad_hash)
	_check("dependency hash changes reject", not rejected.ok and _has_code(rejected.diagnostics, "MODEL_HASH_MISMATCH"), str(rejected.diagnostics))
	var bad_path := valid.duplicate(true)
	bad_path.dependencies[0].path = "res://aircraft/../outside.gd"
	rejected = Registry.validate_manifest(bad_path)
	_check("dependency traversal paths reject", not rejected.ok and _has_code(rejected.diagnostics, "MODEL_DEPENDENCY_PATH_INVALID"), str(rejected.diagnostics))
	var bad_role := valid.duplicate(true)
	bad_role.bindings.controls["future_surface"] = bad_role.bindings.controls.aileron_left.duplicate(true)
	rejected = Registry.validate_manifest(bad_role)
	_check("unknown control roles reject", not rejected.ok and _has_code(rejected.diagnostics, "MODEL_CONTROL_ROLE_UNKNOWN"))
	var missing_control := valid.duplicate(true)
	missing_control.bindings.controls.erase("rudder")
	rejected = Registry.validate_manifest(missing_control)
	_check("missing stable control role rejects", not rejected.ok and _has_code(rejected.diagnostics, "MODEL_CONTROL_MISSING"))
	var wrong_family := Registry.validate_manifest(valid, "gp-extra-300s-60")
	_check("requested family mismatch rejects", not wrong_family.ok and _has_code(wrong_family.diagnostics, "MODEL_FAMILY_MISMATCH"))


func _test_gltf_section_contract() -> void:
	var description: Dictionary = Registry.describe("turbo-lumber-evolution")
	_check("r2 section fixture has a current manifest", description.ok, str(description.errors))
	if not description.ok: return
	var builder: Script = load(str(description.manifest.builder.script))
	var built: Dictionary = builder.call("build")
	var wing: Node = built.root.find_child("wing_left_fixed", true, false)
	var original: Dictionary = wing.get_meta("extras").duplicate(true)
	var missing := original.duplicate(true)
	missing.erase("openrc_section")
	wing.set_meta("extras", missing)
	var result: Dictionary = Registry.validate_derived(description.manifest, built)
	_check("missing imported section rejects before flight", not result.ok and _has_code(result.diagnostics, "MODEL_BUILD_SECTION_MISSING"))
	for value: Variant in [17, "Wing_Left"]:
		var invalid := original.duplicate(true)
		invalid.openrc_section = value
		wing.set_meta("extras", invalid)
		result = Registry.validate_derived(description.manifest, built)
		_check("invalid section type or vocabulary rejects", not result.ok and _has_code(result.diagnostics, "MODEL_BUILD_SECTION_INVALID"))
	wing.set_meta("extras", original)
	var hinge: Node = built.root.find_child("aileron_left_hinge", true, false)
	var hinge_extras: Dictionary = hinge.get_meta("extras").duplicate(true)
	var missing_pivot := hinge_extras.duplicate(true)
	missing_pivot.erase("openrc_section")
	hinge.set_meta("extras", missing_pivot)
	result = Registry.validate_derived(description.manifest, built)
	_check("untagged articulated pivot rejects", not result.ok and _has_code(result.diagnostics, "MODEL_BUILD_SECTION_MISSING"))
	hinge.set_meta("extras", hinge_extras)
	var thrust: Node = built.root.find_child("thrust_frame", true, false)
	var thrust_extras: Dictionary = thrust.get_meta("extras", {}).duplicate(true)
	var capturing := thrust_extras.duplicate(true)
	capturing.openrc_section = "engine"
	thrust.set_meta("extras", capturing)
	result = Registry.validate_derived(description.manifest, built)
	_check("engine ancestor cannot capture propeller section", not result.ok and _has_code(result.diagnostics, "MODEL_BUILD_SECTION_CAPTURED"))
	thrust.set_meta("extras", thrust_extras)
	_check("restored sectioned scene accepts", Registry.validate_derived(description.manifest, built).ok)
	built.root.free()
	var procedural: Dictionary = Registry.describe("jensen-das-ugly-stik-60").manifest.duplicate(true)
	procedural.bindings.crash = {provider = "gltf_extras", metadata_script = "", asset_node = ""}
	result = Registry.validate_manifest(procedural)
	_check("gltf section provider rejects procedural asset", not result.ok and _has_code(result.diagnostics, "MODEL_CRASH_ASSET_INVALID"))


func _test_builders() -> void:
	var exercised: Dictionary = {}
	for aircraft_id in Catalog.ids():
		exercised[Catalog.visual_family(aircraft_id)] = true
	for family_id_variant in exercised.keys():
		var family_id := str(family_id_variant)
		var description: Dictionary = Registry.describe(family_id)
		if not description.ok:
			_check("builder manifest is current: " + family_id, false, str(description.errors))
			continue
		var builder: Script = load(str(description.manifest.builder.script)) as Script
		if builder == null:
			_check("registered builder script loads: " + family_id, false)
			continue
		var built: Dictionary = builder.call("build")
		var result: Dictionary = Registry.validate_derived(description.manifest, built)
		_check("derived builder bindings conform: " + family_id, result.ok, str(result.errors))
		if family_id == "jensen-das-ugly-stik-60" and built.get("root") is Node3D:
			var broken: Dictionary = built.duplicate(false)
			broken.hinges = built.hinges.duplicate()
			broken.hinges.erase("rudder")
			var malformed: Dictionary = Registry.validate_derived(description.manifest, broken)
			_check("builder missing hinge rejects", not malformed.ok and _has_code(malformed.diagnostics, "MODEL_BUILD_HINGE_MISSING"))
		if description.manifest.builder.adapter != "euler_hinges":
			var key: String = description.manifest.bindings.controls.rudder.hinges[0].key
			var invalid: Dictionary = built.duplicate(false)
			invalid.hinges = built.hinges.duplicate()
			invalid.hinges[key] = built.hinges[key].duplicate()
			invalid.hinges[key].axis = Vector3(2.0, 0.0, 0.0)
			_check("non-unit authored axis rejects: " + family_id, not Registry.validate_derived(description.manifest, invalid).ok)
			invalid.hinges[key].axis = built.hinges[key].axis
			invalid.hinges[key].rest = Basis(Vector3(NAN, 0.0, 0.0), Vector3.UP, Vector3.FORWARD)
			_check("non-finite authored rest rejects: " + family_id, not Registry.validate_derived(description.manifest, invalid).ok)
		if built.get("root") is Node:
			built.root.free()


func _has_code(diagnostics: Array, code: String) -> bool:
	for diagnostic: Variant in diagnostics:
		if typeof(diagnostic) == TYPE_DICTIONARY and diagnostic.get("code") == code:
			return true
	return false


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
