## VQ-07: High presentation follows the selected native Forward+ renderer.
## The launcher selects the renderer before engine initialization; inspect the actual result.
extends RefCounted

const ShadowSettings := preload("res://render/shadow_settings.gd")

const ENVIRONMENT_KEY := "OPENRC_GRAPHICS_PROFILE"
const RESEARCH_ENVIRONMENT_KEY := "OPENRC_GRAPHICS_RESEARCH"
const CONTACT_ENVIRONMENT_KEY := "OPENRC_CONTACT_SHADOWS"
const CONTACT_SHADOW_SETTING := "rendering/lights_and_shadows/contact_shadow/enabled"
const CONTACT_THICKNESS_SETTING := "rendering/lights_and_shadows/contact_shadow/surface_thickness"
const CONTACT_LENGTH_SETTING := "rendering/lights_and_shadows/contact_shadow/shadow_length"
static var _configured := false
static var _reported := false

static func requested() -> String:
	return OS.get_environment(ENVIRONMENT_KEY).strip_edges().to_lower()

static func active() -> bool:
	return _active_for(requested(), RenderingServer.get_current_rendering_method(), DisplayServer.get_name())

static func _active_for(profile: String, renderer: String, display: String) -> bool:
	return profile in ["", "high"] and renderer == "forward_plus" and display != "headless"

static func supports_contact_shadows() -> bool:
	for property: Dictionary in ClassDB.class_get_property_list("DirectionalLight3D"):
		if property.name == "shadow_contact_shadows_blur":
			return true
	return false

static func contact_shadows_requested() -> bool:
	return active() and supports_contact_shadows() \
		and OS.get_environment(CONTACT_ENVIRONMENT_KEY).strip_edges().to_lower() == "on"

static func describe() -> Dictionary:
	var result := {"requested": requested(), "active": "high" if active() else "standard",
		"renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name()}
	var raw := OS.get_environment(RESEARCH_ENVIRONMENT_KEY)
	if raw.is_empty():
		return result
	var parser := JSON.new()
	if parser.parse(raw) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		result["research"] = {"error": "invalid launcher research identity"}
		return result
	var identity: Dictionary = parser.data
	for key: String in ["requested_method", "requested_driver", "requested_effects", "requested_reconstruction",
			"project_name", "project_sha256", "profile_sha256"]:
		if typeof(identity.get(key)) != TYPE_STRING:
			result["research"] = {"error": "incomplete launcher research identity"}
			return result
	var actual_name := str(ProjectSettings.get_setting("application/config/name", ""))
	var actual_driver := RenderingServer.get_current_rendering_driver_name()
	# These are renderer/profile observations, not proof of shader parity or MetalFX execution.
	result["research"] = {
		"requested_method": identity.requested_method, "requested_driver": identity.requested_driver,
		"requested_effects": identity.requested_effects, "requested_reconstruction": identity.requested_reconstruction,
		"effective_method": result.renderer, "effective_driver": actual_driver,
		"effective_profile": result.active, "method_matches": result.renderer == identity.requested_method,
		"driver_matches": actual_driver == identity.requested_driver,
		"requested_project_name": identity.project_name, "effective_project_name": actual_name,
		"user_directory_name_matches": OS.get_user_data_dir().get_file() == identity.project_name,
		"project_sha256_at_launch": identity.project_sha256, "profile_sha256_at_launch": identity.profile_sha256,
		"multi_bounce_occlusion_project_setting": ProjectSettings.get_setting(
			"rendering/lights_and_shadows/multi_bounce_occlusion/enabled", false),
	}
	return result

static func restart_arguments(profile: String, editor_binary: bool, project_path: String) -> PackedStringArray:
	if profile not in ["standard", "high"]:
		return PackedStringArray()
	var args := PackedStringArray()
	if editor_binary:
		args.append_array(["--path", project_path])
	args.append_array(["--rendering-method", "forward_plus" if profile == "high" else "gl_compatibility"])
	return args

static func configure() -> void:
	ShadowSettings.ensure_configured(active())
	if not _reported and not requested().is_empty():
		print("Graphics profile: ", JSON.stringify(describe()))
		_reported = true
	if not active() or _configured:
		return
	# Global directional allocation belongs to ShadowSettings, including live preview/revert.
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
	if not supports_contact_shadows():
		return
	sun.set("shadow_contact_shadows_allow", true)
	# Native AA has no temporal denoising; the beta1 default adds visible stipple to walls.
	# Keep the short contact term sharp; ordinary PCSS still supplies distant penumbrae.
	sun.set("shadow_contact_shadows_blur", 0.0)

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
