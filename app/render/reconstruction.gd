## VQ-07d: main-view reconstruction; presentation only, never simulation state.
extends RefCounted

const HighGraphics := preload("res://render/high_graphics_profile.gd")
const MODES: Array[String] = ["native", "fsr2_native", "fsr2_85", "fsr2_quality", "fsr2_balanced", "fsr2_performance"]
const SCALES := {"native": 1.0, "fsr2_native": 1.0, "fsr2_quality": 2.0 / 3.0,
	"fsr2_85": 0.85, "fsr2_balanced": 1.0 / 1.7, "fsr2_performance": 0.5}
const DEFAULT_SHARPNESS := 0.9 # User strength; matches Godot's default fsr_sharpness=0.2.
const ENVIRONMENT_KEY := "OPENRC_RECONSTRUCTION"


static func available() -> bool:
	return HighGraphics.active()


static func resolve(requested: String, high_available: bool) -> Dictionary:
	var effective := requested if high_available and requested in MODES else "native"
	return {"requested": requested, "effective": effective,
		"scale": SCALES[effective],
		"temporal": effective != "native"}


## Direct/technical launches may select a candidate without reading player preferences.
static func startup_config() -> Dictionary:
	var strength := OS.get_environment("OPENRC_FSR2_SHARPNESS").strip_edges()
	return {"reconstruction": OS.get_environment(ENVIRONMENT_KEY).strip_edges().to_lower()
		if OS.has_environment(ENVIRONMENT_KEY) else "native",
		"fsr2_sharpness": sharpness_strength(strength.to_float() if strength.is_valid_float() else DEFAULT_SHARPNESS)}


static func sharpness_strength(value: Variant) -> float:
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)):
		return DEFAULT_SHARPNESS
	return clampf(float(value), 0.0, 1.0)


## Static technical captures need temporal history after the final pose/camera is set.
## At least two jitter cycles for our supported scales; bounded to 64 rendered frames.
static func capture_settle_frames(mode: int, scale: float) -> int:
	if mode != Viewport.SCALING_3D_MODE_FSR2:
		return 2
	var input_scale := clampf(scale, 0.5, 1.0)
	return clampi(ceili(8.0 / (input_scale * input_scale)) * 2, 16, 64)


static func apply(viewport: Viewport, config: Dictionary) -> void:
	var policy := resolve(str(config.get("reconstruction", "native")), available())
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if policy.temporal else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = float(policy.scale)
	# Godot 4.7.2 maps this back to SDK strength as 1 - fsr_sharpness / 2.
	# User zero disables RCAS; one is maximum. Never stack a second sharpening pass.
	viewport.fsr_sharpness = 2.0 * (1.0 - sharpness_strength(config.get("fsr2_sharpness", DEFAULT_SHARPNESS)))
	# FSR2 owns temporal AA. Retain the user's MSAA choice in config for native/Standard.
	viewport.msaa_3d = Viewport.MSAA_DISABLED if policy.temporal else int(config.get("msaa_3d", 2)) as Viewport.MSAA
	viewport.use_taa = false
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.set_meta(&"openrc_reconstruction", policy)


static func describe(viewport: Viewport) -> Dictionary:
	var policy: Dictionary = viewport.get_meta(&"openrc_reconstruction", resolve("native", available())).duplicate(true)
	policy["scaling_3d_mode"] = viewport.scaling_3d_mode
	policy["scale"] = viewport.scaling_3d_scale
	policy["msaa_3d"] = viewport.msaa_3d
	policy["fsr_sharpness"] = viewport.fsr_sharpness
	policy["sharpening_strength"] = 1.0 - viewport.fsr_sharpness / 2.0
	policy["sharpening_active"] = bool(policy.temporal) and viewport.fsr_sharpness < 2.0
	policy["texture_mipmap_bias"] = viewport.texture_mipmap_bias
	policy["output_size"] = [viewport.get_visible_rect().size.x, viewport.get_visible_rect().size.y]
	# Nominal dimensions, not a GPU allocation measurement (engine rounding may differ).
	policy["nominal_3d_size"] = [roundi(policy.output_size[0] * viewport.scaling_3d_scale),
		roundi(policy.output_size[1] * viewport.scaling_3d_scale)]
	return policy

