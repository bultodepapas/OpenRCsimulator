extends SceneTree
## Proves that exported packages retain the separate rotorcraft runtime path and its HX-700 visual.
## Optional pack argument mounts resources before loading scripts, without starting its GDExtensions.
## Without that argument, retain the existing --main-pack invocation for host-matched checks.

var _checks := 0
var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and (args.size() != 1 or not ProjectSettings.load_resource_pack(args[0], true)):
		printerr("Could not mount rotorcraft pack: ", args)
		quit(1)
		return
	var catalog := load("res://app_state/aircraft_catalog.gd") as Script
	var rotorcraft_data := load("res://physics/rotorcraft_data.gd") as Script
	var rotor_blur := load("res://render/rotor/heli_rotor_blur.gd") as Script
	if catalog == null or rotorcraft_data == null or rotor_blur == null:
		printerr("Pack missing rotorcraft catalog, reader or rotor profile loader")
		quit(1)
		return
	var id := "xcell-60-research"
	var entry: Dictionary = catalog.entry(id)
	var data_path := str(entry.get("data", ""))
	_check("exported catalog retains the rotorcraft entry", not entry.is_empty() and catalog.is_rotorcraft(id))
	_check("exported pack contains the rotorcraft configuration", not data_path.is_empty() and FileAccess.file_exists(data_path), data_path)
	var loaded: Dictionary = rotorcraft_data.load_file(data_path)
	_check("exported rotorcraft configuration remains accepted by its strict reader", loaded.get("ok", false), str(loaded.get("errors", [])))
	_check("exported pack contains the HX-700 source model", FileAccess.file_exists("res://assets/aircraft/hx-700/hx-700.glb"))
	_check("exported pack contains hash-bound rotor profile data",
		FileAccess.file_exists("res://assets/aircraft/hx-700/rotor_profiles.json"))
	var model_script := load("res://aircraft/hx700_model.gd") as Script
	_check("exported pack contains the HX-700 runtime adapter", model_script != null)
	if model_script != null:
		var model: Dictionary = model_script.call("build")
		var root: Variant = model.get("root")
		_check("exported HX-700 visual builds its rotor bindings", root is Node3D
			and model.get("main_rotor_pivot") is Node3D and model.get("tail_rotor_pivot") is Node3D,
			str(model.keys()))
		if root is Node3D:
			var main_profile: Dictionary = rotor_blur.measured_profile(model.get("main_rotor_mount") as Node3D, root)
			var tail_profile: Dictionary = rotor_blur.measured_profile(model.get("tail_rotor") as Node3D, root)
			_check("exported pack loads static main and tail rotor profiles",
				main_profile.get("profile_source") == "verified_static_analysis"
				and tail_profile.get("profile_source") == "verified_static_analysis")
		if root is Node:
			root.free()
	print("Rotorcraft package smoke: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	printerr("FAIL: ", label, " ", detail)
