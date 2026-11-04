## RC-TRACK: the "RC car circuit" setting for airplane flights on the club field (Settings > Graphics).
## One decision per flight feeds the rendered circuit, the wheels' terrain and the collision world, so the
## circuit is never visible without its physics or the reverse. Helicopters and the car activity never ask.
## Precedence: --rc_track=<auto|on|off> after --, then OPENRC_RC_TRACK, then the saved preference, which only
## menu-launched (interactive) flights read. Traces, captures and tests stay without it unless asked explicitly.
## Automatic turns it on only for a dedicated GPU (SceneDetail's detection) at High or Extreme scene detail.
extends RefCounted

const SceneDetail := preload("res://render/scene_detail.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")

const AUTO := "auto"
const PREFERENCES: Array[String] = ["auto", "on", "off"]
## display.cfg [graphics] rc_track; app_state/display_preferences.gd mirrors these values.
const DEFAULT := AUTO
const AUTO_REASON := "dedicated GPU"
const AUTO_LEVELS: Array[String] = ["high", "extreme"]

static var _preference := DEFAULT


static func set_preference(value: String) -> void:
	_preference = value if PREFERENCES.has(value) else DEFAULT


static func preference() -> String:
	return _preference


## The explicit command-line or environment request, or "" when there is none (or it is malformed).
static func explicit() -> String:
	var requested := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--rc_track="):
			requested = argument.trim_prefix("--rc_track=").strip_edges().to_lower()
	if requested.is_empty():
		requested = OS.get_environment("OPENRC_RC_TRACK").strip_edges().to_lower()
	return requested if PREFERENCES.has(requested) else ""


## What Automatic picks on this machine, with the reason Settings shows. `detected` is SceneDetail.detected().
static func automatic(detected: Dictionary = {}, detail_level: String = "") -> Dictionary:
	var gpu: Dictionary = detected if not detected.is_empty() else SceneDetail.detected()
	var level: String = detail_level if not detail_level.is_empty() else SceneDetail.level()
	if str(gpu.get("reason", "")) != AUTO_REASON:
		return {enabled = false, reason = str(gpu.get("reason", "unknown GPU"))}
	if not AUTO_LEVELS.has(level):
		return {enabled = false, reason = "Scene detail"}
	return {enabled = true, reason = AUTO_REASON}


## True when this flight shows and simulates the circuit. `interactive` is a menu-launched flight.
static func enabled(interactive: bool) -> bool:
	var requested := explicit()
	if requested.is_empty():
		if not interactive:
			return false
		requested = _preference
	if requested == AUTO:
		return bool(automatic().enabled)
	return requested == "on"


## The validated circuit for this airplane flight, or {} when it is off or the field is not the club's
## authored geometry (custom fields are never changed).
static func resolve(field: Dictionary, interactive: bool) -> Dictionary:
	if not enabled(interactive) or not Track.matches_field(field):
		return {}
	var loaded: Dictionary = Track.load_default()
	if not bool(loaded.get("ok", false)):
		push_warning("RC circuit refused: " + "; ".join(PackedStringArray(loaded.get("errors", []))))
		return {}
	return loaded.track
