extends SceneTree

const Atmosphere := preload("res://render/atmosphere.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const Spec := preload("res://spec.gd")
const ShaderClock := preload("res://render/shader_clock.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	ShaderClock.register()
	var classic := SkyConfig.defaults()
	_check("classic appearance configures", Atmosphere.configure_appearance(classic))
	var classic_sky := Atmosphere.sky_material()
	_check("classic keeps calibrated sky branch", not bool(classic_sky.get_shader_parameter("layered_appearance")))
	_check("classic keeps the calibrated default cloud seed", int(classic_sky.get_shader_parameter("cloud_seed")) == 1253)
	var seeded_classic := classic.duplicate(true)
	seeded_classic.seed = 99
	_check("classic accepts a non-default seed", Atmosphere.configure_appearance(seeded_classic))
	var seeded_sky := Atmosphere.sky_material()
	var seeded_ground := Atmosphere.ground_material(null)
	_check("classic seed reaches sky and ground materials",
		int(seeded_sky.get_shader_parameter("cloud_seed")) == 99 and int(seeded_ground.get_shader_parameter("cloud_seed")) == 99)
	_check("classic seed remains in the detached cloud snapshot", int(Atmosphere.cloud_state_snapshot().seed) == 99)
	_check("classic default config restores the calibrated seed", Atmosphere.configure_appearance(classic)
		and int(Atmosphere.sky_material().get_shader_parameter("cloud_seed")) == 1253)
	var still_classic := classic.duplicate(true)
	still_classic.motion = "still"
	_check("classic still mode configures", Atmosphere.configure_appearance(still_classic))
	var still_env := Atmosphere.environment()
	Atmosphere.update_clouds(still_env, 60.0)
	_check("classic still mode holds the cloud pattern", Atmosphere.cloud_state_snapshot().offset == Vector2.ZERO)
	var follow_classic := classic.duplicate(true)
	follow_classic.motion = "follow_wind"
	var classic_wind := [10.0, -4.0, 0.0]
	_check("classic follow-wind mode configures", Atmosphere.configure_appearance(follow_classic, classic_wind))
	var follow_env := Atmosphere.environment()
	var classic_step := float(Spec.ATMOSPHERE.cloud_update_s)
	Atmosphere.update_clouds(follow_env, classic_step)
	var expected_classic_offset := Vector2(0.016, 0.04) * classic_step
	_check("classic follow-wind advances by mean wind at physical cell scale",
		(Atmosphere.cloud_state_snapshot().offset as Vector2).is_equal_approx(expected_classic_offset))
	_check("classic default motion restores after transport checks", Atmosphere.configure_appearance(classic))

	var clear := SkyConfig.for_preset("clear")
	_check("clear appearance configures", Atmosphere.configure_appearance(clear))
	var clear_sky := Atmosphere.sky_material()
	_check("clear uses layered profile branch", bool(clear_sky.get_shader_parameter("layered_appearance")))
	_check("clear has no cloud layers", int(clear_sky.get_shader_parameter("appearance_layer_count")) == 0)
	var clear_ground := Atmosphere.ground_material(null)
	_check("clear disables custom ground cloud shadow", float(clear_ground.get_shader_parameter("cloud_shadow_strength")) == 0.0)

	var fair := SkyConfig.for_preset("fair_cumulus")
	var mean_wind := [10.0, 0.0, 0.0]
	_check("fair cumulus appearance configures", Atmosphere.configure_appearance(fair, mean_wind, 0.0))
	var fair_sky := Atmosphere.sky_material()
	var parameters: PackedVector4Array = fair_sky.get_shader_parameter("appearance_layer_parameters")
	var motion: PackedVector4Array = fair_sky.get_shader_parameter("appearance_layer_motion")
	_check("fair cumulus has one physical deck", int(fair_sky.get_shader_parameter("appearance_layer_count")) == 1 and parameters[0].x > 0.0 and parameters[0].y > 0.0)
	_check("fair cumulus layer starts at the reset phase", motion[0].x == 0.0 and motion[0].y == 0.0)
	var storm := SkyConfig.for_preset("electrical_storm")
	_check("electrical storm appearance configures", Atmosphere.configure_appearance(storm))
	var storm_sky := Atmosphere.sky_material()
	var storm_parameters: PackedVector4Array = storm_sky.get_shader_parameter("appearance_layer_parameters")
	_check("storm decks render far-to-near by altitude", int(storm_sky.get_shader_parameter("appearance_layer_count")) == 3
		and storm_parameters[0].x < storm_parameters[1].x and storm_parameters[1].x < storm_parameters[2].x)
	_check("layered cloud profile occludes the solar disc", bool(storm_sky.get_shader_parameter("disc_cloud_occlusion")))
	_check("classic branch keeps its calibrated solar disc", not bool(classic_sky.get_shader_parameter("disc_cloud_occlusion")))
	_check("fair cumulus appearance can be restored for transport checks", Atmosphere.configure_appearance(fair, mean_wind, 0.0))
	var snapshot := Atmosphere.cloud_state_snapshot()
	_check("storm snapshot carries the same typed deck", snapshot.cloud_layers.size() == 1 and snapshot.cloud_layers[0].type == "fair_cumulus")
	_check("storm snapshot includes physical projection and relief", snapshot.cloud_layers[0].scale_m > 0.0 and snapshot.cloud_layers[0].cluster_strength > 0.0)
	var config_copy := Atmosphere.appearance_config()
	config_copy.preset = "clear"
	_check("appearance config is detached", Atmosphere.appearance_config().preset == "fair_cumulus")

	var checkpoint := Atmosphere.cloud_transport_checkpoint()
	_check("transport checkpoint matches selected profile and wind", Atmosphere.validate_cloud_transport_for(fair, checkpoint, mean_wind))
	var wrong_identity: Dictionary = checkpoint.duplicate(true)
	wrong_identity.layers[0].seed += 1
	_check("transport checkpoint rejects a layer from another appearance", not Atmosphere.validate_cloud_transport_for(fair, wrong_identity, mean_wind))
	var env := Atmosphere.environment()
	var first_offset: Vector2 = Atmosphere.cloud_state_snapshot().cloud_layers[0].offset
	Atmosphere.update_clouds(env, 2.0)
	var second_offset: Vector2 = Atmosphere.cloud_state_snapshot().cloud_layers[0].offset
	_check("wind-driven sky and shared cloud snapshot advance together", first_offset != second_offset)
	print("sky render contract: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label)
