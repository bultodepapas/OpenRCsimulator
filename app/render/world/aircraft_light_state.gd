## FW-35c: flight-local light selection. Presentation only; no wall clock or physics state.
extends RefCounted

const MODES := ["auto", "all", "nav", "off"]
const EVENING_ON_SECONDS := 17 * 3600 + 30 * 60

var selection: String = "auto"
var active_mode: String = "off"
var gain: float = 0.0
var evening_on_seconds: int = EVENING_ON_SECONDS
var _local_seconds: float = NAN
var _daytime_gain: float = 0.0


## Invalid configuration leaves the accepted threshold intact.
func configure_evening(seconds: int) -> bool:
	if seconds < 0 or seconds >= 86400:
		return false
	evening_on_seconds = seconds
	_resolve()
	return true


## AUTO resumes the default; ALL/NAV/OFF are explicit overrides until reset().
func set_mode(mode: String) -> bool:
	if mode not in MODES:
		return false
	selection = mode
	_resolve()
	return true


## Fixed-wing keeps ALL/NAV/OFF; rotorcraft also offers its existing AUTO detent.
func cycle_mode(include_auto: bool = false) -> String:
	var modes: Array = MODES if include_auto else ["all", "nav", "off"]
	var current := selection if selection != "auto" or include_auto else active_mode
	set_mode(modes[(modes.find(current) + 1) % modes.size()])
	return selection


func reset() -> void:
	set_mode("auto")


## The adapter supplies its established solar/daytime gain. Civil evening only adds ON.
## Returns true only when rendered output changes, so repeated samples need no node writes.
func update(local_seconds: float, daytime_gain: float) -> bool:
	_local_seconds = local_seconds
	_daytime_gain = clampf(daytime_gain, 0.0, 1.0) if is_finite(daytime_gain) else 0.0
	return _resolve()


func _resolve() -> bool:
	var next_gain := 1.0
	var next_mode := selection
	if selection == "auto":
		var evening := is_finite(_local_seconds) and fposmod(_local_seconds, 86400.0) >= evening_on_seconds
		next_gain = 1.0 if evening else _daytime_gain
		next_mode = "all" if next_gain > 0.0 else "off"
	elif selection == "off":
		next_gain = 0.0
	var changed := active_mode != next_mode or gain != next_gain
	active_mode = next_mode
	gain = next_gain
	return changed
