## TOD-03/04: shared daylight/twilight/night parameters and scene-local ownership.
extends SceneTree

const Config = preload("res://environment/time_of_day_config.gd")
const Lighting = preload("res://render/time_of_day_lighting.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Spec = preload("res://spec.gd")
const Ground = preload("res://render/ground.gd")
const FieldBuilder = preload("res://render/field.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Shadow = preload("res://render/shadow.gd")
const ShaderClock = preload("res://render/shader_clock.gd")

var failures: int = 0
var checks: int = 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL " + label)


func _init() -> void:
	call_deferred("run")


func run() -> void:
	ShaderClock.register()
	var original: PackedByteArray = var_to_bytes(Spec.ATMOSPHERE)
	var config: Dictionary = Config.defaults()
	check("legacy snapshot preserves all original data", var_to_bytes(Lighting.snapshot(config)) == original)
	config.mode = "astronomical"
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	for hour: int in range(24):
		config.local_seconds = hour * 3600
		var a: Dictionary = Lighting.snapshot(config)
		var env: Environment = Atmosphere.environment(a)
		var sun: DirectionalLight3D = Atmosphere.create_sun(holder, a)
		var sky: ShaderMaterial = env.sky.sky_material
		var ground: ShaderMaterial = Atmosphere.ground_material(null, a)
		var surface: ShaderMaterial = Ground.surface_material(ground, "runway", Vector2.ZERO, Vector2.ONE)
		check("shared haze %d" % hour, sky.get_shader_parameter("haze_lin").is_equal_approx(ground.get_shader_parameter("haze_lin")))
		check("surface copy shares haze %d" % hour, surface.get_shader_parameter("haze_lin").is_equal_approx(ground.get_shader_parameter("haze_lin")))
		check("light/scatter snapshot %d" % hour, is_equal_approx(sun.light_energy, Atmosphere.light_energy(a)) and is_equal_approx(env.fog_sun_scatter, Atmosphere.sun_scatter(a)))
		check("sun direction agrees %d" % hour, sun.basis.z.distance_to(ground.get_shader_parameter("sun_dir")) < 1e-6)
		check("fixed exposure %d" % hour, is_equal_approx(env.tonemap_exposure, Spec.ATMOSPHERE.exposure))
		check("finite sun transform %d" % hour, sun.transform.is_finite())
		if float(a.solar.elevation_deg) < -18.0:
			check("night direct sun/shadow absent %d" % hour, sun.light_energy == 0.0 and Atmosphere.shadow_strength(a) == 0.0)
			check("night cloud illumination weak %d" % hour, (sky.get_shader_parameter("cloud_lin") as Vector3).length() < 0.002)
		var before: PackedByteArray = var_to_bytes(a)
		Atmosphere.update_clouds(env, 1024.0)
		check("cloud time never changes solar selection %d" % hour, var_to_bytes(a) == before)
		sun.free()
	# Independent sky/ground material instances: a later night build cannot mutate daytime resources.
	config.local_seconds = 12 * 3600
	var day: Dictionary = Lighting.snapshot(config)
	var daytime: Environment = Atmosphere.environment(day)
	var daytime_sky: ShaderMaterial = daytime.sky.sky_material
	var day_colour: Vector3 = daytime_sky.get_shader_parameter("zenith_lin")
	config.local_seconds = 0
	var night: Dictionary = Lighting.snapshot(config)
	var nighttime: Environment = Atmosphere.environment(night)
	check("day and night do not share sky", daytime.sky != nighttime.sky and daytime_sky != nighttime.sky.sky_material)
	check("night construction preserves daytime colour", daytime_sky.get_shader_parameter("zenith_lin") == day_colour)
	var overhead: Dictionary = day.duplicate(true)
	overhead.sun_elevation_deg = 90.0
	var zenith: DirectionalLight3D = Atmosphere.create_sun(holder, overhead)
	check("zenith is finite with a stable up vector", zenith.transform.is_finite())
	zenith.free()
	var shadow: MeshInstance3D = Shadow.create(holder)
	Shadow.update(shadow, Basis.IDENTITY, Vector3(0, 25, 0), 1.5, 1.3, Atmosphere.sun_direction(night), Atmosphere.shadow_strength(night))
	check("night shadow has zero opacity", shadow.material_override.albedo_color.a == 0.0)
	check("horizon projection remains bounded", shadow.transform.is_finite() and shadow.position.length() < 1000.0)
	# The legacy field owns a duplicated, manually lit grass material. The default
	# scenery uses imported vegetation lit by Godot's scene lights instead.
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var had_scenery_env := OS.has_environment("OPENRC_SCENERY")
	var scenery_env := OS.get_environment("OPENRC_SCENERY")
	OS.set_environment("OPENRC_SCENERY", "off")
	var built: Node3D = FieldBuilder.build(field, night)
	if had_scenery_env:
		OS.set_environment("OPENRC_SCENERY", scenery_env)
	else:
		OS.unset_environment("OPENRC_SCENERY")
	var contacts: MeshInstance3D = built.get_node("FlightCueShadows") as MeshInstance3D
	var contact_material: StandardMaterial3D = contacts.mesh.surface_get_material(0) as StandardMaterial3D
	check("night contact cues can only darken", contact_material.albedo_color == Color.BLACK)
	var grass_count: int = 0
	for node: Node in built.find_children("*", "MultiMeshInstance3D", true, false):
		var mesh: Mesh = node.multimesh.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var mat: Material = mesh.surface_get_material(0)
		if mat is ShaderMaterial and mat.shader.resource_path == "res://render/near_grass.gdshader":
			grass_count += 1
			check("near grass has night solar energy", (mat.get_shader_parameter("sun_lin") as Vector3).is_zero_approx())
			check("near grass has matching night haze", (mat.get_shader_parameter("haze_lin") as Vector3).is_equal_approx(Atmosphere.haze_linear(night)))
	check("actual legacy near grass checked", grass_count > 0)
	built.free()
	holder.free()
	check("global defaults never mutated", var_to_bytes(Spec.ATMOSPHERE) == original)
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
