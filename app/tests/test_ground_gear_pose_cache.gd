extends SceneTree
## F1: GroundGearMotion re-poses a retraction rig only when the extension or rig changes, restoring the few nodes it
## rewrites afterwards. Every rig, wheel and compression node must match calling Retraction.apply every frame through
## spin, steering, ground compression, retraction travel and gear cycles, including the Corsair's quarter-turned
## retracted wheels, and must not drift over a long constant-extension stretch. The restored nodes go through the same
## setters with the same values as Retraction.apply, so every pose must be bit-identical.

const Session := preload("res://sim/flight_session.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const GroundGear := preload("res://render/ground_gear.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const TOLERANCE := 0.0 # bit-identical: same setters, same values
const CASES := [
	["sebart-avanti-s-a200-p100rx", "res://data/aircraft/sebart_avanti_s_a200.json"],
	["f4u-corsair-250", "res://data/aircraft/f4u_corsair_250.json"],
]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for case: Array in CASES:
		await _case(str(case[0]), str(case[1]))
	print("ground gear pose cache: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _case(id: String, path: String) -> void:
	var session := Session.new()
	session.setup(path)
	root.add_child(session)
	session.input_enabled = false
	_check(id + " is retractable", session.gear_is_retractable())
	var cached: Dictionary = AirplaneBuilder.build(id)
	var reference: Dictionary = AirplaneBuilder.build(id)
	root.add_child(cached.root)
	root.add_child(reference.root)
	var cached_observer: Node = GroundGear.attach(cached, session)
	var reference_observer: Node = GroundGear.attach(reference, session)
	_check(id + " has a sampled retraction rig", not cached.get("gear_retraction", {}).is_empty())
	var index: int = session.gear_aux_index()
	var extensions := [1.0, 1.0, 1.0, 0.75, 0.75, 0.4, 0.4, 0.4, 0.0, 0.0, 0.0, 0.0, 0.3, 1.0, 1.0]
	var heights := [0.18, 0.2, 0.25, 0.3, 200.0, 200.0, 200.0, 200.0, 200.0, 200.0, 200.0, 200.0, 200.0, 0.2, 0.19]
	var exact := true
	var skipped := 0
	for frame: int in extensions.size():
		session.sim.state = RB.make_state(M.v3(0, 0, -float(heights[frame])), M.v3(0, 0, 0), M.q_identity(), M.v3(0, 0, 0))
		session.sim.previous = session.sim.state.duplicate()
		session.sim.aux[index] = float(extensions[frame])
		session.sim.aux[index + 1] = 1.0 if float(extensions[frame]) >= 0.5 else 0.0
		session.sim.aux[session.AUX_SERVO + 2] = sin(float(frame) * 0.7)
		for observer: Node in [cached_observer, reference_observer]:
			for key: Variant in observer._angles.keys():
				observer._angles[key] = float(frame) * 0.37 + 0.1
		var before_apply: float = cached_observer._applied_extension
		cached_observer._process(1.0 / 60.0)
		reference_observer._applied_extension = NAN # forces Retraction.apply every frame: the original behaviour
		reference_observer._process(1.0 / 60.0)
		if before_apply == float(extensions[frame]):
			skipped += 1
		exact = exact and _largest_difference(cached, reference) <= TOLERANCE
	_check(id + " frames without a new pose skip Retraction.apply", skipped >= 9, str(skipped))
	_check(id + " every rig, wheel and compression node matches per-frame posing", exact)
	# A long constant stretch with spinning wheels and moving steering: the restored pose must not drift.
	var worst := 0.0
	for extension: float in [0.0, 1.0]:
		for frame: int in 600:
			session.sim.aux[index] = extension
			session.sim.aux[index + 1] = extension
			session.sim.aux[session.AUX_SERVO + 2] = sin(float(frame) * 0.05)
			for observer: Node in [cached_observer, reference_observer]:
				for key: Variant in observer._angles.keys():
					observer._angles[key] = fmod(float(frame) * 0.61, TAU)
			cached_observer._process(1.0 / 240.0)
			reference_observer._applied_extension = NAN
			reference_observer._process(1.0 / 240.0)
		worst = maxf(worst, _largest_difference(cached, reference))
	_check(id + " no drift after 600 frames at each end of travel", worst <= TOLERANCE, str(worst))
	var replaced: Dictionary = cached.gear_retraction.duplicate()
	cached.gear_retraction = replaced
	cached_observer._process(1.0 / 60.0)
	_check(id + " a replaced rig is posed again", is_same(cached_observer._applied_rig, replaced))
	cached.root.queue_free()
	reference.root.queue_free()
	session.queue_free()
	await process_frame


func _largest_difference(a: Dictionary, b: Dictionary) -> float:
	var pairs: Array = []
	var rig_a: Dictionary = a.gear_retraction
	var rig_b: Dictionary = b.gear_retraction
	for name: Variant in rig_a.nodes.keys():
		pairs.append([(rig_a.nodes[name] as Node3D).transform, (rig_b.nodes[name] as Node3D).transform])
	for key: Variant in a.get("gear", {}).keys():
		pairs.append([(a.gear[key] as Node3D).transform, (b.gear[key] as Node3D).transform])
	for role: Variant in rig_a.compression.keys():
		pairs.append([(rig_a.compression[role] as Node3D).transform, (rig_b.compression[role] as Node3D).transform])
		pairs.append([rig_a.rest[role], rig_b.rest[role]])
	var worst := 0.0
	for pair: Array in pairs:
		var x: Transform3D = pair[0]
		var y: Transform3D = pair[1]
		for column: int in 3:
			worst = maxf(worst, (x.basis[column] - y.basis[column]).abs().max_axis_index() * 0.0 + (x.basis[column] - y.basis[column]).length())
		worst = maxf(worst, (x.origin - y.origin).length())
	return worst


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1
