extends SceneTree

const Shadow := preload("res://render/shadow.gd")
const ShadowSettings := preload("res://render/shadow_settings.gd")
const Projected := preload("res://render/projected_shadow.gd")


class ShadowStartupProbe extends "res://main.gd":
	const ShadowAPI := preload("res://render/shadow.gd")
	var observed_mode := "not-built"
	var observed_texture := false
	var observed_representation := ""
	var observed_projector := false

	func _build_world() -> bool:
		observed_mode = _shadow_mode
		var carrier := ShadowAPI.create(self, _shadow_mode)
		observed_texture = (carrier.material_override as StandardMaterial3D).albedo_texture != null
		var model := Node3D.new()
		var body := MeshInstance3D.new()
		body.mesh = BoxMesh.new()
		model.add_child(body)
		add_child(model)
		ShadowAPI.bind_model(carrier, model, {}, {}, _shadow_mode)
		var geometry: Dictionary = carrier.get_meta("projected_shadow_geometry", {})
		observed_representation = str(geometry.get("representation", ""))
		observed_projector = carrier.get_node_or_null("ProjectedShadow") != null
		return false # Stop before flight setup; interactive start does not quit.


var checks := 0
var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_global_disabled_and_local_override()
	_test_saved_off_visibility_and_reuse()
	_test_enabled_bind_remains_eager()
	_test_initial_cue_override()
	await _test_flight_startup_order()
	await _test_freed_source()
	await _test_detached_source()
	_test_pending_snapshot_and_visibility()
	_test_rebind_latest_source()
	_test_precomputed_shape()
	_test_legacy_fallback()
	_select("auto", "auto")
	print("deferred aircraft shadow: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		printerr("FAIL: ", label)


func _select(technique: String, cue: String) -> void:
	ShadowSettings.apply({shadow_technique = technique, shadow_aircraft_cue = cue})


func _host() -> Node3D:
	var host := Node3D.new()
	root.add_child(host)
	return host


func _triangle_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.4, 0.1, -0.3), Vector3(0.5, 0.2, -0.2), Vector3(0.0, 0.6, 0.8),
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _two_triangle_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.4, 0.1, -0.3), Vector3(0.5, 0.2, -0.2), Vector3(0.0, 0.6, 0.8),
		Vector3(0.5, 0.2, -0.2), Vector3(0.8, 0.7, 0.4), Vector3(0.0, 0.6, 0.8),
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _model(parent: Node, mesh: Mesh) -> Node3D:
	var model := Node3D.new()
	model.name = "Aircraft"
	var instance := MeshInstance3D.new()
	instance.name = "Body"
	instance.mesh = mesh
	model.add_child(instance)
	if parent != null: parent.add_child(model)
	return model


func _projector(carrier: MeshInstance3D) -> Node:
	return carrier.get_node_or_null("ProjectedShadow")


func _pending_mesh_ref(carrier: MeshInstance3D) -> WeakRef:
	var policy := carrier.get_meta("shadow_cue_policy") as Node
	var pending: Dictionary = policy.get("pending")
	var shape: Dictionary = pending.get("shape", {})
	return weakref(shape.get("mesh"))


func _representation(carrier: MeshInstance3D) -> String:
	var geometry: Dictionary = carrier.get_meta("projected_shadow_geometry", {})
	return str(geometry.get("representation", ""))


func _material(carrier: MeshInstance3D) -> StandardMaterial3D:
	return carrier.material_override as StandardMaterial3D


func _update(carrier: MeshInstance3D, cue: String = "auto", strength: float = 1.0) -> void:
	Shadow.update(carrier, Basis.IDENTITY, Vector3(1, 3, 2), 2.0, 2.0, Vector3(0.4, 0.8, -0.3).normalized(), strength, cue)


func _projector_ready(carrier: MeshInstance3D) -> bool:
	var projector := _projector(carrier)
	if projector == null: return false
	var viewport := projector.get("viewport") as SubViewport
	var receiver := projector.get("receiver") as MeshInstance3D
	return viewport != null and receiver != null and receiver.visible


func _test_global_disabled_and_local_override() -> void:
	_select("native", "sun")
	var host := _host()
	var model := _model(host, BoxMesh.new())
	var carrier := Shadow.create(host)
	_check(_material(carrier).albedo_texture == null, "globally disabled create avoids fallback texture")
	Shadow.bind_model(carrier, model)
	_check(_projector(carrier) == null and _representation(carrier) == "deferred", "global Native defers the projector at bind")
	for i in 3: _update(carrier, "sun")
	_check(_projector(carrier) == null and _material(carrier).albedo_texture == null, "local Sun cannot bypass global Native")
	_update(carrier, "off")
	_select("projected", "off")
	_check(_projector(carrier) == null, "enabling projected route with an Off cue stays deferred")
	_update(carrier, "sun")
	_check(_projector_ready(carrier) and _representation(carrier) == "full", "local Sun activates deferred shadow despite saved Off")
	host.free()


func _test_saved_off_visibility_and_reuse() -> void:
	_select("projected", "off")
	var host := _host()
	var model := _model(host, BoxMesh.new())
	var carrier := Shadow.create(host)
	_check(_material(carrier).albedo_texture == null, "saved Off avoids fallback texture at create")
	Shadow.bind_model(carrier, model)
	_check(_projector(carrier) == null and _representation(carrier) == "deferred", "saved Off defers projector and viewport")
	for i in 3: _update(carrier, "off")
	_update(carrier, "auto")
	_update(carrier, "sun", 0.0)
	_check(_projector(carrier) == null and _material(carrier).albedo_texture == null, "Off and zero-strength updates do not allocate a projector")
	carrier.visible = false
	_update(carrier, "sun")
	_check(_projector(carrier) == null, "hidden carrier does not allocate a projector")
	_update(carrier, "off")
	carrier.visible = true
	model.visible = false
	_update(carrier, "sun")
	_check(_projector(carrier) == null, "hidden source does not allocate a projector")
	_update(carrier, "off")
	model.visible = true
	_update(carrier, "vertical")
	var projector := _projector(carrier)
	_check(_projector_ready(carrier) and _representation(carrier) == "full", "first visible local override creates the full projector")
	if projector != null:
		var viewport := projector.get("viewport") as SubViewport
		var receiver := projector.get("receiver") as MeshInstance3D
		var mask := projector.get("mask_material") as ShaderMaterial
		_check(viewport != null and receiver != null and mask != null and mask.get_shader_parameter("light_direction") == Vector3.UP, "materialized viewport, receiver and local Vertical cue are active")
		_update(carrier, "off")
		_check(_projector(carrier) == projector and receiver != null and not receiver.visible and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "turning cue Off retains and hides the warm projector")
		_update(carrier, "sun")
		_check(_projector(carrier) == projector and projector.get("viewport") == viewport and receiver.visible, "re-enabling reuses the same projector and viewport")
		_select("native", "sun")
		_check(_projector(carrier) == projector and not receiver.visible, "global suppression keeps the warm projector hidden")
		_select("projected", "sun")
		_check(_projector(carrier) == projector and receiver.visible, "global re-enable reuses the warm projector")
	host.free()


func _test_enabled_bind_remains_eager() -> void:
	_select("projected", "sun")
	var host := _host()
	var model := _model(host, BoxMesh.new())
	var carrier := Shadow.create(host)
	Shadow.bind_model(carrier, model)
	var projector := _projector(carrier)
	_check(projector != null and _representation(carrier) == "full", "enabled bind still eagerly builds the projector")
	if projector != null:
		_check(projector.get("viewport") is SubViewport and projector.get("receiver") is MeshInstance3D, "eager projector creates the viewport and receiver")
		_update(carrier, "sun")
		_check(_projector_ready(carrier), "enabled eager projector displays on update")
	host.free()


func _test_initial_cue_override() -> void:
	_select("projected", "sun")
	var host := _host()
	var model := _model(host, BoxMesh.new())
	var carrier := Shadow.create(host, "off")
	_check(_material(carrier).albedo_texture == null and _material(carrier).albedo_color.a == 0.0, "explicit initial Off avoids fallback texture despite saved Sun")
	Shadow.bind_model(carrier, model, {}, {}, "off")
	_check(_projector(carrier) == null and _representation(carrier) == "deferred", "explicit initial Off defers projector despite saved Sun")
	_update(carrier, "off")
	_check(_projector(carrier) == null, "an Off update keeps the explicitly disabled projector deferred")
	_update(carrier, "sun")
	_check(_projector_ready(carrier) and _representation(carrier) == "full", "later local Sun materializes the explicitly deferred projector")
	host.free()
	for cue: String in ["sun", "vertical"]:
		_select("projected", "off")
		host = _host()
		model = _model(host, BoxMesh.new())
		carrier = Shadow.create(host, cue)
		_check(_material(carrier).albedo_texture != null, "explicit initial cue creates fallback texture despite saved Off: " + cue)
		Shadow.bind_model(carrier, model, {}, {}, cue)
		_check(_projector(carrier) != null and _representation(carrier) == "full", "explicit initial cue eagerly binds despite saved Off: " + cue)
		_update(carrier, cue)
		_check(_projector_ready(carrier), "explicit initial cue becomes visible on update: " + cue)
		host.free()
	for technique: String in ["native", "off"]:
		_select(technique, "sun")
		host = _host()
		model = _model(host, BoxMesh.new())
		carrier = Shadow.create(host, "sun")
		_check(_material(carrier).albedo_texture == null and _material(carrier).albedo_color.a == 0.0, "global route vetoes explicit initial Sun at create: " + technique)
		Shadow.bind_model(carrier, model, {}, {}, "sun")
		_update(carrier, "sun")
		_check(_projector(carrier) == null and _representation(carrier) == "deferred", "global route vetoes explicit initial Sun at bind and update: " + technique)
		host.free()


func _test_flight_startup_order() -> void:
	var cases: Array[Dictionary] = [
		{name = "explicit Off, no checkpoint", saved = "sun", argument = "--shadow=off", checkpoint = false, mode = "off"},
		{name = "saved Off, staged checkpoint", saved = "off", argument = "", checkpoint = true, mode = "off"},
		{name = "explicit Sun overrides saved Off", saved = "off", argument = "--shadow=sun", checkpoint = true, mode = "sun"},
		{name = "saved Sun, no checkpoint", saved = "sun", argument = "", checkpoint = false, mode = "sun"},
	]
	for entry: Dictionary in cases:
		_select("projected", entry.saved)
		var flight := ShadowStartupProbe.new()
		flight.interactive_start = true
		var args := PackedStringArray(["--scripted"])
		if not String(entry.argument).is_empty(): args.append(entry.argument)
		flight.set_user_args(args)
		var checkpoint_calls := {count = 0}
		if entry.checkpoint:
			flight.startup_checkpoint = func(_label: String) -> bool:
				checkpoint_calls.count += 1
				return true
		await flight._prepare_flight()
		_check(flight.observed_mode == entry.mode and flight.startup_error.is_empty(), "flight resolves shadow mode before world construction: " + entry.name)
		_check((int(checkpoint_calls.count) > 0) == bool(entry.checkpoint), "flight reaches the selected checkpoint path: " + entry.name)
		var enabled: bool = entry.mode != "off"
		_check(flight.observed_texture == enabled and flight.observed_projector == enabled and flight.observed_representation == ("full" if enabled else "deferred"), "world construction receives the resolved cue: " + entry.name)
		flight.free()


func _test_freed_source() -> void:
	_select("projected", "off")
	var host := _host()
	var model := _model(host, BoxMesh.new())
	var source_ref: WeakRef = weakref(model)
	var carrier := Shadow.create(host)
	Shadow.bind_model(carrier, model)
	var policy := carrier.get_meta("shadow_cue_policy") as Node
	var mesh_ref := _pending_mesh_ref(carrier)
	_check(mesh_ref != null and mesh_ref.get_ref() != null, "deferred binding retains its captured mesh")
	model.free()
	_check(source_ref.get_ref() == null, "deferred binding does not retain a freed source")
	await process_frame
	await process_frame
	_check(ShadowSettings.aircraft_cue() == "off" and (policy.get("pending") as Dictionary).is_empty(), "pending state is cleared while the saved cue remains Off")
	_check(mesh_ref.get_ref() == null, "captured mesh is released after the source is freed")
	_check(_representation(carrier) == "unavailable" and _projector(carrier) == null and _material(carrier).albedo_texture == null, "expired source becomes unavailable without allocating rendering resources")
	_select("projected", "sun")
	_update(carrier, "sun")
	_check(_projector(carrier) == null and (carrier.mesh == null or _material(carrier).albedo_color.a == 0.0), "freed source cannot materialize a projector or visible legacy ghost")
	_check(_representation(carrier) == "unavailable", "freed bound source reports unavailable instead of generic fallback")
	_check(_material(carrier).albedo_texture == null, "freed source does not allocate a fallback texture")
	host.free()


func _test_detached_source() -> void:
	_select("projected", "off")
	var host := _host()
	var model := _model(null, BoxMesh.new())
	var carrier := Shadow.create(host)
	Shadow.bind_model(carrier, model)
	var policy := carrier.get_meta("shadow_cue_policy") as Node
	var mesh_ref := _pending_mesh_ref(carrier)
	await process_frame
	await process_frame
	_check(not (policy.get("pending") as Dictionary).is_empty() and mesh_ref != null and mesh_ref.get_ref() != null, "detached but live source retains its pending shape while Off")
	_check(_projector(carrier) == null and _representation(carrier) == "deferred" and _material(carrier).albedo_texture == null, "detached live source stays deferred without rendering resources")
	_select("projected", "sun")
	_update(carrier, "sun")
	_check(_projector(carrier) == null, "detached source waits without materializing a live carrier")
	host.add_child(model)
	var projector := _projector(carrier)
	_check(_projector_ready(carrier), "reattached source immediately replays the pending visible update")
	if projector != null:
		var receiver := projector.get("receiver") as MeshInstance3D
		var viewport := projector.get("viewport") as SubViewport
		host.remove_child(model)
		_check(receiver != null and viewport != null and not receiver.visible and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "detaching materialized source hides the projector")
		host.add_child(model)
		_check(receiver.visible and _projector(carrier) == projector, "reattaching restores the existing projector")
	host.free()


func _test_pending_snapshot_and_visibility() -> void:
	_select("projected", "off")
	var host := _host()
	var dynamic_mesh := _two_triangle_mesh()
	var model := _model(host, dynamic_mesh)
	var body := model.get_node("Body") as MeshInstance3D
	var original: Dictionary = Projected.collect(model)
	var carrier := Shadow.create(host)
	Shadow.bind_model(carrier, model)
	_check(_projector(carrier) == null and _representation(carrier) == "deferred" and _material(carrier).albedo_texture == null, "bind snapshot does not construct a projector or fallback texture")
	# In-place surface replacement must not alter the already-collected shape.
	dynamic_mesh.clear_surfaces()
	var replacement := _triangle_mesh()
	dynamic_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, replacement.surface_get_arrays(0))
	var mutated: Dictionary = Projected.collect(model)
	_check(int(original.triangles) == 2 and int(mutated.triangles) == 1, "fixture changes a source ArrayMesh in place after bind")
	# Later transform changes, resource replacement and added geometry also must
	# not change the already-collected neutral silhouette.
	body.position = Vector3(7, 3, -2)
	body.rotation.y = 0.5
	body.mesh = _triangle_mesh()
	var added := _model(model, BoxMesh.new())
	added.position = Vector3(-8, 2, 3)
	var changed: Dictionary = Projected.collect(model)
	_check(changed.triangles != original.triangles and var_to_bytes(changed.bounds) != var_to_bytes(original.bounds), "post-bind geometry differs from the captured baseline")
	model.visible = false
	_update(carrier, "sun")
	_check(_projector(carrier) == null, "hidden pending source delays materialization")
	model.visible = true
	var projector := _projector(carrier)
	_check(_projector_ready(carrier), "source becoming visible immediately replays the pending update")
	if projector != null:
		var viewport := projector.get("viewport") as SubViewport
		var proxy_nodes: Array = viewport.find_children("*", "MeshInstance3D", true, false) if viewport != null else []
		_check(int(projector.get("triangle_count")) == int(original.triangles) and var_to_bytes(projector.get("bounds")) == var_to_bytes(original.bounds), "deferred projector keeps bind-time count and full bounds")
		_check(proxy_nodes.size() == 1 and (proxy_nodes[0] as MeshInstance3D).mesh.get_faces().to_byte_array() == original.mesh.get_faces().to_byte_array(), "deferred proxy retains bind-time mesh and transformed face stream")
	host.free()


func _test_rebind_latest_source() -> void:
	_select("projected", "off")
	var host := _host()
	var first := _model(host, BoxMesh.new())
	var latest := _model(host, _triangle_mesh())
	var carrier := Shadow.create(host)
	Shadow.bind_model(carrier, first)
	Shadow.bind_model(carrier, latest)
	first.free()
	_check(_projector(carrier) == null and _representation(carrier) == "deferred", "rebind replaces pending source without creating a projector")
	_select("projected", "sun")
	_update(carrier, "sun")
	var projector := _projector(carrier)
	_check(projector != null and projector.get("source") == latest and int(projector.get("triangle_count")) == 1, "deferred rebind materializes only the latest model")
	_check(_representation(carrier) == "full", "latest model records its materialized representation")
	host.free()


func _test_precomputed_shape() -> void:
	_select("projected", "off")
	var host := _host()
	var model := _model(host, BoxMesh.new())
	var carrier := Shadow.create(host)
	var original_mesh := _triangle_mesh()
	var box := AABB(Vector3(-2, -3, -4), Vector3(5, 6, 7))
	var shape := {mesh = original_mesh, bounds = box, triangles = 1, representation = "imported-lod-proxy", source_triangles = 12, lod_surfaces = 1, max_lod_distance = 0.0005}
	var context := {stock_session = true, model_manifest_sha256 = "1".repeat(64)}
	Shadow.bind_model(carrier, model, shape, context)
	shape = {}
	context.model_manifest_sha256 = "2".repeat(64)
	_check(_projector(carrier) == null and _representation(carrier) == "deferred", "precomputed shape does not create a projector while Off")
	_select("projected", "sun")
	_update(carrier, "sun")
	var projector := _projector(carrier)
	_check(projector != null and int(projector.get("triangle_count")) == 1 and projector.get("bounds") == box, "deferred bind preserves supplied shape and bounds")
	var geometry: Dictionary = carrier.get_meta("projected_shadow_geometry", {})
	_check(geometry.get("representation") == "imported-lod-proxy" and int(geometry.get("source_triangles", -1)) == 12 and int(geometry.get("lod_surfaces", -1)) == 1 and geometry.get("model_manifest_sha256") == "1".repeat(64), "deferred bind preserves precomputed proxy provenance and bind-time context")
	if projector != null:
		var viewport := projector.get("viewport") as SubViewport
		var proxy_nodes: Array = viewport.find_children("*", "MeshInstance3D", true, false) if viewport != null else []
		_check(proxy_nodes.size() == 1 and (proxy_nodes[0] as MeshInstance3D).mesh == original_mesh, "projector uses the retained precomputed mesh")
	host.free()


func _test_legacy_fallback() -> void:
	for with_empty_model in [false, true]:
		_select("projected", "off")
		var host := _host()
		var carrier := Shadow.create(host)
		if with_empty_model:
			var empty := Node3D.new()
			host.add_child(empty)
			Shadow.bind_model(carrier, empty)
		_check(_material(carrier).albedo_texture == null and _projector(carrier) == null, "legacy carrier starts without texture or projector: " + str(with_empty_model))
		_select("projected", "sun")
		_update(carrier, "sun")
		var texture := _material(carrier).albedo_texture
		_check(_projector(carrier) == null and texture != null and carrier.mesh == carrier.get_meta("legacy_shadow_mesh") and _material(carrier).albedo_color.a > 0.0, "unbound or empty source lazily restores visible legacy cue: " + str(with_empty_model))
		if texture != null:
			var image := texture.get_image()
			_check(image != null and image.get_data() == Shadow.silhouette().get_data(), "lazy legacy texture exactly matches the canonical silhouette: " + str(with_empty_model))
		if with_empty_model:
			_check(_representation(carrier) == "legacy", "empty-model materialization reports the legacy representation")
		host.free()
