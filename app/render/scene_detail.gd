## VQ-06b: the Scene detail preset. One saved choice maps onto existing knobs: the scenery prop tier
## (SC-24), which field trees render in 3D (L8a-R1), worn-path turf and the viewport's mesh LOD threshold.
## Prop selection also determines ornament collision at the next world build (LU-05).
## Existing sessions keep their installed collision world; field-tree collision is unchanged.
## Precedence: --scene_detail=<level> after --, then OPENRC_SCENE_DETAIL, then the player's saved
## preference, then the default. The scene parts apply when the world is next built. "auto" (the
## saved default) resolves through recommend() at each launch; tools without a preference keep High.
## VQ-07h: recommend() first asks the GPU capability table (render/gpu_capability.gd); markers cover unknown GPUs.
extends RefCounted

const GpuCapability := preload("res://render/gpu_capability.gd")
const AutoGraphicsPolicy := preload("res://render/auto_graphics_policy.gd")
const Reconstruction := preload("res://render/reconstruction.gd")
const AutoCalibration := preload("res://render/auto_calibration.gd")
const LEVELS: Array[String] = ["low", "medium", "high", "extreme"]
const DEFAULT := "high"
const AUTO := "auto"
const AUTO_FALLBACK := "medium"
# VQ-06b-R1: Godot 4.7.2's Compatibility driver reports no device type (always DEVICE_TYPE_OTHER),
# so Automatic classifies the GL renderer/vendor strings. Discrete markers are checked before
# integrated ones ("Intel Arc", "Radeon RX"). Unknown GPUs start at Medium; Extreme is never automatic.
const SOFTWARE_MARKERS := AutoGraphicsPolicy.SOFTWARE_MARKERS
const ENTRY_DISCRETE_MARKERS := AutoGraphicsPolicy.ENTRY_DISCRETE_MARKERS
const DISCRETE_MARKERS := AutoGraphicsPolicy.DISCRETE_MARKERS
const INTEGRATED_MARKERS := AutoGraphicsPolicy.INTEGRATED_MARKERS
const MOBILE_MARKERS := AutoGraphicsPolicy.MOBILE_MARKERS
# scenery_quality: Scenery tier filter. field_tree_half_angle_deg: 3D field trees within this angle
# of the runway as seen from the pilot (0 = cards only; 180 = the whole near ring).
# mesh_lod_threshold_px: Godot's per-viewport LOD error; 1 px is its perceptually lossless default.
# worn_path_turf: L9b-R3 field-texture blending; lower presets skip its binding and shader samples.
const PROFILES := {
	"low": {"scenery_quality": "low", "field_tree_half_angle_deg": 0.0, "mesh_lod_threshold_px": 4.0, "worn_path_turf": false},
	"medium": {"scenery_quality": "balanced", "field_tree_half_angle_deg": 0.0, "mesh_lod_threshold_px": 2.0, "worn_path_turf": false},
	"high": {"scenery_quality": "high", "field_tree_half_angle_deg": 60.0, "mesh_lod_threshold_px": 1.0, "worn_path_turf": true},
	"extreme": {"scenery_quality": "high", "field_tree_half_angle_deg": 180.0, "mesh_lod_threshold_px": 1.0, "worn_path_turf": true},
}

static var _preference := ""
static var _warned := {}


## The player's saved choice (Settings > Graphics); unknown values fall back to the default.
static func set_preference(level: String) -> void:
	_preference = level if LEVELS.has(level) or level == AUTO else ""


static func level() -> String:
	var requested := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--scene_detail="):
			requested = argument.trim_prefix("--scene_detail=").strip_edges().to_lower()
	if requested.is_empty():
		requested = OS.get_environment("OPENRC_SCENE_DETAIL").strip_edges().to_lower()
	if requested.is_empty():
		requested = _preference
	if requested == AUTO:
		return str(detected().level)
	if not LEVELS.has(requested):
		if not requested.is_empty() and not _warned.has(requested):
			_warned[requested] = true
			push_warning("Unknown scene detail '%s'; using %s" % [requested, DEFAULT])
		return DEFAULT
	return requested


## The level Automatic picks for this GPU, with the reason shown in Settings. Tests may set
## adapter_override to [name, vendor]; headless runs report no GPU.
static var adapter_override: PackedStringArray = []


static func detected() -> Dictionary:
	if adapter_override.size() == 2:
		return calibrated(recommend(adapter_override[0], adapter_override[1]), adapter_override[0])
	var adapter := RenderingServer.get_video_adapter_name()
	return calibrated(recommend(adapter, RenderingServer.get_video_adapter_vendor(), _native_render_pixels()), adapter)


## VQ-07h: the measured first-flight verdict for this GPU (render/auto_calibration.gd), set by AppRoot.
static var calibration: Dictionary = {}


static func _output_pixels() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return 0
	return tree.root.size.x * tree.root.size.y


## Shifts an Automatic recommendation by the stored calibration measured on this adapter and renderer at a
## similar output size.
static func calibrated(recommendation: Dictionary, adapter: String) -> Dictionary:
	var offset := int(calibration.get("scene_offset", 0))
	if offset == 0 or str(calibration.get("adapter", "")) != AutoCalibration.adapter_key(adapter) \
			or str(calibration.get("method", "")) != RenderingServer.get_current_rendering_method() \
			or not AutoCalibration.size_matches(calibration, _output_pixels()):
		return recommendation
	var shifted := recommendation.duplicate()
	shifted.level = AutoCalibration.shifted_level(str(recommendation.level), offset)
	shifted["calibrated"] = shifted.level != recommendation.level
	return shifted


## VQ-07h / AGENTS display exception: a Retina Mac targets its panel's native resolution, so Automatic judges the
## GPU against the pixels it renders there (MetalFX Automatic included). Other systems keep the 1080p reference.
static func _native_render_pixels() -> int:
	if DisplayServer.get_name() == "headless" or not OS.has_feature("arm64") \
			or not GpuCapability.mac_native_target(OS.get_name(), DisplayServer.screen_get_scale()):
		return 0
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	# The scale Automatic reconstruction really selects here: MetalFX when available, else Native.
	var mode := Reconstruction.auto_mode(Reconstruction.runtime_capabilities(), screen)
	return GpuCapability.mac_render_pixels(screen, float(Reconstruction.SCALES.get(mode, 1.0)))


static func recommend(adapter_name: String, vendor: String, render_pixels: int = 0) -> Dictionary:
	return AutoGraphicsPolicy.scene_detail(adapter_name, vendor, render_pixels)


static func profile(detail_level: String = "") -> Dictionary:
	return PROFILES[detail_level if LEVELS.has(detail_level) else level()]


## Applies the saved choice: the viewport's LOD threshold at once, the scene parts at the next build.
static func apply(viewport: Viewport, saved_level: String) -> void:
	set_preference(saved_level)
	viewport.mesh_lod_threshold = float(profile().mesh_lod_threshold_px)
