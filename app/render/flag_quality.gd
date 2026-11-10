## L15c-F07: presentation-only flag animation quality. The command-line and
## environment override is read once; callers refresh profile() when settings
## or the resolved scene detail change, never from the simulation kernel.
extends RefCounted

const SceneDetail := preload("res://render/scene_detail.gd")
const AUTO := "auto"
const PREFERENCES: Array[String] = [AUTO, "static", "basic", "detailed"]
const ARGUMENT_PREFIX := "--flag_animation="
const ENVIRONMENT_KEY := "OPENRC_FLAG_ANIMATION"

static var _preference := AUTO
static var _override_loaded := false
static var _override := {}
static var _warned := {}
## Incremented on a saved/preview preference change; consumers can refresh a live flag.
static var revision := 0


## The override remains in force when the player changes the saved preference.
static func set_preference(value: String) -> void:
	var normalized := _validated(value)
	if normalized != _preference:
		_preference = normalized
		revision += 1


## Testable source selection. A present but unknown override resolves to Auto,
## instead of silently exposing a lower-priority setting.
static func resolve_preference(arguments: PackedStringArray, environment: String, saved: String) -> String:
	var selected := _select_override(arguments, environment)
	return _validated(str(selected.value) if selected.present else saved)


static func _select_override(arguments: PackedStringArray, environment: String) -> Dictionary:
	var selected := {present = false, value = ""}
	for argument: String in arguments:
		if argument.begins_with(ARGUMENT_PREFIX):
			selected = {present = true, value = argument.trim_prefix(ARGUMENT_PREFIX)}
	if not selected.present and not environment.strip_edges().is_empty():
		selected = {present = true, value = environment}
	return selected


static func _validated(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	if PREFERENCES.has(normalized):
		return normalized
	if not _warned.has(normalized):
		_warned[normalized] = true
		push_warning("Unknown flag animation '%s'; using auto" % value)
	return AUTO


static func _requested() -> String:
	if not _override_loaded:
		_override = _select_override(OS.get_cmdline_user_args(), OS.get_environment(ENVIRONMENT_KEY))
		_override_loaded = true
	return _validated(str(_override.value)) if _override.present else _preference


## detail_level is a resolved SceneDetail level. Omitting it uses the current one.
static func level(detail_level: String = "") -> String:
	var requested := _requested()
	if requested != AUTO:
		return requested
	var detail := detail_level if SceneDetail.LEVELS.has(detail_level) else SceneDetail.level()
	return "basic" if detail == "low" else "detailed"


## Grid dimensions are cells, not vertices; return fresh data for each consumer.
static func profile(detail_level: String = "") -> Dictionary:
	var detail := detail_level if SceneDetail.LEVELS.has(detail_level) else SceneDetail.level()
	var mode := level(detail)
	if mode != "detailed":
		return {mode = mode, grid_x = 8, grid_y = 4, material_tier = "low"}
	if detail in ["high", "extreme"]:
		return {mode = mode, grid_x = 32, grid_y = 16, material_tier = "high"}
	return {mode = mode, grid_x = 16, grid_y = 8, material_tier = "medium"}


## Tests can supply an isolated command-line/environment snapshot without touching OS args.
static func _set_override_for_tests(arguments: PackedStringArray, environment: String) -> void:
	_override = _select_override(arguments, environment)
	_override_loaded = true


static func _reset_override_for_tests() -> void:
	_override = {}
	_override_loaded = false
