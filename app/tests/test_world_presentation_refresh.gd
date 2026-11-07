extends SceneTree

const World := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Conditions := preload("res://render/world/conditions.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LightingConfig := preload("res://environment/time_of_day_config.gd")
const TimeLighting := preload("res://render/time_of_day_lighting.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const MoonConfig := preload("res://environment/moon_config.gd")
const Landscapes := preload("res://landscapes/catalog.gd")

var checks := 0
var failures := 0


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL " + label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads", bool(loaded.ok))
	if not loaded.ok:
		quit(1)
		return
	var field: Dictionary = loaded.field
	var day: Dictionary = {time_of_day = false}
	var options := {field_lighting = "club", field_activation = "auto", campfire = false}
	var sky: Dictionary = SkyConfig.defaults()
	Atmosphere.configure_appearance(sky)
	var owner := Node3D.new()
	var world: Dictionary = World.build(owner, field, Callable(), day, {}, options)
	root.add_child(owner)
	var field_node: Node3D = world.field
	var field_id := field_node.get_instance_id()
	var ground_id := (field_node.get_node("rough") as MeshInstance3D).mesh.get_instance_id()
	var original_environment: Environment = world.environment
	var original_sun: DirectionalLight3D = world.sun
	var evening: Dictionary = Conditions.resolve(PackedStringArray(["--time_of_day=golden_hour", "--time_scale=20"]))
	var night: Dictionary = Conditions.resolve(PackedStringArray(["--time_of_day=night"]))
	var custom: Dictionary = LightingConfig.defaults()
	custom.mode = "astronomical"
	custom.local_seconds = 3600
	var explicit: Dictionary = TimeLighting.snapshot(custom)
	var broken: Dictionary = SkyConfig.for_preset("broken")
	var manual := {field_lighting = "airfield", field_activation = "on", campfire = true}
	var moon_off: Dictionary = MoonConfig.defaults()
	moon_off.moon = "off"
	var cases := [
		{name = "evening", conditions = evening, lighting = {}, sky = sky},
		{name = "night", conditions = night, lighting = {}, sky = sky},
		{name = "night moon off", conditions = night, lighting = {}, sky = sky, moon = moon_off, options = manual},
		{name = "night moon restored", conditions = night, lighting = {}, sky = sky},
		{name = "day after night", conditions = day, lighting = {}, sky = sky},
		{name = "explicit night and local gain", conditions = day, lighting = explicit, sky = sky, options = manual},
		{name = "broken sky", conditions = evening, lighting = {}, sky = broken},
		{name = "day after flow", conditions = day, lighting = {}, sky = sky},
	]
	var previous_moon_session: Dictionary = MoonConfig.session_config.duplicate(true)
	for item: Dictionary in cases:
		MoonConfig.session_config = item.get("moon", {}).duplicate(true)
		var case_options: Dictionary = item.get("options", options)
		var refreshed: Dictionary = World.refresh_presentation(owner, field_node, world, item.conditions,
			item.lighting, case_options, item.sky)
		_check(item.name + " refresh succeeds", bool(refreshed.get("ok", false)))
		if not bool(refreshed.get("ok", false)):
			continue
		world = refreshed
		_check(item.name + " retains field, ground, environment and sun",
			field_node.get_instance_id() == field_id and (field_node.get_node("rough") as MeshInstance3D).mesh.get_instance_id() == ground_id
			and world.environment == original_environment and world.sun == original_sun)
		var actual := _appearance(owner, world)
		var retained := World.presentation_context()
		var retained_live: Dictionary = World._live.duplicate(true)
		var retained_when: Dictionary = World._base_when.duplicate(true)
		var retained_moon: Dictionary = World._moon_config.duplicate(true)
		var retained_appearance: Dictionary = World._capture_refresh_appearance()
		Atmosphere.configure_appearance(item.sky)
		var fresh_owner := Node3D.new()
		var fresh: Dictionary = World.build(fresh_owner, field, Callable(), item.conditions, item.lighting, case_options)
		root.add_child(fresh_owner)
		var expected := _appearance(fresh_owner, fresh)
		_compare(item.name, actual, expected)
		fresh_owner.free()
		World.restore_presentation_context(retained)
		World._live = retained_live
		World._base_when = retained_when
		World._moon_config = retained_moon
		World._restore_refresh_appearance(retained_appearance)
		if item.name == "evening":
			var hour := World.flow_hour()
			World.update(world.environment, 3.0)
			_check("refreshed flowing world advances", World.flow_hour() > hour)
	MoonConfig.session_config = previous_moon_session

	var before := _appearance(owner, world)
	var before_context := World.presentation_context()
	var bad_sky := sky.duplicate(true)
	bad_sky.preset = "not-a-preset"
	var rejected: Dictionary = World.refresh_presentation(owner, field_node, world, night, {}, options, bad_sky)
	_check("invalid sky is rejected", not rejected.ok)
	_check("invalid sky retains appearance", _appearance(owner, world) == before)
	_check("invalid sky retains active atmosphere and flow", World.presentation_context() == before_context)
	var malformed := {time_of_day = true, when = {hour = NAN}}
	rejected = World.refresh_presentation(owner, field_node, world, malformed, {}, options, sky)
	_check("malformed conditions are rejected", not rejected.ok)
	var bad_snapshot := explicit.duplicate(true)
	bad_snapshot.solar = {}
	rejected = World.refresh_presentation(owner, field_node, world, day, bad_snapshot, options, sky)
	_check("malformed solar snapshot is rejected", not rejected.ok)
	_check("malformed solar snapshot retains appearance", _appearance(owner, world) == before)
	bad_snapshot = explicit.duplicate(true)
	bad_snapshot.haze = Color(NAN, 0.0, 0.0)
	rejected = World.refresh_presentation(owner, field_node, world, day, bad_snapshot, options, sky)
	_check("non-finite snapshot color is rejected", not rejected.ok)
	_check("non-finite snapshot retains appearance", _appearance(owner, world) == before)
	var other := Node3D.new()
	var other_world: Dictionary = World.build(other, field, Callable(), evening, {}, options)
	root.add_child(other)
	var other_state: Dictionary = Atmosphere.state.duplicate(true)
	var other_flow := World.flow_hour()
	rejected = World.refresh_presentation(owner, field_node, world, night, {}, options, sky)
	_check("inactive owner is rejected", not rejected.ok)
	_check("inactive-owner rejection preserves active world", Atmosphere.state == other_state and World.flow_hour() == other_flow
		and World._flow.get("environment") == other_world.environment)
	var other_live: Dictionary = World._live.duplicate(true)
	var other_when: Dictionary = World._base_when.duplicate(true)
	var other_moon: Dictionary = World._moon_config.duplicate(true)
	var other_appearance := _appearance(other, other_world)
	rejected = World.refresh_presentation(other, other_world.field, other_world, night, {}, options, bad_sky)
	_check("invalid sky rejects active flowing world", not rejected.ok)
	_check("active flow rejection preserves appearance and global state", _appearance(other, other_world) == other_appearance
		and Atmosphere.state == other_state and World.flow_hour() == other_flow
		and World._live == other_live and World._base_when == other_when and World._moon_config == other_moon)
	World.update(other_world.environment, 3.0)
	_check("active flow advances after rejection", World.flow_hour() > other_flow)
	other.free()
	owner.free()
	_test_green_paradise(day, night, options, broken)
	print("world presentation refresh: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _appearance(owner: Node3D, world: Dictionary) -> Dictionary:
	var environment: Environment = world.environment
	var sun: DirectionalLight3D = world.sun
	var field: Node3D = owner.get_node("Field")
	var ground: ShaderMaterial = field.get_meta("lighting_materials")[0]
	var sky: ShaderMaterial = environment.sky.sky_material
	var uniforms := {}
	for key: String in ["zenith_lin", "haze_lin", "sun_dir", "sun_lin", "moon_dir", "moon_lin", "lobe2_lin", "disc_dir", "cloud_coverage"]:
		uniforms[key] = sky.get_shader_parameter(key)
	var ground_uniforms := {}
	for key: String in ["haze_lin", "sun_dir", "sun_lin", "sun_scatter", "lobe_lin", "lobe_dir", "beta", "cloud_coverage"]:
		ground_uniforms[key] = ground.get_shader_parameter(key)
	var star_ref: Variant = environment.get_meta("fw_star_field") if environment.has_meta("fw_star_field") else null
	var stars: Node3D = star_ref.get_ref() as Node3D if star_ref is WeakRef else null
	var star_basis := Basis.IDENTITY
	if stars != null:
		star_basis = stars.basis * (stars.get_meta("fw_equatorial_basis") as Basis)
	var scenery: Node = field.get_node_or_null("Scenery")
	var shadow_signature: Dictionary = scenery.get_meta("directional_shadow_signature", {}) if scenery != null else {}
	var shadow_strength: float = scenery.get_meta("directional_shadow_strength", 0.0) if scenery != null else 0.0
	var field_lights := owner.get_node_or_null("FieldLights") as Node3D
	var helper: Node = owner.get_node_or_null("AirfieldLighting")
	var fire: Node = owner.get_node_or_null("Campfire")
	var first_spot_energy := -1.0
	if field_lights != null:
		var spots := field_lights.find_children("*", "SpotLight3D", true, false)
		if not spots.is_empty():
			first_spot_energy = (spots[0] as SpotLight3D).light_energy
	return {sky = uniforms, ground = ground_uniforms, sun = sun.transform, sun_energy = sun.light_energy,
		sun_color = sun.light_color, sun_shadow = sun.shadow_enabled, exposure = environment.tonemap_exposure,
		ambient = environment.ambient_light_color, ambient_source = environment.ambient_light_source,
		reflection_source = environment.reflected_light_source, fog = environment.fog_light_color,
		tonemap = environment.tonemap_mode, stars = stars != null and stars.visible, star_basis = star_basis,
		shadow_signature = shadow_signature, shadow_strength = shadow_strength,
		field_lights_visible = field_lights.visible if field_lights != null else false,
		night_factor = helper.get_meta("night_factor", -1.0) if helper != null else -1.0,
		local_gain = helper.get_meta("sdr_local_gain", -1.0) if helper != null else -1.0,
		light_profile = helper.get_meta("field_lighting", "") if helper != null else "",
		light_activation = helper.get_meta("field_activation", "") if helper != null else "",
		spot_energy = first_spot_energy, fire_enabled = fire.get("_enabled") if fire != null else false,
		fire_gain = fire.get("_local_gain") if fire != null else -1.0,
		sky_config = Atmosphere.appearance_config(), hour = World.flow_hour()}


func _compare(label: String, actual: Dictionary, expected: Dictionary) -> void:
	for key: String in expected:
		var a: Variant = actual[key]
		var b: Variant = expected[key]
		var equal := false
		if a is float and b is float:
			equal = is_equal_approx(a, b)
		elif a is Basis and b is Basis:
			equal = (a as Basis).is_equal_approx(b)
		elif a is Transform3D and b is Transform3D:
			equal = (a as Transform3D).is_equal_approx(b)
		else:
			equal = a == b
		_check(label + " matches fresh " + key, equal)


func _test_green_paradise(day: Dictionary, night: Dictionary, options: Dictionary, sky: Dictionary) -> void:
	var entry: Dictionary = Landscapes.entry("green_paradise")
	var loaded: Dictionary = FieldLoader.load_from(entry.field_path)
	_check("green paradise field loads", bool(loaded.ok))
	if not loaded.ok:
		return
	var field: Dictionary = loaded.field
	Atmosphere.configure_appearance(SkyConfig.defaults())
	var owner := Node3D.new()
	var build_field := func() -> void: owner.add_child(Landscapes.build("green_paradise", field, {}))
	var world: Dictionary = World.build(owner, field, build_field, day, {}, options)
	root.add_child(owner)
	var field_node: Node3D = owner.get_node("Field")
	var field_id := field_node.get_instance_id()
	var ground_id := (field_node.get_node("rough") as MeshInstance3D).mesh.get_instance_id()
	var refreshed: Dictionary = World.refresh_presentation(owner, field_node, world, night, {}, options, sky)
	_check("green paradise refresh succeeds with callback-built field", bool(refreshed.get("ok", false)))
	if not refreshed.get("ok", false):
		owner.free()
		return
	_check("green paradise keeps its field and ground", refreshed.field == field_node \
		and field_node.get_instance_id() == field_id \
		and (field_node.get_node("rough") as MeshInstance3D).mesh.get_instance_id() == ground_id)
	var actual := _appearance(owner, refreshed)
	Atmosphere.configure_appearance(sky)
	var fresh_owner := Node3D.new()
	var fresh_field := func() -> void: fresh_owner.add_child(Landscapes.build("green_paradise", field, {}))
	var fresh: Dictionary = World.build(fresh_owner, field, fresh_field, night, {}, options)
	root.add_child(fresh_owner)
	_compare("green paradise", actual, _appearance(fresh_owner, fresh))
	fresh_owner.free()
	owner.free()
