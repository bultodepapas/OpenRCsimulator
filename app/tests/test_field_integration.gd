# L5: the validated field is shared by Home and flight, while each scene owns independent render nodes/resources.
# Run: godot --headless --path . --script res://tests/test_field_integration.gd
extends SceneTree

const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
const PilotCamera = preload("res://render/pilot_camera.gd")
const FieldError = preload("res://ui/field_error.gd")
const FlightSession = preload("res://sim/flight_session.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const CUSTOM_FIELD := "user://test_field_integration_custom.json"
const PREFS := "user://test_field_integration_settings.cfg"

var _failures: int = 0
var _ui: RefCounted


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_ui = UiDriver.new(self)
	_run()


func _run() -> void:
	TranslationServer.set_locale("en")
	_cleanup_files()
	var original_default: String = FileAccess.get_file_as_string(FieldLoader.DEFAULT_PATH)
	_check("default field file is readable", not original_default.is_empty())
	if original_default.is_empty():
		_finish()
		return

	_test_builder_contract()
	var custom_source: String = _custom_field_source(original_default)
	_check("custom field copy is derived from the default", not custom_source.is_empty())
	if custom_source.is_empty():
		_finish()
		return
	var custom_file: FileAccess = FileAccess.open(CUSTOM_FIELD, FileAccess.WRITE)
	_check("write only the user:// custom field copy", custom_file != null)
	if custom_file == null:
		_finish()
		return
	custom_file.store_string(custom_source)
	custom_file.close()
	var loaded_custom: Dictionary = FieldLoader.load_from(CUSTOM_FIELD)
	_check("customized field copy remains valid", bool(loaded_custom.get("ok", false)), str(loaded_custom.get("errors", [])))
	if not bool(loaded_custom.get("ok", false)):
		_finish()
		return

	await _test_home_to_fly(custom_source, original_default)
	await _test_field_error_screen()
	_check("the repository default field JSON was never changed",
		FileAccess.get_file_as_string(FieldLoader.DEFAULT_PATH) == original_default)
	_check("the app only read the temporary customized field JSON",
		FileAccess.get_file_as_string(CUSTOM_FIELD) == custom_source)
	_finish()


func _finish() -> void:
	_cleanup_files()
	TranslationServer.set_locale("en")
	print("all field integration checks passed" if _failures == 0 else "%d field integration checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _cleanup_files() -> void:
	for path: String in [CUSTOM_FIELD, PREFS]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_builder_contract() -> void:
	var validation: Dictionary = FieldLoader.validate(_overlapping_field_data())
	_check("loader accepts intentional rough/mown/runway overlap", bool(validation.get("ok", false)), str(validation.get("errors", [])))
	if not bool(validation.get("ok", false)):
		return
	var normalized: Dictionary = validation.field
	var original_normalized: String = JSON.stringify(normalized)
	var first: Node3D = FieldBuilder.build(normalized)
	var second: Node3D = FieldBuilder.build(normalized)
	_check("builder leaves normalized input unchanged", JSON.stringify(normalized) == original_normalized)
	_check("builder creates one named mesh per surface", first.get_child_count() == 3
		and first.get_node_or_null("rough") is MeshInstance3D
		and first.get_node_or_null("mown") is MeshInstance3D
		and first.get_node_or_null("runway") is MeshInstance3D)
	_check("field builder owns no camera, environment, session or collision nodes", _field_has_only_surface_meshes(first))

	var rough: MeshInstance3D = first.get_node("rough") as MeshInstance3D
	var mown: MeshInstance3D = first.get_node("mown") as MeshInstance3D
	var runway: MeshInstance3D = first.get_node("runway") as MeshInstance3D
	var rough_mesh: PlaneMesh = rough.mesh as PlaneMesh
	var mown_mesh: PlaneMesh = mown.mesh as PlaneMesh
	var runway_mesh: PlaneMesh = runway.mesh as PlaneMesh
	_check("rectangles use east-west length and north-south width",
		rough_mesh.size == Vector2(100.0, 100.0)
		and mown_mesh.size == Vector2(20.0, 20.0)
		and runway_mesh.size == Vector2(10.0, 4.0))
	_check("overlap layering gives rough < mown < runway",
		is_equal_approx(rough.position.y, 0.0)
		and is_equal_approx(mown.position.y, 0.015)
		and is_equal_approx(runway.position.y, 0.03))
	_check("every surface is drawn by the ground shader (landscape Phase 4)",
		rough.material_override is ShaderMaterial
		and mown.material_override is ShaderMaterial
		and runway.material_override is ShaderMaterial)
	var rough_material: ShaderMaterial = rough.material_override as ShaderMaterial
	var mown_material: ShaderMaterial = mown.material_override as ShaderMaterial
	var runway_material: ShaderMaterial = runway.material_override as ShaderMaterial
	_check("surface kind and rectangle are selected by surface type",
		[null, 0].has(rough_material.get_shader_parameter("surface_kind")) # unset: the shader's default, rough
		and mown_material.get_shader_parameter("surface_kind") == 1
		and runway_material.get_shader_parameter("surface_kind") == 2
		and runway_material.get_shader_parameter("rect_half") == Vector2(5.0, 2.0)
		and runway_material.get_shader_parameter("rect_center") == Vector2(runway.position.x, runway.position.z)
		and mown_material.get_shader_parameter("rect_half") == Vector2(10.0, 10.0))
	_check("overlapping surfaces remain separate resources that share the build's grass texture",
		not is_same(mown_material, runway_material) and not is_same(rough_material, mown_material)
		and is_same(rough_material.get_shader_parameter("grass"), runway_material.get_shader_parameter("grass")))
	_check("two builds create independent trees, meshes, materials and grass textures",
		_field_instances_are_independent(first, second))
	first.free()
	second.free()


func _test_home_to_fly(custom_source: String, original_default: String) -> void:
	var test_preferences: Dictionary = Preferences.DEFAULTS.duplicate(true)
	test_preferences.first_flight_hint_seen = true
	_check("save test-only preferences", Preferences.save_to(PREFS, test_preferences) == OK)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.set("user_args", PackedStringArray())
	app.set("preferences_path", PREFS)
	app.set("field_path", CUSTOM_FIELD)
	root.add_child(app)
	await _ui.settle()

	var home_scene: Node3D = app.get("home_scene") as Node3D
	var home: Control = app.get("home") as Control
	_check("interactive route opens Home with no flight", home_scene != null and home != null and app.get("flight") == null)
	if home_scene == null or home == null:
		app.queue_free()
		await _ui.settle()
		return
	var home_field: Node3D = home_scene.get_node_or_null("Field") as Node3D
	_check("Home built the field from the injected file", home_field != null and home_scene.get("field").id == "default")
	if home_field == null:
		app.queue_free()
		await _ui.settle()
		return
	_check("Home composition follows the custom pilot station and eye height",
		home_scene.get("camera").global_position.is_equal_approx(Vector3(-3.5, 2.15, -9.25))
		and home_scene.get("airplane").root.global_position.is_equal_approx(Vector3(-3.5, 3.2, -22.25)))
	var home_signature: Array[Dictionary] = _field_signature(home_field)
	var home_resource_ids: Dictionary = _field_resource_ids(home_field)
	_check("Home consumes custom runway center and dimensions", _custom_runway_is_present(home_field))
	var fly_button: Button = home.get("fly_button") as Button
	_check("Home initially focuses Fly", fly_button != null and fly_button.has_focus())
	if fly_button == null:
		app.queue_free()
		await _ui.settle()
		return

	# This uses the actual Home control and its key route, including app_root's scene transition.
	await _ui.tap(KEY_ENTER)
	var flight: Node = app.get("flight") as Node
	_check("activating Home Fly creates the flight", flight != null and app.get("home") == null and app.get("home_scene") == null)
	if flight == null:
		app.queue_free()
		await _ui.settle()
		return
	var flight_field: Node3D = flight.get_node_or_null("Field") as Node3D
	_check("flight built the same custom field geometry and materials",
		flight_field != null and _field_signature(flight_field) == home_signature)
	_check("Home and flight hold separate field trees and mutable resources",
		flight_field != null and _field_ids_are_independent(home_resource_ids, flight_field))
	_check("transition leaves exactly one field, camera and WorldEnvironment",
		_count_named(root, "Field") == 1
		and _count_type(root, "Camera3D") == 1
		and _count_type(root, "WorldEnvironment") == 1,
		"fields=%d cameras=%d environments=%d" % [_count_named(root, "Field"), _count_type(root, "Camera3D"), _count_type(root, "WorldEnvironment")])
	_check("the flight camera and environment are the active ones",
		root.get_viewport().get_camera_3d() == flight.get("_camera")
		and root.get_viewport().world_3d.environment != null
		and root.get_viewport().world_3d.environment == (flight.get("_env") as Environment))
	_check("the flight owns exactly one session", _count_script(root, FlightSession) == 1)
	_check("Home nodes are gone after the transition",
		root.find_children("Home", "", true, false).is_empty()
		and root.find_children("HomeScene", "", true, false).is_empty())

	var camera: Camera3D = flight.get("_camera") as Camera3D
	if camera != null:
		var station: Array = camera.get_meta("pilot_station", [])
		_check("custom pilot station and eye height reach the flight camera metadata",
			station.size() == 3
			and is_equal_approx(float(station[0]), 7.25)
			and is_equal_approx(float(station[1]), -6.5)
			and is_equal_approx(float(station[2]), 0.25)
			and is_equal_approx(float(camera.get_meta("pilot_eye_height", -1.0)), 2.4), str(station))
		_check("camera aim uses custom pilot coordinates and eye height",
			camera.global_position.is_equal_approx(Vector3(-6.5, 2.15, -7.25)), str(camera.global_position))
		PilotCamera.look(camera, 0.0, 0.0)
		_check("review camera defaults to the field's eye height",
			camera.position.is_equal_approx(Vector3(-6.5, 2.15, -7.25)))
		PilotCamera.look(camera, 0.0, -90.0, 30.0)
		_check("review altitude override stays above the field's pilot station",
			camera.position.is_equal_approx(Vector3(-6.5, 29.75, -7.25)))
	else:
		_check("flight has a pilot camera", false)

	_check("app did not mutate either field JSON file",
		FileAccess.get_file_as_string(FieldLoader.DEFAULT_PATH) == original_default
		and FileAccess.get_file_as_string(CUSTOM_FIELD) == custom_source)
	app.queue_free()
	await _ui.settle()


func _test_field_error_screen() -> void:
	var errors: PackedStringArray = PackedStringArray([
		"surfaces[4].width_north_south.value: test validation detail",
		"runway: unknown surface ID 'missing-runway'",
	])
	# Exercise the interactive panel directly. FieldError.report() intentionally quits headless automation on errors.
	var screen: CanvasLayer = FieldError.new(errors)
	root.add_child(screen)
	await _ui.settle()
	var detail_nodes: Array[Node] = screen.find_children("Details", "TextEdit", true, false)
	var quit_nodes: Array[Node] = screen.find_children("Quit", "Button", true, false)
	_check("field error screen shows every validation detail",
		detail_nodes.size() == 1 and (detail_nodes[0] as TextEdit).text == "\n".join(errors))
	_check("field error screen focuses its Quit button", quit_nodes.size() == 1
		and (quit_nodes[0] as Button).has_focus(), _ui.focus_name())
	var label_nodes: Array[Node] = screen.find_children("*", "Label", true, false)
	var title: Label = label_nodes[0] as Label if not label_nodes.is_empty() else null
	_check("English error title is available", title != null and title.atr(title.text) == "The field could not be loaded.")

	var locales: PackedStringArray = TranslationServer.get_loaded_locales()
	if locales.has("es"):
		TranslationServer.set_locale("es")
		await _ui.settle()
		var quit_button: Button = quit_nodes[0] as Button if not quit_nodes.is_empty() else null
		_check("imported Spanish field error strings translate",
			TranslationServer.translate("The field could not be loaded.") == "No se pudo cargar el campo."
			and TranslationServer.translate("Flight is unavailable. Restore the field data and restart the simulator.")
				== "El vuelo no está disponible. Restaura los datos del campo y reinicia el simulador."
			and TranslationServer.translate("Quit") == "Salir")
		_check("error panel controls render the Spanish title and Quit label",
			title != null and title.atr("The field could not be loaded.") == "No se pudo cargar el campo."
			and quit_button != null and quit_button.atr("Quit") == "Salir")
	else:
		print("skip Spanish control check: no imported Spanish catalog in this project load")
	screen.free()
	await _ui.settle()


func _custom_field_source(default_source: String) -> String:
	var parser: JSON = JSON.new()
	if parser.parse(default_source) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return ""
	var raw: Dictionary = (parser.data as Dictionary).duplicate(true)
	# L5 surface/elevated-pilot fixture; L6b default Home -> Fly parity has its own test.
	raw["objects"] = []
	var pilot: Dictionary = raw["pilot"]
	(pilot["north"] as Dictionary)["value"] = 7.25
	(pilot["east"] as Dictionary)["value"] = -6.5
	(pilot["down"] as Dictionary)["value"] = 0.25
	(pilot["eye_height"] as Dictionary)["value"] = 2.4
	var surfaces: Array = raw["surfaces"]
	for index: int in range(surfaces.size()):
		var surface: Dictionary = surfaces[index]
		if surface.get("id") != "runway":
			continue
		(surface["center_north"] as Dictionary)["value"] = 38.5
		(surface["center_east"] as Dictionary)["value"] = -11.25
		(surface["length_east_west"] as Dictionary)["value"] = 132.0
		(surface["width_north_south"] as Dictionary)["value"] = 18.0
		surfaces[index] = surface
	raw["surfaces"] = surfaces
	return JSON.stringify(raw, "\t")


func _overlapping_field_data() -> Dictionary:
	return {
		"format": "openrc-field v1",
		"id": "integration-overlap",
		"runway": "runway",
		"pilot": {
			"id": "pilot",
			"north": _quantity(0.0),
			"east": _quantity(0.0),
			"down": _quantity(0.0),
			"eye_height": _quantity(1.7),
		},
		"surfaces": [
			_surface("rough", "rough", 0.0, 0.0, 100.0, 100.0),
			_surface("mown", "mown", 0.0, 0.0, 20.0, 20.0),
			_surface("runway", "runway", 0.0, 0.0, 10.0, 4.0),
		],
		"objects": [],
	}


func _quantity(value: float) -> Dictionary:
	return {"value": value, "unit": "m", "kind": "estimated", "source": "field integration test"}


func _surface(id: String, kind: String, north: float, east: float, length: float, width: float) -> Dictionary:
	return {
		"id": id,
		"type": kind,
		"center_north": _quantity(north),
		"center_east": _quantity(east),
		"length_east_west": _quantity(length),
		"width_north_south": _quantity(width),
	}


func _custom_runway_is_present(field_node: Node3D) -> bool:
	var runway: MeshInstance3D = field_node.get_node_or_null("runway") as MeshInstance3D
	if runway == null or not runway.mesh is PlaneMesh:
		return false
	var plane: PlaneMesh = runway.mesh as PlaneMesh
	return plane.size == Vector2(132.0, 18.0) and runway.position.is_equal_approx(Vector3(-11.25, 0.03, -38.5))


func _field_signature(field_node: Node3D) -> Array[Dictionary]:
	var signature: Array[Dictionary] = []
	for child: Node in field_node.get_children():
		if not child is MeshInstance3D:
			continue
		var instance: MeshInstance3D = child as MeshInstance3D
		var mesh: PlaneMesh = instance.mesh as PlaneMesh
		var material: Material = instance.material_override
		var entry: Dictionary = {
			"id": instance.name,
			"size": mesh.size,
			"position": instance.position,
			"material_class": material.get_class(),
		}
		if material is StandardMaterial3D:
			var standard: StandardMaterial3D = material as StandardMaterial3D
			entry["albedo"] = standard.albedo_color
			entry["roughness"] = standard.roughness
			entry["metallic"] = standard.metallic
		elif material is ShaderMaterial:
			var shader_material: ShaderMaterial = material as ShaderMaterial
			entry["shader_path"] = shader_material.shader.resource_path
			entry["tile_m"] = shader_material.get_shader_parameter("tile_m")
			entry["surface_kind"] = shader_material.get_shader_parameter("surface_kind")
			entry["rect_center"] = shader_material.get_shader_parameter("rect_center")
			entry["rect_half"] = shader_material.get_shader_parameter("rect_half")
			var grass_texture: Texture2D = shader_material.get_shader_parameter("grass") as Texture2D
			entry["grass_size"] = grass_texture.get_size() if grass_texture != null else Vector2i.ZERO
			entry["grass_data"] = grass_texture.get_image().get_data() if grass_texture != null else PackedByteArray()
		signature.append(entry)
	return signature


func _field_instances_are_independent(first: Node3D, second: Node3D) -> bool:
	if first == null or second == null or is_same(first, second) or first.get_child_count() != second.get_child_count():
		return false
	for child: Node in first.get_children():
		var other: Node = second.get_node_or_null(NodePath(String(child.name)))
		if other == null or is_same(child, other):
			return false
		if not child is MeshInstance3D or not other is MeshInstance3D:
			return false
		var first_mesh: MeshInstance3D = child as MeshInstance3D
		var second_mesh: MeshInstance3D = other as MeshInstance3D
		if is_same(first_mesh.mesh, second_mesh.mesh) or is_same(first_mesh.material_override, second_mesh.material_override):
			return false
		var first_material: Material = first_mesh.material_override
		var second_material: Material = second_mesh.material_override
		if first_material is ShaderMaterial and second_material is ShaderMaterial:
			var first_texture: Texture2D = (first_material as ShaderMaterial).get_shader_parameter("grass") as Texture2D
			var second_texture: Texture2D = (second_material as ShaderMaterial).get_shader_parameter("grass") as Texture2D
			if first_texture == null or second_texture == null or is_same(first_texture, second_texture):
				return false
	return true


func _field_resource_ids(field_node: Node3D) -> Dictionary:
	var result: Dictionary = {"field": field_node.get_instance_id(), "surfaces": {}}
	for child: Node in field_node.get_children():
		if not child is MeshInstance3D:
			continue
		var instance: MeshInstance3D = child as MeshInstance3D
		var resource_ids: Dictionary = {
			"node": instance.get_instance_id(),
			"mesh": instance.mesh.get_instance_id(),
			"material": instance.material_override.get_instance_id(),
		}
		if instance.material_override is ShaderMaterial:
			var texture: Texture2D = (instance.material_override as ShaderMaterial).get_shader_parameter("grass") as Texture2D
			resource_ids["texture"] = texture.get_instance_id() if texture != null else 0
		result.surfaces[instance.name] = resource_ids
	return result


func _field_ids_are_independent(previous_ids: Dictionary, active_field: Node3D) -> bool:
	var active_ids: Dictionary = _field_resource_ids(active_field)
	if int(previous_ids.field) == int(active_ids.field):
		return false
	var previous_surfaces: Dictionary = previous_ids.surfaces
	var active_surfaces: Dictionary = active_ids.surfaces
	if previous_surfaces.size() != active_surfaces.size():
		return false
	for surface_id: Variant in previous_surfaces.keys():
		if not active_surfaces.has(surface_id):
			return false
		var previous: Dictionary = previous_surfaces[surface_id]
		var active: Dictionary = active_surfaces[surface_id]
		for key: String in previous.keys():
			if int(previous[key]) == int(active.get(key, -1)):
				return false
	return true


func _field_has_only_surface_meshes(field_node: Node3D) -> bool:
	for node: Node in _descendants_including_self(field_node):
		if node != field_node and not node is MeshInstance3D:
			return false
		if node is Camera3D or node is WorldEnvironment or node is CollisionObject3D or node.get_script() == FlightSession:
			return false
	return true


func _descendants_including_self(parent: Node) -> Array[Node]:
	var result: Array[Node] = [parent]
	for child: Node in parent.get_children():
		result.append_array(_descendants_including_self(child))
	return result


func _count_type(parent: Node, type_name: String) -> int:
	var count: int = 1 if parent.is_class(type_name) else 0
	for child: Node in parent.get_children():
		count += _count_type(child, type_name)
	return count


func _count_named(parent: Node, target_name: String) -> int:
	var count: int = 1 if parent.name == target_name else 0
	for child: Node in parent.get_children():
		count += _count_named(child, target_name)
	return count


func _count_script(parent: Node, target_script: Script) -> int:
	var count: int = 1 if parent.get_script() == target_script else 0
	for child: Node in parent.get_children():
		count += _count_script(child, target_script)
	return count
