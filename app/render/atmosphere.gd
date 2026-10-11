# Atmosphere (LANDSCAPE-PLAN L1a, L1b, L2): ONE source of truth, Spec.ATMOSPHERE, for the sky shader, the Environment
# (tonemap, exponential haze), the ground's custom fog and the sun's DirectionalLight3D. The sky's horizon, the
# engine's object fog and the ground's fog use one colour formula (GLES3 fog_process), so they can never disagree.
# Note (investigation 02): fog_aerial_perspective is a no-op in 4.7.2 Compatibility, and sky fog has no horizon
# dependence, so the sky draws the haze itself (fog_sky_affect = 0).
extends RefCounted

const Spec := preload("res://spec.gd")
const Frames := preload("res://render/frames.gd")
const SKY_SHADER := preload("res://render/sky.gdshader")
const GROUND_SHADER := preload("res://render/ground.gdshader")

## The cloud noise's lattice period in cells (render/cloud_field.gdshaderinc CLOUD_PERIOD).
const CLOUD_PERIOD := 64.0

# L15d: one active flight environment, like ShaderClock. A global offset also reaches duplicated
# mown/runway materials. Register lazily before any ground material is rendered.
static var _cloud_registered := false
static var last_cloud_offset := Vector2.ZERO


## Koschmieder: visual range = 3.912 / β (2 % contrast threshold).
const KOSCHMIEDER := 3.912

## L7 artistic weather presets, metres of meteorological visibility; default preserves L2 calibration.
const VISIBILITY_PRESETS: Dictionary = {"default": 23000.0, "hazy": 12000.0, "clear": 40000.0}
static var visibility_m: float = _visibility_from_args()


static func _visibility_from_args() -> float:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--visibility="):
			var preset: String = arg.trim_prefix("--visibility=")
			if VISIBILITY_PRESETS.has(preset):
				return float(VISIBILITY_PRESETS[preset])
			push_warning("Unknown visibility preset '%s'; using default (default/hazy/clear)" % preset)
	return Spec.ATMOSPHERE.visibility_m

## FW-22/23 time of day: render/world/sky_state.gd's output for the chosen hour, set by render/world/world.gd before
## the environment is built. Empty (the default) = the calibrated fixed 45° sun of Spec.ATMOSPHERE, byte for byte.
## In time-of-day mode the directional light is the brighter of sun and moon, and the haze's sunward brightening is
## the physical horizon lobe (lobe_*) drawn identically by the sky and the ground's own fog; the engine's fog keeps
## only the uniform haze (fog_sun_scatter = 0), which affects near objects by a few percent at most.
static var state: Dictionary = {}

## Engine (PSSM) sun shadows: off by default. In Compatibility they double every lit object's draw calls, clip white
## surfaces and shift hues (the shadowed light is blended in sRGB after tonemapping: Godot #90259); the sun shadow is
## the planar projected silhouette (render/shadow.gd) instead. `--engine_shadows` turns them on for comparison (L3).
static var engine_shadows := false


## Unit vector toward the sun in render axes (the light shines along the opposite direction).
static func sun_direction() -> Vector3:
	if not state.is_empty():
		return state.light_dir
	var az := deg_to_rad(Spec.ATMOSPHERE.sun_azimuth_deg)
	var el := deg_to_rad(Spec.ATMOSPHERE.sun_elevation_deg)
	return Frames.ned_to_render([cos(az) * cos(el), sin(az) * cos(el), -sin(el)]).normalized()


## Haze extinction coefficient β (1/m) from the visual range.
static func beta() -> float:
	return KOSCHMIEDER / visibility_m


## Fraction of an object's own light that reaches the eye through d metres of haze (64-bit mirror of the shaders).
static func transmittance(d: float) -> float:
	return exp(-beta() * d)


## Fog light colour in linear units, as the engine uses it (fog_light_color · fog_light_energy).
static func haze_linear() -> Vector3:
	if not state.is_empty():
		return state.haze_lin
	var c: Color = Spec.ATMOSPHERE.haze.srgb_to_linear()
	return Vector3(c.r, c.g, c.b) * Spec.ATMOSPHERE.haze_energy


## Compensation for Compatibility's sRGB blending of shadowed lights, used only with engine shadows (L3).
static func shadow_compensation() -> float:
	return Spec.ATMOSPHERE.shadow_energy_compat if engine_shadows else 1.0


## The light's actual energy.
static func light_energy() -> float:
	var energy: float = state.light_energy if not state.is_empty() else Spec.ATMOSPHERE.sun_energy
	return energy * shadow_compensation()


## Fog sun scatter as set on the engine: divided by the compensation, so the haze's sun term never changes.
static func sun_scatter() -> float:
	if not state.is_empty():
		return 0.0
	return Spec.ATMOSPHERE.sun_scatter / shadow_compensation()


## The sun's light in the units of the engine's fog scatter term (linear colour · actual light energy · π).
static func sun_linear() -> Vector3:
	var c: Color = light_color().srgb_to_linear()
	return Vector3(c.r, c.g, c.b) * light_energy() * PI


## The directional light's colour (sRGB): the calibrated sun, or the time-of-day sun/moon.
static func light_color() -> Color:
	return state.light_color if not state.is_empty() else Spec.ATMOSPHERE.sun_color


## Direction for the planar pilot-aid shadow: the light, with its elevation held at ≥ SHADOW_MIN_ELEVATION_DEG so a
## low sun gives a long but bounded shadow instead of one stretched to the horizon (estimate).
const SHADOW_MIN_ELEVATION_DEG := 12.0


static func shadow_direction() -> Vector3:
	var d := sun_direction()
	var min_y := sin(deg_to_rad(SHADOW_MIN_ELEVATION_DEG))
	if d.y >= min_y:
		return d
	var flat := Vector2(d.x, d.z).normalized() * cos(deg_to_rad(SHADOW_MIN_ELEVATION_DEG))
	return Vector3(flat.x, min_y, flat.y)


static func _set_haze_uniforms(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("haze_lin", haze_linear())
	mat.set_shader_parameter("sun_dir", sun_direction())
	mat.set_shader_parameter("sun_lin", sun_linear())
	mat.set_shader_parameter("sun_scatter", sun_scatter())
	if not state.is_empty(): # legacy materials keep the shaders' zero lobe
		mat.set_shader_parameter("lobe_lin", state.lobe_lin)
		mat.set_shader_parameter("lobe_dir", state.lobe_dir)
		mat.set_shader_parameter("lobe_k", state.lobe_k)
		mat.set_shader_parameter("lobe_height", state.lobe_height)


static func sky_material() -> ShaderMaterial:
	var a: Dictionary = Spec.ATMOSPHERE
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	var z: Color = a.zenith.srgb_to_linear()
	mat.set_shader_parameter("zenith_lin", Vector3(z.r, z.g, z.b))
	mat.set_shader_parameter("gradient_curve", a.gradient_curve)
	mat.set_shader_parameter("sun_radius", deg_to_rad(a.sun_diameter_deg) / 2.0)
	var cl: Color = a.cloud_color.srgb_to_linear()
	mat.set_shader_parameter("cloud_lin", Vector3(cl.r, cl.g, cl.b))
	mat.set_shader_parameter("cloud_coverage", a.cloud_coverage)
	mat.set_shader_parameter("cloud_scale", a.cloud_scale)
	mat.set_shader_parameter("cloud_seed", a.cloud_seed)
	mat.set_shader_parameter("cloud_offset", cloud_offset(0.0))
	mat.set_shader_parameter("cluster_strength", a.cloud_cluster_strength)
	mat.set_shader_parameter("cirrus_strength", a.cloud_cirrus_strength)
	mat.set_shader_parameter("silver_strength", a.cloud_silver_strength)
	_set_cloud_offset(cloud_offset(0.0))
	_set_haze_uniforms(mat)
	if not state.is_empty():
		apply_state_to_sky(mat)
	return mat


## FW-22/61: the time-of-day state's sky uniforms (also called when time flows).
static func apply_state_to_sky(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("zenith_lin", state.zenith_lin)
	mat.set_shader_parameter("cloud_lin", state.cloud_lin)
	mat.set_shader_parameter("sun_disc", state.sun_disc)
	mat.set_shader_parameter("moon_dir", state.moon_dir)
	mat.set_shader_parameter("moon_lin", state.moon_lin)
	mat.set_shader_parameter("moon_sun_dir", state.sun_dir)
	_set_haze_uniforms(mat)


## FW-23/61: the time-of-day state's environment: haze colour, ambient colour, no sky reflections (the cubemap path
## double-applies the exposure: sky_state.gd), tonemapper (FW-26). The exposure itself is World.adapt's.
static func apply_state_to_environment(env: Environment) -> void:
	var h: Vector3 = state.haze_lin
	env.fog_light_color = Color(h.x, h.y, h.z).linear_to_srgb()
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = sun_scatter()
	var amb: Vector3 = state.ambient_lin
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(amb.x, amb.y, amb.z).linear_to_srgb()
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX if state.get("tonemapper", "aces") == "agx" else Environment.TONE_MAPPER_ACES


## The directional light from the current state (or the calibrated sun): colour, energy, direction.
static func apply_light(light: DirectionalLight3D) -> void:
	light.light_color = light_color()
	light.light_energy = light_energy()
	# The light shines along its −Z: toward the origin from the sun's side. Built directly (no scene tree needed).
	var d := sun_direction()
	light.transform = Transform3D(Basis.looking_at(-d, Vector3.UP if absf(d.y) < 0.999 else Vector3.FORWARD), d * 100.0)


static func _set_cloud_offset(off: Vector2) -> void:
	if not _cloud_registered:
		RenderingServer.global_shader_parameter_add(&"cloud_drift_offset", RenderingServer.GLOBAL_VAR_TYPE_VEC2, off)
		_cloud_registered = true
	elif last_cloud_offset != off:
		RenderingServer.global_shader_parameter_set(&"cloud_drift_offset", off)
	last_cloud_offset = off


## L4: cloud drift for a simulation time (s): quantised to cloud_update_s and wrapped in float64 to the noise period,
## so the sky changes at most once per update interval and never jumps.
static func cloud_offset(sim_time: float) -> Vector2:
	var a: Dictionary = Spec.ATMOSPHERE
	var step: float = a.cloud_update_s
	var t := floorf(sim_time / step) * step
	var d: Vector2 = a.cloud_drift_cells_per_s
	return Vector2(fposmod(d.x * t, CLOUD_PERIOD), fposmod(d.y * t, CLOUD_PERIOD))


## Moves the clouds of an environment's sky to a simulation time; returns true when the sky actually changed.
static func update_clouds(env: Environment, sim_time: float) -> bool:
	var mat: ShaderMaterial = env.sky.sky_material
	var off := cloud_offset(sim_time)
	_set_cloud_offset(off) # also updates all ground surfaces, even when the sky is already at this time
	if mat.get_shader_parameter("cloud_offset") == off:
		return false
	mat.set_shader_parameter("cloud_offset", off)
	return true


## The ground's material: grass texture in world space + the haze as custom fog with the rim fade.
static func ground_material(grass: Texture2D) -> ShaderMaterial:
	var a: Dictionary = Spec.ATMOSPHERE
	var mat := ShaderMaterial.new()
	_set_cloud_offset(last_cloud_offset) # register before assigning a shader, also in an empty-project pack probe
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("cloud_coverage", a.cloud_coverage)
	mat.set_shader_parameter("cloud_scale", a.cloud_scale)
	mat.set_shader_parameter("cloud_seed", a.cloud_seed)
	mat.set_shader_parameter("cluster_strength", a.cloud_cluster_strength)
	mat.set_shader_parameter("cloud_deck_m", a.cloud_deck_m)
	mat.set_shader_parameter("cloud_shadow_strength", a.cloud_shadow_strength)
	mat.set_shader_parameter("grass", grass)
	mat.set_shader_parameter("tile_m", Spec.GROUND.tile_m)
	mat.set_shader_parameter("beta", beta())
	# L7: 40 km visibility retains ~14% contrast at the 20 km mesh edge. Spread the artistic rim
	# closure in inverse distance (estimated, capture-checked), instead of a sharp distance-space band.
	mat.set_shader_parameter("rim_start", a.rim_start_m if visibility_m <= a.visibility_m else 3000.0)
	mat.set_shader_parameter("rim_end", a.rim_end_m)
	mat.set_shader_parameter("rim_angular", visibility_m > a.visibility_m)
	_set_haze_uniforms(mat)
	return mat


## The world environment. L1a: the sky drawn per pixel as background; its radiance (rendered once, QUALITY) lights
## the scene as ambient light and reflections. L1b: ACES at exposure 0.6, glow off: the best readability of 14 settings
## swept twice (before and after L2's sky colour-space fix). With the correct sky: 3 m view contrast −0.335, ΔE 30.0;
## 30 m view −0.431, ΔE 41.4 (Filmic 0.8: −0.280 / 27.4). Ambient energy has no measurable effect here.
## L2: exponential haze for every object (the ground writes its own), density β, colour = the sky's horizon.
static func environment() -> Environment:
	var a: Dictionary = Spec.ATMOSPHERE
	var sky := Sky.new()
	sky.sky_material = sky_material()
	sky.process_mode = Sky.PROCESS_MODE_QUALITY # deterministic radiance, rendered once (no TIME in the shader)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = state.exposure if not state.is_empty() else a.exposure
	env.tonemap_white = a.white
	env.glow_enabled = false
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = beta()
	env.fog_light_color = a.haze
	env.fog_light_energy = a.haze_energy
	env.fog_sun_scatter = sun_scatter()
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	env.fog_height_density = 0.0
	if not state.is_empty():
		apply_state_to_environment(env)
	return env


## The sun: a DirectionalLight3D shining from sun_direction(); PSSM shadows only with engine_shadows (L3).
static func create_sun(parent: Node) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = engine_shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = Spec.ATMOSPHERE.shadow_max_distance_m
	if state.is_empty():
		# The light shines along its −Z: toward the origin from the sun's side. Built directly (no scene tree needed).
		sun.light_color = light_color()
		sun.light_energy = light_energy()
		sun.transform = Transform3D(Basis.looking_at(-sun_direction(), Vector3.UP), sun_direction() * 100.0)
	else:
		apply_light(sun)
	parent.add_child(sun)
	return sun
