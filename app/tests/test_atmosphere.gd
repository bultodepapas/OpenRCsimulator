# L2: one source of truth for sky, fog, ground and sun (headless, no GPU), and the haze's physics.
# Run: godot --headless --path . --script res://tests/test_atmosphere.gd
extends SceneTree

const Spec := preload("res://spec.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Ground := preload("res://render/ground.gd")

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
	var env := Atmosphere.environment()
	var sky: ShaderMaterial = env.sky.sky_material
	var ground: ShaderMaterial = Ground.grass_material()
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

	# L3: engine shadows are off by default; turned on, the light is compensated and the haze's sun term is unchanged.
	_check("engine shadows off by default", not sun.shadow_enabled and Atmosphere.light_energy() == Spec.ATMOSPHERE.sun_energy)
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

	# Geometry: the ground reaches the rim, and the camera sees past it.
	_check("ground half-size ≥ rim end", Spec.GROUND_SIZE / 2.0 >= Spec.ATMOSPHERE.rim_end_m)
	_check("camera far ≥ 1.05 × rim end", Spec.CAMERA.far >= 1.05 * Spec.ATMOSPHERE.rim_end_m)

	# Physics (64-bit mirror of the shaders): 23 km visibility leaves 0.90 / 0.71 / 0.43 of an object's contrast at
	# 600 m / 2 km / 5 km (investigation 02), and ~3 % at the 20 km rim.
	for case in [[600.0, 0.90], [2000.0, 0.71], [5000.0, 0.43]]:
		_check("transmittance at %.0f m ≈ %.2f" % case, absf(Atmosphere.transmittance(case[0]) - case[1]) < 0.005, "%.4f" % Atmosphere.transmittance(case[0]))
	_check("transmittance at the rim ≤ 4 %", Atmosphere.transmittance(Spec.ATMOSPHERE.rim_end_m) <= 0.04, "%.4f" % Atmosphere.transmittance(Spec.ATMOSPHERE.rim_end_m))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
