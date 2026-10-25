# CAM-17: the player's camera preferences, stored as optional keys of display.cfg [camera] (app_state/
# display_preferences.gd). Presentation only. Home flights receive them through main.gd/helicopter_main.gd
# `camera_preferences`; direct and automation routes never read them, so captures and traces keep their pictures.
extends RefCounted

const PilotCamera := preload("res://render/pilot_camera.gd")

## The view a Home flight starts in (D1: the pilot view stays the default).
const VIEWS: Array[String] = ["pilot", "chase", "flyby", "orbit"]
## The pilot view's widest vertical FOV (deg), which the auto-zoom narrows from. 50° stays the default until CAM-22;
## about 31° is orthoscopic on a 27-inch 16:9 screen seen from 60 cm (CAM-AUD-2026-10-24).
const FOVS: Array[int] = [30, 35, 40, 45, 50, 55, 60, 70]
## Multipliers of the orbit's mouse and stick turn rate, and of the chase boom.
const SENSITIVITIES: Array[float] = [0.5, 0.75, 1.0, 1.5, 2.0]
const CHASE_DISTANCES: Array[float] = [0.6, 0.8, 1.0, 1.25, 1.5]
## CAM-18 magnifier inset modes (mirrors render/camera/magnifier.gd MODES).
const MAGNIFIER_MODES: Array[String] = ["off", "auto", "on"]
## CAM-06/06b/28 pilot aids: off (today's picture) until the pilot chooses them in CAM-22.
const DEFAULTS := {
	"camera_view": "pilot",
	"camera_fov": 50,
	"camera_auto_zoom": true,
	"camera_zoom_law": "constant",
	"camera_horizon_bias": false,
	"camera_overhead_smoothing": false,
	"camera_magnifier": "off",
	"camera_chase_distance": 1.0,
	"camera_sensitivity": 1.0,
	"camera_invert_y": false,
}


## Errors for the camera keys present in `raw` (absent keys take their defaults).
static func errors(raw: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(raw.get("camera_view", DEFAULTS.camera_view)) != TYPE_STRING or raw.get("camera_view", DEFAULTS.camera_view) not in VIEWS:
		out.append("camera_view must be pilot, chase, flyby or orbit")
	if typeof(raw.get("camera_fov", DEFAULTS.camera_fov)) != TYPE_INT or raw.get("camera_fov", DEFAULTS.camera_fov) not in FOVS:
		out.append("camera_fov must be one of the offered fields of view")
	if typeof(raw.get("camera_magnifier", DEFAULTS.camera_magnifier)) != TYPE_STRING or raw.get("camera_magnifier", DEFAULTS.camera_magnifier) not in MAGNIFIER_MODES:
		out.append("camera_magnifier must be off, auto or on")
	if typeof(raw.get("camera_zoom_law", DEFAULTS.camera_zoom_law)) != TYPE_STRING or raw.get("camera_zoom_law", DEFAULTS.camera_zoom_law) not in PilotCamera.ZOOM_LAWS:
		out.append("camera_zoom_law must be constant, partial or gentle")
	for key: String in ["camera_auto_zoom", "camera_invert_y", "camera_horizon_bias", "camera_overhead_smoothing"]:
		if typeof(raw.get(key, DEFAULTS[key])) != TYPE_BOOL:
			out.append("%s must be a boolean" % key)
	for pair: Array in [["camera_chase_distance", CHASE_DISTANCES], ["camera_sensitivity", SENSITIVITIES]]:
		var value: Variant = raw.get(pair[0], DEFAULTS[pair[0]])
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not (pair[1] as Array).any(func(v: float) -> bool: return is_equal_approx(v, float(value))):
			out.append("%s must be one of the offered values" % pair[0])
	return out


## The camera keys of `raw`, normalized; call after errors() is empty.
static func normalized(raw: Dictionary) -> Dictionary:
	return {
		"camera_view": str(raw.get("camera_view", DEFAULTS.camera_view)),
		"camera_fov": int(raw.get("camera_fov", DEFAULTS.camera_fov)),
		"camera_auto_zoom": bool(raw.get("camera_auto_zoom", DEFAULTS.camera_auto_zoom)),
		"camera_zoom_law": str(raw.get("camera_zoom_law", DEFAULTS.camera_zoom_law)),
		"camera_horizon_bias": bool(raw.get("camera_horizon_bias", DEFAULTS.camera_horizon_bias)),
		"camera_overhead_smoothing": bool(raw.get("camera_overhead_smoothing", DEFAULTS.camera_overhead_smoothing)),
		"camera_magnifier": str(raw.get("camera_magnifier", DEFAULTS.camera_magnifier)),
		"camera_chase_distance": float(raw.get("camera_chase_distance", DEFAULTS.camera_chase_distance)),
		"camera_sensitivity": float(raw.get("camera_sensitivity", DEFAULTS.camera_sensitivity)),
		"camera_invert_y": bool(raw.get("camera_invert_y", DEFAULTS.camera_invert_y)),
	}


## A flight's start: every preference, including the first view and the chase boom.
static func apply_at_start(rig: RefCounted, preferences: Dictionary) -> void:
	var config := normalized(preferences)
	rig.set_view(config.camera_view)
	rig.auto_zoom = config.camera_auto_zoom
	rig.chase.zoom = config.camera_chase_distance
	apply_live(rig, config)


## A change made in Settings during a flight: the field of view and the orbit controls apply at once; the first view,
## auto-zoom and chase distance only when they changed, so a key the pilot pressed in flight is not undone.
static func apply_changes(rig: RefCounted, before: Dictionary, after: Dictionary) -> void:
	var old := normalized(before)
	var config := normalized(after)
	if config.camera_auto_zoom != old.camera_auto_zoom and rig.auto_zoom != config.camera_auto_zoom:
		rig.toggle_auto_zoom()
	if not is_equal_approx(config.camera_chase_distance, old.camera_chase_distance):
		rig.chase.zoom = config.camera_chase_distance
	apply_live(rig, config)


static func apply_live(rig: RefCounted, config: Dictionary) -> void:
	rig.set_base_fov(float(config.camera_fov))
	rig.set_zoom_law(str(config.camera_zoom_law))
	rig.horizon_bias = bool(config.camera_horizon_bias)
	rig.overhead_smoothing = bool(config.camera_overhead_smoothing)
	rig.magnifier = str(config.camera_magnifier)
	rig.orbit.sensitivity = float(config.camera_sensitivity)
	rig.orbit.invert_y = bool(config.camera_invert_y)
