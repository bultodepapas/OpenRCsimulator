extends SceneTree
## Wheel presentation far above the ground (render/ground_gear.gd): the per-frame terrain/lake/track compression
## queries are skipped only where the ground-audio no-touch bound holds, and the axles then sit exactly where the
## full compression formula would place them (at rest). On the ground the full formula still moves them.

const Session := preload("res://sim/flight_session.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const GroundGear := preload("res://render/ground_gear.gd")
const GroundAudioModel := preload("res://audio/ground_audio_model.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var session := Session.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	var airplane: Dictionary = AirplaneBuilder.build(AirplaneBuilder.STIK_ID)
	root.add_child(airplane.root)
	var observer: Node = GroundGear.attach(airplane, session)
	var keys: Array = []
	for key: String in ["left", "right", "nose", "tail"]:
		if airplane.gear.has(key):
			keys.append(key)
	_check("the Stik exposes wheel pivots", keys.size() >= 3, str(keys))
	var rest := {}
	for key: String in keys:
		rest[key] = airplane.gear[key].position
	for height: float in [200.0, 0.245, 0.20]:
		session.sim.state = RB.make_state(M.v3(0, 0, -height), M.v3(0, 0, 0), M.q_identity(), M.v3(0, 0, 0))
		session.sim.previous = session.sim.state.duplicate()
		var clear: bool = GroundAudioModel.wheels_clear_of_ground(session)
		var full: PackedFloat64Array = session.gear_compressions(session.sim.state)
		observer._process(0.0)
		var label := "at %.3f m" % height
		var matches := true
		var touching := false
		var contacts: Array = session.current_landing_gear().contacts
		for index: int in contacts.size():
			var key := str(contacts[index].name).trim_prefix("main_")
			if not airplane.gear.has(key):
				continue
			var wheel: Node3D = airplane.gear[key]
			var up_local: Vector3 = wheel.get_parent().global_basis.inverse() * Vector3.UP
			var expected: Vector3 = rest[key] + up_local * maxf(0.0, full[index])
			matches = matches and wheel.position.is_equal_approx(expected)
			touching = touching or full[index] > 0.0
		_check(label + " the axles sit where the full compression formula puts them", matches)
		if height > 100.0:
			_check(label + " the no-touch bound skips the terrain queries", clear and not touching)
		else:
			_check(label + " on the ground the bound does not hold and a wheel is compressed", not clear and touching)
	airplane.root.queue_free()
	session.queue_free()
	await process_frame
	print("ground gear clearance: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1
