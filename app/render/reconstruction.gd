## VQ-07d: main-view reconstruction; presentation only, never simulation state.
extends RefCounted

const HighGraphics := preload("res://render/high_graphics_profile.gd")
const MODES: Array[String] = ["native", "fsr2_native", "fsr2_quality"]
const ENVIRONMENT_KEY := "OPENRC_RECONSTRUCTION"


static func available() -> bool:
	return HighGraphics.active()


static func resolve(requested: String, high_available: bool) -> Dictionary:
	var effective := requested if high_available and requested in MODES else "native"
	return {"requested": requested, "effective": effective,
		"scale": 2.0 / 3.0 if effective == "fsr2_quality" else 1.0,
		"temporal": effective != "native"}


## Direct/technical launches may select a candidate without reading player preferences.
static func startup_config() -> Dictionary:
	return {"reconstruction": OS.get_environment(ENVIRONMENT_KEY).strip_edges().to_lower()
		if OS.has_environment(ENVIRONMENT_KEY) else "native"}


static func apply(viewport: Viewport, config: Dictionary) -> void:
	var policy := resolve(str(config.get("reconstruction", "native")), available())
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if policy.temporal else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = float(policy.scale)
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
	policy["output_size"] = [viewport.get_visible_rect().size.x, viewport.get_visible_rect().size.y]
	return policy

