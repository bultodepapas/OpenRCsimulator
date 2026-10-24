# UI-24/UI-28: display, accessibility and menu audio use their own versioned file so settings.cfg's
# flight/profile contents and controller calibration remain untouched.
extends RefCounted

const DEFAULT_PATH := "user://display.cfg"
const SCHEMA := 1
const WINDOW_MODES: Array[String] = ["windowed", "borderless"]
const WINDOW_RESOLUTIONS: Array[String] = [
	"auto", "1280x720", "1280x800", "1600x900", "1920x1080", "1920x1200",
	"2560x1440", "2560x1600", "3440x1440", "3840x2160",
]
const MAX_FPS_VALUES: Array[int] = [0, 30, 60, 90, 120, 144, 165, 240]
const VSYNC_MODES: Array[String] = ["enabled", "disabled"]
const MSAA_3D_VALUES: Array[int] = [0, 1, 2, 3]
# VQ-06b: mirrors render/scene_detail.gd LEVELS (test_scene_detail.gd keeps them equal).
const SCENE_DETAILS: Array[String] = ["auto", "low", "medium", "high", "extreme"]
# SC-BIRD (birds-sky-life plan D2): mirrors scenery/birds/bird_director.gd PREFERENCES (test_birds.gd keeps them equal).
const BIRD_LEVELS: Array[String] = ["off", "few", "normal", "many"]
const DEFAULTS := {
	"window_mode": "windowed",
	"window_resolution": "auto",
	"max_fps": 0,
	"vsync_mode": "enabled",
	"msaa_3d": 2,
	"scene_detail": "auto",
	"birds": "normal",
	"ui_scale": 1.0,
	"opaque_panels": false,
	"reduced_motion": false,
	"menu_volume": 0.35,
	"master_volume": 1.0, # AUD-12b: whole-game level on the Master bus (flight, scenery, crash, menu)
}
const OPTIONAL_KEYS: Array[String] = [
	"menu_volume", "master_volume", "window_resolution", "max_fps", "vsync_mode", "msaa_3d", "scene_detail", "birds",
] # schema-1 extensions; older files and callers keep defaults
const AUDIO_LEVEL_KEYS: Array[String] = ["menu_volume", "master_volume"]

var path: String
var config: Dictionary
var writable := true
var note := ""


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path
	reload()


func reload() -> Dictionary:
	var loaded := load_from(path)
	config = _config_only(loaded)
	writable = bool(loaded.get("writable", true))
	note = str(loaded.get("note", ""))
	return loaded


func save(candidate: Dictionary) -> Error:
	if not writable:
		return ERR_FILE_NO_PERMISSION
	var checked := validate(candidate)
	if not checked.ok:
		return ERR_INVALID_DATA
	var err := save_to(path, checked.config)
	if err == OK:
		config = checked.config.duplicate(true)
		note = ""
	return err


## Return validated values plus file status. Invalid files are preserved as `.bad` for inspection.
static func load_from(file_path: String) -> Dictionary:
	var result := DEFAULTS.duplicate(true)
	result.writable = true
	result.note = ""
	if not FileAccess.file_exists(file_path):
		return result

	var cfg := ConfigFile.new()
	var load_error := cfg.load(file_path)
	if load_error != OK:
		return _preserve_bad_file(file_path, result, "display settings could not be read")
	var schema: Variant = cfg.get_value("meta", "schema", -1)
	if typeof(schema) != TYPE_INT or schema < 1:
		return _preserve_bad_file(file_path, result, "display settings have an invalid schema")
	if schema > SCHEMA:
		result.writable = false
		result.note = "display settings use a newer version and will not be overwritten"

	var raw := DEFAULTS.duplicate(true)
	raw.window_mode = cfg.get_value("display", "window_mode", DEFAULTS.window_mode)
	raw.window_resolution = cfg.get_value("display", "window_resolution", DEFAULTS.window_resolution)
	raw.ui_scale = cfg.get_value("display", "ui_scale", DEFAULTS.ui_scale)
	raw.max_fps = cfg.get_value("graphics", "max_fps", DEFAULTS.max_fps)
	raw.vsync_mode = cfg.get_value("graphics", "vsync_mode", DEFAULTS.vsync_mode)
	raw.msaa_3d = cfg.get_value("graphics", "msaa_3d", DEFAULTS.msaa_3d)
	raw.scene_detail = cfg.get_value("graphics", "scene_detail", DEFAULTS.scene_detail)
	raw.birds = cfg.get_value("graphics", "birds", DEFAULTS.birds)
	raw.opaque_panels = cfg.get_value("accessibility", "opaque_panels", DEFAULTS.opaque_panels)
	raw.reduced_motion = cfg.get_value("accessibility", "reduced_motion", DEFAULTS.reduced_motion)
	raw.menu_volume = cfg.get_value("audio", "menu_volume", DEFAULTS.menu_volume)
	raw.master_volume = cfg.get_value("audio", "master_volume", DEFAULTS.master_volume)
	var checked := validate(raw)
	if checked.ok:
		result.merge(checked.config, true)
	else:
		result.note = _append_note(result.note, "invalid display values were replaced with defaults")
	return result


static func save_to(file_path: String, candidate: Dictionary) -> Error:
	var checked := validate(candidate)
	if not checked.ok:
		return ERR_INVALID_DATA
	# Never overwrite a settings file from a future build, even if the caller skipped load_from().
	if FileAccess.file_exists(file_path):
		var existing := ConfigFile.new()
		if existing.load(file_path) == OK:
			var current_schema: Variant = existing.get_value("meta", "schema", -1)
			if typeof(current_schema) == TYPE_INT and current_schema > SCHEMA:
				return ERR_FILE_NO_PERMISSION

	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema", SCHEMA)
	cfg.set_value("display", "window_mode", checked.config.window_mode)
	cfg.set_value("display", "window_resolution", checked.config.window_resolution)
	cfg.set_value("display", "ui_scale", checked.config.ui_scale)
	cfg.set_value("graphics", "max_fps", checked.config.max_fps)
	cfg.set_value("graphics", "vsync_mode", checked.config.vsync_mode)
	cfg.set_value("graphics", "msaa_3d", checked.config.msaa_3d)
	cfg.set_value("graphics", "scene_detail", checked.config.scene_detail)
	cfg.set_value("graphics", "birds", checked.config.birds)
	cfg.set_value("accessibility", "opaque_panels", checked.config.opaque_panels)
	cfg.set_value("accessibility", "reduced_motion", checked.config.reduced_motion)
	cfg.set_value("audio", "menu_volume", checked.config.menu_volume)
	cfg.set_value("audio", "master_volume", checked.config.master_volume)
	return cfg.save(file_path)


## UI scale accepts any 5% increment from 100% through 200%.
static func validate(raw: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if not raw is Dictionary:
		return {"ok": false, "config": {}, "errors": PackedStringArray(["display settings must be a dictionary"])}
	for key: String in DEFAULTS:
		if not raw.has(key) and key not in OPTIONAL_KEYS:
			errors.append("missing %s" % key)
	if typeof(raw.get("window_mode")) != TYPE_STRING or raw.get("window_mode") not in WINDOW_MODES:
		errors.append("window_mode must be windowed or borderless")
	var resolution: Variant = raw.get("window_resolution", DEFAULTS.window_resolution)
	if typeof(resolution) != TYPE_STRING or resolution not in WINDOW_RESOLUTIONS:
		errors.append("window_resolution must be auto or a supported resolution")
	var max_fps: Variant = raw.get("max_fps", DEFAULTS.max_fps)
	if typeof(max_fps) != TYPE_INT or max_fps not in MAX_FPS_VALUES:
		errors.append("max_fps must be one of the supported frame limits")
	var vsync_mode: Variant = raw.get("vsync_mode", DEFAULTS.vsync_mode)
	if typeof(vsync_mode) != TYPE_STRING or vsync_mode not in VSYNC_MODES:
		errors.append("vsync_mode must be enabled or disabled")
	var msaa_3d: Variant = raw.get("msaa_3d", DEFAULTS.msaa_3d)
	if typeof(msaa_3d) != TYPE_INT or msaa_3d not in MSAA_3D_VALUES:
		errors.append("msaa_3d must be an integer from 0 through 3")
	var scene_detail: Variant = raw.get("scene_detail", DEFAULTS.scene_detail)
	if typeof(scene_detail) != TYPE_STRING or scene_detail not in SCENE_DETAILS:
		errors.append("scene_detail must be auto, low, medium, high or extreme")
	var birds: Variant = raw.get("birds", DEFAULTS.birds)
	if typeof(birds) != TYPE_STRING or birds not in BIRD_LEVELS:
		errors.append("birds must be off, few, normal or many")
	var scale: Variant = raw.get("ui_scale")
	if typeof(scale) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(scale)) \
			or float(scale) < 1.0 or float(scale) > 2.0 \
			or not is_equal_approx((float(scale) - 1.0) * 20.0, round((float(scale) - 1.0) * 20.0)):
		errors.append("ui_scale must be a 5% increment from 1.0 through 2.0")
	for key: String in ["opaque_panels", "reduced_motion"]:
		if typeof(raw.get(key)) != TYPE_BOOL:
			errors.append("%s must be a boolean" % key)
	for key: String in AUDIO_LEVEL_KEYS:
		var level: Variant = raw.get(key, DEFAULTS[key])
		if typeof(level) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(level)) \
				or float(level) < 0.0 or float(level) > 1.0:
			errors.append("%s must be finite and between 0 and 1" % key)
	if not errors.is_empty():
		return {"ok": false, "config": {}, "errors": errors}
	var normalized := {
		"window_mode": raw.window_mode,
		"window_resolution": resolution,
		"max_fps": max_fps,
		"vsync_mode": vsync_mode,
		"msaa_3d": msaa_3d,
		"scene_detail": scene_detail,
		"birds": birds,
		"ui_scale": float(raw.ui_scale),
		"opaque_panels": raw.opaque_panels,
		"reduced_motion": raw.reduced_motion,
		"menu_volume": float(raw.get("menu_volume", DEFAULTS.menu_volume)),
		"master_volume": float(raw.get("master_volume", DEFAULTS.master_volume)),
	}
	return {"ok": true, "config": normalized, "errors": errors}


static func _preserve_bad_file(file_path: String, result: Dictionary, reason: String) -> Dictionary:
	var backup := file_path + ".bad"
	var absolute_path := ProjectSettings.globalize_path(file_path)
	var absolute_backup := ProjectSettings.globalize_path(backup)
	DirAccess.remove_absolute(absolute_backup)
	var err := DirAccess.rename_absolute(absolute_path, absolute_backup)
	result.note = "%s; %s" % [reason, "kept as " + backup.get_file() if err == OK else "could not keep a copy (error %d)" % err]
	return result


static func _append_note(existing: String, addition: String) -> String:
	return addition if existing.is_empty() else existing + "; " + addition


static func _config_only(loaded: Dictionary) -> Dictionary:
	var config_only := {}
	for key: String in DEFAULTS:
		config_only[key] = loaded.get(key, DEFAULTS[key])
	return config_only
