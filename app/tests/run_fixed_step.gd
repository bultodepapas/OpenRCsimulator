# C5/D5.9 helper (not a test by itself): fly the REAL app (main scene, trimmed start, keyboard → commands path)
# with key presses injected at exact physics ticks, then print a hash of the state at tick 480.
# test.sh runs it at --fixed-fps 30, 60 and 144 and requires identical hashes: the flight depends only on the
# per-tick input samples, never on the rendering frame rate.
extends SceneTree

const TICKS := 480 # 2 s at 240 Hz
## Simulation tick → [[key, pressed], …], injected in the frame that ends exactly on that tick, seen from the next
## tick on. Frames end on global ticks 40k at 30, 60 and 144 fps alike; the simulation starts one tick late (the
## scene becomes ready after the first physics tick), so those are simulation ticks 40k − 1. Misalignment fails loudly.
const SCHEDULE := {
	119: [[KEY_RIGHT, true], [KEY_W, true]],
	239: [[KEY_RIGHT, false], [KEY_W, false], [KEY_DOWN, true]],
	359: [[KEY_DOWN, false], [KEY_A, true]],
}

var _main: Node
var _frames := 0
var _done := {}


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main) # ready (and session created) by the first frame


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _process(_delta: float) -> bool:
	_frames += 1
	var sim: Node = _main.session.sim
	sim.stop_at_tick = TICKS
	for tick in SCHEDULE:
		if _done.has(tick) or sim.tick < tick:
			continue
		if sim.tick != tick:
			printerr("ERROR: a frame ended at tick %d, past the scheduled tick %d (schedule not frame-aligned)" % [sim.tick, tick])
			quit(1)
			return true
		_done[tick] = true
		for k in SCHEDULE[tick]:
			_key(k[0], k[1])
	if sim.tick < TICKS:
		return false
	var throttle: float = _main.session.commands.throttle
	if throttle <= _main.session.start.throttle:
		printerr("ERROR: the injected keys had no effect (throttle %.4f)" % throttle)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(sim.state.to_byte_array())
	var full_hash := HashingContext.new()
	full_hash.start(HashingContext.HASH_SHA256)
	full_hash.update(var_to_bytes(_main.session.checkpoint()))
	print("flight_sha256=%s" % full_hash.finish().hex_encode())
	print("ticks=%d frames=%d throttle=%.4f state_sha256=%s" % [sim.tick, _frames, throttle, hash.finish().hex_encode()])
	return true # quit
