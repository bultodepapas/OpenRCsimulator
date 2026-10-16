# UI-24: display and accessibility preferences use their own versioned file so settings.cfg's
# flight/profile contents and controller calibration remain untouched.
extends RefCounted

const DEFAULT_PATH := "user://display.cfg"
const SCHEMA := 1
const WINDOW_MODES: Array[String] = ["windowed", "borderless"]
const DEFAULTS := {
	"window_mode": "windowed",
	"ui_scale": 1.0,
	"opaque_panels": false,
	"reduced_motion": false,
	"menu_volume": 0.35,
}

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
	raw.ui_scale = cfg.get_value("display", "ui_scale", DEFAULTS.ui_scale)
	raw.opaque_panels = cfg.get_value("accessibility", "opaque_panels", DEFAULTS.opaque_panels)
	raw.reduced_motion = cfg.get_value("accessibility", "reduced_motion", DEFAULTS.reduced_motion)
	raw.menu_volume = cfg.get_value("audio", "menu_volume", DEFAULTS.menu_volume)
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
	cfg.set_value("display", "ui_scale", checked.config.ui_scale)
	cfg.set_value("accessibility", "opaque_panels", checked.config.opaque_panels)
	cfg.set_value("accessibility", "reduced_motion", checked.config.reduced_motion)
	cfg.set_value("audio", "menu_volume", checked.config.menu_volume)
	return cfg.save(file_path)


## UI scale accepts any 5% increment from 100% through 200%.
static func validate(raw: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if not raw is Dictionary:
		return {"ok": false, "config": {}, "errors": PackedStringArray(["display settings must be a dictionary"])}
	for key: String in DEFAULTS:
		if not raw.has(key) and key != "menu_volume": # optional schema-1 extension; older files/callers retain defaults
			errors.append("missing %s" % key)
	if typeof(raw.get("window_mode")) != TYPE_STRING or raw.get("window_mode") not in WINDOW_MODES:
		errors.append("window_mode must be windowed or borderless")
	var scale: Variant = raw.get("ui_scale")
	if typeof(scale) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(scale)) \
			or float(scale) < 1.0 or float(scale) > 2.0 \
			or not is_equal_approx((float(scale) - 1.0) * 20.0, round((float(scale) - 1.0) * 20.0)):
		errors.append("ui_scale must be a 5% increment from 1.0 through 2.0")
	for key: String in ["opaque_panels", "reduced_motion"]:
		if typeof(raw.get(key)) != TYPE_BOOL:
			errors.append("%s must be a boolean" % key)
	var volume: Variant = raw.get("menu_volume", DEFAULTS.menu_volume)
	if typeof(volume) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(volume)) \
			or float(volume) < 0.0 or float(volume) > 1.0:
		errors.append("menu_volume must be finite and between 0 and 1")
	if not errors.is_empty():
		return {"ok": false, "config": {}, "errors": errors}
	var normalized := {
		"window_mode": raw.window_mode,
		"ui_scale": float(raw.ui_scale),
		"opaque_panels": raw.opaque_panels,
		"reduced_motion": raw.reduced_motion,
		"menu_volume": float(volume),
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
