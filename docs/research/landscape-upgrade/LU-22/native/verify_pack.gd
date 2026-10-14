extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
	else:
		print("ok   ", label)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_check("PCK path was supplied", not args.is_empty())
	if args.is_empty():
		_finish()
		return
	var pck_path := args[0]
	_check("Windows PCK mounts into empty project", ProjectSettings.load_resource_pack(pck_path, true))
	var required := [
		"res://data/fields/lake.json",
		"res://assets/landscape/vegetation/catalog.json",
		"res://assets/landscape/vegetation/LICENSE.txt",
		"res://assets/landscape/vegetation/impostors/bush_common_4view.json",
		"res://assets/landscape/vegetation/impostors/bush_common_flowers_4view.json",
		"res://assets/landscape/trees/catalog.json",
		"res://assets/landscape/trees/LICENSE.txt",
		"res://assets/landscape/UPGRADE_CREDITS.md",
		"res://assets/audio/water/LICENSES.md",
		"res://assets/audio/water/peludo-splash1.wav.import",
		"res://assets/audio/water/peludo-splash2.wav.import",
		"res://assets/audio/water/randommind-vistula-short.mp3.import",
		"res://render/lake/water.gdshader",
		"res://render/lake/bank.gdshader",
		"res://assets/landscape/vegetation/impostors/bush_common_4view.gdshader",
	]
	for path: String in required:
		_check("PCK contains " + path, FileAccess.file_exists(path))
	var water_shader: Resource = load("res://render/lake/water.gdshader")
	var bank_shader: Resource = load("res://render/lake/bank.gdshader")
	var hedge_shader: Resource = load("res://assets/landscape/vegetation/impostors/bush_common_4view.gdshader")
	_check("water shader loads from the PCK", water_shader is Shader)
	_check("bank shader loads from the PCK", bank_shader is Shader)
	_check("packed hedge impostor shader loads", hedge_shader is Shader)
	_check("packed hedge shader uses diffuse lighting with no specular", hedge_shader is Shader and (hedge_shader as Shader).code.contains("ROUGHNESS = 1.0;") and (hedge_shader as Shader).code.contains("SPECULAR = 0.0;"))
	var water_material_script: GDScript = load("res://render/lake/water_material.gd") as GDScript
	_check("compiled water material adapter loads from the PCK", water_material_script != null)
	var loader_script: GDScript = load("res://data/lake_loader.gd") as GDScript
	var loaded_lake: Dictionary = loader_script.load_from("res://data/fields/lake.json") if loader_script != null else {}
	_check("packed lake loader reads the included source definition", loaded_lake.get("ok", false))
	var water_material: Variant = water_material_script.call("create", loaded_lake.get("lake", {}), {}) \
		if water_material_script != null and loaded_lake.get("ok", false) else null
	_check("packed material adapter builds the Compatibility water shader",
		water_material is ShaderMaterial and water_material.shader == water_shader)

	var water_fx_script: GDScript = load("res://render/lake/water_effects.gd") as GDScript
	_check("compiled water-effects script loads from the PCK", water_fx_script != null)
	if water_fx_script != null and loaded_lake.get("ok", false):
		var packed_effects: Node = water_fx_script.new()
		root.add_child(packed_effects)
		var fx_constants: Dictionary = water_fx_script.get_script_constant_map()
		var configured_fx: bool = packed_effects.configure(loaded_lake.lake, false)
		var began_fx: bool = packed_effects.begin({"trigger": "water", "tick": 1,
			"point_ned": PackedFloat64Array([110.0, 120.0, 0.45])})
		packed_effects.update(0.24, false)
		var plume: MeshInstance3D = packed_effects.get("_plume") as MeshInstance3D
		var plume_height: float = plume.global_transform.basis.y.length() * 0.36 if plume != null else -1.0
		var plume_material: ShaderMaterial = packed_effects.get("_plume_material") as ShaderMaterial
		var plume_tint: Color = plume_material.get_shader_parameter("tint") if plume_material != null else Color.BLACK
		_check("PCK water FX has the pale 0.85 m plume and 0.82 s phase", configured_fx and began_fx
			and is_equal_approx(float(fx_constants.get("PLUME_DURATION_S", -1.0)), 0.82)
			and is_equal_approx(plume_height, 0.85)
			and plume_tint.is_equal_approx(Color(0.72, 0.84, 0.81, 0.42)))
		packed_effects.free()
	for path: String in [
		"res://assets/audio/water/peludo-splash1.wav",
		"res://assets/audio/water/peludo-splash2.wav",
		"res://assets/audio/water/randommind-vistula-short.mp3",
	]:
		_check("water audio resource loads: " + path, load(path) is AudioStream)
	var catalog_file := FileAccess.open("res://assets/landscape/vegetation/catalog.json", FileAccess.READ)
	var catalog: Variant = JSON.parse_string(catalog_file.get_as_text()) if catalog_file != null else null
	var assets: Array = catalog.get("assets", []) if catalog is Dictionary else []
	var plant_scenes_loaded := 0
	for asset: Dictionary in assets:
		var path := str(asset.get("scene", asset.get("mesh", "")))
		var resource: Resource = load(path) if not path.is_empty() else null
		_check("PCK stores import metadata for plant scene: " + str(asset.get("id", path)),
			FileAccess.file_exists(path + ".import"))
		_check("catalog plant source loads from PCK: " + str(asset.get("id", path)), resource != null)
		if resource != null:
			plant_scenes_loaded += 1
	_check("all 15 source plant scenes load", plant_scenes_loaded == 15)
	_check("unit test sources remain excluded", not FileAccess.file_exists("res://tests/test_water_checkpoint.gd"))
	var main_scene := load("res://main.tscn") as PackedScene
	_check("actual Main scene loads from the PCK", main_scene != null)
	if main_scene != null:
		var flight: Node = main_scene.instantiate()
		flight.set("interactive_start", true)
		root.add_child(flight)
		await process_frame
		var session: Variant = flight.get("session")
		var aircraft_id: String = str(flight.get("aircraft_id"))
		var can_fly: bool = bool(session.call("is_flyable")) if session is Object and session.has_method("is_flyable") else false
		var aircraft_data: Dictionary = session.get("aircraft") if session is Object else {}
		print("MAIN-FLYABILITY ticks=", ProjectSettings.get_setting("physics/common/physics_ticks_per_second", -1), " aircraft_id=", aircraft_id, " is_flyable=", can_fly, " aircraft.ok=", aircraft_data.get("ok", false), " start_error=", session.get("start_error") if session is Object else "", " pause_reason=", session.get("pause_reason") if session is Object else "", " errors=", aircraft_data.get("errors", []))
		_check("default interactive Main has a valid flight session", can_fly and bool(aircraft_data.get("ok", false)) and str(aircraft_id) != "")
		var field: Variant = flight.get("_field_node")
		var scene_lake: Dictionary = field.get_meta("lake_context", {}) if field is Node else {}
		var session_lake: Dictionary = session.call("lake_context") if session is Object and session.has_method("lake_context") else {}
		_check("actual Main scene builds the normalized lake field context",
			field is Node3D and not scene_lake.is_empty() and str(scene_lake.get("identity", "")).length() == 64)
		_check("actual FlightSession loads and matches the lake context",
			session is Object and not session_lake.is_empty()
				and session_lake.get("identity", "") == scene_lake.get("identity", ""))
		flight.queue_free()
		await process_frame
	_finish()

func _finish() -> void:
	print("EMPTY-PCK: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)