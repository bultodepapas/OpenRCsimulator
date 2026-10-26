## VQ-07: opt-in native High experiment. Never selected by GPU name or saved preferences.
## The launcher selects the renderer before engine initialization; inspect the actual result.
extends RefCounted

const ENVIRONMENT_KEY := "OPENRC_GRAPHICS_PROFILE"
const CONTACT_ENVIRONMENT_KEY := "OPENRC_CONTACT_SHADOWS"
const CONTACT_SHADOW_SETTING := "rendering/lights_and_shadows/contact_shadow/enabled"
const CONTACT_THICKNESS_SETTING := "rendering/lights_and_shadows/contact_shadow/surface_thickness"
const CONTACT_LENGTH_SETTING := "rendering/lights_and_shadows/contact_shadow/shadow_length"
static var _configured := false
static var _reported := false

static func requested() -> String:
	return OS.get_environment(ENVIRONMENT_KEY).strip_edges().to_lower()

static func active() -> bool:
	return requested() == "high" and RenderingServer.get_current_rendering_method() == "forward_plus" \
		and DisplayServer.get_name() != "headless"

static func contact_shadows_requested() -> bool:
	return active() and OS.get_environment(CONTACT_ENVIRONMENT_KEY).strip_edges().to_lower() == "on"

static func describe() -> Dictionary:
	return {"requested": requested(), "active": "high_experimental" if active() else "standard",
		"renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name()}

static func restart_arguments(profile: String, editor_binary: bool, project_path: String) -> PackedStringArray:
	if profile not in ["standard", "high"]:
		return PackedStringArray()
	var args := PackedStringArray()
	if editor_binary:
		args.append_array(["--path", project_path])
	args.append_array(["--rendering-method", "forward_plus" if profile == "high" else "gl_compatibility"])
	return args

static func configure() -> void:
	if not _reported and not requested().is_empty():
		print("Graphics profile: ", JSON.stringify(describe()))
		_reported = true
	if not active() or _configured:
		return
	# Four cascades share the atlas. Preserve distant field coverage while improving near detail.
	RenderingServer.directional_shadow_atlas_set_size(8192, false)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	# Beta1 produces visible surface artifacts with Native AA. Keep this explicit
	# experiment off by default until paired visual acceptance improves.
	ProjectSettings.set_setting(CONTACT_SHADOW_SETTING, contact_shadows_requested())
	ProjectSettings.set_setting(CONTACT_THICKNESS_SETTING, 0.01)
	ProjectSettings.set_setting(CONTACT_LENGTH_SETTING, 0)
	_configured = true

static func apply_environment(env: Environment) -> void:
	configure()
	if not active():
		return
	# Short-range ambient occlusion grounds aircraft gear, benches and pavilion joints.
	# Keep direct sunlight untouched; no compulsory bloom, temporal AA or extra fog.
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.2
	env.ssao_power = 1.3
	env.ssao_detail = 0.5
	env.ssao_light_affect = 0.0
	# Forward+ stores sky radiance in linear HDR; the Compatibility double-exposure
	# workaround need not suppress sky reflections on paint, canopy and metal here.
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

static func apply_sun(sun: DirectionalLight3D) -> void:
	configure()
	if not active():
		return
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.20
	sun.directional_shadow_split_3 = 0.50
	# Approximate solar angular diameter; stock PCSS provides contact-hardening penumbrae.
	sun.light_angular_distance = 0.53
	sun.shadow_contact_shadows_allow = true
	# Native AA has no temporal denoising; the beta1 default adds visible stipple to walls.
	# Keep the short contact term sharp; ordinary PCSS still supplies distant penumbrae.
	sun.shadow_contact_shadows_blur = 0.0

## Only a flowing High world pays for dynamic radiance filtering. Frozen worlds
## retain QUALITY; realtime filtering uses Godot's required 256-pixel cubemap.
static func configure_flow_sky(env: Environment) -> void:
	if not active() or env.sky == null:
		return
	env.sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky.process_mode = Sky.PROCESS_MODE_REALTIME

static func supports_frame_sky(env: Environment) -> bool:
	return active() and env.sky != null and env.sky.process_mode == Sky.PROCESS_MODE_REALTIME \
		and env.sky.radiance_size == Sky.RADIANCE_SIZE_256
