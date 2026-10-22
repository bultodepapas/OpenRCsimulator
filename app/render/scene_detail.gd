## VQ-06b: the Scene detail preset. One saved choice maps onto existing knobs: the scenery prop tier
## (SC-24), which field trees render in 3D (L8a-R1) and the viewport's mesh LOD threshold.
## Presentation only: collision, simulation and replays never read it.
## Precedence: --scene_detail=<level> after --, then OPENRC_SCENE_DETAIL, then the player's saved
## preference, then the default. The scene parts apply when the world is next built. "auto" (the
## saved default) resolves through recommend() at each launch; tools without a preference keep High.
extends RefCounted

const LEVELS: Array[String] = ["low", "medium", "high", "extreme"]
const DEFAULT := "high"
const AUTO := "auto"
# VQ-06b-R1: Godot 4.7.2's Compatibility driver reports no device type (always DEVICE_TYPE_OTHER),
# so Automatic classifies the GL renderer/vendor strings. Discrete markers are checked before
# integrated ones ("Intel Arc", "Radeon RX"). Unknown GPUs keep High; Extreme is never automatic.
const SOFTWARE_MARKERS: Array[String] = ["llvmpipe", "softpipe", "lavapipe", "swiftshader",
	"microsoft basic render", "gdi generic", "software rasterizer"]
const ENTRY_DISCRETE_MARKERS: Array[String] = ["geforce mx", "geforce gt ", "geforce 9", "geforce 8"]
const DISCRETE_MARKERS: Array[String] = ["geforce", "rtx", "quadro", "radeon rx", "radeon pro", "radeon r9",
	"radeon r7", "firepro", "intel(r) arc", "intel arc", "arc(tm)"]
const INTEGRATED_MARKERS: Array[String] = ["intel", "uhd graphics", "iris", "hd graphics", "radeon(tm) graphics",
	"radeon graphics", "radeon vega", "radeon(tm) vega", "apple m"]
const MOBILE_MARKERS: Array[String] = ["adreno", "mali", "powervr", "tegra"]
# scenery_quality: Scenery tier filter. field_tree_half_angle_deg: 3D field trees within this angle
# of the runway as seen from the pilot (0 = cards only; 180 = the whole near ring).
# mesh_lod_threshold_px: Godot's per-viewport LOD error; 1 px is its perceptually lossless default.
const PROFILES := {
	"low": {"scenery_quality": "low", "field_tree_half_angle_deg": 0.0, "mesh_lod_threshold_px": 4.0},
	"medium": {"scenery_quality": "balanced", "field_tree_half_angle_deg": 0.0, "mesh_lod_threshold_px": 2.0},
	"high": {"scenery_quality": "high", "field_tree_half_angle_deg": 60.0, "mesh_lod_threshold_px": 1.0},
	"extreme": {"scenery_quality": "high", "field_tree_half_angle_deg": 180.0, "mesh_lod_threshold_px": 1.0},
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
		return recommend(adapter_override[0], adapter_override[1])
	return recommend(RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor())


static func recommend(adapter_name: String, vendor: String) -> Dictionary:
	var gpu := (adapter_name + " " + vendor).strip_edges().to_lower()
	if gpu.is_empty():
		return {level = DEFAULT, reason = "no GPU reported"}
	for rule: Array in [[SOFTWARE_MARKERS, "low", "software renderer"], [MOBILE_MARKERS, "low", "mobile GPU"],
			[ENTRY_DISCRETE_MARKERS, "medium", "entry-level GPU"], [DISCRETE_MARKERS, "high", "dedicated GPU"],
			[INTEGRATED_MARKERS, "medium", "integrated GPU"]]:
		for marker: String in rule[0]:
			if gpu.contains(marker):
				return {level = rule[1], reason = rule[2]}
	return {level = DEFAULT, reason = "unrecognized GPU"}


static func profile(detail_level: String = "") -> Dictionary:
	return PROFILES[detail_level if LEVELS.has(detail_level) else level()]


## Applies the saved choice: the viewport's LOD threshold at once, the scene parts at the next build.
static func apply(viewport: Viewport, saved_level: String) -> void:
	set_preference(saved_level)
	viewport.mesh_lod_threshold = float(profile().mesh_lod_threshold_px)
