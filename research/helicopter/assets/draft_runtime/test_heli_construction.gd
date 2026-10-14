# HELI-25c draft: native admission tests for the detached neutral HX-700 preview.
extends SceneTree

const Model := preload("res://../research/helicopter/assets/draft_runtime/hx700_articulated_model.gd")
const PROFILE_PATH := "res://assets/aircraft/hx-700/articulated/construction.json"
const ASSET_PATH := "res://assets/aircraft/hx-700/articulated/hx-700.glb"
const MUTATED_PROFILE_PATH := "user://heli25c-construction-mutated.json"
const CORRUPTED_ASSET_PATH := "user://heli25c-corrupted.glb"

var _checks := 0
var _failures := 0
var _profile: Dictionary = {}
var _scene: PackedScene


func _initialize() -> void:
	if not FileAccess.file_exists(PROFILE_PATH) or not FileAccess.file_exists(ASSET_PATH):
		_check("runtime construction source files exist", false, PROFILE_PATH)
		_finish()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not parsed is Dictionary:
		_check("runtime construction profile parses", false)
		_finish()
		return
	_profile = parsed
	_scene = ResourceLoader.load(ASSET_PATH) as PackedScene
	if _scene == null:
		_check("HX-700 GLB imports as PackedScene", false)
		_finish()
		return

	var accepted := Model.load_preview()
	_check("native load admits exact hash-bound neutral construction", accepted.ok
		and accepted.root is Node3D and accepted.root.name == "hx700_mechanical_preview"
		and accepted.bindings.size() == _profile.bindings.size(), str(accepted.errors))
	if not accepted.ok:
		_finish()
		return
	_check("preview root has no aircraft flight or propeller ABI", accepted.root.name == "hx700_mechanical_preview"
		and not accepted.has("propeller") and not accepted.has("airplane")
		and not accepted.has("hinges") and not accepted.has("gear"))
	var second := Model.load_preview()
	var first_main_shaft: Node3D = accepted.bindings.get("main.shaft") as Node3D
	var second_main_shaft: Node3D = second.bindings.get("main.shaft") as Node3D
	_check("repeated loads return independent scene and binding clones", second.ok
		and accepted.root != second.root and first_main_shaft != second_main_shaft)
	if second.ok:
		var saved_second_position := second_main_shaft.position
		first_main_shaft.position.x += 0.01
		_check("editing one clone does not change another clone", second_main_shaft.position == saved_second_position)
		second.root.free()
	accepted.root.free()

	var valid_scene := _scene.instantiate() as Node3D
	var valid := Model.validate(_profile.duplicate(true), valid_scene)
	_check("detached imported scene passes profile, hierarchy, rest matrices and nine rigid rods",
		valid.ok and valid.bindings.size() == _profile.bindings.size(), str(valid.errors))
	valid_scene.free()

	_reject_profile("duplicate binding ID", func(data: Dictionary) -> void:
		data.bindings[1].id = data.bindings[0].id)
	_reject_profile("missing binding", func(data: Dictionary) -> void:
		data.bindings.remove_at(data.bindings.size() - 1))
	_reject_profile("wrong profile purpose", func(data: Dictionary) -> void:
		data.purpose = "flight-ready")
	_reject_profile("unknown top-level field", func(data: Dictionary) -> void:
		data["unreviewed"] = true)
	_reject_profile("unknown binding field", func(data: Dictionary) -> void:
		data.bindings[0]["joint_axis"] = [0.0, 1.0, 0.0])
	_reject_profile("malformed transform length", func(data: Dictionary) -> void:
		data.bindings[0].rest_transform.remove_at(0))
	_reject_profile("non-finite transform component", func(data: Dictionary) -> void:
		data.bindings[0].rest_transform[9] = NAN)
	_reject_profile("singular transform basis", func(data: Dictionary) -> void:
		data.bindings[0].rest_transform[0] = 0.0
		data.bindings[0].rest_transform[1] = 0.0
		data.bindings[0].rest_transform[2] = 0.0)
	_reject_profile("cyclic and disconnected parent graph", func(data: Dictionary) -> void:
		_get_binding(data, "root").parent_id = "main.shaft")
	_reject_profile("rod length mismatch", func(data: Dictionary) -> void:
		data.linkages[0].length_m += 0.001)
	_reject_native_transform("native rest transform mismatch")
	_reject_native_rod("native linkage endpoint mismatch")
	_check_wrong_profile_hash()
	_check_corrupted_asset_bytes()
	_check_missing_raw_asset_bytes()
	_finish()


func _reject_profile(label: String, mutate: Callable) -> void:
	var data: Dictionary = _profile.duplicate(true)
	mutate.call(data)
	var instance := _scene.instantiate() as Node3D
	var result := Model.validate(data, instance)
	_check(label, not result.ok and not result.errors.is_empty(), str(result.errors))
	instance.free()


func _reject_native_transform(label: String) -> void:
	var instance := _scene.instantiate() as Node3D
	var binding: Dictionary = _get_binding(_profile, "actuator.tail")
	var node := instance.find_child(String(binding.node), true, false) as Node3D
	if node != null:
		node.position.x += 0.001
	var result := Model.validate(_profile.duplicate(true), instance)
	_check(label, node != null and not result.ok and _has_error(result.errors, "rest transform"), str(result.errors))
	instance.free()


func _reject_native_rod(label: String) -> void:
	var instance := _scene.instantiate() as Node3D
	var endpoint_id: String = String(_profile.linkages[0].endpoint_a)
	var binding: Dictionary = _get_binding(_profile, endpoint_id)
	var node := instance.find_child(String(binding.node), true, false) as Node3D
	if node != null:
		node.position.x += 0.001
	var result := Model.validate(_profile.duplicate(true), instance)
	_check(label, node != null and not result.ok and _has_error(result.errors, "endpoint distance"), str(result.errors))
	instance.free()


func _check_wrong_profile_hash() -> void:
	var data: Dictionary = _profile.duplicate(true)
	data.asset.sha256 = "0".repeat(64)
	var file := FileAccess.open(MUTATED_PROFILE_PATH, FileAccess.WRITE)
	if file == null:
		_check("write disposable wrong-hash profile", false)
		return
	file.store_string(JSON.stringify(data))
	file.close()
	var result := Model.load_preview(MUTATED_PROFILE_PATH)
	_check("profile hash mismatch fails closed before scene admission", not result.ok
		and _has_error(result.errors, "SHA-256"), str(result.errors))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MUTATED_PROFILE_PATH))


func _check_corrupted_asset_bytes() -> void:
	var bytes := FileAccess.get_file_as_bytes(ASSET_PATH)
	if bytes.is_empty():
		_check("read original GLB bytes for disposable corruption case", false)
		return
	bytes[0] = bytes[0] ^ 1
	var file := FileAccess.open(CORRUPTED_ASSET_PATH, FileAccess.WRITE)
	if file == null:
		_check("write disposable corrupted GLB", false)
		return
	file.store_buffer(bytes)
	file.close()
	var result := Model._load_preview_with_asset_bytes(PROFILE_PATH, CORRUPTED_ASSET_PATH)
	_check("one-byte GLB corruption is rejected against profile digest", not result.ok
		and _has_error(result.errors, "SHA-256"), str(result.errors))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CORRUPTED_ASSET_PATH))


func _check_missing_raw_asset_bytes() -> void:
	var result := Model._load_preview_with_asset_bytes(PROFILE_PATH, "user://heli25c-missing.glb")
	_check("missing raw GLB bytes fail closed", not result.ok
		and _has_error(result.errors, "unavailable for SHA-256"), str(result.errors))


func _get_binding(data: Dictionary, binding_id: String) -> Dictionary:
	for value: Variant in data.bindings:
		if value is Dictionary and value.get("id") == binding_id:
			return value
	return {}


func _has_error(errors: Array, phrase: String) -> bool:
	for error: Variant in errors:
		if String(error).contains(phrase):
			return true
	return false


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1


func _finish() -> void:
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
