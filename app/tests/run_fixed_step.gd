# C5 helper (not a test by itself): run a scripted 2 s flight through the real physics tick and print
# a hash of the final state. test.sh runs it at several --fixed-fps values and compares the hashes.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")

const TICKS := 480 # 2 s at 240 Hz

var _sim: Node
var _frames := 0


func _initialize() -> void:
	_sim = Sim.new()
	_sim.mass = 2.7
	_sim.inertia = PackedFloat64Array([0.25, 0.3, 0.5, 0.0, 0.02, 0.0])
	# Scripted "pilot": thrust, plus a roll-moment pulse between 0.5 s and 1.0 s.
	_sim.loads = func(_s: PackedFloat64Array, t: float) -> PackedFloat64Array:
		var roll := 0.3 if t >= 0.5 and t < 1.0 else 0.0
		return PackedFloat64Array([8.0, 0.0, -20.0, roll, 0.05, 0.0])
	_sim.stop_at_tick = TICKS
	root.add_child(_sim)
	_sim.reset(RB.make_state(M.v3(0, 0, -20), M.v3(15, 0, 0), M.q_identity(), M.v3(0, 0, 0)))


func _process(_delta: float) -> bool:
	_frames += 1
	if _sim.tick >= TICKS:
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(_sim.state.to_byte_array())
		print("ticks=%d frames=%d state_sha256=%s" % [_sim.tick, _frames, hash.finish().hex_encode()])
		return true # quit
	return false
