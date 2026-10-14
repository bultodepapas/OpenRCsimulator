extends SceneTree

const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const SkyAppearance := preload("res://render/weather/sky_appearance.gd")
const CloudTransport := preload("res://render/weather/cloud_transport.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const WorldBuilder := preload("res://render/world/world.gd")
const StormBank := preload("res://render/weather/storm_bank.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_catalog_bounds()
	await _test_scene_isolation_and_reconfiguration()
	await _test_seeded_geometry_and_rng()
	await _test_advection_and_rebase()
	await process_frame
	print("storm bank: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_catalog_bounds() -> void:
	var selection: Dictionary = SkyConfig.for_preset("distant_storm")
	var checked: Dictionary = SkyConfig.validate(selection)
	_check("distant-storm catalog profile validates", checked.get("ok", false))
	if not checked.get("ok", false):
		return
	var profile: Dictionary = checked.profile.duplicate(true)
	_check("valid storm layout passes bank validation", SkyConfig._validate_profile(profile).is_empty())
	var unknown_version: Dictionary = profile.duplicate(true)
	unknown_version.renderer.storm_bank.layout_version = 2
	_check("unknown storm layout versions are rejected", not SkyConfig._validate_profile(unknown_version).is_empty())
	var exposed_wrap: Dictionary = profile.duplicate(true)
	exposed_wrap.renderer.cloud_layers[0].scale_m = 500.0
	_check("cloud periods that could expose the far-plane wrap are rejected",
		not SkyConfig._validate_profile(exposed_wrap).is_empty())


func _test_scene_isolation_and_reconfiguration() -> void:
	var storm_config: Dictionary = SkyConfig.for_preset("distant_storm")
	storm_config.seed = 1253
	_check("storm appearance installs", Atmosphere.configure_appearance(storm_config, [0.0, 0.0, 0.0], 0.0))
	var first_owner := Node3D.new()
	root.add_child(first_owner)
	var first_world: Dictionary = _build_empty_world(first_owner)
	var first_environment: Environment = first_world.environment
	var first_snapshot: Dictionary = WorldBuilder.weather_snapshot(first_environment)
	_check("production World exposes a visible storm bank", first_snapshot.get("enabled", false)
		and first_snapshot.get("puff_count", 0) == 30 and first_snapshot.get("rain_count", 0) == 3)

	var second_config: Dictionary = storm_config.duplicate(true)
	second_config.seed = 2871
	_check("second storm appearance installs", Atmosphere.configure_appearance(second_config, [0.0, 0.0, 0.0], 0.0))
	var second_owner := Node3D.new()
	root.add_child(second_owner)
	var second_world: Dictionary = _build_empty_world(second_owner)
	var second_snapshot: Dictionary = WorldBuilder.weather_snapshot(second_world.environment)
	_check("a second World owns independent seeded formation geometry",
		second_snapshot.get("enabled", false) and first_snapshot.puff_centers != second_snapshot.puff_centers)
	_check("the first World remains unchanged when a second is built",
		WorldBuilder.weather_snapshot(first_environment).puff_centers == first_snapshot.puff_centers)

	var clear_config: Dictionary = SkyConfig.for_preset("clear")
	_check("clear appearance installs", Atmosphere.configure_appearance(clear_config, [0.0, 0.0, 0.0], 0.0))
	var clear_owner := Node3D.new()
	root.add_child(clear_owner)
	var clear_world: Dictionary = _build_empty_world(clear_owner)
	var clear_snapshot: Dictionary = WorldBuilder.weather_snapshot(clear_world.environment)
	_check("clear World creates no storm geometry", not clear_snapshot.get("enabled", true)
		and clear_snapshot.get("puff_count", -1) == 0 and clear_snapshot.get("rain_count", -1) == 0)
	_check("clear World does not mutate the retained storm World",
		WorldBuilder.weather_snapshot(first_environment).puff_centers == first_snapshot.puff_centers)

	WorldBuilder.refresh_weather_appearance(first_environment, 2.0)
	_check("refreshing a retained World clears old storm geometry", not WorldBuilder.weather_snapshot(first_environment).get("enabled", true))
	_check("storm appearance can be restored to a retained World",
		Atmosphere.configure_appearance(storm_config, [0.0, 0.0, 0.0], 0.0))
	WorldBuilder.refresh_weather_appearance(first_environment, 2.0)
	var restored_snapshot: Dictionary = WorldBuilder.weather_snapshot(first_environment)
	_check("restored World rebuilds a bounded storm formation", restored_snapshot.get("enabled", false)
		and restored_snapshot.get("puff_count", 0) == 30 and restored_snapshot.get("rain_count", 0) == 3)

	second_owner.queue_free()
	clear_owner.queue_free()
	await process_frame
	_check("freeing other World roots leaves the retained bank alive",
		is_instance_valid(first_owner) and WorldBuilder.weather_snapshot(first_environment).get("enabled", false))
	first_owner.queue_free()
	await process_frame


func _test_seeded_geometry_and_rng() -> void:
	var checked: Dictionary = SkyConfig.validate(SkyConfig.for_preset("distant_storm"))
	var profile: Dictionary = checked.profile
	var first := StormBank.new()
	root.add_child(first)
	first.configure(profile, 147)
	var first_centers: Array = first.snapshot().puff_centers.duplicate(true)
	var same_seed := StormBank.new()
	root.add_child(same_seed)
	same_seed.configure(profile, 147)
	_check("same visual seed reproduces all storm-lobe centers", first_centers == same_seed.snapshot().puff_centers)

	seed(712367)
	var expected_rng := randi()
	seed(712367)
	var isolated := StormBank.new()
	root.add_child(isolated)
	isolated.configure(profile, 701)
	var observed_rng := randi()
	_check("storm geometry does not advance the global RNG", observed_rng == expected_rng)
	_check("storm reconfiguration remains capped at 30 puffs and 3 rain sheets",
		isolated.get_child_count() == 33 and isolated.snapshot().puff_count == 30 and isolated.snapshot().rain_count == 3)
	var clear_profile: Dictionary = SkyConfig.validate(SkyConfig.for_preset("clear")).profile
	isolated.configure(clear_profile, 701)
	_check("switching a bank to clear frees its old geometry", not isolated.visible and isolated.get_child_count() == 0)
	isolated.queue_free()
	first.queue_free()
	same_seed.queue_free()
	await process_frame


func _test_advection_and_rebase() -> void:
	var selection: Dictionary = SkyConfig.for_preset("distant_storm")
	var checked: Dictionary = SkyConfig.validate(selection)
	var profile: Dictionary = checked.profile
	var resolved: Dictionary = SkyAppearance.resolve(profile, selection)
	_check("bank transport has an advection layer", not resolved.cloud_layers.is_empty())
	if resolved.cloud_layers.is_empty():
		return
	var bank := StormBank.new()
	root.add_child(bank)
	bank.configure(profile, int(selection.seed))
	_check("storm appearance installs for transport test", Atmosphere.configure_appearance(selection, [0.0, 0.0, 0.0], 0.0))
	var environment: Environment = Atmosphere.environment()
	var calm_state: Dictionary = _transport(selection, resolved.cloud_layers, [0.0, 0.0, 0.0])
	var calm_offset: Vector2 = CloudTransport.layer_offset(calm_state, 0, 1.0)
	_check("calm wind keeps the initial cloud phase", calm_offset == Vector2.ZERO)
	bank.update_visual(_snapshot(resolved.cloud_layers, calm_offset), environment, null, 1.0)
	var calm_center := Vector2(bank.position.x, bank.position.z)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(500.0, 200.0, -700.0)
	bank.update_visual(_snapshot(resolved.cloud_layers, calm_offset), environment, null, 10.0)
	_check("camera movement does not move the world-anchored bank",
		Vector2(bank.position.x, bank.position.z).is_equal_approx(calm_center))

	var north_state: Dictionary = _transport(selection, resolved.cloud_layers, [10.0, 0.0, 0.0])
	var north_offset: Vector2 = CloudTransport.layer_offset(north_state, 0, 1.0)
	_check("northward wind advances the noise offset northward", north_offset.y > 0.0 and is_zero_approx(north_offset.x))
	bank.update_visual(_snapshot(resolved.cloud_layers, north_offset), environment, null, 1.0)
	_check("northward wind advects the geometry southward", bank.position.z < calm_center.y)

	var east_state: Dictionary = _transport(selection, resolved.cloud_layers, [0.0, 10.0, 0.0])
	var east_offset: Vector2 = CloudTransport.layer_offset(east_state, 0, 1.0)
	_check("eastward wind reverses the wrapped texture X offset",
		float(east_state.layers[0].velocity_cells_s[0]) < 0.0 and east_offset.x > 63.0 and is_zero_approx(east_offset.y))
	bank.update_visual(_snapshot(resolved.cloud_layers, east_offset), environment, null, 1.0)
	_check("eastward wind advects the geometry eastward", bank.position.x > calm_center.x)

	var moving_state: Dictionary = _transport(selection, resolved.cloud_layers, [8.0, -3.0, 0.0])
	var before_rebase: Vector2 = CloudTransport.layer_offset(moving_state, 0, 123456.0)
	var rebased: Dictionary = CloudTransport.rebase(moving_state, 123456.0)
	var after_rebase: Vector2 = CloudTransport.layer_offset(rebased, 0, 123456.0)
	_check("cloud checkpoint rebase preserves advection phase", before_rebase.is_equal_approx(after_rebase))
	bank.update_visual(_snapshot(resolved.cloud_layers, before_rebase), environment, null, 123456.0)
	var bank_before_rebase := Vector2(bank.position.x, bank.position.z)
	bank.update_visual(_snapshot(resolved.cloud_layers, after_rebase), environment, null, 123456.0)
	_check("checkpoint rebase keeps the storm position continuous",
		Vector2(bank.position.x, bank.position.z).is_equal_approx(bank_before_rebase))

	camera.queue_free()
	bank.queue_free()
	await process_frame


func _transport(selection: Dictionary, layers: Array, wind: Array) -> Dictionary:
	return CloudTransport.build(selection, layers, wind, 0.0, 1.0, Vector2.ZERO, [Vector2.ZERO])


func _snapshot(layers: Array, offset: Vector2) -> Dictionary:
	var visible_layers: Array = []
	for item: Dictionary in layers:
		var copy: Dictionary = item.duplicate(true)
		copy.offset = offset
		visible_layers.append(copy)
	return {"cloud_layers": visible_layers}


func _build_empty_world(owner: Node3D) -> Dictionary:
	return WorldBuilder.build(owner, {}, Callable(self, "_empty_field"), {"time_of_day": false}, {},
		{"field_lighting": "off", "campfire": false})


func _empty_field() -> void:
	pass


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s" % label)
