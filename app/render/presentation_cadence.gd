## VQ-01c-R1: once-per-frame cadence for a read-only presentation observer on Simulation.stepped.
## The stepped handler calls on_tick(); the owner's _process calls take() once per rendered frame and,
## when it returns true, observes the current accepted endpoint (the last tick before that frame).
## A reset (tick 0), rewind, restore or other tick gap runs at once, so discontinuities keep their
## per-tick handling; only consecutive ticks wait. every_frames 0 restores per-tick observation.
## Precedence: --presentation-cadence=<0..4> after --, then OPENRC_PRESENTATION_CADENCE, then the default.
## Presentation only: simulation, recorders, flight logs and statistics never read it.
extends RefCounted

const DEFAULT_EVERY_FRAMES := 1
const MAX_EVERY_FRAMES := 4
## Longest deferral. It bounds added audio latency at a slow frame rate, keeps windsock and
## field-people motion inside their 0.5 s catch-up gap, and stays below ground audio's 0.14 s
## minimum airborne time, so a grounded wheel cannot complete an unseen hop and cue.
const MAX_INTERVAL_S := 0.1
const ARGUMENT := "--presentation-cadence="
const ENVIRONMENT_KEY := "OPENRC_PRESENTATION_CADENCE"

## Test and tool seam: >= 0 replaces the command line and environment for gates built afterwards.
static var override_every_frames := -1

## 0 = every accepted tick (historical behaviour); N = once per N rendered frames.
var every_frames := DEFAULT_EVERY_FRAMES
var max_interval_ticks := 24
## Tick of the last observation; the observation before it when every tick between them was seen
## (a continuous interval), else -1; and whether consecutive ticks wait for take().
var last_tick := -1
var since_tick := -1
var pending := false
var _seen_tick := -1
var _frames := 0


func _init(frames: int = -1, tick_rate_hz: float = float(Engine.physics_ticks_per_second)) -> void:
	every_frames = configured_every_frames() if frames < 0 else clampi(frames, 0, MAX_EVERY_FRAMES)
	max_interval_ticks = maxi(1, int(floor(MAX_INTERVAL_S * maxf(tick_rate_hz, 1.0) + 1.0e-9)))


static func configured_every_frames() -> int:
	if override_every_frames >= 0:
		return clampi(override_every_frames, 0, MAX_EVERY_FRAMES)
	var requested := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(ARGUMENT):
			requested = argument.trim_prefix(ARGUMENT).strip_edges()
	if requested.is_empty():
		requested = OS.get_environment(ENVIRONMENT_KEY).strip_edges()
	if requested.is_valid_int() and int(requested) >= 0 and int(requested) <= MAX_EVERY_FRAMES:
		return int(requested)
	if not requested.is_empty():
		push_warning("Unknown presentation cadence '%s'; using %d" % [requested, DEFAULT_EVERY_FRAMES])
	return DEFAULT_EVERY_FRAMES


## From the stepped handler: true when the observer must run at this tick (per-tick mode, a
## discontinuity, the deferral bound or `force`). Otherwise the tick waits for take().
func on_tick(tick: int, force := false) -> bool:
	var continuous := _seen_tick >= 0 and tick == _seen_tick + 1
	_seen_tick = tick
	if force or every_frames <= 0 or not continuous or last_tick < 0 or tick - last_tick >= max_interval_ticks:
		_run(tick, continuous)
		return true
	pending = true
	return false


## Once per rendered frame with the current accepted tick: true when waiting ticks are due now.
func take(tick: int) -> bool:
	_frames += 1
	if not pending or _frames < every_frames:
		return false
	_run(tick, tick == _seen_tick)
	return true


## Before any other observation (priming, a pause notification, a direct call): records `tick` as
## observed. Waiting ticks were seen, so it continues them; an unseen tick starts a new history.
func observe_at(tick: int) -> void:
	if pending or tick != last_tick:
		_run(tick, tick == _seen_tick)


func reset() -> void:
	last_tick = -1
	since_tick = -1
	_seen_tick = -1
	pending = false
	_frames = 0


func _run(tick: int, continuous: bool) -> void:
	since_tick = last_tick if continuous and last_tick >= 0 and tick > last_tick else -1
	last_tick = tick
	_seen_tick = tick
	pending = false
	_frames = 0
