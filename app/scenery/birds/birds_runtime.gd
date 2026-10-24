## SC-BIRD-08: the Birds node's only per-frame work (poll()):
## - settles finished arrivals and departures, so a transition never replays when sim_clock wraps at 1024 s; when the
##   clock has never moved since the scene was built (Home's still picture) pending transitions settle at once;
## - follows flowing time: World.flow_to/flow_frame update Atmosphere.state without committing lighting, so when the
##   flow state's sun moves by FLOW_SUN_STEP_DEG the director runs again on that state;
## - follows the weather: when the rendered cloud cover changes by CLOUD_STEP the director runs again.
## Presentation only: reads ShaderClock, Atmosphere.state and the cloud snapshot; writes the birds' own MultiMeshes.
extends Node3D

const Atmosphere = preload("res://render/atmosphere.gd")
const BirdDirector = preload("res://scenery/birds/bird_director.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const STILL_FRAMES := 30
const FLOW_SUN_STEP_DEG := 0.1
const CLOUD_STEP := 0.05
const CLOUD_POLL_FRAMES := 30

var _birds: Script = null
var _first_clock := NAN
var _clock_moved := false
var _still := 0
var _flow_sun := NAN
var _following_flow := false
var _cloud := NAN
var _frames := 0


func _ready() -> void:
	_birds = load("res://scenery/birds.gd") # not preloaded: birds.gd preloads this script


func _process(_delta: float) -> void:
	poll()


## One frame's work; returns true when the birds changed. Public so tests can drive it without a frame loop.
func poll() -> bool:
	if _birds == null:
		_birds = load("res://scenery/birds.gd")
	var changed := false
	var clock: float = ShaderClock.last_clock
	if is_nan(_first_clock):
		_first_clock = clock
	_clock_moved = _clock_moved or clock != _first_clock
	if not Atmosphere.state.is_empty() and Atmosphere.state.has("sun_elevation_deg"):
		var sun := float(Atmosphere.state.sun_elevation_deg)
		if is_nan(_flow_sun):
			_flow_sun = sun
		elif absf(sun - _flow_sun) >= FLOW_SUN_STEP_DEG:
			_flow_sun = sun
			_following_flow = true
			_birds.apply_lighting(self, {})
			changed = true
	_frames += 1
	if _frames % CLOUD_POLL_FRAMES == 1:
		var cover := BirdDirector.cloud_cover()
		if is_nan(_cloud):
			_cloud = cover
		elif absf(cover - _cloud) >= CLOUD_STEP:
			_cloud = cover
			_birds.apply_lighting(self, {} if _following_flow else get_meta("lighting", {}))
			changed = true
	if not _birds.pending(self):
		_still = 0
		return changed
	if _clock_moved:
		return _birds.settle(self, clock) or changed
	_still += 1
	if _still >= STILL_FRAMES:
		return _birds.settle(self, clock, true) or changed
	return changed
