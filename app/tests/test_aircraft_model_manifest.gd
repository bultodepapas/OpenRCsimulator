extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Registry := preload("res://aircraft/model_registry.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_catalog_family_mapping()
	_test_manifest_rejections()
	_test_construction_rejections()
	_test_gltf_section_contract()
	_test_builders()
	print("Aircraft model manifest: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_catalog_family_mapping() -> void:
	var families: Dictionary = {}
	var ids := Catalog.airplane_flyable_ids()
	var expected_airplane_ids := PackedStringArray()
	for entry: Dictionary in Catalog.flyable_entries():
		var aircraft_id := str(entry.get("id", ""))
		var vehicle := str(entry.get("vehicle", "airplane"))
		var known_vehicle := vehicle in ["airplane", "rotorcraft"]
		_check("catalog vehicle type is supported: " + aircraft_id, known_vehicle)
		if vehicle == "airplane":
			expected_airplane_ids.append(aircraft_id)
			_check("airplane catalog query includes " + aircraft_id, ids.has(aircraft_id) and not Catalog.is_rotorcraft(aircraft_id))
		elif vehicle == "rotorcraft":
			_check("airplane catalog query excludes rotorcraft " + aircraft_id, not ids.has(aircraft_id) and Catalog.is_rotorcraft(aircraft_id))
	_check("airplane IDs follow catalog vehicle classification", ids == expected_airplane_ids, str(ids))
	_check("catalog exposes airplane configurations", not ids.is_empty())
	for aircraft_id in ids:
		var family_id: String = Catalog.visual_family(aircraft_id)
		_check("catalog family is explicit: " + aircraft_id, not family_id.is_empty())
		families[family_id] = true
	_check("every catalog airplane family has an explicit manifest", not families.is_empty(), str(families.keys()))
	var rotor_family: String = Catalog.visual_family("xcell-60-research")
	var rotor_entry: Dictionary = Catalog.entry("xcell-60-research")
	var rotor_manifest: Dictionary = Registry.describe(rotor_family)
	_check("HX-700 rotorcraft family stays outside the airplane manifest registry",
		rotor_entry.get("vehicle", "") == "rotorcraft" and Catalog.is_rotorcraft("xcell-60-research")
		and not ids.has("xcell-60-research") and rotor_family == "hx-700"
		and not rotor_manifest.ok and _has_code(rotor_manifest.diagnostics, "MODEL_MANIFEST_MISSING"), str(rotor_manifest.diagnostics))
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
	unknown_version.version = 3
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
	var built: Dictionary = builder.call("build", description.manifest) if int(description.manifest.get("version", 1)) == 2 else builder.call("build")
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


func _test_construction_rejections() -> void:
	var description: Dictionary = Registry.describe("turbo-lumber-evolution")
	_check("generic imported family has a version 2 manifest", description.ok and int(description.manifest.get("version", 0)) == 2, str(description.errors))
	if not description.ok or int(description.manifest.get("version", 0)) != 2: return
	var valid: Dictionary = description.manifest
	var rejected: Dictionary = {}
	var unknown_version := valid.duplicate(true)
	unknown_version.construction.version = true
	rejected = Registry.validate_manifest(unknown_version)
	_check("boolean construction version rejects", not rejected.ok and _has_code(rejected.diagnostics, "MODEL_CONSTRUCTION_VERSION_UNSUPPORTED"), str(rejected.diagnostics))
	var unknown_field := valid.duplicate(true)
	unknown_field.construction.future_mode = "guess"
	rejected = Registry.validate_manifest(unknown_field)
	_check("unknown construction field rejects", not rejected.ok and _has_code(rejected.diagnostics, "MODEL_CONSTRUCTION_FIELD_UNKNOWN"), str(rejected.diagnostics))
	var duplicate_wrapper := valid.duplicate(true)
	duplicate_wrapper.construction.gear[1].wrapper = duplicate_wrapper.construction.gear[0].wrapper
	rejected = Registry.validate_manifest(duplicate_wrapper)
	_check("duplicate construction wrapper rejects", not rejected.ok and _has_code(rejected.diagnostics, "MODEL_CONSTRUCTION_NODE_COLLISION"), str(rejected.diagnostics))
	var generated_mount_collision := valid.duplicate(true)
	generated_mount_collision.construction.gear[1].node = generated_mount_collision.construction.gear[0].wrapper + "_mount"
	rejected = Registry.validate_manifest(generated_mount_collision)
	_check("generated gear mount cannot collide with an authored pivot", not rejected.ok and _has_code(rejected.diagnostics, "MODEL_CONSTRUCTION_NODE_COLLISION"), str(rejected.diagnostics))
	var wrapper_mount_collision := valid.duplicate(true)
	wrapper_mount_collision.construction.gear[2].node = wrapper_mount_collision.construction.gear[1].wrapper + "_mount"
	rejected = Registry.validate_manifest(wrapper_mount_collision)
	_check("gear node cannot collide with a generated wrapper mount", not rejected.ok and _has_code(rejected.diagnostics, "MODEL_CONSTRUCTION_NODE_COLLISION"), str(rejected.diagnostics))
	var unsupported_ref := valid.duplicate(true)
	unsupported_ref.construction.gear[0].geometry_ref = "articulations..missing"
	rejected = Registry.validate_manifest(unsupported_ref)
	_check("malformed construction reference rejects", not rejected.ok and _has_code(rejected.diagnostics, "MODEL_CONSTRUCTION_REF_INVALID"), str(rejected.diagnostics))
	var cross_role_collision := valid.duplicate(true)
	cross_role_collision.construction.gear[0].node = cross_role_collision.bindings.controls.aileron_left.hinges[0].node
	rejected = Registry.validate_manifest(cross_role_collision)
	_check("construction node cannot collide with a control hinge", not rejected.ok and _has_code(rejected.diagnostics, "MODEL_CONSTRUCTION_NODE_COLLISION"), str(rejected.diagnostics))
	var duplicate_material := valid.duplicate(true)
	duplicate_material.construction.material_grow.append(duplicate_material.construction.material_grow[0].duplicate(true))
	rejected = Registry.validate_manifest(duplicate_material)
	_check("duplicate material node/material pair rejects", not rejected.ok and _has_code(rejected.diagnostics, "MODEL_CONSTRUCTION_MATERIAL_DUPLICATE"), str(rejected.diagnostics))


func _test_builders() -> void:
	var exercised: Dictionary = {}
	for aircraft_id in Catalog.airplane_flyable_ids():
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
		var built: Dictionary = builder.call("build", description.manifest) if int(description.manifest.get("version", 1)) == 2 else builder.call("build")
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
