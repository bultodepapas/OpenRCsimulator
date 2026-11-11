## L15c-F05/F07/F08: real flag nodes, locale loading, publication and field sampling.
extends SceneTree

const AppRoot := preload("res://app_root.gd")
const Flag := preload("res://render/flag.gd")
const FlagIdentity := preload("res://app_state/flag_identity.gd")
const FlagQuality := preload("res://render/flag_quality.gd")
const SceneDetail := preload("res://render/scene_detail.gd")
const FieldBuilder := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Windsock := preload("res://render/windsock.gd")
const World := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const ShaderClock := preload("res://render/shader_clock.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_locale := TranslationServer.get_locale()
	FlagQuality._set_override_for_tests(PackedStringArray(), "")
	FlagQuality.set_preference("basic")
	ShaderClock.register()
	await _resource_request_lifecycle()
	await _locale_and_lifecycle()
	await _quality_wind_and_basis()
	await _camera_lod()
	await _production_registration()
	await _field_observation()
	TranslationServer.set_locale(previous_locale)
	FlagQuality.set_preference("auto")
	FlagQuality._reset_override_for_tests()
	print("flag render integration: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _new_flag(position := Vector3.ZERO) -> MeshInstance3D:
	var node: MeshInstance3D = Flag.build({pivot = Vector3.ZERO}, Transform3D(Basis.IDENTITY, position), 42)
	root.add_child(node)
	return node


func _wait_country(node: MeshInstance3D, target: String) -> bool:
	# Threaded imports finish independently of the frame rate; do not block on get().
	for attempt: int in 200:
		if node.diagnostics().country == target and node.diagnostics().pending_country == "":
			return true
		await create_timer(0.01).timeout
	return false


func _wait_request(node: MeshInstance3D) -> Node:
	for attempt: int in 200:
		await process_frame
		for request: Node in get_nodes_in_group("flag_texture_requests"):
			if request.target.get_ref() == node and request.requested:
				return request
	return null


func _wait_no_requests() -> bool:
	# One frame admits deferred children; later frames complete and delete collectors.
	await process_frame
	for attempt: int in 200:
		await create_timer(0.01).timeout
		if get_nodes_in_group("flag_texture_requests").is_empty():
			return true
	return false


func _resource_request_lifecycle() -> void:
	TranslationServer.set_locale("it")
	var detached: MeshInstance3D = Flag.build({pivot = Vector3.ZERO}, Transform3D.IDENTITY, 1)
	_check("detached build starts no resource request", detached._pending.is_empty()
		and get_nodes_in_group("flag_texture_requests").is_empty())
	var detached_ref: WeakRef = weakref(detached)
	detached.free()
	_check("detached build is freed without a request collector", detached_ref.get_ref() == null and await _wait_no_requests())
	var queued: MeshInstance3D = _new_flag()
	var queued_ref: WeakRef = weakref(queued)
	_check("tree entry queues an asynchronous request", queued.diagnostics().pending_country == "IT")
	queued.free()
	_check("free before deferred request retires its collector", queued_ref.get_ref() == null and await _wait_no_requests())
	var live: MeshInstance3D = _new_flag()
	var request: Node = await _wait_request(live)
	_check("a live collector owns an actual started resource request", request != null)
	var texture_path: String = live._pending.get("front_path", "")
	var live_ref: WeakRef = weakref(live)
	var material_ref: WeakRef = weakref(live._material)
	var request_ref: WeakRef = weakref(request) if request != null else null
	live.free()
	request = null
	var drained := await _wait_no_requests()
	_check("free during request retires flag, material and collector", drained and live_ref.get_ref() == null
		and material_ref.get_ref() == null and request_ref != null and request_ref.get_ref() == null)
	_check("orphaned request leaves no retained country texture", not texture_path.is_empty() and not ResourceLoader.has_cached(texture_path))
	var replacement: MeshInstance3D = _new_flag()
	_check("same country can load after an abandoned owner", await _wait_country(replacement, "IT"))
	replacement.free()
	_check("completed request collectors retire", await _wait_no_requests())
	TranslationServer.set_locale("de")
	var removed: MeshInstance3D = _new_flag()
	var survivor: MeshInstance3D = _new_flag()
	var simultaneous := false
	for attempt: int in 200:
		await process_frame
		var owners := []
		for candidate: Node in get_nodes_in_group("flag_texture_requests"):
			if candidate.requested:
				var owner: Variant = candidate.target.get_ref()
				if owner == removed or owner == survivor:
					owners.append(owner)
		if owners.has(removed) and owners.has(survivor):
			simultaneous = true
			break
	_check("two flags can hold overlapping requests for the same country", simultaneous
		and removed.diagnostics().pending_country == "DE" and survivor.diagnostics().pending_country == "DE")
	var removed_ref: WeakRef = weakref(removed)
	removed.free()
	var survivor_loaded := await _wait_country(survivor, "DE")
	var survivor_texture: Texture2D = survivor._material.get_shader_parameter("country_texture")
	_check("freeing one overlapping requester does not cancel the survivor", removed_ref.get_ref() == null
		and survivor_loaded and survivor_texture != null
		and survivor_texture.resource_path == survivor._identity.descriptor("DE").front_path)
	_check("both overlapping request collectors retire", await _wait_no_requests())
	survivor.free()


func _locale_and_lifecycle() -> void:
	TranslationServer.set_locale("en")
	var shell: Node = AppRoot.new()
	var node: MeshInstance3D = _new_flag()
	var loaded := await _wait_country(node, "US")
	_check("real English flag texture loads", loaded)
	if loaded:
		var tex: Texture2D = node._material.get_shader_parameter("country_texture")
		_check("English shader binds requested resource", tex != null and tex.resource_path == shell._flag_identity.descriptor("US").front_path)
	node.advance_wind(0.1, [2.0, 3.0, 0.0])
	var original_motion: RefCounted = node._motion
	var prior_time: float = node._motion.simulated_time_s
	TranslationServer.set_locale("fr")
	loaded = await _wait_country(node, "FR")
	_check("locale notification loads French texture on existing node", loaded)
	if loaded:
		var desc: Dictionary = shell._flag_identity.descriptor("FR")
		var bound: Texture2D = node._material.get_shader_parameter("country_texture")
		var state: Dictionary = node.diagnostics()
		_check("country, aspect dimensions and bound texture switch together", bound != null
			and bound.resource_path == desc.front_path and is_equal_approx(state.length_m, desc.length_m)
			and is_equal_approx(state.height_m, desc.height_m)
			and node._material.get_shader_parameter("cloth_size") == Vector2(desc.length_m, desc.height_m))
		_check("locale resize retains the motion model and simulated time", node._motion == original_motion
			and node._motion.simulated_time_s == prior_time)
	# Switch while a request is still pending and leave a different final country.
	TranslationServer.set_locale("de")
	TranslationServer.set_locale("ja")
	TranslationServer.set_locale("zh_Hans")
	loaded = await _wait_country(node, "CN")
	_check("latest rapid locale selection wins after pending requests", loaded)
	if loaded:
		var tex: Texture2D = node._material.get_shader_parameter("country_texture")
		_check("rapid switch binds latest texture", tex != null and tex.resource_path == shell._flag_identity.descriptor("CN").front_path)
	TranslationServer.set_locale("es")
	var spanish: String = shell._flag_identity.country_for_locale("es")
	_check("Spanish choice is loaded from the retained shell identity", await _wait_country(node, spanish))
	original_motion = null
	var retired_node: WeakRef = weakref(node)
	var retired_material: WeakRef = weakref(node._material)
	var retired_motion: WeakRef = weakref(node._motion)
	node.free()
	_check("retired flag and its private material and motion are released", retired_node.get_ref() == null
		and retired_material.get_ref() == null and retired_motion.get_ref() == null)
	TranslationServer.set_locale("en")
	var replacement: MeshInstance3D = _new_flag()
	_check("replacement flag loads English", await _wait_country(replacement, "US"))
	TranslationServer.set_locale("es")
	_check("Spanish choice survives scene replacement and es/en/es while shell lives",
		await _wait_country(replacement, spanish) and replacement._identity == shell._flag_identity)
	for cycle: int in 4:
		var old_node: WeakRef = weakref(replacement)
		var old_material: WeakRef = weakref(replacement._material)
		replacement.free()
		_check("rebuild %d retires node and material" % cycle, old_node.get_ref() == null and old_material.get_ref() == null)
		replacement = _new_flag()
		_check("rebuild %d keeps Spanish country" % cycle, await _wait_country(replacement, spanish))
	replacement.free()
	shell.free()


func _quality_wind_and_basis() -> void:
	TranslationServer.set_locale("en")
	FlagQuality.set_preference("basic")
	var node: MeshInstance3D = _new_flag()
	_check("wind test country loads", await _wait_country(node, "US"))
	var parent := Node3D.new()
	root.add_child(parent)
	node.reparent(parent)
	parent.rotation.y = PI * 0.5
	node.rotation.y = PI * 0.5
	node.reset_wind(0.0, [0.0, 1.0, 0.0])
	_check("NED wind converts through the full world basis", node._wind.distance_to(Vector3(-1, 0, 0)) < 0.00001)
	node.advance_wind(0.1, [3.0, 4.0, -0.5])
	var before_publish: Dictionary = node.diagnostics()
	node.publish()
	var published: Dictionary = node.diagnostics()
	_check("Basic updates motion and publishes once", published.profile.mode == "basic"
		and published.motion.revision > 0 and published.uploads == before_publish.uploads + 1)
	var points: PackedVector3Array = node._material.get_shader_parameter("cloth_points")
	node.publish()
	node.advance_wind(0.1, [9.0, 8.0, 7.0])
	node.publish()
	_check("same-time pause and duplicate publication freeze the uploaded pose", node.diagnostics().motion == published.motion
		and node.diagnostics().uploads == published.uploads and node._material.get_shader_parameter("cloth_points") == points)
	var accepted_time: float = node._time
	var accepted_wind: Vector3 = node._wind
	for sample: Array in [[NAN, [1.0, 2.0, 3.0]], [-1.0, [1.0, 2.0, 3.0]], [0.2, [1.0, NAN, 3.0]], [0.2, [1.0, 2.0]]]:
		node.advance_wind(sample[0], sample[1])
		node.reset_wind(sample[0], sample[1])
		node.publish()
	_check("invalid advances and resets freeze accepted time, wind, motion and uploads", node._time == accepted_time
		and node._wind == accepted_wind and node.diagnostics().motion == published.motion and node.diagnostics().uploads == published.uploads)
	var texture: Texture2D = node._material.get_shader_parameter("country_texture")
	var basic_model: RefCounted = node._motion
	FlagQuality.set_preference("detailed")
	node.apply_quality()
	_check("live Detailed enables motion and fabric maps", node.diagnostics().profile.mode == "detailed"
		and node.needs_wind() and node._motion == basic_model and node._material.get_shader_parameter("weave_texture") != null
		and node._material.get_shader_parameter("country_texture") == texture)
	basic_model = null
	var detailed_before: Dictionary = node.diagnostics()
	node.advance_wind(0.2, [3.0, 4.0, -0.5])
	node.publish()
	_check("live Detailed accepts and publishes a later observation", node.diagnostics().motion.revision > detailed_before.motion.revision
		and node.diagnostics().uploads == detailed_before.uploads + 1)
	FlagQuality.set_preference("static")
	node.apply_quality()
	var static_points: PackedVector3Array = node._material.get_shader_parameter("cloth_points")
	_check("live Static releases motion and fabric maps without replacing country", node.diagnostics().profile.mode == "static"
		and not node.needs_wind() and node._motion == null and node._material.get_shader_parameter("weave_texture") == null
		and static_points.size() == 45 and node._material.get_shader_parameter("country_texture") == texture)
	node.advance_wind(0.2, [8.0, 2.0, 0.0])
	node.publish()
	_check("Static ignores wind and retains its pose", node._material.get_shader_parameter("cloth_points") == static_points)
	FlagQuality.set_preference("basic")
	node.apply_quality()
	_check("live Basic restores motion and retains country", node.needs_wind() and node._motion != null
		and node.diagnostics().profile.mode == "basic" and node._material.get_shader_parameter("country_texture") == texture)
	parent.free()


func _camera_lod() -> void:
	TranslationServer.set_locale("en")
	FlagQuality.set_preference("detailed")
	var previous_detail: String = SceneDetail._preference
	var previous_environment := OS.get_environment("OPENRC_SCENE_DETAIL")
	OS.set_environment("OPENRC_SCENE_DETAIL", "")
	SceneDetail.set_preference("high")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	camera.position = Vector3(0, 0, 2)
	var node: MeshInstance3D = Flag.build({pivot = Vector3.ZERO}, Transform3D.IDENTITY, 10)
	viewport.add_child(node)
	_check("1080p LOD fixture loads country", await _wait_country(node, "US"))
	_check("1080p LOD fixture uses its active camera", viewport.get_visible_rect().size == Vector2(1920, 1080)
		and viewport.get_camera_3d() == camera and node.diagnostics().profile.mode == "detailed"
		and node.diagnostics().profile.grid_x == 32)
	node.reset_wind(0.0, [1.0, 2.0, 0.0])
	node.advance_wind(0.1, [1.0, 2.0, 0.0])
	node._last_lod_time = -INF
	node.publish()
	var model: RefCounted = node._motion
	var baseline: Dictionary = node.diagnostics()
	var near_mesh: Mesh = node.mesh
	var near_vertices: PackedVector3Array = near_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check("near camera selects the 32 by 16 mesh", baseline.lod_grid == Vector2i(32, 16) and near_vertices.size() == 33 * 17)
	camera.position = Vector3(0, 0, 100)
	node._last_lod_time = -INF
	node.publish()
	var far: Dictionary = node.diagnostics()
	var far_vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check("far camera selects the 8 by 4 mesh", far.lod_grid == Vector2i(8, 4) and far_vertices.size() == 9 * 5
		and node.mesh != near_mesh)
	_check("far LOD change preserves motion and upload state", node._motion == model and far.motion == baseline.motion
		and far.motion.simulated_time_s == baseline.motion.simulated_time_s and far.motion.phase == baseline.motion.phase
		and far.uploads == baseline.uploads)
	camera.position = Vector3(0, 0, 2)
	node._last_lod_time = -INF
	node.publish()
	var returned: Dictionary = node.diagnostics()
	var returned_vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check("returning near restores the 32 by 16 mesh", returned.lod_grid == Vector2i(32, 16)
		and returned_vertices.size() == 33 * 17 and node.mesh == near_mesh)
	_check("near return preserves motion and upload state", node._motion == model and returned.motion == baseline.motion
		and returned.motion.simulated_time_s == baseline.motion.simulated_time_s and returned.motion.phase == baseline.motion.phase
		and returned.uploads == baseline.uploads)
	viewport.free()
	SceneDetail.set_preference(previous_detail)
	if previous_environment.is_empty():
		OS.unset_environment("OPENRC_SCENE_DETAIL")
	else:
		OS.set_environment("OPENRC_SCENE_DETAIL", previous_environment)


func _production_registration() -> void:
	TranslationServer.set_locale("en")
	FlagQuality.set_preference("basic")
	# Keep the production builder deterministic even when the caller has scenery overrides.
	var keys := ["OPENRC_SCENERY", "OPENRC_SCENERY_AUDIO", "OPENRC_SCENERY_BIRDS", "OPENRC_SCENERY_FILE", "OPENRC_SCENERY_QUALITY"]
	var previous := {}
	for key: String in keys:
		previous[key] = OS.get_environment(key)
	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	OS.set_environment("OPENRC_SCENERY_FILE", "")
	OS.set_environment("OPENRC_SCENERY_QUALITY", "low")
	var loaded: Dictionary = FieldLoader.load_from()
	_check("default field fixture loads", loaded.ok)
	if loaded.ok:
		var field: Node3D = FieldBuilder.build(loaded.field)
		root.add_child(field)
		var scenery := field.get_node_or_null("Scenery")
		var registered: Array = field.get_meta("wind_cues", [])
		var flag_cues: Array = scenery.get_meta("flag_cues", []) if scenery != null else []
		var socks := 0
		for cue: Node3D in registered:
			if cue.has_meta("windsock_motion"):
				socks += 1
		_check("production field registers its scenery flag and windsock", flag_cues.size() == 1
			and registered.has(flag_cues[0]) and socks == 1)
		if flag_cues.size() == 1:
			var flag: MeshInstance3D = flag_cues[0]
			_check("registered production flag loads its country", await _wait_country(flag, "US"))
			var before: Dictionary = flag.diagnostics().motion
			FieldBuilder.advance_wind(field, 0.1, [1.0, 2.0, 0.0])
			_check("registered production flag consumes a field observation", flag.diagnostics().motion.revision > before.revision)
		field.free()
	for key: String in keys:
		if str(previous[key]).is_empty():
			OS.unset_environment(key)
		else:
			OS.set_environment(key, previous[key])


func _field_observation() -> void:
	TranslationServer.set_locale("en")
	FlagQuality.set_preference("basic")
	var field := Node3D.new()
	root.add_child(field)
	field.position = Vector3(10.0, 2.0, -20.0)
	var sock: Node3D = Windsock.build({id = "test_sock", north = 0.0, east = 0.0,
		length = 2.5, pole_height = 5.0, throat_diameter = 0.6, tail_diameter = 0.3})
	field.add_child(sock)
	var first: MeshInstance3D = _new_flag(Vector3(0.0, 5.45, 0.0))
	var second: MeshInstance3D = _new_flag(Vector3(0.0, 5.45, 0.0))
	var other: MeshInstance3D = _new_flag(Vector3(2.0, 5.45, 0.0))
	FlagQuality.set_preference("static")
	var still: MeshInstance3D = _new_flag(Vector3(4.0, 5.45, 0.0))
	for flag: MeshInstance3D in [first, second, other, still]:
		flag.reparent(field, false)
		_check("field flag loads texture", await _wait_country(flag, "US"))
	field.set_meta("wind_cues", [sock, first, second, other, still])
	var samples: Array = []
	var sampler := func(point: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
		samples.append([point.duplicate(), time_s])
		return PackedFloat64Array([1.0 + point[0] * 0.01, 2.0 + point[1] * 0.01, point[2] * 0.1])
	FieldBuilder.reset_wind(field, 0.0, [99.0, 98.0, 97.0], sampler)
	_check("one observation samples two distinct world positions for four active cues", samples.size() == 2
		and samples[0][0] == PackedFloat64Array([20.0, 10.0, -7.0])
		and samples[1][0] == PackedFloat64Array([20.0, 12.0, -7.0]))
	_check("active flag receives sampled local wind, Static receives none", first._wind.distance_to(Vector3(2.1, 0.7, -1.2)) < 0.00001
		and second._wind == first._wind and other._wind.distance_to(Vector3(2.12, 0.7, -1.2)) < 0.00001
		and still._motion == null)
	var sock_motion: Variant = sock.get_meta("windsock_motion")
	var before_sock: Dictionary = sock_motion.state_snapshot()
	var before_flag: Dictionary = first.diagnostics()
	samples.clear()
	FieldBuilder.advance_wind(field, 0.1, [99.0, 98.0, 97.0], sampler)
	var advanced_flag: Dictionary = first.diagnostics()
	var advanced_sock: Dictionary = sock_motion.state_snapshot()
	_check("next accepted observation samples distinct points once and advances both cue types", samples.size() == 2
		and advanced_flag.motion.revision > before_flag.motion.revision
		and advanced_sock.simulated_step_index > before_sock.simulated_step_index)
	FieldBuilder.advance_wind(field, 0.1, [1.0, 2.0, 3.0], sampler)
	_check("duplicate observation does not resample or advance", samples.size() == 2
		and first.diagnostics().motion == advanced_flag.motion and sock_motion.state_snapshot() == advanced_sock)
	var env: Environment = Atmosphere.environment()
	env.set_meta("fw_wind_field", weakref(field))
	World.update(env, 4.0, Vector3(100.0, 200.0, 300.0))
	var uploaded: Dictionary = first.diagnostics()
	_check("World publishes committed pose without resampling or advancing", samples.size() == 2
		and uploaded.motion == advanced_flag.motion and uploaded.uploads == advanced_flag.uploads + 1
		and sock_motion.state_snapshot() == advanced_sock)
	World.update(env, 4.1, Vector3(-100.0, -200.0, -300.0))
	_check("repeated World publication does not upload or advance twice", samples.size() == 2
		and first.diagnostics().uploads == uploaded.uploads and first.diagnostics().motion == uploaded.motion
		and sock_motion.state_snapshot() == advanced_sock)
	samples.clear()
	FieldBuilder.advance_wind(field, 0.2, [NAN, 0.0, 0.0], sampler)
	World.update(env, 5.0, Vector3(9.0, 8.0, 7.0))
	_check("invalid committed fallback cannot be bypassed by sampler or World", samples.is_empty()
		and first.diagnostics().motion == uploaded.motion and sock_motion.state_snapshot() == advanced_sock)
	var invalid_sampler := func(_point: PackedFloat64Array, _time_s: float) -> PackedFloat64Array:
		return PackedFloat64Array([NAN, 0.0, 0.0])
	FieldBuilder.advance_wind(field, 0.3, [1.0, 2.0, 3.0], invalid_sampler)
	_check("invalid local samples freeze both cues instead of using fallback", first.diagnostics().motion == uploaded.motion
		and sock_motion.state_snapshot() == advanced_sock)
	field.free()
	# An invalid first receipt must claim the committed route too; World cannot replace it with raw wind.
	FlagQuality.set_preference("basic")
	var fresh := Node3D.new()
	root.add_child(fresh)
	var fresh_flag: MeshInstance3D = _new_flag()
	fresh_flag.reparent(fresh, false)
	_check("fresh field flag loads", await _wait_country(fresh_flag, "US"))
	fresh.set_meta("wind_cues", [fresh_flag])
	var fresh_before: Dictionary = fresh_flag.diagnostics()
	samples.clear()
	FieldBuilder.advance_wind(fresh, 0.4, [NAN, 0.0, 0.0], sampler)
	env.set_meta("fw_wind_field", weakref(fresh))
	World.update(env, 0.4, Vector3(20.0, 0.0, 0.0))
	_check("invalid first receipt blocks sampler and legacy World observation", samples.is_empty()
		and fresh_flag.diagnostics().motion == fresh_before.motion and fresh_flag.diagnostics().uploads == fresh_before.uploads)
	fresh.free()


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: ", label)
