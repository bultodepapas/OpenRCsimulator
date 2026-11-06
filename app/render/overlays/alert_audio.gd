## HUD-09-R2: presentation-only, non-positional alert earcons.
## Caller supplies the selected visible codes and accepted simulation time. Menus, preview,
## pauses and hidden warnings must call observe with audible=false, or retire_playbacks().
extends Node

signal cue_requested(cue: String, code: String)
signal preview_requested(cue: String)

const Policy := preload("res://render/overlays/alert_policy.gd")
const STREAM_BY_CUE := {
	"danger": preload("res://assets/ui/audio/exit.ogg"),
	"caution": preload("res://assets/ui/audio/reject.ogg"),
	"info": preload("res://assets/ui/audio/navigation.ogg"),
	"cleared": preload("res://assets/ui/audio/accept.ogg"),
}
const GAINS := {"danger": 0.5, "caution": 0.32, "info": 0.23, "cleared": 0.17}
const PITCHES := {"danger": 0.95, "caution": 0.98, "info": 1.02, "cleared": 1.0}
const GLOBAL_GAP_S := 0.9
const URGENT_GAP_S := 0.35
const REARM_QUIET_S := 0.8
const CODE_COOLDOWN_S := 4.0
const MIN_ACTIVE_S := 1.0
const CLEAR_QUIET_S := 0.3

var _player: AudioStreamPlayer
var _clock: Callable
var _configuration := {}
var _enabled := true
var _volume := 0.55
var _clear_enabled := true
var _primed := false
var _previous := PackedStringArray()
var _seen := {}
var _absent_since := {}
var _last_code_cue := {}
var _last_time := -INF
var _last_wall := -INF
var _last_cue_wall := -INF
var _last_cue_rank := -1
var _active_since_wall := -INF
var _active_since_sim := -INF
var _clear_since_wall := -INF
var _clear_eligible := false


## An optional monotonic clock makes timing tests deterministic; production uses wall time.
func _init(clock: Callable = Callable()) -> void:
	_clock = clock
	_player = AudioStreamPlayer.new()
	_player.name = "AlertAudioVoice"
	_player.bus = &"Master"
	_player.max_polyphony = 1
	add_child(_player)


func _ready() -> void:
	set_process(false)


func _exit_tree() -> void:
	retire_playbacks()


func _process(_delta: float) -> void:
	if _is_muted():
		reset()
	elif not _player.playing:
		set_process(false)


## Relevant option changes establish a new silent baseline and stop old tails.
func configure(settings: Dictionary) -> void:
	var next := {
		"warning_sound": _bool_option(settings, "warning_sound", true),
		"warning_volume": _volume_option(settings.get("warning_volume", 0.55)),
		"warning_clear_sound": _bool_option(settings, "warning_clear_sound", true),
		"warning_detail": _bool_option(settings, "warning_detail", true),
		"warning_limit": settings.get("warning_limit", 3),
		"warning_navigation": _bool_option(settings, "warning_navigation", true),
		"warning_energy": _bool_option(settings, "warning_energy", true),
		"warning_status": _bool_option(settings, "warning_status", true),
		"warning_training": _bool_option(settings, "warning_training", false),
		"warnings_visible": _warnings_visible(settings),
	}
	if next == _configuration:
		return
	_configuration = next
	_enabled = bool(next.warning_sound)
	_volume = float(next.warning_volume)
	_clear_enabled = bool(next.warning_clear_sound)
	reset()


## Codes come from AlertPolicy after visibility/category selection. Returns the requested
## cue for deterministic callers; an empty string means silence. No blocked cue is queued.
func observe(codes: PackedStringArray, time_s: float, audible: bool) -> String:
	if not audible or not _configuration.get("warnings_visible", true) or _is_muted() or not is_finite(time_s):
		reset()
		return ""
	var now := _now()
	if not is_finite(now) or (_primed and (time_s < _last_time or now < _last_wall)):
		reset()
		if not is_finite(now): return ""
	var current := _canonical(codes)
	if not _primed:
		_primed = true
		_previous = current
		_last_time = time_s
		_last_wall = now
		for code: String in current: _seen[code] = true
		if not current.is_empty():
			_active_since_wall = now
			_active_since_sim = time_s
		return ""
	_last_time = time_s
	_last_wall = now
	for code: String in _previous:
		if not current.has(code): _absent_since[code] = now
	var chosen := ""
	for code: String in current:
		if _previous.has(code): continue
		var rearmed := not _seen.has(code) or (now - float(_absent_since.get(code, now)) >= REARM_QUIET_S \
				and now - float(_last_code_cue.get(code, -INF)) >= CODE_COOLDOWN_S)
		if chosen.is_empty() and rearmed: chosen = code
		_seen[code] = true
		_absent_since.erase(code)
	if not current.is_empty():
		if _previous.is_empty() and not is_finite(_clear_since_wall):
			_active_since_wall = now
			_active_since_sim = time_s
		_clear_since_wall = -INF
		_clear_eligible = false
	elif not _previous.is_empty():
		_clear_since_wall = now
		_clear_eligible = now - _active_since_wall >= MIN_ACTIVE_S and time_s - _active_since_sim >= MIN_ACTIVE_S
	_previous = current
	if not chosen.is_empty():
		var severity: String = Policy.severity(chosen)
		var rank := _rank(severity)
		var gap := URGENT_GAP_S if severity == "danger" and rank > _last_cue_rank else GLOBAL_GAP_S
		if now - _last_cue_wall >= gap:
			_last_code_cue[chosen] = now
			return _play(severity, chosen, now, rank)
	if current.is_empty() and is_finite(_clear_since_wall) and now - _clear_since_wall >= CLEAR_QUIET_S:
		var should_clear := _clear_enabled and _clear_eligible and now - _last_cue_wall >= GLOBAL_GAP_S
		_clear_since_wall = -INF
		_clear_eligible = false
		_active_since_wall = -INF
		_active_since_sim = -INF
		if should_clear:
			return _play("cleared", "", now, 0)
	return ""


## Reset/reopen/rewind and explicit retirement are silent; no delayed cue survives.
func reset() -> void:
	_player.stop()
	set_process(false)
	_primed = false
	_previous = PackedStringArray()
	_seen.clear()
	_absent_since.clear()
	_last_code_cue.clear()
	_last_time = -INF
	_last_wall = -INF
	_last_cue_wall = -INF
	_last_cue_rank = -1
	_active_since_wall = -INF
	_active_since_sim = -INF
	_clear_since_wall = -INF
	_clear_eligible = false


func retire_playbacks() -> void:
	reset()


## Explicit menu preview; it has its own signal and never changes alert history or cooldowns.
func preview(cue: String) -> bool:
	if not STREAM_BY_CUE.has(cue): return false
	if _is_muted():
		_player.stop()
		return false
	_start_player(cue)
	preview_requested.emit(cue)
	return true


func audio_player() -> AudioStreamPlayer:
	return _player


func _play(cue: String, code: String, now: float, rank: int) -> String:
	_last_cue_wall = now
	_last_cue_rank = rank
	_start_player(cue)
	cue_requested.emit(cue, code)
	return cue


func _start_player(cue: String) -> void:
	_player.stop() # a single voice: a new semantic cue replaces the old tail
	_player.stream = STREAM_BY_CUE[cue]
	_player.pitch_scale = float(PITCHES[cue])
	_player.volume_db = linear_to_db(_volume * float(GAINS[cue]))
	_player.play()
	if is_inside_tree(): set_process(true)


func _is_muted() -> bool:
	if not _enabled or _volume <= 0.0:
		return true
	var master := AudioServer.get_bus_index(&"Master")
	return master >= 0 and (AudioServer.is_bus_mute(master) or AudioServer.get_bus_volume_db(master) <= -80.0)


func _now() -> float:
	if _clock.is_valid(): return float(_clock.call())
	return float(Time.get_ticks_usec()) / 1000000.0


static func _canonical(codes: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for code: String in Policy.ORDER:
		if codes.has(code): out.append(code)
	return out


static func _rank(severity: String) -> int:
	match severity:
		"danger": return 3
		"caution": return 2
		"info": return 1
	return 0


static func _bool_option(settings: Dictionary, key: String, fallback: bool) -> bool:
	var value: Variant = settings.get(key, fallback)
	return value if typeof(value) == TYPE_BOOL else fallback


static func _volume_option(value: Variant) -> float:
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)):
		return 0.55
	return clampf(float(value), 0.0, 1.0)


static func _warnings_visible(settings: Dictionary) -> bool:
	var shown: Variant = settings.get("visible")
	if typeof(shown) == TYPE_ARRAY or typeof(shown) == TYPE_PACKED_STRING_ARRAY:
		return "warnings" in shown
	return true
