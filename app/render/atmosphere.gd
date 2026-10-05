# Atmosphere (LANDSCAPE-PLAN L1a; L2 adds haze): ONE source of truth, Spec.ATMOSPHERE, for the sky shader's uniforms,
# the Environment and the sun's DirectionalLight3D, so the sky, the light and (later) the fog can never disagree.
extends RefCounted

const Spec := preload("res://spec.gd")
const Frames := preload("res://render/frames.gd")
const SKY_SHADER := preload("res://render/sky.gdshader")


## Unit vector toward the sun in render axes (the light shines along the opposite direction).
static func sun_direction() -> Vector3:
	var az := deg_to_rad(Spec.ATMOSPHERE.sun_azimuth_deg)
	var el := deg_to_rad(Spec.ATMOSPHERE.sun_elevation_deg)
	return Frames.ned_to_render([cos(az) * cos(el), sin(az) * cos(el), -sin(el)]).normalized()


static func sky_material() -> ShaderMaterial:
	var a: Dictionary = Spec.ATMOSPHERE
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	mat.set_shader_parameter("zenith_color", a.zenith)
	mat.set_shader_parameter("horizon_color", a.horizon)
	mat.set_shader_parameter("ground_color", a.below_horizon)
	mat.set_shader_parameter("gradient_curve", a.gradient_curve)
	mat.set_shader_parameter("sun_radius", deg_to_rad(a.sun_diameter_deg) / 2.0)
	return mat


## The world environment: the sky drawn per pixel as background; its radiance (rendered once, QUALITY) lights the
## scene as ambient light and reflections (L1a). L1b: ACES at exposure 0.6, glow off. Chosen by L1b's own proof in the
## real harness: Filmic 0.8 (the plan's pick from a spike) gave the 3 m airplane contrast −0.36 and ΔE 29.6; ACES 0.6
## was the only setting swept that passes all thresholds (contrast −0.43, ΔE 30.7, sky saturation 55).
static func environment() -> Environment:
	var sky := Sky.new()
	sky.sky_material = sky_material()
	sky.process_mode = Sky.PROCESS_MODE_QUALITY # deterministic radiance, rendered once (no TIME in the shader)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = Spec.ATMOSPHERE.exposure
	env.tonemap_white = Spec.ATMOSPHERE.white
	env.glow_enabled = false
	return env


## The sun: a DirectionalLight3D shining from sun_direction() (the sky shader draws its disc from this light).
static func create_sun(parent: Node) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	parent.add_child(sun)
	sun.look_at_from_position(sun_direction() * 100.0, Vector3.ZERO, Vector3.UP)
	return sun
