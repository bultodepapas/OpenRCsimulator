extends SceneTree

const Spec := preload("res://spec.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const SkyAppearance := preload("res://render/weather/sky_appearance.gd")
const CloudTransport := preload("res://render/weather/cloud_transport.gd")
const CLOUD_UNIFORMS: Array[StringName] = [
	&"appearance_layer_count", &"appearance_layer_parameters", &"appearance_layer_motion",
	&"appearance_layer_seeds", &"appearance_cloud_density",
]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	var selection: Dictionary = SkyConfig.for_preset("broken")
	selection["seed"] = 4703
	selection["motion"] = "follow_wind"
	var wind := [7.0, -3.0, 0.4]
	_check("initial profile accepted", Atmosphere.configure_appearance(selection, wind, 0.0))
	var checked: Dictionary = SkyConfig.validate(selection)
	var resolved: Dictionary = SkyAppearance.resolve(checked.profile, checked.config)
	var transport: Dictionary = Atmosphere.cloud_transport_checkpoint()
	var environment: Environment = Atmosphere.environment()
	var step := float(Spec.ATMOSPHERE.cloud_update_s)

	var later := step * 5.2
	_check("new quantized offset changes sky", Atmosphere.update_clouds(environment, later))
	_check_material("later", environment, resolved, transport, later)
	_check_snapshot("later", resolved, transport, later)
	_check("same interval does not change sky", not Atmosphere.update_clouds(environment, step * 5.8))
	_check_material("same interval", environment, resolved, transport, step * 5.8)

	var rewind := step * 1.3
	_check("clock rewind changes sky", Atmosphere.update_clouds(environment, rewind))
	_check_material("clock rewind", environment, resolved, transport, rewind)
	_check_snapshot("clock rewind", resolved, transport, rewind)
	var before_rejection: Dictionary = Atmosphere.cloud_state_snapshot()
	var invalid: Dictionary = selection.duplicate(true)
	invalid["preset"] = "unknown"
	_check("invalid profile rejected", not Atmosphere.configure_appearance(invalid, wind, 0.0))
	_check("rejected config leaves selection intact", Atmosphere.appearance_config() == selection)
	_check("rejected config leaves snapshot intact", Atmosphere.cloud_state_snapshot() == before_rejection)
	_check_material("after rejected config", environment, resolved, transport, rewind)

	# Transition through a zero-layer profile at the same clock to exercise both cache invalidations.
	var clear_selection: Dictionary = SkyConfig.for_preset("clear")
	_check("clear profile accepted", Atmosphere.configure_appearance(clear_selection, wind, 0.0))
	var clear_checked: Dictionary = SkyConfig.validate(clear_selection)
	var clear_resolved: Dictionary = SkyAppearance.resolve(clear_checked.profile, clear_checked.config)
	var clear_transport: Dictionary = Atmosphere.cloud_transport_checkpoint()
	_check_snapshot("clear invalidation", clear_resolved, clear_transport, 0.0)
	Atmosphere.update_clouds(environment, 0.0)
	_check_material("clear profile", environment, clear_resolved, clear_transport, 0.0)
	_check("layered profile accepted again", Atmosphere.configure_appearance(selection, wind, 0.0))
	checked = SkyConfig.validate(selection)
	resolved = SkyAppearance.resolve(checked.profile, checked.config)
	transport = Atmosphere.cloud_transport_checkpoint()
	_check_snapshot("layered invalidation", resolved, transport, 0.0)
	Atmosphere.update_clouds(environment, 0.0)
	_check_material("layered profile after clear", environment, resolved, transport, 0.0)

	var restored: Dictionary = CloudTransport.build(checked.config, resolved.cloud_layers,
		[8.0, 2.0, 0.0], step * 3.0, step, Spec.ATMOSPHERE.cloud_drift_cells_per_s,
		[Vector2(7.0, 11.0), Vector2(17.0, 23.0), Vector2(29.0, 31.0)],
		float(Spec.ATMOSPHERE.cloud_deck_m) / maxf(float(Spec.ATMOSPHERE.cloud_scale), 1.0e-6))
	_check("restore transport fixture is valid", CloudTransport.validate(restored))
	_check("restore transport accepted", Atmosphere.restore_cloud_transport(restored.duplicate(true)))
	_check_snapshot("restore before next update", resolved, restored, step * 3.0)
	var restored_rewind := step * 2.2
	_check("restored transport supports rewind", Atmosphere.update_clouds(environment, restored_rewind))
	_check_material("restored rewind", environment, resolved, restored, restored_rewind)
	_check_snapshot("restored rewind", resolved, restored, restored_rewind)

	var fresh_environment := _bare_cloud_environment()
	_check("cached values reach a fresh material", Atmosphere.update_clouds(fresh_environment, restored_rewind))
	_check_material("fresh material", fresh_environment, resolved, restored, restored_rewind)

	var detached: Dictionary = Atmosphere.cloud_state_snapshot()
	detached["offset"] = Vector2(63.0, 62.0)
	detached["seed"] = -1
	var returned_layers: Array = detached["cloud_layers"]
	var returned_layer: Dictionary = returned_layers[0]
	returned_layer["type"] = "cirrus"
	returned_layer["offset"] = Vector2(61.0, 60.0)
	returned_layer["seed"] = -1
	returned_layers.clear()
	var detached_again: Dictionary = Atmosphere.cloud_state_snapshot()
	_check("detached mutation preserves selected offset", detached_again.offset == _selected_offset(resolved, restored, restored_rewind))
	_check("detached mutation preserves seed", int(detached_again.seed) == int(selection.seed))
	_check("detached mutation preserves layer count", detached_again.cloud_layers.size() == resolved.cloud_layers.size())
	_check("detached mutation preserves layer identity",
		str(detached_again.cloud_layers[0].type) == str(resolved.cloud_layers[0].type)
		and int(detached_again.cloud_layers[0].seed) == int(resolved.cloud_layers[0].seed))
	_check_material("after detached mutation", fresh_environment, resolved, restored, restored_rewind)

	if _failures == 0:
		print("PASS independent atmosphere cloud candidate: %d checks" % _checks)
		quit(0)
	else:
		printerr("FAIL independent atmosphere cloud candidate: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _check_material(label: String, environment: Environment, resolved: Dictionary,
		transport: Dictionary, time_s: float) -> void:
	var arrays: Dictionary = SkyAppearance.shader_arrays(resolved.cloud_layers,
		_expected_offsets(resolved, transport, time_s), float(resolved.cloud_cover), float(resolved.cloud_density))
	var material := environment.sky.sky_material as ShaderMaterial
	_check("%s layered flag" % label, material.get_shader_parameter(&"layered_appearance") == true)
	_check("%s occlusion flag" % label, material.get_shader_parameter(&"disc_cloud_occlusion") == true)
	for uniform_name: StringName in CLOUD_UNIFORMS:
		var array_name := String(uniform_name).trim_prefix("appearance_")
		_check("%s %s" % [label, String(uniform_name)], material.get_shader_parameter(uniform_name) == arrays[array_name])


func _check_snapshot(label: String, resolved: Dictionary, transport: Dictionary, time_s: float) -> void:
	var snapshot: Dictionary = Atmosphere.cloud_state_snapshot()
	var offsets := _expected_offsets(resolved, transport, time_s)
	_check("%s layer count" % label, snapshot.cloud_layers.size() == resolved.cloud_layers.size())
	for index in resolved.cloud_layers.size():
		_check("%s layer %d offset" % [label, index], snapshot.cloud_layers[index].offset == _offset_vector(offsets[index]))
	_check("%s selected offset" % label, snapshot.offset == _selected_offset(resolved, transport, time_s))


func _expected_offsets(resolved: Dictionary, transport: Dictionary, time_s: float) -> Array:
	if not resolved.cloud_layers.is_empty() and not transport.layers.is_empty():
		return CloudTransport.offsets(transport, time_s)
	return [CloudTransport.legacy_offset_pair(transport, time_s)]


func _selected_offset(resolved: Dictionary, transport: Dictionary, time_s: float) -> Vector2:
	var offsets := _expected_offsets(resolved, transport, time_s)
	var shadow_index := -1
	var lowest_altitude := INF
	for index in resolved.cloud_layers.size():
		var layer: Dictionary = resolved.cloud_layers[index]
		if str(layer.get("type", "")) in ["cirrus", "anvil"]:
			continue
		if float(layer.get("coverage", 0.0)) <= 0.0 or float(layer.get("density", 0.0)) <= 0.0:
			continue
		var altitude := float(layer.get("altitude_m", INF))
		if altitude < lowest_altitude:
			shadow_index = index
			lowest_altitude = altitude
	var index := shadow_index if shadow_index >= 0 else 0
	return _offset_vector(offsets[index])


func _offset_vector(raw: Variant) -> Vector2:
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


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s" % label)
