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

## Koschmieder: visual range = 3.912 / β (2 % contrast threshold).
const KOSCHMIEDER := 3.912

## Engine (PSSM) sun shadows: off by default. In Compatibility they double every lit object's draw calls, clip white
## surfaces and shift hues (the shadowed light is blended in sRGB after tonemapping: Godot #90259); the sun shadow is
## the planar projected silhouette (render/shadow.gd) instead. `--engine_shadows` turns them on for comparison (L3).
static var engine_shadows := false


## Unit vector toward the sun in render axes (the light shines along the opposite direction).
static func sun_direction() -> Vector3:
	var az := deg_to_rad(Spec.ATMOSPHERE.sun_azimuth_deg)
	var el := deg_to_rad(Spec.ATMOSPHERE.sun_elevation_deg)
	return Frames.ned_to_render([cos(az) * cos(el), sin(az) * cos(el), -sin(el)]).normalized()


## Haze extinction coefficient β (1/m) from the visual range.
static func beta() -> float:
	return KOSCHMIEDER / Spec.ATMOSPHERE.visibility_m


## Fraction of an object's own light that reaches the eye through d metres of haze (64-bit mirror of the shaders).
static func transmittance(d: float) -> float:
	return exp(-beta() * d)


## Fog light colour in linear units, as the engine uses it (fog_light_color · fog_light_energy).
static func haze_linear() -> Vector3:
	var c: Color = Spec.ATMOSPHERE.haze.srgb_to_linear()
	return Vector3(c.r, c.g, c.b) * Spec.ATMOSPHERE.haze_energy


## Compensation for Compatibility's sRGB blending of shadowed lights, used only with engine shadows (L3).
static func shadow_compensation() -> float:
	return Spec.ATMOSPHERE.shadow_energy_compat if engine_shadows else 1.0


## The light's actual energy.
static func light_energy() -> float:
	return Spec.ATMOSPHERE.sun_energy * shadow_compensation()


## Fog sun scatter as set on the engine: divided by the compensation, so the haze's sun term never changes.
static func sun_scatter() -> float:
	return Spec.ATMOSPHERE.sun_scatter / shadow_compensation()


## The sun's light in the units of the engine's fog scatter term (linear colour · actual light energy · π).
static func sun_linear() -> Vector3:
	var c: Color = Spec.ATMOSPHERE.sun_color.srgb_to_linear()
	return Vector3(c.r, c.g, c.b) * light_energy() * PI


static func _set_haze_uniforms(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("haze_lin", haze_linear())
	mat.set_shader_parameter("sun_dir", sun_direction())
	mat.set_shader_parameter("sun_lin", sun_linear())
	mat.set_shader_parameter("sun_scatter", sun_scatter())


static func sky_material() -> ShaderMaterial:
	var a: Dictionary = Spec.ATMOSPHERE
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	var z: Color = a.zenith.srgb_to_linear()
	mat.set_shader_parameter("zenith_lin", Vector3(z.r, z.g, z.b))
	mat.set_shader_parameter("gradient_curve", a.gradient_curve)
	mat.set_shader_parameter("sun_radius", deg_to_rad(a.sun_diameter_deg) / 2.0)
	_set_haze_uniforms(mat)
	return mat


## The ground's material: grass texture in world space + the haze as custom fog with the rim fade.
static func ground_material(grass: Texture2D) -> ShaderMaterial:
	var a: Dictionary = Spec.ATMOSPHERE
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("grass", grass)
	mat.set_shader_parameter("tile_m", Spec.GROUND.tile_m)
	mat.set_shader_parameter("beta", beta())
	mat.set_shader_parameter("rim_start", a.rim_start_m)
	mat.set_shader_parameter("rim_end", a.rim_end_m)
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
	env.tonemap_exposure = a.exposure
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
	return env


## The sun: a DirectionalLight3D shining from sun_direction(); PSSM shadows only with engine_shadows (L3).
static func create_sun(parent: Node) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.light_color = Spec.ATMOSPHERE.sun_color
	sun.light_energy = light_energy()
	sun.shadow_enabled = engine_shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = Spec.ATMOSPHERE.shadow_max_distance_m
	# The light shines along its −Z: toward the origin from the sun's side. Built directly (no scene tree needed).
	sun.transform = Transform3D(Basis.looking_at(-sun_direction(), Vector3.UP), sun_direction() * 100.0)
	parent.add_child(sun)
	return sun
