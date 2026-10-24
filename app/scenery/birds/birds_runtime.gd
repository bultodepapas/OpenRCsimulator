## SC-BIRD-08: the Birds node's only per-frame work. While a bird is arriving or leaving it checks the shader clock and
## settles finished transitions (arrived → flying, gone → not drawn), so a transition never replays when sim_clock wraps
## at 1024 s. When the clock has never moved since the scene was built (Home's still picture), pending transitions
## settle at once. Presentation only: it reads ShaderClock.last_clock and writes the birds' own MultiMesh buffers.
extends Node3D

const ShaderClock = preload("res://render/shader_clock.gd")
const STILL_FRAMES := 30

var _birds: Script = null
var _first_clock := NAN
var _clock_moved := false
var _still := 0


func _ready() -> void:
	_birds = load("res://scenery/birds.gd") # not preloaded: birds.gd preloads this script


func _process(_delta: float) -> void:
	var clock: float = ShaderClock.last_clock
	if is_nan(_first_clock):
		_first_clock = clock
	_clock_moved = _clock_moved or clock != _first_clock
	if _birds == null or not _birds.pending(self):
		_still = 0
		return
	if _clock_moved:
		_birds.settle(self, clock)
		return
	_still += 1
	if _still >= STILL_FRAMES:
		_birds.settle(self, clock, true)
