# L2: one source of truth for sky, fog, ground and sun (headless, no GPU), and the haze's physics.
# Run: godot --headless --path . --script res://tests/test_atmosphere.gd
extends SceneTree

const Spec := preload("res://spec.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Ground := preload("res://render/ground.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const SkyAppearance := preload("res://render/weather/sky_appearance.gd")
const CloudTransport := preload("res://render/weather/cloud_transport.gd")
const LAYERED_CLOUD_UNIFORMS: Array[StringName] = [
	&"appearance_layer_count", &"appearance_layer_parameters", &"appearance_layer_motion",
	&"appearance_layer_seeds", &"appearance_cloud_density",
]

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _v(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


func _initialize() -> void:
	# UI-06d: the calibrated L1-L4 comparison selects its original shadow-off reference explicitly.
	Atmosphere.engine_shadows = false
	# A standalone field/pack can build ground before any sky has registered the cloud global.
	var ground: ShaderMaterial = Ground.grass_material()
	var env := Atmosphere.environment()
	var sky: ShaderMaterial = env.sky.sky_material
	var holder := Node3D.new()
	root.add_child(holder)
	var sun := Atmosphere.create_sun(holder)

	# Engine fog settings: exponential haze, the sky draws the haze itself, aerial perspective (a no-op) off.
	_check("exponential fog", env.fog_enabled and env.fog_mode == Environment.FOG_MODE_EXPONENTIAL)
	# (Environment stores fog settings as float32: compare relative to that precision.)
	_check("density = 3.912 / visibility", absf(env.fog_density / (3.912 / Spec.ATMOSPHERE.visibility_m) - 1.0) < 1e-6, str(env.fog_density))
	_check("fog_sky_affect = 0, fog_aerial_perspective = 0, no height fog", env.fog_sky_affect == 0.0 and env.fog_aerial_perspective == 0.0 and env.fog_height_density == 0.0)

	# One colour formula: the engine's fog colour, the sky's horizon and the ground's fog share every term.
	var haze_lin := _v(env.fog_light_color.srgb_to_linear()) * env.fog_light_energy
	var sun_lin := _v(sun.light_color.srgb_to_linear()) * sun.light_energy * PI
	for m in [[sky, "sky"], [ground, "ground"]]:
		var mat: ShaderMaterial = m[0]
		_check("%s haze = engine fog colour (linear)" % m[1], (mat.get_shader_parameter("haze_lin") as Vector3).is_equal_approx(haze_lin), str(mat.get_shader_parameter("haze_lin")))
		_check("%s sun scatter = engine fog_sun_scatter" % m[1], absf(mat.get_shader_parameter("sun_scatter") - env.fog_sun_scatter) < 1e-6)
		_check("%s sun term = light colour · energy · π" % m[1], (mat.get_shader_parameter("sun_lin") as Vector3).is_equal_approx(sun_lin))
		_check("%s sun direction = the light's basis z (1e-6)" % m[1], (mat.get_shader_parameter("sun_dir") as Vector3).distance_to(sun.transform.basis.z) < 1e-6,
			"%s vs %s" % [mat.get_shader_parameter("sun_dir"), sun.transform.basis.z])
	_check("ground fog density = engine fog density", absf(ground.get_shader_parameter("beta") - env.fog_density) < 1e-9)

	# L3: the off reference and the on path retain the same haze sun term.
	_check("engine shadows explicitly off for the reference", not sun.shadow_enabled and Atmosphere.light_energy() == Spec.ATMOSPHERE.sun_energy)
	var product_off: float = Atmosphere.light_energy() * Atmosphere.sun_scatter()
	Atmosphere.engine_shadows = true
	var sun2 := Atmosphere.create_sun(holder)
	var env2 := Atmosphere.environment()
	_check("engine shadows: PSSM 2 splits to 300 m, energy × compensation", sun2.shadow_enabled and sun2.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		and sun2.directional_shadow_max_distance == Spec.ATMOSPHERE.shadow_max_distance_m and absf(sun2.light_energy - Spec.ATMOSPHERE.sun_energy * Spec.ATMOSPHERE.shadow_energy_compat) < 1e-6)
	_check("engine shadows: fog sun term (energy × scatter) unchanged", absf(Atmosphere.light_energy() * Atmosphere.sun_scatter() - product_off) < 1e-9
		and absf(env2.fog_sun_scatter * sun2.light_energy - product_off) < 1e-5)
	Atmosphere.engine_shadows = false

	# L4 clouds: the drift is quantised to cloud_update_s of simulation, wrapped to the noise period, and the sky is
	# only touched when it actually changes (each change re-renders the radiance).
	var step: float = Spec.ATMOSPHERE.cloud_update_s
	_check("clouds: same offset within one update interval", Atmosphere.cloud_offset(10.0) == Atmosphere.cloud_offset(10.0 + 0.99 * step))
	_check("clouds: new offset at the next interval", Atmosphere.cloud_offset(10.0) != Atmosphere.cloud_offset(10.0 + step))
	var drift: Vector2 = Spec.ATMOSPHERE.cloud_drift_cells_per_s
	var off := Atmosphere.cloud_offset(123.0)
	_check("clouds: offset inside one noise period", off.x >= 0.0 and off.x < Atmosphere.CLOUD_PERIOD and off.y >= 0.0 and off.y < Atmosphere.CLOUD_PERIOD)
	_check("clouds: offset = drift × quantised time, wrapped", off.is_equal_approx(Vector2(fposmod(drift.x * 123.0, 64.0), fposmod(drift.y * 123.0, 64.0))))
	var env3 := Atmosphere.environment()
	_check("clouds: first update at t = 5 s changes the sky", Atmosphere.update_clouds(env3, 5.0))
	_check("clouds: the same interval again does not", not Atmosphere.update_clouds(env3, 5.5))

	# L4b/L15d: one field and one quantised displacement for sky and every ground surface.
	for uniform_name: String in ["cloud_seed", "cloud_scale", "cloud_coverage", "cluster_strength"]:
		_check("clouds: ground shares sky " + uniform_name, ground.get_shader_parameter(uniform_name) == sky.get_shader_parameter(uniform_name))
	_check("clouds: bounded production cloud shadow", float(ground.get_shader_parameter("cloud_shadow_strength")) > 0.0
		and float(ground.get_shader_parameter("cloud_shadow_strength")) <= 0.3)
	_check("clouds: 1500 m deck estimate", ground.get_shader_parameter("cloud_deck_m") == 1500.0)
	_check("clouds: grading remains off", not env.adjustment_enabled)
	for t: float in [0.0, 5.0, 5.9, 1023.0, 1024.0, 16000.0, 864000000.0, 0.0]:
		Atmosphere.update_clouds(env3, t)
		_check("clouds: sky and ground agree at t=%s" % t, (env3.sky.sky_material as ShaderMaterial).get_shader_parameter("cloud_offset") == Atmosphere.last_cloud_offset
			and Atmosphere.last_cloud_offset == Atmosphere.cloud_offset(t))
	# Rendering clock wrapping must not reset a cloud field whose period is much longer than 1024 s.
	_check("clouds: continuous across render clock wrap", Atmosphere.cloud_offset(1024.0).distance_to(Atmosphere.cloud_offset(1023.0)) < 0.01)
	Atmosphere.update_clouds(env3, 5.0)
	var fresh_env := Atmosphere.environment()
	var fresh_sky: ShaderMaterial = fresh_env.sky.sky_material
	_check("clouds: fresh environment preserves displacement", Atmosphere.last_cloud_offset == Atmosphere.cloud_offset(5.0)
		and fresh_sky.get_shader_parameter("cloud_offset") == Atmosphere.cloud_offset(5.0))
	var existing_sky: ShaderMaterial = env3.sky.sky_material
	var existing_offset: Variant = existing_sky.get_shader_parameter("cloud_offset")
	_check("clouds: flight reset reanchors displacement at zero",
		Atmosphere.configure_appearance(Atmosphere.appearance_config()) and Atmosphere.last_cloud_offset == Vector2.ZERO)
	_check("clouds: existing sky restores ground without changing its uniform", Atmosphere.update_clouds(env3, 5.0)
		and Atmosphere.last_cloud_offset == Atmosphere.cloud_offset(5.0)
		and existing_sky.get_shader_parameter("cloud_offset") == existing_offset)
	Atmosphere.update_clouds(fresh_env, 0.0)
	_check("clouds: replay reset restores exact zero", Atmosphere.last_cloud_offset == Vector2.ZERO)

	# Geometry: the ground reaches the rim, and the camera sees past it.
	_check("ground half-size ≥ rim end", Spec.GROUND_SIZE / 2.0 >= Spec.ATMOSPHERE.rim_end_m)
	_check("camera far ≥ 1.05 × rim end", Spec.CAMERA.far >= 1.05 * Spec.ATMOSPHERE.rim_end_m)

	# Physics (64-bit mirror of the shaders): 23 km visibility leaves 0.90 / 0.71 / 0.43 of an object's contrast at
	# 600 m / 2 km / 5 km (investigation 02), and ~3 % at the 20 km rim.
	for case in [[600.0, 0.90], [2000.0, 0.71], [5000.0, 0.43]]:
		_check("transmittance at %.0f m ≈ %.2f" % case, absf(Atmosphere.transmittance(case[0]) - case[1]) < 0.005, "%.4f" % Atmosphere.transmittance(case[0]))
	_check("transmittance at the rim ≤ 4 %", Atmosphere.transmittance(Spec.ATMOSPHERE.rim_end_m) <= 0.04, "%.4f" % Atmosphere.transmittance(Spec.ATMOSPHERE.rim_end_m))

	_test_layered_cloud_cache()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _test_layered_cloud_cache() -> void:
	var selection: Dictionary = SkyConfig.for_preset("broken")
	selection["seed"] = 4703
	selection["motion"] = "follow_wind"
	var mean_wind := [7.0, -3.0, 0.4]
	_check("layered cloud profile is accepted", Atmosphere.configure_appearance(selection, mean_wind, 0.0))
	var checked: Dictionary = SkyConfig.validate(selection)
	var resolved: Dictionary = SkyAppearance.resolve(checked.profile, checked.config)
	var transport: Dictionary = Atmosphere.cloud_transport_checkpoint()
	var environment: Environment = Atmosphere.environment()
	var step := float(Spec.ATMOSPHERE.cloud_update_s)

	var later_time := step * 5.2
	_check("new cloud interval changes layered sky", Atmosphere.update_clouds(environment, later_time))
	_check_layered_uniforms("later interval", environment, resolved, transport, later_time)
	_check_cloud_snapshot_offsets("later interval", resolved, transport, later_time)
	var same_interval_time := step * 5.8
	_check("same cloud interval leaves layered sky unchanged", not Atmosphere.update_clouds(environment, same_interval_time))
	_check_layered_uniforms("same interval", environment, resolved, transport, same_interval_time)

	var rewind_time := step * 1.3
	_check("clock rewind changes layered sky", Atmosphere.update_clouds(environment, rewind_time))
	_check_layered_uniforms("clock rewind", environment, resolved, transport, rewind_time)
	_check_cloud_snapshot_offsets("clock rewind", resolved, transport, rewind_time)
	var before_rejection: Dictionary = Atmosphere.cloud_state_snapshot()
	var invalid_selection: Dictionary = selection.duplicate(true)
	invalid_selection["preset"] = "missing-profile"
	_check("invalid cloud profile is rejected", not Atmosphere.configure_appearance(invalid_selection, mean_wind, 0.0))
	_check("rejected profile preserves selection", Atmosphere.appearance_config() == selection)
	_check("rejected profile preserves detached snapshot", Atmosphere.cloud_state_snapshot() == before_rejection)
	_check_layered_uniforms("after rejected profile", environment, resolved, transport, rewind_time)

	# Switching to an empty profile and back at the same time detects stale packed-array and offset caches.
	var clear_selection: Dictionary = SkyConfig.for_preset("clear")
	_check("clear profile is accepted", Atmosphere.configure_appearance(clear_selection, mean_wind, 0.0))
	var clear_checked: Dictionary = SkyConfig.validate(clear_selection)
	var clear_resolved: Dictionary = SkyAppearance.resolve(clear_checked.profile, clear_checked.config)
	var clear_transport: Dictionary = Atmosphere.cloud_transport_checkpoint()
	_check_cloud_snapshot_offsets("clear-profile invalidation", clear_resolved, clear_transport, 0.0)
	Atmosphere.update_clouds(environment, 0.0)
	_check_layered_uniforms("clear profile", environment, clear_resolved, clear_transport, 0.0)
	_check("layered profile is accepted again", Atmosphere.configure_appearance(selection, mean_wind, 0.0))
	checked = SkyConfig.validate(selection)
	resolved = SkyAppearance.resolve(checked.profile, checked.config)
	transport = Atmosphere.cloud_transport_checkpoint()
	_check_cloud_snapshot_offsets("layered-profile invalidation", resolved, transport, 0.0)
	Atmosphere.update_clouds(environment, 0.0)
	_check_layered_uniforms("layered profile after clear", environment, resolved, transport, 0.0)

	var restore_transport: Dictionary = CloudTransport.build(checked.config, resolved.cloud_layers,
		[8.0, 2.0, 0.0], step * 3.0, step, Spec.ATMOSPHERE.cloud_drift_cells_per_s,
		[Vector2(7.0, 11.0), Vector2(17.0, 23.0), Vector2(29.0, 31.0)],
		float(Spec.ATMOSPHERE.cloud_deck_m) / maxf(float(Spec.ATMOSPHERE.cloud_scale), 1.0e-6))
	_check("restore fixture is valid", CloudTransport.validate(restore_transport))
	_check("layered cloud transport restores", Atmosphere.restore_cloud_transport(restore_transport.duplicate(true)))
	_check_cloud_snapshot_offsets("restore before next update", resolved, restore_transport, step * 3.0)
	var restored_rewind := step * 2.2
	_check("restored clock can rewind before its anchor", Atmosphere.update_clouds(environment, restored_rewind))
	_check_layered_uniforms("restored rewind", environment, resolved, restore_transport, restored_rewind)
	_check_cloud_snapshot_offsets("restored rewind", resolved, restore_transport, restored_rewind)

	var fresh_environment := _bare_cloud_environment()
	_check("cached cloud arrays reach a fresh material", Atmosphere.update_clouds(fresh_environment, restored_rewind))
	_check_layered_uniforms("fresh material", fresh_environment, resolved, restore_transport, restored_rewind)

	# The public snapshot is detached, including nested layer dictionaries and offset arrays.
	var mutated_snapshot: Dictionary = Atmosphere.cloud_state_snapshot()
	mutated_snapshot["offset"] = Vector2(63.0, 62.0)
	mutated_snapshot["seed"] = -1
	var returned_layers: Array = mutated_snapshot["cloud_layers"]
	var returned_layer: Dictionary = returned_layers[0]
	returned_layer["type"] = "cirrus"
	returned_layer["offset"] = Vector2(61.0, 60.0)
	returned_layer["seed"] = -1
	returned_layers.clear()
	var detached_again: Dictionary = Atmosphere.cloud_state_snapshot()
	_check("snapshot mutation does not alter its selected offset", detached_again.offset == _selected_test_offset(resolved, restore_transport, restored_rewind))
	_check("snapshot mutation does not alter its seed", int(detached_again.seed) == int(selection.seed))
	_check("snapshot mutation does not alter layer count", detached_again.cloud_layers.size() == resolved.cloud_layers.size())
	_check("snapshot mutation does not alter layer data",
		str(detached_again.cloud_layers[0].type) == str(resolved.cloud_layers[0].type)
		and int(detached_again.cloud_layers[0].seed) == int(resolved.cloud_layers[0].seed))
	_check_layered_uniforms("after snapshot mutation", fresh_environment, resolved, restore_transport, restored_rewind)


func _check_layered_uniforms(label: String, environment: Environment, resolved: Dictionary,
		transport: Dictionary, time_s: float) -> void:
	var offsets := _expected_cloud_offsets(resolved, transport, time_s)
	var arrays: Dictionary = SkyAppearance.shader_arrays(resolved.cloud_layers, offsets,
		float(resolved.cloud_cover), float(resolved.cloud_density))
	var material := environment.sky.sky_material as ShaderMaterial
	_check("%s layered appearance" % label, material.get_shader_parameter(&"layered_appearance") == true)
	_check("%s disc occlusion" % label, material.get_shader_parameter(&"disc_cloud_occlusion") == true)
	for uniform_name: StringName in LAYERED_CLOUD_UNIFORMS:
		var array_name := String(uniform_name).trim_prefix("appearance_")
		_check("%s %s" % [label, String(uniform_name)],
			material.get_shader_parameter(uniform_name) == arrays[array_name])


func _check_cloud_snapshot_offsets(label: String, resolved: Dictionary, transport: Dictionary, time_s: float) -> void:
	var snapshot: Dictionary = Atmosphere.cloud_state_snapshot()
	var offsets := _expected_cloud_offsets(resolved, transport, time_s)
	_check("%s snapshot layer count" % label, snapshot.cloud_layers.size() == resolved.cloud_layers.size())
	for index in resolved.cloud_layers.size():
		_check("%s snapshot layer %d offset" % [label, index],
			snapshot.cloud_layers[index].offset == _cloud_offset_vector(offsets[index]))
	_check("%s snapshot selected offset" % label,
		snapshot.offset == _selected_test_offset(resolved, transport, time_s))


func _expected_cloud_offsets(resolved: Dictionary, transport: Dictionary, time_s: float) -> Array:
	if not resolved.cloud_layers.is_empty() and not transport.layers.is_empty():
		return CloudTransport.offsets(transport, time_s)
	return [CloudTransport.legacy_offset_pair(transport, time_s)]


func _selected_test_offset(resolved: Dictionary, transport: Dictionary, time_s: float) -> Vector2:
	# The broken-profile fixture's first layer is its low shadow deck; clear has no layers.
	# Use that declared fixture order rather than repeating Atmosphere's layer-selection algorithm.
	return _cloud_offset_vector(_expected_cloud_offsets(resolved, transport, time_s)[0])


func _cloud_offset_vector(raw: Variant) -> Vector2:
	if raw is Vector2:
		return raw
	return Vector2(float(raw[0]), float(raw[1]))


func _bare_cloud_environment() -> Environment:
	var material := ShaderMaterial.new()
	material.shader = Atmosphere.SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	return environment
