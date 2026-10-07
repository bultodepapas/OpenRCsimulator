# Real SceneTree scheduler: run at --fixed-fps 30/60/144 and compare every physics-boundary hash.
extends SceneTree
const Flight = preload("res://sim/flight_session.gd")
const Fixture = preload("res://tests/test_wash_transport.gd")
var flight: Node
var digest: HashingContext = HashingContext.new()
var frames: int = 0

func _initialize() -> void:
	call_deferred("begin")

func begin() -> void:
	flight = Flight.new()
	if not Fixture.configure(flight):
		quit(1)
		return
	root.add_child(flight)
	flight.sim.stop_at_tick = 480
	digest.start(HashingContext.HASH_SHA256)
	flight.sim.stepped.connect(sample)
	flight.sim.faulted.connect(func(reason: String) -> void:
		printerr(reason)
		quit(1))
	# A real transient from the first frame, then a throttle/control pulse at exact physics boundaries.
	flight.sim.continuous = PackedFloat64Array([0, 0, 0])
	flight.sim.reset(flight.sim.state)

func _process(_dt: float) -> bool:
	frames += 1
	if frames > 2000:
		printerr("frame driver did not reach 480 ticks")
		quit(1)
	return false

func sample(tick: int, _t: float, state: PackedFloat64Array, loads: PackedFloat64Array,
		inputs: PackedFloat64Array, aux: PackedFloat64Array) -> void:
	digest.update(state.to_byte_array()+flight.sim.continuous.to_byte_array()+loads.to_byte_array()+inputs.to_byte_array()+aux.to_byte_array())
	if tick == 60:
		flight.sim.inputs = PackedFloat64Array([0.1, 0.05, 0.1, 0.8])
	elif tick == 180:
		flight.sim.inputs = PackedFloat64Array([0, 0, 0, 0.2])
	elif tick == 480:
		print("E0b5 frame hash ", digest.finish().hex_encode(), " ticks=", tick, " frames=", frames)
		quit()
