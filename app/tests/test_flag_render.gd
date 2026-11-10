## L15c-F05/F07/F08: real flag nodes, locale loading, publication and field sampling.
extends SceneTree

const AppRoot := preload("res://app_root.gd")
const Flag := preload("res://render/flag.gd")
const FlagIdentity := preload("res://app_state/flag_identity.gd")
const FlagQuality := preload("res://render/flag_quality.gd")
const FieldBuilder := preload("res://render/field.gd")
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
	await _locale_and_lifecycle()
	await _quality_wind_and_basis()
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


func _locale_and_lifecycle() -> void:
	TranslationServer.set_locale("en")
	var shell: Node = AppRoot.new()
	var node: MeshInstance3D = _new_flag()
	var loaded := await _wait_country(node, "US")
	_check("real English flag texture loads", loaded)
	if loaded:
		var tex: Texture2D = node._material.get_shader_parameter("country_texture")
		_check("English shader binds requested resource", tex != null and tex.resource_path == shell._flag_identity.descriptor("US").front_path)
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
	FlagQuality.set_preference("detailed")
	node.apply_quality()
	_check("live Detailed enables motion and fabric maps", node.diagnostics().profile.mode == "detailed"
		and node.needs_wind() and node._motion != null and node._material.get_shader_parameter("weave_texture") != null
		and node._material.get_shader_parameter("country_texture") == texture)
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


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: ", label)
