## RC-TRACK: the "RC car circuit" setting for airplane and FPV quad flights on the club field (Settings > Graphics).
## One decision per flight feeds the rendered circuit, the wheels' terrain and the collision world, so the
## circuit is never visible without its physics or the reverse (the quad: its terrain and obstacle inventory too).
## Helicopters and the car activity never ask. The quad's command-line route takes no extra arguments: use
## OPENRC_RC_TRACK there.
## Precedence: --rc_track=<auto|on|off> after --, then OPENRC_RC_TRACK, then the saved preference, which only
## menu-launched (interactive) flights read. Traces, captures and tests stay without it unless asked explicitly.
## Automatic selects the same circuit-free scenario on all hardware and detail levels.
extends RefCounted

const Track := preload("res://physics/ground_vehicle/airfield_track.gd")

const AUTO := "auto"
const PREFERENCES: Array[String] = ["auto", "on", "off"]
## display.cfg [graphics] rc_track; app_state/display_preferences.gd mirrors these values.
const DEFAULT := AUTO
const AUTO_REASON := "default scenario"

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


## Automatic is a scenario default, never a graphics or hardware decision. The parameters
## remain accepted for callers displaying a draft and for compatibility with older tools.
static func automatic(_detected: Dictionary = {}, _detail_level: String = "") -> Dictionary:
	return {enabled = false, reason = AUTO_REASON}

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
