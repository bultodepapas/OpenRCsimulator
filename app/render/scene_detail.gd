## VQ-06b: the Scene detail preset. One saved choice maps onto existing knobs: the scenery prop tier
## (SC-24), which field trees render in 3D (L8a-R1), worn-path turf and the viewport's mesh LOD threshold.
## Prop selection also determines ornament collision at the next world build (LU-05).
## Existing sessions keep their installed collision world; field-tree collision is unchanged.
## Precedence: --scene_detail=<level> after --, then OPENRC_SCENE_DETAIL, then the player's saved
## preference, then the default. The scene parts apply when the world is next built. "auto" (the
## saved default) resolves through detected() at each launch; tools without a preference keep High.
## VQ-07h: AutoGraphicsPolicy first asks the GPU capability table (render/gpu_capability.gd); the basic profile covers unknown
## GPUs. detected() adds this host's Extreme facts (A4) and the measured first-flight verdict.
extends RefCounted

const GpuCapability := preload("res://render/gpu_capability.gd")
const AutoGraphicsPolicy := preload("res://render/auto_graphics_policy.gd")
const Reconstruction := preload("res://render/reconstruction.gd")
const AutoCalibration := preload("res://render/auto_calibration.gd")
const LEVELS: Array[String] = ["low", "medium", "high", "extreme"]
const DEFAULT := "high"
const AUTO := "auto"
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
	return calibrated(automatic(), RenderingServer.get_video_adapter_name())


## The Automatic recommendation for this host before any measured verdict.
static func automatic() -> Dictionary:
	if adapter_override.size() == 2:
		return recommend(adapter_override[0], adapter_override[1])
	return AutoGraphicsPolicy.scene_detail(RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(), _native_render_pixels(), extreme_facts())


static var _extreme_facts: Dictionary = {}


## VQ-07h-A4: this host's facts for Automatic Extreme (AutoGraphicsPolicy.extreme): the screen judged as by
## Automatic High, the CPU's logical threads and whether High (Forward+) is actually running. Read once per
## launch, so moving the window to another screen cannot flip the level between the world build and Settings.
static func extreme_facts() -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {}
	if _extreme_facts.is_empty():
		var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
		_extreme_facts = {os = OS.get_name(), arm64 = OS.has_feature("arm64"), pixels = AutoGraphicsPolicy.startup_output_pixels if AutoGraphicsPolicy.startup_output_pixels > 0 else screen.x * screen.y,
			cpu_threads = OS.get_processor_count(),
			forward_plus = RenderingServer.get_current_rendering_method() == AutoCalibration.HIGH_METHOD}
	return _extreme_facts


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
	if not bool(calibration.get("complete", false)) or offset == 0 \
			or str(calibration.get("adapter", "")) != AutoCalibration.adapter_key(adapter) \
			or str(calibration.get("method", "")) != RenderingServer.get_current_rendering_method() \
			or not AutoCalibration.size_matches(calibration, _output_pixels()) \
			or not AutoCalibration.workload_matches(calibration, AutoCalibration.current_workload()):
		return recommendation
	var shifted := recommendation.duplicate()
	shifted.level = AutoCalibration.apply_verdict(str(recommendation.level), calibration)
	shifted["calibrated"] = shifted.level != recommendation.level
	return shifted


## VQ-07h / AGENTS display exception: a Retina Mac targets its panel's native resolution, so Automatic judges the
## GPU against the pixels it renders there (MetalFX Automatic included). Other systems keep the 1080p reference.
static func _native_render_pixels() -> int:
	if DisplayServer.get_name() == "headless" or not OS.has_feature("arm64") \
			or not GpuCapability.mac_native_target(OS.get_name(), DisplayServer.screen_get_scale()):
		return AutoGraphicsPolicy.startup_output_pixels
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	return GpuCapability.mac_render_pixels(screen, _applied_3d_scale(screen))


## Audit 2026-11-19 F06: the 3D scale the root viewport really renders with once its reconstruction is applied
## (an explicit choice, Automatic, or a provider fallback after a runtime failure). Before that, the scale
## Automatic reconstruction would select here: MetalFX when available, else Native.
static func _applied_3d_scale(screen: Vector2i) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null and tree.root.has_meta(Reconstruction.POLICY_META):
		var scale := tree.root.scaling_3d_scale
		if is_finite(scale) and scale > 0.0:
			return scale
	var mode := Reconstruction.auto_mode(Reconstruction.runtime_capabilities(), screen)
	return float(Reconstruction.SCALES.get(mode, 1.0))


static func recommend(adapter_name: String, vendor: String, render_pixels: int = 0) -> Dictionary:
	return AutoGraphicsPolicy.scene_detail(adapter_name, vendor, render_pixels)


static func profile(detail_level: String = "") -> Dictionary:
	return PROFILES[detail_level if LEVELS.has(detail_level) else level()]


## Applies the saved choice: the viewport's LOD threshold at once, the scene parts at the next build.
static func apply(viewport: Viewport, saved_level: String) -> void:
	set_preference(saved_level)
	viewport.mesh_lod_threshold = float(profile().mesh_lod_threshold_px)
