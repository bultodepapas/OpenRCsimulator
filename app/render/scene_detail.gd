## VQ-06b: the Scene detail preset. One saved choice maps onto existing knobs: the scenery prop tier
## (SC-24), which field trees render in 3D (L8a-R1) and the viewport's mesh LOD threshold.
## Presentation only: collision, simulation and replays never read it.
## Precedence: --scene_detail=<level> after --, then OPENRC_SCENE_DETAIL, then the player's saved
## preference, then the default. The scene parts apply when the world is next built.
extends RefCounted

const LEVELS: Array[String] = ["low", "medium", "high", "extreme"]
const DEFAULT := "high"
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
	_preference = level if LEVELS.has(level) else ""


static func level() -> String:
	var requested := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--scene_detail="):
			requested = argument.trim_prefix("--scene_detail=").strip_edges().to_lower()
	if requested.is_empty():
		requested = OS.get_environment("OPENRC_SCENE_DETAIL").strip_edges().to_lower()
	if requested.is_empty():
		requested = _preference
	if not LEVELS.has(requested):
		if not requested.is_empty() and not _warned.has(requested):
			_warned[requested] = true
			push_warning("Unknown scene detail '%s'; using %s" % [requested, DEFAULT])
		return DEFAULT
	return requested


static func profile(detail_level: String = "") -> Dictionary:
	return PROFILES[detail_level if LEVELS.has(detail_level) else level()]


## Applies the saved choice: the viewport's LOD threshold at once, the scene parts at the next build.
static func apply(viewport: Viewport, saved_level: String) -> void:
	set_preference(saved_level)
	viewport.mesh_lod_threshold = float(profile().mesh_lod_threshold_px)
