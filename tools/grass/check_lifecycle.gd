## Bounded production-route lifecycle probe for grass-quality preview qualification.
## Run from the repository root with Godot --path app --script <absolute path> -- --quality=enhanced --cycles=2 --out=<empty absolute directory>.
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const FailureConfig := preload("res://failures/config.gd")
const GroundCatalog := preload("res://vehicles/ground/vehicle_catalog.gd")
const ImportedVegetation := preload("res://scenery/imported_vegetation.gd")
const TreeAssets := preload("res://render/tree_assets.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS_BASE := "user://grass_quality_lifecycle_"
const FIXED_WING_ID := "jensen-das-ugly-stik-60"
const DEFAULT_FIELD_PATH := "res://data/fields/default.json"
const GRASS_GROUND_SHADER := "res://render/ground.gdshader"
const TREE_SHADER := "res://render/treeline.gdshader"
const IMPORTED_GRASS_SHADER := "res://scenery/imported_grass.gdshader"
const SCENERY_ENV := "OPENRC_SCENERY"
const SCENERY_AUDIO_ENV := "OPENRC_SCENERY_AUDIO"
const SCENERY_QUALITY_ENV := "OPENRC_SCENERY_QUALITY"
const GRASS_QUALITY_ENV := "OPENRC_GRASS_QUALITY"

var _options: Dictionary = {}
var _checks := 0
var _failures: Array[String] = []
var _observations: Array[Dictionary] = []
var _screenshots: Array[Dictionary] = []
var _env_original: Dictionary = {}
var _env_used: Dictionary = {}
var _preferences_path := ""
var _output_path := ""
var _app: Node
var _ui: RefCounted
var _home_node_baseline := -1
var _post_warm_object_count := -1
var _abort_run := false
var _tree_reference: Dictionary = {}
var _source_mesh_reference: Dictionary = {}
var _track_flag_diagnostics: Array[Dictionary] = []
var _quality := "default"
var _capture := false
var _headless := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_options = _parse_options(OS.get_cmdline_user_args())
	if _options.get("ok", false) != true:
		printerr(str(_options.get("error", "invalid arguments")))
		quit(2)
		return
	_quality = str(_options.quality)
	_capture = _options.capture == true
	_headless = DisplayServer.get_name() == "headless"
	if _capture and _headless:
		printerr("--capture=on requires a native display; headless lifecycle checks cannot produce render evidence.")
		quit(2)
		return
	_output_path = str(_options.out)
	if not _prepare_output(_output_path):
		printerr("Output directory must be empty: " + _output_path)
		quit(2)
		return
	if _headless:
		get_root().size = Vector2i(1280, 720)
	else:
		get_root().size = Vector2i(1280, 720)
		DisplayServer.window_set_size(Vector2i(1280, 720))
	_set_environment()
	_preferences_path = PREFS_BASE + str(OS.get_process_id()) + ".cfg"
	_clear_scratch_preferences()
	_ui = UiDriver.new(self)
	if not _write_test_preferences():
		_fail("write scratch-only deterministic Home preferences")
		await _finish()
		return
	_app = load("res://app_root.tscn").instantiate()
	if _app == null:
		_fail("instantiate production AppRoot")
		await _finish()
		return
	_app.set("user_args", PackedStringArray())
	_app.set("preferences_path", _preferences_path)
	_app.set("field_path", DEFAULT_FIELD_PATH)
	_app.set("random_seed_source", func() -> int: return 610708)
	get_root().add_child(_app)
	await _settle(12)
	if not _assert_home("startup"):
		await _finish()
		return
	_home_node_baseline = _count_nodes(_app)
	for cycle in range(int(_options.cycles)):
		if not _assert_home("cycle %d start" % (cycle + 1)):
			_abort_run = true
			break
		if cycle > 0:
			_check("Home node count remains stable after cycle %d" % cycle,
				_count_nodes(_app) == _home_node_baseline,
				"expected %d, got %d" % [_home_node_baseline, _count_nodes(_app)])
		if cycle == 0:
			await _settle(12)
			await _capture_route("home", _app.get("home_scene") as Node)
		var home_owner := _app.get("home_scene") as Node
		var home_field := _active_field(home_owner)
		_inspect_field("Home", home_owner, home_field, false, "")
		if home_field == null:
			_abort_run = true
			break
		var old_home := _weak_scene_snapshot(home_owner, home_field)
		var home_control := _app.get("home") as Control
		if home_control == null or home_control.get("fly_button") == null:
			_fail("Home exposes its production Fly button")
			_abort_run = true
			break
		(home_control.get("fly_button") as Button).pressed.emit()
		var flight := _app.get("flight") as Node
		if flight == null:
			_fail("Home Fly button launches the fixed-wing route")
			_abort_run = true
			break
		home_owner = null
		home_field = null
		home_control = null
		var flight_field := _active_field(flight)
		var flight_snapshot := _inspect_field("FixedWing", flight, flight_field, false, "")
		_check("Home and fixed-wing fields own distinct mutable render resources",
			_not_shared_ids(old_home.ids, flight_snapshot.ids))
		await _settle(12)
		if cycle == 0:
			await _capture_route("flight", flight)
		_check("departing Home scene is freed after Fly", _weak_refs_expired(old_home.refs))
		old_home = {}
		var pause := _app.get("pause_menu") as CanvasLayer
		if pause == null:
			_app.call("open_pause")
			await _settle(2)
			pause = _app.get("pause_menu") as CanvasLayer
		if pause == null or pause.get("end_button") == null:
			_fail("fixed-wing pause menu exposes End flight")
			_abort_run = true
			break
		(pause.get("end_button") as Button).pressed.emit()
		pause = null
		flight = null
		flight_field = null
		await _settle(12)
		var home_after_flight_ok := _assert_home("after fixed-wing")
		_check("End flight returns through AppRoot to Home", home_after_flight_ok)
		if not home_after_flight_ok:
			_abort_run = true
		_check("fixed-wing scene resources release on return Home", _weak_refs_expired(flight_snapshot.refs))
		flight_snapshot = {}
		if _abort_run:
			break
		for vehicle_id in GroundCatalog.IDS:
			if not _assert_home("before RC %s" % vehicle_id):
				_abort_run = true
				break
			home_owner = _app.get("home_scene") as Node
			home_field = _active_field(home_owner)
			_inspect_field("Home", home_owner, home_field, false, "")
			old_home = _weak_scene_snapshot(home_owner, home_field)
			home_control = _app.get("home") as Control
			if home_control == null or home_field == null:
				_fail("Home control exists before opening RC vehicle")
				_abort_run = true
				break
			home_control.set("ground_vehicle_id", str(vehicle_id))
			var choice := home_control.get("ground_vehicle_choice") as OptionButton
			var garage_button := home_control.get("ground_vehicle_button") as Button
			if choice == null or garage_button == null:
				_fail("Home garage exposes vehicle selector and launch button")
				_abort_run = true
				break
			choice.select(GroundCatalog.IDS.find(str(vehicle_id)))
			garage_button.pressed.emit()
			var rc_scene := _app.get("ground_vehicle") as Node3D
			if rc_scene == null:
				_fail("Home garage launches actual RC vehicle %s" % vehicle_id)
				_abort_run = true
				break
			home_owner = null
			home_field = null
			home_control = null
			choice = null
			garage_button = null
			_check("AppRoot selected requested RC vehicle %s" % vehicle_id,
				str(rc_scene.get("vehicle_id")) == str(vehicle_id))
			var rc_field := _active_field(rc_scene)
			var rc_snapshot := _inspect_field("RC", rc_scene, rc_field, true, str(vehicle_id))
			_check("Home and RC fields own distinct mutable render resources for %s" % vehicle_id,
				_not_shared_ids(old_home.ids, rc_snapshot.ids))
			await _settle(12)
			if cycle == 0:
				await _capture_route("rc-" + str(vehicle_id), rc_scene)
			_check("departing Home scene is freed after RC launch %s" % vehicle_id,
				_weak_refs_expired(old_home.refs))
			old_home = {}
			var has_home_action := rc_scene.has_method("handle_action")
			_check("RC vehicle %s returns through its real Home action" % vehicle_id, has_home_action)
			if not has_home_action:
				_abort_run = true
				break
			rc_scene.call("handle_action", "home")
			rc_field = null
			rc_scene = null
			await _settle(12)
			var rc_return_ok := _assert_home("after RC " + str(vehicle_id))
			_check("RC %s Home action returns through AppRoot" % vehicle_id, rc_return_ok)
			if not rc_return_ok:
				_abort_run = true
			_check("RC scene resources release after %s returns Home" % vehicle_id,
				_weak_refs_expired(rc_snapshot.refs))
			rc_snapshot = {}
			_check("Home node count remains at baseline after RC %s" % vehicle_id,
				_count_nodes(_app) == _home_node_baseline,
				"expected %d, got %d" % [_home_node_baseline, _count_nodes(_app)])
			if _abort_run:
				break
		if _abort_run:
			break
		if cycle == 0:
			_post_warm_object_count = Performance.get_monitor(Performance.OBJECT_COUNT)
		else:
			var current_objects := Performance.get_monitor(Performance.OBJECT_COUNT)
			_check("live Object count does not grow after warm cycle %d" % cycle,
				current_objects <= _post_warm_object_count,
				"warm=%d current=%d" % [_post_warm_object_count, current_objects])
		_observations.append({
			"cycle": cycle + 1,
			"active_route": "home",
			"node_count": _count_nodes(_app),
			"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
			"grass_quality": _quality,
		})
	await _finish()


func _parse_options(args: PackedStringArray) -> Dictionary:
	var parsed := {"quality": "default", "cycles": 2, "capture": false, "out": "", "ok": true}
	for arg in args:
		if arg == "--help":
			print("Usage: --quality=default|enhanced --cycles=1..20 --out=<empty absolute directory> [--capture=on|off]")
			return {"ok": false, "error": "help requested"}
		if not arg.begins_with("--") or not arg.contains("="):
			return {"ok": false, "error": "unexpected argument: " + arg}
		var pair := arg.trim_prefix("--").split("=", true, 1)
		match pair[0]:
			"quality":
				if pair[1] not in ["default", "enhanced"]:
					return {"ok": false, "error": "--quality must be default or enhanced"}
				parsed.quality = pair[1]
			"cycles":
				if not pair[1].is_valid_int() or int(pair[1]) < 1 or int(pair[1]) > 20:
					return {"ok": false, "error": "--cycles must be an integer from 1 to 20"}
				parsed.cycles = int(pair[1])
			"capture":
				if pair[1] not in ["on", "off"]:
					return {"ok": false, "error": "--capture must be on or off"}
				parsed.capture = pair[1] == "on"
			"out": parsed.out = pair[1]
			_: return {"ok": false, "error": "unknown argument: " + pair[0]}
	if str(parsed.out).is_empty():
		return {"ok": false, "error": "--out=<empty absolute directory> is required"}
	parsed.out = ProjectSettings.globalize_path(str(parsed.out))
	return parsed


func _prepare_output(path: String) -> bool:
	if not path.is_absolute_path():
		return false
	var error := DirAccess.make_dir_recursive_absolute(path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		return false
	var directory := DirAccess.open(path)
	return directory != null and directory.get_files().is_empty() and directory.get_directories().is_empty()


func _set_environment() -> void:
	var values := {
		GRASS_QUALITY_ENV: "" if _quality == "default" else "enhanced",
		SCENERY_ENV: "on",
		SCENERY_AUDIO_ENV: "off",
		SCENERY_QUALITY_ENV: "high",
	}
	for key: String in values:
		_env_original[key] = OS.get_environment(key)
		_env_used[key] = values[key]
		OS.set_environment(key, str(values[key]))


func _write_test_preferences() -> bool:
	var values: Dictionary = Preferences.DEFAULTS.duplicate(true)
	values.language = "en"
	values.first_flight_hint_seen = true
	values.check_updates = false
	values.aircraft = FIXED_WING_ID
	values.start_choice = "runway"
	values.time_of_day = "day"
	values.weather_config = WeatherSettings.defaults()
	values.lighting_config = TimeOfDay.defaults()
	values.sky_config = SkyConfig.defaults()
	values.failure_config = FailureConfig.defaults()
	return Preferences.save_to(_preferences_path, values) == OK


func _clear_scratch_preferences() -> void:
	for suffix in ["", ".display", ".controllers", ".legacy_rc"]:
		var absolute := ProjectSettings.globalize_path(_preferences_path + suffix)
		if FileAccess.file_exists(_preferences_path + suffix):
			DirAccess.remove_absolute(absolute)


func _assert_home(label: String) -> bool:
	var home_scene := _app.get("home_scene") as Node
	var home := _app.get("home") as Control
	var ok := home_scene != null and home != null and _app.get("flight") == null and _app.get("ground_vehicle") == null
	_check(label + ": AppRoot owns Home only", ok)
	if not ok:
		return false
	var field := _active_field(home_scene)
	if field == null:
		_check(label + ": Home contains its Field", false)
		return false
	_check(label + ": Home uses the production default field path", str(_app.get("field_path")) == DEFAULT_FIELD_PATH)
	_check(label + ": Home active camera belongs to HomeScene", _active_camera_owned_by(home_scene))
	_check(label + ": Home WorldEnvironment belongs to HomeScene", _main_view_environment_owned_by(home_scene))
	return true


func _active_field(owner: Node) -> Node3D:
	if owner == null:
		return null
	return owner.get_node_or_null("Field") as Node3D


func _inspect_field(route: String, owner: Node, field: Node3D, is_rc: bool, vehicle_id: String) -> Dictionary:
	if owner == null or field == null:
		_check(route + " active scene and Field exist", false)
		return {"ids": {}, "refs": []}
	_check(route + " field is owned by its active scene", field.get_parent() == owner)
	var near_node := field.get_node_or_null("NearGrass")
	var scenery_node := field.get_node_or_null("Scenery")
	_check(route + " field has grass and enabled scenery", near_node != null and scenery_node != null)
	if near_node == null or scenery_node == null:
		return {"ids": {}, "refs": [weakref(owner), weakref(field)]}
	var near := field.get_node_or_null("NearGrass") as Node3D
	if near == null:
		_check(route + " NearGrass is a Node3D", false)
		return {"ids": {}, "refs": [weakref(owner), weakref(field)]}
	var source_meshes := _source_grass_meshes(route, near)
	_check(route + " near grass uses the high fixed subset", str(near.get_meta("quality", "")) == "high")
	_check(route + " near grass contains retained clumps", int(near.get_meta("clumps", 0)) > 0)
	_check(route + " near grass stays within source triangle budget",
		int(near.get_meta("source_triangles", 0)) <= 50000)
	_check(route + " enhanced wind mode matches the selected quality",
		near.get_meta("grass_wind", false) == (_quality == "enhanced"))
	if _quality == "enhanced":
		_check(route + " grass-only adapter uses its qualified shader", _near_grass_uses_shader(near, IMPORTED_GRASS_SHADER))
	else:
		_check(route + " default imported grass remains on its source material", not _near_grass_uses_shader(near, IMPORTED_GRASS_SHADER))
	var ground_materials := _ground_materials(field)
	_check(route + " field exposes ground shader materials", not ground_materials.is_empty())
	var track := owner.find_child("DirtLoopSurface", true, false) as MeshInstance3D if is_rc else null
	var track_material := track.material_override as ShaderMaterial if track != null else null
	for material: ShaderMaterial in ground_materials:
		var photo_enabled: bool = material.get_shader_parameter("grass_photo_enabled") == true
		_check(route + " grass photo binder matches quality", photo_enabled == (_quality == "enhanced"))
		if not is_rc or material != track_material:
			_check(route + " ground field keeps RC track switch disabled",
				material.get_shader_parameter("rc_track_surface") != true)
	if is_rc:
		_check(route + " RC dirt binder is enabled on its field materials",
			not ground_materials.is_empty() and _all_ground_params(ground_materials, "rc_surface_enabled", true))
		_check(route + " RC field binds retained dirt/albedo maps",
			_ground_params_nonnull(ground_materials, "rc_dirt_albedo"))
		_check(route + " actual DirtLoopSurface has its RC material", track_material != null
			and str(track_material.shader.resource_path) == GRASS_GROUND_SHADER
			and track_material.get_shader_parameter("rc_track_surface") == true)
		var track_is_private := track_material != null and _only_surface_has_track_flag(owner, track)
		_check(route + " dirt track material is private to its intended surface", track_is_private,
			JSON.stringify(_track_flag_diagnostics))
	else:
		var all_ground := _ground_materials(field)
		_check(route + " non-RC route keeps RC dirt coverage disabled",
			_all_ground_params(all_ground, "rc_surface_enabled", false)
			and _all_ground_params(all_ground, "rc_track_surface", false))
		_check(route + " non-RC route leaves RC dirt maps unbound",
			_ground_params_null(all_ground, "rc_dirt_albedo"))
	if route == "FixedWing":
		_check("fixed-wing route has no Home scene or RC activity",
			_app.get("home_scene") == null and _app.get("home") == null and _app.get("ground_vehicle") == null)
		_check("fixed-wing active camera belongs to flight", _active_camera_owned_by(owner))
		_check("fixed-wing WorldEnvironment belongs to flight", _main_view_environment_owned_by(owner))
	if is_rc:
		_check("RC route has no Home or flight scene", _app.get("home_scene") == null and _app.get("home") == null
			and _app.get("flight") == null)
		_check("RC %s active camera belongs to its scene" % vehicle_id, _active_camera_owned_by(owner))
		_check("RC %s WorldEnvironment belongs to its scene" % vehicle_id, _main_view_environment_owned_by(owner))
	var tree_signature := _treeline_signature(route, field)
	if _tree_reference.is_empty():
		_tree_reference = tree_signature
	else:
		_check(route + " deterministic tree source and instance buffers match prior field builds",
			tree_signature == _tree_reference)
	var resources := _owned_field_resources(owner, field)
	_observations.append({
		"route": route,
		"vehicle_id": vehicle_id,
		"field_instance_id": field.get_instance_id(),
		"field_node_count": _count_nodes(field),
		"grass_clumps": int(near.get_meta("clumps", 0)),
		"grass_batches": int(near.get_meta("batches", near.get_child_count())),
		"grass_source_triangles": int(near.get_meta("source_triangles", 0)),
		"grass_wind": near.get_meta("grass_wind", false),
		"grass_source_meshes": source_meshes,
		"tree_signature": tree_signature,
		"owned_resource_ids": resources.ids,
		"instance_count": Performance.get_monitor(Performance.OBJECT_COUNT),
	})
	var route_refs: Array = [weakref(owner), weakref(field)]
	route_refs.append_array(resources.refs)
	return {"ids": resources.ids, "refs": route_refs}


func _source_grass_meshes(route: String, near: Node3D) -> Dictionary:
	var result: Dictionary = {}
	if near == null:
		return result
	for child: Node in near.get_children():
		if not child is MultiMeshInstance3D:
			continue
		var batch := child as MultiMeshInstance3D
		var name := str(batch.name)
		var split_at := name.find("_Part_")
		if split_at < 1 or batch.multimesh == null or batch.multimesh.mesh == null:
			_check(route + " imported grass batch has a source-part identity", false, name)
			continue
		var asset_id := name.substr(0, split_at)
		var part_text := name.substr(split_at + 6)
		if part_text.contains("_Cell_"):
			part_text = part_text.get_slice("_Cell_", 0)
		if not part_text.is_valid_int():
			_check(route + " imported grass source part index is valid", false, name)
			continue
		var part_index := int(part_text)
		var parts := ImportedVegetation.get_parts(asset_id)
		var source_mesh: Mesh = parts[part_index].get("mesh") as Mesh if part_index >= 0 and part_index < parts.size() else null
		var source_hash := _mesh_hash(source_mesh) if source_mesh != null else ""
		var draw_hash := _mesh_hash(batch.multimesh.mesh)
		var label := "%s:part_%d" % [asset_id, part_index]
		_check(route + " %s draw mesh preserves source geometry" % label,
			not source_hash.is_empty() and source_hash == draw_hash)
		result[name] = {"asset_id": asset_id, "part_index": part_index, "source_sha256": source_hash, "draw_sha256": draw_hash}
		var reference_key := "%s:part_%d" % [asset_id, part_index]
		if _source_mesh_reference.has(reference_key):
			_check(route + " %s source identity is unchanged" % reference_key,
				str(_source_mesh_reference[reference_key]) == source_hash)
		else:
			_source_mesh_reference[reference_key] = source_hash
	return result


func _treeline_signature(route: String, field: Node3D) -> Dictionary:
	var tree := field.get_node_or_null("treeline") as Node3D
	_check(route + " field has its committed treeline", tree != null)
	if tree == null:
		return {}
	var source_mesh := TreeAssets.card_mesh("CommonTree_1") as Mesh
	var source_hash := _mesh_hash(source_mesh)
	var signature: Dictionary = {}
	for child: Node in tree.get_children():
		if not child is MultiMeshInstance3D:
			continue
		var mm := (child as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null:
			continue
		var mesh_hash := _mesh_hash(mm.mesh)
		_check(route + " %s mesh preserves tree source geometry" % child.name,
			not source_hash.is_empty() and mesh_hash == source_hash)
		signature[str(child.name)] = {
			"mesh_sha256": mesh_hash,
			"instance_count": mm.instance_count,
			"buffer_sha256": _hash_value(mm.buffer),
			"bounds": _hash_value([mm.custom_aabb.position, mm.custom_aabb.size]),
		}
	return signature


func _ground_materials(owner: Node) -> Array[ShaderMaterial]:
	var found: Array[ShaderMaterial] = []
	var seen: Dictionary = {}
	if owner == null:
		return found
	for node: Node in _all_nodes(owner):
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh != null:
				for surface in mesh_instance.mesh.get_surface_count():
					_add_ground_material(mesh_instance.get_active_material(surface), found, seen)
		elif node is MultiMeshInstance3D:
			var multi_instance := node as MultiMeshInstance3D
			var multi := multi_instance.multimesh
			if multi != null and multi.mesh != null:
				for surface in multi.mesh.get_surface_count():
					var active_material: Material = multi_instance.material_override
					if active_material == null:
						active_material = multi.mesh.surface_get_material(surface)
					_add_ground_material(active_material, found, seen)
	return found


func _add_ground_material(value: Variant, found: Array[ShaderMaterial], seen: Dictionary) -> void:
	if not value is ShaderMaterial:
		return
	var material := value as ShaderMaterial
	if material.shader == null or str(material.shader.resource_path) != GRASS_GROUND_SHADER:
		return
	var id := material.get_instance_id()
	if seen.has(id):
		return
	seen[id] = true
	found.append(material)


func _all_ground_params(materials: Array[ShaderMaterial], parameter: String, expected: bool) -> bool:
	if materials.is_empty():
		return false
	for material: ShaderMaterial in materials:
		var enabled: bool = material.get_shader_parameter(parameter) == true
		if enabled != expected:
			return false
	return true


func _ground_params_nonnull(materials: Array[ShaderMaterial], parameter: String) -> bool:
	if materials.is_empty():
		return false
	for material: ShaderMaterial in materials:
		if material.get_shader_parameter(parameter) == null:
			return false
	return true


func _ground_params_null(materials: Array[ShaderMaterial], parameter: String) -> bool:
	if materials.is_empty():
		return false
	for material: ShaderMaterial in materials:
		if material.get_shader_parameter(parameter) != null:
			return false
	return true


func _only_surface_has_track_flag(owner: Node, expected_surface: MeshInstance3D) -> bool:
	_track_flag_diagnostics.clear()
	if owner == null or expected_surface == null:
		return false
	if expected_surface.mesh == null or expected_surface.mesh.get_surface_count() == 0:
		return false
	var expected_material := expected_surface.get_active_material(0) as ShaderMaterial
	if expected_material == null:
		return false
	var count := 0
	for node: Node in _all_nodes(owner):
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh != null:
				for surface_index in mesh_instance.mesh.get_surface_count():
					var active_material := mesh_instance.get_active_material(surface_index)
					if _track_flag_enabled(active_material):
						count += 1
						_track_flag_diagnostics.append({
							"node": str(mesh_instance.get_path()),
							"material_id": (active_material as Resource).get_instance_id(),
							"expected_node": mesh_instance == expected_surface,
							"expected_material": active_material == expected_material,
						})
						if mesh_instance != expected_surface or active_material != expected_material:
							return false
		elif node is MultiMeshInstance3D:
			var multi_instance := node as MultiMeshInstance3D
			var multi := multi_instance.multimesh
			if multi != null and multi.mesh != null:
				for surface_index in multi.mesh.get_surface_count():
					var active_material: Material = multi_instance.material_override
					if active_material == null:
						active_material = multi.mesh.surface_get_material(surface_index)
					if _track_flag_enabled(active_material):
						_track_flag_diagnostics.append({
							"node": str(node.get_path()),
							"material_id": (active_material as Resource).get_instance_id(),
							"expected_node": false,
							"expected_material": active_material == expected_material,
						})
						return false
	return count == 1


func _track_flag_enabled(value: Variant) -> bool:
	if not value is ShaderMaterial:
		return false
	var material := value as ShaderMaterial
	return (material.shader != null and str(material.shader.resource_path) == GRASS_GROUND_SHADER
		and material.get_shader_parameter("rc_track_surface") == true)


func _near_grass_uses_shader(near: Node3D, shader_path: String) -> bool:
	if near == null:
		return false
	var found := false
	for child: Node in near.get_children():
		if not child is MultiMeshInstance3D:
			continue
		var mm := (child as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null:
			continue
		for surface in mm.mesh.get_surface_count():
			var material := mm.mesh.surface_get_material(surface) as ShaderMaterial
			if material == null or material.shader == null or str(material.shader.resource_path) != shader_path:
				return false
			found = true
	return found


func _owned_field_resources(owner: Node, field: Node3D) -> Dictionary:
	var ids: Dictionary = {}
	var refs: Array = []
	var seen: Dictionary = {}
	for node: Node in _all_nodes(owner):
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			var private_mesh := mesh_instance.name == "DirtLoopSurface" or mesh_instance.get_parent() == field.get_node_or_null("treeline")
			if private_mesh and mesh_instance.mesh != null:
				_add_owned_resource(mesh_instance.mesh, ids, refs, seen)
			if mesh_instance.mesh != null:
				for surface in mesh_instance.mesh.get_surface_count():
					_add_owned_material(mesh_instance.get_active_material(surface), ids, refs, seen)
		elif node is MultiMeshInstance3D:
			var multi_instance := node as MultiMeshInstance3D
			var mm := multi_instance.multimesh
			if mm == null or mm.mesh == null:
				continue
			var parent := node.get_parent()
			if parent == field.get_node_or_null("NearGrass") or parent == field.get_node_or_null("treeline"):
				_add_owned_resource(mm.mesh, ids, refs, seen)
			for surface in mm.mesh.get_surface_count():
				var active_material: Material = multi_instance.material_override
				if active_material == null:
					active_material = mm.mesh.surface_get_material(surface)
				_add_owned_material(active_material, ids, refs, seen)
	return {"ids": ids, "refs": refs}


func _add_owned_material(value: Variant, ids: Dictionary, refs: Array, seen: Dictionary) -> void:
	if not value is ShaderMaterial:
		return
	var material := value as ShaderMaterial
	if material.shader == null:
		return
	var path := str(material.shader.resource_path)
	if path not in [GRASS_GROUND_SHADER, TREE_SHADER, IMPORTED_GRASS_SHADER]:
		return
	_add_owned_resource(material, ids, refs, seen)


func _add_owned_resource(resource: Resource, ids: Dictionary, refs: Array, seen: Dictionary) -> void:
	var id := resource.get_instance_id()
	if seen.has(id):
		return
	seen[id] = true
	ids[id] = resource.get_class()
	refs.append(weakref(resource))


func _weak_scene_snapshot(owner: Node, field: Node3D) -> Dictionary:
	var resources := _owned_field_resources(owner, field)
	var refs: Array = [weakref(owner), weakref(field)]
	refs.append_array(resources.refs)
	return {"ids": resources.ids, "refs": refs}


func _not_shared_ids(previous: Dictionary, current: Dictionary) -> bool:
	for id: Variant in previous.keys():
		if current.has(id):
			return false
	return true


func _weak_refs_expired(refs: Array) -> bool:
	for reference: Variant in refs:
		if reference is WeakRef and (reference as WeakRef).get_ref() != null:
			return false
	return true


func _active_camera_owned_by(owner: Node) -> bool:
	var camera := get_root().get_camera_3d()
	return camera != null and _is_descendant(camera, owner)


func _main_view_environment_owned_by(owner: Node) -> bool:
	for node: Node in _all_nodes(owner):
		if node is WorldEnvironment and node.get_viewport() == get_root():
			return true
	return false


func _is_descendant(node: Node, ancestor: Node) -> bool:
	var cursor := node
	while cursor != null:
		if cursor == ancestor:
			return true
		cursor = cursor.get_parent()
	return false


func _capture_route(label: String, owner: Node) -> void:
	if not _capture or owner == null:
		return
	await RenderingServer.frame_post_draw
	var viewport_image := get_root().get_texture().get_image()
	if viewport_image == null or viewport_image.is_empty():
		_fail("capture native viewport for " + label)
		return
	var filename := label.replace("/", "-") + ".png"
	var path := _output_path.path_join(filename)
	var save_error := viewport_image.save_png(path)
	_check("save first-cycle %s screenshot at 1280x720" % label,
		save_error == OK and viewport_image.get_size() == Vector2i(1280, 720),
		"size=%s error=%d" % [str(viewport_image.get_size()), save_error])
	if save_error == OK:
		_screenshots.append({
			"route": label,
			"path": path,
			"width": viewport_image.get_width(),
			"height": viewport_image.get_height(),
			"sha256": _sha256_bytes(viewport_image.get_data()),
			"settle_frames": 12,
			"framing": _framing_snapshot(owner),
		})


func _framing_snapshot(owner: Node) -> Dictionary:
	var framing: Dictionary = {}
	var camera := get_root().get_camera_3d()
	if camera != null:
		framing.camera = {
			"path": str(camera.get_path()),
			"position": _vector3_array(camera.global_position),
			"rotation_degrees": _vector3_array(camera.global_rotation_degrees),
			"basis": [
				_vector3_array(camera.global_basis.x),
				_vector3_array(camera.global_basis.y),
				_vector3_array(camera.global_basis.z),
			],
			"fov_degrees": camera.fov,
			"projection": camera.projection,
		}
	var owner_vehicle_id: Variant = owner.get("vehicle_id") if owner != null else null
	if owner_vehicle_id is String and not (owner_vehicle_id as String).is_empty():
		framing.vehicle_id = owner_vehicle_id
		var visual_value: Variant = owner.get("visual")
		if visual_value is Dictionary:
			var visual_root := (visual_value as Dictionary).get("root") as Node3D
			if visual_root != null:
				framing.vehicle_root = {
					"path": str(visual_root.get_path()),
					"position": _vector3_array(visual_root.global_position),
					"rotation_degrees": _vector3_array(visual_root.global_rotation_degrees),
				}
	return framing


func _vector3_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _settle(frames: int) -> void:
	for _index in range(frames):
		await process_frame


func _mesh_hash(mesh: Mesh) -> String:
	if mesh == null:
		return ""
	var surfaces: Array = []
	for index in mesh.get_surface_count():
		surfaces.append(mesh.surface_get_arrays(index))
	return _hash_value(surfaces)


func _hash_value(value: Variant) -> String:
	return _sha256_bytes(var_to_bytes(value))


func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


func _all_nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child: Node in node.get_children():
		result.append_array(_all_nodes(child))
	return result


func _count_nodes(node: Node) -> int:
	return _all_nodes(node).size() if node != null else 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		var failure := label + (" :: " + detail if not detail.is_empty() else "")
		_failures.append(failure)
		printerr("FAIL ", failure)


func _fail(label: String) -> void:
	_check(label, false)


func _finish() -> void:
	if _app != null and is_instance_valid(_app):
		await _ui.close_app(_app)
		_app = null
	var summary := {
		"format": "openrc-grass-lifecycle-v1",
		"date": "2026-10-18",
		"quality": _quality,
		"cycles_requested": int(_options.get("cycles", 0)),
		"sequence": ["Home", "fixedwing", "Home", "mt8-bisonte", "Home", "monster-car-2", "Home"],
		"renderer": DisplayServer.get_name(),
		"headless": _headless,
		"capture_requested": _capture,
		"capture_scope": "first cycle only; 12 process-frame settle per route. Home is the startup menu, fixedwing is startup waiting for radio, and both RC scenes are paused. Images verify lifecycle/framing only, not active flight/driving or visual preference acceptance.",
		"viewport_target": {"width": 1280, "height": 720},
		"environment_used": _env_used,
		"home_preferences": {"path": _preferences_path, "aircraft": FIXED_WING_ID, "time_of_day": "day", "weather": "validated calm defaults", "first_flight_hint_seen": true},
		"node_count_home_baseline": _home_node_baseline,
		"object_count_after_first_cycle": _post_warm_object_count,
		"checks": _checks,
		"failed_checks": _failures,
		"observations": _observations,
		"screenshots": _screenshots,
		"qualification": "scene lifecycle and material/mesh ownership only; not a visual preference, complete-session, or performance qualification",
	}
	var report_path := _output_path.path_join("lifecycle.json")
	var report := FileAccess.open(report_path, FileAccess.WRITE)
	var result_code := 1 if not _failures.is_empty() else 0
	if report == null:
		printerr("Could not write lifecycle manifest: " + report_path)
		result_code = 1
	else:
		report.store_string(JSON.stringify(summary, "\t"))
		report.flush()
		report.close()
	for key: String in _env_original:
		var original := str(_env_original[key])
		if original.is_empty():
			OS.unset_environment(key)
		else:
			OS.set_environment(key, original)
	_clear_scratch_preferences()
	print("grass lifecycle: %d checks, %d failed; report=%s" % [_checks, _failures.size(), report_path])
	quit(result_code)
