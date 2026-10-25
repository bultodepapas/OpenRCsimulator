# UI-05-R2: bounded Home-only visual reuse, eviction, hidden models and ownership.
extends SceneTree
var _checks := 0
var _failures := 0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var script: Script = load("res://ui/home_scene.gd")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--home="): script = load(arg.trim_prefix("--home="))
	var home: Node3D = script.new()
	root.add_child(home)
	await process_frame
	var stik: Node3D = home.airplane.root
	var stik_ref: WeakRef = weakref(stik)
	home.show_aircraft("gp-extra-300s-60")
	var extra: Node3D = home.airplane.root
	home.show_aircraft("sebart-avanti-s-a200-p100rx")
	var jet: Node3D = home.airplane.root
	_check("only the current aircraft is visible", not stik.visible and not extra.visible and jet.visible)
	_check("retained aircraft cannot process", stik.process_mode == Node.PROCESS_MODE_DISABLED and extra.process_mode == Node.PROCESS_MODE_DISABLED)
	_check("at most three models are retained", home._preview_models.size() == 3)
	var pose := extra.transform
	home.show_aircraft("gp-extra-300s-60")
	_check("returning to Extra reuses its root", home.airplane.root == extra)
	_check("returning preserves pose and resumes visibility", extra.transform == pose and extra.visible and extra.process_mode == Node.PROCESS_MODE_INHERIT)
	_check("the old selected model is hidden", not jet.visible)
	for repeat in range(4): home.show_aircraft("gp-extra-300s-60")
	_check("same selection reuses its model", home.airplane.root == extra)
	await process_frame
	await process_frame
	_check("only one projected shadow is attached", home._shadow.get_child_count() == 1)
	var geometry: Dictionary = home._preview_geometry["gp-extra-300s-60"]
	var projected: Node = home._shadow.get_child(0)
	_check("projection uses the retained neutral shape", projected.bounds == geometry.shape.bounds and projected.triangle_count == geometry.shape.triangles)
	var fresh: Dictionary = load("res://render/airplane.gd").build("gp-extra-300s-60")
	var fresh_shape: Dictionary = load("res://render/projected_shadow.gd").collect(fresh.root)
	_check("retained shadow vertices equal a fresh model", geometry.shape.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == fresh_shape.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	_check("retained shadow bounds equal a fresh model", geometry.shape.bounds == fresh_shape.bounds)
	fresh.root.free()
	fresh.clear()
	fresh_shape.clear()
	geometry = {} # Do not let the measurement retain a GPU mesh through renderer shutdown.
	home.show_aircraft("turbo-lumber-evolution")
	await process_frame
	await process_frame
	_check("least recently used Stik is freed", stik_ref.get_ref() == null)
	_check("recent Extra remains retained", is_instance_valid(extra) and home._preview_models.size() == 3)
	home.show_aircraft("xcell-60-research")
	_check("helicopter selection preserves its visual identity", home.airplane.visual_family == "hx-700" and home.airplane.root.visible)
	home.show_aircraft("gp-extra-300s-60")
	_check("airplane returns after helicopter without reconstruction", home.airplane.root == extra)
	var refs: Array[WeakRef] = []
	for model: Dictionary in home._preview_models.values(): refs.append(weakref(model.root))
	home.free()
	await process_frame
	await process_frame
	for ref in refs: _check("Home frees retained models", ref.get_ref() == null)
	await _corsair_light_layouts(script)
	print("Home preview cache: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _corsair_light_layouts(script: Script) -> void:
	var lights := load("res://render/world/aircraft_lights.gd")
	var lighting: Dictionary = load("res://environment/time_of_day_config.gd").defaults()
	lighting.mode = "astronomical"
	lighting.local_seconds = 20 * 3600
	var field_path: String = load("res://data/field_loader.gd").DEFAULT_PATH
	var home: Node3D = script.new("f4u-corsair-250", field_path, lighting)
	root.add_child(home)
	await process_frame
	var first_kit: Node3D = home.airplane.root.get_node("NightKit")
	var shared: Dictionary = first_kit.get_meta("geometry_layout")
	_check("cached layout contains compact measurements only", var_to_bytes(shared).size() < 16384)
	var original_key: String = script._light_layout_key(home.airplane)
	var prop: Node3D = home.airplane.propeller
	var original_pose := prop.transform
	prop.rotation.z += 0.1
	_check("different propeller pose cannot share measurements", script._light_layout_key(home.airplane) != original_key)
	prop.transform = original_pose
	prop.scale *= 1.1
	_check("different propeller scale cannot share measurements", script._light_layout_key(home.airplane) != original_key)
	prop.transform = original_pose
	var old_identity: String = home.airplane.model_manifest_sha256
	home.airplane.model_manifest_sha256 = "different-revision"
	_check("different manifest cannot share measurements", script._light_layout_key(home.airplane) != original_key)
	home.airplane.model_manifest_sha256 = old_identity
	home.airplane.root.set_meta("light_anchors", {landing = {position = Vector3(0.1, 0.2, 0.3)}})
	_check("authored landing seat invalidates the fallback layout", script._light_layout_key(home.airplane) != original_key)
	home.airplane.root.remove_meta("light_anchors")
	_check("restoring anchor policy restores layout identity", script._light_layout_key(home.airplane) == original_key)
	var original_world: Transform3D = home.airplane.root.transform
	home.airplane.root.position += Vector3(1, 2, 3)
	_check("world position does not invalidate model-local measurements", script._light_layout_key(home.airplane) == original_key)
	home.airplane.root.transform = original_world
	var previous: WeakRef = weakref(first_kit)
	for record: Dictionary in home.airplane.model_manifest.liveries:
		var start := Time.get_ticks_usec()
		home.show_aircraft("f4u-corsair-250", record.id)
		var show_us := Time.get_ticks_usec() - start
		var model_root: Node3D = home.airplane.root
		var kit: Node3D = model_root.get_node("NightKit")
		_check(record.id + " owns a distinct kit", previous.get_ref() != kit)
		_check(record.id + " shares compact measurements", is_same(kit.get_meta("geometry_layout"), shared))
		model_root.remove_child(kit)
		start = Time.get_ticks_usec()
		var fresh: Dictionary = lights.prepare_layout(model_root)
		var fresh_us := Time.get_ticks_usec() - start
		_check(record.id + " fresh measurements match cached values exactly", var_to_bytes(fresh) == var_to_bytes(shared))
		# Flight's ordinary attach path owns its measurements and resolves crash
		# hosts against this model, never against another retained preview.
		var independent: Node3D = lights.attach(model_root)
		_check(record.id + " default attach owns its measurements", not is_same(independent.get_meta("geometry_layout"), shared))
		var identical := kit.get_child_count() == independent.get_child_count()
		for light: Node3D in kit.get_children():
			var other := independent.get_node_or_null(NodePath(str(light.name))) as Node3D
			identical = identical and other != null
			if other == null: continue
			identical = identical and light.transform == other.transform and light.get_meta("crash_follow", NodePath()) == other.get_meta("crash_follow", NodePath())
			if light is MeshInstance3D:
				identical = identical and light.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == other.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		_check(record.id + " reused kit matches fresh light geometry and crash hosts", identical)
		independent.free()
		model_root.add_child(kit)
		lights.set_mode(kit, "nav")
		_check(record.id + " mode remains local to each kit", previous.get_ref() == null or previous.get_ref().get_meta("mode") == "all")
		lights.set_mode(kit, "all")
		_check(record.id + " cache remains bounded", home._preview_models.size() <= 3 and home._preview_geometry.size() <= 3)
		print("Corsair layout %s: show %.2f ms, uncached tracing %.2f ms" % [record.id, show_us / 1000.0, fresh_us / 1000.0])
		previous = weakref(kit)
		await process_frame
	# Authored seats remain specific to the receiving model even when fallback
	# geometry measurements came from a different paint's root.
	var model_root: Node3D = home.airplane.root
	var old_kit: Node3D = model_root.get_node("NightKit")
	model_root.remove_child(old_kit)
	var seat := Vector3(0.1, 0.2, 0.3)
	model_root.set_meta("light_anchors", {landing = {position = seat}, nav_left = {position = -seat}})
	var anchored: Node3D = lights.attach(model_root, shared)
	_check("reused geometry applies the receiving model's authored seats", anchored.get_node("landing_light").position == seat and anchored.get_node("nav_left").position == -seat)
	anchored.free()
	model_root.remove_meta("light_anchors")
	model_root.add_child(old_kit)
	home.free()
	# A fresh daylight Home must not pay for a layout it will not display.
	lighting.local_seconds = 12 * 3600
	home = script.new("f4u-corsair-250", field_path, lighting)
	root.add_child(home)
	_check("daylight does not prepare a night layout", home.airplane.root.get_node_or_null("NightKit") == null and not home._preview_geometry.values()[0].has("light_layout"))
	home.free()
	await process_frame
func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)
