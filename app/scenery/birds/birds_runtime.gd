## SC-BIRD-08: the Birds node's only per-frame work (poll()):
## - settles finished arrivals and departures, so a transition never replays when sim_clock wraps at 1024 s; when the
##   clock stands still (Home's fixed picture, a paused flight) for STILL_SECONDS of real time, pending transitions
##   settle at once,
##   so a Settings change shows there and then;
## - follows flowing time: World.flow_to/flow_frame update Atmosphere.state without committing lighting, so when the
##   flow state's sun moves by FLOW_SUN_STEP_DEG the director runs again on that state;
## - follows the weather: when the rendered cloud cover changes by CLOUD_STEP the director runs again;
## - follows Settings → Graphics → Birds: a new preference applies at once (birds fly away or arrive).
## Presentation only: reads ShaderClock, Atmosphere.state and the cloud snapshot; writes the birds' own MultiMeshes.
extends Node3D

const Atmosphere = preload("res://render/atmosphere.gd")
const BirdDirector = preload("res://scenery/birds/bird_director.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const STILL_SECONDS := 0.25
const FLOW_SUN_STEP_DEG := 0.1
const CLOUD_STEP := 0.05
const CLOUD_POLL_FRAMES := 30

var _birds: Script = null
var _last_clock := NAN
var _still := 0.0
var _flow_sun := NAN
var _following_flow := false
var _cloud := NAN
var _frames := 0


func _ready() -> void:
	_birds = load("res://scenery/birds.gd") # not preloaded: birds.gd preloads this script


func _process(delta: float) -> void:
	poll(delta)


## One frame's work (delta = real seconds since the last frame); returns true when the birds changed. Public so tests
## can drive it without a frame loop.
func poll(delta: float = 1.0 / 60.0) -> bool:
	if _birds == null:
		_birds = load("res://scenery/birds.gd")
	var changed := false
	var clock: float = ShaderClock.last_clock
	_still = _still + delta if clock == _last_clock else 0.0
	_last_clock = clock
	if not Atmosphere.state.is_empty() and Atmosphere.state.has("sun_elevation_deg"):
		var sun := float(Atmosphere.state.sun_elevation_deg)
		if is_nan(_flow_sun):
			_flow_sun = sun
		elif absf(sun - _flow_sun) >= FLOW_SUN_STEP_DEG:
			_flow_sun = sun
			_following_flow = true
			_birds.apply_lighting(self, {})
			changed = true
	if int(get_meta("preference_serial", -1)) != BirdDirector.preference_serial: # apply_lighting records it
		_birds.apply_lighting(self, {} if _following_flow else get_meta("lighting", {}))
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
		return changed
	return _birds.settle(self, clock, _still >= STILL_SECONDS) or changed
